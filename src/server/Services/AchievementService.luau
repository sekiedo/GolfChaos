--!strict
--[[
	AchievementService — défis et succès INTERNES (Config/Achievements), sans BadgeId Roblox.

	API (docs/ARCHITECTURE.md §8) :
	  AchievementService.Increment(player, statId, amount?)   compteur cumulé profil.stats[statId]
	  AchievementService.AddToSet(player, setName, key)       ensemble profil.sets[setName][key] = true
	  AchievementService.Event(player, eventName)             événement unique profil.events[eventName] = true
	  AchievementService.GetProgress(player) -> { [id] = { progress, target, done } }
	  AchievementService.Completed (Signal : player, achievementId, reward)

	Chaque défi atteint est versé UNE seule fois : PlayerDataService.Transact avec l'identifiant d'opération
	"ach:<id>" (idempotent, rejouable sans double versement après reconnexion). Rien n'est accordé si le profil
	n'est pas prêt (statut Loading/Failed) : la progression reste dans le profil et sera rattrapée au prochain
	événement. Sources écoutées (si les services existent) : BallService.Holed, MatchService.PlayerFinishedHole,
	CombatService.KnockedOut, ItemService.ItemUsed, VehicleService (statistiques passées par Increment).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local GameState = require(Shared.Util.GameState)
local Achievements = require(Shared.Config.Achievements)

type AchievementDef = Achievements.AchievementDef

local AchievementService = {}
AchievementService.Priority = 45
AchievementService.Completed = Signal.new()

local Services = require(script.Parent.Parent.Util.Services)
local services = Services.scope("Achievements")

-- Index : statistique / ensemble / événement -> défis concernés.
local byStat: { [string]: { AchievementDef } } = {}
local bySet: { [string]: { AchievementDef } } = {}
local byEvent: { [string]: { AchievementDef } } = {}
for _, def in Achievements.List do
	if def.kind == "Stat" and def.stat then
		byStat[def.stat] = byStat[def.stat] or {}
		table.insert(byStat[def.stat], def)
	elseif def.kind == "Set" and def.stat then
		bySet[def.stat] = bySet[def.stat] or {}
		table.insert(bySet[def.stat], def)
	elseif def.kind == "Event" and def.event then
		byEvent[def.event] = byEvent[def.event] or {}
		table.insert(byEvent[def.event], def)
	end
end

local function dataService(): any?
	return services.get("PlayerDataService")
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Garantit la présence des sous-tables utilisées ici (sans écraser des données existantes).
local function ensureTables(data: any)
	if type(data.stats) ~= "table" then
		data.stats = {}
	end
	if type(data.sets) ~= "table" then
		data.sets = {}
	end
	if type(data.events) ~= "table" then
		data.events = {}
	end
	if type(data.achievements) ~= "table" then
		data.achievements = {}
	end
end

-- Données du profil en lecture (GetProfile peut renvoyer les données ou un objet profil portant .data).
local function readData(player: Player): any?
	local PlayerDataService = dataService()
	if not PlayerDataService or type(PlayerDataService.GetProfile) ~= "function" then
		return nil
	end
	local ok, profile = pcall(PlayerDataService.GetProfile, player)
	if not ok or type(profile) ~= "table" then
		return nil
	end
	if type((profile :: any).data) == "table" then
		return (profile :: any).data
	end
	return profile
end

-- Verse les défis atteints parmi `candidates` (après une mise à jour du profil).
-- Un premier filtrage en lecture évite d'ouvrir une transaction pour un défi non atteint ou déjà versé
-- (moins d'écritures, budgets de requêtes préservés) ; la transaction revérifie tout de façon autoritaire.
local function settle(player: Player, candidates: { AchievementDef })
	local PlayerDataService = dataService()
	if not PlayerDataService or type(PlayerDataService.Transact) ~= "function" then
		return
	end
	local snapshot = readData(player)
	for _, def in candidates do
		if type(snapshot) == "table" then
			local entry = type(snapshot.achievements) == "table" and snapshot.achievements[def.id] or nil
			if type(entry) == "table" and entry.done == true then
				continue
			end
			if Achievements.progress(def, snapshot.stats, snapshot.sets, snapshot.events) < def.target then
				continue
			end
		end
		local opId = "ach:" .. def.id
		local ok, reason = PlayerDataService.Transact(player, opId, function(data: any): (boolean, string?)
			ensureTables(data)
			local entry = data.achievements[def.id]
			if type(entry) == "table" and entry.done == true then
				return false, "already_done"
			end
			local progress = Achievements.progress(def, data.stats, data.sets, data.events)
			if progress < def.target then
				return false, "not_reached"
			end
			data.achievements[def.id] = { done = true, at = os.time() }
			local coins = if isFiniteNumber(data.coins) then data.coins else 0
			data.coins = math.max(0, math.floor(coins)) + def.reward
			return true, nil
		end)
		if ok then
			Log.info("Achievements", player.Name, "a réussi", def.id, "+" .. def.reward)
			Net.fire("Progress.AchievementCompleted", player, def.id, def.reward)
			AchievementService.Completed:Fire(player, def.id, def.reward)
		elseif reason ~= "already_done" and reason ~= "not_reached" and reason ~= "duplicate" then
			Log.debug("Achievements", "versement différé", def.id, player.Name, reason)
		end
	end
end

local function update(player: Player, mutate: (data: any) -> ()): boolean
	local PlayerDataService = dataService()
	if not PlayerDataService or type(PlayerDataService.Update) ~= "function" then
		return false
	end
	local ok, err = pcall(PlayerDataService.Update, player, function(data: any)
		ensureTables(data)
		mutate(data)
	end)
	if not ok then
		Log.warn("Achievements", "mise à jour refusée", player.Name, err)
	end
	return ok
end

function AchievementService.Increment(player: Player, statId: string, amount: number?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or type(statId) ~= "string" then
		return
	end
	local delta = if isFiniteNumber(amount) then amount :: number else 1
	if delta <= 0 then
		return
	end
	local applied = update(player, function(data)
		local current = data.stats[statId]
		data.stats[statId] = (if isFiniteNumber(current) then current else 0) + delta
	end)
	if applied and byStat[statId] then
		settle(player, byStat[statId])
	end
end

function AchievementService.AddToSet(player: Player, setName: string, key: string)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or type(setName) ~= "string" or type(key) ~= "string" then
		return
	end
	local applied = update(player, function(data)
		local set = data.sets[setName]
		if type(set) ~= "table" then
			set = {}
			data.sets[setName] = set
		end
		set[key] = true
	end)
	if applied and bySet[setName] then
		settle(player, bySet[setName])
	end
end

function AchievementService.Event(player: Player, eventName: string)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or type(eventName) ~= "string" then
		return
	end
	local applied = update(player, function(data)
		data.events[eventName] = true
	end)
	if applied and byEvent[eventName] then
		settle(player, byEvent[eventName])
	end
end

function AchievementService.GetProgress(player: Player): { [string]: { progress: number, target: number, done: boolean } }
	local result = {}
	local data = readData(player)
	for _, def in Achievements.List do
		local entry = if type(data) == "table" and type(data.achievements) == "table" then data.achievements[def.id] else nil
		local progress = if type(data) == "table" then Achievements.progress(def, data.stats, data.sets, data.events) else 0
		result[def.id] = { progress = progress, target = def.target, done = type(entry) == "table" and entry.done == true }
	end
	return result
end

-- Rattrapage à la connexion : verse les défis déjà atteints dont le versement avait échoué.
local function catchUp(player: Player)
	local all = {}
	for _, def in Achievements.List do
		table.insert(all, def)
	end
	settle(player, all)
end

-- Branchements sur les autres services ------------------------------------------------

local function onHoled(player: Player, info: any)
	if type(info) ~= "table" then
		return
	end
	AchievementService.Increment(player, "holesFinished", 1)
	local strokes = if isFiniteNumber(info.strokes) then info.strokes else nil
	local par = GameState.read("HolePar")
	if info.holeInOne == true or strokes == 1 then
		AchievementService.Increment(player, "holesInOne", 1)
	end
	if strokes and isFiniteNumber(par) then
		local diff = strokes - par
		if diff <= 0 then
			AchievementService.Increment(player, "parOrBetter", 1)
		end
		if diff == -1 then
			AchievementService.Increment(player, "birdies", 1)
		elseif diff <= -2 then
			AchievementService.Increment(player, "eagles", 1)
		end
	end
	if info.wasPutt ~= true and isFiniteNumber(info.fromDistance) and info.fromDistance >= Achievements.LongShotDistance then
		AchievementService.Increment(player, "longShots", 1)
	end
	if info.shotType == "Chip" then
		AchievementService.Increment(player, "chipIns", 1)
	end
	if info.wasPutt == true and info.putts == 1 then
		AchievementService.Increment(player, "onePutts", 1)
	end
	local biome = GameState.read("HoleBiome")
	local holeId = GameState.read("HoleId")
	if type(biome) == "string" and biome ~= "" and biome ~= "Training" then
		AchievementService.AddToSet(player, "biomesFinished", biome)
		if type(holeId) == "string" and holeId ~= "" then
			AchievementService.AddToSet(player, "holesFinished_" .. biome, holeId)
		end
	end
end

local function onKnockedOut(victim: Player, attacker: Player?, source: any)
	if typeof(victim) == "Instance" and victim:IsA("Player") then
		AchievementService.Increment(victim, "timesKOed", 1)
	end
	if typeof(attacker) == "Instance" and (attacker :: Instance):IsA("Player") and attacker ~= victim then
		AchievementService.Increment(attacker :: Player, "kos", 1)
		if source == "cart" or source == "caddie_kart" then
			AchievementService.Increment(attacker :: Player, "cartKOs", 1)
		end
	end
end

local function onItemUsed(player: Player, itemId: any)
	if type(itemId) ~= "string" then
		return
	end
	AchievementService.Increment(player, "itemsUsed", 1)
	AchievementService.AddToSet(player, "itemsUsedSet", itemId)
end

local connect = services.connect

function AchievementService.Init()
	-- Rien à créer : les remotes sont déclarés dans Net/Remotes/Progress.luau.
end

function AchievementService.Start()
	connect("BallService", "Holed", onHoled)
	connect("CombatService", "KnockedOut", onKnockedOut)
	connect("ItemService", "ItemUsed", onItemUsed)

	local PlayerDataService = dataService()
	if PlayerDataService and type(PlayerDataService.ProfileLoaded) == "table" then
		PlayerDataService.ProfileLoaded:Connect(function(player: Player)
			task.spawn(catchUp, player)
		end)
	end
	Players.PlayerRemoving:Connect(function(_player)
		-- Aucun état local par joueur à nettoyer : tout est dans le profil.
	end)
end

return AchievementService
