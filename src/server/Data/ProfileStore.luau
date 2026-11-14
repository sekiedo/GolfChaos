--!strict
--[[
	ProfileStore — chargement et enregistrement des profils avec VERROU DE SESSION. SERVEUR uniquement.
	Aucun effet au require. Ne connaît ni les joueurs ni les remotes : PlayerDataService s'en charge.

	  local store = ProfileStore.new({ adapter = adapter })
	  store:Load(userId) -> LoadResult             UNE tentative (l'appelant gère les nouveaux essais et l'attente)
	      status "Loaded"   profile = profil migré + assaini ; le verrou de cette session est posé sur la clé
	             "Locked"   un autre serveur tient un verrou encore valide : rien n'a été écrit, réessayer plus tard
	             "Failed"   lecture impossible ou profil illisible (error = raison) : rien n'a été écrit
	  store:Save(userId, profile, options?) -> (boolean, string?)
	      Écrit une copie assainie du profil et renouvelle le verrou. options.release = true le libère (départ du
	      joueur) ; options.closing = true envoie même sans budget de requêtes (fermeture du serveur).
	      (false, "lock_lost") si la clé n'appartient plus à cette session : le profil ne doit plus être écrit.
	  store:Release(userId) -> boolean             libère le verrou sans toucher aux données
	  store.sessionId, store.persistent (celui de l'adaptateur)

	Garanties :
	  - un profil n'est écrit QUE par la session qui tient son verrou ; un chargement en échec n'écrit jamais rien
	    (un profil existant n'est donc jamais remplacé par un profil vide) ;
	  - un verrou abandonné (serveur planté) expire après `lockExpiry` secondes et peut alors être repris ;
	  - un profil d'une version future ou d'un type inattendu est refusé sans être modifié.
]]

local HttpService = game:GetService("HttpService")

local DataStoreAdapter = require(script.Parent.Adapters.DataStoreAdapter)
local Migrations = require(script.Parent.Migrations)
local Schema = require(script.Parent.Schema)

local Lock = DataStoreAdapter.Lock

export type Profile = Schema.Profile
export type Adapter = DataStoreAdapter.Adapter

export type LoadStatus = "Loaded" | "Locked" | "Failed"

export type LoadResult = {
	status: LoadStatus,
	profile: Profile?,
	isNew: boolean, -- la clé n'existait pas : profil neuf
	notes: { string }, -- migrations et réparations appliquées au chargement
	error: string?,
}

export type SaveOptions = { release: boolean?, closing: boolean? }

export type Config = {
	adapter: Adapter,
	keyPrefix: string?, -- défaut "Player_"
	lockExpiry: number?, -- secondes, défaut 300
	sessionId: string?, -- défaut : GUID
	jobId: string?, -- défaut : game.JobId
	now: (() -> number)?, -- secondes Unix (tests)
}

export type ProfileStore = {
	sessionId: string,
	persistent: boolean,
	Load: (self: ProfileStore, userId: number) -> LoadResult,
	Save: (self: ProfileStore, userId: number, profile: Profile, options: SaveOptions?) -> (boolean, string?),
	Release: (self: ProfileStore, userId: number) -> boolean,
}

local DEFAULT_KEY_PREFIX = "Player_"
local DEFAULT_LOCK_EXPIRY = 300
local CLOSING_OPTIONS: DataStoreAdapter.CallOptions = { proceedWithoutBudget = true, maxAttempts = 2, budgetTimeout = 2 }

local ProfileStore = {}

local Methods = {}
Methods.__index = Methods

local function keyFor(self: any, userId: number): string
	return self._keyPrefix .. tostring(userId)
end

local function errorText(result: DataStoreAdapter.Result): string
	local err = result.error
	return if err then err.kind .. " : " .. err.message else "Unknown"
end

function Methods.Load(self: ProfileStore, userId: number): LoadResult
	local internal = self :: any
	local status: LoadStatus = "Failed"
	local reason: string? = nil
	local loaded: Profile? = nil
	local notes: { string } = {}
	local isNew = false

	-- Transformation PURE (peut être rappelée) : chaque passage repart de zéro.
	local result = internal._adapter:Update(keyFor(internal, userId), function(current: any, keyInfo: DataStoreAdapter.KeyInfo?)
		status, reason, loaded, notes, isNew = "Failed", nil, nil, {}, false
		local time: number = internal._now()
		local metadata = if keyInfo then keyInfo.metadata else nil
		local lock = Lock.read(metadata)
		if lock and lock.id ~= self.sessionId and Lock.isActive(lock, time, internal._lockExpiry) then
			status, reason = "Locked", "verrou tenu par " .. (if lock.job ~= "" then lock.job else lock.id)
			return nil
		end
		local profile, upgradeNotes, upgradeError = Migrations.upgrade(current, time)
		if profile == nil then
			reason = upgradeError or "invalid"
			return nil
		end
		status, notes, isNew = "Loaded", upgradeNotes, current == nil
		loaded = profile :: Profile?
		return profile, { userId }, Lock.write(metadata, Lock.make(self.sessionId, internal._jobId, time))
	end)

	if not result.ok then
		return { status = "Failed", profile = nil, isNew = false, notes = {}, error = errorText(result) }
	end
	if result.aborted or loaded == nil then
		return { status = if status == "Locked" then "Locked" else "Failed", profile = nil, isNew = false, notes = {}, error = reason }
	end
	return { status = "Loaded", profile = loaded, isNew = isNew, notes = notes, error = nil }
end

local function write(self: ProfileStore, userId: number, snapshot: Profile?, options: SaveOptions?): (boolean, string?)
	local internal = self :: any
	local release = options ~= nil and options.release == true
	local lost = false
	local callOptions = if options and options.closing then CLOSING_OPTIONS else nil

	local result = internal._adapter:Update(keyFor(internal, userId), function(current: any, keyInfo: DataStoreAdapter.KeyInfo?)
		lost = false
		local metadata = if keyInfo then keyInfo.metadata else nil
		local lock = Lock.read(metadata)
		if lock == nil or lock.id ~= self.sessionId then
			lost = true
			return nil
		end
		local value = if snapshot ~= nil then snapshot else current
		if value == nil then
			lost = true
			return nil
		end
		local nextLock = if release then nil else Lock.make(self.sessionId, internal._jobId, internal._now())
		return value, { userId }, Lock.write(metadata, nextLock)
	end, callOptions)

	if not result.ok then
		return false, errorText(result)
	end
	if lost then
		return false, "lock_lost"
	end
	return true, nil
end

function Methods.Save(self: ProfileStore, userId: number, profile: Profile, options: SaveOptions?): (boolean, string?)
	local time: number = (self :: any)._now()
	-- Copie assainie, indépendante du profil vivant (qui peut changer pendant l'écriture).
	local snapshot = Schema.sanitize(profile, time)
	snapshot.updatedAt = time
	return write(self, userId, snapshot, options)
end

function Methods.Release(self: ProfileStore, userId: number): boolean
	local ok = write(self, userId, nil, { release = true })
	return ok
end

function ProfileStore.new(config: Config): ProfileStore
	assert(type(config) == "table" and config.adapter ~= nil, "ProfileStore.new : adaptateur manquant")
	local self = {
		sessionId = config.sessionId or HttpService:GenerateGUID(false),
		persistent = config.adapter.persistent,
		_adapter = config.adapter,
		_keyPrefix = config.keyPrefix or DEFAULT_KEY_PREFIX,
		_lockExpiry = config.lockExpiry or DEFAULT_LOCK_EXPIRY,
		_jobId = config.jobId or game.JobId,
		_now = config.now or os.time,
	}
	return (setmetatable(self, Methods) :: any) :: ProfileStore
end

return ProfileStore
