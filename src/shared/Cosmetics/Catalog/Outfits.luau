--!strict
--[[
	Catalog/Outfits : tenues (emplacement "Outfit") — 1 tenue gratuite par défaut + 20 tenues.

	CONTRAT (Cosmetics/init.luau) : build(variant) -> Folder d'Accessory ; couleurs du corps par le champ
	bodyColors de la définition (CosmeticService les applique au BodyColors du personnage). Les décorations
	(boutons, rayures, cols, capes, ceintures...) sont des Accessory construits par code avec Cosmetics/Build :
	Massless, sans collision ni requête (Build.finalize), aucun script, aucun asset importé.

	REPÈRE DE MODÉLISATION : un Accessory par zone, dont le Handle (invisible) est placé SUR l'attachement R15 :
	  front  BodyFrontAttachment   milieu de la face avant du torse ; -Z = vers l'extérieur, +Y = haut, X = droite
	  back   BodyBackAttachment    milieu de la face arrière ; +Z = vers l'extérieur
	  waist  WaistCenterAttachment centre du bassin (LowerTorso)
	  neck   NeckAttachment        base du cou
	Le torse (UpperTorso) mesure ≈ 2 × 1.6 × 1 ; le bassin ≈ 2 × 0.4 × 1.
	>> À vérifier visuellement dans Studio (étape finale) : les décalages supposent un attachement au centre
	>> de la face concernée ; seuls les décors, pas la couleur du corps, en dépendent.

	Couleurs : variants[v].colors[i] (i = 1 couleur d'accent principale, 2 secondaire, 3 détail) ; noms de
	variantes partagés « cos.sc.col.<couleur> ». Attributs posés sur chaque Accessory : CosmeticId,
	CosmeticSlot ("Outfit"), CosmeticVariant. Les particules portent CosmeticFx = true (coupées en effets réduits).

	Prix : Common ≈ 300, Rare ≈ 600, Epic ≈ 1100, Legendary ≈ 2200. Une tenue se débloque par l'activité
	(10 victoires). Aucun avantage de jeu : apparence uniquement.
]]

local Cosmetics = require(script.Parent.Parent)
local Build = require(script.Parent.Parent.Build)

type CosmeticDef = Cosmetics.CosmeticDef
type Rarity = Cosmetics.Rarity
type Unlock = Cosmetics.Unlock
type Variant = Cosmetics.Variant

type Paint = (index: number, fallback: Color3) -> Color3
type Zones = { front: BasePart, back: BasePart, waist: BasePart, neck: BasePart }
type Body = { [string]: Color3 }

local rgb = Color3.fromRGB
local rad = math.rad
local PLASTIC, FABRIC, METAL, NEON = Enum.Material.SmoothPlastic, Enum.Material.Fabric, Enum.Material.Metal, Enum.Material.Neon
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local ZONES = {
	{ key = "front", name = "Devant", attachment = "BodyFrontAttachment" },
	{ key = "back", name = "Dos", attachment = "BodyBackAttachment" },
	{ key = "waist", name = "Ceinture", attachment = "WaistCenterAttachment" },
	{ key = "neck", name = "Col", attachment = "NeckAttachment" },
}

local function variant(colorKey: string, colors: { Color3 }): Variant
	return { nameKey = "cos.sc.col." .. colorKey, colors = colors }
end

local function put(handle: BasePart, part: BasePart, x: number, y: number, z: number, rotation: CFrame?): BasePart
	return Build.attach(handle, part, CFrame.new(x, y, z) * (rotation or CFrame.identity))
end

local function block(handle: BasePart, x: number, y: number, z: number, sx: number, sy: number, sz: number, color: Color3, material: Enum.Material?, rotation: CFrame?): BasePart
	return put(handle, Build.block(Vector3.new(sx, sy, sz), color, material or FABRIC), x, y, z, rotation)
end

local function ball(handle: BasePart, x: number, y: number, z: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	return put(handle, Build.ball(diameter, color, material or PLASTIC), x, y, z)
end

-- Ellipsoïde (SpecialMesh « Sphere » intégré : aucune ressource externe).
local function ellipsoid(handle: BasePart, x: number, y: number, z: number, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	local part = Build.part({ Name = "Ellipsoide", Size = size, Color = color, Material = material or PLASTIC })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return put(handle, part, x, y, z)
end

-- Rangée de petites billes (fourrure, perles...) sur une ellipse horizontale autour de l'axe Y du Handle.
local function ring(handle: BasePart, y: number, radius: number, count: number, diameter: number, color: Color3, material: Enum.Material?, flatten: number?)
	for index = 1, count do
		local angle = (index - 1) / count * math.pi * 2
		ball(handle, math.cos(angle) * radius, y, math.sin(angle) * radius * (flatten or 1), diameter, color, material)
	end
end

local function sparkle(part: BasePart, color: Color3, rate: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = "Eclat"
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Etincelles"
	emitter.Texture = SPARKLE_TEXTURE
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(0.3, 0.9)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 0.6
	emitter.Parent = attachment
	emitter:SetAttribute("CosmeticFx", true)
end

local function body(torso: Color3, arms: Color3, legs: Color3): Body
	return {
		TorsoColor3 = torso,
		LeftArmColor3 = arms,
		RightArmColor3 = arms,
		LeftLegColor3 = legs,
		RightLegColor3 = legs,
	}
end

type ZoneBuilder = (zones: Zones, col: Paint) -> ()

local function buildFolder(id: string, variants: { Variant }, chosen: number?, builder: ZoneBuilder): Instance
	local folder = Instance.new("Folder")
	folder.Name = "Tenue"
	local function col(index: number, fallback: Color3): Color3
		return Build.color(variants, chosen, index, fallback)
	end
	local accessories: { [string]: Accessory } = {}
	local zones: any = {}
	for _, zone in ZONES do
		local accessory, handle = Build.accessory(zone.name, zone.attachment, Vector3.new(0.2, 0.2, 0.2), Vector3.zero)
		accessory:SetAttribute("CosmeticId", id)
		accessory:SetAttribute("CosmeticSlot", "Outfit")
		accessory:SetAttribute("CosmeticVariant", chosen or 1)
		accessories[zone.key] = accessory
		zones[zone.key] = handle
	end
	builder(zones :: Zones, col)
	for _, zone in ZONES do
		local accessory = accessories[zone.key]
		-- Une zone sans décor n'ajoute aucun Accessory (seul le Handle invisible serait présent).
		if #accessory:GetChildren() > 1 then
			accessory.Parent = folder
		else
			accessory:Destroy()
		end
	end
	return Build.finalize(folder)
end

local function outfit(id: string, rarity: Rarity, price: number, unlock: Unlock, bodyColors: Body, variants: { Variant }, tags: { string }, builder: ZoneBuilder): CosmeticDef
	return {
		id = id,
		slot = "Outfit",
		nameKey = "cos." .. id,
		descKey = "cos." .. id .. ".desc",
		rarity = rarity,
		price = price,
		unlock = unlock,
		variants = variants,
		bodyColors = bodyColors,
		tags = tags,
		build = function(chosen: number?): Instance
			return buildFolder(id, variants, chosen, builder)
		end,
	}
end

local DEFAULT = { kind = "Default" } :: Unlock
local PRICE = { kind = "Price" } :: Unlock

return {
	-- Gratuite ------------------------------------------------------------------------------------
	-- 1 accent (col, bouton, écusson), 2 ceinture.
	outfit("outfit_polo_classic", "Common", 0, DEFAULT, body(rgb(245, 245, 240), rgb(245, 245, 240), rgb(196, 176, 130)), {
		variant("navy", { rgb(35, 55, 110), rgb(95, 70, 45) }),
		variant("red", { rgb(190, 45, 50), rgb(60, 45, 35) }),
	}, { "starter", "golf" }, function(z, col)
		block(z.front, 0, 0.55, -0.04, 0.16, 0.7, 0.07, col(1, rgb(35, 55, 110)))
		ball(z.front, 0.45, 0.4, -0.05, 0.22, col(1, rgb(35, 55, 110)))
		block(z.neck, -0.38, 0.02, -0.18, 0.5, 0.14, 0.34, col(1, rgb(35, 55, 110)), nil, CFrame.Angles(0, rad(-20), 0))
		block(z.neck, 0.38, 0.02, -0.18, 0.5, 0.14, 0.34, col(1, rgb(35, 55, 110)), nil, CFrame.Angles(0, rad(20), 0))
		block(z.waist, 0, 0.05, 0, 2.08, 0.18, 1.08, col(2, rgb(95, 70, 45)), Enum.Material.Leather)
	end),

	-- Communes ------------------------------------------------------------------------------------
	-- 1 rayure A, 2 rayure B.
	outfit("outfit_polo_stripes", "Common", 300, PRICE, body(rgb(250, 250, 250), rgb(250, 250, 250), rgb(60, 70, 95)), {
		variant("green", { rgb(40, 140, 85), rgb(250, 250, 250) }),
		variant("orange", { rgb(235, 130, 40), rgb(35, 45, 75) }),
		variant("sky", { rgb(90, 170, 230), rgb(250, 250, 250) }),
	}, { "golf", "sport" }, function(z, col)
		for index, y in { 0.6, 0.2, -0.2, -0.6 } do
			local color = if index % 2 == 1 then col(1, rgb(40, 140, 85)) else col(2, rgb(250, 250, 250))
			block(z.front, 0, y, -0.04, 2.04, 0.2, 0.08, color)
			block(z.back, 0, y, 0.04, 2.04, 0.2, 0.08, color)
		end
		block(z.neck, 0, 0.02, -0.18, 1.1, 0.14, 0.3, col(1, rgb(40, 140, 85)))
	end),

	-- 1 losange A, 2 losange B.
	outfit("outfit_argyle_vest", "Common", 300, PRICE, body(rgb(236, 222, 190), rgb(236, 222, 190), rgb(120, 125, 140)), {
		variant("royal", { rgb(60, 85, 170), rgb(190, 60, 70) }),
		variant("emerald", { rgb(35, 130, 90), rgb(225, 185, 60) }),
	}, { "golf", "classic" }, function(z, col)
		local diamond = CFrame.Angles(0, 0, rad(45))
		for row = 0, 2 do
			for column = -1, 1 do
				local x = column * 0.6 + (if row % 2 == 1 then 0.3 else 0)
				if math.abs(x) < 0.85 then
					local color = if (row + column) % 2 == 0 then col(1, rgb(60, 85, 170)) else col(2, rgb(190, 60, 70))
					block(z.front, x, 0.5 - row * 0.5, -0.04, 0.32, 0.32, 0.07, color, nil, diamond)
				end
			end
		end
		block(z.neck, 0, -0.02, -0.18, 1.0, 0.16, 0.3, col(1, rgb(60, 85, 170)))
	end),

	-- 1 liseré, 2 ceinture.
	outfit("outfit_tennis_whites", "Common", 300, PRICE, body(rgb(250, 250, 250), rgb(250, 250, 250), rgb(250, 250, 250)), {
		variant("blue", { rgb(50, 100, 200), rgb(250, 220, 80) }),
		variant("red", { rgb(205, 55, 60), rgb(40, 40, 50) }),
	}, { "sport" }, function(z, col)
		block(z.front, -0.92, 0, -0.04, 0.12, 1.6, 0.08, col(1, rgb(50, 100, 200)))
		block(z.front, 0.92, 0, -0.04, 0.12, 1.6, 0.08, col(1, rgb(50, 100, 200)))
		block(z.neck, 0, 0.02, -0.18, 1.1, 0.12, 0.3, col(1, rgb(50, 100, 200)))
		block(z.waist, 0, 0.05, 0, 2.06, 0.14, 1.06, col(2, rgb(250, 220, 80)))
	end),

	-- 1 bandes latérales, 2 fermeture.
	outfit("outfit_tracksuit", "Common", 350, PRICE, body(rgb(40, 60, 120), rgb(40, 60, 120), rgb(40, 60, 120)), {
		variant("white", { rgb(250, 250, 250), rgb(220, 220, 225) }),
		variant("gold", { rgb(235, 195, 70), rgb(250, 250, 250) }),
	}, { "sport" }, function(z, col)
		block(z.front, 0, 0, -0.04, 0.08, 1.6, 0.08, col(2, rgb(220, 220, 225)), METAL)
		block(z.front, -0.97, 0, -0.04, 0.1, 1.6, 0.08, col(1, rgb(250, 250, 250)))
		block(z.front, 0.97, 0, -0.04, 0.1, 1.6, 0.08, col(1, rgb(250, 250, 250)))
		block(z.back, -0.97, 0, 0.04, 0.1, 1.6, 0.08, col(1, rgb(250, 250, 250)))
		block(z.back, 0.97, 0, 0.04, 0.1, 1.6, 0.08, col(1, rgb(250, 250, 250)))
		block(z.neck, 0, 0.05, 0, 1.2, 0.3, 0.9, rgb(40, 60, 120))
	end),

	-- 1 bavette, 2 boutons.
	outfit("outfit_overalls", "Common", 350, PRICE, body(rgb(215, 70, 60), rgb(215, 70, 60), rgb(60, 95, 160)), {
		variant("denim", { rgb(60, 95, 160), rgb(235, 195, 70) }),
		variant("green", { rgb(60, 140, 90), rgb(250, 250, 250) }),
	}, { "work" }, function(z, col)
		block(z.front, 0, -0.1, -0.05, 1.3, 1.1, 0.09, col(1, rgb(60, 95, 160)))
		block(z.front, -0.6, 0.62, -0.05, 0.2, 0.9, 0.09, col(1, rgb(60, 95, 160)))
		block(z.front, 0.6, 0.62, -0.05, 0.2, 0.9, 0.09, col(1, rgb(60, 95, 160)))
		ball(z.front, -0.6, 0.38, -0.12, 0.18, col(2, rgb(235, 195, 70)), METAL)
		ball(z.front, 0.6, 0.38, -0.12, 0.18, col(2, rgb(235, 195, 70)), METAL)
		block(z.front, 0, -0.35, -0.12, 0.7, 0.4, 0.06, col(1, rgb(60, 95, 160)))
		block(z.back, -0.6, 0.62, 0.05, 0.2, 0.9, 0.09, col(1, rgb(60, 95, 160)))
		block(z.back, 0.6, 0.62, 0.05, 0.2, 0.9, 0.09, col(1, rgb(60, 95, 160)))
	end),

	-- Rares ---------------------------------------------------------------------------------------
	-- 1 fleurs A, 2 fleurs B, 3 col.
	outfit("outfit_hawaiian_shirt", "Rare", 600, PRICE, body(rgb(40, 160, 190), rgb(40, 160, 190), rgb(240, 225, 190)), {
		variant("turquoise", { rgb(250, 120, 140), rgb(250, 220, 80), rgb(250, 250, 250) }),
		variant("orange", { rgb(250, 250, 250), rgb(120, 220, 120), rgb(250, 200, 90) }),
	}, { "coast", "silly" }, function(z, col)
		local spots = { { -0.6, 0.5 }, { 0.5, 0.35 }, { -0.2, -0.05 }, { 0.65, -0.5 }, { -0.65, -0.55 } }
		for index, spot in spots do
			local color = if index % 2 == 1 then col(1, rgb(250, 120, 140)) else col(2, rgb(250, 220, 80))
			ball(z.front, spot[1], spot[2], -0.05, 0.42, color)
			ball(z.front, spot[1], spot[2], -0.09, 0.16, col(3, rgb(250, 250, 250)))
			ball(z.back, spot[1], spot[2], 0.05, 0.42, color)
		end
		block(z.neck, -0.4, 0.04, -0.2, 0.55, 0.14, 0.4, col(3, rgb(250, 250, 250)), nil, CFrame.Angles(0, rad(-25), 0))
		block(z.neck, 0.4, 0.04, -0.2, 0.55, 0.14, 0.4, col(3, rgb(250, 250, 250)), nil, CFrame.Angles(0, rad(25), 0))
	end),

	-- 1 croix et short, 2 sifflet.
	outfit("outfit_lifeguard", "Rare", 600, PRICE, body(rgb(235, 190, 150), rgb(235, 190, 150), rgb(215, 55, 50)), {
		variant("red", { rgb(215, 55, 50), rgb(250, 220, 60) }),
		variant("blue", { rgb(50, 110, 200), rgb(250, 250, 250) }),
	}, { "coast" }, function(z, col)
		block(z.front, 0, 0.35, -0.04, 0.9, 0.3, 0.07, col(1, rgb(215, 55, 50)), PLASTIC)
		block(z.front, 0, 0.35, -0.04, 0.3, 0.9, 0.07, col(1, rgb(215, 55, 50)), PLASTIC)
		block(z.front, 0, -0.3, -0.04, 2.0, 0.22, 0.07, col(2, rgb(250, 220, 60)), PLASTIC)
		ball(z.front, 0, -0.1, -0.1, 0.2, col(2, rgb(250, 220, 60)), METAL)
		block(z.waist, 0, 0, 0, 2.08, 0.38, 1.08, col(1, rgb(215, 55, 50)), PLASTIC)
	end),

	-- 1 foulard, 2 boutons.
	outfit("outfit_chef_whites", "Rare", 650, PRICE, body(rgb(252, 252, 252), rgb(252, 252, 252), rgb(90, 90, 100)), {
		variant("red", { rgb(205, 55, 55), rgb(150, 150, 155) }),
		variant("blue", { rgb(60, 110, 200), rgb(235, 195, 70) }),
	}, { "food", "silly" }, function(z, col)
		for _, x in { -0.28, 0.28 } do
			for _, y in { 0.55, 0.15, -0.25 } do
				ball(z.front, x, y, -0.06, 0.2, col(2, rgb(150, 150, 155)), METAL)
			end
		end
		block(z.neck, 0, 0.0, -0.18, 1.0, 0.2, 0.4, col(1, rgb(205, 55, 55)))
		block(z.waist, 0, -0.3, -0.58, 1.5, 1.1, 0.06, rgb(250, 250, 250))
		block(z.waist, 0, 0.05, -0.55, 1.7, 0.12, 0.08, rgb(250, 250, 250))
	end),

	-- 1 stylo et badge, 2 poche.
	outfit("outfit_scientist_coat", "Rare", 650, PRICE, body(rgb(250, 250, 252), rgb(250, 250, 252), rgb(70, 80, 110)), {
		variant("teal", { rgb(60, 170, 170), rgb(235, 90, 90) }),
		variant("violet", { rgb(130, 90, 200), rgb(90, 200, 120) }),
	}, { "silly" }, function(z, col)
		block(z.front, -0.55, -0.55, -0.06, 0.55, 0.45, 0.07, rgb(235, 235, 240))
		block(z.front, 0.55, -0.55, -0.06, 0.55, 0.45, 0.07, rgb(235, 235, 240))
		block(z.front, 0.6, 0.5, -0.06, 0.4, 0.28, 0.06, col(2, rgb(235, 90, 90)))
		block(z.front, -0.55, -0.35, -0.1, 0.08, 0.35, 0.05, col(1, rgb(60, 170, 170)))
		block(z.neck, -0.45, -0.1, -0.2, 0.55, 0.18, 0.4, rgb(250, 250, 252), nil, CFrame.Angles(0, rad(-25), 0))
		block(z.neck, 0.45, -0.1, -0.2, 0.55, 0.18, 0.4, rgb(250, 250, 252), nil, CFrame.Angles(0, rad(25), 0))
		block(z.waist, 0, -0.6, -0.54, 2.0, 0.9, 0.07, rgb(250, 250, 252))
		block(z.waist, 0, -0.6, 0.54, 2.0, 0.9, 0.07, rgb(250, 250, 252))
	end),

	-- 1 gilet, 2 étoile, 3 foulard.
	outfit("outfit_cowboy_vest", "Rare", 650, PRICE, body(rgb(235, 225, 205), rgb(235, 225, 205), rgb(70, 90, 140)), {
		variant("brown", { rgb(130, 85, 50), rgb(235, 195, 70), rgb(200, 50, 50) }),
		variant("black", { rgb(45, 40, 40), rgb(220, 220, 225), rgb(60, 110, 200) }),
	}, { "desert" }, function(z, col)
		block(z.front, -0.58, 0, -0.05, 0.8, 1.6, 0.09, col(1, rgb(130, 85, 50)), Enum.Material.Leather)
		block(z.front, 0.58, 0, -0.05, 0.8, 1.6, 0.09, col(1, rgb(130, 85, 50)), Enum.Material.Leather)
		block(z.front, 0.62, 0.45, -0.13, 0.26, 0.26, 0.05, col(2, rgb(235, 195, 70)), METAL)
		block(z.front, 0.62, 0.45, -0.13, 0.26, 0.26, 0.05, col(2, rgb(235, 195, 70)), METAL, CFrame.Angles(0, 0, rad(45)))
		block(z.waist, 0, 0.05, 0, 2.08, 0.18, 1.08, rgb(75, 55, 40), Enum.Material.Leather)
		block(z.waist, 0, 0.05, -0.56, 0.4, 0.26, 0.06, col(2, rgb(235, 195, 70)), METAL)
		block(z.neck, 0, -0.05, -0.2, 0.7, 0.5, 0.2, col(3, rgb(200, 50, 50)), nil, CFrame.Angles(rad(-35), 0, 0))
	end),

	-- 1 ceinture et foulard, 2 sangles.
	outfit("outfit_ninja_garb", "Rare", 700, PRICE, body(rgb(35, 35, 42), rgb(35, 35, 42), rgb(35, 35, 42)), {
		variant("red", { rgb(200, 45, 50), rgb(55, 55, 65) }),
		variant("gold", { rgb(235, 190, 60), rgb(70, 70, 80) }),
	}, { "stealth" }, function(z, col)
		block(z.front, 0.1, 0, -0.04, 0.2, 2.1, 0.08, col(2, rgb(55, 55, 65)), nil, CFrame.Angles(0, 0, rad(35)))
		block(z.front, -0.1, 0, -0.04, 0.2, 2.1, 0.08, col(2, rgb(55, 55, 65)), nil, CFrame.Angles(0, 0, rad(-35)))
		block(z.waist, 0, 0.05, 0, 2.1, 0.3, 1.1, col(1, rgb(200, 45, 50)))
		block(z.waist, 0.7, -0.45, -0.5, 0.2, 0.8, 0.08, col(1, rgb(200, 45, 50)))
		block(z.neck, 0, 0, 0.1, 1.2, 0.3, 0.9, col(1, rgb(200, 45, 50)))
		block(z.back, -0.4, -0.7, 0.2, 0.3, 1.8, 0.07, col(1, rgb(200, 45, 50)), nil, CFrame.Angles(rad(12), 0, 0))
	end),

	-- 1 manteau, 2 or, 3 écharpe.
	outfit("outfit_pirate_coat", "Rare", 700, PRICE, body(rgb(40, 60, 110), rgb(40, 60, 110), rgb(55, 45, 40)), {
		variant("navy", { rgb(40, 60, 110), rgb(235, 195, 70), rgb(205, 55, 55) }),
		variant("crimson", { rgb(150, 35, 45), rgb(235, 195, 70), rgb(35, 35, 42) }),
	}, { "coast", "pirate" }, function(z, col)
		for _, y in { 0.55, 0.15, -0.25 } do
			ball(z.front, 0, y, -0.07, 0.18, col(2, rgb(235, 195, 70)), METAL)
		end
		block(z.front, -0.55, 0.1, -0.05, 0.14, 1.5, 0.07, col(2, rgb(235, 195, 70)), METAL)
		block(z.front, 0.55, 0.1, -0.05, 0.14, 1.5, 0.07, col(2, rgb(235, 195, 70)), METAL)
		block(z.neck, 0, -0.1, -0.22, 0.7, 0.8, 0.12, rgb(250, 250, 250))
		block(z.waist, 0, 0.05, 0, 2.1, 0.3, 1.1, col(3, rgb(205, 55, 55)))
		block(z.waist, 0, 0.05, -0.57, 0.3, 0.3, 0.06, col(2, rgb(235, 195, 70)), METAL)
		block(z.back, 0, -1.0, 0.1, 1.8, 1.0, 0.08, col(1, rgb(40, 60, 110)))
	end),

	-- 1 cuir, 2 fourrure, 3 métal.
	outfit("outfit_viking_tunic", "Rare", 700, PRICE, body(rgb(130, 90, 55), rgb(130, 90, 55), rgb(90, 70, 55)), {
		variant("brown", { rgb(95, 65, 40), rgb(215, 215, 210), rgb(170, 170, 175) }),
		variant("blue", { rgb(50, 75, 130), rgb(235, 235, 230), rgb(200, 170, 80) }),
	}, { "snow", "viking" }, function(z, col)
		ring(z.neck, 0.02, 0.62, 12, 0.46, col(2, rgb(215, 215, 210)), nil, 0.8)
		block(z.front, 0, -0.45, -0.05, 2.04, 0.18, 0.08, col(1, rgb(95, 65, 40)), Enum.Material.Leather)
		block(z.front, 0, -0.45, -0.1, 0.34, 0.3, 0.05, col(3, rgb(170, 170, 175)), METAL)
		block(z.front, -0.55, 0.45, -0.05, 0.18, 1.0, 0.07, col(1, rgb(95, 65, 40)), Enum.Material.Leather, CFrame.Angles(0, 0, rad(-18)))
		block(z.waist, 0, 0.1, 0, 2.1, 0.22, 1.1, col(1, rgb(95, 65, 40)), Enum.Material.Leather)
	end),

	-- Épiques -------------------------------------------------------------------------------------
	-- 1 voyants, 2 liseré.
	outfit("outfit_astronaut_suit", "Epic", 1100, PRICE, body(rgb(245, 245, 248), rgb(245, 245, 248), rgb(235, 235, 240)), {
		variant("orange", { rgb(250, 130, 40), rgb(60, 110, 200) }),
		variant("teal", { rgb(60, 200, 190), rgb(235, 90, 90) }),
	}, { "space" }, function(z, col)
		block(z.front, 0, 0.1, -0.08, 1.1, 0.8, 0.14, rgb(210, 212, 220), METAL)
		ball(z.front, -0.3, 0.2, -0.17, 0.18, col(1, rgb(250, 130, 40)), NEON)
		ball(z.front, 0, 0.2, -0.17, 0.18, rgb(90, 220, 120), NEON)
		ball(z.front, 0.3, 0.2, -0.17, 0.18, rgb(235, 80, 80), NEON)
		block(z.front, 0, -0.1, -0.17, 0.8, 0.14, 0.04, col(2, rgb(60, 110, 200)))
		block(z.back, 0, 0.1, 0.4, 1.5, 1.7, 0.7, rgb(215, 217, 225), METAL)
		block(z.back, 0.5, -0.9, 0.4, 0.22, 0.3, 0.22, col(1, rgb(250, 130, 40)))
		block(z.back, -0.5, -0.9, 0.4, 0.22, 0.3, 0.22, col(1, rgb(250, 130, 40)))
		put(z.neck, Build.cylinder(0.3, 1.5, rgb(230, 232, 238), METAL), 0, 0.08, 0, Build.UP)
		block(z.waist, 0, 0.05, 0, 2.1, 0.26, 1.1, col(2, rgb(60, 110, 200)))
	end),

	-- 1 acier, 2 cape, 3 or.
	outfit("outfit_knight_armor", "Epic", 1200, PRICE, body(rgb(150, 155, 165), rgb(150, 155, 165), rgb(120, 125, 135)), {
		variant("silver", { rgb(205, 208, 215), rgb(205, 55, 55), rgb(235, 195, 70) }),
		variant("black", { rgb(55, 58, 68), rgb(235, 195, 70), rgb(200, 200, 210) }),
	}, { "armor", "medieval" }, function(z, col)
		ellipsoid(z.front, 0, 0.1, 0.1, Vector3.new(2.1, 1.7, 1.1), col(1, rgb(205, 208, 215)), METAL)
		block(z.front, 0, -0.45, -0.1, 1.5, 0.12, 0.08, col(3, rgb(235, 195, 70)), METAL)
		ellipsoid(z.front, -1.15, 0.7, 0.5, Vector3.new(0.95, 0.7, 1.1), col(1, rgb(205, 208, 215)), METAL)
		ellipsoid(z.front, 1.15, 0.7, 0.5, Vector3.new(0.95, 0.7, 1.1), col(1, rgb(205, 208, 215)), METAL)
		block(z.back, 0, -0.9, 0.12, 1.7, 2.0, 0.07, col(2, rgb(205, 55, 55)))
		for _, x in { -0.65, -0.22, 0.22, 0.65 } do
			block(z.waist, x, -0.35, -0.5, 0.4, 0.6, 0.08, col(1, rgb(205, 208, 215)), METAL)
		end
		block(z.waist, 0, 0.05, 0, 2.1, 0.22, 1.1, col(3, rgb(235, 195, 70)), METAL)
	end),

	-- 1 robe, 2 étoiles, 3 ceinture.
	outfit("outfit_wizard_robe", "Epic", 1200, PRICE, body(rgb(95, 60, 160), rgb(95, 60, 160), rgb(70, 45, 120)), {
		variant("purple", { rgb(95, 60, 160), rgb(250, 220, 80), rgb(235, 195, 70) }),
		variant("night", { rgb(35, 55, 130), rgb(210, 230, 255), rgb(190, 190, 200) }),
	}, { "magic" }, function(z, col)
		local stars = { { -0.55, 0.45 }, { 0.5, 0.15 }, { -0.2, -0.3 }, { 0.6, -0.55 } }
		for _, spot in stars do
			block(z.front, spot[1], spot[2], -0.05, 0.26, 0.26, 0.05, col(2, rgb(250, 220, 80)), NEON)
			block(z.front, spot[1], spot[2], -0.05, 0.26, 0.26, 0.05, col(2, rgb(250, 220, 80)), NEON, CFrame.Angles(0, 0, rad(45)))
		end
		block(z.waist, 0, -0.75, 0, 2.3, 1.3, 1.3, col(1, rgb(95, 60, 160)))
		block(z.waist, 0, 0.05, 0, 2.12, 0.2, 1.12, col(3, rgb(235, 195, 70)), METAL)
		block(z.back, 0, -0.8, 0.14, 1.9, 2.4, 0.07, col(1, rgb(70, 45, 120)))
		block(z.neck, 0, 0.02, 0, 1.5, 0.3, 1.0, col(3, rgb(235, 195, 70)), METAL)
	end),

	-- 1 chemise, 2 nœud.
	outfit("outfit_tuxedo", "Epic", 1100, PRICE, body(rgb(30, 30, 36), rgb(30, 30, 36), rgb(30, 30, 36)), {
		variant("red", { rgb(250, 250, 250), rgb(195, 40, 55) }),
		variant("gold", { rgb(250, 250, 250), rgb(230, 190, 70) }),
	}, { "formal" }, function(z, col)
		block(z.front, 0, 0.1, -0.05, 0.75, 1.4, 0.08, col(1, rgb(250, 250, 250)), PLASTIC)
		for _, y in { 0.45, 0.1, -0.25 } do
			ball(z.front, 0, y, -0.1, 0.12, rgb(30, 30, 36))
		end
		block(z.neck, -0.18, 0, -0.2, 0.3, 0.22, 0.12, col(2, rgb(195, 40, 55)))
		block(z.neck, 0.18, 0, -0.2, 0.3, 0.22, 0.12, col(2, rgb(195, 40, 55)))
		ball(z.neck, 0, 0, -0.2, 0.16, col(2, rgb(195, 40, 55)))
		block(z.waist, 0, 0.05, 0, 2.08, 0.3, 1.08, col(2, rgb(195, 40, 55)), PLASTIC)
		block(z.back, 0, -1.3, 0.1, 1.2, 1.4, 0.07, rgb(30, 30, 36), nil, CFrame.Angles(rad(-8), 0, 0))
	end),

	-- 1 cape, 2 emblème, 3 ceinture.
	outfit("outfit_superhero_cape", "Epic", 1200, PRICE, body(rgb(45, 100, 220), rgb(45, 100, 220), rgb(45, 100, 220)), {
		variant("blue", { rgb(205, 45, 55), rgb(250, 220, 80), rgb(250, 220, 80) }),
		variant("green", { rgb(235, 190, 60), rgb(35, 35, 42), rgb(35, 35, 42) }),
	}, { "hero", "silly" }, function(z, col)
		block(z.front, 0, 0.35, -0.05, 0.95, 0.95, 0.07, col(2, rgb(250, 220, 80)), PLASTIC, CFrame.Angles(0, 0, rad(45)))
		ball(z.front, 0, 0.35, -0.1, 0.4, col(1, rgb(205, 45, 55)))
		block(z.waist, 0, 0.05, 0, 2.1, 0.26, 1.1, col(3, rgb(250, 220, 80)), PLASTIC)
		block(z.back, 0, -1.2, 0.14, 1.9, 3.0, 0.06, col(1, rgb(205, 45, 55)), nil, CFrame.Angles(rad(8), 0, 0))
		block(z.neck, 0, 0.05, 0.2, 1.6, 0.3, 0.5, col(1, rgb(205, 45, 55)))
	end),

	-- Légendaires ---------------------------------------------------------------------------------
	-- 1 velours, 2 fourrure, 3 or.
	outfit("outfit_royal_robe", "Legendary", 2200, PRICE, body(rgb(170, 35, 50), rgb(170, 35, 50), rgb(120, 25, 40)), {
		variant("crimson", { rgb(170, 35, 50), rgb(250, 250, 250), rgb(240, 200, 70) }),
		variant("royal", { rgb(60, 55, 150), rgb(250, 250, 250), rgb(240, 200, 70) }),
	}, { "royal" }, function(z, col)
		ring(z.neck, 0.0, 0.7, 14, 0.5, col(2, rgb(250, 250, 250)), nil, 0.85)
		block(z.front, -0.45, -0.1, -0.06, 0.38, 1.8, 0.08, col(2, rgb(250, 250, 250)))
		block(z.front, 0.45, -0.1, -0.06, 0.38, 1.8, 0.08, col(2, rgb(250, 250, 250)))
		for _, y in { 0.4, -0.1, -0.6 } do
			ball(z.front, -0.45, y, -0.1, 0.12, rgb(30, 30, 36))
			ball(z.front, 0.45, y, -0.1, 0.12, rgb(30, 30, 36))
		end
		for index = -3, 3 do
			ball(z.front, index * 0.22, 0.6 - math.abs(index) * 0.06, -0.12, 0.16, col(3, rgb(240, 200, 70)), METAL)
		end
		block(z.back, 0, -1.5, 0.15, 2.0, 3.6, 0.07, col(1, rgb(170, 35, 50)))
		block(z.back, 0, -3.25, 0.15, 2.0, 0.22, 0.09, col(2, rgb(250, 250, 250)))
		block(z.waist, 0, 0.05, 0, 2.12, 0.24, 1.12, col(3, rgb(240, 200, 70)), METAL)
	end),

	-- 1 or, 2 reflets. Débloquée par 10 victoires.
	outfit("outfit_golden_champion", "Legendary", 0, { kind = "Wins", value = 10 }, body(rgb(235, 190, 60), rgb(235, 190, 60), rgb(215, 170, 45)), {
		variant("gold", { rgb(250, 215, 90), rgb(255, 245, 200) }),
		variant("rose", { rgb(235, 165, 150), rgb(255, 230, 220) }),
	}, { "champion", "fx" }, function(z, col)
		block(z.front, 0, 0.2, -0.06, 1.0, 0.9, 0.1, col(1, rgb(250, 215, 90)), METAL)
		ball(z.front, 0, 0.45, -0.12, 0.4, col(2, rgb(255, 245, 200)), METAL)
		block(z.front, 0, -0.1, -0.12, 0.3, 0.3, 0.06, col(2, rgb(255, 245, 200)), METAL)
		block(z.waist, 0, 0.05, 0, 2.12, 0.3, 1.12, col(1, rgb(250, 215, 90)), METAL)
		block(z.waist, 0, 0.05, -0.58, 0.6, 0.34, 0.08, col(2, rgb(255, 245, 200)), METAL)
		block(z.neck, 0, 0.0, 0, 1.4, 0.26, 0.9, col(1, rgb(250, 215, 90)), METAL)
		block(z.back, 0, -0.9, 0.12, 1.5, 2.0, 0.06, col(1, rgb(250, 215, 90)), METAL)
		sparkle(z.front, col(2, rgb(255, 245, 200)), 6)
		sparkle(z.back, col(2, rgb(255, 245, 200)), 4)
	end),
}
