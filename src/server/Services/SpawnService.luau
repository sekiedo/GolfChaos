--!strict
--[[
	SpawnService — apparition et réapparition des personnages (docs/ARCHITECTURE.md §8, priorité 55).

	Players.CharacterAutoLoads = false dans ce projet : SpawnService est le SEUL à appeler LoadCharacter.

	API
	  Spawn(player, where: "Lobby" | "Hole", cframe: CFrame?, opts?) -> boolean   (peut céder : LoadCharacter)
	      Charge le personnage s'il n'existe pas (ou opts.reload), puis le pose au sol à `cframe`.
	      Sans cframe : "Lobby" -> un plot de CourseService.GetLobby() ; "Hole" -> résolveur (SetSpawnResolver),
	      sinon point de contrôle du trou, sinon accueil.
	      opts = { reload: boolean?, protection: number?, reason: string? }
	  Respawn(player, reason) -> boolean     après KO, chute, mort : résolveur, sinon point de contrôle
	      (CourseService.GetCheckpointFor) pendant "Playing" pour un participant actif, sinon accueil.
	  SetSpawnResolver(fn(player) -> CFrame?)   (MatchService) ; nil = aucun résolveur.
	  PlaceCharacter(player, cframe) -> boolean  téléportation serveur posée au sol, sans rechargement.
	  GetLobbyCFrame(player?) -> CFrame          plot d'accueil (ou plateforme de secours).
	  GetLastSafePosition(player) -> Vector3?    dernière position sûre (au sol, au-dessus du vide).
	  IsLoading(player) -> boolean
	  Signaux : Spawned(player, character, where, reason), Fell(player, position)

	COMPORTEMENT
	  - PlayerAdded : première apparition (résolveur s'il renvoie un CFrame — participant d'une partie —,
	    sinon accueil ; un spectateur ou un arrivant tardif apparaît donc à l'accueil).
	  - CharacterAdded : CollisionService.AssignCharacter, CosmeticService.ApplyAppearance (si présent),
	    CombatService.GrantProtection, surveillance de Humanoid.Died (réapparition après Spawn.RespawnDelay).
	  - Chute sous killY (trou chargé : HoleRuntime.killY ; accueil : lobby.killY ou Spawn.LobbyKillY) ou
	    position non finie : Respawn(player, "fell") + notification.
	  - Téléportations serveur via MovementService.Teleport (jamais punies par le contrôle de plausibilité).
	  - Trove par joueur (PlayerRemoving) et par personnage (CharacterRemoving).
	  - Accueil absent (CourseService non chargé) : attente Spawn.LobbyWaitTimeout puis plateforme de secours
	    construite par code.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigMatch = require(Shared.Config.Match)
local GameState = require(Shared.Util.GameState)
local Log = require(Shared.Util.Log)
local MatchStateMachine = require(Shared.Logic.MatchStateMachine)
local Net = require(Shared.Net)
local SignalModule = require(Shared.Util.Signal)
local TroveModule = require(Shared.Util.Trove)
local Validate = require(Shared.Util.Validate)

type Signal = SignalModule.Signal
type Trove = TroveModule.Trove

export type SpawnWhere = "Lobby" | "Hole"
export type SpawnOptions = {
	reload: boolean?, -- recharge le personnage même s'il est vivant
	protection: number?, -- durée de protection (défaut Spawn.ProtectionSeconds)
	reason: string?, -- motif transmis au signal Spawned
}

type PlayerState = {
	trove: Trove,
	characterTrove: Trove?,
	loading: boolean,
	lastSafe: Vector3?,
	lastFallAt: number,
	respawnThread: thread?,
}

local SPAWN = ConfigMatch.Spawn
local LOG_TAG = "Spawn"

local SpawnService = {}
SpawnService.Priority = 55
SpawnService.Spawned = SignalModule.new() :: Signal -- (player, character, where, reason)
SpawnService.Fell = SignalModule.new() :: Signal -- (player, position)

local servicesFolder = script.Parent
local states: { [Player]: PlayerState } = {}
local resolver: ((Player) -> CFrame?)? = nil
local padCursor = 0
local fallbackModel: Model? = nil
local fallbackCFrame: CFrame? = nil
local lobbyWaited = false
local started = false

--------------------------------------------------------------------------------
-- Services facultatifs (chargés à la demande : aucun cycle de require au démarrage)
--------------------------------------------------------------------------------

local serviceCache: { [string]: { module: any?, checkedAt: number } } = {}

local function optionalService(name: string): any?
	local entry = serviceCache[name]
	local time = os.clock()
	if entry and (entry.module ~= nil or time - entry.checkedAt < 5) then
		return entry.module
	end
	local module = servicesFolder:FindFirstChild(name)
	local loaded: any? = nil
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			loaded = result
		end
	end
	serviceCache[name] = { module = loaded, checkedAt = time }
	return loaded
end

-- Appelle service.method(...) protégé ; (false, nil) si le service ou la méthode manque ou échoue.
local function callService(name: string, method: string, ...: any): (boolean, any)
	local service = optionalService(name)
	if not service then
		return false, nil
	end
	local fn = service[method]
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		Log.warn(LOG_TAG, name .. "." .. method .. " :", result)
		return false, nil
	end
	return true, result
end

--------------------------------------------------------------------------------
-- Outils
--------------------------------------------------------------------------------

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function currentPhase(): string
	local phase = GameState.read("Phase")
	return if type(phase) == "string" then phase else "Lobby"
end

local function getRoot(character: Model?): BasePart?
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function isAlive(player: Player): boolean
	local character = player.Character
	if not character or not character.Parent then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and getRoot(character) ~= nil
end

local function horizontalLook(cframe: CFrame): Vector3
	local look = cframe.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

-- Instances ignorées par la recherche du sol : personnages et balles.
local function probeExclusions(): { Instance }
	local list: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(list, other.Character)
		end
	end
	local balls = Workspace:FindFirstChild("Balls")
	if balls then
		table.insert(list, balls)
	end
	return list
end

-- CFrame du pivot du personnage : posé sur le sol sous `cframe`, orienté à l'horizontale.
local function groundedCFrame(cframe: CFrame): CFrame
	local position = cframe.Position
	local ground = position.Y
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = probeExclusions()
	params.IgnoreWater = true
	local origin = position + Vector3.new(0, SPAWN.GroundProbeUp, 0)
	local result = Workspace:Raycast(origin, Vector3.new(0, -(SPAWN.GroundProbeUp + SPAWN.GroundProbeDown), 0), params)
	if result then
		ground = result.Position.Y
	end
	local base = Vector3.new(position.X, ground + SPAWN.CharacterLift, position.Z)
	return CFrame.lookAt(base, base + horizontalLook(cframe))
end

--------------------------------------------------------------------------------
-- Accueil
--------------------------------------------------------------------------------

local function getLobby(): { [string]: any }?
	local ok, lobby = callService("CourseService", "GetLobby")
	if ok and type(lobby) == "table" then
		return lobby
	end
	return nil
end

-- Plateforme de secours construite par code (CourseService absent ou accueil non construit).
local function ensureFallbackLobby(): CFrame
	local existing = fallbackModel
	local cached = fallbackCFrame
	if existing and existing.Parent and cached then
		return cached
	end
	local size = SPAWN.FallbackPlatformSize
	local center = SPAWN.FallbackPlatformPosition
	local model = Instance.new("Model")
	model.Name = "FallbackLobby"

	local base = Instance.new("Part")
	base.Name = "Platform"
	base.Anchored = true
	base.Size = size
	base.Position = center
	base.Color = Color3.fromRGB(116, 204, 92)
	base.Material = Enum.Material.Grass
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	base.Parent = model

	local rim = Instance.new("Part")
	rim.Name = "Rim"
	rim.Anchored = true
	rim.Size = Vector3.new(size.X + 4, size.Y, size.Z + 4)
	rim.Position = center - Vector3.new(0, 0.4, 0)
	rim.Color = Color3.fromRGB(250, 246, 232)
	rim.Material = Enum.Material.SmoothPlastic
	rim.Parent = model

	local flagPole = Instance.new("Part")
	flagPole.Name = "FlagPole"
	flagPole.Anchored = true
	flagPole.CanCollide = false
	flagPole.Shape = Enum.PartType.Cylinder
	flagPole.Size = Vector3.new(10, 0.4, 0.4)
	flagPole.CFrame = CFrame.new(center + Vector3.new(size.X * 0.3, size.Y / 2 + 5, size.Z * 0.3))
		* CFrame.Angles(0, 0, math.rad(90))
	flagPole.Color = Color3.fromRGB(245, 245, 245)
	flagPole.Material = Enum.Material.SmoothPlastic
	flagPole.Parent = model

	local flag = Instance.new("Part")
	flag.Name = "Flag"
	flag.Anchored = true
	flag.CanCollide = false
	flag.Size = Vector3.new(0.2, 2, 3)
	flag.CFrame = CFrame.new(center + Vector3.new(size.X * 0.3, size.Y / 2 + 9, size.Z * 0.3 + 1.5))
	flag.Color = Color3.fromRGB(255, 92, 92)
	flag.Material = Enum.Material.SmoothPlastic
	flag.Parent = model

	model.PrimaryPart = base
	model.Parent = Workspace
	callService("CollisionService", "AssignModel", model, "Course", false)
	fallbackModel = model
	local spawnCFrame = CFrame.new(center + Vector3.new(0, size.Y / 2, 0))
	fallbackCFrame = spawnCFrame
	Log.warn(LOG_TAG, "accueil indisponible : plateforme de secours utilisée")
	return spawnCFrame
end

-- Attend que CourseService fournisse l'accueil (au plus `timeout` s, une seule fois pour tout le serveur).
local function waitForLobby(timeout: number): { [string]: any }?
	local lobby = getLobby()
	if lobby or lobbyWaited then
		return lobby
	end
	local startedAt = os.clock()
	while os.clock() - startedAt < timeout do
		task.wait(0.5)
		lobby = getLobby()
		if lobby then
			return lobby
		end
	end
	lobbyWaited = true
	return nil
end

local function jitter(cframe: CFrame): CFrame
	local radius = SPAWN.PadJitter
	if radius <= 0 then
		return cframe
	end
	local angle = math.random() * math.pi * 2
	local distance = math.sqrt(math.random()) * radius
	return cframe + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

-- Plot d'apparition de l'accueil (tourniquet sur les plots, sinon point unique, sinon plateforme de secours).
function SpawnService.GetLobbyCFrame(_player: Player?): CFrame
	local lobby = getLobby()
	if lobby then
		local spawns = lobby.spawns
		if type(spawns) == "table" then
			local valid: { CFrame } = {}
			for _, value in spawns :: { any } do
				if Validate.isFiniteCFrame(value) then
					table.insert(valid, value)
				end
			end
			if #valid > 0 then
				padCursor = (padCursor % #valid) + 1
				return jitter(valid[padCursor])
			end
		end
		if Validate.isFiniteCFrame(lobby.spawn) then
			return jitter(lobby.spawn :: CFrame)
		end
	end
	return jitter(ensureFallbackLobby())
end

local cachedLobbyKillY = SPAWN.LobbyKillY
local lobbyKillYReadAt = -math.huge

-- killY de l'accueil (relu au plus toutes les 2 s : la boucle de surveillance tourne 4 fois par seconde).
local function lobbyKillY(): number
	local time = os.clock()
	if time - lobbyKillYReadAt < 2 then
		return cachedLobbyKillY
	end
	lobbyKillYReadAt = time
	local lobby = getLobby()
	cachedLobbyKillY = if lobby and Validate.isFiniteNumber(lobby.killY) then lobby.killY :: number else SPAWN.LobbyKillY
	return cachedLobbyKillY
end

-- Limites de chute de l'image courante : (killY du trou, bornes du trou) si un trou est chargé, et killY de
-- l'accueil. Un personnage dans l'emprise horizontale du trou suit la limite du trou, les autres celle de l'accueil
-- (le trou est construit loin de l'accueil : les spectateurs restés à l'accueil ne sont jamais concernés).
type KillZones = { holeKillY: number?, holeMin: Vector3?, holeMax: Vector3?, lobbyKillY: number }

local HOLE_BOUNDS_MARGIN = 60

local function currentKillZones(): KillZones
	local zones: KillZones = { holeKillY = nil, holeMin = nil, holeMax = nil, lobbyKillY = lobbyKillY() }
	if MatchStateMachine.isHolePhase(currentPhase()) then
		local ok, runtime = callService("CourseService", "GetCurrent")
		if ok and type(runtime) == "table" and Validate.isFiniteNumber(runtime.killY) then
			zones.holeKillY = runtime.killY
			local bounds = runtime.bounds
			if type(bounds) == "table" and Validate.isFiniteVector3(bounds.min) and Validate.isFiniteVector3(bounds.max) then
				zones.holeMin = bounds.min
				zones.holeMax = bounds.max
			end
		end
	end
	return zones
end

local function killYAt(zones: KillZones, position: Vector3): number
	local holeKillY = zones.holeKillY
	if holeKillY == nil then
		return zones.lobbyKillY
	end
	local low, high = zones.holeMin, zones.holeMax
	if low == nil or high == nil then
		return math.min(holeKillY, zones.lobbyKillY)
	end
	local margin = HOLE_BOUNDS_MARGIN
	local inside = position.X >= low.X - margin
		and position.X <= high.X + margin
		and position.Z >= low.Z - margin
		and position.Z <= high.Z + margin
	return if inside then holeKillY else zones.lobbyKillY
end

--------------------------------------------------------------------------------
-- Résolution des destinations
--------------------------------------------------------------------------------

local function fromResolver(player: Player): CFrame?
	local fn = resolver
	if not fn then
		return nil
	end
	local ok, result = pcall(fn, player)
	if not ok then
		Log.warn(LOG_TAG, "résolveur d'apparition en erreur :", result)
		return nil
	end
	if Validate.isFiniteCFrame(result) then
		return result :: CFrame
	end
	return nil
end

local function isActiveParticipant(player: Player): boolean
	local ok, result = callService("MatchService", "IsActive", player)
	return ok and result == true
end

local function checkpointFor(player: Player): CFrame?
	local state = states[player]
	local reference: Vector3? = state and state.lastSafe
	if not reference then
		local root = getRoot(player.Character)
		reference = root and root.Position
	end
	if not reference or not Validate.isFiniteVector3(reference) then
		return nil
	end
	local ok, result = callService("CourseService", "GetCheckpointFor", reference)
	if ok and Validate.isFiniteCFrame(result) then
		return result :: CFrame
	end
	return nil
end

-- Destination d'une réapparition : (CFrame, où).
local function resolveRespawn(player: Player): (CFrame, SpawnWhere)
	local custom = fromResolver(player)
	if custom then
		return custom, "Hole"
	end
	if currentPhase() == "Playing" and isActiveParticipant(player) then
		local checkpoint = checkpointFor(player)
		if checkpoint then
			return checkpoint, "Hole"
		end
	end
	return SpawnService.GetLobbyCFrame(player), "Lobby"
end

--------------------------------------------------------------------------------
-- Chargement et placement
--------------------------------------------------------------------------------

local function getState(player: Player): PlayerState?
	return states[player]
end

-- Player:LoadCharacter avec nouvelles tentatives ; une seule demande à la fois par joueur.
local function loadCharacter(player: Player, state: PlayerState): boolean
	if state.loading then
		local waitStart = os.clock()
		while state.loading and player.Parent == Players and os.clock() - waitStart < 20 do
			task.wait(0.1)
		end
		return isAlive(player)
	end
	state.loading = true
	local success = false
	for attempt = 1, math.max(1, SPAWN.LoadRetries) do
		if player.Parent ~= Players then
			break
		end
		local ok, err = pcall(function()
			player:LoadCharacter()
		end)
		if ok and player.Character ~= nil then
			success = true
			break
		end
		Log.warn(LOG_TAG, "LoadCharacter a échoué pour", player.Name, "tentative", attempt, err)
		if attempt == 1 then
			Net.fire("Core.NotifyKey", player, "match.spawn.loadFailed")
		end
		task.wait(SPAWN.LoadRetryDelay)
	end
	state.loading = false
	return success
end

-- Déplace le personnage existant (téléportation autorisée par MovementService).
local function moveCharacter(player: Player, target: CFrame): boolean
	local character = player.Character
	if not character or not character.Parent then
		return false
	end
	local ok, moved = callService("MovementService", "Teleport", player, target)
	if ok and moved == true then
		return true
	end
	local root = getRoot(character)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	character:PivotTo(target)
	callService("MovementService", "AllowDisplacement", player, 2, "spawn")
	return true
end

function SpawnService.PlaceCharacter(player: Player, cframe: CFrame): boolean
	if not isPlayer(player) or not Validate.isFiniteCFrame(cframe) then
		return false
	end
	local placed = groundedCFrame(cframe)
	local moved = moveCharacter(player, placed)
	local state = states[player]
	if moved and state then
		state.lastSafe = placed.Position
	end
	return moved
end

function SpawnService.Spawn(player: Player, where: SpawnWhere, cframe: CFrame?, opts: SpawnOptions?): boolean
	if not isPlayer(player) or player.Parent ~= Players then
		return false
	end
	local state = getState(player)
	if not state then
		return false
	end
	local options: SpawnOptions = opts or {}
	local target: CFrame
	local destination: SpawnWhere = if where == "Hole" then "Hole" else "Lobby"
	if cframe ~= nil and Validate.isFiniteCFrame(cframe) then
		target = cframe
	elseif destination == "Hole" then
		local resolved, resolvedWhere = resolveRespawn(player)
		target, destination = resolved, resolvedWhere
	else
		target = SpawnService.GetLobbyCFrame(player)
	end

	if options.reload == true or not isAlive(player) then
		if not loadCharacter(player, state) then
			return false
		end
		if player.Parent ~= Players then
			return false
		end
	end
	local character = player.Character
	if not character then
		return false
	end
	if not getRoot(character) then
		character:WaitForChild("HumanoidRootPart", 5)
	end
	local placed = groundedCFrame(target)
	if not moveCharacter(player, placed) then
		return false
	end
	state.lastSafe = placed.Position
	local protection = if options.protection ~= nil then options.protection else SPAWN.ProtectionSeconds
	if protection > 0 then
		callService("CombatService", "GrantProtection", player, protection)
	end
	SpawnService.Spawned:Fire(player, character, destination, options.reason or destination)
	return true
end

function SpawnService.Respawn(player: Player, reason: string?): boolean
	if not isPlayer(player) or player.Parent ~= Players then
		return false
	end
	local why = if type(reason) == "string" and reason ~= "" then reason else "respawn"
	local target, where = resolveRespawn(player)
	local protection = if why == "fell" then SPAWN.FallProtectionSeconds else SPAWN.ProtectionSeconds
	return SpawnService.Spawn(player, where, target, { reason = why, protection = protection })
end

function SpawnService.SetSpawnResolver(fn: ((Player) -> CFrame?)?)
	resolver = if type(fn) == "function" then fn else nil
end

function SpawnService.GetLastSafePosition(player: Player): Vector3?
	local state = states[player]
	return state and state.lastSafe
end

function SpawnService.IsLoading(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.loading
end

--------------------------------------------------------------------------------
-- Personnages
--------------------------------------------------------------------------------

local function scheduleDeathRespawn(player: Player, state: PlayerState, character: Model)
	if state.respawnThread then
		pcall(task.cancel, state.respawnThread)
	end
	local delaySeconds = math.max(0, SPAWN.RespawnDelay)
	Net.fire("Core.NotifyKey", player, "match.spawn.respawning", { seconds = math.ceil(delaySeconds) })
	state.respawnThread = task.delay(delaySeconds, function()
		state.respawnThread = nil
		if states[player] ~= state or player.Parent ~= Players then
			return
		end
		-- Quelqu'un a déjà fait réapparaître le joueur entre-temps.
		if player.Character ~= character and isAlive(player) then
			return
		end
		SpawnService.Respawn(player, "died")
	end)
end

local function onCharacterAdded(player: Player, state: PlayerState, character: Model)
	local previous = state.characterTrove
	if previous then
		previous:Clean()
	end
	local trove = TroveModule.new()
	state.characterTrove = trove

	callService("CollisionService", "AssignCharacter", character)

	trove:Add(task.defer(function()
		if player.Character ~= character or not character.Parent then
			return
		end
		local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			local found = character:WaitForChild("Humanoid", 10)
			if found and found:IsA("Humanoid") then
				humanoid = (found :: any) :: Humanoid
			end
		end
		if not humanoid or player.Character ~= character then
			return
		end
		callService("CosmeticService", "ApplyAppearance", player, character)
		local thisHumanoid: Humanoid = humanoid
		trove:Connect(thisHumanoid.Died, function()
			if player.Character == character then
				scheduleDeathRespawn(player, state, character)
			end
		end)
	end))
end

local function setupPlayer(player: Player): PlayerState
	local existing = states[player]
	if existing then
		return existing
	end
	local state: PlayerState = {
		trove = TroveModule.new(),
		characterTrove = nil,
		loading = false,
		lastSafe = nil,
		lastFallAt = 0,
		respawnThread = nil,
	}
	states[player] = state
	state.trove:Connect(player.CharacterAdded, function(character: Model)
		onCharacterAdded(player, state, character)
	end)
	state.trove:Connect(player.CharacterRemoving, function(character: Model)
		if player.Character == character or player.Character == nil then
			local trove = state.characterTrove
			if trove then
				trove:Clean()
			end
			state.characterTrove = nil
		end
	end)
	if player.Character then
		onCharacterAdded(player, state, player.Character)
	end
	return state
end

local function cleanupPlayer(player: Player)
	local state = states[player]
	if not state then
		return
	end
	states[player] = nil
	if state.respawnThread then
		pcall(task.cancel, state.respawnThread)
		state.respawnThread = nil
	end
	local characterTrove = state.characterTrove
	if characterTrove then
		characterTrove:Clean()
	end
	state.trove:Clean()
end

-- Première apparition : résolveur (participant d'une partie en cours), sinon accueil.
local function initialSpawn(player: Player)
	local state = states[player]
	if not state or isAlive(player) then
		return
	end
	waitForLobby(SPAWN.LobbyWaitTimeout)
	if player.Parent ~= Players or isAlive(player) then
		return
	end
	local custom = fromResolver(player)
	if custom then
		SpawnService.Spawn(player, "Hole", custom, { reason = "join" })
	else
		SpawnService.Spawn(player, "Lobby", nil, { reason = "join" })
	end
end

--------------------------------------------------------------------------------
-- Surveillance des chutes et des positions sûres
--------------------------------------------------------------------------------

local function onFell(player: Player, state: PlayerState, position: Vector3)
	local time = os.clock()
	if time - state.lastFallAt < SPAWN.FallRespawnCooldown or state.loading then
		return
	end
	state.lastFallAt = time
	SpawnService.Fell:Fire(player, position)
	Net.fire("Core.NotifyKey", player, "match.spawn.fell")
	task.spawn(SpawnService.Respawn, player, "fell")
end

local function watchLoop()
	local lastSafeSample = 0
	while true do
		task.wait(SPAWN.KillCheckInterval)
		local zones = currentKillZones()
		local time = os.clock()
		local sampleSafe = time - lastSafeSample >= SPAWN.SafeSampleInterval
		if sampleSafe then
			lastSafeSample = time
		end
		for player, state in states do
			local character = player.Character
			local root = getRoot(character)
			if not character or not root or state.loading then
				continue
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				continue
			end
			local position = root.Position
			if not Validate.isFiniteVector3(position) then
				onFell(player, state, Vector3.zero)
				continue
			end
			local killY = killYAt(zones, position)
			if position.Y < killY then
				onFell(player, state, position)
			elseif sampleSafe and humanoid.FloorMaterial ~= Enum.Material.Air and position.Y > killY + 4 then
				state.lastSafe = position
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function SpawnService.Init()
	Players.CharacterAutoLoads = false
	Players.PlayerAdded:Connect(function(player: Player)
		setupPlayer(player)
		if started then
			task.spawn(initialSpawn, player)
		end
	end)
	Players.PlayerRemoving:Connect(cleanupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
end

function SpawnService.Start()
	started = true
	for _, player in Players:GetPlayers() do
		task.spawn(initialSpawn, player)
	end
	task.spawn(watchLoop)
end

return SpawnService
