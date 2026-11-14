--!strict
--[[
	LobbyBuilder — construit par code l'accueil (hub) de Golf Chaos : une île cartoon toujours chargée.

	  local info = LobbyBuilder.build(origin, parent) -> LobbyInfo
	  (appelé par CourseService.Start ; origin = dessus du sol au centre de la place)

	CONTENU (repère : origin ; le nord = -Z, côté driving range)
	  - Île engazonnée (rayon 96) et place pavée (rayon 46) à motifs concentriques.
	  - Fontaine centrale : bassin, jets d'eau (particules intégrées au moteur) et statue originale d'une balle de
	    golf géante posée sur son tee.
	  - 16 plots d'apparition en couronne autour de la fontaine (spawns, orientés vers l'extérieur).
	  - Stands avec panneau (SurfaceGui, polices intégrées, textes Locale) et emblème construit par code :
	    Jouer, Boutique, Personnaliser, Défis, Entraînement. Chaque comptoir porte un ProximityPrompt avec
	    l'attribut "Kiosk" (nom du stand) : un contrôleur client peut ouvrir l'écran correspondant
	    (ProximityPromptService.PromptTriggered côté client), sans remote supplémentaire.
	  - Green d'entraînement (est) : avant-green, green (attribut Surface "Green"), trou + drapeau, 4 points de
	    départ et un distributeur de balles (ProximityPrompt, attribut PracticeArea = "green").
	  - Driving range (nord) : porte-arche, tertre de départ avec 5 points de frappe et distributeur
	    (PracticeArea = "range"), terrain rayé ouvert de 330 studs, lignes et panneaux de distance tous les
	    50 studs, greens-cibles avec drapeaux, butte de fond.
	  - Podium (ouest) : 3 marches (or, argent, bronze) étiquetées, fond décoré.
	  - Arbres, buissons, massifs, lampadaires, bancs via server/Course/Props (repli intégré si absent).
	  - Clôture visible et murs invisibles tout autour (île et range) ; la mer est décorative (non collidable)
	    pour que tout ce qui tomberait passe sous la zone mortelle (CourseService ramène alors le joueur).

	LobbyInfo = {
	  folder, spawns { CFrame }, spawn CFrame,
	  practiceTee CFrame, practiceCup Vector3, practiceCupRadius number, practiceSpots { CFrame },
	  practiceGreenCenter Vector3, practiceGreenRadius number,
	  rangeTee CFrame, rangeSpots { CFrame }, rangeZone { cframe, size },
	  kiosks { [nom]: CFrame } : play, shop, customize, challenges, training, practice, range (où se placer devant
	         le stand, tourné vers lui), podium1, podium2, podium3 (debout sur la marche, tourné vers le public),
	         podiumView (point de vue face au podium),
	  bounds { min, max }, killY number, prompts { ProximityPrompt },
	}
	Les points (spawns, kiosks, podium) sont à hauteur de HumanoidRootPart (sol + 3) ; les points de départ
	de balle (practiceSpots, rangeSpots, practiceTee, rangeTee) sont au niveau du sol.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Locale = require(Shared.Locale)
local Log = require(Shared.Util.Log)

local LobbyBuilder = {}

export type LobbyInfo = {
	folder: Folder,
	spawns: { CFrame },
	spawn: CFrame,
	practiceTee: CFrame,
	practiceCup: Vector3,
	practiceCupRadius: number,
	practiceSpots: { CFrame },
	practiceGreenCenter: Vector3,
	practiceGreenRadius: number,
	rangeTee: CFrame,
	rangeSpots: { CFrame },
	rangeZone: { cframe: CFrame, size: Vector3 },
	kiosks: { [string]: CFrame },
	bounds: { min: Vector3, max: Vector3 },
	killY: number,
	prompts: { ProximityPrompt },
}

--------------------------------------------------------------------------------
-- Plan de l'accueil (studs, relatif à l'origine)
--------------------------------------------------------------------------------

local LAYOUT = {
	IslandRadius = 96,
	IslandDepth = 10,
	PlazaRadius = 46,
	FountainRadius = 9,
	SpawnCount = 16,
	SpawnRingRadius = 22,
	FenceRadius = 90,
	BarrierRadius = 92,
	BarrierHeight = 40,
	BarrierSegments = 40,
	RangeHalfWidth = 57, -- couloir du driving range (clôtures)
	RangeGroundHalfWidth = 75,
	RangeStartZ = -60,
	RangeEndZ = -430,
	RangeTeeZ = -95,
	RangeMarkers = { 50, 100, 150, 200, 250, 300 },
	RangeTargets = {
		{ distance = 100, x = -18, radius = 9, color = Color3.fromRGB(232, 72, 72) },
		{ distance = 170, x = 16, radius = 11, color = Color3.fromRGB(255, 206, 64) },
		{ distance = 240, x = -6, radius = 13, color = Color3.fromRGB(66, 140, 232) },
		{ distance = 310, x = 12, radius = 15, color = Color3.fromRGB(156, 98, 226) },
	},
	GreenCenter = Vector3.new(64, 0, -6),
	GreenRadius = 14,
	FringeWidth = 2.5,
	CupOffset = Vector3.new(5, 0, -3),
	CupRadius = 1.7,
	PodiumCenter = Vector3.new(-60, 0, 0),
	PodiumHeights = { 4.5, 3.2, 2 },
	KillDepth = 45,
	Seed = 20261114,
}

local KIOSKS = {
	{ name = "play", position = Vector3.new(-26, 0, -50), title = "course.sign.play", sub = "course.sign.playSub", color = Color3.fromRGB(88, 186, 84), icon = "flag" },
	{ name = "training", position = Vector3.new(26, 0, -50), title = "course.sign.training", sub = "course.sign.trainingSub", color = Color3.fromRGB(66, 140, 232), icon = "target" },
	{ name = "shop", position = Vector3.new(-42, 0, 32), title = "course.sign.shop", sub = "course.sign.shopSub", color = Color3.fromRGB(255, 170, 40), icon = "coin" },
	{ name = "customize", position = Vector3.new(42, 0, 32), title = "course.sign.customize", sub = "course.sign.customizeSub", color = Color3.fromRGB(232, 92, 160), icon = "hat" },
	{ name = "challenges", position = Vector3.new(0, 0, 56), title = "course.sign.challenges", sub = "course.sign.challengesSub", color = Color3.fromRGB(156, 98, 226), icon = "trophy" },
}

local COLORS = {
	grass = Color3.fromRGB(110, 200, 90),
	grassDark = Color3.fromRGB(96, 184, 78),
	grassTee = Color3.fromRGB(84, 168, 70),
	green = Color3.fromRGB(132, 224, 106),
	fringe = Color3.fromRGB(104, 196, 86),
	dirt = Color3.fromRGB(150, 104, 66),
	cliff = Color3.fromRGB(122, 86, 58),
	sea = Color3.fromRGB(70, 168, 232),
	paving = Color3.fromRGB(240, 226, 196),
	pavingDark = Color3.fromRGB(218, 198, 164),
	pavingAccent = Color3.fromRGB(232, 140, 96),
	stone = Color3.fromRGB(196, 196, 204),
	stoneDark = Color3.fromRGB(150, 150, 162),
	water = Color3.fromRGB(86, 190, 245),
	white = Color3.fromRGB(250, 248, 242),
	cream = Color3.fromRGB(246, 236, 214),
	dark = Color3.fromRGB(44, 44, 54),
	wood = Color3.fromRGB(176, 120, 72),
	woodDark = Color3.fromRGB(116, 78, 48),
	red = Color3.fromRGB(232, 72, 72),
	yellow = Color3.fromRGB(255, 206, 64),
	gold = Color3.fromRGB(255, 196, 46),
	silver = Color3.fromRGB(204, 210, 222),
	bronze = Color3.fromRGB(205, 128, 72),
	purple = Color3.fromRGB(120, 84, 200),
	textStroke = Color3.fromRGB(30, 30, 46),
	leaf = Color3.fromRGB(70, 160, 72),
	leafLight = Color3.fromRGB(104, 190, 86),
}

