--!strict
--[[
	LobbyService — salon : hôte, réglages de partie, prêts, équipes, playlists personnalisées, parties privées
	et entraînement à l'accueil (docs/ARCHITECTURE.md §8, priorité 60 ; règles : docs/REGLES_SCORE.md §6 et §9).

	Ce service ne change JAMAIS la phase : il émet des demandes que MatchService (seul écrivain de
	GameState.Phase, HostUserId et SettingsJson) applique.
	  PrepareRequested(requester)   hôte : Lobby -> Preparing (Lobby.Advance)
	  CancelRequested(requester)    hôte : Preparing -> Lobby (Lobby.Cancel)
	  StartRequested(settings)      hôte (Lobby.Advance en préparation) ou départ automatique (tous prêts)
	  HostChanged(newHost?, oldHost?)   SettingsChanged(settings)   ClientReady(player)
	  SpectatorChanged(player, isSpectator)   TrainingChanged(player, kind?)

	API
	  GetHost() -> Player?          IsHost(player) -> boolean
	  GetSettings() -> MatchSettings (copie)       ApplySetting(player?, key, value) -> (boolean, cléErreur?, vars?)
	  SetCustomPlaylist(player?, ids) -> (boolean, cléErreur?, vars?)
	  BalanceTeams()                GetTeamChoice(player) -> "Red" | "Blue" | "Auto"
	  GetParticipants() -> { Player }   (ordre d'arrivée ; spectateurs exclus ; plafond 8/16 ; Solo : 1)
	  GetMaxParticipants() -> number    CanStart() -> boolean    GetJoinOrder() -> { Player }
	  SetSpectatorPreference(player, bool)    IsSpectatorPreferred(player) -> boolean
	  IsTraining(player) -> boolean     EndTraining(player, cléNotification?)
	  (player = nil dans ApplySetting / SetCustomPlaylist : appel système, sans contrôle d'hôte.)

	REMOTES GÉRÉS (Net/Remotes/Lobby.luau + Core.ClientReady, dont ce service est l'unique handler)
	  Lobby.SetSetting, Lobby.SetCustomPlaylist, Lobby.SetReady, Lobby.Advance, Lobby.Cancel, Lobby.SetTeam,
	  Lobby.BalanceTeams, Lobby.CreatePrivate, Lobby.RequestTraining ; instantanés Lobby.State (regroupés,
	  envoyés aussi à chaque Core.ClientReady). Refus expliqués par Core.NotifyKey (clés Locale "lobby.*").

	ATTRIBUTS JOUEUR POSÉS : Ready (bool), Practice (bool), TrainingKind ("" | "Range" | "Tutorial").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local ConfigMatch = require(Shared.Config.Match)
local GameState = require(Shared.Util.GameState)
local Log = require(Shared.Util.Log)
local MatchStateMachine = require(Shared.Logic.MatchStateMachine)
local Net = require(Shared.Net)
local Playlist = require(Shared.Logic.Playlist)
local Scoring = require(Shared.Logic.Scoring)
local SignalModule = require(Shared.Util.Signal)
local Validate = require(Shared.Util.Validate)

type Signal = SignalModule.Signal
type MatchSettings = Types.MatchSettings
type TeamChoice = "Red" | "Blue" | "Auto"

type TrainingSession = {
	kind: string,
	origin: Vector3,
	startedAt: number,
}

type AutoStart = {
	token: number,
	endsAt: number,
	thread: thread?,
}

local LOG_TAG = "Lobby"
local LOBBY = ConfigMatch.Lobby
local TRAINING = ConfigMatch.Training
local PRIVATE = ConfigMatch.Private

local LobbyService = {}
LobbyService.Priority = 60
LobbyService.HostChanged = SignalModule.new() :: Signal -- (newHost: Player?, oldHost: Player?)
LobbyService.SettingsChanged = SignalModule.new() :: Signal -- (settings: MatchSettings)
LobbyService.PrepareRequested = SignalModule.new() :: Signal -- (requester: Player?)
LobbyService.CancelRequested = SignalModule.new() :: Signal -- (requester: Player?)
LobbyService.StartRequested = SignalModule.new() :: Signal -- (settings: MatchSettings)
LobbyService.ClientReady = SignalModule.new() :: Signal -- (player)
LobbyService.SpectatorChanged = SignalModule.new() :: Signal -- (player, isSpectator: boolean)
LobbyService.TrainingChanged = SignalModule.new() :: Signal -- (player, kind: string?)

local servicesFolder = script.Parent

local joinOrder: { Player } = {}
local host: Player? = nil
local settings: MatchSettings = table.clone(ConfigMatch.DefaultSettings)
local ready: { [Player]: boolean } = {}
local teamChoice: { [Player]: TeamChoice } = {}
local spectatorPref: { [Player]: boolean } = {}
local training: { [Player]: TrainingSession } = {}
local trainingCooldown: { [Player]: number } = {}
local privateBusy: { [Player]: boolean } = {}
local privatePending: { [Player]: Player } = {} -- membre téléporté -> joueur ayant demandé la partie privée
local autoStart: AutoStart? = nil
local autoStartToken = 0
local stateScheduled = false
local startPendingUntil = 0
local preparePendingUntil = 0

--------------------------------------------------------------------------------
-- Outils
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

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function isPresent(player: Player): boolean
	return player.Parent == Players
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function currentPhase(): string
	local phase = GameState.read("Phase")
	return if type(phase) == "string" then phase else "Lobby"
end

local function notify(player: Player, key: string, vars: { [string]: any }?)
	Net.fire("Core.NotifyKey", player, key, vars)
end

local function notifyAll(key: string, vars: { [string]: any }?)
	Net.fireAll("Core.NotifyKey", key, vars)
end

local function displayName(player: Player): string
	return player.DisplayName ~= "" and player.DisplayName or player.Name
end

local function copyList<T>(list: { T }?): { T }?
	if type(list) ~= "table" then
		return nil
	end
	return table.clone(list)
end

local function cloneSettings(source: MatchSettings): MatchSettings
	local copy = table.clone(source)
	copy.customHoleIds = copyList(source.customHoleIds)
	copy.biomes = copyList(source.biomes)
	return copy
end

-- Module Data/Holes (facultatif : écrit en parallèle) ; nil s'il est absent ou illisible.
local function getHoles(): any?
	local data = Shared:FindFirstChild("Data")
	local module = data and data:FindFirstChild("Holes")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		return result
	end
	return nil
end

-- Identifiants des trous jouables en partie (jamais les trous d'entraînement).
local function courseHoleIndex(): { [string]: boolean }
	local index: { [string]: boolean } = {}
	local holes = getHoles()
	if not holes or type(holes.all) ~= "function" then
		return index
	end
	local ok, list = pcall(holes.all)
	if not ok or type(list) ~= "table" then
		return index
	end
	local trainingBiome = ConfigMatch.Playlists.TrainingBiome
	for _, hole in Playlist.dedupeHoles(list) do
		if hole.biome ~= trainingBiome then
			index[hole.id] = true
		end
	end
	return index
end

--------------------------------------------------------------------------------
-- Instantanés Lobby.State
--------------------------------------------------------------------------------

function LobbyService.GetMaxParticipants(): number
	return if settings.experimental16 then ConfigMatch.MaxParticipantsExperimental else ConfigMatch.MaxParticipants
end

local function eligiblePlayers(): { Player }
	local list: { Player } = {}
	for _, player in joinOrder do
		if isPresent(player) and spectatorPref[player] ~= true then
			table.insert(list, player)
		end
	end
	return list
end

function LobbyService.GetParticipants(): { Player }
	local eligible = eligiblePlayers()
	if settings.mode == "Solo" then
		local currentHost = host
		if currentHost and table.find(eligible, currentHost) then
			return { currentHost }
		end
		return if eligible[1] then { eligible[1] } else {}
	end
	local limit = LobbyService.GetMaxParticipants()
	local result: { Player } = {}
	for index = 1, math.min(#eligible, limit) do
		result[index] = eligible[index]
	end
	return result
end

function LobbyService.GetJoinOrder(): { Player }
	local list: { Player } = {}
	for _, player in joinOrder do
		if isPresent(player) then
			table.insert(list, player)
		end
	end
	return list
end

function LobbyService.CanStart(): boolean
	return currentPhase() == "Preparing" and #LobbyService.GetParticipants() >= ConfigMatch.MinParticipants
end

local function buildState(): { [string]: any }
	local players = {}
	for _, player in joinOrder do
		if isPresent(player) then
			local session = training[player]
			table.insert(players, {
				userId = player.UserId,
				name = displayName(player),
				ready = ready[player] == true,
				team = teamChoice[player] or "Auto",
				spectator = spectatorPref[player] == true,
				training = if session then session.kind else "",
			})
		end
	end
	local pending = autoStart
	local currentHost = host
	return {
		hostUserId = if currentHost then currentHost.UserId else 0,
		settings = cloneSettings(settings),
		players = players,
		canStart = LobbyService.CanStart(),
		phase = currentPhase(),
		autoStartAt = if pending then pending.endsAt else 0,
		minParticipants = ConfigMatch.MinParticipants,
		maxParticipants = LobbyService.GetMaxParticipants(),
	}
end

local function scheduleState()
	if stateScheduled then
		return
	end
	stateScheduled = true
	task.delay(LOBBY.StateDebounce, function()
		stateScheduled = false
		Net.fireAll("Lobby.State", buildState())
	end)
end

--------------------------------------------------------------------------------
-- Départ automatique (tous les participants prêts pendant la préparation)
--------------------------------------------------------------------------------

local function allParticipantsReady(): boolean
	local participants = LobbyService.GetParticipants()
	if #participants < ConfigMatch.MinParticipants then
		return false
	end
	for _, player in participants do
		if ready[player] ~= true then
			return false
		end
	end
	return true
end

local function cancelAutoStart(announce: boolean)
	local pending = autoStart
	if not pending then
		return
	end
	autoStart = nil
	if pending.thread then
		pcall(task.cancel, pending.thread)
	end
	if announce then
		notifyAll("lobby.autoStartCancelled")
	end
	scheduleState()
end

local function fireStart(): boolean
	if LobbyService.StartRequested:GetConnectionCount() == 0 then
		return false
	end
	startPendingUntil = os.clock() + 6
	LobbyService.StartRequested:Fire(LobbyService.GetSettings())
	return true
end

local function evaluateAutoStart()
	local wanted = LOBBY.AutoStartWhenAllReady and currentPhase() == "Preparing" and allParticipantsReady()
	if not wanted then
		cancelAutoStart(autoStart ~= nil and currentPhase() == "Preparing")
		return
	end
	if autoStart then
		return
	end
	autoStartToken += 1
	local token = autoStartToken
	local delaySeconds = ConfigMatch.Durations.AllReadyDelay
	local pending: AutoStart = { token = token, endsAt = now() + delaySeconds, thread = nil }
	autoStart = pending
	notifyAll("lobby.autoStart", { seconds = math.ceil(delaySeconds) })
	pending.thread = task.delay(delaySeconds, function()
		if autoStart ~= pending then
			return
		end
		autoStart = nil
		if currentPhase() == "Preparing" and allParticipantsReady() then
			notifyAll("lobby.starting")
			if not fireStart() then
				notifyAll("lobby.error.matchUnavailable")
			end
		end
		scheduleState()
	end)
	scheduleState()
end

--------------------------------------------------------------------------------
-- Hôte
--------------------------------------------------------------------------------

local function setHost(newHost: Player?)
	local old = host
	if old == newHost then
		return
	end
	host = newHost
	LobbyService.HostChanged:Fire(newHost, old)
	if newHost then
		if old ~= nil then
			notifyAll("lobby.hostChanged", { name = displayName(newHost) })
		end
		notify(newHost, "lobby.youAreHost")
	end
	scheduleState()
end

function LobbyService.GetHost(): Player?
	local current = host
	if current and not isPresent(current) then
		return nil
	end
	return current
end

function LobbyService.IsHost(player: Player): boolean
	return isPlayer(player) and host == player and isPresent(player)
end

--------------------------------------------------------------------------------
-- Réglages
--------------------------------------------------------------------------------

function LobbyService.GetSettings(): MatchSettings
	return cloneSettings(settings)
end

local function roundToStep(value: number, step: number?): number
	if step == nil or step <= 0 then
		return value
	end
	local rounded = math.floor(value / step + 0.5) * step
	return tonumber(string.format("%.4f", rounded)) or rounded
end

-- Valide une valeur selon Config.Match.SettingRules : (ok, valeur normalisée, cléErreur?, variables?).
local function validateSetting(key: string, value: any): (boolean, any, string?, { [string]: any }?)
	local rule = ConfigMatch.SettingRules[key]
	if rule == nil then
		return false, nil, "lobby.error.unknownSetting", nil
	end
	if rule.viaSetSetting == false then
		return false, nil, "lobby.error.invalidValue", nil
	end
	local kind = rule.kind
	if kind == "enum" then
		if type(value) == "string" and rule.values and table.find(rule.values, value) then
			return true, value, nil, nil
		end
		return false, nil, "lobby.error.invalidValue", nil
	elseif kind == "boolean" then
		if type(value) == "boolean" then
			return true, value, nil, nil
		end
		return false, nil, "lobby.error.invalidValue", nil
	elseif kind == "integer" or kind == "number" then
		if not Validate.isFiniteNumber(value) then
			return false, nil, "lobby.error.invalidValue", nil
		end
		local minimum = rule.min or -math.huge
		local maximum = rule.max or math.huge
		local number: number = if kind == "integer" then value else roundToStep(value, rule.step)
		if kind == "integer" and math.floor(number) ~= number then
			return false, nil, "lobby.error.invalidValue", nil
		end
		if number < minimum or number > maximum then
			return false, nil, "lobby.error.outOfRange", { min = rule.min, max = rule.max }
		end
		return true, number, nil, nil
	elseif kind == "playlist" then
		local playlistKind, biome = Playlist.parse(value)
		if playlistKind == nil or biome == ConfigMatch.Playlists.TrainingBiome then
			return false, nil, "lobby.error.invalidValue", nil
		end
		if playlistKind == "Custom" then
			local custom = settings.customHoleIds
			if type(custom) ~= "table" or #custom == 0 then
				return false, nil, "lobby.error.customEmpty", nil
			end
		end
		return true, value, nil, nil
	elseif kind == "biomeList" then
		if type(value) ~= "table" then
			return false, nil, "lobby.error.invalidValue", nil
		end
		local maximum = rule.max or #ConfigMatch.Playlists.CourseBiomes
		local result: { Types.Biome } = {}
		local seen: { [string]: boolean } = {}
		for index = 1, maximum + 1 do
			local entry = (value :: { any })[index]
			if entry == nil then
				break
			end
			if index > maximum then
				return false, nil, "lobby.error.invalidValue", nil
			end
			local valid = type(entry) == "string"
				and rule.values ~= nil
				and table.find(rule.values, entry) ~= nil
				and entry ~= ConfigMatch.Playlists.TrainingBiome
			if not valid or seen[entry] then
				return false, nil, "lobby.error.invalidValue", nil
			end
			seen[entry] = true
			table.insert(result, entry :: Types.Biome)
		end
		local normalized: { Types.Biome }? = if #result > 0 then result else nil
		return true, normalized, nil, nil
	end
	return false, nil, "lobby.error.invalidValue", nil
end

local function settingsChanged()
	LobbyService.SettingsChanged:Fire(LobbyService.GetSettings())
	scheduleState()
	evaluateAutoStart()
end

-- Applique un réglage (hôte uniquement, accueil ou préparation). player = nil : appel système.
function LobbyService.ApplySetting(player: Player?, key: any, value: any): (boolean, string?, { [string]: any }?)
	if player ~= nil and not LobbyService.IsHost(player) then
		return false, "lobby.error.notHost", nil
	end
	if not MatchStateMachine.allowsSettingsChange(currentPhase()) then
		return false, "lobby.error.phase", nil
	end
	if type(key) ~= "string" then
		return false, "lobby.error.unknownSetting", nil
	end
	local ok, normalized, errorKey, vars = validateSetting(key, value)
	if not ok then
		return false, errorKey or "lobby.error.invalidValue", vars
	end
	if key == "friendlyFire" and normalized == true and settings.mode == "Teams" then
		return false, "lobby.error.friendlyFireTeams", nil
	end
	local target = settings :: any
	target[key] = normalized
	if key == "mode" and normalized == "Teams" then
		settings.friendlyFire = false
	end
	if key == "playlist" and normalized == "Custom" and type(settings.customHoleIds) == "table" then
		settings.holeCount = #(settings.customHoleIds :: { string })
	end
	settingsChanged()
	return true, nil, nil
end

-- Playlist personnalisée : ids connus (hors entraînement), uniques, 1..18. Bascule la playlist sur "Custom".
function LobbyService.SetCustomPlaylist(player: Player?, ids: any): (boolean, string?, { [string]: any }?)
	if player ~= nil and not LobbyService.IsHost(player) then
		return false, "lobby.error.notHost", nil
	end
	if not MatchStateMachine.allowsSettingsChange(currentPhase()) then
		return false, "lobby.error.phase", nil
	end
	if type(ids) ~= "table" then
		return false, "lobby.error.customInvalid", nil
	end
	local known = courseHoleIndex()
	if next(known) == nil then
		return false, "lobby.error.noHoles", nil
	end
	local clean, rejected = Playlist.sanitizeCustom(ids, known, LOBBY.MaxCustomHoles)
	if #clean < LOBBY.MinCustomHoles then
		return false, "lobby.error.customInvalid", nil
	end
	settings.customHoleIds = clean
	settings.playlist = "Custom"
	settings.holeCount = #clean
	settingsChanged()
	if player then
		notify(player, "lobby.custom.applied", { count = #clean })
		if #rejected > 0 then
			notify(player, "lobby.custom.partial", { count = #rejected })
		end
	end
	return true, nil, nil
end

--------------------------------------------------------------------------------
-- Prêts, équipes, spectateurs
--------------------------------------------------------------------------------

local function setReady(player: Player, value: boolean)
	local wanted = value and spectatorPref[player] ~= true
	if (ready[player] == true) == wanted then
		return
	end
	ready[player] = wanted
	player:SetAttribute("Ready", wanted)
	scheduleState()
	evaluateAutoStart()
end

function LobbyService.GetTeamChoice(player: Player): TeamChoice
	return teamChoice[player] or "Auto"
end

function LobbyService.SetTeamChoice(player: Player, choice: any): (boolean, string?)
	if type(choice) ~= "string" or not table.find(LOBBY.TeamChoices, choice) then
		return false, "lobby.error.invalidTeam"
	end
	if not MatchStateMachine.allowsSettingsChange(currentPhase()) then
		return false, "lobby.error.phase"
	end
	teamChoice[player] = choice :: TeamChoice
	scheduleState()
	return true, nil
end

-- Équilibrage déterministe : Rouge, Bleu, Rouge… dans l'ordre d'arrivée (remplace les choix existants).
function LobbyService.BalanceTeams()
	local participants = eligiblePlayers()
	local teams = Scoring.balanceTeams(#participants)
	for index, player in participants do
		teamChoice[player] = teams[index]
	end
	scheduleState()
end

function LobbyService.SetSpectatorPreference(player: Player, isSpectator: boolean)
	if not isPlayer(player) then
		return
	end
	local value = isSpectator == true
	if (spectatorPref[player] == true) == value then
		return
	end
	spectatorPref[player] = value
	if value then
		setReady(player, false)
	end
	LobbyService.SpectatorChanged:Fire(player, value)
	scheduleState()
	evaluateAutoStart()
end

function LobbyService.IsSpectatorPreferred(player: Player): boolean
	return spectatorPref[player] == true
end

--------------------------------------------------------------------------------
-- Entraînement à l'accueil (aucun score, aucune pièce)
--------------------------------------------------------------------------------

function LobbyService.IsTraining(player: Player): boolean
	return training[player] ~= nil
end

function LobbyService.EndTraining(player: Player, noticeKey: string?)
	local session = training[player]
	if not session then
		return
	end
	training[player] = nil
	-- Seule une balle d'entraînement est retirée (jamais une balle de partie).
	local ok, isPractice = callService("BallService", "IsPractice", player)
	if ok and isPractice == true then
		callService("BallService", "RemoveBall", player)
	end
	if isPresent(player) then
		player:SetAttribute("Practice", false)
		player:SetAttribute("TrainingKind", "")
		if noticeKey then
			notify(player, noticeKey)
		end
	end
	LobbyService.TrainingChanged:Fire(player, nil)
	scheduleState()
end

local function endAllTraining(noticeKey: string?)
	local list: { Player } = {}
	for player in training do
		table.insert(list, player)
	end
	for _, player in list do
		LobbyService.EndTraining(player, noticeKey)
	end
end

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

function LobbyService.RequestTraining(player: Player, kind: any): (boolean, string?)
	if type(kind) ~= "string" or not table.find(TRAINING.Kinds, kind) then
		return false, "lobby.training.invalid"
	end
	if currentPhase() ~= "Lobby" then
		return false, "lobby.training.phase"
	end
	local time = os.clock()
	if time < (trainingCooldown[player] or 0) then
		return false, "lobby.error.tooFast"
	end
	trainingCooldown[player] = time + TRAINING.Cooldown
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 or not character:FindFirstChild("HumanoidRootPart") then
		return false, "lobby.training.noCharacter"
	end
	local okLobby, lobby = callService("CourseService", "GetLobby")
	if not okLobby or type(lobby) ~= "table" then
		return false, "lobby.training.unavailable"
	end
	local tee = if kind == "Range" then lobby.rangeTee else lobby.practiceTee
	if not Validate.isFiniteCFrame(tee) then
		return false, "lobby.training.unavailable"
	end
	local teeCFrame: CFrame = tee
	if training[player] then
		LobbyService.EndTraining(player, nil)
	end

	-- Téléportation au départ de la zone (SpawnService : pose au sol + exemption de plausibilité).
	local okPlace, placed = callService("SpawnService", "PlaceCharacter", player, teeCFrame)
	if not (okPlace and placed == true) then
		local okTeleport = callService("MovementService", "Teleport", player, teeCFrame + Vector3.new(0, 3, 0))
		if not okTeleport then
			character:PivotTo(teeCFrame + Vector3.new(0, 3, 0))
		end
	end

	local look = horizontal(teeCFrame.LookVector)
	local forward = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local ballPosition = teeCFrame.Position + forward * TRAINING.BallForward
	local okBall, ball = callService("BallService", "SpawnBall", player, ballPosition, { practice = true })
	if not okBall or ball == nil then
		return false, "lobby.training.ballFailed"
	end

	training[player] = { kind = kind, origin = teeCFrame.Position, startedAt = time }
	player:SetAttribute("Practice", true)
	player:SetAttribute("TrainingKind", kind)
	notify(player, if kind == "Range" then "lobby.training.startedRange" else "lobby.training.startedTutorial")
	LobbyService.TrainingChanged:Fire(player, kind)
	scheduleState()
	return true, nil
end

local function trainingLoop()
	while true do
		task.wait(TRAINING.CheckInterval)
		local toEnd: { Player } = {}
		for player, session in training do
			if not isPresent(player) then
				table.insert(toEnd, player)
				continue
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local okBall, ball = callService("BallService", "GetBall", player)
			if okBall and ball == nil then
				table.insert(toEnd, player)
			elseif root and root:IsA("BasePart") then
				local distance = horizontal(root.Position - session.origin).Magnitude
				if distance > TRAINING.AreaRadius then
					table.insert(toEnd, player)
				end
			end
		end
		for _, player in toEnd do
			LobbyService.EndTraining(player, "lobby.training.ended")
		end
	end
end

--------------------------------------------------------------------------------
-- Parties privées (serveur réservé ; expérience publiée uniquement, jamais dans Studio)
--------------------------------------------------------------------------------

local function teleportFailureKey(result: Enum.TeleportResult): string
	if result == Enum.TeleportResult.Flooded then
		return "lobby.private.failedFlooded"
	elseif result == Enum.TeleportResult.GameFull then
		return "lobby.private.failedFull"
	elseif result == Enum.TeleportResult.Unauthorized then
		return "lobby.private.failedUnauthorized"
	elseif result == Enum.TeleportResult.IsTeleporting then
		return "lobby.private.busy"
	end
	return "lobby.private.failed"
end

local function buildTeleportOptions(requester: Player): TeleportOptions
	local options = Instance.new("TeleportOptions")
	local okReserve, accessCode, serverId = pcall(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	local configured = false
	if okReserve and type(serverId) == "string" and serverId ~= "" then
		-- API actuelle : identifiant du serveur réservé ; repli sur le code d'accès si la propriété manque.
		configured = pcall(function()
			local anyOptions: any = options
			anyOptions.ReservedServerId = serverId
		end)
	end
	if not configured and okReserve and type(accessCode) == "string" and accessCode ~= "" then
		configured = pcall(function()
			options.ReservedServerAccessCode = accessCode
		end)
	end
	if not configured then
		options.ShouldReserveServer = true
	end
	pcall(function()
		options:SetTeleportData({ privateMatch = true, hostUserId = requester.UserId })
	end)
	return options
end

local function privateGroup(requester: Player): { Player }
	local group: { Player } = { requester }
	if not PRIVATE.IncludeFriends then
		return group
	end
	for _, other in Players:GetPlayers() do
		if #group >= PRIVATE.MaxPlayers then
			break
		end
		if other ~= requester then
			local ok, isFriend = pcall(function()
				return requester:IsFriendsWith(other.UserId)
			end)
			if ok and isFriend == true then
				table.insert(group, other)
			end
		end
	end
	return group
end

local function runPrivateTeleport(requester: Player)
	local group = privateGroup(requester)
	notify(requester, "lobby.private.creating", { count = #group })
	for _, member in group do
		if member ~= requester then
			notify(member, "lobby.private.invited", { name = displayName(requester) })
		end
	end
	local attempts = math.max(1, PRIVATE.Retries + 1)
	for attempt = 1, attempts do
		local present: { Player } = {}
		for _, member in group do
			if isPresent(member) then
				table.insert(present, member)
			end
		end
		if #present == 0 or not isPresent(requester) then
			break
		end
		local options = buildTeleportOptions(requester)
		for _, member in present do
			privatePending[member] = requester
		end
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, present, options)
		end)
		if ok then
			-- Les échecs asynchrones arrivent par TeleportInitFailed ; le verrou tombe de lui-même ensuite.
			task.delay(15, function()
				privateBusy[requester] = nil
				for _, member in present do
					if privatePending[member] == requester then
						privatePending[member] = nil
					end
				end
			end)
			return
		end
		for _, member in present do
			if privatePending[member] == requester then
				privatePending[member] = nil
			end
		end
		Log.warn(LOG_TAG, "téléportation privée échouée (tentative " .. attempt .. ") :", err)
		if attempt < attempts then
			notify(requester, "lobby.private.retrying")
			task.wait(PRIVATE.RetryDelay)
		end
	end
	privateBusy[requester] = nil
	if isPresent(requester) then
		notify(requester, "lobby.private.failed")
	end
end

function LobbyService.CreatePrivate(player: Player): (boolean, string?)
	if RunService:IsStudio() then
		return false, "lobby.private.studio"
	end
	if game.PlaceId == 0 then
		return false, "lobby.private.unpublished"
	end
	if game.PrivateServerId ~= "" then
		return false, "lobby.private.onPrivateServer"
	end
	if not MatchStateMachine.allowsSettingsChange(currentPhase()) then
		return false, "lobby.private.phase"
	end
	if privateBusy[player] then
		return false, "lobby.private.busy"
	end
	privateBusy[player] = true
	task.spawn(runPrivateTeleport, player)
	return true, nil
end

--------------------------------------------------------------------------------
-- Avancer / annuler
--------------------------------------------------------------------------------

local function advance(player: Player)
	if not LobbyService.IsHost(player) then
		notify(player, "lobby.error.notHost")
		return
	end
	local phase = currentPhase()
	if phase == "Lobby" then
		if os.clock() < preparePendingUntil then
			return
		end
		if LobbyService.PrepareRequested:GetConnectionCount() == 0 then
			notify(player, "lobby.error.matchUnavailable")
			return
		end
		preparePendingUntil = os.clock() + 3
		LobbyService.PrepareRequested:Fire(player)
		task.delay(3, function()
			if currentPhase() == "Lobby" and isPresent(player) and preparePendingUntil > 0 then
				preparePendingUntil = 0
				notify(player, "lobby.error.prepareFailed")
			end
		end)
	elseif phase == "Preparing" then
		if os.clock() < startPendingUntil then
			notify(player, "lobby.error.alreadyStarting")
			return
		end
		if not LobbyService.CanStart() then
			notify(player, "lobby.error.noParticipants", { min = ConfigMatch.MinParticipants })
			return
		end
		cancelAutoStart(false)
		notifyAll("lobby.starting")
		if not fireStart() then
			notify(player, "lobby.error.matchUnavailable")
			return
		end
		task.delay(6, function()
			if currentPhase() == "Preparing" and startPendingUntil > 0 and os.clock() >= startPendingUntil then
				startPendingUntil = 0
				if isPresent(player) then
					notify(player, "lobby.error.startTimeout")
				end
			end
		end)
	else
		notify(player, "lobby.error.phase")
	end
end

local function cancel(player: Player)
	if not LobbyService.IsHost(player) then
		notify(player, "lobby.error.notHost")
		return
	end
	if currentPhase() ~= "Preparing" then
		notify(player, "lobby.error.phase")
		return
	end
	if LobbyService.CancelRequested:GetConnectionCount() == 0 then
		notify(player, "lobby.error.cancelUnavailable")
		return
	end
	cancelAutoStart(false)
	LobbyService.CancelRequested:Fire(player)
end

--------------------------------------------------------------------------------
-- Joueurs et phases
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	if table.find(joinOrder, player) then
		return
	end
	table.insert(joinOrder, player)
	ready[player] = false
	teamChoice[player] = "Auto"
	player:SetAttribute("Ready", false)
	player:SetAttribute("Practice", false)
	player:SetAttribute("TrainingKind", "")
	if LobbyService.GetHost() == nil then
		setHost(player)
	end
	scheduleState()
	evaluateAutoStart()
end

local function onPlayerRemoving(player: Player)
	if training[player] then
		training[player] = nil
		LobbyService.TrainingChanged:Fire(player, nil)
	end
	local index = table.find(joinOrder, player)
	if index then
		table.remove(joinOrder, index)
	end
	ready[player] = nil
	teamChoice[player] = nil
	spectatorPref[player] = nil
	trainingCooldown[player] = nil
	privateBusy[player] = nil
	privatePending[player] = nil
	if host == player then
		-- Migration : le joueur présent depuis le plus longtemps devient hôte.
		local nextHost: Player? = nil
		for _, candidate in joinOrder do
			if isPresent(candidate) then
				nextHost = candidate
				break
			end
		end
		setHost(nextHost)
	end
	scheduleState()
	evaluateAutoStart()
end

local function onPhaseChanged(phase: any)
	if phase ~= "Lobby" then
		if next(training) ~= nil then
			endAllTraining(if phase == "Preparing" then "lobby.training.endedPreparing" else "lobby.training.ended")
		end
	end
	preparePendingUntil = 0
	if phase ~= "Preparing" then
		startPendingUntil = 0
		cancelAutoStart(false)
	end
	if phase == "Lobby" then
		-- Retour à l'accueil : personne n'est plus prêt.
		for _, player in joinOrder do
			if ready[player] then
				ready[player] = false
				if isPresent(player) then
					player:SetAttribute("Ready", false)
				end
			end
		end
	end
	scheduleState()
	evaluateAutoStart()
end

--------------------------------------------------------------------------------
-- Remotes
--------------------------------------------------------------------------------

local function bindRemotes()
	Net.on("Lobby.SetSetting", function(player: Player, key: any, value: any)
		local ok, errorKey, vars = LobbyService.ApplySetting(player, key, value)
		if not ok then
			notify(player, errorKey or "lobby.error.invalidValue", vars)
		end
	end)

	Net.on("Lobby.SetCustomPlaylist", function(player: Player, ids: any)
		local ok, errorKey, vars = LobbyService.SetCustomPlaylist(player, ids)
		if not ok then
			notify(player, errorKey or "lobby.error.customInvalid", vars)
		end
	end)

	Net.on("Lobby.SetReady", function(player: Player, value: boolean)
		if not MatchStateMachine.allowsSettingsChange(currentPhase()) then
			notify(player, "lobby.error.phase")
			return
		end
		setReady(player, value)
	end)

	Net.on("Lobby.Advance", function(player: Player)
		advance(player)
	end)

	Net.on("Lobby.Cancel", function(player: Player)
		cancel(player)
	end)

	Net.on("Lobby.SetTeam", function(player: Player, choice: string)
		local ok, errorKey = LobbyService.SetTeamChoice(player, choice)
		if not ok then
			notify(player, errorKey or "lobby.error.invalidTeam")
		end
	end)

	Net.on("Lobby.BalanceTeams", function(player: Player)
		if not LobbyService.IsHost(player) then
			notify(player, "lobby.error.notHost")
			return
		end
		if not MatchStateMachine.allowsSettingsChange(currentPhase()) then
			notify(player, "lobby.error.phase")
			return
		end
		LobbyService.BalanceTeams()
		notifyAll("lobby.teamsBalanced")
	end)

	Net.on("Lobby.CreatePrivate", function(player: Player)
		local ok, errorKey = LobbyService.CreatePrivate(player)
		if not ok then
			notify(player, errorKey or "lobby.private.failed")
		end
	end)

	Net.on("Lobby.RequestTraining", function(player: Player, kind: string)
		local ok, errorKey = LobbyService.RequestTraining(player, kind)
		if not ok then
			notify(player, errorKey or "lobby.training.unavailable")
		end
	end)

	Net.on("Core.ClientReady", function(player: Player)
		Net.fire("Lobby.State", player, buildState())
		LobbyService.ClientReady:Fire(player)
	end)
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function LobbyService.Init()
	settings = cloneSettings(ConfigMatch.DefaultSettings)
	bindRemotes()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	GameState.changed("Phase", onPhaseChanged)
	TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string)
		local requester = privatePending[player]
		if requester == nil then
			return -- téléportation étrangère à ce service
		end
		privatePending[player] = nil
		privateBusy[requester] = nil
		Log.warn(LOG_TAG, "TeleportInitFailed", player.Name, tostring(result), message)
		if isPresent(player) then
			notify(player, teleportFailureKey(result))
		end
	end)
end

function LobbyService.Start()
	task.spawn(trainingLoop)
	scheduleState()
end

return LobbyService
