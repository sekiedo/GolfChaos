--!strict
--[[
	CourseService — construction et nettoyage des trous, accueil, éclairage par biome, checkpoints, limites
	(docs/ARCHITECTURE.md §8, priorité 25).

	TROUS
	  LoadHole(def) -> HoleRuntime?     construit le trou à Config.Course.HoleOrigin (repli (0, 0, 5000)) dans
	                                    Workspace.Course via server/Course/HoleBuilder, fait apparaître les obstacles
	                                    (server/Course/Obstacles), règle le trou de BallService (SetCup) et l'éclairage
	                                    du biome. Tout ce qui appartient au trou vit dans une Trove de manche.
	                                    Retourne nil (et journalise) si le constructeur est absent ou échoue.
	  UnloadHole()                      détruit le trou (géométrie, obstacles, connexions), BallService.SetCup(nil).
	  GetCurrent() -> HoleRuntime?      trou chargé (types : shared/Types.luau).
	  GetExtras() -> HoleExtras?        données du constructeur absentes de HoleRuntime (boîtes de mobilité,
	                                    voiturettes, centre du green, obstacles, nombre de pièces).
	  GetCheckpointFor(position) -> CFrame   meilleur checkpoint qui n'est pas en avant de la position le long du
	                                    chemin (tolérance Config.Course.Checkpoint.BehindTolerance) ; le départ sinon ;
	                                    l'apparition de l'accueil quand aucun trou n'est chargé.
	  GetPathProgress(position) -> number    progression (studs) le long de la ligne centrale du trou chargé.
	  IsOutOfBounds(position) -> boolean     hors des bornes, sous killY ou dans un danger "oob"/"void" (trou) ;
	                                    hors de l'enceinte ou sous la zone mortelle (accueil).
	  GetStartPlacements(count) -> { CFrame }  départs équitables : tous à la même distance horizontale du trou
	                                    (arc centré sur le trou, à 1 stud près), espacés de 5 à 6 studs, sur un sol du
	                                    parcours, hors dangers et obstacles, orientés vers le premier segment du chemin.
	                                    Position = point au sol où poser la balle ; le joueur se place derrière
	                                    (Config.Course.Tee.PlayerOffset dans le repère du CFrame).
	  BuildPreview(holeId | def, origin?) -> Folder?   construction d'inspection (mode Édition possible : barre de
	                                    commande) dans Workspace.CoursePreviews, obstacles immobiles, sans BallService.
	  Signaux : HoleLoaded(runtime), HoleUnloaded().

	ÉCLAIRAGE
	  ApplyBiomeLighting(biome?)        propriétés de Lighting + une Atmosphere gérée ; "Lobby" sans biome.
	                                    Lit Config.Biomes[biome].lighting / .atmosphere (tables de propriétés,
	                                    noms Roblox ou camelCase) par-dessus des préréglages de repli intégrés.
	                                    Appliqué automatiquement : biome du trou au chargement, "Lobby" quand la
	                                    phase passe à Lobby / Preparing / Podium sans trou chargé.

	ACCUEIL (construit dans Start à Config.Course.LobbyOrigin, repli (0, 0, 0), toujours chargé)
	  GetLobby() -> LobbyInfo           { spawns, spawn, practiceTee, practiceCup, practiceCupRadius, rangeTee,
	                                      kiosks = { play, shop, customize, challenges, training, practice, range,
	                                      podium1, podium2, podium3 }, ... } (voir server/Course/LobbyBuilder.luau).
	  IsInLobbyPractice(position) -> boolean   sur le green d'entraînement ou sur le driving range.
	  GetPracticeCup() -> (Vector3?, number)   trou du green d'entraînement.
	  Entraînement : les distributeurs de balles (ProximityPrompt, attribut PracticeArea) donnent une balle
	  d'entraînement (BallService.SpawnBall(..., { practice = true })) pendant Ball.PracticePhases. BallService ne
	  gère qu'un seul trou (celui de la partie, capture en phase Playing) : CourseService surveille donc lui-même
	  le trou du green d'entraînement (balle lente au-dessus du trou -> balle posée dans le trou, effets, retour
	  au point de départ du green).
	  Sécurité : un personnage tombé sous la zone mortelle de l'accueil est ramené sur la place.

	OUTIL STUDIO (RunService:IsStudio() uniquement)
	  CourseService.Dev.BuildAllPreviews(spacing?, biome?) -> Folder?   tous les trous de Holes.all() côte à côte
	  (une rangée par biome) pour les captures d'écran. Exemple (barre de commande, mode Édition) :
	    require(game.ServerScriptService.Server.Services.CourseService).Dev.BuildAllPreviews(900)

	Dépendances chargées à la demande (pcall) : server/Course/HoleBuilder, Obstacles, LobbyBuilder,
	shared/Data/Holes, shared/Config/Biomes, BallService, MovementService, Net. Une dépendance absente dégrade
	la fonction concernée (journal unique), sans erreur au chargement.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local GameState = require(Shared.Util.GameState)
local Log = require(Shared.Util.Log)
local SignalModule = require(Shared.Util.Signal)
local TroveModule = require(Shared.Util.Trove)
local Validate = require(Shared.Util.Validate)

local PathMath = require(script.Parent.Parent.Course.PathMath)
type Trove = TroveModule.Trove
type Signal = SignalModule.Signal
type HoleDef = Types.HoleDef
type HoleRuntime = Types.HoleRuntime
type ObstacleDef = Types.ObstacleDef

--------------------------------------------------------------------------------
-- Types publics
--------------------------------------------------------------------------------

export type Bounds = PathMath.Bounds

export type LobbyInfo = {
	folder: Folder?,
	spawns: { CFrame },
	spawn: CFrame,
	practiceTee: CFrame,
	practiceCup: Vector3,
	practiceCupRadius: number,
	rangeTee: CFrame,
	kiosks: { [string]: CFrame },
	practiceSpots: { CFrame }?,
	rangeSpots: { CFrame }?,
	practiceGreenCenter: Vector3?,
	practiceGreenRadius: number?,
	rangeZone: { cframe: CFrame, size: Vector3 }?,
	bounds: Bounds?,
	killY: number?,
	prompts: { ProximityPrompt }?,
}

export type Zone = PathMath.Zone

export type HoleExtras = {
	mobilityBoxes: { Vector3 },
	carts: { CFrame },
	greenCenter: Vector3,
	obstacles: { ObstacleDef },
	obstacleModels: { Model },
	hazards: { Zone },
	partCount: number,
}

type HoleState = {
	runtime: HoleRuntime,
	extras: HoleExtras,
	trove: Trove,
	pathPoints: { Vector3 },
	pathCumulative: { number },
	checkpointProgress: { number },
	firstDirection: Vector3,
	oobZones: { Zone },
	allZones: { Zone },
	obstaclesFolder: Folder,
}

type LightingPreset = {
	lighting: { [string]: any },
	atmosphere: { [string]: any },
}

--------------------------------------------------------------------------------
-- Réglages internes (valeurs de repli quand Config.Course ne les fournit pas)
--------------------------------------------------------------------------------

local DEFAULT_HOLE_ORIGIN = Vector3.new(0, 0, 5000)
local DEFAULT_LOBBY_ORIGIN = Vector3.zero
local DEFAULT_PREVIEW_ORIGIN = Vector3.new(3000, 0, 0)
local DEFAULT_CUP_RADIUS = 1.7
local DEFAULT_KILL_MARGIN = 30
local DEFAULT_BOUNDS_MARGIN = 40
local DEFAULT_BOUNDS_CEILING = 160
local DEFAULT_BEHIND_TOLERANCE = 8
local DEFAULT_LOBBY_KILL_DEPTH = 45

