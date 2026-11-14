--!strict
--[[
	Catalog/Clubs : clubs de golf (emplacement "Club") — 1 club gratuit par défaut + 15 clubs.

	CONTRAT (Cosmetics/init.luau) : build(variant) -> Model dont le PrimaryPart "Handle" porte l'Attachment "Grip".
	CosmeticService soude le Handle à la main droite (alignement Grip <-> RightGripAttachment).

	REPÈRE DE MODÉLISATION (repère du Handle ; convention lue par AnimationController pour réorienter le manche)
	  origine   = centre de la poignée (là où la main serre) ; Grip est à l'origine, sans rotation
	  -Y        = le manche descend vers la tête (la tête est TOUJOURS en bas : y ≈ -3.5)
	  -Z        = FACE DE FRAPPE (la normale de la face regarde vers -Z) ; la tête dépasse du manche vers +X (pointe)
	Poignée de y = +0.45 à y = -0.45 ; manche de y = -0.45 à y = -3.3 ; tête entre y ≈ -3.25 et y ≈ -3.85.
	Longueur totale ≈ 4.3 studs pour TOUS les clubs : la portée ne dépend jamais du skin (Cosmetics.spec vérifie
	que le plus grand côté reste dans [2.6, 4.6]).

	ÉQUITÉ : toute pièce passe par Build (Massless, sans collision, sans requête, sans contact), aucun script ; les
	particules portent CosmeticFx = true (coupées en effets réduits). Un club ne change ni la puissance ni la visée.

	Couleurs : variants[v].colors[i] (1 tête / matière principale, 2 accent, 3 poignée) ; noms de variantes
	partagés « cos.sc.col.<couleur> ». Prix : Common ≈ 300, Rare ≈ 600, Epic ≈ 1100, Legendary ≈ 2400.
]]

local Cosmetics = require(script.Parent.Parent)
local Build = require(script.Parent.Parent.Build)

type CosmeticDef = Cosmetics.CosmeticDef
type Rarity = Cosmetics.Rarity
type Unlock = Cosmetics.Unlock
type Variant = Cosmetics.Variant

type Paint = (index: number, fallback: Color3) -> Color3
type ClubBuilder = (handle: BasePart, col: Paint) -> ()

local rgb = Color3.fromRGB
local rad = math.rad
local PLASTIC, METAL, WOOD, NEON, LEATHER = Enum.Material.SmoothPlastic, Enum.Material.Metal, Enum.Material.Wood, Enum.Material.Neon, Enum.Material.Leather
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local GRIP_TOP, GRIP_BOTTOM = 0.45, -0.45
local SHAFT_BOTTOM = -3.3
local HEAD_Y = -3.55

local function variant(colorKey: string, colors: { Color3 }): Variant
	return { nameKey = "cos.sc.col." .. colorKey, colors = colors }
end

local function put(handle: BasePart, part: BasePart, x: number, y: number, z: number, rotation: CFrame?): BasePart
	return Build.attach(handle, part, CFrame.new(x, y, z) * (rotation or CFrame.identity))
end

local function block(handle: BasePart, x: number, y: number, z: number, sx: number, sy: number, sz: number, color: Color3, material: Enum.Material?, rotation: CFrame?): BasePart
	return put(handle, Build.block(Vector3.new(sx, sy, sz), color, material or PLASTIC), x, y, z, rotation)
end

