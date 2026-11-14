--!strict
--[[
	MemoryAdapter — magasin de profils EN MÉMOIRE, NON PERSISTANT. SERVEUR uniquement.

	Utilisé quand le DataStore réel n'est pas accessible (Studio sans accès aux API, place non publiée) et dans
	les tests. Les données disparaissent à l'arrêt du serveur : l'appelant doit le signaler honnêtement
	(attribut joueur DataStatus = "Memory", GameState.PersistentData = false).

	  local adapter = MemoryAdapter.new()          -- même interface que DataStoreAdapter (Get/Update/Remove/Probe)
	  adapter.kind = "Memory", adapter.persistent = false

	Réalisé comme une émulation minimale de DataStoreService injectée dans DataStoreAdapter : files par clé,
	vérification des valeurs, verrou de session et transformations se comportent donc exactement comme avec le
	vrai service. Les valeurs sont copiées à l'écriture et à la lecture (comme une sérialisation).

	  MemoryAdapter.newService(options?) -> service émulé (tests : options.failWith = fonction(operation, key)
	                                         qui renvoie un message d'erreur à lever, ou nil)
]]

local DataStoreAdapter = require(script.Parent.DataStoreAdapter)

export type Adapter = DataStoreAdapter.Adapter
export type ServiceOptions = {
	failWith: ((operation: string, key: string) -> string?)?,
	now: (() -> number)?, -- millisecondes Unix (tests)
}

type Entry = { value: any, userIds: { number }, metadata: { [string]: any }, version: number, created: number, updated: number }

local MemoryAdapter = {}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = deepCopy(item)
	end
	return copy
end

-- Émulation de DataStoreKeyInfo (lue par DataStoreAdapter.toKeyInfo).
local function keyInfo(entry: Entry): any
	return {
		Version = tostring(entry.version),
		CreatedTime = entry.created,
		UpdatedTime = entry.updated,
		GetUserIds = function(_self: any)
			return table.clone(entry.userIds)
		end,
		GetMetadata = function(_self: any)
			return deepCopy(entry.metadata)
		end,
	}
end

function MemoryAdapter.newService(options: ServiceOptions?): any
	local opts: ServiceOptions = options or {}
	local now = opts.now or function(): number
		return os.time() * 1000
	end
	local stores: { [string]: { [string]: Entry } } = {}

	local function fail(operation: string, key: string)
		local message = if opts.failWith then opts.failWith(operation, key) else nil
		if message then
			error(message, 0)
		end
	end

	local service = {}

	function service.GetRequestBudgetForRequestType(_self: any, _requestType: any): number
		return 1000
	end

	function service.GetDataStore(_self: any, name: string, scope: string?): any
		local id = name .. "/" .. (scope or "global")
		local entries = stores[id]
		if entries == nil then
			entries = {}
			stores[id] = entries
		end
		local data = entries :: { [string]: Entry }
		local store = {}

		function store.GetAsync(_store: any, key: string, _getOptions: any?): (any, any)
			fail("Get", key)
			local entry = data[key]
			if entry == nil then
				return nil, nil
			end
			return deepCopy(entry.value), keyInfo(entry)
		end

		function store.UpdateAsync(_store: any, key: string, transform: (any, any) -> (any, any, any)): (any, any)
			fail("Update", key)
			local entry = data[key]
			local value, userIds, metadata = transform(
				if entry then deepCopy(entry.value) else nil,
				if entry then keyInfo(entry) else nil
			)
			if value == nil then
				return nil, nil
			end
			local time = now()
			local updated: Entry = {
				value = deepCopy(value),
				userIds = if type(userIds) == "table" then table.clone(userIds) else {},
				metadata = if type(metadata) == "table" then deepCopy(metadata) else {},
				version = if entry then entry.version + 1 else 1,
				created = if entry then entry.created else time,
				updated = time,
			}
			data[key] = updated
			return deepCopy(updated.value), keyInfo(updated)
		end

		function store.RemoveAsync(_store: any, key: string): (any, any)
			fail("Remove", key)
			local entry = data[key]
			if entry == nil then
				return nil, nil
			end
			data[key] = nil
			return deepCopy(entry.value), keyInfo(entry)
		end

		return store
	end

	return service
end

function MemoryAdapter.new(config: DataStoreAdapter.Config?, options: ServiceOptions?): Adapter
	local cfg: DataStoreAdapter.Config = if config then table.clone(config) else {}
	cfg.service = cfg.service or MemoryAdapter.newService(options)
	cfg.kind = "Memory"
	cfg.persistent = false
	return DataStoreAdapter.new(cfg)
end

return MemoryAdapter
