--!strict
--[[
	Catalog/Shoes : chaussures (emplacement "Shoes") — 1 paire gratuite par défaut + 10 paires.

	Contrat (Cosmetics/init.luau) : build(variant) -> Folder de 2 Accessory dont le Handle porte
	l'attachement LeftFootAttachment / RightFootAttachment. Constructeurs purs : rien n'est parenté au
	DataModel, aucune connexion ; toutes les pièces passent par Build (Massless, sans collision ni requête).

	Repère de construction (Handle d'une chaussure) : origine = centre du DESSOUS du pied, -Z = pointe,
	+Y = haut. Rig R15 par défaut mesuré (13/11/2026) : pied ≈ 1.01 × 0.31 × 1.0, attachement de pied
	en (±0.018, -0.16, -0.05) dans le pied (bas du pied, légèrement en avant), sans rotation.
	Le pied occupe donc X ∈ [-0.5, 0.5], Y ∈ [0, 0.31], Z ∈ [-0.5, 0.5] ; le bas de jambe commence à Y ≈ 0.31.
	`side` vaut -1 pour le pied gauche et +1 pour le droit (côté extérieur = side * X).

	Couleurs : variants[v].colors[i] ; l'usage de chaque indice est indiqué au-dessus de chaque entrée.
]]

local Build = require(script.Parent.Parent.Build)

type Variant = { nameKey: string?, colors: { Color3 } }
type ColorOf = (index: number, fallback: Color3) -> Color3
type ShoeBuilder = (handle: Part, side: number, col: ColorOf) -> ()

local rgb = Color3.fromRGB
local rad = math.rad

-- Position de l'attachement dans le Handle : place l'origine du Handle au centre du dessous du pied.
local FOOT_ATTACHMENT = {
	Left = Vector3.new(0.02, 0, -0.05),
	Right = Vector3.new(-0.02, 0, -0.05),
}
local HANDLE_SIZE = Vector3.new(1, 0.3, 1.2)
local ALONG_Y = Build.UP -- cylindre debout
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local function variant(colorKey: string, colors: { Color3 }): Variant
	return { nameKey = "cos.sc.col." .. colorKey, colors = colors }
end

-- Place `part` à (x, y, z) dans le repère du Handle (rotation facultative) puis la soude.
local function put(handle: BasePart, part: BasePart, x: number, y: number, z: number, rotation: CFrame?): BasePart
	return Build.attach(handle, part, CFrame.new(x, y, z) * (rotation or CFrame.identity))
end

-- Ellipsoïde (SpecialMesh intégré de type Sphere : aucune ressource externe).
local function ellipsoid(size: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Build.part({ Name = "Ellipsoide", Size = size, Color = color, Material = material })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Barre rectangulaire tendue entre deux points du repère du Handle.
local function beam(handle: BasePart, a: Vector3, b: Vector3, thickness: number, color: Color3, material: Enum.Material?): BasePart
	local direction = b - a
	local up = if math.abs(direction.Unit.Y) > 0.98 then Vector3.zAxis else Vector3.yAxis
	local part = Build.block(Vector3.new(thickness, thickness, direction.Magnitude), color, material)
	return Build.attach(handle, part, CFrame.lookAt((a + b) / 2, b, up))
end

-- Petites étincelles douces (texture intégrée, débit faible, aucun clignotement).
local function sparkle(part: BasePart, color: Color3, rate: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = "Eclat"
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Etincelles"
	emitter.Texture = SPARKLE_TEXTURE
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(0.3, 0.8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 0.5
	emitter.Parent = attachment
end

-- Construit la paire : `builder` est appelé pour chaque pied avec son Handle.
local function pair(variants: { Variant }, chosen: number?, builder: ShoeBuilder): Instance
	local folder = Instance.new("Folder")
	folder.Name = "Chaussures"
	local function col(index: number, fallback: Color3): Color3
		return Build.color(variants, chosen, index, fallback)
	end
	for _, sideName in { "Left", "Right" } do
		local accessory, handle = Build.accessory(
			if sideName == "Left" then "ChaussureGauche" else "ChaussureDroite",
			sideName .. "FootAttachment",
			HANDLE_SIZE,
			FOOT_ATTACHMENT[sideName]
		)
		builder(handle, if sideName == "Left" then -1 else 1, col)
		accessory.Parent = folder
	end
	return Build.finalize(folder)
end

type ShoeDef = {
	id: string,
	slot: "Shoes",
	nameKey: string,
	descKey: string,
	rarity: "Common" | "Rare" | "Epic" | "Legendary",
	price: number,
	unlock: { kind: string, value: any? },
	variants: { Variant },
	tags: { string },
	build: (variant: number?) -> Instance,
}

local function shoe(
	id: string,
	rarity: "Common" | "Rare" | "Epic" | "Legendary",
	price: number,
	unlock: { kind: string, value: any? },
	variants: { Variant },
	tags: { string },
	builder: ShoeBuilder
): ShoeDef
	return {
		id = id,
		slot = "Shoes",
		nameKey = "cos." .. id,
		descKey = "cos." .. id .. ".desc",
		rarity = rarity,
		price = price,
		unlock = unlock,
		variants = variants,
		tags = tags,
		build = function(chosen: number?): Instance
			return pair(variants, chosen, builder)
		end,
	}
end

local PRICE = { kind = "Price" }

return {
	-- Gratuite. 1 tige, 2 semelle et selle, 3 lacets.
	shoe("shoes_classic", "Common", 0, { kind = "Default" }, {
		variant("white", { rgb(245, 245, 240), rgb(35, 45, 75), rgb(250, 250, 250) }),
		variant("black", { rgb(40, 40, 45), rgb(235, 235, 230), rgb(30, 30, 30) }),
	}, { "starter" }, function(handle, _side, col)
		put(handle, Build.block(Vector3.new(1.12, 0.1, 1.16), col(2, rgb(35, 45, 75))), 0, 0.01, -0.03)
		put(handle, Build.block(Vector3.new(1.08, 0.3, 1.04), col(1, rgb(245, 245, 240))), 0, 0.2, 0.02)
		put(handle, Build.cylinder(1.08, 0.34, col(1, rgb(245, 245, 240))), 0, 0.18, -0.5)
		put(handle, Build.block(Vector3.new(1.1, 0.31, 0.34), col(2, rgb(35, 45, 75))), 0, 0.205, -0.05)
		put(handle, Build.block(Vector3.new(0.42, 0.05, 0.42), col(3, rgb(250, 250, 250))), 0, 0.37, -0.22)
	end),

	-- Pantoufles lapin. 1 fourrure, 2 intérieur des oreilles et museau, 3 yeux.
	shoe("shoes_bunny_slippers", "Common", 180, PRICE, {
		variant("pink", { rgb(255, 196, 214), rgb(255, 120, 160), rgb(30, 30, 35) }),
		variant("white", { rgb(250, 250, 250), rgb(255, 160, 185), rgb(30, 30, 35) }),
		variant("grey", { rgb(170, 170, 178), rgb(255, 170, 190), rgb(20, 20, 25) }),
	}, { "cute" }, function(handle, side, col)
		local fur = col(1, rgb(255, 196, 214))
		local inner = col(2, rgb(255, 120, 160))
		put(handle, ellipsoid(Vector3.new(1.22, 0.56, 1.38), fur, Enum.Material.Fabric), 0, 0.2, -0.04)
		for _, x in { -0.2, 0.2 } do
			local tilt = CFrame.Angles(rad(-12), 0, rad(if x < 0 then 14 else -14))
			put(handle, ellipsoid(Vector3.new(0.22, 0.72, 0.12), fur, Enum.Material.Fabric), x, 0.66, -0.22, tilt)
			put(handle, ellipsoid(Vector3.new(0.12, 0.5, 0.06), inner, Enum.Material.Fabric), x, 0.64, -0.27, tilt)
			put(handle, Build.ball(0.14, col(3, rgb(30, 30, 35))), x, 0.36, -0.6)
		end
		put(handle, Build.ball(0.16, inner), 0, 0.27, -0.7)
		put(handle, Build.ball(0.3, rgb(255, 255, 255), Enum.Material.Fabric), side * 0.05, 0.26, 0.66)
	end),

	-- Bottes de pluie. 1 caoutchouc, 2 semelle et revers.
	shoe("shoes_rain_boots", "Common", 200, PRICE, {
		variant("yellow", { rgb(255, 205, 40), rgb(120, 80, 40) }),
		variant("red", { rgb(210, 40, 45), rgb(250, 250, 250) }),
		variant("green", { rgb(60, 140, 70), rgb(45, 40, 35) }),
		variant("navy", { rgb(35, 50, 100), rgb(240, 200, 60) }),
	}, { "weather" }, function(handle, _side, col)
		local rubber = col(1, rgb(255, 205, 40))
		local trim = col(2, rgb(120, 80, 40))
		put(handle, Build.block(Vector3.new(1.14, 0.1, 1.2), trim), 0, 0.01, -0.04)
		put(handle, Build.block(Vector3.new(1.1, 0.32, 1.08), rubber), 0, 0.2, 0.02)
		put(handle, Build.cylinder(1.1, 0.36, rubber), 0, 0.2, -0.5)
		put(handle, Build.block(Vector3.new(1.1, 0.62, 1.06), rubber), 0, 0.66, 0.04)
		put(handle, Build.block(Vector3.new(1.18, 0.14, 1.14), trim), 0, 0.98, 0.04)
	end),

	-- Tongs de plage. 1 semelle, 2 lanière, 3 pétales, 4 cœur de fleur.
	shoe("shoes_flip_flops", "Common", 160, PRICE, {
		variant("turquoise", { rgb(60, 200, 200), rgb(255, 255, 255), rgb(255, 120, 170), rgb(255, 220, 60) }),
		variant("orange", { rgb(255, 150, 50), rgb(60, 60, 70), rgb(255, 255, 255), rgb(255, 200, 40) }),
		variant("purple", { rgb(150, 90, 200), rgb(255, 230, 120), rgb(120, 220, 255), rgb(255, 255, 255) }),
	}, { "summer" }, function(handle, side, col)
		local strap = col(2, rgb(255, 255, 255))
		put(handle, Build.block(Vector3.new(1.06, 0.08, 1.28), col(1, rgb(60, 200, 200)), Enum.Material.Fabric), 0, 0, -0.06)
		local post = Vector3.new(0, 0.33, -0.36)
		beam(handle, post, Vector3.new(-0.53, 0.18, 0.08), 0.09, strap)
		beam(handle, post, Vector3.new(0.53, 0.18, 0.08), 0.09, strap)
		beam(handle, Vector3.new(0, 0.04, -0.36), post, 0.07, strap)
		local petals = col(3, rgb(255, 120, 170))
		local center = Vector3.new(side * 0.12, 0.38, -0.38)
		for i = 0, 3 do
			local angle = rad(45 + i * 90)
			put(handle, Build.ball(0.13, petals), center.X + math.cos(angle) * 0.08, center.Y + math.sin(angle) * 0.08, center.Z)
		end
		put(handle, Build.ball(0.1, col(4, rgb(255, 220, 60))), center.X, center.Y, center.Z - 0.04)
	end),

	-- Baskets montantes. 1 toile, 2 pastille, 3 caoutchouc et lacets.
	shoe("shoes_high_tops", "Common", 240, PRICE, {
		variant("red", { rgb(200, 35, 45), rgb(255, 255, 255), rgb(245, 245, 240) }),
		variant("black", { rgb(30, 30, 35), rgb(255, 210, 50), rgb(245, 245, 240) }),
		variant("sky", { rgb(110, 180, 240), rgb(255, 110, 150), rgb(250, 250, 250) }),
	}, { "sport" }, function(handle, side, col)
		local canvas = col(1, rgb(200, 35, 45))
		local rubber = col(3, rgb(245, 245, 240))
		put(handle, Build.block(Vector3.new(1.14, 0.13, 1.2), rubber), 0, 0.02, -0.04)
		put(handle, Build.block(Vector3.new(1.08, 0.3, 1.06), canvas, Enum.Material.Fabric), 0, 0.22, 0.02)
		put(handle, Build.cylinder(1.1, 0.32, rubber), 0, 0.2, -0.5)
		put(handle, Build.block(Vector3.new(1.08, 0.46, 0.98), canvas, Enum.Material.Fabric), 0, 0.58, 0.06)
		put(handle, Build.cylinder(0.06, 0.34, col(2, rgb(255, 255, 255))), side * 0.56, 0.58, 0.12)
		for i = 0, 2 do
			put(handle, Build.block(Vector3.new(0.5, 0.05, 0.07), rubber), 0, 0.4 + i * 0.16, -0.46 + i * 0.03)
		end
	end),

	-- Chaussures de clown. 1 cuir, 2 semelle, 3 lacets et pompon.
	shoe("shoes_clown", "Rare", 450, PRICE, {
		variant("red", { rgb(220, 30, 40), rgb(255, 215, 40), rgb(60, 140, 255) }),
		variant("green", { rgb(60, 190, 80), rgb(255, 120, 40), rgb(255, 255, 255) }),
		variant("blue", { rgb(50, 110, 230), rgb(255, 255, 255), rgb(255, 80, 160) }),
	}, { "funny" }, function(handle, _side, col)
		local leather = col(1, rgb(220, 30, 40))
		local accent = col(3, rgb(60, 140, 255))
		put(handle, Build.block(Vector3.new(1.16, 0.12, 1.9), col(2, rgb(255, 215, 40))), 0, 0.02, -0.4)
		put(handle, Build.block(Vector3.new(1.12, 0.34, 1.2), leather), 0, 0.22, 0)
		put(handle, ellipsoid(Vector3.new(1.4, 0.66, 1.0), leather), 0, 0.3, -0.95)
		put(handle, Build.ball(0.22, accent), -0.18, 0.42, -0.42)
		put(handle, Build.ball(0.22, accent), 0.18, 0.42, -0.42)
		put(handle, Build.ball(0.3, accent, Enum.Material.Fabric), 0, 0.62, -1.0)
	end),

	-- Bottes de cowboy. 1 cuir, 2 talon et surpiqûres, 3 éperon.
	shoe("shoes_cowboy", "Rare", 550, PRICE, {
		variant("brown", { rgb(140, 85, 45), rgb(70, 40, 20), rgb(200, 200, 205) }),
		variant("black", { rgb(35, 30, 30), rgb(190, 40, 40), rgb(215, 180, 80) }),
		variant("white", { rgb(240, 235, 225), rgb(60, 120, 200), rgb(200, 200, 205) }),
	}, { "western" }, function(handle, _side, col)
		local leather = col(1, rgb(140, 85, 45))
		local accent = col(2, rgb(70, 40, 20))
		local metal = col(3, rgb(200, 200, 205))
		put(handle, Build.block(Vector3.new(1.1, 0.34, 1.0), leather), 0, 0.17, 0.06)
		put(handle, Build.wedge(Vector3.new(0.9, 0.3, 0.55), leather), 0, 0.15, -0.71)
		put(handle, Build.block(Vector3.new(0.7, 0.14, 0.3), accent), 0, 0.02, -0.45)
		put(handle, Build.block(Vector3.new(0.9, 0.24, 0.32), accent), 0, 0.02, 0.4)
		put(handle, Build.block(Vector3.new(1.08, 0.66, 1.0), leather), 0, 0.66, 0.08)
		put(handle, Build.block(Vector3.new(1.12, 0.08, 1.04), accent), 0, 0.84, 0.08)
		beam(handle, Vector3.new(-0.4, 0.22, 0.56), Vector3.new(0.4, 0.22, 0.56), 0.06, metal, Enum.Material.Metal)
		put(handle, Build.cylinder(0.05, 0.26, metal, Enum.Material.Metal), 0, 0.22, 0.72, CFrame.Angles(0, rad(90), 0))
	end),

	-- Après-ski moelleux. 1 doudoune, 2 fourrure, 3 sangles.
	shoe("shoes_moon_boots", "Rare", 500, PRICE, {
		variant("silver", { rgb(200, 205, 215), rgb(255, 255, 255), rgb(60, 70, 90) }),
		variant("pink", { rgb(255, 130, 190), rgb(255, 245, 250), rgb(120, 40, 90) }),
		variant("orange", { rgb(255, 140, 40), rgb(250, 245, 230), rgb(40, 40, 50) }),
	}, { "winter" }, function(handle, _side, col)
		local puffy = col(1, rgb(200, 205, 215))
		local strap = col(3, rgb(60, 70, 90))
		put(handle, Build.block(Vector3.new(1.3, 0.12, 1.42), strap), 0, 0.01, -0.06)
		put(handle, ellipsoid(Vector3.new(1.36, 0.62, 1.48), puffy, Enum.Material.Fabric), 0, 0.26, -0.06)
		put(handle, ellipsoid(Vector3.new(1.26, 0.86, 1.2), puffy, Enum.Material.Fabric), 0, 0.68, 0.06)
		put(handle, ellipsoid(Vector3.new(1.42, 0.32, 1.34), col(2, rgb(255, 255, 255)), Enum.Material.Fabric), 0, 1.06, 0.06)
		put(handle, Build.block(Vector3.new(1.3, 0.1, 0.16), strap), 0, 0.5, -0.44)
		put(handle, Build.block(Vector3.new(1.24, 0.1, 0.16), strap), 0, 0.78, -0.5)
	end),

	-- Pattes de dino. 1 écailles, 2 taches et crête, 3 griffes.
	shoe("shoes_dino_feet", "Epic", 1000, PRICE, {
		variant("green", { rgb(90, 180, 70), rgb(40, 110, 40), rgb(250, 248, 235) }),
		variant("purple", { rgb(140, 80, 200), rgb(255, 200, 60), rgb(250, 248, 235) }),
		variant("orange", { rgb(240, 130, 40), rgb(120, 50, 20), rgb(255, 255, 255) }),
	}, { "monster" }, function(handle, side, col)
		local scales = col(1, rgb(90, 180, 70))
		local spots = col(2, rgb(40, 110, 40))
		local claw = col(3, rgb(250, 248, 235))
		put(handle, ellipsoid(Vector3.new(1.32, 0.62, 1.56), scales), 0, 0.25, -0.1)
		put(handle, ellipsoid(Vector3.new(1.16, 0.4, 1.06), scales), 0, 0.56, 0.08)
		for _, x in { -0.38, 0, 0.38 } do
			put(handle, ellipsoid(Vector3.new(0.2, 0.2, 0.42), claw), x, 0.14, -0.86, CFrame.Angles(rad(12), 0, 0))
		end
		put(handle, Build.ball(0.2, spots), side * 0.3, 0.48, -0.3)
		put(handle, Build.ball(0.15, spots), side * -0.15, 0.52, -0.45)
		put(handle, Build.wedge(Vector3.new(0.12, 0.32, 0.36), spots), 0, 0.55, 0.62, CFrame.Angles(0, rad(180), 0))
	end),

	-- Godillots du globe-trotteur (défi « Globe-trotteur »). 1 cuir, 2 coque et col, 3 semelle, 4 lacets.
	shoe("shoes_hiking", "Epic", 0, { kind = "Achievement", value = "ach_all_biomes" }, {
		variant("brown", { rgb(150, 95, 55), rgb(90, 55, 30), rgb(45, 40, 38), rgb(210, 40, 40) }),
		variant("olive", { rgb(110, 115, 60), rgb(60, 62, 35), rgb(35, 35, 35), rgb(255, 170, 30) }),
	}, { "explorer" }, function(handle, side, col)
		local leather = col(1, rgb(150, 95, 55))
		local dark = col(2, rgb(90, 55, 30))
		local lace = col(4, rgb(210, 40, 40))
		put(handle, Build.block(Vector3.new(1.16, 0.15, 1.24), col(3, rgb(45, 40, 38))), 0, 0.02, -0.04)
		put(handle, Build.block(Vector3.new(1.08, 0.32, 1.06), leather, Enum.Material.Leather), 0, 0.24, 0.02)
		put(handle, Build.cylinder(1.1, 0.36, dark, Enum.Material.Leather), 0, 0.22, -0.5)
		local shaft = put(handle, Build.block(Vector3.new(1.06, 0.5, 0.98), leather, Enum.Material.Leather), 0, 0.62, 0.06)
		put(handle, Build.block(Vector3.new(1.12, 0.14, 1.04), dark, Enum.Material.Fabric), 0, 0.9, 0.06)
		for i = 0, 2 do
			put(handle, Build.block(Vector3.new(0.56, 0.05, 0.06), lace), 0, 0.42 + i * 0.16, -0.49 + i * 0.04)
		end
		-- Écussons des cinq biomes (côte, forêt, désert, neige, ville) dessinés sur le côté extérieur.
		local badges = {}
		for index, color in { rgb(60, 150, 230), rgb(50, 150, 60), rgb(235, 195, 110), rgb(250, 250, 255), rgb(130, 130, 140) } do
			table.insert(badges, {
				position = UDim2.fromScale(0.16 + (index - 1) * 0.17, 0.5),
				size = UDim2.fromScale(0.13, 0.26),
				color = color,
				corner = 1,
			})
		end
		Build.face(shaft, badges, if side < 0 then Enum.NormalId.Left else Enum.NormalId.Right)
	end),

	-- Pantoufles royales. 1 velours, 2 joyau, 3 or, 4 hermine.
	shoe("shoes_royal_slippers", "Legendary", 2000, PRICE, {
		variant("crimson", { rgb(170, 20, 50), rgb(60, 200, 255), rgb(255, 205, 60), rgb(255, 255, 250) }),
		variant("royal", { rgb(60, 40, 160), rgb(255, 60, 120), rgb(255, 205, 60), rgb(255, 255, 250) }),
		variant("emerald", { rgb(20, 120, 80), rgb(255, 230, 90), rgb(235, 235, 240), rgb(255, 255, 250) }),
	}, { "royal" }, function(handle, side, col)
		local velvet = col(1, rgb(170, 20, 50))
		local gold = col(3, rgb(255, 205, 60))
		local ermine = col(4, rgb(255, 255, 250))
		put(handle, Build.block(Vector3.new(1.1, 0.08, 1.24), gold, Enum.Material.Metal), 0, 0, -0.04)
		put(handle, ellipsoid(Vector3.new(1.16, 0.46, 1.36), velvet, Enum.Material.Fabric), 0, 0.2, -0.06)
		put(handle, ellipsoid(Vector3.new(1.22, 0.2, 0.92), ermine, Enum.Material.Fabric), 0, 0.38, 0.16)
		put(handle, Build.ball(0.07, rgb(20, 20, 20)), side * 0.35, 0.47, 0.12)
		put(handle, Build.ball(0.07, rgb(20, 20, 20)), side * -0.2, 0.48, 0.3)
		put(handle, ellipsoid(Vector3.new(0.34, 0.26, 0.4), velvet, Enum.Material.Fabric), 0, 0.26, -0.78, CFrame.Angles(rad(-25), 0, 0))
		put(handle, ellipsoid(Vector3.new(0.2, 0.2, 0.3), velvet, Enum.Material.Fabric), 0, 0.42, -0.94, CFrame.Angles(rad(-60), 0, 0))
		put(handle, Build.ball(0.18, gold, Enum.Material.Metal), 0, 0.56, -0.96)
		local jewel = put(handle, Build.ball(0.18, col(2, rgb(60, 200, 255)), Enum.Material.Neon), 0, 0.4, -0.44)
		sparkle(jewel, gold, 3)
	end),
}