local function ball(handle: BasePart, x: number, y: number, z: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	return put(handle, Build.ball(diameter, color, material or PLASTIC), x, y, z)
end

local function ellipsoid(handle: BasePart, x: number, y: number, z: number, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	local part = Build.part({ Name = "Ellipsoide", Size = size, Color = color, Material = material or PLASTIC })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return put(handle, part, x, y, z)
end

-- Cylindre vertical entre deux hauteurs (y0 au-dessus de y1) à l'abscisse x, profondeur z.
local function seg(handle: BasePart, y0: number, y1: number, diameter: number, color: Color3, material: Enum.Material?, x: number?, z: number?): BasePart
	return put(handle, Build.cylinder(y0 - y1, diameter, color, material or PLASTIC), x or 0, (y0 + y1) / 2, z or 0, Build.UP)
end

-- Poignée et manche standard.
local function gripAndShaft(handle: BasePart, gripColor: Color3, shaftColor: Color3, thickness: number?, shaftMaterial: Enum.Material?)
	seg(handle, GRIP_TOP, GRIP_BOTTOM, 0.27, gripColor, LEATHER)
	seg(handle, GRIP_BOTTOM, SHAFT_BOTTOM, thickness or 0.12, shaftColor, shaftMaterial or METAL)
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

local function buildClub(id: string, variants: { Variant }, chosen: number?, builder: ClubBuilder): Instance
	local model = Instance.new("Model")
	model.Name = "Club"
	local handle = Build.part({ Name = "Handle", Size = Vector3.new(0.24, 0.24, 0.24), Transparency = 1 })
	handle.Parent = model
	local grip = Instance.new("Attachment")
	grip.Name = "Grip"
	grip.Parent = handle
	model.PrimaryPart = handle
	model:SetAttribute("CosmeticId", id)
	model:SetAttribute("CosmeticSlot", "Club")
	model:SetAttribute("CosmeticVariant", chosen or 1)
	local function col(index: number, fallback: Color3): Color3
		return Build.color(variants, chosen, index, fallback)
	end
	builder(handle, col)
	return Build.finalize(model)
end

local function club(id: string, rarity: Rarity, price: number, unlock: Unlock, variants: { Variant }, tags: { string }, builder: ClubBuilder): CosmeticDef
	return {
		id = id,
		slot = "Club",
		nameKey = "cos." .. id,
		descKey = "cos." .. id .. ".desc",
		rarity = rarity,
		price = price,
		unlock = unlock,
		variants = variants,
		tags = tags,
		build = function(chosen: number?): Instance
			return buildClub(id, variants, chosen, builder)
		end,
	}
end

local DEFAULT = { kind = "Default" } :: Unlock
local PRICE = { kind = "Price" } :: Unlock

return {
	-- Gratuit -------------------------------------------------------------------------------------
	-- 1 tête, 2 semelle, 3 poignée.
	club("club_classic_iron", "Common", 0, DEFAULT, {
		variant("silver", { rgb(200, 204, 212), rgb(120, 125, 135), rgb(35, 35, 40) }),
		variant("black", { rgb(55, 58, 66), rgb(200, 204, 212), rgb(190, 45, 50) }),
	}, { "starter", "golf" }, function(h, col)
		gripAndShaft(h, col(3, rgb(35, 35, 40)), rgb(185, 190, 198))
		seg(h, -3.15, -3.4, 0.17, col(1, rgb(200, 204, 212)), METAL)
		block(h, 0.32, HEAD_Y, 0, 0.9, 0.5, 0.14, col(1, rgb(200, 204, 212)), METAL)
		block(h, 0.32, HEAD_Y - 0.28, 0.02, 0.9, 0.08, 0.2, col(2, rgb(120, 125, 135)), METAL)
		for _, y in { -3.45, -3.55, -3.65 } do
			block(h, 0.32, y, -0.08, 0.7, 0.03, 0.02, col(2, rgb(120, 125, 135)), METAL)
		end
	end),

	-- Communs --------------------------------------------------------------------------------------
	-- 1 tête, 2 face, 3 poignée.
	club("club_driver_pro", "Common", 300, PRICE, {
		variant("black", { rgb(40, 42, 50), rgb(205, 55, 55), rgb(205, 55, 55) }),
		variant("white", { rgb(240, 240, 244), rgb(50, 100, 200), rgb(50, 100, 200) }),
	}, { "golf" }, function(h, col)
		gripAndShaft(h, col(3, rgb(205, 55, 55)), rgb(70, 75, 85), 0.12, METAL)
		ellipsoid(h, 0.3, HEAD_Y + 0.05, 0.1, Vector3.new(1.15, 0.78, 1.0), col(1, rgb(40, 42, 50)), METAL)
		block(h, 0.3, HEAD_Y, -0.38, 0.8, 0.4, 0.05, col(2, rgb(205, 55, 55)), METAL)
		block(h, 0.3, HEAD_Y + 0.38, 0.1, 0.5, 0.05, 0.5, col(2, rgb(205, 55, 55)))
	end),

	-- 1 bois, 2 laiton, 3 poignée.
	club("club_oak_wood", "Common", 300, PRICE, {
		variant("oak", { rgb(150, 100, 55), rgb(215, 175, 70), rgb(95, 60, 35) }),
		variant("dark", { rgb(80, 52, 35), rgb(190, 190, 195), rgb(35, 35, 40) }),
	}, { "classic" }, function(h, col)
		gripAndShaft(h, col(3, rgb(95, 60, 35)), col(1, rgb(150, 100, 55)), 0.14, WOOD)
		ellipsoid(h, 0.3, HEAD_Y + 0.02, 0.08, Vector3.new(1.05, 0.7, 0.8), col(1, rgb(150, 100, 55)), WOOD)
		block(h, 0.3, HEAD_Y - 0.3, 0.08, 0.8, 0.06, 0.6, col(2, rgb(215, 175, 70)), METAL)
		block(h, 0.3, HEAD_Y, -0.34, 0.5, 0.35, 0.04, col(2, rgb(215, 175, 70)), METAL)
	end),

	-- 1 bambou, 2 nœuds, 3 poignée.
	club("club_bamboo_stick", "Common", 300, PRICE, {
		variant("green", { rgb(120, 170, 75), rgb(85, 130, 50), rgb(235, 225, 190) }),
		variant("gold", { rgb(215, 185, 95), rgb(165, 130, 55), rgb(120, 75, 45) }),
	}, { "forest", "nature" }, function(h, col)
		seg(h, GRIP_TOP, GRIP_BOTTOM, 0.27, col(3, rgb(235, 225, 190)), Enum.Material.Fabric)
		seg(h, GRIP_BOTTOM, SHAFT_BOTTOM, 0.17, col(1, rgb(120, 170, 75)), WOOD)
		for _, y in { -0.9, -1.7, -2.5, -3.2 } do
			seg(h, y + 0.04, y - 0.04, 0.23, col(2, rgb(85, 130, 50)), WOOD)
		end
		block(h, 0.3, HEAD_Y, 0, 0.95, 0.5, 0.3, col(1, rgb(120, 170, 75)), WOOD)
		block(h, 0.3, HEAD_Y, -0.17, 0.95, 0.12, 0.04, col(2, rgb(85, 130, 50)), WOOD)
	end),

	-- 1 tête, 2 bande, 3 poignée.
	club("club_mallet_putter", "Common", 350, PRICE, {
		variant("steel", { rgb(175, 180, 190), rgb(205, 55, 55), rgb(40, 40, 46) }),
		variant("copper", { rgb(205, 125, 80), rgb(40, 40, 46), rgb(40, 40, 46) }),
	}, { "golf", "putter" }, function(h, col)
		gripAndShaft(h, col(3, rgb(40, 40, 46)), rgb(160, 165, 175), 0.12, METAL)
		put(h, Build.cylinder(1.1, 0.6, col(1, rgb(175, 180, 190)), METAL), 0.3, HEAD_Y + 0.1, 0.05)
		block(h, 0.3, HEAD_Y + 0.1, -0.31, 0.7, 0.18, 0.03, col(2, rgb(205, 55, 55)), METAL)
	end),

	-- Rares ----------------------------------------------------------------------------------------
	-- 1 rouge, 2 blanc, 3 poignée.
	club("club_candy_cane", "Rare", 600, PRICE, {
		variant("classic", { rgb(215, 45, 55), rgb(250, 250, 250), rgb(250, 250, 250) }),
		variant("mint", { rgb(60, 185, 140), rgb(250, 250, 250), rgb(250, 250, 250) }),
	}, { "snow", "food", "silly" }, function(h, col)
		seg(h, GRIP_TOP, GRIP_BOTTOM, 0.27, col(3, rgb(250, 250, 250)), PLASTIC)
		local y = GRIP_BOTTOM
		local index = 0
		while y > SHAFT_BOTTOM + 0.01 do
			local nextY = math.max(y - 0.3, SHAFT_BOTTOM)
			seg(h, y, nextY, 0.17, if index % 2 == 0 then col(1, rgb(215, 45, 55)) else col(2, rgb(250, 250, 250)), PLASTIC)
			y = nextY
			index += 1
		end
		block(h, 0.18, -3.5, 0, 0.17, 0.5, 0.17, col(1, rgb(215, 45, 55)))
		block(h, 0.55, -3.74, 0, 0.7, 0.17, 0.17, col(2, rgb(250, 250, 250)))
		block(h, 0.85, -3.6, 0, 0.17, 0.4, 0.17, col(1, rgb(215, 45, 55)))
		block(h, 0.55, -3.74, -0.12, 0.7, 0.14, 0.04, col(1, rgb(215, 45, 55)))
	end),

	-- 1 poêle, 2 bord, 3 poignée.
	club("club_frying_pan", "Rare", 650, PRICE, {
		variant("black", { rgb(48, 48, 54), rgb(215, 130, 55), rgb(95, 60, 35) }),
		variant("copper", { rgb(195, 115, 70), rgb(240, 200, 150), rgb(60, 40, 30) }),
	}, { "food", "silly" }, function(h, col)
		gripAndShaft(h, col(3, rgb(95, 60, 35)), rgb(150, 155, 165), 0.13, METAL)
		put(h, Build.cylinder(0.12, 1.1, col(1, rgb(48, 48, 54)), METAL), 0.38, -3.45, 0, CFrame.Angles(0, rad(90), 0))
		put(h, Build.cylinder(0.05, 0.94, col(2, rgb(215, 130, 55)), METAL), 0.38, -3.45, -0.08, CFrame.Angles(0, rad(90), 0))
		block(h, 0.15, -3.3, 0, 0.12, 0.28, 0.12, col(1, rgb(48, 48, 54)), METAL)
	end),

	-- 1 cuillère, 2 reflet, 3 poignée.
	club("club_spoon", "Rare", 600, PRICE, {
		variant("silver", { rgb(215, 218, 226), rgb(250, 250, 255), rgb(60, 90, 160) }),
		variant("gold", { rgb(235, 195, 80), rgb(255, 240, 190), rgb(125, 50, 55) }),
	}, { "food", "silly" }, function(h, col)
		gripAndShaft(h, col(3, rgb(60, 90, 160)), col(1, rgb(215, 218, 226)), 0.13, METAL)
		ellipsoid(h, 0.3, -3.45, 0.04, Vector3.new(1.0, 1.0, 0.3), col(1, rgb(215, 218, 226)), METAL)
		ellipsoid(h, 0.3, -3.47, -0.1, Vector3.new(0.58, 0.6, 0.08), col(2, rgb(250, 250, 255)), METAL)
	end),

	-- 1 bois, 2 ruban, 3 poignée.
	club("club_hockey_stick", "Rare", 650, PRICE, {
		variant("pine", { rgb(205, 160, 95), rgb(250, 250, 250), rgb(40, 40, 46) }),
		variant("ice", { rgb(120, 185, 230), rgb(250, 220, 80), rgb(235, 235, 240) }),
	}, { "snow", "sport" }, function(h, col)
		gripAndShaft(h, col(3, rgb(40, 40, 46)), col(1, rgb(205, 160, 95)), 0.14, WOOD)
		block(h, 0.4, HEAD_Y, 0, 1.3, 0.46, 0.14, col(1, rgb(205, 160, 95)), WOOD)
		block(h, 0.85, HEAD_Y, 0, 0.3, 0.48, 0.16, col(2, rgb(250, 250, 250)), Enum.Material.Fabric)
		block(h, 0.0, HEAD_Y + 0.02, 0, 0.3, 0.5, 0.16, col(2, rgb(250, 250, 250)), Enum.Material.Fabric)
	end),

	-- 1 croûte, 2 entailles, 3 mie.
	club("club_baguette", "Rare", 650, PRICE, {
		variant("golden", { rgb(220, 165, 85), rgb(165, 105, 50), rgb(250, 235, 190) }),
		variant("dark", { rgb(170, 110, 60), rgb(110, 65, 35), rgb(235, 215, 165) }),
	}, { "food", "silly" }, function(h, col)
		seg(h, 0.5, -3.55, 0.34, col(1, rgb(220, 165, 85)), Enum.Material.Fabric)
		ellipsoid(h, 0, 0.5, 0, Vector3.new(0.34, 0.3, 0.34), col(1, rgb(220, 165, 85)), Enum.Material.Fabric)
		ellipsoid(h, 0, -3.55, 0, Vector3.new(0.34, 0.3, 0.34), col(3, rgb(250, 235, 190)), Enum.Material.Fabric)
		for index = 0, 5 do
			block(h, 0, -0.5 - index * 0.55, -0.15, 0.1, 0.35, 0.06, col(2, rgb(165, 105, 50)), Enum.Material.Fabric, CFrame.Angles(0, 0, rad(-35)))
		end
		ellipsoid(h, 0.28, HEAD_Y, 0, Vector3.new(0.95, 0.6, 0.5), col(1, rgb(220, 165, 85)), Enum.Material.Fabric)
		block(h, 0.28, HEAD_Y, -0.24, 0.6, 0.06, 0.03, col(2, rgb(165, 105, 50)), Enum.Material.Fabric)
	end),

	-- 1 mousse, 2 extrémités.
	club("club_pool_noodle", "Rare", 600, PRICE, {
		variant("pink", { rgb(250, 120, 170), rgb(250, 190, 215), rgb(250, 190, 215) }),
		variant("lime", { rgb(140, 220, 70), rgb(215, 245, 160), rgb(215, 245, 160) }),
		variant("blue", { rgb(70, 170, 245), rgb(170, 215, 250), rgb(170, 215, 250) }),
	}, { "coast", "silly" }, function(h, col)
		seg(h, 0.5, -3.3, 0.34, col(1, rgb(250, 120, 170)), PLASTIC)
		seg(h, 0.5, 0.46, 0.2, col(2, rgb(250, 190, 215)), PLASTIC)
		ellipsoid(h, 0.3, HEAD_Y, 0.02, Vector3.new(1.15, 0.65, 0.6), col(1, rgb(250, 120, 170)), PLASTIC)
		block(h, 0.3, HEAD_Y, -0.3, 0.8, 0.3, 0.04, col(2, rgb(250, 190, 215)), PLASTIC)
	end),

	-- Épiques --------------------------------------------------------------------------------------
	-- 1 métal, 2 pointes, 3 poignée.
	club("club_trident", "Epic", 1100, PRICE, {
		variant("sea", { rgb(60, 185, 190), rgb(235, 195, 80), rgb(40, 90, 120) }),
		variant("gold", { rgb(235, 195, 80), rgb(255, 240, 190), rgb(125, 50, 55) }),
	}, { "coast", "myth" }, function(h, col)
		gripAndShaft(h, col(3, rgb(40, 90, 120)), col(1, rgb(60, 185, 190)), 0.14, METAL)
		block(h, 0.0, -3.4, 0, 1.15, 0.12, 0.12, col(1, rgb(60, 185, 190)), METAL)
		for _, x in { -0.52, 0.52 } do
			block(h, x, -3.58, 0, 0.1, 0.4, 0.1, col(1, rgb(60, 185, 190)), METAL)
			block(h, x, -3.82, 0, 0.14, 0.14, 0.1, col(2, rgb(235, 195, 80)), METAL, CFrame.Angles(0, 0, rad(45)))
		end
		block(h, 0, -3.62, 0, 0.12, 0.5, 0.1, col(1, rgb(60, 185, 190)), METAL)
		block(h, 0, -3.9, 0, 0.16, 0.16, 0.1, col(2, rgb(235, 195, 80)), METAL, CFrame.Angles(0, 0, rad(45)))
	end),

	-- 1 néon principal, 2 néon secondaire, 3 poignée.
	club("club_neon_tube", "Epic", 1200, PRICE, {
		variant("pink", { rgb(255, 80, 190), rgb(90, 220, 255), rgb(30, 30, 40) }),
		variant("cyan", { rgb(70, 235, 255), rgb(255, 110, 200), rgb(30, 30, 40) }),
		variant("lime", { rgb(150, 255, 70), rgb(255, 235, 80), rgb(30, 30, 40) }),
	}, { "city", "fx" }, function(h, col)
		seg(h, GRIP_TOP, GRIP_BOTTOM, 0.27, col(3, rgb(30, 30, 40)), PLASTIC)
		seg(h, GRIP_BOTTOM, SHAFT_BOTTOM, 0.15, col(1, rgb(255, 80, 190)), NEON)
		block(h, 0.3, HEAD_Y, 0, 1.0, 0.45, 0.25, col(2, rgb(90, 220, 255)), NEON)
		block(h, 0.3, HEAD_Y, -0.16, 0.9, 0.08, 0.05, col(3, rgb(30, 30, 40)))
		sparkle(h, col(1, rgb(255, 80, 190)), 3)
	end),

	-- 1 or, 2 argent, 3 cuir.
	club("club_pirate_hook", "Epic", 1100, PRICE, {
		variant("silver", { rgb(205, 208, 216), rgb(235, 195, 80), rgb(95, 60, 35) }),
		variant("black", { rgb(50, 52, 60), rgb(205, 208, 216), rgb(130, 35, 45) }),
	}, { "coast", "pirate" }, function(h, col)
		gripAndShaft(h, col(3, rgb(95, 60, 35)), rgb(120, 85, 55), 0.14, WOOD)
		block(h, 0.0, -3.35, 0, 0.3, 0.16, 0.3, col(2, rgb(235, 195, 80)), METAL)
		block(h, 0.0, -3.6, 0, 0.18, 0.4, 0.14, col(1, rgb(205, 208, 216)), METAL)
		block(h, 0.3, -3.82, 0, 0.7, 0.18, 0.14, col(1, rgb(205, 208, 216)), METAL)
		block(h, 0.62, -3.62, 0, 0.18, 0.5, 0.14, col(1, rgb(205, 208, 216)), METAL)
		block(h, 0.62, -3.38, 0, 0.14, 0.14, 0.14, col(1, rgb(205, 208, 216)), METAL, CFrame.Angles(0, 0, rad(45)))
		block(h, 0.3, -3.82, -0.09, 0.5, 0.1, 0.04, col(2, rgb(235, 195, 80)), METAL)
	end),

	-- Légendaires ----------------------------------------------------------------------------------
	-- 1 or, 2 plaque, 3 poignée.
	club("club_golden_driver", "Legendary", 2400, PRICE, {
		variant("gold", { rgb(250, 205, 70), rgb(255, 245, 200), rgb(120, 40, 50) }),
		variant("rose", { rgb(240, 175, 160), rgb(255, 235, 225), rgb(70, 40, 60) }),
	}, { "champion", "fx" }, function(h, col)
		gripAndShaft(h, col(3, rgb(120, 40, 50)), col(1, rgb(250, 205, 70)), 0.13, METAL)
		ellipsoid(h, 0.3, HEAD_Y + 0.05, 0.1, Vector3.new(1.15, 0.78, 1.0), col(1, rgb(250, 205, 70)), METAL)
		block(h, 0.3, HEAD_Y, -0.38, 0.8, 0.4, 0.05, col(2, rgb(255, 245, 200)), METAL)
		sparkle(h, col(2, rgb(255, 245, 200)), 6)
	end),

	-- 1 étoile, 2 reflets. Débloqué par 15 victoires.
	club("club_rainbow_wand", "Legendary", 0, { kind = "Wins", value = 15 }, {
		variant("rainbow", { rgb(255, 235, 90), rgb(255, 255, 255), rgb(60, 50, 90) }),
		variant("night", { rgb(150, 190, 255), rgb(255, 255, 255), rgb(35, 35, 60) }),
	}, { "champion", "magic", "fx" }, function(h, col)
		seg(h, GRIP_TOP, GRIP_BOTTOM, 0.27, col(3, rgb(60, 50, 90)), PLASTIC)
		local colors = { rgb(235, 60, 60), rgb(250, 150, 50), rgb(250, 225, 60), rgb(90, 200, 90), rgb(70, 160, 240), rgb(130, 90, 220), rgb(230, 100, 190) }
		local top = GRIP_BOTTOM
		local step = (top - SHAFT_BOTTOM) / #colors
		for index, color in colors do
			seg(h, top - (index - 1) * step, top - index * step, 0.14, color, NEON)
		end
		block(h, 0.3, -3.5, 0, 0.7, 0.7, 0.2, col(1, rgb(255, 235, 90)), NEON)
		block(h, 0.3, -3.5, 0, 0.7, 0.7, 0.2, col(1, rgb(255, 235, 90)), NEON, CFrame.Angles(0, 0, rad(45)))
		ball(h, 0.3, -3.5, -0.14, 0.3, col(2, rgb(255, 255, 255)), NEON)
		sparkle(h, col(2, rgb(255, 255, 255)), 8)
	end),
}