local FONT_TITLE = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local FONT_BODY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)

--------------------------------------------------------------------------------
-- Pièces
--------------------------------------------------------------------------------

type PartOptions = {
	shape: Enum.PartType?,
	wedge: boolean?,
	collide: boolean?,
	query: boolean?,
	transparency: number?,
	surface: string?,
	shadow: boolean?,
	reflectance: number?,
}

local function newPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, partColor: Color3, partMaterial: Enum.Material?, opts: PartOptions?): BasePart
	local options: PartOptions = opts or {}
	local part: BasePart
	if options.wedge then
		part = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		if options.shape then
			block.Shape = options.shape
		end
		part = block
	end
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = partColor
	part.Material = partMaterial or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local collide = options.collide ~= false
	part.CanCollide = collide
	part.CanQuery = if options.query ~= nil then options.query else collide
	part.CanTouch = collide
	part.CastShadow = options.shadow ~= false
	if options.transparency then
		part.Transparency = options.transparency
	end
	if options.reflectance then
		part.Reflectance = options.reflectance
	end
	if options.surface then
		part:SetAttribute("Surface", options.surface)
	end
	part.Parent = parent
	return part
end

local function decor(parent: Instance, name: string, size: Vector3, cframe: CFrame, partColor: Color3, partMaterial: Enum.Material?, opts: PartOptions?): BasePart
	local options: PartOptions = table.clone(opts or {})
	options.collide = false
	options.query = false
	return newPart(parent, name, size, cframe, partColor, partMaterial, options)
end

-- Cylindre vertical centré sur `center` (l'axe des cylindres Roblox est X).
local function disc(parent: Instance, name: string, diameter: number, height: number, center: Vector3, partColor: Color3, partMaterial: Enum.Material?, opts: PartOptions?): BasePart
	local options: PartOptions = table.clone(opts or {})
	options.shape = Enum.PartType.Cylinder
	return newPart(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), partColor, partMaterial, options)
end

local function ball(parent: Instance, name: string, diameter: number, center: Vector3, partColor: Color3, partMaterial: Enum.Material?, solid: boolean?): BasePart
	local options: PartOptions = { shape = Enum.PartType.Ball }
	if solid then
		return newPart(parent, name, Vector3.one * diameter, CFrame.new(center), partColor, partMaterial, options)
	end
	return decor(parent, name, Vector3.one * diameter, CFrame.new(center), partColor, partMaterial, options)
end

