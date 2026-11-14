--!strict
--[[
	Catalogue des couvre-chefs (emplacement « Head ») : 25 modèles originaux construits par code
	(chapeaux, casques, masques, couronnes et farces) avec les primitives de Cosmetics/Build.
	Aucun asset : géométrie, maillage intégré « Sphere » (SpecialMesh sans fichier), visages dessinés
	en SurfaceGui (Build.face) et, pour trois pièces, particules aux textures intégrées du moteur.

	REPÈRE DE MODÉLISATION
	  Le Handle (invisible) est placé au CENTRE de la tête R15 ; son attachement est décalé au point R15
	  visé : HatAttachment / HairAttachment au sommet (0, 0.6, 0), FaceFrontAttachment devant (0, 0, -0.6).
	  Toutes les pièces se placent donc dans le repère de la tête : +Y en haut, -Z vers le visage,
	  +X à droite du personnage. Tête par défaut ≈ cylindre de rayon 0.6, sommet à y = 0.6,
	  yeux vers y ≈ 0.15, haut du torse vers y ≈ -0.5.

	CONTRAT (Cosmetics/init.luau)
	  id "head_*" stable ; nameKey "cos.<id>" ; descKey "cos.<id>.desc" ; variantes de couleurs nommées
	  "cos.heads.var.<thème>" ; build(variant) -> Accessory (Handle + pièces soudées) toujours passé par
	  Build.finalize. Textes : Locale/fr/CosmeticsHeads.luau et Locale/en/CosmeticsHeads.luau.
	  Étiquettes (filtres de boutique) : hat, helmet, mask, crown, headband, silly, golf, food, animal,
	  fx (particules) et biome évoqué : coast, forest, desert, snow, city.
	  Attributs posés sur l'Accessory : CosmeticId, CosmeticSlot ("Head"), CosmeticVariant.

	ÉQUITÉ
	  build() est pur : aucun parent dans le DataModel, aucune connexion, aucun script. Toute pièce est
	  Massless, sans collision, sans requête et sans contact (Build.finalize). Les particules sont
	  purement visuelles, à faible débit, et portent l'attribut CosmeticFx = true pour que le client
	  puisse les couper en mode « effets réduits ».

	Prix en pièces : Common ≈ 200, Rare ≈ 500, Epic ≈ 1000, Legendary ≈ 2000 (±20 %). Trois pièces se
	débloquent par un défi (ach_tutorial, ach_eagle, ach_hole_in_one). Aucun objet « Default » : sans
	couvre-chef, la tête reste simplement nue.
]]

local Cosmetics = require(script.Parent.Parent)
local Build = require(script.Parent.Parent.Build)

type CosmeticDef = Cosmetics.CosmeticDef
type Rarity = Cosmetics.Rarity
type Unlock = Cosmetics.Unlock
type Variant = Cosmetics.Variant
type FaceShape = Build.FaceShape

-- Couleur n° index de la variante choisie (repli sur la première couleur).
type Paint = (index: number) -> Color3
type AttachmentName = "HatAttachment" | "HairAttachment" | "FaceFrontAttachment"

type Entry = {
	id: string,
	attachment: AttachmentName,
	rarity: Rarity,
	price: number,
	unlock: Unlock,
	tags: { string },
	variants: { Variant },
	-- Ajoute les pièces autour du Handle `h` (repère de la tête) avec la palette `c`.
	model: (h: BasePart, c: Paint) -> (),
}

type FxOptions = {
	texture: string,
	color: Color3,
	rate: number,
	lifetime: NumberRange,
	speed: NumberRange,
	size: NumberSequence,
	transparency: NumberSequence,
	lightEmission: number,
	direction: Enum.NormalId?,
	spread: Vector2?,
	acceleration: Vector3?,
}

--------------------------------------------------------------------------------
-- Constantes
--------------------------------------------------------------------------------

local HANDLE_SIZE = Vector3.new(0.4, 0.4, 0.4)

local ATTACH_POINTS: { [AttachmentName]: Vector3 } = {
	HatAttachment = Vector3.new(0, 0.6, 0),
	HairAttachment = Vector3.new(0, 0.6, 0),
	FaceFrontAttachment = Vector3.new(0, 0, -0.6),
}

local ACCESSORY_TYPES: { [AttachmentName]: Enum.AccessoryType } = {
	HatAttachment = Enum.AccessoryType.Hat,
	HairAttachment = Enum.AccessoryType.Hair,
	FaceFrontAttachment = Enum.AccessoryType.Face,
}

-- Textures de particules intégrées au moteur (aucun AssetId).
local TEX_SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SQUARE = "rbxasset://textures/particles/SquareParticle.png"

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = rgb(248, 248, 244)
local BLACK = rgb(24, 24, 28)
local DARK = rgb(38, 32, 44)
local SOIL = rgb(92, 62, 40)
local BLUSH = rgb(255, 150, 170)
local FALLBACK = rgb(200, 200, 200)

local UP = Build.UP -- couche l'axe X (axe des cylindres Roblox) sur l'axe Y

local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass
local FABRIC = Enum.Material.Fabric

--------------------------------------------------------------------------------
-- Outils de placement (repère de la tête, Handle à l'origine)
--------------------------------------------------------------------------------

local function v3(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- Rotation en degrés autour de X, Y, Z (même convention que CFrame.Angles).
local function rot(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

local function block(h: BasePart, size: Vector3, color: Color3, cf: CFrame, material: Enum.Material?): BasePart
	return Build.attach(h, Build.block(size, color, material), cf)
end

local function ball(h: BasePart, diameter: number, color: Color3, cf: CFrame, material: Enum.Material?): BasePart
	return Build.attach(h, Build.ball(diameter, color, material), cf)
end

-- Ellipsoïde : bloc habillé du maillage intégré « Sphere » (aucun fichier), épouse la taille du bloc.
local function blob(h: BasePart, size: Vector3, color: Color3, cf: CFrame, material: Enum.Material?): BasePart
	local part = Build.block(size, color, material)
	part.Name = "Galbe"
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return Build.attach(h, part, cf)
end

-- Cylindre debout (axe vertical local de `cf`).
local function column(h: BasePart, height: number, diameter: number, color: Color3, cf: CFrame, material: Enum.Material?): BasePart
	return Build.attach(h, Build.cylinder(height, diameter, color, material), cf * UP)
end

-- Cylindre couché le long de l'axe X local de `cf`.
local function tube(h: BasePart, length: number, diameter: number, color: Color3, cf: CFrame, material: Enum.Material?): BasePart
	return Build.attach(h, Build.cylinder(length, diameter, color, material), cf)
end

-- Repère centré entre a et b dont l'axe X va de a vers b (et longueur du segment).
local function span(a: Vector3, b: Vector3): (CFrame, number)
	local delta = b - a
	local up = if math.abs(delta.Unit.Y) > 0.99 then Vector3.zAxis else Vector3.yAxis
	return CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.rad(90), 0), delta.Magnitude
end

-- Cylindre tendu entre deux points.
local function rod(h: BasePart, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local cf, length = span(a, b)
	return tube(h, length, diameter, color, cf, material)
end

-- Barre plate (épaisseur dans le plan vertical, profondeur selon Z) tendue entre deux points.
local function bar(h: BasePart, a: Vector3, b: Vector3, thickness: number, depth: number, color: Color3, material: Enum.Material?): BasePart
	local cf, length = span(a, b)
	return block(h, Vector3.new(length, thickness, depth), color, cf, material)
end

-- Trait de visage pour Build.face : position en échelle de la face, dimensions en studs
-- (les cercles restent ronds quelle que soit la forme de la face).
local function mark(face: Vector2, x: number, y: number, width: number, height: number, color: Color3, corner: number?, rotation: number?): FaceShape
	return {
		position = UDim2.fromScale(x, y),
		size = UDim2.fromScale(width / face.X, height / face.Y),
		color = color,
		corner = corner or 1,
		rotation = rotation,
	}
end

-- Zone invisible servant de volume d'émission aux particules.
local function effectZone(h: BasePart, size: Vector3, cf: CFrame): BasePart
	return Build.attach(h, Build.part({ Name = "ZoneEffet", Size = size, Transparency = 1 }), cf)
end

-- Particules purement visuelles (textures intégrées uniquement), repérables par l'attribut CosmeticFx.
local function particles(zone: BasePart, options: FxOptions): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Particules"
	emitter.Texture = options.texture
	emitter.Color = ColorSequence.new(options.color)
	emitter.Rate = options.rate
	emitter.Lifetime = options.lifetime
	emitter.Speed = options.speed
	emitter.Size = options.size
	emitter.Transparency = options.transparency
	emitter.LightEmission = options.lightEmission
	emitter.EmissionDirection = options.direction or Enum.NormalId.Top
	emitter.SpreadAngle = options.spread or Vector2.new(180, 180)
	emitter.Acceleration = options.acceleration or Vector3.zero
	emitter.LockedToPart = false
	emitter:SetAttribute("CosmeticFx", true)
	emitter.Parent = zone
	return emitter
end

-- Scintillement doré discret (couronne, auréole).
local function sparkles(zone: BasePart, color: Color3, rate: number): ParticleEmitter
	return particles(zone, {
		texture = TEX_SPARKLES,
		color = color,
		rate = rate,
		lifetime = NumberRange.new(0.6, 1.1),
		speed = NumberRange.new(0.2, 0.6),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0) }),
		transparency = NumberSequence.new(0.1, 1),
		lightEmission = 1,
	})
