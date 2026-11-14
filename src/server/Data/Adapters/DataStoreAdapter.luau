--!strict
--[[
	DataStoreAdapter — accès DataStore RÉEL (persistent = true) pour le magasin de profils. SERVEUR uniquement.
	Aucun effet au require : DataStoreService, le store et le générateur aléatoire sont obtenus dans new() ou à
	la première requête.

	  local adapter = DataStoreAdapter.new({ storeName = "PlayerData" })
	  adapter:Get(key, options?)               -> Result   GetAsync (options.useCache = false : contourne le cache de 4 s)
	  adapter:Update(key, transform, options?) -> Result   UpdateAsync (voir « Transformation »)
	  adapter:Remove(key, options?)            -> Result   RemoveAsync (droit à l'effacement)
	  adapter:Probe()                          -> Result   lecture d'essai : ok = false + kind "NoAccess" si Studio
	                                                       n'a pas accès aux API ou si la place n'est pas publiée
	  adapter:GetStats()                       -> Stats
	  adapter.kind = "DataStore", adapter.persistent = true, adapter.storeName = nom effectif du store
	  options = { useCache?, maxAttempts?, budgetTimeout?, proceedWithoutBudget? }

	Result = { ok, value, keyInfo?, aborted, attempts, error? }
	  ok = true    requête aboutie ; pour Update : écrite, ou ANNULÉE volontairement (aborted = true, rien d'écrit)
	  ok = false   error = { kind, code?, message, retryable } après des tentatives bornées, ou tout de suite si
	               l'erreur n'est pas reprenable. kind :
	                 "Throttled" | "Transient" | "Unknown"  reprenables (déjà reprises ici ; réessayer plus tard)
	                 "Budget"     budget de requêtes du serveur épuisé (rien n'a été envoyé ; réessayer plus tard)
	                 "NoAccess"   Studio sans accès aux API / place non publiée (403, « publish ») : basculer sur
	                              MemoryAdapter (données NON persistantes, à signaler honnêtement)
	                 "Shutdown"   serveur en cours d'arrêt (401/402)
	                 "TooLarge" | "Invalid"  valeur refusée (taille, type, UTF-8, NaN/inf, table mixte, métadonnées)
	                 "Transform"  la transformation a levé une erreur ou a cédé (yield)
	  ATTENTION (doc Roblox) : un échec d'écriture ne prouve pas l'absence d'écriture. Relire avec
	  Get(key, { useCache = false }) avant de conclure ; les transactions restent idempotentes (Schema.recordOp).

	Transformation (Update) : transform(current, keyInfo) -> (nouvelleValeur | nil, userIds?, metadata?)
	  - nil annule l'écriture (aborted = true). Elle peut être rappelée plusieurs fois (conflit entre serveurs,
	    nouvelle tentative) : elle doit être PURE, rapide et ne jamais céder (yield) — un yield est détecté et
	    refusé (kind "Transform").
	  - userIds / metadata renvoyés à nil sont CONSERVÉS (l'API brute les effacerait) ; {} les vide.
	  - avant écriture, la valeur est vérifiée : types sérialisables, textes UTF-8, nombres finis, pas de table
	    mixte ni de tableau à trous, JSON <= 4 194 304 caractères ; métadonnées <= 300 caractères ; 4 userIds max.
	  - keyInfo (copie) = { version?, createdTime?, updatedTime? (ms), userIds, metadata } ou nil (clé absente).

	Garanties :
	  - les opérations sur une même clé s'exécutent dans l'ordre d'appel (file par clé, dans un thread de travail
	    propre) : une vieille reprise ne peut pas écraser une écriture plus récente, et annuler le thread appelant
	    (task.cancel) ne bloque jamais la clé ;
	  - budget vérifié avant chaque tentative (GetRequestBudgetForRequestType, attente bornée), puis tentatives
	    bornées avec attente exponentielle et gigue ;
	  - en Studio, le store est suffixé "_Studio" (isolateStudio, vrai par défaut) : une session Studio ne lit ni
	    n'écrit jamais les données réelles des joueurs, même si l'accès aux API est activé.

	Verrou de session (convention partagée ; appliqué par le magasin de profils, pas par l'adaptateur) :
	  DataStoreAdapter.Lock.make(id, jobId?, now) -> SessionLock         { id, job, at (secondes) }
	  DataStoreAdapter.Lock.read(metadata?) -> SessionLock?
	  DataStoreAdapter.Lock.write(metadata?, lock?) -> metadata          copie ; lock = nil efface le verrou
	  DataStoreAdapter.Lock.isActive(lock?, now, expirySeconds) -> boolean
	  Stocké à plat dans les métadonnées de la clé (lockId, lockJob, lockAt) pour rester sous 300 caractères.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Log = require(Shared.Util.Log)

export type ErrorKind =
	"Throttled"
	| "Budget"
	| "Transient"
	| "Unknown"
	| "NoAccess"
	| "Shutdown"
	| "TooLarge"
	| "Invalid"
	| "Transform"

export type AdapterError = {
	kind: ErrorKind,
	code: number?,
	message: string,
	retryable: boolean,
}

export type KeyInfo = {
	version: string?,
	createdTime: number?, -- millisecondes Unix
	updatedTime: number?,
	userIds: { number },
	metadata: { [string]: any },
}

export type Result = {
	ok: boolean,
	value: any,
	keyInfo: KeyInfo?,
	aborted: boolean,
	attempts: number,
	error: AdapterError?,
}

export type Transform = (current: any, keyInfo: KeyInfo?) -> (any, { number }?, { [string]: any }?)

export type CallOptions = {
	useCache: boolean?, -- Get : false = relecture sans le cache local de 4 s
	maxAttempts: number?, -- 1..10 (défaut : configuration de l'adaptateur)
	budgetTimeout: number?, -- attente maximale d'un budget de requêtes (secondes)
	proceedWithoutBudget: boolean?, -- après l'attente, envoyer quand même (sauvegarde de fermeture)
}

export type Config = {
	storeName: string?, -- défaut "PlayerData"
	scope: string?, -- facultatif (préférer des préfixes de clé)
	isolateStudio: boolean?, -- défaut true : en Studio, store suffixé "_Studio"
	maxAttempts: number?, -- défaut 5
	baseDelay: number?, -- défaut 1 s (attente exponentielle : base × 2^(n-1), gigue 50..100 %)
	maxDelay: number?, -- défaut 12 s
	budgetTimeout: number?, -- défaut 6 s
	budgetPoll: number?, -- défaut 0,5 s
	service: any?, -- DataStoreService injecté (émulation : MemoryAdapter, tests)
	kind: string?, -- réservé à MemoryAdapter
	persistent: boolean?, -- réservé à MemoryAdapter
	isStudio: boolean?, -- remplace RunService:IsStudio() (tests)
}

export type Stats = {
	requests: number, -- tentatives envoyées au service
	succeeded: number,
	failed: number, -- opérations en échec définitif
	retries: number,
	aborted: number, -- mises à jour annulées par leur transformation
	budgetWaits: number,
	queued: number, -- opérations ayant attendu leur tour sur leur clé
	lastError: AdapterError?,
}

export type SessionLock = { id: string, job: string, at: number }

export type Adapter = {
	kind: string,
	persistent: boolean,
	storeName: string,
	Get: (self: Adapter, key: string, options: CallOptions?) -> Result,
	Update: (self: Adapter, key: string, transform: Transform, options: CallOptions?) -> Result,
	Remove: (self: Adapter, key: string, options: CallOptions?) -> Result,
	Probe: (self: Adapter) -> Result,
	GetStats: (self: Adapter) -> Stats,
}

type Operation = "Get" | "Update" | "Remove"
type Attempt = (store: any) -> (Result?, AdapterError?)

local DataStoreAdapter = {}

DataStoreAdapter.DEFAULT_STORE = "PlayerData"
DataStoreAdapter.STUDIO_SUFFIX = "_Studio"
DataStoreAdapter.PROBE_KEY = "__probe"

DataStoreAdapter.Limits = table.freeze({
	NameLength = 50, -- nom de store, scope
	KeyLength = 50,
	ValueLength = 4_194_304, -- caractères JSON par clé
	MetadataLength = 300, -- JSON total des métadonnées
	MetadataKeyLength = 50,
	MetadataValueLength = 250,
	UserIds = 4,
	MaxDepth = 64,
	MaxAttempts = 10,
})
local LIMITS = DataStoreAdapter.Limits

local DEFAULTS = table.freeze({
	maxAttempts = 5,
	baseDelay = 1,
	maxDelay = 12,
	budgetTimeout = 6,
	budgetPoll = 0.5,
})

--------------------------------------------------------------------------------
-- Outils
--------------------------------------------------------------------------------

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function numberOr(value: any, fallback: number, min: number, max: number): number
	if isFinite(value) then
		return math.clamp(value, min, max)
	end
	return fallback
end

local httpService: HttpService? = nil

local function getHttpService(): HttpService
	local service = httpService
	if service == nil then
		service = game:GetService("HttpService")
		httpService = service
	end
	return service :: HttpService
end

local function jsonLength(value: any): (boolean, number | string)
	local ok, encoded = pcall(function()
		return getHttpService():JSONEncode(value)
	end)
	if not ok then
		return false, tostring(encoded)
	end
	return true, #(encoded :: string)
end

--------------------------------------------------------------------------------
-- Classification des erreurs
--------------------------------------------------------------------------------

local RETRYABLE: { [string]: boolean } = { Throttled = true, Budget = true, Transient = true, Unknown = true }

local function makeError(kind: ErrorKind, code: number?, message: string): AdapterError
	return {
		kind = kind,
		code = code,
		message = string.sub(message, 1, 400),
		retryable = RETRYABLE[kind] == true,
	}
end
DataStoreAdapter.makeError = makeError

-- Codes documentés (create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits).
local CODE_KINDS: { [number]: ErrorKind } = {
	[101] = "Invalid", -- KeyNameEmpty
	[102] = "Invalid", -- KeyNameLimit
	[103] = "Invalid", -- ValueNotAllowed
	[104] = "Invalid", -- CantStoreValue
	[105] = "TooLarge", -- ValueTooLarge
	[106] = "Invalid",
	[107] = "Invalid",
	[301] = "Throttled", -- GetAsync : file pleine
	[302] = "Throttled",
	[303] = "Throttled",
	[304] = "Throttled", -- UpdateAsync : file pleine
	[305] = "Throttled",
	[306] = "Throttled", -- RemoveAsync : file pleine
	[401] = "Shutdown", -- DataModelNoAccess
	[402] = "Shutdown", -- LuaWebSrvsNoAccess
	[403] = "NoAccess", -- StudioAccessToApisNotAllowed
	[404] = "Transient",
	[501] = "Transient",
	[502] = "Transient", -- RequestRejected
	[503] = "Transient",
	[504] = "Transient",
	[505] = "Transient",
	[509] = "NoAccess", -- OperationNotAllowed (RCC personnel)
	[511] = "TooLarge", -- AttributeSizeTooLarge (métadonnées)
	[512] = "Invalid", -- UserIdLimitExceeded
	[513] = "Invalid", -- AttributeFormatError
}

-- Messages sans code numérique (KeyThrottled, StandardReadExperienceThrottled...), testés dans l'ordre.
local TEXT_KINDS: { { pattern: string, kind: ErrorKind } } = {
	{ pattern = "studioaccesstoapisnotallowed", kind = "NoAccess" },
	{ pattern = "api access", kind = "NoAccess" },
	{ pattern = "publish", kind = "NoAccess" }, -- « You must publish this place to the web to access DataStore »
	{ pattern = "operationnotallowed", kind = "NoAccess" },
	{ pattern = "shutting down", kind = "Shutdown" },
	{ pattern = "datamodelnoaccess", kind = "Shutdown" },
	{ pattern = "luawebsrvsnoaccess", kind = "Shutdown" },
	{ pattern = "throttl", kind = "Throttled" },
	{ pattern = "queue", kind = "Throttled" },
	{ pattern = "keyname", kind = "Invalid" },
	{ pattern = "useridlimit", kind = "Invalid" },
	{ pattern = "attributeformat", kind = "Invalid" },
	{ pattern = "utf%-8", kind = "Invalid" },
	{ pattern = "can't store", kind = "Invalid" },
	{ pattern = "cannot store", kind = "Invalid" },
	{ pattern = "cantstorevalue", kind = "Invalid" },
	{ pattern = "can't allow", kind = "Invalid" },
	{ pattern = "valuenotallowed", kind = "Invalid" },
	{ pattern = "toolarge", kind = "TooLarge" },
	{ pattern = "too large", kind = "TooLarge" },
	{ pattern = "exceeds", kind = "TooLarge" },
	{ pattern = "http", kind = "Transient" },
	{ pattern = "timeout", kind = "Transient" },
	{ pattern = "timed out", kind = "Transient" },
	{ pattern = "internal", kind = "Transient" },
	{ pattern = "requestrejected", kind = "Transient" },
}

function DataStoreAdapter.classifyError(err: any): AdapterError
	local message = tostring(err)
	-- « 502: ... », « DataStoreService: 403: ... » : premier nombre à 3 chiffres suivi de « : »
	local code = tonumber(string.match(message, "^%D-(%d%d%d)%s*:"))
	if code ~= nil then
		local kind = CODE_KINDS[code]
		if kind == nil and code >= 500 and code <= 599 then
			kind = "Transient"
		end
		if kind ~= nil then
			return makeError(kind, code, message)
		end
	end
	local lowered = string.lower(message)
	for _, rule in TEXT_KINDS do
		if string.find(lowered, rule.pattern) then
			return makeError(rule.kind, code, message)
		end
	end
	return makeError("Unknown", code, message)
end

function DataStoreAdapter.backoffDelay(attempt: number, baseDelay: number, maxDelay: number, random: Random?): number
	local raw = math.min(maxDelay, baseDelay * 2 ^ math.max(0, attempt - 1))
	local factor = if random then random:NextNumber() else math.random()
	return raw * (0.5 + 0.5 * factor)
end

--------------------------------------------------------------------------------
-- Vérification des valeurs (mêmes règles que DataStore, messages précis)
--------------------------------------------------------------------------------

local function formatKey(key: any): string
	return if type(key) == "number" then "[" .. tostring(key) .. "]" else "." .. tostring(key)
end

-- Parcours récursif ; renvoie (false, " chemin : motif") au premier problème.
local function walk(value: any, depth: number, seen: { [any]: boolean }): (boolean, string?)
	local kind = type(value)
	if kind == "boolean" or kind == "buffer" then
		return true, nil
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return false, " : nombre non fini (NaN/inf)"
		end
		return true, nil
	elseif kind == "string" then
		if utf8.len(value) == nil then
			return false, " : texte non UTF-8"
		end
		return true, nil
	elseif kind ~= "table" then
		return false, " : type non sérialisable (" .. typeof(value) .. ")"
	end
	if seen[value] then
		return false, " : référence cyclique"
	end
	if depth >= LIMITS.MaxDepth then
		return false, " : imbrication trop profonde"
	end
	seen[value] = true
	local hasText, numeric = false, 0
	for key, child in value do
		local keyType = type(key)
		if keyType == "string" then
			if utf8.len(key) == nil then
				seen[value] = nil
				return false, " : clé non UTF-8"
			end
			hasText = true
		elseif keyType == "number" then
			if key < 1 or key ~= math.floor(key) or key ~= key then
				seen[value] = nil
				return false, formatKey(key) .. " : clé numérique invalide"
			end
			numeric += 1
		else
			seen[value] = nil
			return false, " : clé de type " .. typeof(key)
		end
		local ok, reason = walk(child, depth + 1, seen)
		if not ok then
			seen[value] = nil
			return false, formatKey(key) .. (reason or "")
		end
	end
	seen[value] = nil
	if hasText and numeric > 0 then
		return false, " : table mixte (clés texte et numériques)"
	end
	for index = 1, numeric do
		if value[index] == nil then
			return false, " : tableau à trous"
		end
	end
	return true, nil
end

-- Valeur stockable telle quelle ? (ok, kind?, message?)
function DataStoreAdapter.checkValue(value: any): (boolean, ErrorKind?, string?)
	if value == nil then
		return false, "Invalid", "valeur : nil"
	end
	local ok, reason = walk(value, 0, {})
	if not ok then
		return false, "Invalid", "valeur" .. (reason or "")
	end
	local encoded, length = jsonLength(value)
	if not encoded then
		return false, "Invalid", "valeur : encodage JSON impossible (" .. tostring(length) .. ")"
	end
	if (length :: number) > LIMITS.ValueLength then
		return false, "TooLarge", string.format("valeur : %d caractères > %d", length :: number, LIMITS.ValueLength)
	end
	return true, nil, nil
end

local function checkUserIds(userIds: any): (boolean, ErrorKind?, string?)
	if type(userIds) ~= "table" then
		return false, "Invalid", "userIds : liste attendue"
	end
	local total = 0
	for key, id in userIds do
		total += 1
		if type(key) ~= "number" or not isFinite(id) or id ~= math.floor(id) then
			return false, "Invalid", "userIds : entier attendu (" .. tostring(id) .. ")"
		end
	end
	if total > LIMITS.UserIds then
		return false, "Invalid", string.format("userIds : %d > %d", total, LIMITS.UserIds)
	end
	for index = 1, total do
		if userIds[index] == nil then
			return false, "Invalid", "userIds : liste à trous"
		end
	end
	return true, nil, nil
end

local function checkMetadata(metadata: any): (boolean, ErrorKind?, string?)
	if type(metadata) ~= "table" then
		return false, "Invalid", "métadonnées : table attendue"
	end
	for key, value in metadata do
		if type(key) ~= "string" or key == "" or #key > LIMITS.MetadataKeyLength then
			return false, "Invalid", "métadonnées : clé invalide (" .. tostring(key) .. ")"
		end
		local kind = type(value)
		if kind == "string" then
			if utf8.len(value) == nil then
				return false, "Invalid", "métadonnées : texte non UTF-8 (" .. key .. ")"
			elseif #value > LIMITS.MetadataValueLength then
				return false, "TooLarge", "métadonnées : valeur trop longue (" .. key .. ")"
			end
		elseif kind == "number" then
			if not isFinite(value) then
				return false, "Invalid", "métadonnées : nombre non fini (" .. key .. ")"
			end
		elseif kind ~= "boolean" then
			return false, "Invalid", "métadonnées : valeur non simple (" .. key .. ")"
		end
	end
	local encoded, length = jsonLength(metadata)
	if not encoded then
		return false, "Invalid", "métadonnées : encodage JSON impossible"
	end
	if (length :: number) > LIMITS.MetadataLength then
		return false, "TooLarge", string.format("métadonnées : %d caractères > %d", length :: number, LIMITS.MetadataLength)
	end
	return true, nil, nil
end

-- Écriture complète (valeur + userIds + métadonnées) stockable ? (ok, kind?, message?)
function DataStoreAdapter.checkWrite(value: any, userIds: any, metadata: any): (boolean, ErrorKind?, string?)
	local ok, kind, reason = DataStoreAdapter.checkValue(value)
	if not ok then
		return false, kind, reason
	end
	ok, kind, reason = checkUserIds(userIds)
	if not ok then
		return false, kind, reason
	end
	return checkMetadata(metadata)
end

-- Convertit un DataStoreKeyInfo (ou son émulation) en table simple et indépendante.
function DataStoreAdapter.toKeyInfo(raw: any): KeyInfo?
	if raw == nil then
		return nil
	end
	local metadata: { [string]: any } = {}
	local userIds: { number } = {}
	local okMeta, rawMeta = pcall(function()
		return raw:GetMetadata()
	end)
	if okMeta and type(rawMeta) == "table" then
		metadata = table.clone(rawMeta)
	end
	local okIds, rawIds = pcall(function()
		return raw:GetUserIds()
	end)
	if okIds and type(rawIds) == "table" then
		userIds = table.clone(rawIds)
	end
	local okFields, version, created, updated = pcall(function()
		return raw.Version, raw.CreatedTime, raw.UpdatedTime
	end)
	return {
		version = if okFields and version ~= nil then tostring(version) else nil,
		createdTime = if okFields then tonumber(created) else nil,
		updatedTime = if okFields then tonumber(updated) else nil,
		userIds = userIds,
		metadata = metadata,
	}
end

-- Exécute fn(...) en interdisant tout yield (règle des transformations UpdateAsync).
-- Renvoie (true, résultats...) ou (false, message).
local function runPure(fn: (...any) -> ...any, ...: any): (boolean, ...any)
	local thread = coroutine.create(function(...: any)
		return xpcall(fn, function(err: any)
			return debug.traceback(tostring(err), 2)
		end, ...)
	end)
	local resumed = table.pack(coroutine.resume(thread, ...))
	if coroutine.status(thread) ~= "dead" then
		pcall(task.cancel, thread)
		return false, "la transformation a cédé (yield) : interdit dans UpdateAsync"
	end
	if not resumed[1] then
		return false, tostring(resumed[2])
	end
	if not resumed[2] then
		return false, tostring(resumed[3])
	end
	return true, table.unpack(resumed, 3, resumed.n)
end

--------------------------------------------------------------------------------
-- Verrou de session (convention de métadonnées partagée)
--------------------------------------------------------------------------------

local Lock = {}
Lock.IdKey = "lockId"
Lock.JobKey = "lockJob"
Lock.AtKey = "lockAt"

function Lock.make(id: string, jobId: string?, now: number): SessionLock
	return { id = id, job = jobId or "", at = now }
end

function Lock.read(metadata: { [string]: any }?): SessionLock?
	if type(metadata) ~= "table" then
		return nil
	end
	local id = metadata[Lock.IdKey]
	local at = metadata[Lock.AtKey]
	if type(id) ~= "string" or id == "" or not isFinite(at) then
		return nil
	end
	local job = metadata[Lock.JobKey]
	return { id = id, job = if type(job) == "string" then job else "", at = at }
end

function Lock.write(metadata: { [string]: any }?, lock: SessionLock?): { [string]: any }
	local copy: { [string]: any } = if type(metadata) == "table" then table.clone(metadata) else {}
	if lock then
		copy[Lock.IdKey] = lock.id
		copy[Lock.JobKey] = lock.job
		copy[Lock.AtKey] = lock.at
	else
		copy[Lock.IdKey] = nil
		copy[Lock.JobKey] = nil
		copy[Lock.AtKey] = nil
	end
	return copy
end

-- Verrou encore valide : posé il y a moins de `expirySeconds` (un horodatage aberrant dans le futur est ignoré).
function Lock.isActive(lock: SessionLock?, now: number, expirySeconds: number): boolean
	if lock == nil or not isFinite(now) or not isFinite(expirySeconds) then
		return false
	end
	if lock.at > now + expirySeconds then
		return false
	end
	return now - lock.at < expirySeconds
end

DataStoreAdapter.Lock = table.freeze(Lock)

--------------------------------------------------------------------------------
-- Instance
--------------------------------------------------------------------------------

local requestTypeCache: { [string]: { EnumItem } } = {}

local function resolveRequestType(modern: string, legacy: string): EnumItem?
	for _, name in { modern, legacy } do
		local ok, item = pcall(function()
			return (Enum.DataStoreRequestType :: any)[name]
		end)
		if ok and typeof(item) == "EnumItem" then
			return item
		end
	end
	return nil
end

-- Types de budget consommés par chaque opération (UpdateAsync consomme lecture ET écriture).
local function requestTypesFor(operation: Operation): { EnumItem }
	local cached = requestTypeCache[operation]
	if cached then
		return cached
	end
	local list: { EnumItem } = {}
	local function add(modern: string, legacy: string)
		local item = resolveRequestType(modern, legacy)
		if item then
			table.insert(list, item)
		end
	end
	if operation == "Get" then
		add("StandardRead", "GetAsync")
	elseif operation == "Update" then
		add("StandardRead", "GetAsync")
		add("StandardWrite", "SetIncrementAsync")
	else
		add("StandardRemove", "SetIncrementAsync")
	end
	requestTypeCache[operation] = list
	return list
end

local function makeResult(ok: boolean, value: any, keyInfo: KeyInfo?, aborted: boolean, err: AdapterError?): Result
	return { ok = ok, value = value, keyInfo = keyInfo, aborted = aborted, attempts = 0, error = err }
end

local Methods = {}
Methods.__index = Methods

local function getStore(self: any): (any, AdapterError?)
	if self._store ~= nil then
		return self._store, nil
	end
	local service = self._service
	if service == nil then
		local ok, result = pcall(function()
			return game:GetService("DataStoreService")
		end)
		if not ok then
			return nil, DataStoreAdapter.classifyError(result)
		end
		service = result
		self._service = service
	end
	local scope = self._scope
	local ok, store = pcall(function()
		if scope ~= nil then
			return service:GetDataStore(self.storeName, scope)
		end
		return service:GetDataStore(self.storeName)
	end)
	if not ok then
		return nil, DataStoreAdapter.classifyError(store)
	end
	self._store = store
	return store, nil
end

local function hasBudget(self: any, types: { EnumItem }): boolean
	local service = self._service
	if service == nil then
		return true
	end
	for _, requestType in types do
		local ok, budget = pcall(function()
			return service:GetRequestBudgetForRequestType(requestType)
		end)
		if ok and type(budget) == "number" and budget < 1 then
			return false
		end
	end
	return true
end

local function waitForBudget(self: any, types: { EnumItem }, timeout: number): boolean
	if hasBudget(self, types) then
		return true
	end
	self._stats.budgetWaits += 1
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		task.wait(math.min(self._budgetPoll, math.max(0, deadline - os.clock())))
		if hasBudget(self, types) then
			return true
		end
	end
	return false
end

-- File par clé : un seul thread de travail actif par clé, les autres attendent dans l'ordre d'arrivée.
local function acquire(self: any, key: string)
	local queue = self._queues[key]
	if queue == nil then
		self._queues[key] = {}
		return
	end
	self._stats.queued += 1
	table.insert(queue, coroutine.running())
	coroutine.yield()
end

local function release(self: any, key: string)
	local queue = self._queues[key]
	if queue == nil then
		return
	end
	while #queue > 0 do
		local nextThread = table.remove(queue, 1)
		if nextThread and coroutine.status(nextThread) == "suspended" then
			task.spawn(nextThread)
			return
		end
	end
	self._queues[key] = nil
end

local function attemptLoop(self: any, operation: Operation, options: CallOptions?, attempt: Attempt): Result
	local opts: CallOptions = options or {}
	local maxAttempts = self._maxAttempts
	if isFinite(opts.maxAttempts) then
		maxAttempts = math.clamp(math.floor(opts.maxAttempts :: number), 1, LIMITS.MaxAttempts)
	end
	local budgetTimeout = numberOr(opts.budgetTimeout, self._budgetTimeout, 0, 120)
	local types = requestTypesFor(operation)
	local attempts = 0
	local lastError: AdapterError? = nil
	while attempts < maxAttempts do
		local store, storeError = getStore(self)
		if store == nil then
			attempts += 1
			lastError = storeError or makeError("Unknown", nil, operation .. " : store indisponible")
			if not (lastError :: AdapterError).retryable or attempts >= maxAttempts then
				break
			end
			self._stats.retries += 1
			task.wait(DataStoreAdapter.backoffDelay(attempts, self._baseDelay, self._maxDelay, self._random))
			continue
		end
		if not waitForBudget(self, types, budgetTimeout) and not opts.proceedWithoutBudget then
			lastError = makeError("Budget", nil, operation .. " : budget de requêtes épuisé")
			break
		end
		attempts += 1
		self._stats.requests += 1
		local result, err = attempt(store)
		if result ~= nil then
			result.attempts = attempts
			return result
		end
		lastError = err
		if err == nil or not err.retryable or attempts >= maxAttempts then
			break
		end
		self._stats.retries += 1
		Log.debug("Data", operation, "nouvelle tentative", attempts, err.kind, err.message)
		task.wait(DataStoreAdapter.backoffDelay(attempts, self._baseDelay, self._maxDelay, self._random))
	end
	local failure = makeResult(false, nil, nil, false, lastError or makeError("Unknown", nil, operation .. " : échec"))
	failure.attempts = attempts
	return failure
end

-- Point d'entrée commun : validation de la clé, thread de travail (file par clé, tentatives), statistiques.
local function execute(self: any, operation: Operation, key: any, options: CallOptions?, attempt: Attempt): Result
	local stats: Stats = self._stats
	if type(key) ~= "string" or key == "" or #key > LIMITS.KeyLength then
		local invalid = makeResult(
			false,
			nil,
			nil,
			false,
			makeError("Invalid", if key == "" then 101 else 102, operation .. " : clé invalide (" .. tostring(key) .. ")")
		)
		stats.failed += 1
		stats.lastError = invalid.error
		return invalid
	end
	local caller = coroutine.running()
	local outcome: Result? = nil
	-- Le travail tourne dans son propre thread : si l'appelant est annulé, la clé est quand même libérée.
	task.spawn(function()
		acquire(self, key)
		local ok, result = pcall(attemptLoop, self, operation, options, attempt)
		release(self, key)
		local final: Result
		if ok then
			final = result
		else
			Log.warn("Data", "erreur interne de l'adaptateur", operation, key, result)
			final = makeResult(false, nil, nil, false, makeError("Unknown", nil, "erreur interne : " .. tostring(result)))
		end
		if final.ok then
			stats.succeeded += 1
			if final.aborted then
				stats.aborted += 1
			end
		else
			stats.failed += 1
			stats.lastError = final.error
		end
		outcome = final
		if coroutine.status(caller) == "suspended" then
			task.spawn(caller)
		end
	end)
	while outcome == nil do
		coroutine.yield()
	end
	return outcome :: Result
end

function Methods.Get(self: Adapter, key: string, options: CallOptions?): Result
	local internal = self :: any
	local bypassCache = options ~= nil and options.useCache == false
	return execute(internal, "Get", key, options, function(store: any): (Result?, AdapterError?)
		local getOptions: any = nil
		if bypassCache then
			if internal._getOptions == nil then
				local created, instance = pcall(function()
					local made = Instance.new("DataStoreGetOptions")
					made.UseCache = false
					return made
				end)
				if created then
					internal._getOptions = instance
				end
			end
			getOptions = internal._getOptions
		end
		local ok, value, info = pcall(function()
			if getOptions ~= nil then
				return store:GetAsync(key, getOptions)
			end
			return store:GetAsync(key)
		end)
		if not ok then
			return nil, DataStoreAdapter.classifyError(value)
		end
		return makeResult(true, value, DataStoreAdapter.toKeyInfo(info), false, nil), nil
	end)
end

function Methods.Update(self: Adapter, key: string, transform: Transform, options: CallOptions?): Result
	local internal = self :: any
	if type(transform) ~= "function" then
		local invalid = makeResult(false, nil, nil, false, makeError("Invalid", nil, "Update : transformation manquante"))
		internal._stats.failed += 1
		internal._stats.lastError = invalid.error
		return invalid
	end
	return execute(internal, "Update", key, options, function(store: any): (Result?, AdapterError?)
		local aborted = false
		local failureKind: ErrorKind? = nil
		local failureMessage = ""
		local seenInfo: KeyInfo? = nil
		local ok, value, info = pcall(function()
			return store:UpdateAsync(key, function(current: any, rawInfo: any): (any, any, any)
				aborted = false
				failureKind = nil
				local keyInfo = DataStoreAdapter.toKeyInfo(rawInfo)
				seenInfo = keyInfo
				local results = table.pack(runPure(transform, current, keyInfo))
				if not results[1] then
					aborted = true
					failureKind = "Transform"
					failureMessage = tostring(results[2])
					return nil
				end
				local newValue = results[2]
				if newValue == nil then
					aborted = true
					return nil
				end
				local userIds = if results[3] ~= nil then results[3] elseif keyInfo then keyInfo.userIds else {}
				local metadata = if results[4] ~= nil then results[4] elseif keyInfo then keyInfo.metadata else {}
				local valid, kind, reason = DataStoreAdapter.checkWrite(newValue, userIds, metadata)
				if not valid then
					aborted = true
					failureKind = kind or "Invalid"
					failureMessage = reason or "valeur refusée"
					return nil
				end
				return newValue, userIds, metadata
			end)
		end)
		if not ok then
			return nil, DataStoreAdapter.classifyError(value)
		end
		if failureKind ~= nil then
			-- Erreur de la transformation ou valeur refusée : définitif, rien n'a été écrit.
			return makeResult(false, nil, seenInfo, true, makeError(failureKind, nil, "Update : " .. failureMessage)), nil
		end
		if aborted then
			return makeResult(true, nil, seenInfo, true, nil), nil
		end
		return makeResult(true, value, DataStoreAdapter.toKeyInfo(info) or seenInfo, false, nil), nil
	end)
end

function Methods.Remove(self: Adapter, key: string, options: CallOptions?): Result
	return execute(self :: any, "Remove", key, options, function(store: any): (Result?, AdapterError?)
		local ok, value, info = pcall(function()
			return store:RemoveAsync(key)
		end)
		if not ok then
			return nil, DataStoreAdapter.classifyError(value)
		end
		return makeResult(true, value, DataStoreAdapter.toKeyInfo(info), false, nil), nil
	end)
end

function Methods.Probe(self: Adapter): Result
	return Methods.Get(self, DataStoreAdapter.PROBE_KEY, { maxAttempts = 2, budgetTimeout = 2 })
end

function Methods.GetStats(self: Adapter): Stats
	return table.clone((self :: any)._stats :: Stats)
end

function DataStoreAdapter.new(config: Config?): Adapter
	local cfg: Config = config or {}
	local baseName = cfg.storeName or DataStoreAdapter.DEFAULT_STORE
	local isStudio = cfg.isStudio
	if isStudio == nil then
		isStudio = game:GetService("RunService"):IsStudio()
	end
	local storeName = baseName
	if cfg.service == nil and cfg.isolateStudio ~= false and isStudio then
		storeName = baseName .. DataStoreAdapter.STUDIO_SUFFIX
	end
	assert(
		type(storeName) == "string" and #storeName > 0 and #storeName <= LIMITS.NameLength,
		"DataStoreAdapter : nom de store invalide (1..50 caractères, suffixe Studio compris)"
	)
	assert(
		cfg.scope == nil or (type(cfg.scope) == "string" and #cfg.scope > 0 and #cfg.scope <= LIMITS.NameLength),
		"DataStoreAdapter : scope invalide"
	)
	local baseDelay = numberOr(cfg.baseDelay, DEFAULTS.baseDelay, 0, 60)
	local self = {
		kind = cfg.kind or "DataStore",
		persistent = if cfg.persistent ~= nil then cfg.persistent else true,
		storeName = storeName,
		_scope = cfg.scope,
		_service = cfg.service,
		_store = nil :: any,
		_getOptions = nil :: any,
		_maxAttempts = math.floor(numberOr(cfg.maxAttempts, DEFAULTS.maxAttempts, 1, LIMITS.MaxAttempts)),
		_baseDelay = baseDelay,
		_maxDelay = numberOr(cfg.maxDelay, math.max(DEFAULTS.maxDelay, baseDelay), baseDelay, 300),
		_budgetTimeout = numberOr(cfg.budgetTimeout, DEFAULTS.budgetTimeout, 0, 120),
		_budgetPoll = numberOr(cfg.budgetPoll, DEFAULTS.budgetPoll, 0.01, 5),
		_random = Random.new(),
		_queues = {} :: { [string]: { thread } },
		_stats = {
			requests = 0,
			succeeded = 0,
			failed = 0,
			retries = 0,
			aborted = 0,
			budgetWaits = 0,
			queued = 0,
			lastError = nil,
		} :: Stats,
	}
	return (setmetatable(self, Methods) :: any) :: Adapter
end

return DataStoreAdapter