local function folderIn(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- Panneau : SurfaceGui sur la face avant (LookVector) d'une planche, titre + sous-titre optionnel.
local function signText(board: BasePart, titleKey: string, subKey: string?, titleVars: { [string]: any }?, textColor: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Panneau"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.ResetOnSpawn = false
	gui.Parent = board

	local title = Instance.new("TextLabel")
	title.Name = "Titre"
	title.BackgroundTransparency = 1
	title.Size = if subKey then UDim2.new(1, -24, 0.6, -8) else UDim2.new(1, -24, 1, -16)
	title.Position = UDim2.new(0, 12, 0, 8)
	title.FontFace = FONT_TITLE
	title.TextScaled = true
	title.TextColor3 = textColor or COLORS.white
	title.Text = Locale.t(titleKey, titleVars)
	title:SetAttribute("LocaleKey", titleKey)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = COLORS.textStroke
	stroke.Parent = title
	title.Parent = gui

	if subKey then
		local sub = Instance.new("TextLabel")
		sub.Name = "SousTitre"
		sub.BackgroundTransparency = 1
		sub.Size = UDim2.new(1, -40, 0.3, 0)
		sub.Position = UDim2.new(0, 20, 0.62, 0)
		sub.FontFace = FONT_BODY
		sub.TextScaled = true
		sub.TextColor3 = COLORS.cream
		sub.Text = Locale.t(subKey)
		sub:SetAttribute("LocaleKey", subKey)
		local subStroke = Instance.new("UIStroke")
		subStroke.Thickness = 2
		subStroke.Color = COLORS.textStroke
		subStroke.Parent = sub
		sub.Parent = gui
	end
	return gui
end

local function addPrompt(parent: BasePart, actionKey: string, objectKey: string, attributes: { [string]: any }, prompts: { ProximityPrompt }): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Invite"
	prompt.ActionText = Locale.t(actionKey)
	prompt.ObjectText = Locale.t(objectKey)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt:SetAttribute("LocaleKey", actionKey)
	prompt:SetAttribute("ObjectLocaleKey", objectKey)
	for key, value in attributes do
		prompt:SetAttribute(key, value)
	end
	prompt.Parent = parent
	table.insert(prompts, prompt)
	return prompt
end

-- Pose debout (HumanoidRootPart) devant un point, tournée vers une cible (horizontalement).
local function standFacing(position: Vector3, target: Vector3): CFrame
	local flatTarget = Vector3.new(target.X, position.Y, target.Z)
	if (flatTarget - position).Magnitude < 1e-3 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, flatTarget)
end

--------------------------------------------------------------------------------
-- Décor (Props si disponible, sinon repli intégré)
--------------------------------------------------------------------------------

type PropsModule = { make: (kind: string, cf: CFrame, scale: number?, rng: Random?, palette: any?) -> Model? }

local function loadProps(): PropsModule?
	local module = script.Parent:FindFirstChild("Props")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" and type((result :: any).make) == "function" then
		return result :: any
	end
	Log.warn("Lobby", "Props illisible, décor de repli :", tostring(result))
	return nil
end

local function lobbyPalette(): any?
	local config = Shared:FindFirstChild("Config")
	local module = config and config:FindFirstChild("Biomes")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, biomes = pcall(require, module)
	if ok and type(biomes) == "table" then
		local entry = (biomes :: any).Lobby
		if type(entry) == "table" then
			return entry.palette
		end
	end
	return nil
end

local function fallbackProp(parent: Instance, kind: string, cf: CFrame, scale: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Decor_" .. kind
	local base = cf.Position
	if kind == "tree" or kind == "pine" then
		local trunkHeight = 5 * scale
		disc(model, "Tronc", 1.4 * scale, trunkHeight, base + Vector3.new(0, trunkHeight / 2, 0), COLORS.woodDark, Enum.Material.Wood)
		if kind == "pine" then
			for layer = 0, 2 do
				local size = (6 - layer * 1.6) * scale
				local y = trunkHeight + layer * 2.6 * scale
				decor(model, "Aiguilles", Vector3.new(size, 3.2 * scale, size), CFrame.new(base + Vector3.new(0, y + 1.6 * scale, 0)) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0), COLORS.leaf, Enum.Material.SmoothPlastic)
			end
		else
			ball(model, "Feuillage", 7 * scale, base + Vector3.new(0, trunkHeight + 2.6 * scale, 0), COLORS.leaf, Enum.Material.SmoothPlastic)
			ball(model, "Feuillage", 5 * scale, base + Vector3.new(2.2 * scale, trunkHeight + 1.6 * scale, 0.8 * scale), COLORS.leafLight, Enum.Material.SmoothPlastic)
			ball(model, "Feuillage", 4.6 * scale, base + Vector3.new(-1.8 * scale, trunkHeight + 1.8 * scale, -1.2 * scale), COLORS.leafLight, Enum.Material.SmoothPlastic)
		end
	elseif kind == "bush" then
		ball(model, "Buisson", 3.4 * scale, base + Vector3.new(0, 1.2 * scale, 0), COLORS.leaf, Enum.Material.SmoothPlastic)
		ball(model, "Buisson", 2.6 * scale, base + Vector3.new(1.4 * scale, 0.9 * scale, 0.4 * scale), COLORS.leafLight, Enum.Material.SmoothPlastic)
	elseif kind == "flowerbed" then
		disc(model, "Terreau", 5 * scale, 0.5, base + Vector3.new(0, 0.25, 0), COLORS.dirt, Enum.Material.Ground, { collide = false, query = false })
		local petals = { COLORS.red, COLORS.yellow, Color3.fromRGB(255, 140, 200), COLORS.white, Color3.fromRGB(160, 120, 255) }
		for index = 1, 9 do
			local angle = index / 9 * math.pi * 2
			local radius = (index % 3 + 0.4) * 0.6 * scale
			ball(model, "Fleur", 0.9 * scale, base + Vector3.new(math.cos(angle) * radius, 0.75, math.sin(angle) * radius), petals[(index % #petals) + 1], Enum.Material.SmoothPlastic)
		end
	elseif kind == "lamp" then
		disc(model, "Mat", 0.6, 9, base + Vector3.new(0, 4.5, 0), COLORS.dark, Enum.Material.Metal)
		local bulb = ball(model, "Globe", 1.8, base + Vector3.new(0, 9.4, 0), Color3.fromRGB(255, 240, 190), Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Range = 18
		light.Brightness = 1.2
		light.Color = Color3.fromRGB(255, 228, 170)
		light.Parent = bulb
	elseif kind == "bench" then
		newPart(model, "Assise", Vector3.new(5, 0.4, 1.6), cf * CFrame.new(0, 1.4, 0), COLORS.wood, Enum.Material.WoodPlanks)
		newPart(model, "Dossier", Vector3.new(5, 1.4, 0.3), cf * CFrame.new(0, 2.3, 0.75), COLORS.wood, Enum.Material.WoodPlanks)
		for _, side in { -1, 1 } do
			newPart(model, "Pied", Vector3.new(0.4, 1.2, 1.4), cf * CFrame.new(side * 2.1, 0.6, 0), COLORS.dark, Enum.Material.Metal)
		end
	end
	model.Parent = parent
end

local function placeProp(props: PropsModule?, parent: Instance, kind: string, cf: CFrame, scale: number, rng: Random, palette: any?)
	if props then
		local ok, model = pcall(props.make, kind, cf, scale, rng, palette)
		if ok and typeof(model) == "Instance" then
			if model.Parent == nil then
				model.Parent = parent
			end
			return
		end
	end
	fallbackProp(parent, kind, cf, scale, rng)
end

--------------------------------------------------------------------------------
-- Sections
--------------------------------------------------------------------------------

local function buildGround(folder: Folder, origin: Vector3)
	local ground = folderIn(folder, "Sol")
	local depth = LAYOUT.IslandDepth
	disc(ground, "Ile", LAYOUT.IslandRadius * 2, depth, origin - Vector3.new(0, depth / 2, 0), COLORS.grass, Enum.Material.Grass, { surface = "Fairway" })
	disc(ground, "Falaise", LAYOUT.IslandRadius * 2 + 4, depth, origin - Vector3.new(0, depth / 2 + 1.2, 0), COLORS.cliff, Enum.Material.Slate)
	disc(ground, "Socle", LAYOUT.IslandRadius * 2 - 8, 8, origin - Vector3.new(0, depth + 4, 0), COLORS.dirt, Enum.Material.Ground)
	-- Mer décorative non collidable : tout ce qui tombe la traverse et passe sous la zone mortelle.
	newPart(ground, "Mer", Vector3.new(2048, 1, 2048), CFrame.new(origin + Vector3.new(0, -14, -150)), COLORS.sea, Enum.Material.Glass, {
		collide = false,
		query = false,
		transparency = 0.05,
		reflectance = 0.05,
		shadow = false,
	})

	-- Place pavée à motifs concentriques.
	disc(ground, "Place", LAYOUT.PlazaRadius * 2, 0.4, origin + Vector3.new(0, 0, 0), COLORS.paving, Enum.Material.Cobblestone, { surface = "Rock" })
	disc(ground, "Bordure", LAYOUT.PlazaRadius * 2 + 2, 0.3, origin + Vector3.new(0, -0.02, 0), COLORS.pavingDark, Enum.Material.Slate, { surface = "Rock" })
	decor(ground, "Motif", Vector3.new(0.05, 64, 64), CFrame.new(origin + Vector3.new(0, 0.22, 0)) * CFrame.Angles(0, 0, math.pi / 2), COLORS.pavingDark, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder, shadow = false })
	decor(ground, "Motif", Vector3.new(0.06, 58, 58), CFrame.new(origin + Vector3.new(0, 0.23, 0)) * CFrame.Angles(0, 0, math.pi / 2), COLORS.paving, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder, shadow = false })
	-- Rayons colorés (rosace) entre la fontaine et la couronne d'apparition.
	for index = 1, 8 do
		local angle = index / 8 * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local center = origin + direction * 34 + Vector3.new(0, 0.235, 0)
		decor(ground, "Rayon", Vector3.new(1.4, 0.05, 18), CFrame.lookAt(center, center + direction), COLORS.pavingAccent, Enum.Material.SmoothPlastic, { shadow = false })
	end
end

local function buildFountain(folder: Folder, origin: Vector3)
	local fountain = folderIn(folder, "Fontaine")
	local r = LAYOUT.FountainRadius
	disc(fountain, "Bassin", r * 2, 1.6, origin + Vector3.new(0, 0.8, 0), COLORS.stone, Enum.Material.Cobblestone, { surface = "Rock" })
	disc(fountain, "Margelle", r * 2 + 1, 0.4, origin + Vector3.new(0, 1.7, 0), COLORS.white, Enum.Material.Marble, { surface = "Rock" })
	disc(fountain, "Eau", r * 2 - 1.6, 0.2, origin + Vector3.new(0, 1.75, 0), COLORS.water, Enum.Material.Glass, { collide = false, query = false, transparency = 0.15, reflectance = 0.15 })
	-- Socle et statue : balle de golf géante sur son tee (création originale).
	disc(fountain, "Socle", 5, 3, origin + Vector3.new(0, 3, 0), COLORS.stoneDark, Enum.Material.SmoothPlastic, { surface = "Rock" })
	disc(fountain, "Corniche", 6, 0.6, origin + Vector3.new(0, 4.6, 0), COLORS.white, Enum.Material.SmoothPlastic)
	disc(fountain, "Tee", 1.4, 4, origin + Vector3.new(0, 6.9, 0), COLORS.yellow, Enum.Material.SmoothPlastic)
	disc(fountain, "TeteDeTee", 3.6, 0.6, origin + Vector3.new(0, 9.1, 0), COLORS.yellow, Enum.Material.SmoothPlastic)
	local giant = ball(fountain, "BalleGeante", 7, origin + Vector3.new(0, 12.8, 0), COLORS.white, Enum.Material.SmoothPlastic, true)
	-- Alvéoles stylisées (petites pastilles grises en spirale).
	for index = 1, 26 do
		local t = index / 26
		local polar = math.acos(1 - 2 * t)
		local azimuth = index * 2.39996
		local normal = Vector3.new(math.sin(polar) * math.cos(azimuth), math.cos(polar), math.sin(polar) * math.sin(azimuth))
		local position = giant.Position + normal * 3.42
		decor(fountain, "Alveole", Vector3.new(0.12, 0.9, 0.9), CFrame.lookAt(position, position + normal) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(226, 228, 232), Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder, shadow = false })
	end
	-- Jets d'eau : particules (texture intégrée au moteur).
	for index = 1, 4 do
		local angle = index / 4 * math.pi * 2 + math.pi / 4
		local nozzle = decor(fountain, "Buse", Vector3.new(0.8, 0.8, 0.8), CFrame.new(origin + Vector3.new(math.cos(angle) * 5.5, 1.9, math.sin(angle) * 5.5)), COLORS.stoneDark, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Ball })
		local attachment = Instance.new("Attachment")
		attachment.CFrame = CFrame.Angles(0, 0, 0)
		attachment.Parent = nozzle
		local spray = Instance.new("ParticleEmitter")
		spray.Name = "Jet"
		spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		spray.Color = ColorSequence.new(Color3.fromRGB(200, 236, 255), Color3.fromRGB(120, 200, 255))
		spray.LightEmission = 0.4
		spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.15) })
		spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		spray.Lifetime = NumberRange.new(0.9, 1.2)
		spray.Rate = 40
		spray.Speed = NumberRange.new(13, 15)
		spray.SpreadAngle = Vector2.new(6, 6)
		spray.Acceleration = Vector3.new(0, -22, 0)
		spray.EmissionDirection = Enum.NormalId.Top
		spray.Parent = attachment
	end