end

--------------------------------------------------------------------------------
-- Définitions
--------------------------------------------------------------------------------

local function var(theme: string, colors: { Color3 }): Variant
	return { nameKey = "cos.heads.var." .. theme, colors = colors }
end

local function forSale(): Unlock
	return { kind = "Price" }
end

local function achievement(achievementId: string): Unlock
	return { kind = "Achievement", value = achievementId }
end

local function painter(variant: Variant): Paint
	local colors = variant.colors
	return function(index: number): Color3
		return colors[index] or colors[1] or FALLBACK
	end
end

local function newAccessory(id: string, attachment: AttachmentName): (Accessory, Part)
	local accessory, handle = Build.accessory(id, attachment, HANDLE_SIZE, ATTACH_POINTS[attachment])
	accessory.AccessoryType = ACCESSORY_TYPES[attachment]
	return accessory, handle
end

local function define(entry: Entry): CosmeticDef
	local variants = entry.variants
	return {
		id = entry.id,
		slot = "Head",
		nameKey = "cos." .. entry.id,
		descKey = "cos." .. entry.id .. ".desc",
		rarity = entry.rarity,
		price = entry.price,
		unlock = entry.unlock,
		variants = variants,
		tags = entry.tags,
		build = function(variant: number?): Instance
			local index = if variant ~= nil and variants[variant] ~= nil then variant else 1
			local accessory, handle = newAccessory(entry.id, entry.attachment)
			accessory:SetAttribute("CosmeticId", entry.id)
			accessory:SetAttribute("CosmeticSlot", "Head")
			accessory:SetAttribute("CosmeticVariant", index)
			entry.model(handle, painter(variants[index]))
			return Build.finalize(accessory)
		end,
	}
end

local defs: { CosmeticDef } = {}

local function add(entry: Entry)
	table.insert(defs, define(entry))
end

--------------------------------------------------------------------------------
-- Communs (10)
--------------------------------------------------------------------------------

-- Casquette de golf : calotte, visière, bouton et balle de golf brodée en relief.
add({
	id = "head_caddie_cap",
	attachment = "HatAttachment",
	rarity = "Common",
	price = 160,
	unlock = forSale(),
	tags = { "hat", "golf" },
	variants = {
		var("classic", { rgb(46, 139, 87), rgb(245, 245, 240), rgb(245, 245, 240) }),
		var("night", { rgb(32, 44, 92), rgb(250, 200, 50), rgb(250, 200, 50) }),
		var("lava", { rgb(205, 45, 45), rgb(40, 40, 46), rgb(245, 245, 240) }),
		var("candy", { rgb(255, 140, 190), rgb(120, 80, 170), rgb(255, 255, 255) }),
	},
	model = function(h: BasePart, c: Paint)
		blob(h, v3(1.32, 0.8, 1.34), c(1), at(0, 0.5, 0.02)) -- calotte
		blob(h, v3(1.02, 0.09, 0.92), c(2), at(0, 0.38, -0.56) * rot(-8, 0, 0)) -- visière
		ball(h, 0.15, c(3), at(0, 0.9, 0.02)) -- bouton
		ball(h, 0.26, WHITE, at(0, 0.6, -0.6)) -- balle de golf en relief
	end,
})

-- Bob de pêcheur à bord souple, avec un bouchon de pêche piqué sur le côté.
add({
	id = "head_bucket_hat",
	attachment = "HatAttachment",
	rarity = "Common",
	price = 180,
	unlock = forSale(),
	tags = { "hat", "golf", "coast" },
	variants = {
		var("desert", { rgb(214, 190, 140), rgb(120, 88, 58), rgb(225, 50, 50) }),
		var("ocean", { rgb(70, 130, 180), rgb(240, 240, 240), rgb(250, 200, 40) }),
		var("forest", { rgb(96, 124, 72), rgb(62, 46, 32), rgb(255, 130, 20) }),
	},
	model = function(h: BasePart, c: Paint)
		blob(h, v3(1.95, 0.2, 1.95), c(1), at(0, 0.44, 0), FABRIC) -- bord souple
		column(h, 0.48, 1.3, c(1), at(0, 0.66, 0), FABRIC) -- calotte
		blob(h, v3(1.3, 0.26, 1.3), c(1), at(0, 0.9, 0), FABRIC) -- dessus arrondi
		column(h, 0.12, 1.33, c(2), at(0, 0.5, 0)) -- ruban
		local bobber = v3(0.44, 0.7, -0.52)
		ball(h, 0.2, c(3), CFrame.new(bobber)) -- bouchon
		column(h, 0.05, 0.23, WHITE, CFrame.new(bobber)) -- bague blanche du bouchon
		rod(h, bobber + v3(0, 0.08, 0), bobber + v3(-0.01, 0.24, 0.02), 0.025, WHITE) -- antenne du bouchon
	end,
})

