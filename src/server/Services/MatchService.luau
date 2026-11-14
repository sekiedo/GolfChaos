--!strict
--[[
	MatchService — boucle de jeu : machine à états, modes, score, résultats, podium
	(docs/ARCHITECTURE.md §6–8, priorité 70 ; règles chiffrées : docs/REGLES_SCORE.md).

	  Lobby → Preparing → Loading → HoleIntro → Countdown → Playing → HoleEnd → HoleResults
	        → (Loading du trou suivant | Podium) → Lobby
	Chaque transition est validée par shared/Logic/MatchStateMachine ; chaque phase a une durée maximale
	(Config/Match.Durations) : aucune situation ne bloque la progression.

	SEUL ÉCRIVAIN de GameState.Phase et de tous les attributs de GameState (§6) sauf PersistentData
	(HostUserId et SettingsJson recopiés depuis les signaux de LobbyService), et des attributs joueur
	Participant, Spectating, Team, Strokes (recopié de BallService.Shot), HoleFinished, FinishOrder, MatchPoints, AFK.

	ENTRÉES
	  LobbyService : PrepareRequested (Lobby → Preparing), CancelRequested (Preparing → Lobby),
	                 StartRequested(settings) (Preparing → Loading), HostChanged, SettingsChanged, ClientReady.
	  BallService  : Shot (coups, activité), Holed (arrivée), Rested / Respawned (plafond de coups).
	  Remotes      : Match.Forfeit(roundId), Match.SetSpectator(bool), Match.Heartbeat(roundId).
	SORTIES
	  Remotes      : Match.PlayerFinished, Match.HoleResults, Match.Podium, Match.Announce(clé, variables),
	                 Effects.Sound / Effects.Play / Effects.Music (cosmétique).
	  Signaux      : PhaseChanged(new, old), HoleStarted(runtime), HoleEnded(results), MatchEnded(summary),
	                 PlayerFinishedHole(player, result).

	API
	  GetPhase() / GetRoundId() / GetMatchId() / IsParticipant(player) / IsActive(player) / GetTeam(player)
	  AreAllies(a, b) / GetSettings() / GetRacePosition(player) -> (rang, total) / GetHoleRuntime() / Abort(reason?)
	  Dev (Studio uniquement) : Dev.ForceStart(settings?), Dev.SkipPhase(), Dev.FinishPlayer(player), Dev.GetDebugState()
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local ConfigMatch = require(Shared.Config.Match)
local ConfigScoring = require(Shared.Config.Scoring)
local Gameplay = require(Shared.Config.Gameplay)
local GameState = require(Shared.Util.GameState)
local Locale = require(Shared.Locale)
local Log = require(Shared.Util.Log)
local MatchStateMachine = require(Shared.Logic.MatchStateMachine)
local Net = require(Shared.Net)
local Playlist = require(Shared.Logic.Playlist)
local Scoring = require(Shared.Logic.Scoring)
local SignalModule = require(Shared.Util.Signal)
local TroveModule = require(Shared.Util.Trove)
local Validate = require(Shared.Util.Validate)

type Signal = SignalModule.Signal
type Trove = TroveModule.Trove
type Phase = Types.Phase
type Mode = Types.Mode
type Team = Types.Team
type MatchSettings = Types.MatchSettings
type HoleResult = Types.HoleResult
type EntryStatus = "Playing" | "Finished" | "TimeOut" | "Forfeit" | "Disconnected" | "AFK"

type PlayerRecord = {
	userId: number,
	name: string,
	player: Player?,
	present: boolean,
	team: Team?,
	joinedHole: number, -- index de playlist du premier trou joué
	holesAccounted: number, -- trous joués déjà comptés dans totalStrokes (rattrapage des trous manqués)
	points: number,
	holeWins: number,
	totalStrokes: number,
	birdiesOrBetter: number,
	holesPlayed: number,
	holesFinished: number,
	activeHoles: number,
	parOrBetter: number,
	holeInOnes: number,
	eagles: number,
	birdies: number,
	soloHoles: { Scoring.SoloHole },
	afkFlag: boolean, -- encore marqué AFK : délai réduit au trou suivant
	afkPos: Vector3?,
}

type HoleEntry = {
	record: PlayerRecord,
	status: EntryStatus,
	reason: string?,
	finishOrder: number?,
	finishTime: number?,
	strokes: number,
	shots: number,
	fromDistance: number?,
	wasPutt: boolean?,
	points: number,
	bonuses: { string },
	category: string?,
	startCFrame: CFrame,
	lastActivityAt: number,
	activityPos: Vector3?,
	heartbeatPos: Vector3?,
	heartbeatLook: Vector3?,
	afkWarned: boolean,
}

type HoleState = {
	index: number,
	def: Types.HoleDef,
	runtime: Types.HoleRuntime,
	par: number,
	cap: number,
	timeLimit: number,
	referenceTime: number,
	startedAt: number,
	deadline: number,
	overtimeTriggered: boolean,
	entries: { [number]: HoleEntry },
	order: { number },
	finishCount: number,
	lastFinishFrame: number?,
	lastFinishRank: number?,
	teamSizes: { [string]: number },
	frozen: boolean,
	endCheckScheduled: boolean,
	results: { HoleResult }?,
	teamWinner: Team?,
	trove: Trove,
}

type MatchState = {
	id: string,
	settings: MatchSettings,
	mode: Mode,
	playlist: { string },
	holeIndex: number,
	holesPlayed: number,
	holeCaps: { number }, -- plafond de coups de chaque trou joué (dans l'ordre)
	records: { [number]: PlayerRecord },
	order: { number },
	pendingLate: { [Player]: boolean },
	teamScores: { [string]: number },
	teamInstances: { [string]: Team },
	trove: Trove,
	lastHoleResults: { [string]: any }?,
	podium: { [string]: any }?,
	completed: boolean,
}

local LOG_TAG = "Match"
local LOCK_REASON = "MatchPhase"
local DUR = ConfigMatch.Durations
local AFK = ConfigMatch.Afk
local SPAWN = ConfigMatch.Spawn
local AUDIO = ConfigMatch.Audio
local TEAM_ORDER: { Team } = { "Red", "Blue" }

local MatchService = {}
MatchService.Priority = 70
MatchService.PhaseChanged = SignalModule.new() :: Signal -- (new: Phase, old: Phase)
MatchService.HoleStarted = SignalModule.new() :: Signal -- (runtime: HoleRuntime)
MatchService.HoleEnded = SignalModule.new() :: Signal -- (results: { HoleResult })
MatchService.MatchEnded = SignalModule.new() :: Signal -- (summary)
MatchService.PlayerFinishedHole = SignalModule.new() :: Signal -- (player, result)

local Services = require(script.Parent.Parent.Util.Services)
local phase: Phase = "Lobby"
local phaseToken = 0
local phaseTrove: Trove = TroveModule.new()
local roundId = 0
local loadAttempt = 0
local loadingStartedAt = 0
local frameCounter = 0
local match: MatchState? = nil
local hole: HoleState? = nil
local frozenRoots: { [Player]: BasePart } = {}
local currentMusic = ""
local rng = Random.new()

--------------------------------------------------------------------------------
-- Outils
--------------------------------------------------------------------------------

local services = Services.scope(LOG_TAG)
local optionalService = services.get
-- service.method(...) protégé : (false, nil) si absent ou en erreur (journalisé).
local callService = services.call

-- Abonnement protégé à un signal d'un autre service ; un signal absent est signalé (la partie en dépend).
local function connectSignal(serviceName: string, signalName: string, handler: (...any) -> ()): boolean
	local connected = services.connect(serviceName, signalName, handler)
	if not connected then
		Log.warn(LOG_TAG, "signal absent :", serviceName .. "." .. signalName)
	end
	return connected
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function isPresent(player: Player?): boolean
	return player ~= nil and player.Parent == Players
end

local function displayName(player: Player): string
	return if player.DisplayName ~= "" then player.DisplayName else player.Name
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function horizontalLook(cframe: CFrame): Vector3
	local look = flat(cframe.LookVector)
	if look.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return look.Unit
end

local function cloneSettings(source: MatchSettings): MatchSettings
	local copy = table.clone(source)
	if type(source.customHoleIds) == "table" then
		copy.customHoleIds = table.clone(source.customHoleIds)
	end
	if type(source.biomes) == "table" then
		copy.biomes = table.clone(source.biomes)
	end
	return copy
end

local function encodeSettings(settings: MatchSettings): string
	local ok, json = pcall(HttpService.JSONEncode, HttpService, settings)
	return if ok and type(json) == "string" then json else ""
end

local function setAttr(player: Player?, name: string, value: any)
	if player and player.Parent == Players then
		player:SetAttribute(name, value)
	end
end

--------------------------------------------------------------------------------
-- Annonces, sons, musique
--------------------------------------------------------------------------------

local function announceAll(key: string, vars: { [string]: any }?)
	Net.fireAll("Match.Announce", key, vars)
end

local function announceTo(player: Player, key: string, vars: { [string]: any }?)
	Net.fire("Match.Announce", player, key, vars)
end

local function announceExcept(player: Player, key: string, vars: { [string]: any }?)
	Net.fireAllExcept("Match.Announce", player, key, vars)
end

local function notify(player: Player, key: string, vars: { [string]: any }?)
	Net.fire("Core.NotifyKey", player, key, vars)
end

local function playSound(name: string, position: Vector3?)
	if name ~= "" then
		Net.fireAll("Effects.Sound", name, position)
	end
end

local function setMusic(name: string)
	if name == currentMusic then
		return
	end
	currentMusic = name
	Net.fireAll("Effects.Music", name)
end

--------------------------------------------------------------------------------
-- État répliqué
--------------------------------------------------------------------------------

local function lobbySettings(): MatchSettings
	local ok, settings = callService("LobbyService", "GetSettings")
	if ok and type(settings) == "table" then
		return settings :: MatchSettings
	end
	return cloneSettings(ConfigMatch.DefaultSettings)
end

local function resetHoleGameState()
	GameState.set("HoleIndex", 0)
	GameState.set("HoleCount", 0)
	GameState.set("HoleId", "")
	GameState.set("HoleName", "")
	GameState.set("HoleBiome", "")
	GameState.set("HolePar", 0)
	GameState.set("CupPosition", Vector3.zero)
	GameState.set("Wind", Vector3.zero)
	GameState.set("HoleStartedAt", 0)
	GameState.set("OvertimeEndsAt", 0)
end

local function publishLobbyState()
	local settings = lobbySettings()
	GameState.set("MatchId", "")
	GameState.set("Mode", settings.mode)
	GameState.set("SettingsJson", encodeSettings(settings))
	GameState.set("TeamScoreRed", 0)
	GameState.set("TeamScoreBlue", 0)
	resetHoleGameState()
end

local function initGameState()
	GameState.set("Phase", phase)
	GameState.set("PhaseEndsAt", 0)
	GameState.set("RoundId", roundId)
	local okHost, host = callService("LobbyService", "GetHost")
	GameState.set("HostUserId", if okHost and isPlayer(host) then (host :: Player).UserId else 0)
	publishLobbyState()
end

-- Attributs joueur de partie remis à zéro (accueil, nouvelle partie).
local function resetMatchAttributes(player: Player, spectating: boolean)
	setAttr(player, "Participant", false)
	setAttr(player, "Spectating", spectating)
	setAttr(player, "Team", "")
	setAttr(player, "Strokes", 0)
	setAttr(player, "HoleFinished", false)
	setAttr(player, "FinishOrder", 0)
	setAttr(player, "MatchPoints", 0)
	setAttr(player, "AFK", false)
end

local function prefersSpectating(player: Player): boolean
	local ok, value = callService("LobbyService", "IsSpectatorPreferred", player)
	return ok and value == true
end

--------------------------------------------------------------------------------
-- Machine à états
--------------------------------------------------------------------------------

-- Change de phase (validée par la table de transitions). `duration` publie PhaseEndsAt et, avec
-- `onTimeout`, programme la sortie automatique de la phase (durée maximale).
local function setPhase(new: Phase, duration: number?, onTimeout: (() -> ())?): boolean
	if not MatchStateMachine.canTransition(phase, new) then
		Log.warn(LOG_TAG, "transition refusée :", phase, "->", new)
		return false
	end
	local old = phase
	phaseTrove:Clean()
	phaseToken += 1
	local token = phaseToken
	phase = new
	GameState.set("Phase", new)
	local seconds = if duration ~= nil and duration > 0 then duration else 0
	GameState.set("PhaseEndsAt", if seconds > 0 then now() + seconds else 0)
	if seconds > 0 and onTimeout then
		local callback: () -> () = onTimeout
		phaseTrove:Add(task.delay(seconds, function()
			if phaseToken == token then
				local ok, err = xpcall(callback, debug.traceback)
				if not ok then
					Log.error(LOG_TAG, "sortie de phase " .. new .. " :", err)
					if phaseToken == token and phase ~= "Lobby" then
						MatchService.Abort("error")
					end
				end
			end
		end))
	end
	Log.info(LOG_TAG, "phase", old, "->", new)
	MatchService.PhaseChanged:Fire(new, old)
	return true
end

--------------------------------------------------------------------------------
-- Participants
--------------------------------------------------------------------------------

local function newRecord(player: Player, holeIndex: number): PlayerRecord
	return {
		userId = player.UserId,
		name = displayName(player),
		player = player,
		present = true,
		team = nil,
		joinedHole = holeIndex,
		holesAccounted = 0,
		points = 0,
		holeWins = 0,
		totalStrokes = 0,
		birdiesOrBetter = 0,
		holesPlayed = 0,
		holesFinished = 0,
		activeHoles = 0,
		parOrBetter = 0,
		holeInOnes = 0,
		eagles = 0,
		birdies = 0,
		soloHoles = {},
		afkFlag = false,
		afkPos = nil,
	}
end

local function presentRecords(m: MatchState): { PlayerRecord }
	local list: { PlayerRecord } = {}
	for _, userId in m.order do
		local record = m.records[userId]
		if record and record.present and isPresent(record.player) then
			table.insert(list, record)
		end
	end
	return list
end

local function maxParticipants(m: MatchState): number
	if m.mode == "Solo" then
		return 1
	end
	return if m.settings.experimental16 then ConfigMatch.MaxParticipantsExperimental else ConfigMatch.MaxParticipants
end

local function countPending(m: MatchState): number
	local count = 0
	for player in m.pendingLate do
		if isPresent(player) then
			count += 1
		end
	end
	return count
end

local function teamCounts(m: MatchState): { [string]: number }
	local counts: { [string]: number } = { Red = 0, Blue = 0 }
	for _, record in presentRecords(m) do
		if record.team then
			counts[record.team] += 1
		end
	end
	return counts
end

local function ensureTeamInstances(m: MatchState)
	for _, team in TEAM_ORDER do
		if m.teamInstances[team] == nil then
			local teamConfig = (ConfigMatch.Teams :: any)[team]
			local instance = Instance.new("Team")
			instance.Name = Locale.t(teamConfig.NameKey)
			instance.TeamColor = BrickColor.new(teamConfig.BrickColor)
			instance.AutoAssignable = false
			instance.Parent = Teams
			m.teamInstances[team] = instance
			m.trove:Add(instance)
		end
	end
end

local function applyTeam(m: MatchState, record: PlayerRecord)
	local player = record.player
	if not player then
		return
	end
	setAttr(player, "Team", record.team or "")
	local team = record.team
	if team and m.teamInstances[team] then
		player.Team = m.teamInstances[team]
		player.Neutral = false
	end
end

local function admitRecord(m: MatchState, record: PlayerRecord)
	local player = record.player
	if not player then
		return
	end
	-- Trous manqués : comptés au plafond pour le départage (aucun avantage à arriver tard).
	for index = record.holesAccounted + 1, m.holesPlayed do
		record.totalStrokes += m.holeCaps[index] or ConfigScoring.StrokeCap.Max
	end
	record.holesAccounted = m.holesPlayed
	setAttr(player, "Participant", true)
	setAttr(player, "Spectating", false)
	setAttr(player, "MatchPoints", record.points)
	callService("CollisionService", "SetGhost", player, false)
	applyTeam(m, record)
end

-- Arrivées tardives acceptées : elles deviennent participantes au chargement du trou suivant.
local function admitLateJoiners(m: MatchState)
	local candidates: { Player } = {}
	for player in m.pendingLate do
		table.insert(candidates, player)
	end
	table.clear(m.pendingLate)
	table.sort(candidates, function(a: Player, b: Player): boolean
		return a.UserId < b.UserId
	end)
	for _, player in candidates do
		if not isPresent(player) or prefersSpectating(player) then
			continue
		end
		if #presentRecords(m) >= maxParticipants(m) then
			notify(player, "match.lateJoin.full")
			continue
		end
		local record = m.records[player.UserId]
		if record then
			record.player = player
			record.present = true
			record.name = displayName(player)
		else
			record = newRecord(player, m.holeIndex)
			m.records[player.UserId] = record
			table.insert(m.order, player.UserId)
		end
		local admitted: PlayerRecord = record
		if m.mode == "Teams" and admitted.team == nil then
			local counts = teamCounts(m)
			admitted.team = if counts.Red <= counts.Blue then "Red" else "Blue"
		end
		admitRecord(m, admitted)
		notify(player, "match.lateJoin.nowPlaying")
	end
end

--------------------------------------------------------------------------------
-- Données des trous
--------------------------------------------------------------------------------

local function getHolesModule(): any?
	local data = Shared:FindFirstChild("Data")
	local module = data and data:FindFirstChild("Holes")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		return result
	end
	Log.warn(LOG_TAG, "Data/Holes illisible :", result)
	return nil
end

-- Trous jouables en partie (jamais les trous d'entraînement).
local function courseHoles(): { any }
	local holes = getHolesModule()
	if not holes or type(holes.all) ~= "function" then
		return {}
	end
	local ok, list = pcall(holes.all)
	if not ok or type(list) ~= "table" then
		return {}
	end
	local result = {}
	for _, def in list :: { any } do
		if type(def) == "table" and def.biome ~= ConfigMatch.Playlists.TrainingBiome then
			table.insert(result, def)
		end
	end
	return result
end

local function getHoleDef(id: string): Types.HoleDef?
	local holes = getHolesModule()
	if not holes or type(holes.get) ~= "function" then
		return nil
	end
	local ok, def = pcall(holes.get, id)
	if ok and type(def) == "table" and def.biome ~= ConfigMatch.Playlists.TrainingBiome then
		return def :: Types.HoleDef
	end
	return nil
end

local function computeWind(setting: string, bias: Vector3?): Vector3
	local windConfig = Gameplay.Wind
	if setting == "Off" then
		return Vector3.zero
	end
	local magnitude: number
	if setting == "Random" then
		magnitude = rng:NextNumber(windConfig.RandomMin, windConfig.RandomMax)
	else
		magnitude = windConfig.Strengths[setting] or 0
	end
	local vector = Vector3.zero
	if magnitude > 0 then
		local angle = rng:NextNumber(0, math.pi * 2)
		vector = Vector3.new(math.cos(angle), 0, math.sin(angle)) * magnitude
	end
	if bias ~= nil and Validate.isFiniteVector3(bias) then
		vector += flat(bias)
	end
	return vector
end

-- Position du joueur relative à un emplacement de départ (Config.Course.Tee.PlayerOffset, lu à la demande).
local DEFAULT_PLAYER_OFFSET = Vector3.new(0, 3, 3.5)
local function teePlayerOffset(): Vector3
	local configFolder = Shared:FindFirstChild("Config")
	local module = configFolder and configFolder:FindFirstChild("Course")
	if module and module:IsA("ModuleScript") then
		local ok, course = pcall(require, module)
		if ok and type(course) == "table" and type(course.Tee) == "table" and Validate.isFiniteVector3(course.Tee.PlayerOffset) then
			return course.Tee.PlayerOffset
		end
	end
	return DEFAULT_PLAYER_OFFSET
end

-- Départs équitables de CourseService (point où poser la balle), complétés par des décalages latéraux.
local function startPlacements(runtime: Types.HoleRuntime, count: number): { CFrame }
	local list: { CFrame } = {}
	local ok, result = callService("CourseService", "GetStartPlacements", count)
	if ok and type(result) == "table" then
		for _, value in result :: { any } do
			if Validate.isFiniteCFrame(value) then
				table.insert(list, value)
			end
		end
	end
	local tee: CFrame = if Validate.isFiniteCFrame(runtime.teeCFrame)
		then runtime.teeCFrame
		else CFrame.new(runtime.cupPosition + Vector3.new(0, 4, 40))
	local index = 0
	while #list < count do
		local side = if index % 2 == 0 then 1 else -1
		local step = math.floor(index / 2) + (if index % 2 == 0 then 0 else 1)
		table.insert(list, tee * CFrame.new(side * step * SPAWN.StartSpacing, 0, 0))
		index += 1
	end
	return list
end

--------------------------------------------------------------------------------
-- Gel des personnages (chargement, présentation, compte à rebours)
--------------------------------------------------------------------------------

local function setFrozen(player: Player, frozen: boolean)
	if frozen then
		local root = rootOf(player)
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
			root.Anchored = true
			frozenRoots[player] = root
		end
	else
		local root = frozenRoots[player]
		frozenRoots[player] = nil
		if root and root.Parent then
			root.Anchored = false
		end
	end
end

local function unfreezeAll()
	local list: { Player } = {}
	for player in frozenRoots do
		table.insert(list, player)
	end
	for _, player in list do
		setFrozen(player, false)
	end
end

local function lockPlayer(player: Player, locked: boolean)
	if locked then
		callService("MovementService", "Lock", player, LOCK_REASON)
	else
		callService("MovementService", "Unlock", player, LOCK_REASON)
	end
end

--------------------------------------------------------------------------------
-- Score
--------------------------------------------------------------------------------

local function ballStrokes(player: Player): number
	local ok, value = callService("BallService", "GetStrokes", player)
	if ok and Validate.isFiniteNumber(value) then
		return value :: number
	end
	return 0
end

local function isKnockedOut(player: Player): boolean
	local ok, value = callService("CombatService", "IsKnockedOut", player)
	if ok then
		return value == true
	end
	return player:GetAttribute("KnockedOut") == true
end

local function withArrival(m: MatchState): boolean
	return m.mode == "FreeForAll" or m.mode == "Teams"
end

local function scoreEntry(m: MatchState, h: HoleState, entry: HoleEntry): Scoring.HoleScore
	local status: Scoring.HoleStatus = if entry.status == "Playing" then "TimeOut" else entry.status :: any
	return Scoring.scoreHole({
		status = status,
		rank = entry.finishOrder,
		strokes = entry.strokes,
		par = h.par,
		fromDistance = entry.fromDistance,
		wasPutt = entry.wasPutt,
		finishTime = entry.finishTime,
		referenceTime = h.referenceTime,
		withArrival = withArrival(m),
		withBonuses = m.mode ~= "Training",
	})
end

-- Points retenus pour le classement : Solo et Entraînement n'en marquent pas.
local function pointsFor(m: MatchState, score: Scoring.HoleScore): number
	if m.mode == "Solo" or m.mode == "Training" then
		return 0
	end
	return score.points
end

local function standingsRows(m: MatchState): { Scoring.StandingRow }
	local entries: { Scoring.StandingInput } = {}
	for _, record in presentRecords(m) do
		table.insert(entries, {
			userId = record.userId,
			name = record.name,
			team = record.team,
			points = record.points,
			holeWins = record.holeWins,
			totalStrokes = record.totalStrokes,
			birdiesOrBetter = record.birdiesOrBetter,
		})
	end
	return Scoring.matchStandings(entries)
end

local function standingsPayload(m: MatchState): { { [string]: any } }
	local rows = {}
	for _, row in standingsRows(m) do
		table.insert(rows, {
			userId = row.userId,
			name = row.name,
			team = row.team,
			points = row.points,
			strokes = row.totalStrokes,
			holeWins = row.holeWins,
			birdiesOrBetter = row.birdiesOrBetter,
			rank = row.rank,
		})
	end
	return rows
end

--------------------------------------------------------------------------------
-- Déroulement d'un trou : déclarations anticipées
--------------------------------------------------------------------------------

local enterLobby: (returnPlayers: boolean) -> ()
local enterPodium: () -> ()
local enterLoading: () -> ()
local enterCountdown: () -> ()
local enterPlaying: () -> ()
local enterHoleResults: () -> ()
local afterResults: () -> ()
local endHole: (reason: string) -> ()

local function anyPlaying(h: HoleState, except: number?): boolean
	for userId, entry in h.entries do
		if userId ~= except and entry.status == "Playing" then
			return true
		end
	end
	return false
end

-- Fin anticipée de "Playing" quand plus personne n'est en jeu ; différée à la fin de l'image serveur pour que
-- deux arrivées simultanées soient toutes deux enregistrées.
local function scheduleEndCheck()
	local h = hole
	if not h or h.endCheckScheduled or h.frozen or phase ~= "Playing" then
		return
	end
	h.endCheckScheduled = true
	task.defer(function()
		h.endCheckScheduled = false
		if hole ~= h or h.frozen or phase ~= "Playing" then
			return
		end
		if not anyPlaying(h, nil) then
			endHole("allDone")
		end
	end)
end

-- Abandon du trou (volontaire, plafond de coups, AFK, déconnexion) : spectateur intangible du trou.
local function forfeitEntry(entry: HoleEntry, status: EntryStatus, reason: string)
	local h = hole
	if not h or h.frozen or entry.status ~= "Playing" then
		return
	end
	entry.status = status
	entry.reason = reason
	local player = entry.record.player
	if player and isPresent(player) then
		callService("BallService", "CancelAim", player, "phase")
		callService("BallService", "RemoveBall", player)
		callService("CollisionService", "SetGhost", player, true)
		local name = displayName(player)
		if reason == "strokeCap" then
			announceExcept(player, "match.announce.strokeCap", { name = name })
			announceTo(player, "match.announce.strokeCapSelf", { cap = h.cap })
		elseif reason == "voluntary" then
			announceExcept(player, "match.announce.forfeit", { name = name })
			announceTo(player, "match.announce.forfeitSelf")
		elseif reason == "afk" then
			announceExcept(player, "match.announce.afk", { name = name })
			announceTo(player, "match.announce.afkSelf")
		end
	end
	scheduleEndCheck()
end

-- Arrivée d'un joueur (même chemin pour BallService.Holed et Dev.FinishPlayer).
local function finishEntry(player: Player, entry: HoleEntry, info: { [string]: any })
	local m = match
	local h = hole
	if not m or not h or h.frozen or entry.status ~= "Playing" or phase ~= "Playing" then
		return
	end
	local time = now()
	local rank = Scoring.nextFinishRank(h.finishCount, h.lastFinishFrame, h.lastFinishRank, frameCounter)
	h.finishCount += 1
	h.lastFinishFrame = frameCounter
	h.lastFinishRank = rank

	local strokes = if Validate.isInteger(info.strokes) and info.strokes >= 1 then info.strokes else ballStrokes(player)
	entry.status = "Finished"
	entry.finishOrder = rank
	entry.finishTime = math.max(0, time - h.startedAt)
	entry.strokes = math.max(1, strokes)
	entry.fromDistance = if info.external == true then nil
		elseif Validate.isFiniteNumber(info.fromDistance) then info.fromDistance
		else nil
	entry.wasPutt = info.wasPutt == true
	local score = scoreEntry(m, h, entry)
	entry.points = pointsFor(m, score)
	entry.bonuses = score.bonus.ids
	entry.category = score.bonus.category

	setAttr(player, "HoleFinished", true)
	setAttr(player, "FinishOrder", rank)
	setAttr(player, "Strokes", entry.strokes)
	callService("BallService", "CancelAim", player, "phase")
	callService("CollisionService", "SetGhost", player, true)
	h.trove:Add(task.delay(DUR.HoledBallRemoveDelay, function()
		if hole == h then
			callService("BallService", "RemoveBall", player)
		end
	end))

	local result = {
		finished = true,
		strokes = entry.strokes,
		par = h.par,
		finishOrder = rank,
		time = entry.finishTime,
		status = "Finished",
		points = entry.points,
		bonuses = entry.bonuses,
		holeId = h.def.id,
		roundId = roundId,
	}
	MatchService.PlayerFinishedHole:Fire(player, result)
	Net.fireAll("Match.PlayerFinished", {
		userId = player.UserId,
		name = entry.record.name,
		team = entry.record.team,
		finishOrder = rank,
		strokes = entry.strokes,
		par = h.par,
		points = entry.points,
		bonuses = entry.bonuses,
		time = entry.finishTime,
	})

	-- Annonces et sons (purement cosmétiques).
	local name = displayName(player)
	if h.finishCount == 1 and withArrival(m) then
		announceAll("match.announce.firstFinish", { name = name })
	end
	local category = entry.category
	if category == "holeInOne" or category == "albatross" or category == "eagle" or category == "birdie" then
		announceAll("match.announce." .. category, { name = name })
	end
	if table.find(entry.bonuses, ConfigScoring.LongShot.Id) then
		announceAll("match.announce.longShot", { name = name })
	end
	if category == "holeInOne" then
		playSound(AUDIO.HoleInOne, nil)
	elseif Scoring.isBirdieOrBetter(category :: any) then
		playSound(AUDIO.Birdie, nil)
	end
	playSound(AUDIO.Finish, h.runtime.cupPosition)

	-- Prolongation déclenchée par la première arrivée (une seule fois, s'il reste quelqu'un en jeu).
	if m.mode ~= "Solo" and not h.overtimeTriggered and h.finishCount == 1 then
		h.overtimeTriggered = true
		if anyPlaying(h, player.UserId) then
			local deadline, triggered = Scoring.deadlineAfterFinish(time, h.deadline, m.settings.timeScale, false)
			if triggered then
				h.deadline = deadline
				GameState.set("OvertimeEndsAt", deadline)
				GameState.set("PhaseEndsAt", deadline)
				announceAll("match.announce.overtime", { seconds = math.ceil(deadline - time) })
				setMusic(AUDIO.MusicOvertime)
			end
		end
	end
	scheduleEndCheck()
end

-- Prédicat BallService.SetCanShoot : participant en jeu, trou non figé, pas KO, sous le plafond de coups.
local function canShoot(player: Player): boolean
	if phase ~= "Playing" then
		return false
	end
	local h = hole
	if not h or h.frozen then
		return false
	end
	local entry = h.entries[player.UserId]
	if not entry or entry.status ~= "Playing" then
		return false
	end
	if isKnockedOut(player) then
		return false
	end
	return ballStrokes(player) < h.cap
end

local function refuseShots(_player: Player): boolean
	return false
end

--------------------------------------------------------------------------------
-- Signaux de BallService
--------------------------------------------------------------------------------

local function playingEntry(player: Player): HoleEntry?
	local h = hole
	if not h or h.frozen or phase ~= "Playing" or not isPlayer(player) then
		return nil
	end
	local entry = h.entries[player.UserId]
	if entry and entry.status == "Playing" then
		return entry
	end
	return nil
end

local function onShot(player: Player, strokes: any, _power: any, info: any)
	if type(info) == "table" and info.practice == true then
		return
	end
	local entry = playingEntry(player)
	if not entry then
		return
	end
	entry.strokes = if Validate.isFiniteNumber(strokes) then strokes else ballStrokes(player)
	entry.shots += 1
	entry.lastActivityAt = now()
	entry.afkWarned = false
	setAttr(player, "Strokes", entry.strokes)
	if player:GetAttribute("AFK") == true then
		setAttr(player, "AFK", false)
		entry.record.afkFlag = false
	end
end

local function onHoled(player: Player, info: any)
	if type(info) ~= "table" or info.practice == true then
		return
	end
	local entry = playingEntry(player)
	if entry then
		finishEntry(player, entry, info)
	end
end

local function checkStrokeCap(player: Player)
	local entry = playingEntry(player)
	local h = hole
	if not entry or not h then
		return
	end
	entry.strokes = ballStrokes(player)
	setAttr(player, "Strokes", entry.strokes)
	if entry.strokes >= h.cap then
		forfeitEntry(entry, "Forfeit", "strokeCap")
	end
end

local function onRested(player: Player, _position: any)
	checkStrokeCap(player)
end

local function onRespawned(player: Player, _reason: any)
	-- Remise en jeu après un danger : la balle repart immobile, pénalité comprise.
	checkStrokeCap(player)
end

--------------------------------------------------------------------------------
-- Résultats du trou
--------------------------------------------------------------------------------

local function computeHoleResults(m: MatchState, h: HoleState): { HoleResult }
	local results: { HoleResult } = {}
	m.holesPlayed += 1
	m.holeCaps[m.holesPlayed] = h.cap
	for _, userId in h.order do
		local entry = h.entries[userId]
		if not entry then
			continue
		end
		if entry.status == "Playing" then
			entry.status = "TimeOut"
			entry.reason = "timeout"
		end
		local record = entry.record
		local finished = entry.status == "Finished"
		local score = scoreEntry(m, h, entry)
		entry.points = pointsFor(m, score)
		entry.bonuses = score.bonus.ids
		entry.category = score.bonus.category
		local member = record.player
		if not finished and member and isPresent(member) then
			entry.strokes = math.max(entry.strokes, ballStrokes(member))
		end
		local status: Scoring.HoleStatus = entry.status :: any
		local standing = Scoring.standingStrokes(status, entry.strokes, h.cap)

		-- Cumuls de la partie (le joueur parti reste compté jusqu'au classement final, dont il est retiré).
		record.points += entry.points
		record.totalStrokes += standing
		record.holesAccounted = math.max(record.holesAccounted, m.holesPlayed)
		record.holesPlayed += 1
		if entry.shots > 0 then
			record.activeHoles += 1
		end
		if finished then
			record.holesFinished += 1
			if entry.finishOrder == 1 then
				record.holeWins += 1
			end
			local category = entry.category
			if Scoring.isBirdieOrBetter(category :: any) then
				record.birdiesOrBetter += 1
			end
			if category ~= nil then
				record.parOrBetter += 1
			end
			if category == "holeInOne" then
				record.holeInOnes += 1
			elseif category == "eagle" or category == "albatross" then
				record.eagles += 1
			elseif category == "birdie" then
				record.birdies += 1
			end
		end
		table.insert(record.soloHoles, {
			finished = finished,
			strokes = entry.strokes,
			par = h.par,
			time = entry.finishTime,
			timeLimit = h.timeLimit,
			cap = h.cap,
		})
		setAttr(record.player, "MatchPoints", record.points)

		local result: any = {
			userId = record.userId,
			name = record.name,
			team = record.team,
			finished = finished,
			finishOrder = entry.finishOrder,
			finishTime = entry.finishTime,
			strokes = entry.strokes,
			par = h.par,
			points = entry.points,
			bonuses = entry.bonuses,
			status = entry.status,
			reason = entry.reason,
			standingStrokes = standing,
			totalPoints = record.points,
		}
		table.insert(results, result :: HoleResult)
	end

	-- Ordre d'affichage : arrivés (rang, temps), puis non-arrivés (coups retenus, nom).
	table.sort(results, function(a: HoleResult, b: HoleResult): boolean
		if a.finished ~= b.finished then
			return a.finished
		end
		if a.finished then
			local rankA, rankB = a.finishOrder or math.huge, b.finishOrder or math.huge
			if rankA ~= rankB then
				return rankA < rankB
			end
			local timeA, timeB = a.finishTime or math.huge, b.finishTime or math.huge
			if timeA ~= timeB then
				return timeA < timeB
			end
		elseif a.strokes ~= b.strokes then
			return a.strokes < b.strokes
		end
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.userId < b.userId
	end)

	-- Point d'équipe (ratio d'arrivées, puis arrivées absolues, puis moyenne de coups).
	h.teamWinner = nil
	if m.mode == "Teams" then
		local stats: { [string]: Scoring.TeamHoleStats } = {
			Red = { size = h.teamSizes.Red or 0, finishers = 0, finisherStrokes = 0 },
			Blue = { size = h.teamSizes.Blue or 0, finishers = 0, finisherStrokes = 0 },
		}
		for _, entry in h.entries do
			local team = entry.record.team
			if team and entry.status == "Finished" then
				stats[team].finishers += 1
				stats[team].finisherStrokes += entry.strokes
			end
		end
		local winner = Scoring.teamHolePoint(stats.Red, stats.Blue)
		h.teamWinner = winner
		if winner then
			m.teamScores[winner] += ConfigScoring.Team.PointPerHole
		end
		GameState.set("TeamScoreRed", m.teamScores.Red)
		GameState.set("TeamScoreBlue", m.teamScores.Blue)
	end
	h.results = results
	return results
end

-- Record personnel Solo (data.bestSolo[holeId] = { strokes, time }, champ du Schema) via PlayerDataService.Update.
local function saveSoloRecord(player: Player, holeId: string, strokes: number, time: number)
	local service = optionalService("PlayerDataService")
	if not service or type(service.Update) ~= "function" then
		return
	end
	local improved = false
	local ok, err = pcall(service.Update, player, function(data: any): (boolean, string?)
		if type(data) ~= "table" then
			return false, "invalid"
		end
		if type(data.stats) ~= "table" then
			data.stats = {}
		end
		if type(data.bestSolo) ~= "table" then
			data.bestSolo = {}
		end
		local previous = data.bestSolo[holeId]
		local candidate = { strokes = strokes, time = math.floor(time * 100 + 0.5) / 100 }
		local valid = type(previous) == "table" and Validate.isFiniteNumber(previous.strokes) and Validate.isFiniteNumber(previous.time)
		if Scoring.isBetterSoloRecord(candidate, if valid then previous else nil) then
			data.bestSolo[holeId] = candidate
			improved = true
			return true, nil
		end
		return false, nil
	end)
	if not ok then
		Log.warn(LOG_TAG, "record solo non enregistré :", err)
	elseif improved and isPresent(player) then
		announceTo(player, "match.announce.soloBest", { strokes = strokes, time = string.format("%.1f", time) })
	end
end

--------------------------------------------------------------------------------
-- Nettoyage de manche
--------------------------------------------------------------------------------

-- Retire objets, voiturettes et balles de la manche ; `unload` démonte aussi le trou.
local function cleanupRound(unload: boolean)
	callService("ItemService", "ClearRound")
	callService("VehicleService", "ClearAll")
	callService("BallService", "RemoveAll")
	if unload then
		local h = hole
		if h then
			h.trove:Clean()
		end
		hole = nil
		callService("BallService", "SetCup", nil, nil)
		callService("CourseService", "UnloadHole")
	end
end

--------------------------------------------------------------------------------
-- Phases
--------------------------------------------------------------------------------

local function participantPlayers(m: MatchState): { Player }
	local list: { Player } = {}
	for _, record in presentRecords(m) do
		local player = record.player
		if player then
			table.insert(list, player)
		end
	end
	return list
end

local function proceedToIntro()
	local m = match
	local h = hole
	if not m or not h or phase ~= "Loading" then
		return
	end
	if not setPhase("HoleIntro", DUR.HoleIntro, enterCountdown) then
		return
	end
	setMusic(AUDIO.MusicMatch)
	if h.index >= #m.playlist then
		announceAll("match.announce.lastHole")
	end
end

-- Chargement d'un trou (dans son propre thread) : trou, état répliqué, vent, placements, balles.
local function runLoading(token: number, attempt: number)
	local function stale(): boolean
		return phaseToken ~= token or loadAttempt ~= attempt or phase ~= "Loading"
	end
	local m = match
	if not m then
		return
	end
	roundId += 1
	GameState.set("RoundId", roundId)
	admitLateJoiners(m)
	local records = presentRecords(m)
	if #records == 0 then
		MatchService.Abort("noParticipants")
		return
	end

	local def: Types.HoleDef? = nil
	local runtime: Types.HoleRuntime? = nil
	while m.holeIndex <= #m.playlist do
		local id = m.playlist[m.holeIndex]
		def = getHoleDef(id)
		GameState.set("HoleIndex", m.holeIndex)
		if def then
			local loadingDef: Types.HoleDef = def
			GameState.set("HoleId", loadingDef.id)
			GameState.set("HoleName", loadingDef.name)
			GameState.set("HoleBiome", loadingDef.biome)
			GameState.set("HolePar", loadingDef.par)
			local ok, result = callService("CourseService", "LoadHole", loadingDef)
			if stale() then
				-- Délai dépassé ou partie interrompue pendant la construction : ne rien laisser derrière soi
				-- (une nouvelle tentative de chargement remplace d'elle-même le trou construit).
				if phase ~= "Loading" then
					callService("CourseService", "UnloadHole")
				end
				return
			end
			if ok and type(result) == "table" and Validate.isFiniteVector3((result :: any).cupPosition) then
				runtime = result :: Types.HoleRuntime
				break
			end
		end
		if optionalService("CourseService") == nil then
			Log.error(LOG_TAG, "CourseService absent : aucun trou ne peut être construit")
			break
		end
		Log.warn(LOG_TAG, "trou non chargeable :", id)
		announceAll("match.loading.skipped")
		callService("CourseService", "UnloadHole")
		m.holeIndex += 1
	end
	if not def or not runtime then
		if m.holesPlayed > 0 then
			enterPodium()
		else
			MatchService.Abort("noHoles")
		end
		return
	end
	local holeDef: Types.HoleDef = def
	local holeRuntime: Types.HoleRuntime = runtime

	-- État répliqué du trou.
	local par = if Validate.isFiniteNumber(holeDef.par) then holeDef.par else 3
	GameState.set("HoleIndex", m.holeIndex)
	GameState.set("HoleCount", #m.playlist)
	GameState.set("HoleId", holeDef.id)
	GameState.set("HoleName", holeDef.name)
	GameState.set("HoleBiome", holeDef.biome)
	GameState.set("HolePar", par)
	GameState.set("CupPosition", holeRuntime.cupPosition)
	GameState.set("HoleStartedAt", 0)
	GameState.set("OvertimeEndsAt", 0)
	callService("BallService", "SetCup", holeRuntime.cupPosition, holeRuntime.cupRadius)
	local wind = computeWind(m.settings.wind, holeDef.windBias)
	callService("BallService", "SetWind", wind)
	local okWind, appliedWind = callService("BallService", "GetWind")
	GameState.set("Wind", if okWind and Validate.isFiniteVector3(appliedWind) then appliedWind else wind)
	callService("CourseService", "ApplyBiomeLighting", holeDef.biome)
	callService("BallService", "SetCanShoot", refuseShots)

	-- État du trou (avant les placements : le résolveur d'apparition s'en sert).
	local timeLimit = Scoring.holeTimeLimit(holeDef.targetTime, m.settings.timeScale)
	local h: HoleState = {
		index = m.holeIndex,
		def = holeDef,
		runtime = holeRuntime,
		par = par,
		cap = Scoring.strokeCap(par),
		timeLimit = timeLimit,
		referenceTime = Scoring.referenceTime(holeDef.targetTime, m.settings.timeScale),
		startedAt = now(),
		deadline = now() + timeLimit,
		overtimeTriggered = false,
		entries = {},
		order = {},
		finishCount = 0,
		lastFinishFrame = nil,
		lastFinishRank = nil,
		teamSizes = { Red = 0, Blue = 0 },
		frozen = false,
		endCheckScheduled = false,
		results = nil,
		teamWinner = nil,
		trove = TroveModule.new(),
	}
	hole = h
	-- Emplacement de départ = point où poser la balle ; le joueur se place derrière (Config.Course.Tee).
	local placements = startPlacements(holeRuntime, #records)
	local playerOffset = teePlayerOffset()
	local playerCFrames: { CFrame } = {}
	for index, placement in placements do
		playerCFrames[index] = placement * CFrame.new(playerOffset)
	end
	for index, record in records do
		local entry: HoleEntry = {
			record = record,
			status = "Playing",
			reason = nil,
			finishOrder = nil,
			finishTime = nil,
			strokes = 0,
			shots = 0,
			fromDistance = nil,
			wasPutt = nil,
			points = 0,
			bonuses = {},
			category = nil,
			startCFrame = playerCFrames[index],
			lastActivityAt = now(),
			activityPos = nil,
			heartbeatPos = nil,
			heartbeatLook = nil,
			afkWarned = false,
		}
		h.entries[record.userId] = entry
		table.insert(h.order, record.userId)
		if record.team then
			h.teamSizes[record.team] += 1
		end
	end

	-- Placements (en parallèle : un chargement de personnage peut céder).
	local pending = #records
	for index, record in records do
		local player = record.player :: Player
		local ballSpot = placements[index]
		local standSpot = playerCFrames[index]
		setAttr(player, "Strokes", 0)
		setAttr(player, "HoleFinished", false)
		setAttr(player, "FinishOrder", 0)
		callService("CollisionService", "SetGhost", player, false)
		lockPlayer(player, true)
		task.spawn(function()
			local okSpawn, result = callService("SpawnService", "Spawn", player, "Hole", standSpot, { reason = "hole" })
			if not (okSpawn and result == true) and player.Character then
				player.Character:PivotTo(standSpot + Vector3.new(0, SPAWN.CharacterLift, 0))
			end
			if not stale() and isPresent(player) then
				setFrozen(player, true)
				callService("BallService", "SpawnBall", player, ballSpot.Position + Vector3.new(0, SPAWN.BallLift, 0), {
					practice = false,
				})
				callService("BallService", "ResetStrokes", player)
			end
			pending -= 1
		end)
	end
	local waitStart = os.clock()
	while pending > 0 and os.clock() - waitStart < DUR.PlacementTimeout do
		task.wait(0.1)
		if stale() then
			return
		end
	end
	local remaining = DUR.LoadingMin - (os.clock() - loadingStartedAt)
	if remaining > 0 then
		task.wait(remaining)
	end
	if stale() then
		return
	end
	proceedToIntro()
end

local onLoadingTimeout: () -> ()

local function startLoadAttempt()
	loadAttempt += 1
	local attempt = loadAttempt
	local token = phaseToken
	GameState.set("PhaseEndsAt", now() + DUR.LoadingMax)
	phaseTrove:Add(task.delay(DUR.LoadingMax, function()
		if phaseToken == token and loadAttempt == attempt and phase == "Loading" then
			onLoadingTimeout()
		end
	end))
	task.spawn(function()
		local ok, err = xpcall(runLoading, debug.traceback, token, attempt)
		if not ok then
			Log.error(LOG_TAG, "chargement du trou :", err)
			if phaseToken == token and phase == "Loading" then
				MatchService.Abort("error")
			end
		end
	end)
end

onLoadingTimeout = function()
	local m = match
	if not m then
		return
	end
	local h = hole
	if h and h.index == m.holeIndex then
		-- Trou construit mais placements trop longs : on lance quand même (les retardataires réapparaîtront).
		Log.warn(LOG_TAG, "placements incomplets : lancement du trou malgré tout")
		proceedToIntro()
		return
	end
	Log.warn(LOG_TAG, "chargement bloqué : trou abandonné", m.playlist[m.holeIndex])
	announceAll("match.loading.skipped")
	m.holeIndex += 1
	if m.holeIndex <= #m.playlist then
		startLoadAttempt()
	elseif m.holesPlayed > 0 then
		enterPodium()
	else
		MatchService.Abort("noHoles")
	end
end

enterLoading = function()
	local m = match
	if not m then
		return
	end
	if not setPhase("Loading", DUR.LoadingMax, nil) then
		return
	end
	loadingStartedAt = os.clock()
	announceAll("match.loading.hole", { index = m.holeIndex, count = #m.playlist })
	startLoadAttempt()
end

enterCountdown = function()
	if phase ~= "HoleIntro" then
		return
	end
	if not setPhase("Countdown", DUR.Countdown, enterPlaying) then
		return
	end
	local steps = math.max(1, math.floor(DUR.Countdown + 0.5))
	for step = 0, steps - 1 do
		phaseTrove:Add(task.delay(step * (DUR.Countdown / steps), function()
			playSound(AUDIO.CountdownBeep, nil)
		end))
	end
end

local function afkStep()
	local m = match
	if not m then
		return
	end
	local time = now()
	-- Un joueur marqué AFK le redevient actif dès qu'il bouge (toute phase de la partie).
	for _, record in presentRecords(m) do
		local player = record.player :: Player
		if player:GetAttribute("AFK") == true then
			local root = rootOf(player)
			local reference = record.afkPos
			if root and reference and flat(root.Position - reference).Magnitude >= AFK.MinMove then
				setAttr(player, "AFK", false)
				record.afkFlag = false
				record.afkPos = nil
			elseif root and not reference then
				record.afkPos = root.Position
			end
		end
	end
	local h = hole
	if not AFK.Enabled or phase ~= "Playing" or not h or h.frozen then
		return
	end
	for _, entry in h.entries do
		local player = entry.record.player
		if entry.status ~= "Playing" or not player or not isPresent(player) then
			continue
		end
		local root = rootOf(player)
		if AFK.IgnoreWhileKnockedOut and isKnockedOut(player) then
			entry.lastActivityAt = time
			entry.activityPos = if root then root.Position else entry.activityPos
			continue
		end
		if root then
			local reference = entry.activityPos
			if reference == nil or flat(root.Position - reference).Magnitude >= AFK.MinMove then
				entry.activityPos = root.Position
				if reference ~= nil then
					entry.lastActivityAt = time
					entry.afkWarned = false
				end
			end
		end
		local limit = if entry.record.afkFlag then AFK.RepeatSeconds else AFK.Seconds
		local idle = time - entry.lastActivityAt
		if idle >= limit then
			entry.record.afkFlag = true
			entry.record.afkPos = if root then root.Position else nil
			setAttr(player, "AFK", true)
			forfeitEntry(entry, "AFK", "afk")
		elseif not entry.afkWarned and idle >= limit - AFK.WarningBefore then
			entry.afkWarned = true
			announceTo(player, "match.announce.afkWarning", { seconds = math.max(1, math.ceil(limit - idle)) })
		end
	end
end

enterPlaying = function()
	local m = match
	local h = hole
	if not m or not h or phase ~= "Countdown" then
		return
	end
	if not setPhase("Playing", DUR.PlayingMax, function()
		endHole("safety")
	end) then
		return
	end
	local token = phaseToken
	local time = now()
	h.startedAt = time
	h.deadline = time + h.timeLimit
	GameState.set("HoleStartedAt", time)
	GameState.set("OvertimeEndsAt", 0)
	GameState.set("PhaseEndsAt", h.deadline)
	for _, entry in h.entries do
		local player = entry.record.player
		entry.lastActivityAt = time
		entry.activityPos = nil
		if player and isPresent(player) then
			setFrozen(player, false)
			lockPlayer(player, false)
			local root = rootOf(player)
			entry.activityPos = if root then root.Position else nil
		end
	end
	callService("BallService", "SetCanShoot", canShoot)
	playSound(AUDIO.CountdownGo, nil)
	MatchService.HoleStarted:Fire(h.runtime)

	-- Échéance du trou (prolongation comprise) et inactivité.
	phaseTrove:Add(task.spawn(function()
		while phaseToken == token do
			task.wait(DUR.DeadlineCheckInterval)
			if phaseToken ~= token then
				break
			end
			if now() >= h.deadline then
				endHole("timeout")
				break
			end
		end
	end))
	phaseTrove:Add(task.spawn(function()
		while phaseToken == token do
			task.wait(AFK.SampleInterval)
			if phaseToken ~= token then
				break
			end
			local ok, err = pcall(afkStep)
			if not ok then
				Log.warn(LOG_TAG, "AFK :", err)
			end
		end
	end))
	scheduleEndCheck()
end

endHole = function(reason: string)
	local m = match
	local h = hole
	if not m or not h or h.frozen or phase ~= "Playing" then
		return
	end
	h.frozen = true
	callService("BallService", "SetCanShoot", refuseShots)
	local timedOut = anyPlaying(h, nil)
	for _, entry in h.entries do
		local player = entry.record.player
		if player and isPresent(player) then
			callService("BallService", "CancelAim", player, "phase")
		end
	end
	local results = computeHoleResults(m, h)
	if not setPhase("HoleEnd", DUR.HoleEnd, enterHoleResults) then
		return
	end
	Log.info(LOG_TAG, "fin du trou", h.def.id, "(" .. reason .. ")")
	if timedOut then
		announceAll("match.announce.timeUp")
		playSound(AUDIO.TimeUp, nil)
	else
		announceAll("match.announce.allFinished")
	end
	if m.mode == "Teams" then
		announceAll(if h.teamWinner == "Red"
			then "match.announce.teamPointRed"
			elseif h.teamWinner == "Blue" then "match.announce.teamPointBlue"
			else "match.announce.teamNoPoint")
	end
	setMusic(AUDIO.MusicMatch)
	-- Plus rien ne peut modifier le score : objets, voiturettes et balles retirés.
	cleanupRound(false)

	-- Résultats non terminés (finished = false) pour les écouteurs (récompenses, défis).
	for _, userId in h.order do
		local entry = h.entries[userId]
		local player = entry and entry.record.player
		if entry and entry.status ~= "Finished" and player and isPresent(player) then
			MatchService.PlayerFinishedHole:Fire(player, {
				finished = false,
				strokes = entry.strokes,
				par = h.par,
				finishOrder = nil,
				time = nil,
				status = entry.status,
				reason = entry.reason,
				points = 0,
				bonuses = {},
				holeId = h.def.id,
				roundId = roundId,
			})
		end
	end
	MatchService.HoleEnded:Fire(results)

	if m.mode == "Solo" then
		for _, entry in h.entries do
			local player = entry.record.player
			if entry.status == "Finished" and player and isPresent(player) then
				task.spawn(saveSoloRecord, player, h.def.id, entry.strokes, entry.finishTime or h.timeLimit)
			end
		end
	end
end

enterHoleResults = function()
	local m = match
	local h = hole
	if not m or not h or phase ~= "HoleEnd" then
		return
	end
	if not setPhase("HoleResults", DUR.HoleResults, afterResults) then
		return
	end
	local payload = {
		holeId = h.def.id,
		holeName = h.def.name,
		biome = h.def.biome,
		par = h.par,
		index = h.index,
		count = #m.playlist,
		mode = m.mode,
		results = h.results or {},
		teamScores = { Red = m.teamScores.Red, Blue = m.teamScores.Blue },
		teamWinner = h.teamWinner,
		standings = standingsPayload(m),
		cap = h.cap,
		timeLimit = h.timeLimit,
	}
	m.lastHoleResults = payload
	Net.fireAll("Match.HoleResults", payload)
	if MatchStateMachine.nextAfterResults(h.index, #m.playlist) == "Loading" then
		announceAll("match.announce.nextHole", { seconds = math.ceil(DUR.HoleResults) })
	else
		announceAll("match.announce.matchEnd")
	end
end

afterResults = function()
	local m = match
	if not m or phase ~= "HoleResults" then
		return
	end
	-- Les personnages restent immobiles pendant le démontage du trou (aucune chute dans le vide).
	for _, player in participantPlayers(m) do
		lockPlayer(player, true)
		setFrozen(player, true)
	end
	local lastIndex = m.holeIndex
	cleanupRound(true)
	if MatchStateMachine.nextAfterResults(lastIndex, #m.playlist) == "Loading" then
		m.holeIndex = lastIndex + 1
		enterLoading()
	else
		enterPodium()
	end
end

--------------------------------------------------------------------------------
-- Podium et fin de partie
--------------------------------------------------------------------------------

local function buildSummary(m: MatchState): ({ [string]: any }, { [string]: any })
	local rows = standingsRows(m)
	local winner: string? = nil
	if m.mode == "Teams" then
		winner = Scoring.teamMatchResult(m.teamScores.Red, m.teamScores.Blue)
	end
	local standings = {}
	local playersInfo = {}
	local netPlayers = {}
	for _, row in rows do
		local record = m.records[row.userId]
		table.insert(standings, {
			userId = row.userId,
			name = row.name,
			team = row.team,
			points = row.points,
			strokes = row.totalStrokes,
			holeWins = row.holeWins,
			rank = row.rank,
		})
		if record then
			local teamResult = if winner ~= nil
				then Scoring.teamResultFor(record.team, winner :: any)
				else nil
			local soloSummary = Scoring.soloSummary(record.soloHoles)
			local info = {
				userId = record.userId,
				name = record.name,
				team = record.team,
				mode = m.mode,
				rank = row.rank,
				participants = #rows,
				holeCount = m.holesPlayed,
				activeHoles = record.activeHoles,
				holesFinished = record.holesFinished,
				parOrBetter = record.parOrBetter,
				holeInOnes = record.holeInOnes,
				eagles = record.eagles,
				birdies = record.birdies,
				teamResult = teamResult,
				solo = {
					strokes = soloSummary.strokes,
					par = soloSummary.par,
					toPar = soloSummary.toPar,
					toParText = Scoring.signed(soloSummary.toPar),
					time = soloSummary.time,
					holesFinished = soloSummary.holesFinished,
				},
			}
			table.insert(netPlayers, info)
			local withPlayer = table.clone(info) :: { [string]: any }
			withPlayer.player = record.player
			table.insert(playersInfo, withPlayer)
		end
	end
	local base = {
		matchId = m.id,
		mode = m.mode,
		standings = standings,
		teamScores = { Red = m.teamScores.Red, Blue = m.teamScores.Blue },
		winner = winner,
		winnerUserId = if m.mode ~= "Teams" and rows[1] then rows[1].userId else 0,
		holeCount = m.holesPlayed,
		completed = true,
	}
	local summary = table.clone(base) :: { [string]: any }
	summary.players = playersInfo
	local payload = table.clone(base) :: { [string]: any }
	payload.players = netPlayers
	return summary, payload
end

-- Places du podium : les trois premiers (en mode Équipes, l'équipe gagnante d'abord).
local function podiumOrder(m: MatchState, standings: { { [string]: any } }, winner: string?): { Player }
	local ordered: { { [string]: any } } = {}
	if m.mode == "Teams" and (winner == "Red" or winner == "Blue") then
		for _, row in standings do
			if row.team == winner then
				table.insert(ordered, row)
			end
		end
		for _, row in standings do
			if row.team ~= winner then
				table.insert(ordered, row)
			end
		end
	else
		ordered = standings
	end
	local result: { Player } = {}
	for _, row in ordered do
		local record = m.records[row.userId]
		local player = record and record.player
		if player and isPresent(player) then
			table.insert(result, player)
		end
	end
	return result
end

local function placeOnPodium(m: MatchState, order: { Player })
	local okLobby, lobby = callService("CourseService", "GetLobby")
	local kiosks = if okLobby and type(lobby) == "table" and type(lobby.kiosks) == "table" then lobby.kiosks else {}
	local placed: { [Player]: boolean } = {}
	for index, slot in ConfigMatch.Podium.Slots do
		local player = order[index]
		local cframe = kiosks[slot]
		if player and Validate.isFiniteCFrame(cframe) then
			placed[player] = true
			task.spawn(function()
				setFrozen(player, false)
				callService("SpawnService", "Spawn", player, "Lobby", cframe, { reason = "podium", protection = 0 })
				lockPlayer(player, true)
			end)
			for burst = 0, ConfigMatch.Podium.EffectRepeat - 1 do
				phaseTrove:Add(task.delay(burst * ConfigMatch.Podium.EffectInterval, function()
					Net.fireAll("Effects.Play", ConfigMatch.Podium.Effect, { position = (cframe :: CFrame).Position + Vector3.new(0, 4, 0) })
				end))
			end
		end
	end
	-- Tous les autres joueurs de la partie retournent à l'accueil.
	for _, player in participantPlayers(m) do
		if not placed[player] then
			task.spawn(function()
				setFrozen(player, false)
				callService("SpawnService", "Spawn", player, "Lobby", nil, { reason = "podium" })
				lockPlayer(player, false)
			end)
		end
	end
end

enterPodium = function()
	local m = match
	if not m then
		return
	end
	if not setPhase("Podium", DUR.Podium, function()
		enterLobby(false)
	end) then
		return
	end
	m.completed = true
	cleanupRound(true)
	callService("CourseService", "ApplyBiomeLighting", "Lobby")
	callService("BallService", "SetWind", Vector3.zero)
	resetHoleGameState()
	GameState.set("HoleCount", #m.playlist)
	setMusic(AUDIO.MusicPodium)

	local summary, payload = buildSummary(m)
	m.podium = payload
	Net.fireAll("Match.Podium", payload)
	placeOnPodium(m, podiumOrder(m, payload.standings, payload.winner))
	playSound(AUDIO.Finish, nil)

	local winner = payload.winner
	if m.mode == "Teams" then
		announceAll(if winner == "Red"
			then "match.announce.winnerRed"
			elseif winner == "Blue" then "match.announce.winnerBlue"
			else "match.announce.draw")
	elseif m.mode ~= "Solo" and payload.standings[1] then
		announceAll("match.announce.winner", { name = payload.standings[1].name })
	else
		announceAll("match.announce.matchEnd")
	end
	announceAll("match.announce.returnLobby", { seconds = math.ceil(DUR.Podium) })

	-- Récompenses et défis : jamais pour une partie d'entraînement.
	if m.mode ~= "Training" then
		MatchService.MatchEnded:Fire(summary)
	end
end

local function teardownMatch()
	local m = match
	match = nil
	if hole then
		cleanupRound(true)
	end
	unfreezeAll()
	callService("BallService", "SetCanShoot", nil)
	callService("BallService", "SetBallCollisions", false)
	callService("BallService", "SetWind", Vector3.zero)
	callService("BallService", "SetCup", nil, nil)
	for _, player in Players:GetPlayers() do
		lockPlayer(player, false)
		callService("CollisionService", "SetGhost", player, false)
		resetMatchAttributes(player, prefersSpectating(player))
		player.Neutral = true
		player.Team = nil
	end
	if m then
		m.trove:Clean()
	end
end

enterLobby = function(returnPlayers: boolean)
	if phase == "Lobby" then
		return
	end
	if not setPhase("Lobby", nil, nil) then
		return
	end
	teardownMatch()
	publishLobbyState()
	callService("CourseService", "ApplyBiomeLighting", "Lobby")
	setMusic(AUDIO.MusicLobby)
	if returnPlayers then
		for _, player in Players:GetPlayers() do
			task.spawn(function()
				callService("SpawnService", "Spawn", player, "Lobby", nil, { reason = "lobby" })
			end)
		end
	end
end

local function enterPreparing(): boolean
	if phase ~= "Lobby" then
		return false
	end
	return setPhase("Preparing", ConfigMatch.Durations.PreparingMax, function()
		announceAll("match.announce.preparingExpired")
		enterLobby(false)
	end)
end

--------------------------------------------------------------------------------
-- Lancement d'une partie
--------------------------------------------------------------------------------

-- Copie figée des réglages (bornes revérifiées, tir ami toujours désactivé en mode Équipes).
local function freezeSettings(requested: any): MatchSettings
	local base = cloneSettings(ConfigMatch.DefaultSettings)
	local target = base :: any
	if type(requested) == "table" then
		for key, value in requested do
			if type(key) == "string" and ConfigMatch.SettingRules[key] ~= nil then
				target[key] = value
			end
		end
		if type(requested.customHoleIds) == "table" then
			base.customHoleIds = table.clone(requested.customHoleIds)
		end
		if type(requested.biomes) == "table" then
			base.biomes = table.clone(requested.biomes)
		end
	end
	local rules = ConfigMatch.SettingRules
	local modeRule = rules.mode
	if not (modeRule.values and table.find(modeRule.values, base.mode)) then
		base.mode = ConfigMatch.DefaultSettings.mode
	end
	base.timeScale = Validate.clampNumber(base.timeScale, rules.timeScale.min or 0.5, rules.timeScale.max or 2, 1)
	base.gameSpeed = Validate.clampNumber(base.gameSpeed, rules.gameSpeed.min or 0.75, rules.gameSpeed.max or 1.5, 1)
	base.holeCount = math.floor(Validate.clampNumber(base.holeCount, 1, ConfigMatch.Playlists.MaxHoles, 3))
	local windRule = rules.wind
	if not (windRule.values and table.find(windRule.values, base.wind)) then
		base.wind = ConfigMatch.DefaultSettings.wind
	end
	if base.mode == "Teams" then
		base.friendlyFire = false
	end
	base.ballCollisions = base.ballCollisions == true
	base.lateJoin = base.lateJoin == true
	base.experimental16 = base.experimental16 == true
	base.itemsEnabled = base.itemsEnabled ~= false
	base.shuffle = base.shuffle == true
	return base
end

local function startMatch(requested: any, forcedParticipants: { Player }?): (boolean, string?)
	if phase ~= "Preparing" then
		return false, "phase"
	end
	local settings = freezeSettings(requested)
	local candidates: { Player } = {}
	if forcedParticipants then
		candidates = forcedParticipants
	else
		local ok, list = callService("LobbyService", "GetParticipants")
		if ok and type(list) == "table" then
			candidates = list
		end
	end
	local participants: { Player } = {}
	for _, player in candidates do
		if isPlayer(player) and isPresent(player) and not table.find(participants, player) then
			table.insert(participants, player)
		end
	end
	if settings.mode == "Solo" and #participants > 1 then
		local okHost, host = callService("LobbyService", "GetHost")
		local chosen = if okHost and isPlayer(host) and table.find(participants, host) then host :: Player else participants[1]
		participants = { chosen }
	end
	local limit = if settings.experimental16 then ConfigMatch.MaxParticipantsExperimental else ConfigMatch.MaxParticipants
	while #participants > limit do
		table.remove(participants)
	end
	if #participants < ConfigMatch.MinParticipants then
		local okHost, host = callService("LobbyService", "GetHost")
		if okHost and isPlayer(host) then
			notify(host :: Player, "lobby.error.noParticipants", { min = ConfigMatch.MinParticipants })
		end
		return false, "noParticipants"
	end

	local playlist = Playlist.build(settings, courseHoles(), rng:NextInteger(1, 2 ^ 30))
	if #playlist.holeIds == 0 then
		announceAll("match.abort.noHoles")
		enterLobby(false)
		return false, "noHoles"
	end

	local m: MatchState = {
		id = HttpService:GenerateGUID(false),
		settings = settings,
		mode = settings.mode,
		playlist = playlist.holeIds,
		holeIndex = 1,
		holesPlayed = 0,
		holeCaps = {},
		records = {},
		order = {},
		pendingLate = {},
		teamScores = { Red = 0, Blue = 0 },
		teamInstances = {},
		trove = TroveModule.new(),
		lastHoleResults = nil,
		podium = nil,
		completed = false,
	}
	match = m

	-- Participants, équipes, spectateurs.
	local teamsList: { Team }? = nil
	if m.mode == "Teams" then
		ensureTeamInstances(m)
		local choices: { string } = {}
		for index, player in participants do
			local ok, choice = callService("LobbyService", "GetTeamChoice", player)
			choices[index] = if ok and type(choice) == "string" then choice else "Auto"
		end
		teamsList = Scoring.assignTeams(choices)
	end
	for index, player in participants do
		local record = newRecord(player, 1)
		if teamsList then
			record.team = teamsList[index]
		end
		m.records[player.UserId] = record
		table.insert(m.order, player.UserId)
		resetMatchAttributes(player, false)
		admitRecord(m, record)
		if record.team then
			notify(player, if record.team == "Red" then "match.team.yoursRed" else "match.team.yoursBlue")
		end
	end
	for _, player in Players:GetPlayers() do
		if not m.records[player.UserId] then
			resetMatchAttributes(player, true)
			callService("CollisionService", "SetGhost", player, true)
			notify(player, "match.lateJoin.nextMatch")
		end
	end

	GameState.set("MatchId", m.id)
	GameState.set("Mode", m.mode)
	GameState.set("SettingsJson", encodeSettings(settings))
	GameState.set("HoleCount", #m.playlist)
	GameState.set("HoleIndex", 0)
	GameState.set("TeamScoreRed", 0)
	GameState.set("TeamScoreBlue", 0)
	callService("BallService", "SetBallCollisions", settings.ballCollisions)

	Log.info(LOG_TAG, "partie", m.id, m.mode, #participants, "participant(s),", #m.playlist, "trou(s)")
	announceAll("match.announce.matchStart", { count = #m.playlist })
	if playlist.fallback == "fewerHoles" then
		announceAll("match.announce.playlistShort", { count = #m.playlist })
	end
	enterLoading()
	return true, nil
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

function MatchService.GetPhase(): Phase
	return phase
end

function MatchService.GetRoundId(): number
	return roundId
end

function MatchService.GetMatchId(): string
	local m = match
	return if m then m.id else ""
end

function MatchService.GetHoleRuntime(): Types.HoleRuntime?
	local h = hole
	return if h then h.runtime else nil
end

function MatchService.IsParticipant(player: Player): boolean
	local m = match
	if not m or not isPlayer(player) then
		return false
	end
	local record = m.records[player.UserId]
	return record ~= nil and record.present and record.player == player
end

-- Participant en jeu sur le trou courant, non terminé (du chargement jusqu'à la fin de "Playing").
function MatchService.IsActive(player: Player): boolean
	local h = hole
	if not h or h.frozen or not isPlayer(player) then
		return false
	end
	if phase ~= "Loading" and phase ~= "HoleIntro" and phase ~= "Countdown" and phase ~= "Playing" then
		return false
	end
	local entry = h.entries[player.UserId]
	return entry ~= nil and entry.status == "Playing" and entry.record.player == player
end

function MatchService.GetTeam(player: Player): Team?
	local m = match
	if not m or not isPlayer(player) then
		return nil
	end
	local record = m.records[player.UserId]
	return record and record.team
end

function MatchService.AreAllies(a: Player, b: Player): boolean
	local m = match
	if not m or m.mode ~= "Teams" or a == b then
		return false
	end
	local teamA = MatchService.GetTeam(a)
	return teamA ~= nil and teamA == MatchService.GetTeam(b)
end

function MatchService.GetSettings(): MatchSettings
	local m = match
	if m then
		return cloneSettings(m.settings)
	end
	return lobbySettings()
end

-- Classement de course : arrivés (rang, temps), puis joueurs en jeu (distance de la balle au trou),
-- puis non-arrivés. Retourne (rang, total) ; (0, 0) hors trou.
function MatchService.GetRacePosition(player: Player): (number, number)
	local h = hole
	if not h or not isPlayer(player) then
		return 0, 0
	end
	local cup = h.runtime.cupPosition
	type Row = { userId: number, group: number, key: number, key2: number }
	local rows: { Row } = {}
	for userId, entry in h.entries do
		local row: Row = { userId = userId, group = 3, key = math.huge, key2 = 0 }
		if entry.status == "Finished" then
			row.group = 1
			row.key = entry.finishOrder or math.huge
			row.key2 = entry.finishTime or math.huge
		elseif entry.status == "Playing" then
			row.group = 2
			local member = entry.record.player
			local position: Vector3? = nil
			if member then
				local okBall, ball = callService("BallService", "GetBall", member)
				if okBall and typeof(ball) == "Instance" and (ball :: Instance):IsA("BasePart") then
					position = (ball :: BasePart).Position
				else
					local root = rootOf(member)
					position = root and root.Position
				end
			end
			row.key = if position then flat(position - cup).Magnitude else math.huge
		else
			row.key = entry.strokes
		end
		table.insert(rows, row)
	end
	table.sort(rows, function(a: Row, b: Row): boolean
		if a.group ~= b.group then
			return a.group < b.group
		end
		if a.key ~= b.key then
			return a.key < b.key
		end
		if a.key2 ~= b.key2 then
			return a.key2 < b.key2
		end
		return a.userId < b.userId
	end)
	for index, row in rows do
		if row.userId == player.UserId then
			return index, #rows
		end
	end
	return 0, #rows
end

-- Interrompt la partie (sans récompense) et ramène tout le monde à l'accueil.
function MatchService.Abort(reason: string?)
	if phase == "Lobby" then
		return
	end
	local why = if type(reason) == "string" and reason ~= "" then reason else "error"
	Log.warn(LOG_TAG, "partie interrompue :", why)
	if phase == "Preparing" then
		enterLobby(false)
		return
	end
	local key = "match.abort." .. why
	announceAll(if Locale.has(key, "fr") then key else "match.announce.aborted")
	enterLobby(true)
end

--------------------------------------------------------------------------------
-- Joueurs : arrivées tardives, départs, spectateurs, AFK
--------------------------------------------------------------------------------

local function offerLateJoin(player: Player)
	local m = match
	if not m then
		return
	end
	if m.records[player.UserId] and m.records[player.UserId].present and m.records[player.UserId].player == player then
		return
	end
	local allowedInMode = (m.mode ~= "Solo" or ConfigMatch.LateJoin.AllowInSolo)
		and (m.mode ~= "Training" or ConfigMatch.LateJoin.AllowInTraining)
	if prefersSpectating(player) then
		m.pendingLate[player] = nil
		notify(player, "match.lateJoin.nextMatch")
		return
	end
	if not m.settings.lateJoin or not allowedInMode or phase == "Podium" then
		notify(player, "match.lateJoin.nextMatch")
		return
	end
	if m.pendingLate[player] then
		notify(player, "match.lateJoin.nextHole")
		return
	end
	if #presentRecords(m) + countPending(m) >= maxParticipants(m) then
		notify(player, "match.lateJoin.full")
		return
	end
	m.pendingLate[player] = true
	notify(player, "match.lateJoin.nextHole")
	announceExcept(player, "match.announce.lateJoin", { name = displayName(player) })
end

local function onPlayerAdded(player: Player)
	resetMatchAttributes(player, prefersSpectating(player) or match ~= nil)
	if match then
		callService("CollisionService", "SetGhost", player, true)
		offerLateJoin(player)
	end
end

local function onPlayerRemoving(player: Player)
	frozenRoots[player] = nil
	local m = match
	if m then
		m.pendingLate[player] = nil
		local record = m.records[player.UserId]
		if record and record.present and record.player == player then
			record.present = false
			record.player = nil
			local h = hole
			local entry = h and h.entries[player.UserId]
			if entry and entry.status == "Playing" and h and not h.frozen then
				entry.status = "Disconnected"
				entry.reason = "disconnected"
			end
			announceAll("match.announce.disconnected", { name = record.name })
		end
		task.defer(function()
			local current = match
			if current ~= m or phase == "Lobby" or phase == "Preparing" then
				return
			end
			if #presentRecords(m) == 0 then
				MatchService.Abort("noParticipants")
			else
				scheduleEndCheck()
			end
		end)
	elseif phase == "Preparing" then
		task.defer(function()
			if phase == "Preparing" and #Players:GetPlayers() == 0 then
				enterLobby(false)
			end
		end)
	end
end

local function onForfeit(player: Player, requestRound: number)
	if phase ~= "Playing" then
		notify(player, "match.error.phase")
		return
	end
	if requestRound ~= roundId then
		notify(player, "match.error.staleRound")
		return
	end
	local h = hole
	local entry = h and h.entries[player.UserId]
	if not entry or entry.record.player ~= player then
		notify(player, "match.error.notParticipant")
		return
	end
	if entry.status ~= "Playing" then
		notify(player, "match.error.finished")
		return
	end
	forfeitEntry(entry, "Forfeit", "voluntary")
end

local function onSetSpectator(player: Player, value: boolean)
	callService("LobbyService", "SetSpectatorPreference", player, value)
	notify(player, if value then "match.spectator.on" else "match.spectator.off")
	local m = match
	if not m then
		setAttr(player, "Spectating", value)
		return
	end
	if not MatchService.IsParticipant(player) then
		if value then
			m.pendingLate[player] = nil
		else
			offerLateJoin(player)
		end
	end
end

local function onHeartbeat(player: Player, requestRound: number)
	if phase ~= "Playing" or requestRound ~= roundId then
		return
	end
	local h = hole
	local entry = h and h.entries[player.UserId]
	if not entry or entry.status ~= "Playing" or entry.record.player ~= player then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	local position = root.Position
	local look = horizontalLook(root.CFrame)
	local previousPos, previousLook = entry.heartbeatPos, entry.heartbeatLook
	entry.heartbeatPos = position
	entry.heartbeatLook = look
	if not previousPos or not previousLook then
		return
	end
	local moved = flat(position - previousPos).Magnitude >= AFK.HeartbeatMinMove
	local angle = math.deg(math.acos(math.clamp(look:Dot(previousLook), -1, 1)))
	if moved or angle >= AFK.HeartbeatMinTurnDeg then
		entry.lastActivityAt = now()
		entry.afkWarned = false
	end
end

local function onClientReady(player: Player)
	if currentMusic ~= "" then
		Net.fire("Effects.Music", player, currentMusic)
	end
	local m = match
	if not m then
		return
	end
	if not MatchService.IsParticipant(player) then
		if m.pendingLate[player] then
			notify(player, "match.lateJoin.nextHole")
		else
			offerLateJoin(player)
		end
	end
	if phase == "HoleResults" and m.lastHoleResults then
		Net.fire("Match.HoleResults", player, m.lastHoleResults)
	elseif phase == "Podium" and m.podium then
		Net.fire("Match.Podium", player, m.podium)
	end
end

-- Résolveur d'apparition (SpawnService) : départ du trou avant "Playing", point de contrôle ensuite ;
-- nil (accueil) pour les non-participants et hors trou.
local function spawnResolver(player: Player): CFrame?
	local m = match
	local h = hole
	if not m or not h or not MatchStateMachine.isHolePhase(phase) then
		return nil
	end
	local entry = h.entries[player.UserId]
	if not entry or entry.record.player ~= player then
		return nil
	end
	if phase == "Loading" or phase == "HoleIntro" or phase == "Countdown" then
		return entry.startCFrame
	end
	local okSafe, safe = callService("SpawnService", "GetLastSafePosition", player)
	local reference: Vector3? = if okSafe and Validate.isFiniteVector3(safe) then safe else nil
	if not reference then
		local okBall, ball = callService("BallService", "GetBall", player)
		if okBall and typeof(ball) == "Instance" and (ball :: Instance):IsA("BasePart") then
			reference = (ball :: BasePart).Position
		end
	end
	if reference then
		local ok, checkpoint = callService("CourseService", "GetCheckpointFor", reference)
		if ok and Validate.isFiniteCFrame(checkpoint) then
			return checkpoint
		end
	end
	return entry.startCFrame
end

--------------------------------------------------------------------------------
-- Outils de test (Studio uniquement)
--------------------------------------------------------------------------------

if RunService:IsStudio() then
	local Dev = {}

	-- Lance une partie depuis l'accueil ou la préparation (défaut : Chacun pour soi, 2 trous existants).
	function Dev.ForceStart(settings: any?): (boolean, string?)
		if phase ~= "Lobby" and phase ~= "Preparing" then
			return false, "phase:" .. phase
		end
		local requested: { [string]: any } = cloneSettings(ConfigMatch.DefaultSettings) :: any
		requested.mode = "FreeForAll"
		if type(settings) == "table" then
			for key, value in settings do
				requested[key] = value
			end
		else
			local sorted = Playlist.sortCourse(Playlist.dedupeHoles(courseHoles()))
			local ids: { string } = {}
			for index = 1, math.min(2, #sorted) do
				table.insert(ids, sorted[index].id)
			end
			if #ids > 0 then
				requested.playlist = "Custom"
				requested.customHoleIds = ids
				requested.holeCount = #ids
			end
		end
		local participants: { Player } = {}
		local ok, list = callService("LobbyService", "GetParticipants")
		if ok and type(list) == "table" and #list > 0 then
			participants = list
		else
			participants = Players:GetPlayers()
		end
		if phase == "Lobby" and not enterPreparing() then
			return false, "prepare"
		end
		return startMatch(requested, participants)
	end

	-- Avance immédiatement à la phase suivante. Retourne la phase atteinte.
	function Dev.SkipPhase(): string
		if phase == "Lobby" then
			enterPreparing()
		elseif phase == "Preparing" then
			Dev.ForceStart(nil)
		elseif phase == "HoleIntro" then
			enterCountdown()
		elseif phase == "Countdown" then
			enterPlaying()
		elseif phase == "Playing" then
			endHole("skip")
		elseif phase == "HoleEnd" then
			enterHoleResults()
		elseif phase == "HoleResults" then
			afterResults()
		elseif phase == "Podium" then
			enterLobby(false)
		end
		return phase
	end

	-- Trou réussi à « coups actuels + 1 », par le même chemin que BallService.Holed.
	function Dev.FinishPlayer(player: Player): boolean
		local entry = playingEntry(player)
		if not entry then
			return false
		end
		local strokes = ballStrokes(player) + 1
		onHoled(player, {
			strokes = strokes,
			shotDistance = 0,
			fromDistance = 0,
			wasPutt = true,
			holeInOne = strokes == 1,
			shotType = "Putt",
			gimme = false,
			external = false,
			practice = false,
		})
		return entry.status == "Finished"
	end

	function Dev.GetDebugState(): { [string]: any }
		local m = match
		local h = hole
		local participants = {}
		if m then
			for _, userId in m.order do
				local record = m.records[userId]
				local entry = h and h.entries[userId]
				table.insert(participants, {
					userId = userId,
					name = record.name,
					present = record.present,
					team = record.team,
					points = record.points,
					totalStrokes = record.totalStrokes,
					status = if entry then entry.status else "",
					strokes = if entry then entry.strokes else 0,
					finishOrder = if entry then entry.finishOrder else nil,
				})
			end
		end
		return {
			phase = phase,
			phaseEndsAt = GameState.read("PhaseEndsAt"),
			now = now(),
			roundId = roundId,
			matchId = if m then m.id else "",
			mode = if m then m.mode else "",
			holeIndex = if m then m.holeIndex else 0,
			holeCount = if m then #m.playlist else 0,
			playlist = if m then table.clone(m.playlist) else {},
			holeId = if h then h.def.id else "",
			deadline = if h then h.deadline else 0,
			overtime = if h then h.overtimeTriggered else false,
			cap = if h then h.cap else 0,
			teamScores = if m then { Red = m.teamScores.Red, Blue = m.teamScores.Blue } else nil,
			participants = participants,
		}
	end

	MatchService.Dev = Dev
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function MatchService.Init()
	initGameState()

	connectSignal("LobbyService", "PrepareRequested", function()
		if phase == "Lobby" then
			enterPreparing()
		end
	end)
	connectSignal("LobbyService", "CancelRequested", function()
		if phase == "Preparing" then
			Net.fireAll("Core.NotifyKey", "lobby.cancelled")
			enterLobby(false)
		end
	end)
	connectSignal("LobbyService", "StartRequested", function(settings: any)
		if phase == "Preparing" then
			startMatch(settings, nil)
		end
	end)
	connectSignal("LobbyService", "HostChanged", function(newHost: any)
		GameState.set("HostUserId", if isPlayer(newHost) then (newHost :: Player).UserId else 0)
	end)
	connectSignal("LobbyService", "SettingsChanged", function(settings: any)
		if match == nil and type(settings) == "table" then
			GameState.set("SettingsJson", encodeSettings(settings))
			if type(settings.mode) == "string" then
				GameState.set("Mode", settings.mode)
			end
		end
	end)
	connectSignal("LobbyService", "SpectatorChanged", function(player: any, value: any)
		if match == nil and isPlayer(player) then
			setAttr(player, "Spectating", value == true)
		end
	end)
	connectSignal("LobbyService", "ClientReady", onClientReady)

	connectSignal("BallService", "Shot", onShot)
	connectSignal("BallService", "Holed", onHoled)
	connectSignal("BallService", "Rested", onRested)
	connectSignal("BallService", "Respawned", onRespawned)

	callService("SpawnService", "SetSpawnResolver", spawnResolver)

	Net.on("Match.Forfeit", onForfeit)
	Net.on("Match.SetSpectator", onSetSpectator)
	Net.on("Match.Heartbeat", onHeartbeat)

	RunService.PreSimulation:Connect(function()
		frameCounter += 1
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

function MatchService.Start()
	callService("CourseService", "ApplyBiomeLighting", "Lobby")
	setMusic(AUDIO.MusicLobby)
end

return MatchService