end

local function buildSpawns(folder: Folder, origin: Vector3): { CFrame }
	local pads = folderIn(folder, "Apparitions")
	local spawns: { CFrame } = {}
	local padColors = {
		Color3.fromRGB(255, 206, 64),
		Color3.fromRGB(110, 200, 255),
		Color3.fromRGB(255, 140, 120),
		Color3.fromRGB(170, 140, 255),
	}
	for index = 1, LAYOUT.SpawnCount do
		local angle = (index - 1) / LAYOUT.SpawnCount * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = origin + direction * LAYOUT.SpawnRingRadius
		local padColor = padColors[((index - 1) % #padColors) + 1]
		disc(pads, "Plot", 4.6, 0.3, position + Vector3.new(0, 0.3, 0), COLORS.white, Enum.Material.SmoothPlastic, { surface = "Rock" })
		disc(pads, "PlotCentre", 3.4, 0.32, position + Vector3.new(0, 0.32, 0), padColor, Enum.Material.SmoothPlastic, { collide = false, query = false, shadow = false })
		local standAt = position + Vector3.new(0, 3.5, 0)
		table.insert(spawns, CFrame.lookAt(standAt, standAt + direction))
	end
	return spawns
end

-- Emblème du stand construit par code (au-dessus de l'auvent).
local function buildEmblem(model: Model, kind: string, frame: CFrame, accent: Color3)
	if kind == "flag" then
		decor(model, "Mat", Vector3.new(0.3, 4, 0.3), frame * CFrame.new(0, 2, 0), COLORS.white, Enum.Material.SmoothPlastic)
		decor(model, "Fanion", Vector3.new(2.4, 1.5, 0.15), frame * CFrame.new(1.25, 3.2, 0), COLORS.red, Enum.Material.SmoothPlastic)
		decor(model, "Balle", Vector3.one * 1.2, frame * CFrame.new(0.9, 0.6, 0), COLORS.white, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Ball })
	elseif kind == "coin" then
		decor(model, "Piece", Vector3.new(0.5, 3.2, 3.2), frame * CFrame.new(0, 1.8, 0) * CFrame.Angles(0, math.pi / 2, 0), COLORS.gold, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
		decor(model, "Relief", Vector3.new(0.6, 2.2, 2.2), frame * CFrame.new(0, 1.8, 0) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(255, 226, 120), Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
	elseif kind == "hat" then
		decor(model, "Bord", Vector3.new(0.3, 3.6, 3.6), frame * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.pi / 2), COLORS.dark, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
		decor(model, "Calotte", Vector3.new(2.2, 2.2, 2.2), frame * CFrame.new(0, 1.4, 0) * CFrame.Angles(0, 0, math.pi / 2), COLORS.dark, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
		decor(model, "Ruban", Vector3.new(0.5, 2.3, 2.3), frame * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.pi / 2), accent, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
	elseif kind == "trophy" then
		decor(model, "Pied", Vector3.new(0.6, 2, 2), frame * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2), COLORS.woodDark, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
		decor(model, "Tige", Vector3.new(1.2, 0.5, 0.5), frame * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.pi / 2), COLORS.gold, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
		decor(model, "Coupe", Vector3.one * 2.4, frame * CFrame.new(0, 2.6, 0), COLORS.gold, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Ball })
		for _, side in { -1, 1 } do
			decor(model, "Anse", Vector3.new(0.3, 1.2, 1.2), frame * CFrame.new(side * 1.4, 2.8, 0), COLORS.gold, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
		end
	elseif kind == "target" then
		local rings = { COLORS.white, COLORS.red, COLORS.white, COLORS.red }
		for index, ringColor in rings do
			local size = 3.6 - (index - 1) * 0.8
			decor(model, "Cible", Vector3.new(0.3 + index * 0.04, size, size), frame * CFrame.new(0, 2, 0) * CFrame.Angles(0, math.pi / 2, 0), ringColor, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
		end
	end
end

-- Stand : plancher, comptoir, poteaux, enseigne, auvent festonné, emblème et invite.
local function buildKiosk(parent: Instance, origin: Vector3, spec: any, prompts: { ProximityPrompt }): CFrame
	local model = Instance.new("Model")
	model.Name = "Stand_" .. spec.name
	model:SetAttribute("Kiosk", spec.name)
	local position = origin + spec.position
	-- Le stand regarde le centre de la place (LookVector = vers les joueurs ; l'arrière est +Z local).
	local frame = standFacing(position, origin)
	local accent: Color3 = spec.color

	disc(model, "Plancher", 13, 0.4, position + Vector3.new(0, 0.2, 0), COLORS.cream, Enum.Material.SmoothPlastic, { surface = "Wood" })
	local counter = newPart(model, "Comptoir", Vector3.new(8, 2.8, 2.2), frame * CFrame.new(0, 1.8, -0.5), COLORS.white, Enum.Material.SmoothPlastic, { surface = "Wood" })
	decor(model, "Bandeau", Vector3.new(8.05, 0.8, 2.25), frame * CFrame.new(0, 2.2, -0.5), accent, Enum.Material.SmoothPlastic)
	newPart(model, "Plateau", Vector3.new(8.6, 0.3, 2.6), frame * CFrame.new(0, 3.35, -0.5), COLORS.woodDark, Enum.Material.WoodPlanks)
	for _, side in { -1, 1 } do
		newPart(model, "Poteau", Vector3.new(0.7, 9, 0.7), frame * CFrame.new(side * 5, 4.9, 2.4), COLORS.white, Enum.Material.SmoothPlastic)
	end
	local board = newPart(model, "Enseigne", Vector3.new(11, 3.6, 0.5), frame * CFrame.new(0, 7.2, 2.4), accent, Enum.Material.SmoothPlastic)
	decor(model, "Cadre", Vector3.new(11.6, 4.2, 0.4), frame * CFrame.new(0, 7.2, 2.55), COLORS.white, Enum.Material.SmoothPlastic)
	signText(board, spec.title, spec.sub)
	-- Auvent rayé incliné vers l'avant + feston de boules.
	local stripes = 6
	for index = 1, stripes do
		local x = -6 + (index - 0.5) * 12 / stripes
		local stripeColor = if index % 2 == 0 then COLORS.white else accent
		newPart(model, "Auvent", Vector3.new(12 / stripes, 0.35, 5.6), frame * CFrame.new(x, 9.6, 0.4) * CFrame.Angles(math.rad(-12), 0, 0), stripeColor, Enum.Material.SmoothPlastic)
	end
	for index = 1, 9 do
		local x = -5.6 + (index - 1) * 1.4
		decor(model, "Feston", Vector3.one * 0.9, frame * CFrame.new(x, 8.95, -2.4), if index % 2 == 0 then COLORS.white else accent, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Ball })
	end
	buildEmblem(model, spec.icon, frame * CFrame.new(0, 10.4, 1.2), accent)
	addPrompt(counter, "course.prompt.open", spec.title, { Kiosk = spec.name }, prompts)
	model.PrimaryPart = counter
	model.Parent = parent
	-- Où se placer : devant le comptoir, tourné vers lui.
	local standAt = (frame * CFrame.new(0, 3, -5)).Position
	return standFacing(standAt, position)
end

-- Tableau sur deux pieds (panneaux du green, du range et du podium).
local function buildSignpost(parent: Instance, frame: CFrame, width: number, height: number, accent: Color3, titleKey: string, subKey: string?, titleVars: { [string]: any }?)
	local model = Instance.new("Model")
	model.Name = "Panneau_" .. titleKey
	for _, side in { -1, 1 } do
		newPart(model, "Pied", Vector3.new(0.5, height + 2, 0.5), frame * CFrame.new(side * (width / 2 - 0.6), (height + 2) / 2, 0.3), COLORS.woodDark, Enum.Material.Wood)
	end
	local board = newPart(model, "Planche", Vector3.new(width, height, 0.4), frame * CFrame.new(0, 2 + height / 2, 0), accent, Enum.Material.SmoothPlastic)
	decor(model, "Liseré", Vector3.new(width + 0.4, height + 0.4, 0.3), frame * CFrame.new(0, 2 + height / 2, 0.12), COLORS.white, Enum.Material.SmoothPlastic)
	signText(board, titleKey, subKey, titleVars)
	model.PrimaryPart = board
	model.Parent = parent
	return board
end

local function buildFlag(parent: Instance, base: Vector3, height: number, clothColor: Color3)
	decor(parent, "Mat", Vector3.new(height, 0.25, 0.25), CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), COLORS.white, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
	decor(parent, "Drapeau", Vector3.new(0.1, 1.7, 2.8), CFrame.new(base + Vector3.new(1.45, height - 1, 0)), clothColor, Enum.Material.SmoothPlastic)
	decor(parent, "Pommeau", Vector3.one * 0.5, CFrame.new(base + Vector3.new(0, height + 0.2, 0)), COLORS.yellow, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Ball })
end

-- Distributeur de balles : seau sur un pied avec invite.
local function buildDispenser(parent: Instance, position: Vector3, area: string, objectKey: string, prompts: { ProximityPrompt })
	local model = Instance.new("Model")
	model.Name = "Distributeur_" .. area
	disc(model, "Pied", 0.8, 2.4, position + Vector3.new(0, 1.2, 0), COLORS.dark, Enum.Material.Metal)
	local bucket = disc(model, "Seau", 2.6, 1.8, position + Vector3.new(0, 3.2, 0), COLORS.red, Enum.Material.SmoothPlastic)
	disc(model, "Rebord", 2.9, 0.3, position + Vector3.new(0, 4.1, 0), COLORS.white, Enum.Material.SmoothPlastic, { collide = false, query = false })
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		ball(model, "Balle", 0.8, position + Vector3.new(math.cos(angle) * 0.6, 4.25, math.sin(angle) * 0.6), COLORS.white, Enum.Material.SmoothPlastic)
	end
	addPrompt(bucket, "course.prompt.takeBall", objectKey, { PracticeArea = area }, prompts)
	model.PrimaryPart = bucket
	model.Parent = parent
end

local function buildPracticeGreen(folder: Folder, origin: Vector3, prompts: { ProximityPrompt }, rng: Random, props: PropsModule?, palette: any?)
	local green = folderIn(folder, "GreenEntrainement")
	local center = origin + LAYOUT.GreenCenter
	local radius = LAYOUT.GreenRadius
	disc(green, "AvantGreen", (radius + LAYOUT.FringeWidth) * 2, 0.4, center + Vector3.new(0, -0.1, 0), COLORS.fringe, Enum.Material.SmoothPlastic, { surface = "Fairway" })
	disc(green, "Green", radius * 2, 0.4, center + Vector3.new(0, -0.02, 0), COLORS.green, Enum.Material.SmoothPlastic, { surface = "Green" })
	local top = center.Y + 0.18
	local cup = Vector3.new(center.X + LAYOUT.CupOffset.X, top, center.Z + LAYOUT.CupOffset.Z)
	disc(green, "Trou", LAYOUT.CupRadius * 2, 0.04, cup + Vector3.new(0, 0.005, 0), COLORS.dark, Enum.Material.SmoothPlastic, { collide = false, query = false, shadow = false })
	disc(green, "Anneau", LAYOUT.CupRadius * 2 + 0.4, 0.02, cup, COLORS.white, Enum.Material.SmoothPlastic, { collide = false, query = false, shadow = false })
	buildFlag(green, cup, 8, COLORS.red)
	-- Points de départ : arc côté ouest, tournés vers le trou.
	local spots: { CFrame } = {}
	for index = 1, 4 do
		local offset = Vector3.new(-9, 0, -6 + (index - 1) * 4)
		local spot = Vector3.new(center.X + offset.X, top, center.Z + offset.Z)
		table.insert(spots, CFrame.lookAt(spot, Vector3.new(cup.X, top, cup.Z)))
		decor(green, "Repere", Vector3.new(0.04, 0.8, 0.8), CFrame.new(spot + Vector3.new(0, 0.01, 0)) * CFrame.Angles(0, 0, math.pi / 2), COLORS.white, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder, shadow = false })
	end
	buildDispenser(green, center + Vector3.new(-14, 0, 8), "green", "course.sign.practice", prompts)
	local signPosition = center + Vector3.new(-17, 0, -10)
	buildSignpost(green, standFacing(signPosition, origin), 9, 3.2, Color3.fromRGB(70, 150, 90), "course.sign.practice", "course.sign.practiceSub")
	for index = 1, 5 do
		local angle = math.rad(-60 + index * 24)
		local position = center + Vector3.new(math.cos(angle) * (radius + 6), 0, math.sin(angle) * (radius + 6))
		placeProp(props, green, if index % 2 == 0 then "flowerbed" else "bush", CFrame.new(position), 0.9 + rng:NextNumber() * 0.3, rng, palette)
	end
	return {
		cup = cup,
		spots = spots,
		center = Vector3.new(center.X, top, center.Z),
		standAt = standFacing(center + Vector3.new(-14, 3, 3), cup),
	}
end

local function buildRange(folder: Folder, origin: Vector3, prompts: { ProximityPrompt }, rng: Random, props: PropsModule?, palette: any?)
	local range = folderIn(folder, "DrivingRange")
	local halfGround = LAYOUT.RangeGroundHalfWidth
	local startZ, endZ = LAYOUT.RangeStartZ, LAYOUT.RangeEndZ
	-- Terrain rayé (premier segment de la couleur de l'île : pas de scintillement au raccord).
	local segments: { { number } } = { { startZ, -100 } }
	local z = -100
	while z > endZ do
		table.insert(segments, { z, math.max(z - 30, endZ) })
		z -= 30
	end
	for index, segment in segments do
		local a, b = segment[1], segment[2]
		local length = a - b
		local segmentColor = if index == 1 then COLORS.grass elseif index % 2 == 0 then COLORS.grassDark else COLORS.grass
		newPart(range, "Terrain", Vector3.new(halfGround * 2, LAYOUT.IslandDepth, length), CFrame.new(origin + Vector3.new(0, -LAYOUT.IslandDepth / 2, (a + b) / 2)), segmentColor, Enum.Material.SmoothPlastic, { surface = "Fairway" })
	end
	newPart(range, "Falaise", Vector3.new(halfGround * 2 + 4, LAYOUT.IslandDepth, startZ - endZ + 4), CFrame.new(origin + Vector3.new(0, -LAYOUT.IslandDepth / 2 - 1.2, (startZ + endZ) / 2)), COLORS.cliff, Enum.Material.SmoothPlastic)

	-- Tertre de départ et points de frappe.
	local teeZ = LAYOUT.RangeTeeZ
	newPart(range, "Tertre", Vector3.new(44, 0.6, 12), CFrame.new(origin + Vector3.new(0, 0, teeZ + 2)), COLORS.grassTee, Enum.Material.SmoothPlastic, { surface = "Fairway" })
	local teeTop = origin.Y + 0.3
	local spots: { CFrame } = {}
	for index = 1, 5 do
		local x = -12 + (index - 1) * 6
		local spot = Vector3.new(origin.X + x, teeTop, origin.Z + teeZ)
		table.insert(spots, CFrame.lookAt(spot, spot + Vector3.new(0, 0, -1)))
		decor(range, "Tapis", Vector3.new(3, 0.06, 3), CFrame.new(spot + Vector3.new(0, 0.02, 0)), Color3.fromRGB(62, 140, 62), Enum.Material.SmoothPlastic, { shadow = false })
		ball(range, "Plot", 0.5, spot + Vector3.new(-1.2, 0.25, -1.2), COLORS.red, Enum.Material.SmoothPlastic)
	end
	buildDispenser(range, origin + Vector3.new(-19, 0.3, teeZ + 3), "range", "course.sign.range", prompts)
	buildSignpost(range, standFacing(origin + Vector3.new(19, 0.3, teeZ + 6), origin + Vector3.new(0, 0, 0)), 9, 3, Color3.fromRGB(60, 120, 200), "course.sign.range", "course.sign.rangeSub")

	-- Lignes et panneaux de distance.
	for _, distance in LAYOUT.RangeMarkers do
		local markerZ = teeZ - distance
		if markerZ <= endZ + 10 then
			continue
		end
		decor(range, "Ligne", Vector3.new(LAYOUT.RangeHalfWidth * 2 - 4, 0.06, 1.2), CFrame.new(origin + Vector3.new(0, 0.03, markerZ)), COLORS.white, Enum.Material.SmoothPlastic, { shadow = false })
		local signAt = origin + Vector3.new(-LAYOUT.RangeHalfWidth + 6, 0, markerZ)
		buildSignpost(range, CFrame.lookAt(signAt, signAt + Vector3.new(0, 0, 1)), 6, 2.6, COLORS.purple, "course.range.marker", nil, { n = distance })
	end
	-- Greens-cibles.
	for _, target in LAYOUT.RangeTargets do
		local center = origin + Vector3.new(target.x, 0, teeZ - target.distance)
		disc(range, "Cible", target.radius * 2 + 2, 0.3, center + Vector3.new(0, 0.02, 0), COLORS.white, Enum.Material.SmoothPlastic, { surface = "Green" })
		disc(range, "Cible", target.radius * 2, 0.3, center + Vector3.new(0, 0.06, 0), COLORS.green, Enum.Material.SmoothPlastic, { surface = "Green" })
		disc(range, "Centre", 3, 0.3, center + Vector3.new(0, 0.1, 0), target.color, Enum.Material.SmoothPlastic, { collide = false, query = false, shadow = false })
		buildFlag(range, center + Vector3.new(0, 0.2, 0), 9, target.color)
	end
	-- Butte de fond.
	newPart(range, "Butte", Vector3.new(halfGround * 2, 14, 30), CFrame.new(origin + Vector3.new(0, 7, endZ + 15)) * CFrame.Angles(0, math.pi, 0), COLORS.grassDark, Enum.Material.SmoothPlastic, { wedge = true, surface = "Rough" })
	-- Arbres le long du range, à l'extérieur des clôtures.
	local treeZ = startZ - 30
	while treeZ > endZ + 20 do
		for _, side in { -1, 1 } do
			local x = side * (LAYOUT.RangeHalfWidth + 9 + rng:NextNumber() * 6)
			placeProp(props, range, if rng:NextNumber() < 0.5 then "tree" else "pine", CFrame.new(origin + Vector3.new(x, 0, treeZ + rng:NextNumber() * 8)), 1 + rng:NextNumber() * 0.4, rng, palette)
		end
		treeZ -= 34
	end
	return {
		tee = spots[3],
		spots = spots,
		zone = {
			cframe = CFrame.new(origin + Vector3.new(0, 15, (startZ + endZ) / 2)),
			size = Vector3.new(LAYOUT.RangeHalfWidth * 2, 50, startZ - endZ),
		},
		standAt = standFacing(origin + Vector3.new(-17, 3.3, teeZ + 8), origin + Vector3.new(0, 3.3, teeZ - 50)),
	}
end

-- Porte-arche à l'entrée du range (titre du jeu + accueil).
local function buildGate(folder: Folder, origin: Vector3)
	local gate = Instance.new("Model")
	gate.Name = "PorteRange"
	local z = -70
	local frame = CFrame.lookAt(origin + Vector3.new(0, 0, z), origin + Vector3.new(0, 0, z + 10)) -- face vers la place
	for _, side in { -1, 1 } do
		newPart(gate, "Pilier", Vector3.new(3, 14, 3), frame * CFrame.new(side * 12, 7, 0), COLORS.white, Enum.Material.SmoothPlastic)
		newPart(gate, "Chapiteau", Vector3.new(4, 1, 4), frame * CFrame.new(side * 12, 14.5, 0), COLORS.red, Enum.Material.SmoothPlastic)
		decor(gate, "Boule", Vector3.one * 2.2, frame * CFrame.new(side * 12, 16.1, 0), COLORS.yellow, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Ball })
	end
	local banner = newPart(gate, "Banniere", Vector3.new(27, 5, 0.8), frame * CFrame.new(0, 12.5, 0), COLORS.red, Enum.Material.SmoothPlastic)
	decor(gate, "Cadre", Vector3.new(28, 5.8, 0.6), frame * CFrame.new(0, 12.5, 0.2), COLORS.yellow, Enum.Material.SmoothPlastic)
	signText(banner, "course.sign.welcome", "course.sign.welcomeSub")
	-- Revers (côté range) : panneau du driving range.
	local back = newPart(gate, "Revers", Vector3.new(20, 3, 0.4), frame * CFrame.new(0, 12.5, 0.65) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(60, 120, 200), Enum.Material.SmoothPlastic)
	signText(back, "course.sign.range")
	gate.PrimaryPart = banner
	gate.Parent = folder
end

local function buildPodium(folder: Folder, origin: Vector3): { [string]: CFrame }
	local podium = folderIn(folder, "Podium")
	local center = origin + LAYOUT.PodiumCenter
	local frame = standFacing(center, origin) -- tourné vers la place (public)
	disc(podium, "Estrade", 26, 0.5, center + Vector3.new(0, 0.25, 0), COLORS.purple, Enum.Material.SmoothPlastic, { surface = "Rock" })
	local heights = LAYOUT.PodiumHeights
	local stepColors = { COLORS.gold, COLORS.silver, COLORS.bronze }
	local labels = { "course.podium.first", "course.podium.second", "course.podium.third" }
	-- 2e à gauche du vainqueur vu du public (droite du podium), 3e de l'autre côté.
	local offsets = { 0, 6.4, -6.4 }
	local result: { [string]: CFrame } = {}
	for rank = 1, 3 do
		local height = heights[rank]
		local stepFrame = frame * CFrame.new(offsets[rank], height / 2 + 0.5, 0)
		local step = newPart(podium, "Marche" .. rank, Vector3.new(6, height, 6), stepFrame, COLORS.white, Enum.Material.SmoothPlastic, { surface = "Rock" })
		newPart(podium, "Dessus" .. rank, Vector3.new(6.4, 0.4, 6.4), frame * CFrame.new(offsets[rank], height + 0.7, 0), stepColors[rank], Enum.Material.SmoothPlastic, { surface = "Rock" })
		local plate = decor(podium, "Plaque" .. rank, Vector3.new(4, math.min(2.2, height - 0.4), 0.2), frame * CFrame.new(offsets[rank], height / 2 + 0.5, -3.05), stepColors[rank], Enum.Material.SmoothPlastic)
		signText(plate, labels[rank], nil, nil, COLORS.white)
		local top = (frame * CFrame.new(offsets[rank], height + 0.9 + 3, 0)).Position
		result["podium" .. rank] = CFrame.lookAt(top, top + frame.LookVector)
		step:SetAttribute("PodiumRank", rank)
	end
	-- Fond décoré et panneau.
	newPart(podium, "Fond", Vector3.new(24, 11, 1), frame * CFrame.new(0, 6, 5), COLORS.purple, Enum.Material.SmoothPlastic)
	local sign = newPart(podium, "Enseigne", Vector3.new(16, 3.4, 0.4), frame * CFrame.new(0, 9, 4.4), COLORS.red, Enum.Material.SmoothPlastic)
	signText(sign, "course.sign.podium", "course.sign.podiumSub")
	local starColors = { COLORS.yellow, COLORS.white, Color3.fromRGB(255, 140, 200), Color3.fromRGB(110, 200, 255) }
	for index = 1, 12 do
		local x = -11 + (index - 1) * 2
		local y = 2 + (index % 3) * 1.6
		decor(podium, "Pastille", Vector3.one * 0.9, frame * CFrame.new(x, y, 4.4), starColors[(index % #starColors) + 1], Enum.Material.Neon, { shape = Enum.PartType.Ball })
	end
	local viewAt = (frame * CFrame.new(0, 6, -22)).Position
	result.podiumView = CFrame.lookAt(viewAt, (frame * CFrame.new(0, 5, 0)).Position)
	return result
end

local function buildBoundary(folder: Folder, origin: Vector3)
	local boundary = folderIn(folder, "Enceinte")
	local halfRange = LAYOUT.RangeHalfWidth
	local function inRangeGap(point: Vector3): boolean
		return point.Z < origin.Z - 20 and math.abs(point.X - origin.X) < halfRange + 1
	end
	-- Clôture visible (poteaux + 2 lisses) sur le cercle de l'île, ouverte vers le range.
	local fenceRadius = LAYOUT.FenceRadius
	local posts = 56
	local previous: Vector3? = nil
	for index = 0, posts do
		local angle = index / posts * math.pi * 2
		local point = origin + Vector3.new(math.cos(angle) * fenceRadius, 0, math.sin(angle) * fenceRadius)
		local blocked = inRangeGap(point)
		if not blocked and index < posts then
			newPart(boundary, "Poteau", Vector3.new(0.8, 3.4, 0.8), CFrame.new(point + Vector3.new(0, 1.7, 0)), COLORS.white, Enum.Material.SmoothPlastic)
		end
		if previous and not blocked and not inRangeGap(previous) then
			local a: Vector3 = previous
			local middle = (a + point) / 2
			local length = (point - a).Magnitude
			for _, height in { 1.2, 2.6 } do
				newPart(boundary, "Lisse", Vector3.new(0.4, 0.4, length), CFrame.lookAt(middle + Vector3.new(0, height, 0), point + Vector3.new(0, height, 0)), COLORS.white, Enum.Material.SmoothPlastic)
			end
		end
		previous = point
	end
	-- Murs invisibles (île).
	local barrierRadius = LAYOUT.BarrierRadius
	local segments = LAYOUT.BarrierSegments
	local segmentLength = 2 * math.pi * barrierRadius / segments + 1
	for index = 1, segments do
		local angle = (index - 0.5) / segments * math.pi * 2
		local point = origin + Vector3.new(math.cos(angle) * barrierRadius, 0, math.sin(angle) * barrierRadius)
		if inRangeGap(point) then
			continue
		end
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		newPart(boundary, "MurInvisible", Vector3.new(segmentLength, LAYOUT.BarrierHeight, 2), CFrame.lookAt(point + Vector3.new(0, LAYOUT.BarrierHeight / 2 - 2, 0), point + Vector3.new(0, LAYOUT.BarrierHeight / 2 - 2, 0) + outward), COLORS.white, Enum.Material.SmoothPlastic, {
			transparency = 1,
			query = false,
			shadow = false,
		})
	end
	-- Range : clôtures latérales et de fond + murs invisibles.
	local startZ, endZ = -64, LAYOUT.RangeEndZ + 2
	for _, side in { -1, 1 } do
		local x = side * halfRange
		local z = startZ
		while z > endZ do
			local nextZ = math.max(z - 12, endZ)
			newPart(boundary, "Poteau", Vector3.new(0.8, 3.4, 0.8), CFrame.new(origin + Vector3.new(x, 1.7, z)), COLORS.white, Enum.Material.SmoothPlastic)
			for _, height in { 1.2, 2.6 } do
				newPart(boundary, "Lisse", Vector3.new(0.4, 0.4, z - nextZ), CFrame.new(origin + Vector3.new(x, height, (z + nextZ) / 2)), COLORS.white, Enum.Material.SmoothPlastic)
			end
			z = nextZ
		end
		local wallStart = -62
		newPart(boundary, "MurInvisible", Vector3.new(2, LAYOUT.BarrierHeight, wallStart - endZ), CFrame.new(origin + Vector3.new(x + side * 1, LAYOUT.BarrierHeight / 2 - 2, (wallStart + endZ) / 2)), COLORS.white, Enum.Material.SmoothPlastic, {
			transparency = 1,
			query = false,
			shadow = false,
		})
	end
	newPart(boundary, "MurInvisible", Vector3.new(halfRange * 2 + 4, LAYOUT.BarrierHeight + 20, 2), CFrame.new(origin + Vector3.new(0, (LAYOUT.BarrierHeight + 20) / 2 - 2, LAYOUT.RangeEndZ - 1)), COLORS.white, Enum.Material.SmoothPlastic, {
		transparency = 1,
		query = false,
		shadow = false,
	})
end

local function buildDecor(folder: Folder, origin: Vector3, rng: Random, props: PropsModule?, palette: any?, keepClear: { Vector3 })
	local decorFolder = folderIn(folder, "Decor")
	local function clear(position: Vector3, radius: number): boolean
		for _, point in keepClear do
			if (Vector3.new(position.X - point.X, 0, position.Z - point.Z)).Magnitude < radius then
				return false
			end
		end
		if position.Z < origin.Z - 40 and math.abs(position.X - origin.X) < LAYOUT.RangeHalfWidth + 4 then
			return false
		end
		return true
	end
	-- Couronne d'arbres et de buissons entre la place et la clôture.
	for index = 1, 30 do
		local angle = index / 30 * math.pi * 2 + rng:NextNumber() * 0.08
		local radius = 72 + rng:NextNumber() * 12
		local position = origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		if clear(position, 15) then
			local roll = rng:NextNumber()
			local kind = if roll < 0.45 then "tree" elseif roll < 0.65 then "pine" elseif roll < 0.85 then "bush" else "flowerbed"
			placeProp(props, decorFolder, kind, CFrame.new(position) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0), 0.9 + rng:NextNumber() * 0.5, rng, palette)
		end
	end
	-- Lampadaires au bord de la place.
	for index = 1, 8 do
		local angle = (index - 0.5) / 8 * math.pi * 2
		local position = origin + Vector3.new(math.cos(angle) * (LAYOUT.PlazaRadius - 2), 0.2, math.sin(angle) * (LAYOUT.PlazaRadius - 2))
		if clear(position, 9) then
			placeProp(props, decorFolder, "lamp", CFrame.new(position), 1, rng, palette)
		end
	end
	-- Bancs face à la fontaine et massifs fleuris.
	for index = 1, 4 do
		local angle = index / 4 * math.pi * 2 + math.pi / 8
		local position = origin + Vector3.new(math.cos(angle) * 34, 0.2, math.sin(angle) * 34)
		local towardCenter = CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z))
		placeProp(props, decorFolder, "bench", towardCenter, 1, rng, palette)
	end
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		local position = origin + Vector3.new(math.cos(angle) * 13.5, 0.2, math.sin(angle) * 13.5)
		placeProp(props, decorFolder, "flowerbed", CFrame.new(position), 0.8, rng, palette)
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function LobbyBuilder.build(origin: Vector3, parent: Instance): LobbyInfo
	local folderName = "Lobby"
	local config = Shared:FindFirstChild("Config")
	local courseModule = config and config:FindFirstChild("Course")
	local killDepth = LAYOUT.KillDepth
	if courseModule and courseModule:IsA("ModuleScript") then
		local ok, course = pcall(require, courseModule)
		if ok and type(course) == "table" then
			local world = (course :: any).World
			if type(world) == "table" and type(world.LobbyFolderName) == "string" then
				folderName = world.LobbyFolderName
			end
			local lobby = (course :: any).Lobby
			if type(lobby) == "table" and type(lobby.KillDepth) == "number" then
				killDepth = lobby.KillDepth
			end
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder:SetAttribute("GolfChaosGenerated", true)
	local rng = Random.new(LAYOUT.Seed)
	local props = loadProps()
	local palette = lobbyPalette()
	local prompts: { ProximityPrompt } = {}

	buildGround(folder, origin)
	buildFountain(folder, origin)
	local spawns = buildSpawns(folder, origin)
	local kioskFolder = folderIn(folder, "Stands")
	local kiosks: { [string]: CFrame } = {}
	local keepClear: { Vector3 } = { origin }
	for _, spec in KIOSKS do
		kiosks[spec.name] = buildKiosk(kioskFolder, origin, spec, prompts)
		table.insert(keepClear, origin + spec.position)
	end
	local practice = buildPracticeGreen(folder, origin, prompts, rng, props, palette)
	kiosks.practice = practice.standAt
	table.insert(keepClear, origin + LAYOUT.GreenCenter)
	local range = buildRange(folder, origin, prompts, rng, props, palette)
	kiosks.range = range.standAt
	buildGate(folder, origin)
	local podium = buildPodium(folder, origin)
	for key, value in podium do
		kiosks[key] = value
	end
	table.insert(keepClear, origin + LAYOUT.PodiumCenter)
	buildBoundary(folder, origin)
	do
		local positions: { Vector3 } = {}
		for _, spec in KIOSKS do
			table.insert(positions, spec.position)
		end
		local ok, extras = pcall(require, script.Parent.LobbyExtras)
		if ok then
			local built, reason = pcall(extras.build, folder, origin, positions)
			if not built then
				Log.warn("Lobby", "decor additionnel ignore : " .. tostring(reason))
			end
		end
	end
	buildDecor(folder, origin, rng, props, palette, keepClear)

	-- Une seule insertion dans le DataModel (réplication groupée).
	folder.Parent = parent

	local info: LobbyInfo = {
		folder = folder,
		spawns = spawns,
		spawn = spawns[1],
		practiceTee = practice.spots[1],
		practiceCup = practice.cup,
		practiceCupRadius = LAYOUT.CupRadius,
		practiceSpots = practice.spots,
		practiceGreenCenter = practice.center,
		practiceGreenRadius = LAYOUT.GreenRadius,
		rangeTee = range.tee,
		rangeSpots = range.spots,
		rangeZone = range.zone,
		kiosks = kiosks,
		bounds = {
			min = origin + Vector3.new(-LAYOUT.IslandRadius - 4, -60, LAYOUT.RangeEndZ - 10),
			max = origin + Vector3.new(LAYOUT.IslandRadius + 4, 260, LAYOUT.IslandRadius + 4),
		},
		killY = origin.Y - killDepth,
		prompts = prompts,
	}
	Log.info("Lobby", string.format("accueil construit (%d pièces)", #folder:GetDescendants()))
	return info
end

return LobbyBuilder