-- Serre-tête à oreilles de lapin : une oreille droite, l'autre pliée.
add({
	id = "head_bunny_ears",
	attachment = "HairAttachment",
	rarity = "Common",
	price = 180,
	unlock = forSale(),
	tags = { "headband", "animal", "silly" },
	variants = {
		var("classic", { rgb(255, 120, 170), rgb(248, 248, 248), rgb(255, 182, 200) }),
		var("chocolate", { rgb(200, 40, 50), rgb(120, 80, 50), rgb(235, 205, 170) }),
		var("night", { rgb(190, 190, 200), rgb(48, 48, 58), rgb(150, 100, 200) }),
	},
	model = function(h: BasePart, c: Paint)
		blob(h, v3(1.32, 0.6, 0.2), c(1), at(0, 0.36, 0.05)) -- serre-tête (arc visible sur le dessus)
		local left = at(-0.25, 0.58, 0.05) * rot(0, 0, 14)
		blob(h, v3(0.32, 1.0, 0.14), c(2), left * at(0, 0.5, 0))
		blob(h, v3(0.18, 0.72, 0.05), c(3), left * at(0, 0.52, -0.06))
		local right = at(0.25, 0.58, 0.05) * rot(0, 0, -10)
		blob(h, v3(0.32, 0.56, 0.14), c(2), right * at(0, 0.26, 0))
		blob(h, v3(0.18, 0.4, 0.05), c(3), right * at(0, 0.28, -0.06))
		local fold = right * at(0, 0.5, 0) * rot(0, 0, -95) -- l'oreille qui a abandonné
		blob(h, v3(0.3, 0.56, 0.14), c(2), fold * at(0, 0.25, 0))
		blob(h, v3(0.16, 0.38, 0.05), c(3), fold * at(0, 0.27, -0.06))
	end,
})

-- Bonnet tricoté avec revers rayé, étiquette et gros pompon.
add({
	id = "head_pompom_beanie",
	attachment = "HatAttachment",
	rarity = "Common",
	price = 200,
	unlock = forSale(),
	tags = { "hat", "snow" },
	variants = {
		var("classic", { rgb(200, 40, 50), rgb(245, 245, 245), rgb(245, 245, 245) }),
		var("frost", { rgb(120, 180, 230), rgb(240, 248, 255), rgb(255, 255, 255) }),
		var("forest", { rgb(50, 120, 70), rgb(30, 75, 45), rgb(250, 210, 60) }),
		var("sunset", { rgb(250, 140, 50), rgb(120, 60, 150), rgb(255, 170, 200) }),
	},
	model = function(h: BasePart, c: Paint)
		blob(h, v3(1.34, 1.0, 1.36), c(1), at(0, 0.52, 0.01), FABRIC) -- bonnet
		column(h, 0.26, 1.38, c(2), at(0, 0.42, 0), FABRIC) -- revers
		column(h, 0.05, 1.4, c(1), at(0, 0.48, 0), FABRIC) -- rayure du revers
		ball(h, 0.44, c(3), at(0, 1.08, 0.02), FABRIC) -- pompon
		block(h, v3(0.24, 0.12, 0.04), c(1), at(0, 0.37, -0.7)) -- étiquette
	end,
})

-- Cône de signalisation en gradins, bandes réfléchissantes et socle carré.
add({
	id = "head_traffic_cone",
	attachment = "HatAttachment",
	rarity = "Common",
	price = 200,
	unlock = forSale(),
	tags = { "hat", "silly", "city" },
	variants = {
		var("classic", { rgb(255, 120, 20), rgb(250, 250, 250), rgb(40, 40, 45) }),
		var("retro", { rgb(250, 210, 40), rgb(35, 35, 40), rgb(70, 70, 75) }),
		var("neon", { rgb(150, 230, 60), rgb(250, 250, 250), rgb(30, 30, 35) }),
	},
	model = function(h: BasePart, c: Paint)
		block(h, v3(1.3, 0.1, 1.3), c(3), at(0, 0.56, 0)) -- socle
		local y = 0.61
		-- { hauteur, diamètre, couleur } du bas vers le haut
		for _, tier in { { 0.32, 1.06, 1 }, { 0.16, 0.92, 2 }, { 0.3, 0.78, 1 }, { 0.14, 0.64, 2 }, { 0.28, 0.5, 1 } } do
			local height, diameter, colorIndex = tier[1], tier[2], tier[3]
			local part = column(h, height, diameter, c(colorIndex), at(0, y + height / 2, 0))
			if colorIndex == 2 then
				part.Reflectance = 0.2 -- bande réfléchissante
			end
			y += height - 0.01
		end
		ball(h, 0.36, c(1), at(0, y + 0.08, 0)) -- pointe arrondie
	end,
})

-- Tee géant planté dans le crâne, balle posée dessus avec son trait d'alignement.
add({
	id = "head_giant_tee",
	attachment = "HatAttachment",
	rarity = "Common",
	price = 200,
	unlock = forSale(),
	tags = { "hat", "golf", "silly" },
	variants = {
		var("classic", { rgb(214, 170, 110), rgb(248, 248, 245), rgb(220, 40, 40) }),
		var("candy", { rgb(255, 120, 190), rgb(248, 248, 245), rgb(60, 140, 255) }),
		var("neon", { rgb(240, 240, 40), rgb(248, 248, 245), rgb(40, 200, 90) }),
	},
	model = function(h: BasePart, c: Paint)
		column(h, 0.75, 0.16, c(1), at(0, 0.85, 0)) -- tige
		column(h, 0.1, 0.26, c(1), at(0, 1.25, 0)) -- évasement
		column(h, 0.08, 0.42, c(1), at(0, 1.32, 0)) -- coupelle
		ball(h, 0.62, c(2), at(0, 1.6, 0)) -- balle
		tube(h, 0.05, 0.64, c(3), at(0, 1.6, 0) * rot(0, 30, 0)) -- trait d'alignement
	end,
})

-- Toque de chef bouffante, cuillère en bois glissée dans le bandeau.
add({
	id = "head_chef_toque",
	attachment = "HatAttachment",
	rarity = "Common",
	price = 220,
	unlock = forSale(),
	tags = { "hat", "food" },
	variants = {
		var("classic", { rgb(250, 250, 250), rgb(232, 232, 236), rgb(190, 140, 90) }),
		var("candy", { rgb(255, 214, 230), rgb(255, 190, 215), rgb(190, 140, 90) }),
		var("night", { rgb(52, 52, 60), rgb(32, 32, 38), rgb(200, 205, 215) }),
	},
	model = function(h: BasePart, c: Paint)
		column(h, 0.42, 1.3, c(2), at(0, 0.62, 0)) -- bandeau
		blob(h, v3(1.5, 0.7, 1.5), c(1), at(0, 1.08, 0)) -- dôme bouffant
		ball(h, 0.66, c(1), at(0.36, 1.24, 0.05))
		ball(h, 0.66, c(1), at(-0.36, 1.24, 0.05))
		ball(h, 0.62, c(1), at(0, 1.26, -0.34))
		ball(h, 0.62, c(1), at(0, 1.26, 0.38))
		local tip = v3(-0.8, 1.25, -0.1)
		rod(h, v3(-0.62, 0.5, -0.25), tip, 0.07, c(3)) -- manche de la cuillère
		blob(h, v3(0.2, 0.3, 0.08), c(3), CFrame.new(tip + v3(-0.03, 0.12, 0.02)) * rot(0, 0, 14)) -- cuilleron
	end,
})

