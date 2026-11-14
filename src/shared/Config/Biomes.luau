--!strict
--[[
	Config/Biomes : identité visuelle de chaque biome (couleurs et matériaux des surfaces, falaises, eau, décor,
	éclairage, atmosphère, musique). DONNÉES UNIQUEMENT (aucune instance créée au require).

	Utilisé par : server/Course/HoleBuilder (sol, ponts, tunnels, dangers), server/Course/Props et
	Biomes/Common (palette de décor, fond), CourseService.ApplyBiomeLighting (presets Lighting et Atmosphere).
	Pas de ciel texturé (aucun AssetId) : le ciel par défaut est teinté par l'atmosphère et l'éclairage.
	Style : cartoon low-poly, couleurs franches, matériau SmoothPlastic majoritaire.

	  local Biomes = require(Shared.Config.Biomes)
	  local def = Biomes.get("Coast")      -- jamais nil (repli : Training)
	  def.ground.Fairway.color             -- Color3
	  def.lighting.ClockTime               -- 14.5
]]

export type SurfaceStyle = { color: Color3, material: Enum.Material, alt: Color3? } -- alt = teinte des bandes de tonte

export type LightingPreset = {
	ClockTime: number,
	Brightness: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	ColorShift_Top: Color3,
	EnvironmentDiffuseScale: number,
	EnvironmentSpecularScale: number,
	FogColor: Color3,
	FogStart: number,
	FogEnd: number,
}

export type AtmospherePreset = {
	Density: number,
	Offset: number,
	Color: Color3,
	Decay: Color3,
	Glare: number,
	Haze: number,
}

export type Palette = { [string]: { Color3 } }

export type WeightedKind = { kind: string, weight: number, scale: { number }? }

