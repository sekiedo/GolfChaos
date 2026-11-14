--!strict
--[[
	RewardService — pièces de fin de partie, décidées et versées par le serveur (docs/ARCHITECTURE.md §8).

	  RewardService.GrantMatchRewards(summary)      appelé par MatchService (ou déclenché par MatchService.MatchEnded)
	  RewardService.GrantOnce(player, rewardId, amount) -> boolean   récompense unique (ex. tutoriel)
	  RewardService.MatchRewarded (Signal : player, reward)

	Calcul pur et testé : Logic/Rewards.computeMatch + Config/Economy (anti-farm : entraînement = 0, joueur inactif = 0,
	plafonds par partie). Versement idempotent : PlayerDataService.Transact avec l'opération
	"match:<MatchId>:<UserId>" — un double appel (signal + appel direct, reconnexion) ne paie jamais deux fois.

	Les statistiques de la partie sont relevées ici à partir des signaux (indépendamment du format interne de
	MatchService) : BallService.Shot (activité par manche), MatchService.PlayerFinishedHole (résultats par trou).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local GameState = require(Shared.Util.GameState)
local Economy = require(Shared.Config.Economy)
local Rewards = require(Shared.Logic.Rewards)

local RewardService = {}
RewardService.Priority = 50
RewardService.MatchRewarded = Signal.new()

local Services = require(script.Parent.Parent.Util.Services)
local services = Services.scope("Rewards")

type PlayerMatchStats = {
	activeRounds: { [number]: boolean },
	holesFinished: number,
	parOrBetter: number,
	holeInOnes: number,
	eagles: number,
	birdies: number,
	lastResultRound: { [number]: boolean },
}

local currentMatchId: string? = nil
local statsByUser: { [number]: PlayerMatchStats } = {}
local processed: { [string]: boolean } = {}

local getService = services.get

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function resetIfNewMatch()
	local matchId = GameState.read("MatchId")
	if type(matchId) == "string" and matchId ~= "" and matchId ~= currentMatchId then
		currentMatchId = matchId
		table.clear(statsByUser)
	end
end

local function statsFor(userId: number): PlayerMatchStats
	local entry = statsByUser[userId]
	if not entry then
		entry = { activeRounds = {}, holesFinished = 0, parOrBetter = 0, holeInOnes = 0, eagles = 0, birdies = 0, lastResultRound = {} }
		statsByUser[userId] = entry
	end
	return entry
end

local function countKeys(map: { [any]: boolean }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

local function onShot(player: Player, ...: any)
	resetIfNewMatch()
	local roundId = GameState.read("RoundId")
	if typeof(player) == "Instance" and player:IsA("Player") and isFiniteNumber(roundId) and roundId > 0 then
		statsFor(player.UserId).activeRounds[roundId] = true
	end
end

local function onPlayerFinishedHole(player: Player, result: any)
	resetIfNewMatch()
	if typeof(player) ~= "Instance" or not player:IsA("Player") or type(result) ~= "table" then
		return
	end
	local roundId = GameState.read("RoundId")
	local entry = statsFor(player.UserId)
	-- Un résultat par manche et par joueur (un signal répété ne compte pas deux fois).
	if isFiniteNumber(roundId) then
		if entry.lastResultRound[roundId] then
			return
		end
		entry.lastResultRound[roundId] = true
	end
	if result.finished ~= true then
		return
	end
	entry.holesFinished += 1
	local strokes, par = result.strokes, result.par
	if isFiniteNumber(strokes) and isFiniteNumber(par) then
		local diff = strokes - par
		if diff <= 0 then
			entry.parOrBetter += 1
		end
		if strokes == 1 then
			entry.holeInOnes += 1
		elseif diff <= -2 then
			entry.eagles += 1
		elseif diff == -1 then
			entry.birdies += 1
		end
	end
end

local function teamResultFor(player: Player, summary: any): string?
	local team = player:GetAttribute("Team")
	if type(team) ~= "string" or team == "" then
		return nil
	end
	local winner = summary.winner
	if winner == "Draw" or winner == "draw" or winner == nil then
		local scores = summary.teamScores
		if type(scores) == "table" and isFiniteNumber(scores.Red) and isFiniteNumber(scores.Blue) then
			if scores.Red == scores.Blue then
				return "Draw"
			end
			winner = if scores.Red > scores.Blue then "Red" else "Blue"
		else
			return "Draw"
		end
	end
	return if winner == team then "Win" else "Lose"
end

local function rankFor(userId: number, summary: any): (number?, number)
	local standings = summary.standings
	if type(standings) ~= "table" then
		return nil, 0
	end
	local count = 0
	local rank: number? = nil
	for _, row in standings do
		if type(row) == "table" then
			count += 1
			if row.userId == userId and isFiniteNumber(row.rank) then
				rank = row.rank
			end
		end
	end
	return rank, count
end

-- Versement pour un joueur (idempotent).
local function rewardPlayer(player: Player, summary: any)
	local matchId = summary.matchId or currentMatchId
	if type(matchId) ~= "string" or matchId == "" then
		return
	end
	local key = matchId .. ":" .. player.UserId
	if processed[key] then
		return
	end
	processed[key] = true

	local entry = statsByUser[player.UserId] or statsFor(player.UserId)
	local mode = if type(summary.mode) == "string" then summary.mode else GameState.read("Mode")
	local rank, participants = rankFor(player.UserId, summary)
	local holeCount = GameState.read("HoleCount")
	local input = {
		mode = if type(mode) == "string" then mode else "FreeForAll",
		rank = rank,
		participants = participants,
		holeCount = if isFiniteNumber(holeCount) then holeCount else countKeys(entry.activeRounds),
		activeHoles = countKeys(entry.activeRounds),
		holesFinished = entry.holesFinished,
		parOrBetter = entry.parOrBetter,
		holeInOnes = entry.holeInOnes,
		eagles = entry.eagles,
		birdies = entry.birdies,
		teamResult = teamResultFor(player, summary),
	}
	local reward = Rewards.computeMatch(input, Economy)

	local PlayerDataService = getService("PlayerDataService")
	local paid = false
	if reward.eligible and reward.total > 0 and PlayerDataService and type(PlayerDataService.Transact) == "function" then
		local ok, reason = PlayerDataService.Transact(player, "match:" .. key, function(data: any): (boolean, string?)
			local coins = if isFiniteNumber(data.coins) then data.coins else 0
			data.coins = math.clamp(math.floor(coins) + reward.total, 0, Economy.MaxCoins)
			return true, nil
		end)
		paid = ok == true
		if not ok then
			Log.warn("Rewards", "versement non effectué", player.Name, reason)
			reward = { eligible = false, reason = reason or "save_unavailable", total = 0, breakdown = reward.breakdown }
		end
	end

	-- Statistiques de partie (une seule fois par partie grâce à `processed`).
	local AchievementService = getService("AchievementService")
	if AchievementService and input.activeHoles > 0 and input.mode ~= "Training" then
		AchievementService.Increment(player, "matchesPlayed", 1)
		local won = (input.mode == "FreeForAll" and rank == 1 and participants >= 2) or input.teamResult == "Win"
		if won then
			AchievementService.Increment(player, "matchesWon", 1)
		end
		if input.mode == "Teams" and input.teamResult == "Win" then
			AchievementService.Increment(player, "teamWins", 1)
		end
	end

	Net.fire("Progress.MatchReward", player, {
		total = reward.total,
		breakdown = reward.breakdown,
		eligible = reward.eligible,
		reason = reward.reason,
		paid = paid,
	})
	RewardService.MatchRewarded:Fire(player, reward)
end

function RewardService.GrantMatchRewards(summary: any)
	if type(summary) ~= "table" then
		return
	end
	for _, player in Players:GetPlayers() do
		local participates = player:GetAttribute("Participant") == true
		local rank = rankFor(player.UserId, summary)
		if participates or rank ~= nil then
			local ok, err = pcall(rewardPlayer, player, summary)
			if not ok then
				Log.error("Rewards", "calcul de récompense", player.Name, err)
			end
		end
	end
end

function RewardService.GrantOnce(player: Player, rewardId: string, amount: number): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") or type(rewardId) ~= "string" then
		return false
	end
	if not isFiniteNumber(amount) or amount <= 0 then
		return false
	end
	local PlayerDataService = getService("PlayerDataService")
	if not PlayerDataService or type(PlayerDataService.Transact) ~= "function" then
		return false
	end
	local value = math.floor(amount)
	local ok = PlayerDataService.Transact(player, "once:" .. rewardId, function(data: any): (boolean, string?)
		local coins = if isFiniteNumber(data.coins) then data.coins else 0
		data.coins = math.clamp(math.floor(coins) + value, 0, Economy.MaxCoins)
		return true, nil
	end)
	return ok == true
end

local connect = services.connect

function RewardService.Init() end

function RewardService.Start()
	connect("BallService", "Shot", onShot)
	connect("MatchService", "PlayerFinishedHole", onPlayerFinishedHole)
	connect("MatchService", "MatchEnded", function(summary: any)
		RewardService.GrantMatchRewards(summary)
	end)
	Players.PlayerRemoving:Connect(function(player)
		statsByUser[player.UserId] = nil
	end)
end

return RewardService