-- Œuf au plat posé sur le crâne : blanc irrégulier, coulure sur la tempe, jaune brillant.
add({
	id = "head_fried_egg",
	attachment = "HatAttachment",
	rarity = "Common",
	price = 220,
	unlock = forSale(),
	tags = { "hat", "food", "silly", "desert" },
	variants = {
		var("classic", { rgb(252, 252, 246), rgb(255, 184, 28), rgb(255, 255, 255) }),
		var("sunset", { rgb(255, 242, 228), rgb(255, 112, 40), rgb(255, 255, 255) }),
		var("toxic", { rgb(214, 255, 210), rgb(130, 220, 60), rgb(240, 255, 240) }),
	},
	model = function(h: BasePart, c: Paint)
		blob(h, v3(1.45, 0.12, 1.15), c(1), at(0.05, 0.63, 0.04) * rot(0, 12, 0)) -- blanc
		blob(h, v3(0.95, 0.12, 0.85), c(1), at(-0.4, 0.62, -0.22) * rot(0, -20, 5))
		blob(h, v3(0.9, 0.12, 0.8), c(1), at(0.38, 0.615, 0.36) * rot(0, 35, -5))
		blob(h, v3(0.12, 0.5, 0.42), c(1), at(0.67, 0.42, -0.12) * rot(0, 0, 6)) -- coulure sur la tempe
		blob(h, v3(0.56, 0.4, 0.56), c(2), at(0.06, 0.72, -0.02)) -- jaune
		ball(h, 0.12, c(3), at(-0.04, 0.88, -0.14)) -- reflet
	end,
})

-- Grille-pain rétro : deux tartines qui jaillissent, levier et molette.
add({
	id = "head_toaster",
	attachment = "HatAttachment",
	rarity = "Common",
	price = 240,
	unlock = forSale(),
	tags = { "hat", "food", "silly" },
	variants = {
		var("silver", { rgb(200, 205, 212), rgb(232, 190, 120), rgb(160, 100, 50), rgb(40, 40, 45) }),
		var("retro", { rgb(210, 60, 50), rgb(232, 190, 120), rgb(160, 100, 50), rgb(245, 240, 230) }),
		var("candy", { rgb(150, 220, 195), rgb(240, 200, 140), rgb(170, 110, 60), rgb(255, 255, 255) }),
	},
	model = function(h: BasePart, c: Paint)
		local body = block(h, v3(1.1, 0.5, 0.7), c(1), at(0, 0.85, 0)) -- corps
		body.Reflectance = 0.15
		local top = tube(h, 1.1, 0.7, c(1), at(0, 1.1, 0)) -- dessus arrondi
		top.Reflectance = 0.15
		block(h, v3(0.78, 0.04, 0.1), c(4), at(0, 1.43, -0.13)) -- fentes
		block(h, v3(0.78, 0.04, 0.1), c(4), at(0, 1.43, 0.13))
		for index, z in { -0.13, 0.13 } do
			local slice = at(0, 1.5, z) * rot(if index == 1 then -6 else 5, 0, 0)
			block(h, v3(0.6, 0.5, 0.09), c(2), slice) -- tartine
			blob(h, v3(0.62, 0.24, 0.1), c(3), slice * at(0, 0.26, 0)) -- croûte arrondie
		end
		block(h, v3(0.16, 0.07, 0.12), c(4), at(0.62, 0.95, 0)) -- levier
		tube(h, 0.05, 0.16, c(4), at(0.32, 0.8, -0.36) * rot(0, 90, 0)) -- molette
	end,
})

-- Mortier de diplômé (défi : terminer le tutoriel), cordon et pompon pendant à droite.
add({
	id = "head_graduation_cap",
	attachment = "HatAttachment",
	rarity = "Common",
	price = 0,
	unlock = achievement("ach_tutorial"),
	tags = { "hat" },
	variants = {
		var("classic", { rgb(30, 30, 36), rgb(240, 190, 50) }),
		var("royal", { rgb(40, 60, 150), rgb(225, 230, 240) }),
		var("lava", { rgb(150, 25, 40), rgb(240, 190, 50) }),
	},
	model = function(h: BasePart, c: Paint)
		column(h, 0.3, 1.28, c(1), at(0, 0.6, 0)) -- calotte
		block(h, v3(1.55, 0.06, 1.55), c(1), at(0, 0.78, 0) * rot(0, 45, 0)) -- planche
		column(h, 0.05, 0.14, c(2), at(0, 0.835, 0)) -- bouton
		local corner = v3(1.04, 0.83, 0)
		rod(h, v3(0, 0.83, 0), corner, 0.04, c(2)) -- cordon
		rod(h, corner, v3(1.04, 0.44, 0), 0.04, c(2)) -- cordon pendant
		blob(h, v3(0.13, 0.28, 0.13), c(2), at(1.04, 0.34, 0)) -- pompon
	end,
})

--------------------------------------------------------------------------------
-- Rares (7)
--------------------------------------------------------------------------------

-- Haut-de-forme, ruban et boucle, tee de secours glissé dans le ruban.
add({
	id = "head_top_hat",
	attachment = "HatAttachment",
	rarity = "Rare",
	price = 450,
	unlock = forSale(),
	tags = { "hat", "golf" },
	variants = {
		var("classic", { rgb(28, 28, 34), rgb(170, 30, 45), rgb(235, 195, 70) }),
		var("ghost", { rgb(240, 240, 244), rgb(35, 35, 42), rgb(190, 195, 205) }),
		var("royal", { rgb(80, 40, 125), rgb(240, 200, 70), rgb(250, 250, 250) }),
	},
	model = function(h: BasePart, c: Paint)
		column(h, 0.07, 1.8, c(1), at(0, 0.5, 0)) -- bord
		column(h, 1.05, 1.24, c(1), at(0, 1.05, 0)) -- cheminée
		column(h, 0.06, 1.3, c(1), at(0, 1.57, 0)) -- rebord du dessus
		column(h, 0.22, 1.27, c(2), at(0, 0.66, 0)) -- ruban
		block(h, v3(0.26, 0.18, 0.05), c(3), at(0, 0.66, -0.63)) -- boucle
		local base, tip = v3(0.56, 0.6, -0.22), v3(0.74, 1.05, -0.3)
		rod(h, base, tip, 0.06, c(3)) -- tige du tee
		rod(h, tip, tip + (tip - base).Unit * 0.07, 0.15, c(3)) -- coupelle du tee
	end,
})

-- Bonnet à hélice : coutures en croix, petite visière, hélice à deux pales.
add({
	id = "head_propeller_beanie",
	attachment = "HatAttachment",
	rarity = "Rare",
	price = 460,
	unlock = forSale(),
	tags = { "hat", "silly" },
	variants = {
		var("classic", { rgb(220, 50, 50), rgb(250, 210, 40), rgb(40, 110, 230), rgb(245, 245, 245) }),
		var("retro", { rgb(60, 170, 90), rgb(245, 245, 245), rgb(225, 60, 50), rgb(250, 210, 40) }),
		var("night", { rgb(40, 40, 55), rgb(150, 90, 220), rgb(120, 240, 140), rgb(200, 205, 215) }),
	},
	model = function(h: BasePart, c: Paint)
		blob(h, v3(1.34, 0.82, 1.36), c(1), at(0, 0.52, 0.01)) -- calotte
		blob(h, v3(1.37, 0.86, 0.2), c(2), at(0, 0.52, 0.01)) -- couture gauche-droite
		blob(h, v3(0.2, 0.86, 1.39), c(2), at(0, 0.52, 0.01)) -- couture avant-arrière
		blob(h, v3(0.8, 0.07, 0.5), c(2), at(0, 0.37, -0.6) * rot(-8, 0, 0)) -- visière
		column(h, 0.2, 0.06, c(4), at(0, 1.0, 0.01)) -- axe
		ball(h, 0.14, c(4), at(0, 1.1, 0.01)) -- moyeu
		blob(h, v3(0.78, 0.04, 0.2), c(3), at(0.39, 1.1, 0.01) * rot(14, 0, 0)) -- pale droite
		blob(h, v3(0.78, 0.04, 0.2), c(3), at(-0.39, 1.1, 0.01) * rot(-14, 0, 0)) -- pale gauche
	end,
})