export type BiomeDef = {
	name: string,
	ground: { [string]: SurfaceStyle }, -- par surface du format (Fairway, Rough, Green, Sand...)
	borderSurface: string, -- surface des bordures latérales du ruban
	edge: SurfaceStyle, -- rebord biseauté sous le ruban
	cliff: SurfaceStyle, -- fondations (falaises, plateaux)
	floor: SurfaceStyle, -- sol de fond (sous la zone mortelle)
	tee: SurfaceStyle,
	teeMarkers: { Color3 },
	bridge: { deck: SurfaceStyle, rail: Color3, post: Color3, rope: boolean },
	tunnel: SurfaceStyle,
	water: { color: Color3, transparency: number, bed: Color3 },
	lava: { color: Color3, transparency: number },
	flag: { pole: Color3, cloth: Color3 },
	palette: Palette, -- couleurs du décor (Props)
	verge: { WeightedKind }, -- accessoires de bordure (près du chemin)
	far: { WeightedKind }, -- accessoires lointains
	decorDensity: number, -- multiplicateur du biome (× HoleDef.decorDensity)
	backdrop: string, -- "sea" | "forest" | "desert" | "snow" | "city" | "ring"
	lighting: LightingPreset,
	atmosphere: AtmospherePreset,
	music: string?, -- nom dans Config/Sounds
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function style(color: Color3, material: Enum.Material?, alt: Color3?): SurfaceStyle
	return { color = color, material = material or Enum.Material.SmoothPlastic, alt = alt }
end

-- Surfaces communes (chaque biome surcharge ce qui lui est propre).
local function baseGround(): { [string]: SurfaceStyle }
	return {
		Fairway = style(rgb(118, 196, 82), nil, rgb(104, 182, 72)),
		Rough = style(rgb(82, 150, 62)),
		Green = style(rgb(140, 220, 100)),
		Sand = style(rgb(240, 214, 150), Enum.Material.Sand),
		Ice = style(rgb(180, 228, 255), Enum.Material.Ice),
		Rock = style(rgb(150, 146, 140), Enum.Material.Slate),
		Wood = style(rgb(170, 118, 72), Enum.Material.WoodPlanks),
		Asphalt = style(rgb(78, 80, 88), Enum.Material.Asphalt),
		Snow = style(rgb(244, 248, 255), Enum.Material.Snow),
		Mud = style(rgb(116, 86, 60), Enum.Material.Mud),
	}
end

local Biomes = {}

Biomes.List = {} :: { [string]: BiomeDef }

--------------------------------------------------------------------------------
-- Côte : turquoise, sable doré, falaises claires, plein soleil
--------------------------------------------------------------------------------
do
	local ground = baseGround()
	ground.Fairway = style(rgb(122, 204, 92), nil, rgb(108, 190, 80))
	ground.Rough = style(rgb(86, 160, 70))
	ground.Green = style(rgb(150, 228, 108))
	ground.Sand = style(rgb(246, 222, 160), Enum.Material.Sand)
	ground.Wood = style(rgb(186, 134, 84), Enum.Material.WoodPlanks)
	Biomes.List.Coast = {
		name = "Coast",
		ground = ground,
		borderSurface = "Rough",
		edge = style(rgb(236, 214, 160)),
		cliff = style(rgb(214, 190, 150), Enum.Material.Sandstone),
		floor = style(rgb(232, 210, 158), Enum.Material.Sand),
		tee = style(rgb(132, 214, 100)),
		teeMarkers = { rgb(255, 255, 255), rgb(66, 135, 245) },
		bridge = { deck = style(rgb(186, 134, 84), Enum.Material.WoodPlanks), rail = rgb(222, 196, 140), post = rgb(130, 90, 56), rope = true },
		tunnel = style(rgb(150, 132, 112), Enum.Material.Slate),
		water = { color = rgb(40, 190, 210), transparency = 0.25, bed = rgb(240, 220, 160) },
		lava = { color = rgb(255, 110, 30), transparency = 0 },
		flag = { pole = rgb(250, 250, 250), cloth = rgb(255, 82, 82) },
		palette = {
			foliage = { rgb(76, 184, 76), rgb(96, 200, 84), rgb(60, 162, 80) },
			trunk = { rgb(150, 104, 64), rgb(170, 122, 78) },
			rock = { rgb(200, 192, 176), rgb(178, 170, 156), rgb(222, 212, 196) },
			flower = { rgb(255, 120, 150), rgb(255, 210, 80), rgb(255, 255, 255), rgb(255, 150, 60) },
			accent = { rgb(255, 82, 82), rgb(255, 255, 255), rgb(56, 170, 255), rgb(255, 200, 60) },
			sand = { rgb(246, 222, 160) },
			building = { rgb(255, 255, 255), rgb(250, 236, 210), rgb(200, 232, 255) },
			roof = { rgb(66, 135, 245), rgb(230, 90, 70) },
			metal = { rgb(90, 96, 110) },
		},
		verge = {
			{ kind = "palm", weight = 4, scale = { 0.8, 1.3 } },
			{ kind = "rock", weight = 3, scale = { 0.4, 1 } },
			{ kind = "bush", weight = 2, scale = { 0.7, 1.1 } },
			{ kind = "umbrella", weight = 1, scale = { 0.9, 1.1 } },
			{ kind = "flowerbed", weight = 1, scale = { 0.7, 1 } },
		},
		far = {
			{ kind = "palm", weight = 4, scale = { 0.9, 1.5 } },
			{ kind = "boulder", weight = 2, scale = { 0.8, 1.6 } },
			{ kind = "hut", weight = 1, scale = { 0.9, 1.2 } },
			{ kind = "boat", weight = 1, scale = { 1, 1.4 } },
			{ kind = "buoy", weight = 2, scale = { 1, 1.3 } },
		},
		decorDensity = 1,
		backdrop = "sea",
		lighting = {
			ClockTime = 14.5,
			Brightness = 2.6,
			Ambient = rgb(120, 120, 130),
			OutdoorAmbient = rgb(150, 160, 170),
			ColorShift_Top = rgb(255, 244, 214),
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.4,
			FogColor = rgb(190, 228, 245),
			FogStart = 400,
			FogEnd = 2200,
		},
		atmosphere = { Density = 0.28, Offset = 0.1, Color = rgb(200, 232, 250), Decay = rgb(120, 190, 230), Glare = 0.3, Haze = 1.2 },
		music = "music_match",
	}
end

--------------------------------------------------------------------------------
-- Forêt : verts profonds, terre, lumière dorée
--------------------------------------------------------------------------------
do
	local ground = baseGround()
	ground.Fairway = style(rgb(104, 182, 70), nil, rgb(92, 168, 62))
	ground.Rough = style(rgb(66, 130, 52))
	ground.Green = style(rgb(128, 206, 90))
	Biomes.List.Forest = {
		name = "Forest",
		ground = ground,
		borderSurface = "Rough",
		edge = style(rgb(120, 92, 62)),
		cliff = style(rgb(116, 88, 62), Enum.Material.Ground),
		floor = style(rgb(70, 120, 56), Enum.Material.Grass),
		tee = style(rgb(116, 194, 80)),
		teeMarkers = { rgb(255, 230, 90), rgb(255, 130, 60) },
		bridge = { deck = style(rgb(150, 104, 64), Enum.Material.WoodPlanks), rail = rgb(120, 84, 52), post = rgb(96, 66, 42), rope = false },
		tunnel = style(rgb(110, 80, 54), Enum.Material.Wood),
		water = { color = rgb(60, 150, 170), transparency = 0.3, bed = rgb(90, 80, 60) },
		lava = { color = rgb(255, 110, 30), transparency = 0 },
		flag = { pole = rgb(250, 250, 250), cloth = rgb(255, 200, 40) },
		palette = {
			foliage = { rgb(52, 140, 60), rgb(70, 160, 66), rgb(40, 120, 70), rgb(96, 170, 60) },
			trunk = { rgb(110, 74, 46), rgb(130, 90, 56) },
			rock = { rgb(130, 130, 124), rgb(110, 112, 108) },
			flower = { rgb(255, 230, 90), rgb(200, 120, 255), rgb(255, 120, 120) },
			accent = { rgb(230, 60, 60), rgb(255, 255, 255) },
			sand = { rgb(200, 180, 130) },
			building = { rgb(170, 120, 80) },
			roof = { rgb(150, 60, 50) },
			metal = { rgb(90, 96, 110) },
		},
		verge = {
			{ kind = "tree", weight = 3, scale = { 0.8, 1.3 } },
			{ kind = "pine", weight = 3, scale = { 0.8, 1.4 } },
			{ kind = "bush", weight = 3, scale = { 0.7, 1.2 } },
			{ kind = "mushroom", weight = 2, scale = { 0.5, 1 } },
			{ kind = "rock", weight = 1, scale = { 0.5, 1 } },
		},
		far = {
			{ kind = "pine", weight = 5, scale = { 1.2, 2.2 } },
			{ kind = "tree", weight = 4, scale = { 1.2, 2 } },
			{ kind = "birch", weight = 2, scale = { 1, 1.6 } },
		},
		decorDensity = 1.3,
		backdrop = "forest",
		lighting = {
			ClockTime = 16.2,
			Brightness = 2.2,
			Ambient = rgb(110, 115, 100),
			OutdoorAmbient = rgb(140, 150, 120),
			ColorShift_Top = rgb(255, 226, 170),
			EnvironmentDiffuseScale = 0.5,
			EnvironmentSpecularScale = 0.3,
			FogColor = rgb(170, 200, 160),
			FogStart = 250,
			FogEnd = 1600,
		},
		atmosphere = { Density = 0.35, Offset = 0.15, Color = rgb(210, 230, 190), Decay = rgb(140, 170, 110), Glare = 0.2, Haze = 1.6 },
		music = "music_match",
	}
end

--------------------------------------------------------------------------------
-- Désert : ocres, grès, soleil écrasant
--------------------------------------------------------------------------------
do
	local ground = baseGround()
	ground.Fairway = style(rgb(170, 196, 92), nil, rgb(158, 184, 84))
	ground.Rough = style(rgb(214, 180, 120), Enum.Material.Sand)
	ground.Green = style(rgb(150, 212, 96))
	ground.Sand = style(rgb(236, 196, 128), Enum.Material.Sand)
	ground.Rock = style(rgb(206, 140, 90), Enum.Material.Sandstone)
	Biomes.List.Desert = {
		name = "Desert",
		ground = ground,
		borderSurface = "Sand",
		edge = style(rgb(220, 160, 104)),
		cliff = style(rgb(204, 128, 82), Enum.Material.Sandstone),
		floor = style(rgb(232, 190, 126), Enum.Material.Sand),
		tee = style(rgb(176, 204, 96)),
		teeMarkers = { rgb(255, 255, 255), rgb(230, 80, 60) },
		bridge = { deck = style(rgb(176, 130, 86), Enum.Material.WoodPlanks), rail = rgb(150, 110, 70), post = rgb(120, 84, 52), rope = true },
		tunnel = style(rgb(196, 124, 80), Enum.Material.Sandstone),
		water = { color = rgb(50, 180, 200), transparency = 0.25, bed = rgb(220, 190, 130) },
		lava = { color = rgb(255, 110, 30), transparency = 0 },
		flag = { pole = rgb(250, 250, 250), cloth = rgb(60, 140, 255) },
		palette = {
			foliage = { rgb(110, 170, 70), rgb(130, 180, 80) },
			trunk = { rgb(150, 110, 70) },
			rock = { rgb(214, 140, 90), rgb(190, 120, 80), rgb(230, 170, 110) },
			flower = { rgb(255, 120, 160), rgb(255, 220, 90) },
			accent = { rgb(230, 80, 60), rgb(60, 140, 255), rgb(255, 220, 90) },
			sand = { rgb(236, 196, 128) },
			cactus = { rgb(84, 160, 84), rgb(70, 146, 90) },
			building = { rgb(230, 200, 150) },
			roof = { rgb(200, 110, 70) },
			metal = { rgb(90, 96, 110) },
		},
		verge = {
			{ kind = "cactus", weight = 4, scale = { 0.7, 1.3 } },
			{ kind = "rock", weight = 3, scale = { 0.5, 1.1 } },
			{ kind = "duneGrass", weight = 3, scale = { 0.7, 1.2 } },
		},
		far = {
			{ kind = "dune", weight = 4, scale = { 1, 2 } },
			{ kind = "boulder", weight = 3, scale = { 1, 2 } },
			{ kind = "cactus", weight = 3, scale = { 1, 1.8 } },
			{ kind = "palm", weight = 1, scale = { 1, 1.4 } },
		},
		decorDensity = 0.9,
		backdrop = "desert",
		lighting = {
			ClockTime = 13,
			Brightness = 3,
			Ambient = rgb(140, 120, 100),
			OutdoorAmbient = rgb(170, 150, 120),
			ColorShift_Top = rgb(255, 230, 190),
			EnvironmentDiffuseScale = 0.5,
			EnvironmentSpecularScale = 0.3,
			FogColor = rgb(240, 210, 170),
			FogStart = 350,
			FogEnd = 2000,
		},
		atmosphere = { Density = 0.32, Offset = 0.05, Color = rgb(250, 220, 180), Decay = rgb(220, 160, 110), Glare = 0.6, Haze = 2 },
		music = "music_match",
	}
end

--------------------------------------------------------------------------------
-- Neige : blancs bleutés, glace, lumière froide
--------------------------------------------------------------------------------
do
	local ground = baseGround()
	ground.Fairway = style(rgb(150, 200, 130), nil, rgb(138, 190, 122))
	ground.Rough = style(rgb(236, 244, 252), Enum.Material.Snow)
	ground.Green = style(rgb(150, 214, 128))
	Biomes.List.Snow = {
		name = "Snow",
		ground = ground,
		borderSurface = "Snow",
		edge = style(rgb(220, 232, 245)),
		cliff = style(rgb(150, 162, 182), Enum.Material.Slate),
		floor = style(rgb(240, 246, 255), Enum.Material.Snow),
		tee = style(rgb(156, 206, 136)),
		teeMarkers = { rgb(255, 70, 70), rgb(70, 140, 255) },
		bridge = { deck = style(rgb(150, 110, 76), Enum.Material.WoodPlanks), rail = rgb(220, 232, 245), post = rgb(110, 80, 56), rope = false },
		tunnel = style(rgb(170, 210, 240), Enum.Material.Ice),
		water = { color = rgb(60, 120, 170), transparency = 0.2, bed = rgb(80, 100, 120) },
		lava = { color = rgb(255, 110, 30), transparency = 0 },
		flag = { pole = rgb(250, 250, 250), cloth = rgb(255, 70, 70) },
		palette = {
			foliage = { rgb(46, 110, 80), rgb(60, 126, 90) },
			trunk = { rgb(110, 80, 56) },
			rock = { rgb(150, 160, 178), rgb(130, 140, 160) },
			flower = { rgb(255, 255, 255) },
			accent = { rgb(255, 70, 70), rgb(70, 140, 255), rgb(255, 210, 60) },
			snow = { rgb(244, 248, 255) },
			ice = { rgb(170, 220, 255), rgb(200, 236, 255) },
			building = { rgb(170, 120, 80) },
			roof = { rgb(240, 246, 255) },
			metal = { rgb(90, 96, 110) },
		},
		verge = {
			{ kind = "pine", weight = 4, scale = { 0.8, 1.3 } },
			{ kind = "snowman", weight = 1, scale = { 0.8, 1.1 } },
			{ kind = "iceCrystal", weight = 2, scale = { 0.6, 1.2 } },
			{ kind = "rock", weight = 2, scale = { 0.5, 1 } },
		},
		far = {
			{ kind = "pine", weight = 6, scale = { 1.2, 2.2 } },
			{ kind = "boulder", weight = 2, scale = { 1, 1.8 } },
			{ kind = "iceCrystal", weight = 1, scale = { 1.5, 2.5 } },
		},
		decorDensity = 1,
		backdrop = "snow",
		lighting = {
			ClockTime = 11,
			Brightness = 2.4,
			Ambient = rgb(130, 140, 160),
			OutdoorAmbient = rgb(170, 180, 200),
			ColorShift_Top = rgb(220, 235, 255),
			EnvironmentDiffuseScale = 0.7,
			EnvironmentSpecularScale = 0.6,
			FogColor = rgb(220, 232, 248),
			FogStart = 200,
			FogEnd = 1400,
		},
		atmosphere = { Density = 0.4, Offset = 0.2, Color = rgb(230, 240, 255), Decay = rgb(170, 190, 220), Glare = 0.4, Haze = 2.2 },
		music = "music_match",
	}
end

--------------------------------------------------------------------------------
-- Ville : asphalte, briques, néons doux, fin d'après-midi
--------------------------------------------------------------------------------
do
	local ground = baseGround()
	ground.Fairway = style(rgb(112, 190, 86), nil, rgb(100, 176, 76))
	ground.Rough = style(rgb(180, 180, 176), Enum.Material.Concrete)
	Biomes.List.City = {
		name = "City",
		ground = ground,
		borderSurface = "Rock", -- trottoirs
		edge = style(rgb(196, 196, 190), Enum.Material.Concrete),
		cliff = style(rgb(150, 150, 156), Enum.Material.Concrete),
		floor = style(rgb(86, 88, 96), Enum.Material.Asphalt),
		tee = style(rgb(120, 198, 90)),
		teeMarkers = { rgb(255, 210, 60), rgb(255, 255, 255) },
		bridge = { deck = style(rgb(150, 150, 156), Enum.Material.Concrete), rail = rgb(60, 70, 90), post = rgb(60, 70, 90), rope = false },
		tunnel = style(rgb(130, 130, 136), Enum.Material.Concrete),
		water = { color = rgb(50, 130, 160), transparency = 0.2, bed = rgb(70, 80, 90) },
		lava = { color = rgb(255, 110, 30), transparency = 0 },
		flag = { pole = rgb(250, 250, 250), cloth = rgb(255, 210, 60) },
		palette = {
			foliage = { rgb(76, 170, 76), rgb(96, 186, 84) },
			trunk = { rgb(120, 84, 56) },
			rock = { rgb(150, 150, 156) },
			flower = { rgb(255, 120, 150), rgb(255, 210, 80) },
			accent = { rgb(255, 210, 60), rgb(255, 82, 82), rgb(60, 140, 255) },
			building = { rgb(220, 120, 90), rgb(240, 220, 180), rgb(130, 170, 220), rgb(200, 200, 210), rgb(250, 190, 110) },
			roof = { rgb(70, 74, 86), rgb(120, 60, 50) },
			metal = { rgb(60, 70, 90) },
		},
		verge = {
			{ kind = "lamp", weight = 3, scale = { 1, 1 } },
			{ kind = "bench", weight = 2, scale = { 1, 1 } },
			{ kind = "tree", weight = 2, scale = { 0.8, 1.1 } },
			{ kind = "cone", weight = 2, scale = { 0.8, 1.2 } },
			{ kind = "flowerbed", weight = 1, scale = { 0.8, 1 } },
		},
		far = {
			{ kind = "building", weight = 6, scale = { 1, 2.2 } },
			{ kind = "house", weight = 2, scale = { 1, 1.4 } },
			{ kind = "tree", weight = 2, scale = { 1, 1.5 } },
		},
		decorDensity = 1,
		backdrop = "city",
		lighting = {
			ClockTime = 17.3,
			Brightness = 2,
			Ambient = rgb(120, 110, 120),
			OutdoorAmbient = rgb(150, 140, 150),
			ColorShift_Top = rgb(255, 200, 160),
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.5,
			FogColor = rgb(220, 190, 180),
			FogStart = 300,
			FogEnd = 1800,
		},
		atmosphere = { Density = 0.33, Offset = 0.1, Color = rgb(240, 210, 200), Decay = rgb(200, 140, 130), Glare = 0.4, Haze = 1.6 },
		music = "music_match",
	}
end

--------------------------------------------------------------------------------
-- Entraînement : practice soigné, ciel clair
--------------------------------------------------------------------------------
do
	local ground = baseGround()
	ground.Fairway = style(rgb(116, 200, 84), nil, rgb(100, 184, 72))
	ground.Rough = style(rgb(78, 152, 62))
	ground.Green = style(rgb(146, 226, 106))
	Biomes.List.Training = {
		name = "Training",
		ground = ground,
		borderSurface = "Rough",
		edge = style(rgb(240, 236, 226)),
		cliff = style(rgb(150, 120, 90), Enum.Material.Ground),
		floor = style(rgb(96, 170, 76), Enum.Material.Grass),
		tee = style(rgb(126, 210, 92)),
		teeMarkers = { rgb(255, 255, 255), rgb(255, 82, 82) },
		bridge = { deck = style(rgb(176, 126, 80), Enum.Material.WoodPlanks), rail = rgb(250, 250, 250), post = rgb(120, 84, 52), rope = false },
		tunnel = style(rgb(150, 146, 140), Enum.Material.Slate),
		water = { color = rgb(56, 170, 220), transparency = 0.25, bed = rgb(200, 190, 150) },
		lava = { color = rgb(255, 110, 30), transparency = 0 },
		flag = { pole = rgb(250, 250, 250), cloth = rgb(255, 82, 82) },
		palette = {
			foliage = { rgb(76, 176, 76), rgb(96, 196, 84), rgb(60, 156, 80) },
			trunk = { rgb(140, 98, 60) },
			rock = { rgb(170, 166, 160) },
			flower = { rgb(255, 120, 150), rgb(255, 210, 80), rgb(255, 255, 255), rgb(170, 120, 255) },
			accent = { rgb(255, 82, 82), rgb(255, 255, 255), rgb(56, 170, 255), rgb(255, 200, 60) },
			building = { rgb(255, 255, 255) },
			roof = { rgb(56, 170, 255) },
			metal = { rgb(90, 96, 110) },
		},
		verge = {
			{ kind = "bush", weight = 3, scale = { 0.7, 1.1 } },
			{ kind = "flowerbed", weight = 2, scale = { 0.7, 1.1 } },
			{ kind = "tree", weight = 2, scale = { 0.8, 1.2 } },
		},
		far = {
			{ kind = "tree", weight = 4, scale = { 1, 1.8 } },
			{ kind = "pine", weight = 2, scale = { 1, 1.8 } },
			{ kind = "birch", weight = 2, scale = { 1, 1.5 } },
		},
		decorDensity = 0.9,
		backdrop = "ring",
		lighting = {
			ClockTime = 14,
			Brightness = 2.5,
			Ambient = rgb(120, 120, 128),
			OutdoorAmbient = rgb(150, 156, 166),
			ColorShift_Top = rgb(255, 240, 214),
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.4,
			FogColor = rgb(200, 226, 245),
			FogStart = 400,
			FogEnd = 2200,
		},
		atmosphere = { Density = 0.26, Offset = 0.1, Color = rgb(205, 230, 250), Decay = rgb(130, 180, 220), Glare = 0.25, Haze = 1 },
		music = "music_lobby",
	}
end

--------------------------------------------------------------------------------
-- Accueil (Lobby) : même famille que l'entraînement, plus festif
--------------------------------------------------------------------------------
do
	local training = Biomes.List.Training
	local lobby = table.clone(training)
	lobby.name = "Lobby"
	lobby.decorDensity = 1.1
	lobby.lighting = table.clone(training.lighting)
	lobby.lighting.ClockTime = 14.8
	lobby.lighting.Brightness = 2.6
	lobby.atmosphere = table.clone(training.atmosphere)
	lobby.music = "music_lobby"
	Biomes.List.Lobby = lobby
end

-- Matériaux réalistes : herbe (Grass) pour fairway/rough/green, sol (Ground) pour les bordures et le terreau.
-- Seul le rendu change : la physique de la balle lit l'attribut "Surface", jamais le matériau.
do
	local seen: { [any]: boolean } = {}
	for _, biome in Biomes.List do
		if not seen[biome.ground] then
			seen[biome.ground] = true
			for _, name in { "Fairway", "Rough", "Green" } do
				local entry = biome.ground[name]
				if entry and entry.material == Enum.Material.SmoothPlastic then
					entry.material = Enum.Material.Grass
				end
			end
		end
		if biome.edge.material == Enum.Material.SmoothPlastic then
			biome.edge = { color = biome.edge.color, material = Enum.Material.Ground, alt = biome.edge.alt }
		end
	end
end

-- Définition d'un biome (repli : Training, jamais nil).
function Biomes.get(name: string?): BiomeDef
	return (name and Biomes.List[name]) or Biomes.List.Training
end

-- Style d'une surface du format pour un biome (repli : Fairway).
function Biomes.surfaceStyle(biome: BiomeDef, surface: string): SurfaceStyle
	return biome.ground[surface] or biome.ground.Fairway
end

return Biomes
