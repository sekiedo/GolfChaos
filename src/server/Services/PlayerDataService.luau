--!strict
--[[
	PlayerDataService — profils persistants des joueurs (docs/ARCHITECTURE.md, docs/SPEC_DEMANDE.md §8).

	  PlayerDataService.GetProfile(player) -> Profile?          données vivantes (lecture seule pour l'appelant) ;
	                                                            nil tant que le chargement n'est pas terminé
	  PlayerDataService.WaitForProfile(player, timeout?) -> Profile?
	  PlayerDataService.GetStatus(player) -> "Loading" | "Ready" | "Memory" | "Failed"
	  PlayerDataService.IsPersistent() -> boolean               false = sauvegarde en mémoire (Studio sans API)
	  PlayerDataService.Update(player, fn(data)) -> (boolean, string?)
	        fn modifie une COPIE du profil ; elle est validée sauf si fn renvoie false ou lève une erreur.
	  PlayerDataService.Transact(player, opId, fn(data) -> (boolean, string?)) -> (boolean, string?)
	        Idempotent : (false, "duplicate") si opId a déjà été appliqué. L'opération n'est mémorisée QUE si fn
	        renvoie true (un défi « pas encore atteint » pourra donc être versé plus tard).
	  PlayerDataService.AddCoins(player, amount, reason, opId) -> (boolean, string?)
	  PlayerDataService.SpendCoins(player, amount, reason, opId) -> (boolean, string?)
	  Signaux : ProfileLoaded(player, data), ProfileChanged(player)

	États (attribut joueur `DataStatus`) :
	  "Loading"  chargement en cours ; aucune lecture ni écriture
	  "Ready"    profil chargé depuis le DataStore, verrou de session tenu, modifications enregistrées
	  "Memory"   profil chargé depuis l'adaptateur mémoire : tout fonctionne mais RIEN n'est conservé après la
	             session (GameState.PersistentData = false, à afficher honnêtement)
	  "Failed"   le chargement a échoué ou le verrou a été perdu : profil par défaut en LECTURE SEULE, jamais
	             enregistré — un profil existant n'est donc jamais écrasé par un profil vide

	Réplication : attributs joueur `Coins` et `DataStatus`, GameState.PersistentData, instantané `Data.Sync`
	(regroupé) au propriétaire. Le client n'envoie que `Data.SaveSettings` (validé clé par clé) et
	`Data.RequestSync`.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local GameState = require(Shared.Util.GameState)
local ConfigData = require(Shared.Config.Data)

local dataFolder = script.Parent.Parent.Data
local Schema = require(dataFolder.Schema)
local ProfileOps = require(dataFolder.ProfileOps)
local ProfileStore = require(dataFolder.ProfileStore)
local DataStoreAdapter = require(dataFolder.Adapters.DataStoreAdapter)
local MemoryAdapter = require(dataFolder.Adapters.MemoryAdapter)

type Profile = Schema.Profile
export type Status = "Loading" | "Ready" | "Memory" | "Failed"

type Entry = {
	player: Player,
	userId: number,
	status: Status,
	data: Profile?,
	owned: boolean, -- cette session tient le verrou de la clé
	dirty: boolean,
	urgent: boolean,
	saving: boolean,
	released: boolean,
	lastSaveAt: number,
	syncQueued: boolean,
}

local LOG_TAG = "Data"

local PlayerDataService = {}
PlayerDataService.Priority = 5
PlayerDataService.ProfileLoaded = Signal.new() -- (player, data)
PlayerDataService.ProfileChanged = Signal.new() -- (player)

local entries: { [Player]: Entry } = {}
local store: ProfileStore.ProfileStore? = nil
local persistent = false
local closing = false

--------------------------------------------------------------------------------
-- Outils
--------------------------------------------------------------------------------

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isMutable(entry: Entry?): boolean
	return entry ~= nil and entry.data ~= nil and (entry.status == "Ready" or entry.status == "Memory")
end

local clampCoins = ProfileOps.clampCoins

local function sendSync(entry: Entry)
	local data = entry.data
	if data == nil or entry.player.Parent ~= Players then
		return
	end
	local payload = Schema.clientView(data)
	payload.status = entry.status
	payload.persistent = persistent
	local ok, err = pcall(Net.fire, "Data.Sync", entry.player, payload)
	if not ok then
		Log.warn(LOG_TAG, "Data.Sync non envoyé", entry.player.Name, err)
	end
end

local function queueSync(entry: Entry)
	if entry.syncQueued then
		return
	end
	entry.syncQueued = true
	task.delay(ConfigData.SyncDelay, function()
		entry.syncQueued = false
		if entries[entry.player] == entry then
			sendSync(entry)
		end
	end)
end

-- Publie l'état répliqué d'un joueur (attributs + instantané).
local function publish(entry: Entry)
	local player = entry.player
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute("DataStatus", entry.status)
	player:SetAttribute("Coins", if entry.data then entry.data.coins else 0)
	queueSync(entry)
end

local function commit(entry: Entry, draft: Profile, urgent: boolean)
	entry.data = draft
	entry.dirty = true
	entry.urgent = entry.urgent or urgent
	publish(entry)
	PlayerDataService.ProfileChanged:Fire(entry.player)
end

--------------------------------------------------------------------------------
-- Chargement et enregistrement
--------------------------------------------------------------------------------

local function selectStore(): ProfileStore.ProfileStore
	local adapter: DataStoreAdapter.Adapter? = nil
	local okCreate, created = pcall(DataStoreAdapter.new, { storeName = ConfigData.StoreName })
	if okCreate then
		local probe = created:Probe()
		if probe.ok then
			adapter = created
		elseif probe.error and probe.error.kind == "NoAccess" then
			Log.warn(LOG_TAG, "DataStore inaccessible (Studio sans accès aux API ou place non publiée) :", probe.error.message)
		else
			-- Panne passagère : on garde le DataStore réel. Les chargements qui échouent passent en « Failed »
			-- (lecture seule) au lieu de basculer tout le serveur en mémoire.
			adapter = created
			Log.warn(LOG_TAG, "DataStore instable au démarrage :", if probe.error then probe.error.message else "?")
		end
	else
		Log.warn(LOG_TAG, "DataStoreAdapter indisponible :", created)
	end
	if adapter == nil then
		adapter = MemoryAdapter.new()
		Log.warn(LOG_TAG, "SAUVEGARDE EN MÉMOIRE : les profils de cette session ne seront PAS conservés.")
	end
	return ProfileStore.new({
		adapter = adapter :: DataStoreAdapter.Adapter,
		keyPrefix = ConfigData.KeyPrefix,
		lockExpiry = ConfigData.LockExpiry,
	})
end

-- Enregistre un profil. `release` libère le verrou (départ du joueur) ; `final` = fermeture du serveur.
local function saveEntry(entry: Entry, release: boolean, final: boolean): boolean
	local profileStore = store
	local data = entry.data
	if profileStore == nil or data == nil or not entry.owned or entry.released then
		return false
	end
	-- Une seule écriture à la fois par profil.
	local waited = 0
	while entry.saving and waited < ConfigData.CloseTimeout do
		waited += task.wait(0.1)
	end
	if entry.released then
		return false
	end
	entry.saving = true
	local wasDirty, wasUrgent = entry.dirty, entry.urgent
	entry.dirty, entry.urgent = false, false
	if release then
		entry.released = true
	end
	local ok, reason = profileStore:Save(entry.userId, data, { release = release, closing = final })
	entry.saving = false
	entry.lastSaveAt = os.clock()
	if ok then
		return true
	end
	entry.dirty = entry.dirty or wasDirty
	entry.urgent = entry.urgent or wasUrgent
	Log.warn(LOG_TAG, "enregistrement non effectué", entry.player.Name, reason)
	if reason == "lock_lost" then
		-- Un autre serveur possède maintenant ce profil : ne plus jamais l'écrire depuis ici.
		entry.owned = false
		entry.status = "Failed"
		if entries[entry.player] == entry then
			publish(entry)
		end
	end
	return false
end

local function loadProfile(player: Player)
	local profileStore = store
	if profileStore == nil or entries[player] ~= nil then
		return
	end
	local entry: Entry = {
		player = player,
		userId = player.UserId,
		status = "Loading",
		data = nil,
		owned = false,
		dirty = false,
		urgent = false,
		saving = false,
		released = false,
		lastSaveAt = os.clock(),
		syncQueued = false,
	}
	entries[player] = entry
	player:SetAttribute("DataStatus", "Loading")

	local loaded: ProfileStore.LoadResult = { status = "Failed", profile = nil, isNew = false, notes = {}, error = "non chargé" }
	for attempt = 1, ConfigData.LoadRetries do
		local result = profileStore:Load(entry.userId)
		loaded = result
		if entries[player] ~= entry then
			-- Le joueur est parti pendant le chargement : rendre le verrou sans rien écrire d'autre.
			if result.status == "Loaded" then
				profileStore:Release(entry.userId)
			end
			return
		end
		if result.status ~= "Locked" or attempt == ConfigData.LoadRetries then
			break
		end
		Log.debug(LOG_TAG, "profil verrouillé, nouvel essai", player.Name, attempt)
		task.wait(ConfigData.LoadRetryDelay)
		if entries[player] ~= entry then
			return
		end
	end

	if loaded.status == "Loaded" and loaded.profile then
		entry.data = loaded.profile
		entry.owned = true
		entry.status = if persistent then "Ready" else "Memory"
		if #loaded.notes > 0 and not loaded.isNew then
			Log.info(LOG_TAG, player.Name, ":", #loaded.notes, "ajustement(s) au chargement —", table.concat(loaded.notes, " ; ", 1, math.min(#loaded.notes, 5)))
			entry.dirty = true
		end
	else
		-- Lecture seule : profil par défaut temporaire, jamais enregistré.
		entry.data = Schema.defaultProfile()
		entry.status = "Failed"
		Log.warn(LOG_TAG, "profil indisponible pour", player.Name, "(" .. loaded.status .. ") :", loaded.error)
	end
	publish(entry)
	PlayerDataService.ProfileLoaded:Fire(player, entry.data)
end

local function unloadProfile(player: Player)
	local entry = entries[player]
	if entry == nil then
		return
	end
	entries[player] = nil
	if entry.owned and not closing then
		saveEntry(entry, true, false)
	end
end

local function saveLoop()
	while not closing do
		task.wait(1)
		local clock = os.clock()
		for _, entry in entries do
			if not entry.owned or entry.saving or entry.released then
				continue
			end
			local since = clock - entry.lastSaveAt
			local due = (entry.dirty and entry.urgent and since >= math.max(ConfigData.UrgentSaveDelay, ConfigData.MinSaveGap))
				or (entry.dirty and since >= ConfigData.AutosaveInterval)
				or since >= ConfigData.LockRefresh
			if due then
				task.spawn(saveEntry, entry, false, false)
			end
		end
	end
end

local function saveAllOnClose()
	closing = true
	local pending = 0
	for _, entry in entries do
		if entry.owned and not entry.released then
			pending += 1
			task.spawn(function()
				saveEntry(entry, true, true)
				pending -= 1
			end)
		end
	end
	local deadline = os.clock() + ConfigData.CloseTimeout
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
	if pending > 0 then
		Log.warn(LOG_TAG, pending, "profil(s) non enregistré(s) à la fermeture (délai dépassé)")
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function PlayerDataService.GetProfile(player: Player): Profile?
	local entry = entries[player]
	if entry == nil or entry.status == "Loading" then
		return nil
	end
	return entry.data
end

function PlayerDataService.GetStatus(player: Player): Status
	local entry = entries[player]
	return if entry then entry.status else "Loading"
end

function PlayerDataService.IsPersistent(): boolean
	return persistent
end

function PlayerDataService.WaitForProfile(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or ConfigData.ProfileWaitTimeout)
	while player.Parent == Players and os.clock() < deadline do
		local profile = PlayerDataService.GetProfile(player)
		if profile then
			return profile
		end
		task.wait(0.1)
	end
	return PlayerDataService.GetProfile(player)
end

function PlayerDataService.Update(player: Player, fn: (data: any) -> ...any): (boolean, string?)
	local entry = entries[player]
	if not isMutable(entry) or type(fn) ~= "function" then
		return false, "profile_unavailable"
	end
	local current = entry :: Entry
	local ok, draft, reason, message = ProfileOps.update(current.data :: Profile, fn)
	if not ok or draft == nil then
		if reason == "error" then
			Log.warn(LOG_TAG, "Update : erreur de la fonction", player.Name, message)
		end
		return false, reason
	end
	commit(current, draft, false)
	return true, nil
end

function PlayerDataService.Transact(player: Player, opId: string, fn: (data: any) -> (boolean, string?)): (boolean, string?)
	local entry = entries[player]
	if not isMutable(entry) or type(fn) ~= "function" then
		return false, "profile_unavailable"
	end
	local current = entry :: Entry
	-- Tout ou rien : un refus métier ne modifie rien et ne mémorise pas opId (nouvel essai possible plus tard).
	local ok, draft, reason, message = ProfileOps.transact(current.data :: Profile, opId, fn)
	if not ok or draft == nil then
		if reason == "error" then
			Log.warn(LOG_TAG, "Transact : erreur de la fonction", player.Name, opId, message)
		end
		return false, reason
	end
	commit(current, draft, true)
	return true, nil
end

function PlayerDataService.AddCoins(player: Player, amount: number, reason: string, opId: string): (boolean, string?)
	if not isFiniteNumber(amount) or amount <= 0 then
		return false, "invalid_amount"
	end
	local ok, why = PlayerDataService.Transact(player, opId, function(data: any): (boolean, string?)
		data.coins = clampCoins(clampCoins(data.coins) + math.floor(amount))
		return true, nil
	end)
	if ok then
		Log.debug(LOG_TAG, player.Name, "+" .. math.floor(amount), "pièces :", reason)
	end
	return ok, why
end

function PlayerDataService.SpendCoins(player: Player, amount: number, reason: string, opId: string): (boolean, string?)
	if not isFiniteNumber(amount) or amount < 0 then
		return false, "invalid_amount"
	end
	local price = math.floor(amount)
	local ok, why = PlayerDataService.Transact(player, opId, function(data: any): (boolean, string?)
		local coins = clampCoins(data.coins)
		if coins < price then
			return false, "not_enough_coins"
		end
		data.coins = coins - price
		return true, nil
	end)
	if ok then
		Log.debug(LOG_TAG, player.Name, "-" .. price, "pièces :", reason)
	end
	return ok, why
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function PlayerDataService.Init()
	Net.on("Data.SaveSettings", function(player: Player, patch: any)
		PlayerDataService.Update(player, function(data: any): boolean
			local changed, rejected = Schema.applySettings(data.settings, patch)
			if #rejected > 0 then
				Log.debug(LOG_TAG, "préférences refusées", player.Name, table.concat(rejected, ","))
			end
			return #changed > 0
		end)
	end)
	Net.on("Data.RequestSync", function(player: Player)
		local entry = entries[player]
		if entry and entry.status ~= "Loading" then
			queueSync(entry)
		end
	end)
	Players.PlayerRemoving:Connect(unloadProfile)
end

function PlayerDataService.Start()
	local selected = selectStore()
	store = selected
	persistent = selected.persistent
	GameState.set("PersistentData", persistent)
	Log.info(LOG_TAG, if persistent then "sauvegarde DataStore prête" else "sauvegarde en mémoire (non persistante)")

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(loadProfile, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(loadProfile, player)
	end
	task.spawn(saveLoop)
	game:BindToClose(saveAllOnClose)
end

return PlayerDataService