-- Masque de plongée aux grands yeux étonnés, sangle et tuba qui remonte le long de la tête.
add({
	id = "head_snorkel_mask",
	attachment = "FaceFrontAttachment",
	rarity = "Rare",
	price = 480,
	unlock = forSale(),
	tags = { "mask", "silly", "coast" },
	variants = {
		var("classic", { rgb(30, 30, 36), rgb(250, 210, 40), rgb(255, 120, 30), rgb(170, 220, 255) }),
		var("ocean", { rgb(30, 90, 170), rgb(245, 245, 245), rgb(230, 50, 50), rgb(190, 235, 255) }),
		var("candy", { rgb(255, 130, 190), rgb(150, 230, 210), rgb(255, 255, 255), rgb(255, 220, 240) }),
		var("neon", { rgb(140, 230, 60), rgb(30, 30, 36), rgb(255, 140, 30), rgb(220, 255, 200) }),
	},
	model = function(h: BasePart, c: Paint)
		blob(h, v3(1.08, 0.56, 0.3), c(1), at(0, 0.13, -0.55)) -- monture en caoutchouc
		local glass = blob(h, v3(0.88, 0.4, 0.24), c(4), at(0, 0.14, -0.62), GLASS) -- vitre
		glass.Transparency = 0.3
		local size = Vector2.new(0.88, 0.4)
		Build.face(glass, {
			mark(size, 0.3, 0.5, 0.3, 0.3, WHITE),
			mark(size, 0.7, 0.5, 0.3, 0.3, WHITE),
			mark(size, 0.33, 0.43, 0.12, 0.12, BLACK),
			mark(size, 0.67, 0.43, 0.12, 0.12, BLACK),
			mark(size, 0.31, 0.37, 0.04, 0.04, WHITE),
			mark(size, 0.65, 0.37, 0.04, 0.04, WHITE),
		}, Enum.NormalId.Front)
		blob(h, v3(0.3, 0.26, 0.22), c(1), at(0, -0.1, -0.68)) -- poche du nez
		column(h, 0.14, 1.27, c(1), at(0, 0.13, 0)) -- sangle
		local elbow, mouth = v3(-0.7, -0.32, -0.4), v3(-0.1, -0.32, -0.7)
		local top, tip = v3(-0.7, 0.98, -0.4), v3(-0.64, 1.16, -0.3)
		rod(h, elbow, top, 0.13, c(2)) -- tube
		rod(h, top, tip, 0.13, c(2)) -- extrémité coudée
		ball(h, 0.18, c(3), CFrame.new(tip)) -- embout coloré
		ball(h, 0.14, c(2), CFrame.new(elbow)) -- coude
		rod(h, elbow, mouth, 0.12, c(2)) -- tube vers la bouche
		block(h, v3(0.26, 0.12, 0.08), c(3), at(-0.04, -0.32, -0.72)) -- embout buccal
	end,
})

-- Loup de carnaval : deux lobes aux yeux mystérieux, joyau, sequins et bouquet de plumes.
add({
	id = "head_carnival_mask",
	attachment = "FaceFrontAttachment",
	rarity = "Rare",
	price = 500,
	unlock = forSale(),
	tags = { "mask", "city" },
	variants = {
		var("royal", { rgb(100, 40, 150), rgb(240, 195, 70), rgb(255, 120, 180), rgb(60, 200, 200) }),
		var("night", { rgb(25, 25, 30), rgb(200, 205, 215), rgb(245, 245, 245), rgb(130, 130, 140) }),
		var("lava", { rgb(190, 30, 40), rgb(240, 195, 70), rgb(255, 140, 40), rgb(255, 220, 60) }),
		var("ocean", { rgb(20, 140, 150), rgb(200, 205, 215), rgb(60, 120, 230), rgb(240, 250, 255) }),
	},
	model = function(h: BasePart, c: Paint)
		local size = Vector2.new(0.62, 0.4)
		for side = -1, 1, 2 do
			local lobe = blob(h, v3(0.62, 0.4, 0.16), c(1), at(0.27 * side, 0.14, -0.64) * rot(0, 0, 10 * side))
			Build.face(lobe, {
				mark(size, 0.5, 0.52, 0.28, 0.12, DARK),
				mark(size, 0.45, 0.47, 0.04, 0.04, WHITE),
			}, Enum.NormalId.Front)
			ball(h, 0.07, c(2), at(0.57 * side, 0.25, -0.66)) -- sequin
		end
		ball(h, 0.15, c(2), at(0, 0.2, -0.72), GLASS) -- joyau
		local base = v3(0.5, 0.3, -0.68)
		blob(h, v3(0.14, 0.85, 0.05), c(3), CFrame.new(base) * rot(0, 0, -18) * at(0, 0.42, 0)) -- plumes
		blob(h, v3(0.13, 0.75, 0.05), c(4), CFrame.new(base + v3(0.04, 0, 0.02)) * rot(0, 0, -40) * at(0, 0.37, 0))
		blob(h, v3(0.12, 0.7, 0.05), c(4), CFrame.new(base + v3(-0.03, 0, 0.02)) * rot(0, 0, 4) * at(0, 0.35, 0))
	end,
})

