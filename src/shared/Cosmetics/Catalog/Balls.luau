--!strict
--[[
	Catalog/Balls : apparences de balle (emplacement "Ball") — 1 balle gratuite par défaut + 10 balles.

	CONTRAT (Cosmetics/init.luau, BallVisualController) : decorate(visual, variant) -> Instance?
	  - `visual` est la balle VISUELLE côté client (Part sphérique ancrée, déplacée par le contrôleur) : on peut
	    changer sa couleur, sa matière, son reflet et sa transparence (le contrôleur rétablit l'aspect par défaut
	    avant chaque nouvelle apparence) ;
	  - les pièces ajoutées sont rassemblées dans un Folder enfant de `visual`, soudées à elle (elles la suivent
	    et roulent avec elle) ; ce Folder est retourné et détruit par le contrôleur au changement d'apparence ;
	  - rien d'autre n'est modifié : la balle serveur, sa collision, sa taille et sa physique restent la référence.

	ÉQUITÉ : toutes les pièces ajoutées passent par Build (Massless, sans collision, sans requête, sans contact) ;
	les dimensions sont proportionnelles au diamètre de `visual` mais ne dépassent jamais 1,9 fois ce diamètre
	(anneau de planète) ; les particules portent CosmeticFx = true (coupées en effets réduits).

	Couleurs : variants[v].colors[i] ; noms partagés « cos.sc.col.<couleur> ».
	Prix : Common ≈ 250, Rare ≈ 500 à 650, Epic ≈ 900 à 1000, Legendary ≈ 2000. Une balle se débloque par un
	trou en un.
]]

local Cosmetics = require(script.Parent.Parent)
local Build = require(script.Parent.Parent.Build)

type CosmeticDef = Cosmetics.CosmeticDef
type Rarity = Cosmetics.Rarity
type Unlock = Cosmetics.Unlock
type Variant = Cosmetics.Variant

type Paint = (index: number, fallback: Color3) -> Color3
type Decorator = (visual: BasePart, size: number, folder: Folder, col: Paint) -> ()

local rgb = Color3.fromRGB
local rad = math.rad
local PLASTIC, METAL, NEON, ICE, SLATE = Enum.Material.SmoothPlastic, Enum.Material.Metal, Enum.Material.Neon, Enum.Material.Ice, Enum.Material.Slate
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local function variant(colorKey: string, colors: { Color3 }): Variant
	return { nameKey = "cos.sc.col." .. colorKey, colors = colors }
end

-- Soude une pièce à la balle (position et rotation relatives au centre de la balle) ; elle est rangée dans `folder`.
local function fit(visual: BasePart, folder: Folder, part: BasePart, offset: CFrame): BasePart
	part.CFrame = visual.CFrame * offset
	part.Parent = folder
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = visual
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function ball(visual: BasePart, folder: Folder, offset: Vector3, diameter: number, color: Color3, material: Enum.Material?): BasePart
	return fit(visual, folder, Build.ball(diameter, color, material or PLASTIC), CFrame.new(offset))
end

