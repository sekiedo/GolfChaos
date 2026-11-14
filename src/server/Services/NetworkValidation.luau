--!strict
--[[
	NetworkValidation — statistiques et garde-fous réseau communs (docs/ARCHITECTURE.md §5, priorité 8).

	Les rejets « techniques » (types, cadence, direction) sont déjà comptés par Net (Net.getStats()).
	Ce service compte les rejets MÉTIER signalés par les autres services (requête d'une ancienne manche,
	frappe trop rapide, déplacement implausible, cible hors de portée...) :

	  NetworkValidation.Report(player, reason, details?)   -- compte (joueur, motif) ; details = contexte court
	  NetworkValidation.GetReport() -> Report              -- fusionne nos compteurs et Net.getStats()
	  NetworkValidation.GetPlayerReport(player) -> PlayerReport?
	  NetworkValidation.Reset()
	  NetworkValidation.Reported : Signal(player, reason, count)   -- pour un outil d'analyse (DevService...)

	Garde-fous communs (utilisables par tous les services qui reçoivent des intentions) :
	  NetworkValidation.CurrentRoundId() -> number
	  NetworkValidation.CheckRound(player, roundId, allowZero?) -> boolean      -- signale "stale_round"
	  NetworkValidation.CheckCooldown(player, key, seconds) -> boolean           -- true = autorisé (horodaté)
	  NetworkValidation.GetAliveCharacter(player) -> (Model?, Humanoid?, BasePart?)
	  NetworkValidation.CheckDistance(player, position, maxDistance, reason?) -> boolean

	JAMAIS d'exclusion automatique : ces compteurs servent au diagnostic et à la détection d'abus
	(un exploiteur et un joueur à forte latence peuvent produire les mêmes symptômes).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.Gameplay)
local GameState = require(Shared.Util.GameState)
local Log = require(Shared.Util.Log)
local Net = require(Shared.Net)
local SignalModule = require(Shared.Util.Signal)
local Validate = require(Shared.Util.Validate)

type Signal = SignalModule.Signal

export type ReasonStats = {
	count: number,
	firstAt: number,
	lastAt: number,
	samples: { string },
}

export type PlayerReport = {
	userId: number,
	name: string,
	total: number,
	left: boolean,
	reasons: { [string]: ReasonStats },
}

export type NetTotals = {
	accepted: number,
	rejectedRate: number,
	rejectedArgs: number,
	rejectedDir: number,
	errors: number,
}

export type Report = {
	generatedAt: number,
	totals: { [string]: number },
	players: { [string]: PlayerReport }, -- clé = UserId en texte (table sérialisable en JSON)
	net: { [string]: any },
	netTotals: NetTotals,
}

local NetworkValidation = {}
NetworkValidation.Priority = 8

NetworkValidation.Reported = SignalModule.new() :: Signal

local CONFIG = Config.NetworkValidation
local MAX_REASON_LENGTH = 48

local records: { [number]: PlayerReport } = {}
local totals: { [string]: number } = {}
local departed: { number } = {} -- UserId des joueurs partis, du plus ancien au plus récent
local cooldowns: { [Player]: { [string]: number } } = {}
local initialized = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function sanitizeReason(reason: any): string
	if type(reason) ~= "string" or reason == "" then
		return "unknown"
	end
	if #reason > MAX_REASON_LENGTH then
		return string.sub(reason, 1, MAX_REASON_LENGTH)
	end
	return reason
end

local function describeValue(value: any): string
	local kind = typeof(value)
	if kind == "Vector3" then
		return string.format("(%.1f, %.1f, %.1f)", value.X, value.Y, value.Z)
	elseif kind == "number" then
		if value ~= value then
			return "NaN"
		end
		return string.format("%.3g", value)
	elseif kind == "Instance" then
		return value.Name
	end
	return tostring(value)
end

-- Texte court et borné décrivant le contexte d'un rapport (jamais de structure profonde).
local function describe(details: any): string
	local text: string
	if type(details) == "table" then
		local parts = {}
		local count = 0
		for key, value in details do
			count += 1
			if count > 8 then
				table.insert(parts, "…")
				break
			end
			table.insert(parts, tostring(key) .. "=" .. describeValue(value))
		end
		table.sort(parts)
		text = table.concat(parts, " ")
	else
		text = describeValue(details)
	end
	if #text > CONFIG.MaxSampleLength then
		text = string.sub(text, 1, CONFIG.MaxSampleLength) .. "…"
	end
	return text
end

local function getRecord(player: Player): PlayerReport
	local record = records[player.UserId]
	if not record then
		record = {
			userId = player.UserId,
			name = player.Name,
			total = 0,
			left = false,
			reasons = {},
		}
		records[player.UserId] = record
	end
	return record
end

local function trimDeparted()
	while #departed > CONFIG.MaxDeparted do
		local oldest = table.remove(departed, 1)
		if oldest ~= nil then
			local record = records[oldest]
			-- Un joueur revenu entre-temps n'est plus « parti » : on garde sa fiche.
			if record and record.left then
				records[oldest] = nil
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Rapports
--------------------------------------------------------------------------------

function NetworkValidation.Report(player: Player, reason: string, details: any?)
	if not isPlayer(player) then
		return
	end
	local key = sanitizeReason(reason)
	local time = now()
	local record = getRecord(player)
	local stats = record.reasons[key]
	if not stats then
		stats = { count = 0, firstAt = time, lastAt = time, samples = {} }
		record.reasons[key] = stats
	end
	stats.count += 1
	stats.lastAt = time
	record.total += 1
	totals[key] = (totals[key] or 0) + 1

	local sample = if details ~= nil then describe(details) else nil
	if sample then
		table.insert(stats.samples, sample)
		while #stats.samples > CONFIG.MaxSamples do
			table.remove(stats.samples, 1)
		end
	end

	Log.debug("NetVal", player.Name, key, sample or "")
	if stats.count == CONFIG.WarnThreshold or (stats.count > CONFIG.WarnThreshold and stats.count % CONFIG.WarnEvery == 0) then
		Log.warn("NetVal", string.format("%s : %d rejets « %s » (dernier : %s)", player.Name, stats.count, key, sample or "-"))
	end
	NetworkValidation.Reported:Fire(player, key, stats.count)
end

local function copyReasons(reasons: { [string]: ReasonStats }): { [string]: ReasonStats }
	local copy = {}
	for key, stats in reasons do
		copy[key] = {
			count = stats.count,
			firstAt = stats.firstAt,
			lastAt = stats.lastAt,
			samples = table.clone(stats.samples),
		}
	end
	return copy
end

local function copyRecord(record: PlayerReport): PlayerReport
	return {
		userId = record.userId,
		name = record.name,
		total = record.total,
		left = record.left,
		reasons = copyReasons(record.reasons),
	}
end

function NetworkValidation.GetPlayerReport(player: Player): PlayerReport?
	if not isPlayer(player) then
		return nil
	end
	local record = records[player.UserId]
	return if record then copyRecord(record) else nil
end

function NetworkValidation.GetReport(): Report
	local netStats: { [string]: any } = {}
	local netTotals: NetTotals = { accepted = 0, rejectedRate = 0, rejectedArgs = 0, rejectedDir = 0, errors = 0 }
	local getStats = (Net :: any).getStats
	if type(getStats) == "function" then
		local ok, result = pcall(getStats)
		if ok and type(result) == "table" then
			netStats = result
			for _, entry in result do
				if type(entry) == "table" then
					netTotals.accepted += tonumber(entry.accepted) or 0
					netTotals.rejectedRate += tonumber(entry.rejectedRate) or 0
					netTotals.rejectedArgs += tonumber(entry.rejectedArgs) or 0
					netTotals.rejectedDir += tonumber(entry.rejectedDir) or 0
					netTotals.errors += tonumber(entry.errors) or 0
				end
			end
		end
	end

	local players: { [string]: PlayerReport } = {}
	for userId, record in records do
		players[tostring(userId)] = copyRecord(record)
	end

	return {
		generatedAt = os.time(),
		totals = table.clone(totals),
		players = players,
		net = netStats,
		netTotals = netTotals,
	}
end

function NetworkValidation.Reset()
	table.clear(records)
	table.clear(totals)
	table.clear(departed)
	for _, player in Players:GetPlayers() do
		getRecord(player)
	end
end

--------------------------------------------------------------------------------
-- Garde-fous communs
--------------------------------------------------------------------------------

function NetworkValidation.CurrentRoundId(): number
	local value = GameState.read("RoundId")
	if type(value) == "number" and Validate.isFiniteNumber(value) then
		return value
	end
	return 0
end

-- Vrai si `roundId` désigne la manche courante (ou 0 quand allowZero, ex. entraînement à l'accueil).
-- Une requête d'une ancienne manche est ignorée et comptée ("stale_round").
function NetworkValidation.CheckRound(player: Player, roundId: any, allowZero: boolean?): boolean
	if not Validate.isInteger(roundId) then
		NetworkValidation.Report(player, "invalid_round", { value = tostring(roundId) })
		return false
	end
	local current = NetworkValidation.CurrentRoundId()
	if roundId == current or (allowZero == true and roundId == 0) then
		return true
	end
	NetworkValidation.Report(player, "stale_round", { got = roundId, current = current })
	return false
end

-- Cadence métier par joueur et par clé (en plus du seau à jetons de Net). Retourne true si l'action est
-- autorisée, et mémorise alors l'horodatage.
function NetworkValidation.CheckCooldown(player: Player, key: string, seconds: number): boolean
	local perPlayer = cooldowns[player]
	if not perPlayer then
		perPlayer = {}
		cooldowns[player] = perPlayer
	end
	local time = now()
	local last = perPlayer[key]
	if last ~= nil and time - last < seconds then
		return false
	end
	perPlayer[key] = time
	return true
end

-- Personnage vivant du joueur : (modèle, Humanoid, HumanoidRootPart) ou trois nil.
function NetworkValidation.GetAliveCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character or not character.Parent then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

-- Distance (serveur) entre le HumanoidRootPart du joueur et une position ; signale `reason` si trop loin.
function NetworkValidation.CheckDistance(player: Player, position: Vector3, maxDistance: number, reason: string?): boolean
	local _, _, root = NetworkValidation.GetAliveCharacter(player)
	if not root then
		return false
	end
	local distance = (root.Position - position).Magnitude
	if distance <= maxDistance then
		return true
	end
	if reason then
		NetworkValidation.Report(player, reason, { distance = distance, max = maxDistance })
	end
	return false
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function NetworkValidation.Init()
	if initialized then
		return
	end
	initialized = true

	Players.PlayerAdded:Connect(function(player)
		local record = getRecord(player)
		record.left = false
		record.name = player.Name
	end)
	Players.PlayerRemoving:Connect(function(player)
		cooldowns[player] = nil
		local record = records[player.UserId]
		if record then
			record.left = true
			table.insert(departed, player.UserId)
			trimDeparted()
		end
	end)
	for _, player in Players:GetPlayers() do
		getRecord(player)
	end
end

function NetworkValidation.Start() end

return NetworkValidation