-- Tricorne de pirate : trois bords relevés en triangle, balle-crâne et clubs croisés.
add({
	id = "head_pirate_tricorn",
	attachment = "HatAttachment",
	rarity = "Rare",
	price = 520,
	unlock = forSale(),
	tags = { "hat", "coast" },
	variants = {
		var("classic", { rgb(30, 28, 32), rgb(245, 240, 225), rgb(230, 185, 60) }),
		var("ghost", { rgb(80, 100, 100), rgb(200, 255, 225), rgb(190, 200, 205) }),
		var("royal", { rgb(30, 40, 95), rgb(245, 245, 245), rgb(230, 185, 60) }),
	},
	model = function(h: BasePart, c: Paint)
		blob(h, v3(1.3, 0.78, 1.32), c(1), at(0, 0.56, 0.02)) -- calotte
		for _, angle in { 0, 120, 240 } do -- bord arrière puis bords avant (pointe vers l'avant)
			local normal = v3(math.sin(math.rad(angle)), 0, math.cos(math.rad(angle)))
			local center = normal * 0.64 + v3(0, 0.52, 0)
			blob(h, v3(2.25, 0.62, 0.12), c(1), CFrame.lookAt(center, center + normal) * rot(-18, 0, 0))
		end
		rod(h, v3(-0.21, 0.66, -0.58), v3(0.21, 0.86, -0.38), 0.05, c(3)) -- clubs croisés
		rod(h, v3(0.21, 0.66, -0.58), v3(-0.21, 0.86, -0.38), 0.05, c(3))
		ball(h, 0.28, c(2), at(0, 0.77, -0.5)) -- balle-crâne
		ball(h, 0.07, DARK, at(-0.05, 0.79, -0.63))
		ball(h, 0.07, DARK, at(0.05, 0.79, -0.63))
	end,
})

-- Casque à cornes : calotte de métal, cerclage, crête, nasal et cornes recourbées.
add({
	id = "head_viking_helmet",
	attachment = "HatAttachment",
	rarity = "Rare",
	price = 540,
	unlock = forSale(),
	tags = { "helmet", "snow" },
	variants = {
		var("classic", { rgb(150, 155, 162), rgb(180, 120, 50), rgb(240, 230, 200) }),
		var("gold", { rgb(230, 190, 70), rgb(110, 70, 40), rgb(250, 250, 245) }),
		var("frost", { rgb(170, 210, 240), rgb(240, 248, 255), rgb(210, 230, 250) }),
		var("night", { rgb(50, 50, 60), rgb(170, 40, 40), rgb(220, 210, 190) }),
	},
	model = function(h: BasePart, c: Paint)
		blob(h, v3(1.34, 0.96, 1.36), c(1), at(0, 0.47, 0.01), METAL) -- calotte
		column(h, 0.16, 1.39, c(2), at(0, 0.34, 0), METAL) -- cerclage
		blob(h, v3(0.16, 0.98, 1.39), c(2), at(0, 0.48, 0.01), METAL) -- crête
		block(h, v3(0.14, 0.4, 0.08), c(2), at(0, 0.13, -0.67), METAL) -- nasal
		for side = -1, 1, 2 do
			-- repère dont l'axe X local pointe vers l'extérieur ; chaque segment se relève un peu plus
			local frame = CFrame.new(0.58 * side, 0.56, 0) * (if side < 0 then rot(0, 180, 0) else CFrame.identity) * rot(0, 0, 10)
			for _, segment in { { 0.34, 0.26, 32 }, { 0.3, 0.2, 38 }, { 0.26, 0.13, 0 } } do
				local length, diameter, bend = segment[1], segment[2], segment[3]
				tube(h, length, diameter, c(3), frame * at(length / 2, 0, 0))
				frame = frame * at(length * 0.9, 0, 0) * rot(0, 0, bend)
			end
			ball(h, 0.13, c(3), frame * at(0.02, 0, 0)) -- pointe arrondie
		end
	end,
})

-- Cactus en pot souriant, deux bras levés et une fleur au sommet.
add({
	id = "head_cactus_pot",
	attachment = "HatAttachment",
	rarity = "Rare",
	price = 560,
	unlock = forSale(),
	tags = { "hat", "silly", "desert" },
	variants = {
		var("classic", { rgb(200, 100, 60), rgb(70, 160, 80), rgb(255, 110, 170) }),
		var("desert", { rgb(220, 190, 130), rgb(110, 140, 70), rgb(255, 220, 60) }),
		var("candy", { rgb(110, 150, 240), rgb(150, 230, 190), rgb(255, 255, 255) }),
	},
	model = function(h: BasePart, c: Paint)
		column(h, 0.5, 1.0, c(1), at(0, 0.86, 0)) -- pot
		column(h, 0.14, 1.12, c(1), at(0, 1.12, 0)) -- rebord
		column(h, 0.04, 0.98, SOIL, at(0, 1.2, 0)) -- terreau
		local stem = blob(h, v3(0.44, 1.12, 0.44), c(2), at(0, 1.72, 0)) -- tige
		local size = Vector2.new(0.44, 1.12)
		Build.face(stem, {
			mark(size, 0.36, 0.38, 0.06, 0.06, DARK),
			mark(size, 0.64, 0.38, 0.06, 0.06, DARK),
			mark(size, 0.5, 0.45, 0.1, 0.03, DARK),
			mark(size, 0.24, 0.44, 0.06, 0.035, BLUSH),
			mark(size, 0.76, 0.44, 0.06, 0.035, BLUSH),
		}, Enum.NormalId.Front)
		blob(h, v3(0.38, 0.2, 0.2), c(2), at(-0.3, 1.62, 0)) -- bras gauche
		blob(h, v3(0.2, 0.46, 0.2), c(2), at(-0.44, 1.84, 0))
		blob(h, v3(0.34, 0.18, 0.18), c(2), at(0.28, 1.8, 0)) -- bras droit
		blob(h, v3(0.18, 0.4, 0.18), c(2), at(0.4, 2.0, 0))
		ball(h, 0.22, c(3), at(0, 2.3, 0)) -- fleur
	end,
})

--------------------------------------------------------------------------------
-- Épiques (5)
--------------------------------------------------------------------------------

-- Chapeau de mage : large bord, cône en gradins qui ploie vers l'arrière, étoiles lumineuses.
add({
	id = "head_wizard_hat",
	attachment = "HatAttachment",
	rarity = "Epic",
	price = 950,
	unlock = forSale(),
	tags = { "hat", "golf" },
	variants = {
		var("classic", { rgb(45, 55, 140), rgb(235, 195, 70), rgb(255, 230, 120) }),
		var("desert", { rgb(205, 175, 115), rgb(110, 75, 45), rgb(255, 150, 60) }),
		var("forest", { rgb(40, 105, 60), rgb(100, 70, 40), rgb(190, 255, 120) }),
		var("royal", { rgb(95, 45, 145), rgb(210, 215, 230), rgb(130, 230, 255) }),
	},
	model = function(h: BasePart, c: Paint)
		blob(h, v3(2.0, 0.12, 2.0), c(1), at(0, 0.47, 0)) -- bord large et souple
		column(h, 0.14, 1.25, c(2), at(0, 0.6, 0)) -- ruban
		block(h, v3(0.22, 0.18, 0.05), c(3), at(0, 0.6, -0.635)) -- boucle
		local frame = CFrame.new(0, 0.48, 0)
		local frames: { CFrame } = {}
		-- { hauteur, diamètre, inclinaison supplémentaire vers l'arrière }
		for _, tier in { { 0.42, 1.2, 0 }, { 0.38, 0.98, 5 }, { 0.34, 0.76, 11 }, { 0.3, 0.55, 20 }, { 0.28, 0.36, 32 } } do
			local height, diameter, bend = tier[1], tier[2], tier[3]
			frame = frame * rot(bend, 0, 0)
			column(h, height, diameter, c(1), frame * at(0, height / 2, 0))
			table.insert(frames, frame)
			frame = frame * at(0, height * 0.9, 0)
		end
		ball(h, 0.22, c(3), frame * at(0, 0.06, 0), NEON) -- étoile au bout
		ball(h, 0.14, c(3), frames[1] * at(-0.3, 0.24, -0.5), NEON) -- étoiles brodées
		ball(h, 0.11, c(3), frames[2] * at(0.22, 0.2, -0.42), NEON)
		ball(h, 0.1, c(3), frames[3] * at(-0.12, 0.18, -0.35), NEON)
	end,
})

-- Igloo douillet, joints de blocs de glace, tunnel d'entrée et pingouin locataire.
add({
	id = "head_igloo",
	attachment = "HatAttachment",
	rarity = "Epic",
	price = 980,
	unlock = forSale(),
	tags = { "hat", "animal", "snow" },
	variants = {
		var("classic", { rgb(236, 246, 255), rgb(190, 215, 235), rgb(255, 150, 40) }),
		var("frost", { rgb(170, 215, 245), rgb(120, 170, 215), rgb(255, 210, 60) }),
		var("candy", { rgb(255, 215, 235), rgb(240, 170, 205), rgb(255, 150, 40) }),
	},
	model = function(h: BasePart, c: Paint)
		blob(h, v3(1.5, 1.12, 1.5), c(1), at(0, 0.62, 0)) -- dôme de glace
		column(h, 0.03, 1.42, c(2), at(0, 0.82, 0)) -- joints des blocs
		column(h, 0.03, 1.04, c(2), at(0, 1.03, 0))
		tube(h, 0.5, 0.5, c(1), at(0, 0.62, -0.72) * rot(0, 90, 0)) -- tunnel d'entrée
		tube(h, 0.04, 0.36, DARK, at(0, 0.6, -0.97) * rot(0, 90, 0)) -- ouverture
		local penguin = blob(h, v3(0.26, 0.32, 0.24), BLACK, at(0, 0.62, -0.94)) -- pingouin
		local size = Vector2.new(0.26, 0.32)
		Build.face(penguin, {
			mark(size, 0.35, 0.3, 0.07, 0.07, WHITE),
			mark(size, 0.65, 0.3, 0.07, 0.07, WHITE),
			mark(size, 0.36, 0.31, 0.035, 0.035, BLACK),
			mark(size, 0.64, 0.31, 0.035, 0.035, BLACK),
		}, Enum.NormalId.Front)
		blob(h, v3(0.17, 0.2, 0.06), WHITE, at(0, 0.56, -1.04)) -- ventre
		blob(h, v3(0.09, 0.06, 0.12), c(3), at(0, 0.64, -1.08)) -- bec
	end,
})

-- Heaume de chevalier : fût d'acier, plaque faciale à fentes, renfort doré et plumet.
add({
	id = "head_knight_helm",
	attachment = "HatAttachment",
	rarity = "Epic",
	price = 1000,
	unlock = forSale(),
	tags = { "helmet" },
	variants = {
		var("classic", { rgb(165, 170, 180), rgb(220, 180, 60), rgb(60, 170, 80) }),
		var("night", { rgb(55, 55, 65), rgb(190, 195, 205), rgb(130, 60, 190) }),
		var("royal", { rgb(225, 228, 235), rgb(220, 180, 60), rgb(50, 90, 200) }),
	},
	model = function(h: BasePart, c: Paint)
		column(h, 1.4, 1.42, c(1), at(0, 0.06, 0), METAL) -- fût du heaume
		blob(h, v3(1.42, 0.42, 1.42), c(1), at(0, 0.76, 0), METAL) -- dôme
		local plate = block(h, v3(1.0, 1.22, 0.24), c(1), at(0, 0.04, -0.6), METAL) -- plaque faciale
		local size = Vector2.new(1.0, 1.22)
		local shapes = {
			mark(size, 0.26, 0.37, 0.34, 0.06, DARK, 0.5), -- fentes des yeux
			mark(size, 0.74, 0.37, 0.34, 0.06, DARK, 0.5),
		}
		for row = 0, 1 do -- trous d'aération
			for column_ = 0, 2 do
				table.insert(shapes, mark(size, 0.64 + column_ * 0.08, 0.6 + row * 0.08, 0.045, 0.045, DARK))
			end
		end
		Build.face(plate, shapes, Enum.NormalId.Front)
		block(h, v3(0.12, 1.24, 0.04), c(2), at(0, 0.04, -0.735), METAL) -- renfort vertical
		column(h, 0.08, 1.45, c(2), at(0, -0.62, 0), METAL) -- cerclage bas
		column(h, 0.08, 1.45, c(2), at(0, 0.74, 0), METAL) -- cerclage haut
		column(h, 0.16, 0.2, c(2), at(0, 1.0, 0), METAL) -- support du plumet
		blob(h, v3(0.26, 0.62, 1.3), c(3), at(0, 1.25, 0.12) * rot(12, 0, 0)) -- plumet
	end,
})

-- Bocal de verre autour de la tête : poisson rouge, algues, bulles, collier et valve.
add({
	id = "head_fishbowl_helmet",
	attachment = "HatAttachment",
	rarity = "Epic",
	price = 1100,
	unlock = forSale(),
	tags = { "helmet", "animal", "silly", "coast" },
	variants = {
		var("classic", { rgb(190, 235, 255), rgb(170, 175, 185), rgb(255, 140, 30), rgb(60, 170, 80) }),
		var("ocean", { rgb(150, 200, 255), rgb(230, 190, 70), rgb(255, 220, 60), rgb(40, 160, 150) }),
		var("candy", { rgb(255, 210, 235), rgb(245, 245, 245), rgb(170, 90, 220), rgb(150, 230, 190) }),
	},
	model = function(h: BasePart, c: Paint)
		local bowl = ball(h, 2.1, c(1), at(0, 0.2, 0), GLASS) -- bocal
		bowl.Transparency = 0.65
		column(h, 0.24, 1.62, c(2), at(0, -0.5, 0), METAL) -- collier
		column(h, 0.08, 0.3, c(2), at(0, 1.27, 0), METAL) -- valve
		local fish = blob(h, v3(0.28, 0.18, 0.1), c(3), at(-0.5, 0.62, -0.68)) -- poisson rouge
		local size = Vector2.new(0.28, 0.18)
		Build.face(fish, {
			mark(size, 0.78, 0.42, 0.05, 0.05, WHITE),
			mark(size, 0.8, 0.42, 0.025, 0.025, BLACK),
		}, Enum.NormalId.Front)
		blob(h, v3(0.12, 0.2, 0.04), c(3), at(-0.33, 0.62, -0.68) * rot(0, 0, 10)) -- queue
		blob(h, v3(0.1, 0.07, 0.03), c(3), at(-0.5, 0.72, -0.68)) -- nageoire
		blob(h, v3(0.1, 0.42, 0.06), c(4), at(0.64, -0.24, 0.32) * rot(0, 0, 10)) -- algues
		blob(h, v3(0.09, 0.36, 0.06), c(4), at(0.6, 0.08, 0.36) * rot(0, 0, -14))
		for _, bubble in { { -0.32, 0.8, -0.6, 0.1 }, { -0.24, 0.94, -0.52, 0.08 }, { -0.15, 1.06, -0.4, 0.06 } } do
			local part = ball(h, bubble[4], WHITE, at(bubble[1], bubble[2], bubble[3]), GLASS) -- bulles
			part.Transparency = 0.4
		end
	end,
})

-- Tête d'aigle (défi : réussir un eagle) : bec crochu, regard froncé, collerette et plumes.
add({
	id = "head_eagle_helm",
	attachment = "HatAttachment",
	rarity = "Epic",
	price = 0,
	unlock = achievement("ach_eagle"),
	tags = { "helmet", "animal", "golf" },
	variants = {
		var("classic", { rgb(248, 248, 244), rgb(250, 200, 40), rgb(110, 70, 40) }),
		var("gold", { rgb(205, 155, 75), rgb(250, 210, 60), rgb(90, 55, 30) }),
		var("frost", { rgb(215, 232, 255), rgb(205, 210, 220), rgb(40, 60, 110) }),
	},
	model = function(h: BasePart, c: Paint)
		blob(h, v3(1.32, 0.92, 1.42), c(1), at(0, 0.74, 0.02)) -- tête d'aigle
		column(h, 0.26, 1.38, c(3), at(0, 0.38, 0.02)) -- collerette de plumes
		blob(h, v3(0.42, 0.3, 0.62), c(2), at(0, 0.62, -0.74) * rot(-12, 0, 0)) -- bec
		blob(h, v3(0.22, 0.26, 0.2), c(2), at(0, 0.5, -1.0) * rot(30, 0, 0)) -- crochet du bec
		for side = -1, 1, 2 do
			ball(h, 0.22, WHITE, at(0.28 * side, 0.9, -0.55)) -- œil
			ball(h, 0.1, BLACK, at(0.26 * side, 0.9, -0.65)) -- pupille
			block(h, v3(0.3, 0.07, 0.08), c(3), at(0.28 * side, 1.04, -0.47) * rot(0, 0, 18 * side)) -- sourcil froncé
			blob(h, v3(0.34, 0.14, 0.62), c(3), at(0.18 * side, 0.86, 0.66) * rot(20, 14 * side, 0)) -- plumes arrière
		end
	end,
})

--------------------------------------------------------------------------------
-- Légendaires (3)
--------------------------------------------------------------------------------

-- Couronne d'or : fleurons, gemmes, coussin de velours, balle de golf sur tee en guise d'orbe.
add({
	id = "head_green_crown",
	attachment = "HatAttachment",
	rarity = "Legendary",
	price = 2000,
	unlock = forSale(),
	tags = { "crown", "golf", "fx" },
	variants = {
		var("classic", { rgb(240, 190, 50), rgb(170, 30, 50), rgb(40, 200, 90), rgb(220, 40, 60) }),
		var("silver", { rgb(205, 210, 220), rgb(40, 60, 160), rgb(60, 130, 255), rgb(160, 80, 220) }),
		var("night", { rgb(70, 64, 80), rgb(90, 30, 120), rgb(120, 255, 170), rgb(255, 90, 200) }),
		var("rose", { rgb(232, 165, 140), rgb(250, 235, 220), rgb(255, 130, 180), rgb(255, 255, 255) }),
	},
	model = function(h: BasePart, c: Paint)
		blob(h, v3(1.12, 0.56, 1.12), c(2), at(0, 0.76, 0), FABRIC) -- coussin de velours
		column(h, 0.34, 1.32, c(1), at(0, 0.62, 0), METAL) -- bandeau
		for index = 0, 4 do
			local angle = math.rad(index * 72)
			local direction = v3(math.sin(angle), 0, -math.cos(angle))
			local post = v3(direction.X * 0.6, 0.92, direction.Z * 0.6)
			block(h, v3(0.2, 0.34, 0.08), c(1), CFrame.lookAt(post, post + direction), METAL) -- fleuron
			ball(h, 0.17, c(1), CFrame.new(post.X, 1.12, post.Z), METAL)
		end
		ball(h, 0.24, c(3), at(0, 0.62, -0.66), GLASS) -- gemme frontale
		ball(h, 0.16, c(4), at(-0.57, 0.62, -0.33), GLASS)
		ball(h, 0.16, c(4), at(0.57, 0.62, -0.33), GLASS)
		column(h, 0.16, 0.08, c(1), at(0, 1.1, 0), METAL) -- petit tee
		ball(h, 0.26, WHITE, at(0, 1.27, 0)) -- balle de golf, l'orbe royal
		sparkles(effectZone(h, v3(1.3, 0.4, 1.3), at(0, 1.0, 0)), c(1), 3)
	end,
})

-- Nuage d'orage boudeur qui flotte au-dessus de la tête : visage grognon, éclair et pluie continue.
add({
	id = "head_storm_cloud",
	attachment = "HatAttachment",
	rarity = "Legendary",
	price = 2200,
	unlock = forSale(),
	tags = { "hat", "silly", "fx" },
	variants = {
		var("classic", { rgb(120, 126, 140), rgb(255, 230, 60), rgb(150, 200, 255) }),
		var("candy", { rgb(255, 190, 222), rgb(90, 230, 255), rgb(255, 150, 210) }),
		var("toxic", { rgb(110, 140, 90), rgb(160, 255, 80), rgb(150, 255, 120) }),
		var("night", { rgb(52, 52, 72), rgb(190, 120, 255), rgb(230, 230, 255) }),
	},
	model = function(h: BasePart, c: Paint)
		blob(h, v3(1.4, 0.78, 1.0), c(1), at(0, 1.55, 0.05)) -- masse du nuage
		ball(h, 0.78, c(1), at(-0.58, 1.48, 0.08))
		ball(h, 0.7, c(1), at(0.6, 1.46, 0.06))
		ball(h, 0.74, c(1), at(0.18, 1.86, 0.1))
		ball(h, 0.6, c(1), at(-0.3, 1.84, 0.12))
		local front = blob(h, v3(0.9, 0.56, 0.3), c(1), at(0, 1.52, -0.36)) -- avant du nuage (visage)
		local size = Vector2.new(0.9, 0.56)
		Build.face(front, {
			mark(size, 0.36, 0.44, 0.16, 0.16, WHITE),
			mark(size, 0.64, 0.44, 0.16, 0.16, WHITE),
			mark(size, 0.37, 0.48, 0.07, 0.07, DARK),
			mark(size, 0.63, 0.48, 0.07, 0.07, DARK),
			mark(size, 0.34, 0.24, 0.2, 0.045, DARK, 0.5, 20), -- sourcils froncés
			mark(size, 0.66, 0.24, 0.2, 0.045, DARK, 0.5, -20),
			mark(size, 0.5, 0.74, 0.22, 0.045, DARK, 0.5), -- bouche boudeuse
		}, Enum.NormalId.Front)
		local bolt = { v3(0.42, 1.18, -0.12), v3(0.28, 0.98, -0.12), v3(0.44, 0.9, -0.12), v3(0.3, 0.66, -0.12) }
		for index = 1, #bolt - 1 do -- éclair en zigzag qui vise le sommet du crâne
			bar(h, bolt[index], bolt[index + 1], 0.09, 0.05, c(2), NEON)
		end
		particles(effectZone(h, v3(1.1, 0.06, 0.6), at(0, 1.12, 0.05)), { -- pluie continue
			texture = TEX_SQUARE,
			color = c(3),
			rate = 14,
			lifetime = NumberRange.new(0.35, 0.45),
			speed = NumberRange.new(3, 4),
			size = NumberSequence.new(0.06),
			transparency = NumberSequence.new(0.25),
			lightEmission = 0.2,
			direction = Enum.NormalId.Bottom,
			spread = Vector2.new(4, 4),
			acceleration = v3(0, -10, 0),
		})
	end,
})

-- Auréole lumineuse (défi : réussir un trou en un), sertie de la balle victorieuse.
add({
	id = "head_halo",
	attachment = "HatAttachment",
	rarity = "Legendary",
	price = 0,
	unlock = achievement("ach_hole_in_one"),
	tags = { "crown", "golf", "fx" },
	variants = {
		var("gold", { rgb(255, 214, 90), rgb(255, 240, 170) }),
		var("silver", { rgb(230, 240, 255), rgb(255, 255, 255) }),
		var("rose", { rgb(255, 160, 205), rgb(255, 220, 240) }),
	},
	model = function(h: BasePart, c: Paint)
		local ring = at(0, 1.18, 0.04) * rot(-12, 0, 0) -- bord avant légèrement abaissé
		local radius, count = 0.48, 12
		local length = 2 * math.pi * radius / count * 1.08
		for index = 0, count - 1 do
			local angle = index * 2 * math.pi / count
			local segment = ring * CFrame.new(radius * math.cos(angle), 0, radius * math.sin(angle)) * CFrame.Angles(0, -(angle + math.pi / 2), 0)
			tube(h, length, 0.09, c(1), segment, NEON)
		end
		ball(h, 0.16, WHITE, ring * at(0, 0, -radius)) -- la balle du trou en un
		sparkles(effectZone(h, v3(1.0, 0.12, 1.0), ring), c(2), 5)
	end,
})

return defs