local GENERATED_ATTRIBUTE = "GolfChaosGenerated" -- dossiers générés (nettoyés au démarrage s'ils traînent)
local ATMOSPHERE_NAME = "GolfChaosAtmosphere"
local LIGHT_TWEEN_TIME = 1.2 -- transition d'éclairage (s)
local REGION_MARGIN = 250 -- autour des bornes : une position y appartient encore au trou / à l'accueil
local START_SPACINGS = { 6, 5 } -- espacements essayés entre deux départs (exigence : 5 à 7 studs)
local START_RADIUS_OFFSETS = { 0, -3, 3, -6, 6, -9, 9, -12, 12 } -- rayons d'arc essayés autour du départ
local START_MAX_STEPS_PER_SIDE = 16
local START_MAX_HEIGHT_DELTA = 4 -- écart d'altitude maximal d'un départ avec le tertre
local START_MIN_NORMAL_Y = 0.85 -- sol presque plat
local START_OBSTACLE_CLEARANCE = 1.8
local RESCUE_INTERVAL = 0.5 -- surveillance des chutes dans l'accueil (s)
local PRACTICE_WATCH_INTERVAL = 1 / 20 -- surveillance du trou d'entraînement (s)
local PRACTICE_CAPTURE_SPEED = 22 -- vitesse maximale (studs/s) d'une balle capturée par le trou d'entraînement
local PRACTICE_CAPTURE_HEIGHT = 2 -- écart vertical maximal balle / trou
local PRACTICE_RETURN_DELAY = 1.4 -- délai avant le retour de la balle au départ du green (s)
local PRACTICE_PROMPT_COOLDOWN = 1.5 -- délai entre deux balles d'entraînement d'un même joueur (s)
local PRACTICE_PROMPT_MAX_DISTANCE = 26 -- distance maximale joueur / point de départ (contrôle serveur)
local PRACTICE_SPOT_CLEARANCE = 2.5 -- un point de départ est libre si aucune balle n'est à moins de 2,5 studs
local DEFAULT_PRACTICE_PHASES = { "Lobby", "Preparing" }
local PLAYER_OFFSET = CFrame.new(0, 3, 3.5) -- joueur derrière sa balle (repli de Config.Course.Tee.PlayerOffset)

-- Préréglages de repli (Config.Biomes les complète ou les remplace propriété par propriété).
local FALLBACK_PRESETS: { [string]: LightingPreset } = {
	Lobby = {
		lighting = {
			ClockTime = 14.2,
			Brightness = 2.6,
			Ambient = Color3.fromRGB(122, 122, 138),
			OutdoorAmbient = Color3.fromRGB(150, 150, 162),
			ColorShift_Top = Color3.fromRGB(255, 242, 222),
			ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
			EnvironmentDiffuseScale = 1,
			EnvironmentSpecularScale = 0.6,
			ExposureCompensation = 0.1,
			GeographicLatitude = 32,
			FogStart = 0,
			FogEnd = 100000,
			FogColor = Color3.fromRGB(200, 222, 255),
		},
		atmosphere = {
			Density = 0.28,
			Offset = 0.2,
			Color = Color3.fromRGB(199, 221, 255),
			Decay = Color3.fromRGB(106, 140, 180),
			Glare = 0.15,
			Haze = 0.8,
		},
	},
	Coast = {
		lighting = {
			ClockTime = 15,
			Brightness = 3,
			Ambient = Color3.fromRGB(125, 130, 142),
			OutdoorAmbient = Color3.fromRGB(160, 166, 178),
			ColorShift_Top = Color3.fromRGB(255, 240, 215),
			ExposureCompensation = 0.1,
		},
		atmosphere = {
			Density = 0.3,
			Offset = 0.15,
			Color = Color3.fromRGB(200, 230, 255),
			Decay = Color3.fromRGB(90, 150, 200),
			Glare = 0.3,
			Haze = 1.2,
		},
	},
	Forest = {
		lighting = {
			ClockTime = 10.5,
			Brightness = 2.3,
			Ambient = Color3.fromRGB(110, 125, 105),
			OutdoorAmbient = Color3.fromRGB(130, 150, 120),
			ColorShift_Top = Color3.fromRGB(255, 245, 210),
			ExposureCompensation = 0.05,
		},
		atmosphere = {
			Density = 0.38,
			Offset = 0.1,
			Color = Color3.fromRGB(200, 225, 200),
			Decay = Color3.fromRGB(90, 120, 90),
			Glare = 0.1,
			Haze = 1.6,
		},
	},
	Desert = {
		lighting = {
			ClockTime = 13,
			Brightness = 3.4,
			Ambient = Color3.fromRGB(150, 130, 110),
			OutdoorAmbient = Color3.fromRGB(185, 160, 130),
			ColorShift_Top = Color3.fromRGB(255, 225, 180),
			ExposureCompensation = 0,
		},
		atmosphere = {
			Density = 0.33,
			Offset = 0.1,
			Color = Color3.fromRGB(255, 230, 190),
			Decay = Color3.fromRGB(200, 150, 100),
			Glare = 0.4,
			Haze = 2,
		},
	},
	Snow = {
		lighting = {
			ClockTime = 12,
			Brightness = 2.8,
			Ambient = Color3.fromRGB(140, 150, 170),
			OutdoorAmbient = Color3.fromRGB(175, 185, 205),
			ColorShift_Top = Color3.fromRGB(230, 240, 255),
			ExposureCompensation = -0.1,
		},
		atmosphere = {
			Density = 0.42,
			Offset = 0.1,
			Color = Color3.fromRGB(225, 235, 255),
			Decay = Color3.fromRGB(160, 180, 215),
			Glare = 0.2,
			Haze = 2.4,
		},
	},
	City = {
		lighting = {
			ClockTime = 17.2,
			Brightness = 2.2,
			Ambient = Color3.fromRGB(125, 115, 135),
			OutdoorAmbient = Color3.fromRGB(150, 135, 150),
			ColorShift_Top = Color3.fromRGB(255, 200, 160),
			ExposureCompensation = 0.15,
		},
		atmosphere = {
			Density = 0.36,
			Offset = 0.12,
			Color = Color3.fromRGB(255, 215, 190),
			Decay = Color3.fromRGB(130, 100, 120),
			Glare = 0.5,
			Haze = 1.8,
		},
	},
}
FALLBACK_PRESETS.Training = FALLBACK_PRESETS.Lobby

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local CourseService = {}
CourseService.Priority = 25
CourseService.HoleLoaded = SignalModule.new() :: Signal
CourseService.HoleUnloaded = SignalModule.new() :: Signal

local current: HoleState? = nil
local lobbyInfo: LobbyInfo? = nil
local lobbyBuilding = false
local courseRoot: Folder? = nil
local serviceTrove: Trove = TroveModule.new()
local currentLightingKey: string? = nil
local lightTween: Tween? = nil

local warned: { [string]: boolean } = {}
local moduleCache: { [string]: any } = {}
local netModule: any = nil
local practiceCooldowns: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local practiceSinking: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any

--------------------------------------------------------------------------------
-- Utilitaires
--------------------------------------------------------------------------------

local function warnOnce(key: string, ...: any)
	if warned[key] then
		return
	end
	warned[key] = true
	Log.warn("Course", ...)
end

local function requireOptional(parent: Instance?, name: string): any?
	if parent == nil then
		return nil
	end
	local cacheKey = parent:GetFullName() .. "/" .. name
	local cached = moduleCache[cacheKey]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local module = parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		moduleCache[cacheKey] = false
		warnOnce("missing:" .. cacheKey, "module absent :", cacheKey)
		return nil
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		moduleCache[cacheKey] = result
		return result
	end
	moduleCache[cacheKey] = false
	warnOnce("broken:" .. cacheKey, "module illisible :", cacheKey, tostring(result))
	return nil
end

-- server/Course/<name>
local function courseModule(name: string): any?
	local serverRoot = script.Parent and script.Parent.Parent
	return requireOptional(serverRoot and serverRoot:FindFirstChild("Course"), name)
end

-- shared/Config/<name>
local function configModule(name: string): any?
	return requireOptional(Shared:FindFirstChild("Config"), name)
end

-- Service voisin chargé à la demande (Server.Util.Services) : aucun cycle de require au chargement.
local service = require(script.Parent.Parent.Util.Services).get

local function net(): any?
	if netModule == nil then
		local module = Shared:FindFirstChild("Net")
		local ok, result = pcall(function()
			return require(module :: any)
		end)
		netModule = if ok and type(result) == "table" then result else false
	end
	return if netModule then netModule else nil
end

local function notify(player: Player, key: string, vars: { [string]: any }?)
	local Net = net()
	if Net and type(Net.fire) == "function" then
		pcall(Net.fire, "Core.NotifyKey", player, key, vars or {})
	end
end

local function fireAll(remote: string, ...: any)
	local Net = net()
	if Net and type(Net.fireAll) == "function" then
		pcall(Net.fireAll, remote, ...)
	end
end

local function courseConfig(): any
	return configModule("Course") or {}
end

local function configTable(name: string): { [string]: any }
	local value = courseConfig()[name]
	return if type(value) == "table" then value else {}
end

local function configNumber(section: { [string]: any }, key: string, default: number): number
	local value = section[key]
	return if Validate.isFiniteNumber(value) then value else default
end

-- Vecteur de Config.Course : clé de premier niveau, puis Config.Course.World[clé], puis repli.
local function configVector(key: string, default: Vector3): Vector3
	local cfg = courseConfig()
	local value = cfg[key]
	if not Validate.isFiniteVector3(value) then
		value = configTable("World")[key]
	end
	return if Validate.isFiniteVector3(value) then value else default
end

local function configString(key: string, default: string): string
	local value = configTable("World")[key]
	return if type(value) == "string" and value ~= "" then value else default
end

local function holeOrigin(): Vector3
	return configVector("HoleOrigin", DEFAULT_HOLE_ORIGIN)
end

local function lobbyOrigin(): Vector3
	return configVector("LobbyOrigin", DEFAULT_LOBBY_ORIGIN)
end

local function previewOrigin(): Vector3
	return configVector("PreviewOrigin", DEFAULT_PREVIEW_ORIGIN)
end

local function playerOffset(): CFrame
	local offset = configTable("Tee").PlayerOffset
	if Validate.isFiniteVector3(offset) then
		return CFrame.new(offset)
	end
	return PLAYER_OFFSET
end

-- Repère local d'un trou -> monde : origine + (x, y, -z) (voir Config/Course).
local function toWorld(origin: Vector3, localPoint: Vector3): Vector3
	return origin + Vector3.new(localPoint.X, localPoint.Y, -localPoint.Z)
end

-- Cap (degrés, depuis +Z local vers +X local) -> rotation monde.
local function yawRotation(yaw: any): CFrame
	local degrees = if Validate.isFiniteNumber(yaw) then yaw else 0
	return CFrame.Angles(0, -math.rad(degrees), 0)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatUnit(v: Vector3, fallback: Vector3): Vector3
	local f = flat(v)
	if f.Magnitude < 1e-4 then
		return fallback
	end
	return f.Unit
end

local function generatedFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder:SetAttribute(GENERATED_ATTRIBUTE, true)
	folder.Parent = parent
	return folder
end

local function ensureCourseRoot(): Folder
	local root = courseRoot
	if root and root.Parent then
		return root
	end
	local folder = generatedFolder(Workspace, configString("FolderName", "Course"))
	courseRoot = folder
	return folder
end

local function ensurePreviewRoot(): Folder
	return generatedFolder(Workspace, configString("PreviewFolderName", "CoursePreviews"))
end

local function currentPhase(): string?
	local ok, phase = pcall(function()
		return GameState.get():GetAttribute("Phase")
	end)
	return if ok and type(phase) == "string" then phase else nil
end

local function practicePhases(): { string }
	local gameplay = configModule("Gameplay")
	local ball = gameplay and gameplay.Ball
	local phases = if type(ball) == "table" then ball.PracticePhases else nil
	return if type(phases) == "table" then phases else DEFAULT_PRACTICE_PHASES
end

local function ballTag(): string
	local gameplay = configModule("Gameplay")
	local ball = gameplay and gameplay.Ball
	local tag = if type(ball) == "table" then ball.Tag else nil
	return if type(tag) == "string" then tag else "GolfBall"
end

local function rootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function ballOwner(ball: BasePart): Player?
	local userId = ball:GetAttribute("OwnerUserId")
	if type(userId) ~= "number" then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

--------------------------------------------------------------------------------
-- Zones (dangers) et chemin
--------------------------------------------------------------------------------

local inAnyZone = PathMath.inAnyZone
local progressAlong = PathMath.progressAlong
local inBox = PathMath.inBox
local vectorList = PathMath.vectorList
local cframeList = PathMath.cframeList
local cumulativeLengths = PathMath.cumulativeLengths

local function absVector(v: Vector3): Vector3
	return Vector3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
end

-- Zones de danger du HoleDef (repère local -> monde) + volumes balisés (attribut Hazard) du dossier construit.
local function collectZones(def: HoleDef, origin: Vector3, folder: Instance): { Zone }
	local zones: { Zone } = {}
	if type(def.hazards) == "table" then
		for _, hazard in def.hazards do
			if type(hazard) == "table" and Validate.isFiniteVector3(hazard.center) and Validate.isFiniteVector3(hazard.size) then
				table.insert(zones, {
					kind = tostring(hazard.kind),
					shape = if hazard.shape == "cylinder" then "cylinder" else "box",
					cframe = CFrame.new(toWorld(origin, hazard.center)) * yawRotation(hazard.yaw),
					size = absVector(hazard.size),
				})
			end
		end
	end
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("BasePart") then
			local kind = descendant:GetAttribute("Hazard")
			if type(kind) == "string" then
				table.insert(zones, {
					kind = kind,
					shape = "box",
					cframe = descendant.CFrame,
					size = descendant.Size,
				})
			end
		end
	end
	return zones
end

--------------------------------------------------------------------------------
-- Lecture défensive du résultat du constructeur
--------------------------------------------------------------------------------

local function worldPath(def: HoleDef, origin: Vector3): { Vector3 }
	local points: { Vector3 } = {}
	if type(def.path) == "table" then
		for _, node in def.path do
			if type(node) == "table" and Validate.isFiniteVector3(node.p) then
				table.insert(points, toWorld(origin, node.p))
			end
		end
	end
	return points
end

local function computeBounds(points: { Vector3 }, extra: { Vector3 }): Bounds
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	local function grow(point: Vector3)
		minV = minV:Min(point)
		maxV = maxV:Max(point)
	end
	for _, point in points do
		grow(point)
	end
	for _, point in extra do
		grow(point)
	end
	if minV.X == math.huge then
		return { min = Vector3.new(-100, -50, -100), max = Vector3.new(100, 200, 100) }
	end
	local bounds = configTable("Bounds")
	local margin = configNumber(bounds, "Margin", DEFAULT_BOUNDS_MARGIN)
	local ceiling = configNumber(bounds, "Ceiling", DEFAULT_BOUNDS_CEILING)
	return {
		min = minV - Vector3.new(margin, margin, margin),
		max = maxV + Vector3.new(margin, ceiling, margin),
	}
end

-- Obstacles en coordonnées monde : ceux du constructeur, sinon conversion du HoleDef.
local function worldObstacles(def: HoleDef, origin: Vector3, fromBuilder: any): { ObstacleDef }
	local list: { ObstacleDef } = {}
	if type(fromBuilder) == "table" then
		for _, obstacle in fromBuilder do
			if type(obstacle) == "table" then
				table.insert(list, obstacle)
			end
		end
		return list
	end
	if type(def.obstacles) == "table" then
		for _, obstacle in def.obstacles do
			if type(obstacle) == "table" and Validate.isFiniteVector3(obstacle.center) then
				table.insert(list, {
					kind = obstacle.kind,
					center = toWorld(origin, obstacle.center),
					size = obstacle.size,
					yaw = obstacle.yaw,
					params = obstacle.params,
				})
			end
		end
	end
	return list
end

local function spawnObstacles(list: { ObstacleDef }, parent: Folder, groundRoot: Instance, trove: Trove, preview: boolean): { Model }
	local models: { Model } = {}
	if #list == 0 then
		return models
	end
	local Obstacles = courseModule("Obstacles")
	if not Obstacles or type(Obstacles.spawn) ~= "function" then
		warnOnce("obstacles", "Obstacles absent : obstacles ignorés")
		return models
	end
	for index, obstacle in list do
		local ok, model = pcall(Obstacles.spawn, obstacle, parent, trove, { preview = preview, groundRoot = groundRoot })
		if not ok then
			Log.warn("Course", "obstacle", index, tostring(obstacle.kind), "en erreur :", tostring(model))
		elseif typeof(model) == "Instance" and model:IsA("Model") then
			table.insert(models, model)
		end
	end
	return models
end

--------------------------------------------------------------------------------
-- Éclairage
--------------------------------------------------------------------------------

local function normalizePropertyName(name: string): string
	return string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
end

local function mergeProperties(base: { [string]: any }, override: any): { [string]: any }
	local merged = table.clone(base)
	if type(override) == "table" then
		for key, value in override do
			if type(key) == "string" then
				merged[normalizePropertyName(key)] = value
			end
		end
	end
	return merged
end

local function biomePreset(key: string): LightingPreset
	local fallback = FALLBACK_PRESETS[key] or FALLBACK_PRESETS.Lobby
	local preset: LightingPreset = {
		lighting = mergeProperties(FALLBACK_PRESETS.Lobby.lighting, fallback.lighting),
		atmosphere = mergeProperties(FALLBACK_PRESETS.Lobby.atmosphere, fallback.atmosphere),
	}
	local biomes = configModule("Biomes")
	if biomes then
		local entry = biomes[key]
		if type(entry) ~= "table" and type(biomes.Biomes) == "table" then
			entry = biomes.Biomes[key]
		end
		if type(entry) == "table" then
			preset.lighting = mergeProperties(preset.lighting, entry.lighting or entry.Lighting)
			preset.atmosphere = mergeProperties(preset.atmosphere, entry.atmosphere or entry.Atmosphere)
		end
	end
	return preset
end

local function ensureAtmosphere(): Atmosphere
	local named = Lighting:FindFirstChild(ATMOSPHERE_NAME)
	if named and named:IsA("Atmosphere") then
		return named
	end
	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	if existing then
		existing.Name = ATMOSPHERE_NAME
		return existing
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = ATMOSPHERE_NAME
	atmosphere.Parent = Lighting
	return atmosphere
end

-- Applique une table de propriétés ; les nombres et couleurs sont interpolés (si demandé), le reste est direct.
local function applyProperties(instance: Instance, properties: { [string]: any }, goals: { [string]: any }?)
	for name, value in properties do
		local okRead, currentValue = pcall(function()
			return (instance :: any)[name]
		end)
		if not okRead then
			warnOnce("prop:" .. instance.ClassName .. "." .. name, "propriété d'éclairage inconnue :", instance.ClassName, name)
			continue
		end
		local kind = typeof(value)
		if goals and (kind == "number" or kind == "Color3") and typeof(currentValue) == kind then
			goals[name] = value
		else
			local okWrite, err = pcall(function()
				(instance :: any)[name] = value
			end)
			if not okWrite then
				warnOnce("propw:" .. instance.ClassName .. "." .. name, "propriété d'éclairage refusée :", name, tostring(err))
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Accueil
--------------------------------------------------------------------------------

-- Données de l'accueil minimal de secours (sans géométrie).
local function fallbackLobbyData(origin: Vector3, folder: Folder?): LobbyInfo
	local spawns: { CFrame } = {}
	for index = 1, 16 do
		local angle = (index - 1) / 16 * math.pi * 2
		local position = origin + Vector3.new(math.cos(angle) * 20, 3, math.sin(angle) * 20)
		table.insert(spawns, CFrame.lookAt(position, position + flatUnit(position - origin, Vector3.new(0, 0, -1))))
	end
	local spawn = CFrame.new(origin + Vector3.new(0, 3, 0))
	local practiceCup = origin + Vector3.new(40, 0, 0)
	return {
		folder = folder,
		spawns = spawns,
		spawn = spawn,
		practiceTee = CFrame.new(origin + Vector3.new(25, 0, 0)),
		practiceCup = practiceCup,
		practiceCupRadius = DEFAULT_CUP_RADIUS,
		rangeTee = CFrame.new(origin + Vector3.new(0, 0, -60)),
		kiosks = {
			podium1 = CFrame.new(origin + Vector3.new(-40, 3, 0)),
			podium2 = CFrame.new(origin + Vector3.new(-40, 3, 6)),
			podium3 = CFrame.new(origin + Vector3.new(-40, 3, -6)),
		},
		practiceSpots = { CFrame.new(origin + Vector3.new(25, 0, 0)) },
		rangeSpots = { CFrame.new(origin + Vector3.new(0, 0, -60)) },
		bounds = { min = origin - Vector3.new(80, 50, 80), max = origin + Vector3.new(80, 200, 80) },
		killY = origin.Y - DEFAULT_LOBBY_KILL_DEPTH,
	}
end

-- Accueil minimal de secours (si LobbyBuilder est absent ou échoue) : une dalle sûre et des apparitions.
local function buildFallbackLobby(origin: Vector3): LobbyInfo
	local folder = generatedFolder(Workspace, configString("LobbyFolderName", "Lobby"))
	local slab = Instance.new("Part")
	slab.Name = "SecoursDalle"
	slab.Anchored = true
	slab.Size = Vector3.new(160, 4, 160)
	slab.CFrame = CFrame.new(origin - Vector3.new(0, 2, 0))
	slab.Color = Color3.fromRGB(110, 200, 90)
	slab.Material = Enum.Material.SmoothPlastic
	slab.TopSurface = Enum.SurfaceType.Smooth
	slab.Parent = folder
	return fallbackLobbyData(origin, folder)
end

local function sanitizeLobby(info: any, origin: Vector3): LobbyInfo
	if type(info) ~= "table" or typeof(info.folder) ~= "Instance" then
		return buildFallbackLobby(origin)
	end
	local fallback = fallbackLobbyData(origin, nil)
	local spawns = cframeList(info.spawns)
	local kiosks: { [string]: CFrame } = {}
	if type(info.kiosks) == "table" then
		for key, value in info.kiosks do
			if type(key) == "string" and Validate.isFiniteCFrame(value) then
				kiosks[key] = value
			end
		end
	end
	for key, value in fallback.kiosks do
		if kiosks[key] == nil then
			kiosks[key] = value
		end
	end
	local prompts: { ProximityPrompt } = {}
	if type(info.prompts) == "table" then
		for _, prompt in info.prompts do
			if typeof(prompt) == "Instance" and prompt:IsA("ProximityPrompt") then
				table.insert(prompts, prompt)
			end
		end
	end
	local bounds = fallback.bounds
	if type(info.bounds) == "table" and Validate.isFiniteVector3(info.bounds.min) and Validate.isFiniteVector3(info.bounds.max) then
		bounds = { min = info.bounds.min, max = info.bounds.max }
	end
	local rangeZone = nil
	if type(info.rangeZone) == "table" and Validate.isFiniteCFrame(info.rangeZone.cframe) and Validate.isFiniteVector3(info.rangeZone.size) then
		rangeZone = { cframe = info.rangeZone.cframe, size = info.rangeZone.size }
	end
	local practiceSpots = cframeList(info.practiceSpots)
	local rangeSpots = cframeList(info.rangeSpots)
	return {
		folder = if typeof(info.folder) == "Instance" and info.folder:IsA("Folder") then info.folder else fallback.folder,
		spawns = if #spawns > 0 then spawns else fallback.spawns,
		spawn = if Validate.isFiniteCFrame(info.spawn) then info.spawn else (spawns[1] or fallback.spawn),
		practiceTee = if Validate.isFiniteCFrame(info.practiceTee) then info.practiceTee else fallback.practiceTee,
		practiceCup = if Validate.isFiniteVector3(info.practiceCup) then info.practiceCup else fallback.practiceCup,
		practiceCupRadius = if Validate.isFiniteNumber(info.practiceCupRadius) then info.practiceCupRadius else DEFAULT_CUP_RADIUS,
		rangeTee = if Validate.isFiniteCFrame(info.rangeTee) then info.rangeTee else fallback.rangeTee,
		kiosks = kiosks,
		practiceSpots = if #practiceSpots > 0 then practiceSpots else fallback.practiceSpots,
		rangeSpots = if #rangeSpots > 0 then rangeSpots else fallback.rangeSpots,
		practiceGreenCenter = if Validate.isFiniteVector3(info.practiceGreenCenter) then info.practiceGreenCenter else nil,
		practiceGreenRadius = if Validate.isFiniteNumber(info.practiceGreenRadius) then info.practiceGreenRadius else nil,
		rangeZone = rangeZone,
		bounds = bounds,
		killY = if Validate.isFiniteNumber(info.killY) then info.killY else fallback.killY,
		prompts = prompts,
	}
end

local function ensureLobby(): LobbyInfo
	local info = lobbyInfo
	if info then
		return info
	end
	local origin = lobbyOrigin()
	if lobbyBuilding then
		-- Appel réentrant pendant la construction : renvoie un accueil provisoire non mémorisé.
		return fallbackLobbyData(origin, nil)
	end
	lobbyBuilding = true
	local stale = Workspace:FindFirstChild(configString("LobbyFolderName", "Lobby"))
	if stale and stale:GetAttribute(GENERATED_ATTRIBUTE) then
		stale:Destroy()
	end
	local built: any = nil
	local LobbyBuilder = courseModule("LobbyBuilder")
	if LobbyBuilder and type(LobbyBuilder.build) == "function" then
		local ok, result = pcall(LobbyBuilder.build, origin, Workspace)
		if ok then
			built = result
		else
			Log.warn("Course", "construction de l'accueil en échec :", tostring(result))
		end
	else
		warnOnce("lobbybuilder", "LobbyBuilder absent : accueil de secours")
	end
	local sanitized = sanitizeLobby(built, origin)
	if sanitized.folder then
		sanitized.folder:SetAttribute(GENERATED_ATTRIBUTE, true)
	end
	lobbyInfo = sanitized
	lobbyBuilding = false
	return sanitized
end

local function inLobbyRegion(info: LobbyInfo, position: Vector3): boolean
	local bounds = info.bounds
	if bounds then
		return inBox(position, bounds, REGION_MARGIN)
	end
	return (flat(position - lobbyOrigin())).Magnitude < 600
end

local function lobbyOutOfBounds(info: LobbyInfo, position: Vector3): boolean
	local killY = info.killY or (lobbyOrigin().Y - DEFAULT_LOBBY_KILL_DEPTH)
	if position.Y < killY then
		return true
	end
	local bounds = info.bounds
	if bounds and not inBox(position, bounds, 0) then
		return true
	end
	return false
end

--------------------------------------------------------------------------------
-- API : trous
--------------------------------------------------------------------------------

function CourseService.GetCurrent(): HoleRuntime?
	local state = current
	return if state then state.runtime else nil
end

function CourseService.GetExtras(): HoleExtras?
	local state = current
	return if state then state.extras else nil
end

function CourseService.GetHoleFolder(): Folder?
	local state = current
	return if state then state.runtime.folder else nil
end

function CourseService.UnloadHole()
	local state = current
	current = nil
	if state then
		state.trove:Clean()
	end
	-- Résidus éventuels (construction partielle, ajouts d'autres services dans Workspace.Course).
	local root = courseRoot
	if root and root.Parent then
		for _, child in root:GetChildren() do
			child:Destroy()
		end
	end
	local Ball = service("BallService")
	if Ball and type(Ball.SetCup) == "function" then
		pcall(Ball.SetCup, nil)
	end
	if state then
		Log.info("Course", "trou déchargé", state.runtime.def.id)
		CourseService.HoleUnloaded:Fire()
	end
end

function CourseService.LoadHole(def: HoleDef): HoleRuntime?
	if type(def) ~= "table" or type(def.id) ~= "string" then
		Log.warn("Course", "LoadHole : définition invalide")
		return nil
	end
	if current then
		CourseService.UnloadHole()
	end
	local HoleBuilder = courseModule("HoleBuilder")
	if not HoleBuilder or type(HoleBuilder.build) ~= "function" then
		warnOnce("holebuilder", "HoleBuilder absent : impossible de charger", def.id)
		return nil
	end

	local origin = holeOrigin()
	local root = ensureCourseRoot()
	local startedAt = os.clock()
	local ok, result = pcall(HoleBuilder.build, def, origin, root, { preview = false })
	if not ok or type(result) ~= "table" or typeof(result.folder) ~= "Instance" then
		Log.warn("Course", "construction du trou", def.id, "en échec :", tostring(if ok then "résultat invalide" else result))
		for _, child in root:GetChildren() do
			child:Destroy()
		end
		return nil
	end

	local folder: Folder
	if result.folder:IsA("Folder") then
		folder = result.folder
	else
		-- Le constructeur a renvoyé un autre conteneur : on l'enveloppe pour respecter HoleRuntime.folder.
		folder = Instance.new("Folder")
		folder.Name = "Hole_" .. def.id
		folder.Parent = root
		result.folder.Parent = folder
	end
	folder:SetAttribute("HoleId", def.id)

	local trove = TroveModule.new()
	trove:Add(folder)

	-- Données du trou (valeurs du constructeur, sinon recalculées depuis le HoleDef).
	local pathPoints = worldPath(def, origin)
	local cumulative, computedLength = cumulativeLengths(pathPoints)
	local cupPosition: Vector3 = if Validate.isFiniteVector3(result.cupPosition)
		then result.cupPosition
		elseif Validate.isFiniteVector3(def.cup) then toWorld(origin, def.cup)
		else (pathPoints[#pathPoints] or origin)
	local cupRadius = if Validate.isFiniteNumber(result.cupRadius) and result.cupRadius > 0
		then result.cupRadius
		else configNumber(courseConfig(), "CupRadius", DEFAULT_CUP_RADIUS)
	local firstDirection = Vector3.new(0, 0, -1)
	if #pathPoints >= 2 then
		firstDirection = flatUnit(pathPoints[2] - pathPoints[1], firstDirection)
	end
	local teeCFrame: CFrame
	if Validate.isFiniteCFrame(result.teeCFrame) then
		teeCFrame = result.teeCFrame
		if #pathPoints < 2 then
			firstDirection = flatUnit(teeCFrame.LookVector, firstDirection)
		end
	else
		local teePosition = pathPoints[1] or origin
		teeCFrame = CFrame.lookAt(teePosition, teePosition + firstDirection)
	end
	local checkpoints = cframeList(result.checkpoints)
	local itemBoxes = vectorList(result.itemBoxes)
	local bounds: Bounds
	if type(result.bounds) == "table" and Validate.isFiniteVector3(result.bounds.min) and Validate.isFiniteVector3(result.bounds.max) then
		bounds = { min = result.bounds.min, max = result.bounds.max }
	else
		bounds = computeBounds(pathPoints, { cupPosition, teeCFrame.Position })
	end
	local killY: number
	if Validate.isFiniteNumber(result.killY) then
		killY = result.killY
	else
		local lowest = math.min(cupPosition.Y, teeCFrame.Position.Y)
		for _, point in pathPoints do
			lowest = math.min(lowest, point.Y)
		end
		killY = lowest - configNumber(courseConfig(), "KillMargin", DEFAULT_KILL_MARGIN)
	end
	local pathLength = if Validate.isFiniteNumber(result.pathLength) then result.pathLength else computedLength

	local runtime: HoleRuntime = {
		def = def,
		folder = folder,
		origin = origin,
		cupPosition = cupPosition,
		cupRadius = cupRadius,
		teeCFrame = teeCFrame,
		checkpoints = checkpoints,
		itemBoxes = itemBoxes,
		killY = killY,
		bounds = bounds,
		pathLength = pathLength,
	}

	-- Obstacles (Trove de manche : géométrie + mouvements + contacts).
	local obstaclesFolder = Instance.new("Folder")
	obstaclesFolder.Name = "Obstacles"
	obstaclesFolder.Parent = folder
	local obstacleDefs = worldObstacles(def, origin, result.obstacles)
	local models = spawnObstacles(obstacleDefs, obstaclesFolder, folder, trove, false)

	local zones = collectZones(def, origin, folder)
	local oobZones: { Zone } = {}
	for _, zone in zones do
		if zone.kind == "oob" or zone.kind == "void" then
			table.insert(oobZones, zone)
		end
	end
	local checkpointProgress: { number } = {}
	for index, checkpoint in checkpoints do
		checkpointProgress[index] = progressAlong(pathPoints, cumulative, checkpoint.Position)
	end

	local extras: HoleExtras = {
		mobilityBoxes = vectorList(result.mobilityBoxes),
		carts = cframeList(result.carts),
		greenCenter = if Validate.isFiniteVector3(result.greenCenter) then result.greenCenter else cupPosition,
		obstacles = obstacleDefs,
		obstacleModels = models,
		hazards = zones,
		partCount = if Validate.isFiniteNumber(result.partCount) then result.partCount else #folder:GetDescendants(),
	}

	current = {
		runtime = runtime,
		extras = extras,
		trove = trove,
		pathPoints = pathPoints,
		pathCumulative = cumulative,
		checkpointProgress = checkpointProgress,
		firstDirection = firstDirection,
		oobZones = oobZones,
		allZones = zones,
		obstaclesFolder = obstaclesFolder,
	}

	local Ball = service("BallService")
	if Ball and type(Ball.SetCup) == "function" then
		local okCup, err = pcall(Ball.SetCup, cupPosition, cupRadius)
		if not okCup then
			Log.warn("Course", "BallService.SetCup en échec :", tostring(err))
		end
	else
		warnOnce("ballservice", "BallService absent : trou non transmis")
	end
	CourseService.ApplyBiomeLighting(def.biome)

	Log.info(
		"Course",
		string.format(
			"trou %s chargé (%s, %d obstacles, %d pièces, %.0f ms)",
			def.id,
			tostring(def.biome),
			#models,
			extras.partCount,
			(os.clock() - startedAt) * 1000
		)
	)
	CourseService.HoleLoaded:Fire(runtime)
	return runtime
end

function CourseService.GetPathProgress(position: Vector3): number
	local state = current
	if not state or not Validate.isFiniteVector3(position) then
		return 0
	end
	return progressAlong(state.pathPoints, state.pathCumulative, position)
end

function CourseService.GetCheckpointFor(position: Vector3): CFrame
	local state = current
	local lobby = lobbyInfo
	if not state then
		return ensureLobby().spawn
	end
	if not Validate.isFiniteVector3(position) then
		return state.runtime.teeCFrame
	end
	if lobby and inLobbyRegion(lobby, position) and not inBox(position, state.runtime.bounds, REGION_MARGIN) then
		return lobby.spawn
	end
	local tolerance = configNumber(configTable("Checkpoint"), "BehindTolerance", DEFAULT_BEHIND_TOLERANCE)
	local progress = progressAlong(state.pathPoints, state.pathCumulative, position)
	local best = state.runtime.teeCFrame
	local bestProgress = -math.huge
	for index, checkpoint in state.runtime.checkpoints do
		local checkpointProgress = state.checkpointProgress[index] or 0
		if checkpointProgress <= progress + tolerance and checkpointProgress > bestProgress then
			best = checkpoint
			bestProgress = checkpointProgress
		end
	end
	return best
end

function CourseService.IsOutOfBounds(position: Vector3): boolean
	if not Validate.isFiniteVector3(position) then
		return true
	end
	local state = current
	if state then
		local runtime = state.runtime
		if inBox(position, runtime.bounds, REGION_MARGIN) then
			if position.Y < runtime.killY then
				return true
			end
			if not inBox(position, runtime.bounds, 0) then
				return true
			end
			return inAnyZone(state.oobZones, position)
		end
	end
	local lobby = lobbyInfo
	if lobby and inLobbyRegion(lobby, position) then
		return lobbyOutOfBounds(lobby, position)
	end
	-- Ni dans le trou ni dans l'accueil : hors limites dès qu'un monde existe.
	return state ~= nil or lobby ~= nil
end

--------------------------------------------------------------------------------
-- Départs équitables
--------------------------------------------------------------------------------

local function startSpotValid(state: HoleState, point: Vector3, refY: number, rayParams: RaycastParams, overlap: OverlapParams): Vector3?
	local origin = Vector3.new(point.X, refY + 10, point.Z)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -(10 + START_MAX_HEIGHT_DELTA + 6), 0), rayParams)
	if not hit then
		return nil
	end
	if hit.Normal.Y < START_MIN_NORMAL_Y or math.abs(hit.Position.Y - refY) > START_MAX_HEIGHT_DELTA then
		return nil
	end
	local instance: Instance? = hit.Instance
	if instance and instance:IsDescendantOf(state.obstaclesFolder) then
		return nil
	end
	while instance and instance ~= state.runtime.folder do
		if instance:GetAttribute("Hazard") ~= nil then
			return nil
		end
		instance = instance.Parent
	end
	local ground = hit.Position
	if inAnyZone(state.allZones, ground + Vector3.new(0, 0.5, 0)) then
		return nil
	end
	local nearby = Workspace:GetPartBoundsInRadius(ground + Vector3.new(0, 1.5, 0), START_OBSTACLE_CLEARANCE, overlap)
	if #nearby > 0 then
		return nil
	end
	return ground
end

local function arcPlacements(
	state: HoleState,
	cup: Vector3,
	radius: number,
	baseAngle: number,
	spacing: number,
	count: number,
	refY: number,
	facing: Vector3,
	rayParams: RaycastParams,
	overlap: OverlapParams
): { CFrame }
	local placements: { CFrame } = {}
	if radius < spacing then
		return placements
	end
	local step = 2 * math.asin(math.min(1, spacing / (2 * radius)))
	local offsets = { 0 }
	for k = 1, START_MAX_STEPS_PER_SIDE do
		table.insert(offsets, k)
		table.insert(offsets, -k)
	end
	for _, k in offsets do
		local angle = baseAngle + k * step
		local candidate = Vector3.new(cup.X + math.cos(angle) * radius, refY, cup.Z + math.sin(angle) * radius)
		local ground = startSpotValid(state, candidate, refY, rayParams, overlap)
		if ground then
			table.insert(placements, CFrame.lookAt(ground, ground + facing))
			if #placements >= count then
				break
			end
		end
	end
	return placements
end

function CourseService.GetStartPlacements(count: number): { CFrame }
	local wanted = math.clamp(math.floor(if Validate.isFiniteNumber(count) then count else 1), 1, 32)
	local state = current
	if not state then
		local lobby = ensureLobby()
		local list: { CFrame } = {}
		for index = 1, wanted do
			list[index] = lobby.spawns[((index - 1) % #lobby.spawns) + 1]
		end
		return list
	end

	local runtime = state.runtime
	local tee = runtime.teeCFrame.Position
	local cup = runtime.cupPosition
	local facing = state.firstDirection
	local toTee = flat(tee - cup)
	local radius = toTee.Magnitude

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { runtime.folder }
	rayParams.IgnoreWater = false
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { state.obstaclesFolder }

	local best: { CFrame } = {}
	if radius >= 12 then
		local baseAngle = math.atan2(toTee.Z, toTee.X)
		for _, spacing in START_SPACINGS do
			for _, offset in START_RADIUS_OFFSETS do
				local placements = arcPlacements(state, cup, radius + offset, baseAngle, spacing, wanted, tee.Y, facing, rayParams, overlap)
				if #placements >= wanted then
					return placements
				end
				if #placements > #best then
					best = placements
				end
			end
		end
	end

	-- Complément (trou atypique) : rangées derrière le départ ; l'équité de distance n'est plus garantie.
	Log.warn("Course", "départs équitables incomplets pour", runtime.def.id, #best, "/", wanted)
	local right = facing:Cross(Vector3.yAxis).Unit
	local row = 0
	while #best < wanted and row < 8 do
		row += 1
		local back = tee - facing * (row * 5)
		for k = 0, 8 do
			for _, sign in { 1, -1 } do
				if #best >= wanted then
					break
				end
				if k == 0 and sign == -1 then
					continue
				end
				local candidate = back + right * (k * 6 * sign)
				local ground = startSpotValid(state, candidate, tee.Y, rayParams, overlap) or candidate
				table.insert(best, CFrame.lookAt(ground, ground + facing))
			end
		end
	end
	return best
end

--------------------------------------------------------------------------------
-- Éclairage
--------------------------------------------------------------------------------

function CourseService.ApplyBiomeLighting(biome: string?)
	local key = if type(biome) == "string" and biome ~= "" then biome else "Lobby"
	local preset = biomePreset(key)
	local animate = RunService:IsRunning()
	local lightingGoals: { [string]: any }? = if animate then {} else nil
	applyProperties(Lighting, preset.lighting, lightingGoals)
	local atmosphere = ensureAtmosphere()
	local atmosphereGoals: { [string]: any }? = if animate then {} else nil
	applyProperties(atmosphere, preset.atmosphere, atmosphereGoals)
	if lightTween then
		lightTween:Cancel()
		lightTween = nil
	end
	local info = TweenInfo.new(LIGHT_TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	if lightingGoals and next(lightingGoals) then
		local tween = TweenService:Create(Lighting, info, lightingGoals)
		lightTween = tween
		tween:Play()
	end
	if atmosphereGoals and next(atmosphereGoals) then
		TweenService:Create(atmosphere, info, atmosphereGoals):Play()
	end
	currentLightingKey = key
end

function CourseService.GetLightingBiome(): string?
	return currentLightingKey
end

--------------------------------------------------------------------------------
-- Aperçus (mode Édition possible)
--------------------------------------------------------------------------------

local function holesModule(): any?
	return requireOptional(Shared:FindFirstChild("Data"), "Holes")
end

local function resolveHoleDef(hole: any): HoleDef?
	if type(hole) == "table" and type(hole.id) == "string" then
		return hole :: HoleDef
	end
	if type(hole) ~= "string" then
		return nil
	end
	local Holes = holesModule()
	if not Holes or type(Holes.get) ~= "function" then
		warnOnce("holes", "Data/Holes absent : aperçu impossible")
		return nil
	end
	local ok, def = pcall(Holes.get, hole)
	if ok and type(def) == "table" then
		return def :: HoleDef
	end
	return nil
end

local function buildPreviewInto(def: HoleDef, origin: Vector3, parent: Instance): Folder?
	local HoleBuilder = courseModule("HoleBuilder")
	if not HoleBuilder or type(HoleBuilder.build) ~= "function" then
		warnOnce("holebuilder", "HoleBuilder absent : aperçu impossible")
		return nil
	end
	local ok, result = pcall(HoleBuilder.build, def, origin, parent, { preview = true })
	if not ok or type(result) ~= "table" or typeof(result.folder) ~= "Instance" then
		Log.warn("Course", "aperçu de", def.id, "en échec :", tostring(if ok then "résultat invalide" else result))
		return nil
	end
	local folder: Folder
	if result.folder:IsA("Folder") then
		folder = result.folder
	else
		folder = Instance.new("Folder")
		folder.Name = "Preview_" .. def.id
		folder.Parent = parent
		result.folder.Parent = folder
	end
	folder:SetAttribute("PreviewHoleId", def.id)
	local obstaclesFolder = Instance.new("Folder")
	obstaclesFolder.Name = "Obstacles"
	obstaclesFolder.Parent = folder
	-- Trove jetable : un aperçu ne crée aucune connexion ; ses pièces disparaissent avec le dossier.
	spawnObstacles(worldObstacles(def, origin, result.obstacles), obstaclesFolder, folder, TroveModule.new(), true)
	return folder
end

function CourseService.BuildPreview(holeId: any, origin: Vector3?): Folder?
	local def = resolveHoleDef(holeId)
	if not def then
		Log.warn("Course", "BuildPreview : trou introuvable", tostring(holeId))
		return nil
	end
	local at = if Validate.isFiniteVector3(origin) then origin :: Vector3 else previewOrigin()
	return buildPreviewInto(def, at, ensurePreviewRoot())
end

--------------------------------------------------------------------------------
-- API : accueil et entraînement
--------------------------------------------------------------------------------

function CourseService.GetLobby(): LobbyInfo
	return ensureLobby()
end

function CourseService.GetPracticeCup(): (Vector3?, number)
	local info = lobbyInfo
	if not info then
		return nil, DEFAULT_CUP_RADIUS
	end
	return info.practiceCup, info.practiceCupRadius
end

-- "green" | "range" | nil
function CourseService.GetPracticeArea(position: Vector3): string?
	local info = lobbyInfo
	if not info or not Validate.isFiniteVector3(position) then
		return nil
	end
	local center = info.practiceGreenCenter or info.practiceCup
	local radius = (info.practiceGreenRadius or 14) + 4
	if flat(position - center).Magnitude <= radius and math.abs(position.Y - center.Y) <= 8 then
		return "green"
	end
	local zone = info.rangeZone
	if zone then
		local localPoint = zone.cframe:PointToObjectSpace(position)
		if math.abs(localPoint.X) <= zone.size.X / 2 and math.abs(localPoint.Y) <= zone.size.Y / 2 and math.abs(localPoint.Z) <= zone.size.Z / 2 then
			return "range"
		end
	end
	return nil
end

function CourseService.IsInLobbyPractice(position: Vector3): boolean
	return CourseService.GetPracticeArea(position) ~= nil
end

local function ballsByPosition(): { BasePart }
	local list: { BasePart } = {}
	for _, instance in CollectionService:GetTagged(ballTag()) do
		if instance:IsA("BasePart") then
			table.insert(list, instance)
		end
	end
	return list
end

-- Premier point de départ libre (aucune balle à proximité), sinon le premier.
local function freeSpot(spots: { CFrame }, ignoreBall: BasePart?): CFrame
	local balls = ballsByPosition()
	for _, spot in spots do
		local free = true
		for _, ball in balls do
			if ball ~= ignoreBall and (ball.Position - spot.Position).Magnitude < PRACTICE_SPOT_CLEARANCE then
				free = false
				break
			end
		end
		if free then
			return spot
		end
	end
	return spots[1]
end

local function practicePhaseAllowed(): boolean
	local phase = currentPhase()
	if phase == nil then
		return true
	end
	return table.find(practicePhases(), phase) ~= nil
end

local function onPracticePrompt(player: Player, area: string)
	local info = lobbyInfo
	if not info or player.Parent ~= Players then
		return
	end
	local now = os.clock()
	local last = practiceCooldowns[player]
	if last and now - last < PRACTICE_PROMPT_COOLDOWN then
		notify(player, "course.practice.busy")
		return
	end
	practiceCooldowns[player] = now
	if not practicePhaseAllowed() then
		notify(player, "course.practice.unavailable")
		return
	end
	local spots = (if area == "range" then info.rangeSpots else info.practiceSpots) or {}
	if #spots == 0 then
		spots = { if area == "range" then info.rangeTee else info.practiceTee }
	end
	local root = rootPart(player)
	if not root or (root.Position - spots[1].Position).Magnitude > PRACTICE_PROMPT_MAX_DISTANCE then
		return
	end
	local Ball = service("BallService")
	if not Ball or type(Ball.SpawnBall) ~= "function" then
		warnOnce("ballpractice", "BallService absent : balle d'entraînement impossible")
		return
	end
	local existing = if type(Ball.GetBall) == "function" then Ball.GetBall(player) else nil
	local spot = freeSpot(spots, existing)
	if existing and type(Ball.RemoveBall) == "function" then
		pcall(Ball.RemoveBall, player)
	end
	local ok, ball = pcall(Ball.SpawnBall, player, spot.Position + Vector3.new(0, 0.7, 0), { practice = true, snap = true })
	if not ok or ball == nil then
		Log.warn("Course", "balle d'entraînement refusée pour", player.Name, tostring(ball))
		return
	end
	local Movement = service("MovementService")
	local target = spot * playerOffset()
	if Movement and type(Movement.Teleport) == "function" then
		pcall(Movement.Teleport, player, target)
	end
	notify(player, "course.practice.ready")
end

local function sinkPracticeBall(ball: BasePart, owner: Player, info: LobbyInfo)
	practiceSinking[ball] = true
	local Ball = service("BallService")
	local cup = info.practiceCup
	if Ball and type(Ball.PlaceBall) == "function" then
		-- Balle posée au fond du trou (visuellement dans la coupe), immobile.
		pcall(Ball.PlaceBall, owner, cup - Vector3.new(0, 0.35, 0), false)
	end
	fireAll("Effects.Play", "Confetti", { position = cup + Vector3.new(0, 1, 0) })
	fireAll("Effects.Sound", "ball_cup_drop", cup, 1)
	notify(owner, "course.practice.holed")
	task.delay(PRACTICE_RETURN_DELAY, function()
		practiceSinking[ball] = nil
		if owner.Parent ~= Players or not Ball or type(Ball.GetBall) ~= "function" then
			return
		end
		local currentBall = Ball.GetBall(owner)
		if currentBall ~= ball or ball:GetAttribute("Practice") ~= true then
			return
		end
		local spots = info.practiceSpots or { info.practiceTee }
		local spot = freeSpot(spots, ball)
		pcall(Ball.PlaceBall, owner, spot.Position + Vector3.new(0, 0.7, 0), true)
	end)
end

local function watchPracticeCup()
	local info = lobbyInfo
	if not info then
		return
	end
	local cup = info.practiceCup
	local radius = info.practiceCupRadius
	for _, ball in ballsByPosition() do
		if practiceSinking[ball] or ball:GetAttribute("Practice") ~= true then
			continue
		end
		local state = ball:GetAttribute("State")
		if state ~= "Moving" and state ~= "Resting" then
			continue
		end
		local position = ball.Position
		if math.abs(position.Y - cup.Y) > PRACTICE_CAPTURE_HEIGHT then
			continue
		end
		if flat(position - cup).Magnitude > radius then
			continue
		end
		if ball.AssemblyLinearVelocity.Magnitude > PRACTICE_CAPTURE_SPEED then
			continue
		end
		local owner = ballOwner(ball)
		if owner then
			sinkPracticeBall(ball, owner, info)
		end
	end
end

local function rescueFallenPlayers()
	local info = lobbyInfo
	if not info then
		return
	end
	local killY = info.killY or (lobbyOrigin().Y - DEFAULT_LOBBY_KILL_DEPTH)
	for _, player in Players:GetPlayers() do
		local root = rootPart(player)
		if root and root.Position.Y < killY and inLobbyRegion(info, root.Position) then
			local state = current
			if state and inBox(root.Position, state.runtime.bounds, REGION_MARGIN) then
				continue -- le trou est responsable de ses chutes
			end
			local target = info.spawn
			local Movement = service("MovementService")
			local moved = false
			if Movement and type(Movement.Teleport) == "function" then
				local ok, result = pcall(Movement.Teleport, player, target)
				moved = ok and result == true
			end
			if not moved and player.Character then
				player.Character:PivotTo(target)
			end
			notify(player, "course.lobby.rescued")
		end
	end
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function CourseService.Init()
	-- Dossiers générés laissés par une place sauvegardée : nettoyés pour repartir d'un monde propre.
	local courseName = configString("FolderName", "Course")
	local stale = Workspace:FindFirstChild(courseName)
	if stale and stale:GetAttribute(GENERATED_ATTRIBUTE) then
		stale:Destroy()
	end
	ensureCourseRoot()
end

function CourseService.Start()
	local info = ensureLobby()
	if not current then
		CourseService.ApplyBiomeLighting("Lobby")
	end

	-- Distributeurs de balles d'entraînement.
	for _, prompt in info.prompts or {} do
		local area = prompt:GetAttribute("PracticeArea")
		if type(area) == "string" then
			serviceTrove:Connect(prompt.Triggered, function(player: Player)
				onPracticePrompt(player, area)
			end)
		end
	end

	-- Éclairage de l'accueil au retour au salon.
	local okState, folder = pcall(GameState.get)
	if okState and folder then
		serviceTrove:Connect(folder:GetAttributeChangedSignal("Phase"), function()
			local phase = folder:GetAttribute("Phase")
			if (phase == "Lobby" or phase == "Preparing" or phase == "Podium") and current == nil then
				CourseService.ApplyBiomeLighting("Lobby")
			end
		end)
	end

	-- Trou d'entraînement et sécurité des chutes (cadencés, sans boucle active).
	local practiceAccumulator = 0
	local rescueAccumulator = 0
	serviceTrove:Connect(RunService.Heartbeat, function(dt: number)
		practiceAccumulator += dt
		rescueAccumulator += dt
		if practiceAccumulator >= PRACTICE_WATCH_INTERVAL then
			practiceAccumulator = 0
			watchPracticeCup()
		end
		if rescueAccumulator >= RESCUE_INTERVAL then
			rescueAccumulator = 0
			rescueFallenPlayers()
		end
	end)
	serviceTrove:Connect(Players.PlayerRemoving, function(player: Player)
		practiceCooldowns[player] = nil
	end)
	Log.info("Course", "accueil prêt", tostring(info.folder and info.folder:GetFullName()))
end

--------------------------------------------------------------------------------
-- Outils Studio
--------------------------------------------------------------------------------

if RunService:IsStudio() then
	CourseService.Dev = {
		-- Construit tous les trous côte à côte (une rangée par biome, colonnes espacées de `spacing`).
		BuildAllPreviews = function(spacing: number?, biome: string?): Folder?
			local Holes = holesModule()
			if not Holes or type(Holes.all) ~= "function" then
				Log.warn("Course", "Data/Holes absent : BuildAllPreviews impossible")
				return nil
			end
			local okAll, all = pcall(Holes.all)
			if not okAll or type(all) ~= "table" then
				Log.warn("Course", "Holes.all() en échec :", tostring(all))
				return nil
			end
			local step = if Validate.isFiniteNumber(spacing) and (spacing :: number) > 50 then spacing :: number else 900
			local root = ensurePreviewRoot()
			local old = root:FindFirstChild("AllPreviews")
			if old then
				old:Destroy()
			end
			local container = Instance.new("Folder")
			container.Name = "AllPreviews"
			container.Parent = root
			local biomeOrder = configTable("Biomes")
			local order: { string } = {}
			for _, name in (if #biomeOrder > 0 then biomeOrder else { "Coast", "Forest", "Desert", "Snow", "City", "Training" }) :: { any } do
				if type(name) == "string" then
					table.insert(order, name)
				end
			end
			local rows: { [string]: number } = {}
			local columns: { [string]: number } = {}
			local built = 0
			local base = previewOrigin()
			for _, def in all do
				if type(def) ~= "table" or type(def.id) ~= "string" then
					continue
				end
				local holeBiome = tostring(def.biome)
				if biome ~= nil and holeBiome ~= biome then
					continue
				end
				if rows[holeBiome] == nil then
					rows[holeBiome] = table.find(order, holeBiome) or (#order + 1)
				end
				local column = (columns[holeBiome] or 0) + 1
				columns[holeBiome] = column
				local at = base + Vector3.new((column - 1) * step, 0, (rows[holeBiome] - 1) * step)
				if buildPreviewInto(def :: HoleDef, at, container) then
					built += 1
				end
			end
			Log.info("Course", "aperçus construits :", built)
			return container
		end,
	}
end

return CourseService