local function ellipsoid(visual: BasePart, folder: Folder, offset: CFrame, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	local part = Build.part({ Name = "Ellipsoide", Size = size, Color = color, Material = material or PLASTIC })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return fit(visual, folder, part, offset)
end

-- Minuscule pièce invisible : support d'Attachment (particules, traînée).
local function anchorAt(visual: BasePart, folder: Folder, offset: Vector3, name: string): Attachment
	local part = Build.part({ Name = "Support", Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 })
	fit(visual, folder, part, CFrame.new(offset))
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = part
	return attachment
end

local function emitter(attachment: Attachment, color: Color3, rate: number, size: number, speed: number, emission: number)
	local particles = Instance.new("ParticleEmitter")
	particles.Name = "Particules"
	particles.Texture = SPARKLE_TEXTURE
	particles.Color = ColorSequence.new(color)
	particles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	particles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	particles.Lifetime = NumberRange.new(0.5, 0.9)
	particles.Rate = rate
	particles.Speed = NumberRange.new(speed * 0.5, speed)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.LightEmission = emission
	particles.Parent = attachment
	particles:SetAttribute("CosmeticFx", true)
end

local function ball_(id: string, rarity: Rarity, price: number, unlock: Unlock, variants: { Variant }, tags: { string }, decorator: Decorator): CosmeticDef
	return {
		id = id,
		slot = "Ball",
		nameKey = "cos." .. id,
		descKey = "cos." .. id .. ".desc",
		rarity = rarity,
		price = price,
		unlock = unlock,
		variants = variants,
		tags = tags,
		decorate = function(visual: BasePart, chosen: number?): Instance?
			local folder = Instance.new("Folder")
			folder.Name = "DecorBalle"
			folder:SetAttribute("CosmeticId", id)
			folder:SetAttribute("CosmeticSlot", "Ball")
			folder:SetAttribute("CosmeticVariant", chosen or 1)
			local function col(index: number, fallback: Color3): Color3
				return Build.color(variants, chosen, index, fallback)
			end
			decorator(visual, math.max(visual.Size.X, 0.2), folder, col)
			folder.Parent = visual
			return folder
		end,
	}
end

local DEFAULT = { kind = "Default" } :: Unlock
local PRICE = { kind = "Price" } :: Unlock

return {
	-- Gratuite : balle de golf blanche avec alvéoles discrètes. 1 teinte, 2 alvéoles.
	ball_("ball_classic", "Common", 0, DEFAULT, {
		variant("white", { rgb(250, 250, 250), rgb(215, 218, 225) }),
		variant("yellow", { rgb(250, 225, 80), rgb(220, 190, 50) }),
		variant("orange", { rgb(250, 150, 60), rgb(215, 120, 40) }),
	}, { "starter", "golf" }, function(visual, size, folder, col)
		visual.Color = col(1, rgb(250, 250, 250))
		for index = 0, 7 do
			local angle = index / 8 * math.pi * 2
			local y = if index % 2 == 0 then 0.25 else -0.25
			ball(visual, folder, Vector3.new(math.cos(angle) * 0.46 * size, y * size, math.sin(angle) * 0.46 * size), 0.1 * size, col(2, rgb(215, 218, 225)))
		end
	end),

	-- Communes -------------------------------------------------------------------------------------
	-- 1 lueur.
	ball_("ball_neon", "Common", 250, PRICE, {
		variant("lime", { rgb(150, 255, 70) }),
		variant("pink", { rgb(255, 90, 190) }),
		variant("cyan", { rgb(70, 235, 255) }),
	}, { "city", "fx" }, function(visual, size, folder, col)
		visual.Material = NEON
		visual.Color = col(1, rgb(150, 255, 70))
		emitter(anchorAt(visual, folder, Vector3.zero, "Lueur"), col(1, rgb(150, 255, 70)), 3, 0.2 * size, 0.6, 0.8)
	end),

	-- 1 visage.
	ball_("ball_smiley", "Common", 250, PRICE, {
		variant("yellow", { rgb(255, 215, 60) }),
		variant("green", { rgb(130, 220, 90) }),
		variant("pink", { rgb(255, 150, 190) }),
	}, { "silly" }, function(visual, _size, folder, col)
		visual.Color = col(1, rgb(255, 215, 60))
		local dark = rgb(60, 45, 30)
		local gui = Build.face(visual, {
			{ position = UDim2.fromScale(0.34, 0.38), size = UDim2.fromScale(0.1, 0.16), color = dark, corner = 0.5 },
			{ position = UDim2.fromScale(0.66, 0.38), size = UDim2.fromScale(0.1, 0.16), color = dark, corner = 0.5 },
			{ position = UDim2.fromScale(0.5, 0.68), size = UDim2.fromScale(0.42, 0.1), color = dark, corner = 0.5 },
		})
		gui.Parent = folder
		-- Le SurfaceGui doit rester sur la balle : on le rattache via Adornee.
		gui.Adornee = visual
	end),

	-- Rares ----------------------------------------------------------------------------------------
	-- 1 chair, 2 tige.
	ball_("ball_pumpkin", "Rare", 500, PRICE, {
		variant("orange", { rgb(245, 140, 40), rgb(80, 140, 60) }),
		variant("white", { rgb(240, 235, 215), rgb(120, 150, 70) }),
	}, { "forest", "season" }, function(visual, size, folder, col)
		visual.Color = col(1, rgb(245, 140, 40))
		visual.Material = Enum.Material.SmoothPlastic
		for index = 0, 2 do
			ellipsoid(visual, folder, CFrame.Angles(0, rad(index * 60), 0), Vector3.new(0.12 * size, 1.02 * size, 1.02 * size), col(1, rgb(245, 140, 40)), PLASTIC)
		end
		fit(visual, folder, Build.block(Vector3.new(0.18 * size, 0.26 * size, 0.18 * size), col(2, rgb(80, 140, 60)), Enum.Material.Wood), CFrame.new(0, 0.5 * size, 0))
	end),

	-- 1 glace, 2 éclats.
	ball_("ball_ice", "Rare", 500, PRICE, {
		variant("blue", { rgb(170, 225, 255), rgb(255, 255, 255) }),
		variant("mint", { rgb(180, 250, 225), rgb(255, 255, 255) }),
	}, { "snow", "fx" }, function(visual, size, folder, col)
		visual.Material = ICE
		visual.Color = col(1, rgb(170, 225, 255))
		visual.Transparency = 0.2
		visual.Reflectance = 0.2
		emitter(anchorAt(visual, folder, Vector3.zero, "Givre"), col(2, rgb(255, 255, 255)), 4, 0.18 * size, 0.5, 0.3)
	end),

	-- 1 miroir, 2 reflets.
	ball_("ball_disco", "Rare", 600, PRICE, {
		variant("silver", { rgb(215, 218, 228), rgb(255, 255, 255) }),
		variant("gold", { rgb(240, 205, 110), rgb(255, 250, 215) }),
	}, { "city", "fx" }, function(visual, size, folder, col)
		visual.Material = METAL
		visual.Color = col(1, rgb(215, 218, 228))
		visual.Reflectance = 0.6
		for index = 0, 9 do
			local angle = index / 10 * math.pi * 2
			local tilt = if index % 2 == 0 then 0.3 else -0.3
			ball(visual, folder, Vector3.new(math.cos(angle) * 0.5 * size, tilt * size, math.sin(angle) * 0.5 * size), 0.13 * size, col(2, rgb(255, 255, 255)), NEON)
		end
		emitter(anchorAt(visual, folder, Vector3.zero, "Eclats"), col(2, rgb(255, 255, 255)), 6, 0.22 * size, 0.7, 0.7)
	end),

	-- 1 roche, 2 braises.
	ball_("ball_lava", "Rare", 650, PRICE, {
		variant("orange", { rgb(55, 40, 38), rgb(255, 120, 30) }),
		variant("blue", { rgb(40, 42, 58), rgb(80, 170, 255) }),
	}, { "desert", "fx" }, function(visual, size, folder, col)
		visual.Material = SLATE
		visual.Color = col(1, rgb(55, 40, 38))
		local cracks = { Vector3.new(0.4, 0.2, -0.3), Vector3.new(-0.35, 0.3, -0.3), Vector3.new(0.1, -0.4, -0.3), Vector3.new(-0.3, -0.15, 0.35), Vector3.new(0.3, 0.05, 0.35) }
		for _, spot in cracks do
			ball(visual, folder, spot.Unit * 0.5 * size, 0.2 * size, col(2, rgb(255, 120, 30)), NEON)
		end
		emitter(anchorAt(visual, folder, Vector3.new(0, 0.4 * size, 0), "Braises"), col(2, rgb(255, 120, 30)), 5, 0.22 * size, 0.8, 0.8)
	end),

	-- Épiques --------------------------------------------------------------------------------------
	-- 1 globe, 2 iris, 3 pupille.
	ball_("ball_eyeball", "Epic", 900, PRICE, {
		variant("blue", { rgb(250, 248, 245), rgb(70, 150, 235), rgb(20, 20, 24) }),
		variant("green", { rgb(250, 248, 245), rgb(80, 200, 110), rgb(20, 20, 24) }),
		variant("red", { rgb(250, 248, 245), rgb(220, 60, 60), rgb(20, 20, 24) }),
	}, { "silly" }, function(visual, size, folder, col)
		visual.Color = col(1, rgb(250, 248, 245))
		ball(visual, folder, Vector3.new(0, 0, -0.36 * size), 0.5 * size, col(2, rgb(70, 150, 235)))
		ball(visual, folder, Vector3.new(0, 0, -0.47 * size), 0.24 * size, col(3, rgb(20, 20, 24)))
		ball(visual, folder, Vector3.new(0.08 * size, 0.1 * size, -0.5 * size), 0.07 * size, rgb(255, 255, 255))
	end),

	-- 1 planète, 2 continents, 3 anneau.
	ball_("ball_planet", "Epic", 1000, PRICE, {
		variant("earth", { rgb(60, 130, 215), rgb(90, 190, 100), rgb(230, 200, 140) }),
		variant("mars", { rgb(205, 100, 60), rgb(150, 70, 45), rgb(230, 190, 150) }),
		variant("neptune", { rgb(70, 90, 215), rgb(130, 150, 250), rgb(200, 215, 255) }),
	}, { "space" }, function(visual, size, folder, col)
		visual.Color = col(1, rgb(60, 130, 215))
		ellipsoid(visual, folder, CFrame.new(0.2 * size, 0.2 * size, -0.28 * size) * CFrame.Angles(0, rad(-25), 0), Vector3.new(0.5 * size, 0.38 * size, 0.3 * size), col(2, rgb(90, 190, 100)), PLASTIC)
		ellipsoid(visual, folder, CFrame.new(-0.25 * size, -0.2 * size, -0.3 * size), Vector3.new(0.34 * size, 0.3 * size, 0.26 * size), col(2, rgb(90, 190, 100)), PLASTIC)
		local ringPart = Build.cylinder(0.04 * size, 1.9 * size, col(3, rgb(230, 200, 140)), PLASTIC)
		ringPart.Transparency = 0.3
		fit(visual, folder, ringPart, CFrame.Angles(0, 0, rad(90)) * CFrame.Angles(rad(15), 0, 0))
	end),

	-- Légendaires ----------------------------------------------------------------------------------
	-- 1 or, 2 éclat.
	ball_("ball_golden", "Legendary", 2000, PRICE, {
		variant("gold", { rgb(250, 205, 70), rgb(255, 245, 200) }),
		variant("rose", { rgb(240, 175, 160), rgb(255, 235, 225) }),
	}, { "champion", "fx" }, function(visual, size, folder, col)
		visual.Material = METAL
		visual.Color = col(1, rgb(250, 205, 70))
		visual.Reflectance = 0.5
		emitter(anchorAt(visual, folder, Vector3.zero, "Eclat"), col(2, rgb(255, 245, 200)), 8, 0.28 * size, 0.9, 0.7)
	end),

	-- 1 noyau, 2 queue. Débloquée par un trou en un.
	ball_("ball_comet", "Legendary", 0, { kind = "HolesInOne", value = 1 }, {
		variant("ice", { rgb(200, 235, 255), rgb(120, 190, 255) }),
		variant("fire", { rgb(255, 200, 120), rgb(255, 110, 40) }),
	}, { "space", "fx", "champion" }, function(visual, size, folder, col)
		visual.Material = NEON
		visual.Color = col(1, rgb(200, 235, 255))
		local top = anchorAt(visual, folder, Vector3.new(0, 0.35 * size, 0), "Haut")
		local bottom = anchorAt(visual, folder, Vector3.new(0, -0.35 * size, 0), "Bas")
		local trail = Instance.new("Trail")
		trail.Name = "Queue"
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Lifetime = 0.5
		trail.MinLength = 0.05
		trail.LightEmission = 0.8
		trail.Color = ColorSequence.new(col(1, rgb(200, 235, 255)), col(2, rgb(120, 190, 255)))
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		trail.Parent = folder
		trail:SetAttribute("CosmeticFx", true)
		emitter(top, col(2, rgb(120, 190, 255)), 6, 0.24 * size, 0.7, 0.8)
	end),
}
