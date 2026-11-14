--!strict
--[[
	Services : accès paresseux aux services voisins (ServerScriptService.Server.Services.<Nom>).

	Remplace les copies locales de `getService` / `optionalService` / `callService` / `connect` qui existaient dans
	chaque service. Règles conservées :
	  - aucun `require` d'un autre service au chargement d'un module : la recherche se fait à l'appel, donc sans cycle ;
	  - un service absent ou en erreur vaut nil (dégradation propre) ; l'échec est mémorisé puis retenté après
	    `retryTime` secondes (5 par défaut), ce qui permet de livrer les systèmes un par un ;
	  - seul un module qui retourne une table est considéré comme un service.

	Ce module est dans Server/Util et NON dans Server/Services : le démarrage (init.server.luau) charge tout
	ModuleScript de Services/ comme un service.

	Usage dans un service :
	    local Services = require(script.Parent.Parent.Util.Services)
	    local services = Services.scope("Match")          -- étiquette de journal
	    local Ball = services.get("BallService")           -- any? (nil si absent)
	    local ok, result = services.call("BallService", "RemoveBall", player)   -- (false, nil) si absent / erreur
	    services.connect("BallService", "Holed", onHoled)  -- true si le signal existe ; le gestionnaire est protégé

	Tests : Services.new({ folder, retryTime, clock, loader }) crée un localisateur isolé.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Log"))

export type Scope = {
	get: (name: string) -> any?,
	call: (name: string, method: string, ...any) -> (boolean, any),
	connect: (serviceName: string, signalName: string, handler: (...any) -> ()) -> boolean,
}

export type Locator = {
	get: (name: string) -> any?,
	scope: (tag: string) -> Scope,
	reset: () -> (),
}

export type Options = {
	folder: Instance?, -- dossier des services (défaut : Server.Services)
	retryTime: number?, -- délai avant un nouvel essai après un échec (s)
	clock: (() -> number)?, -- horloge injectable (tests)
	loader: ((ModuleScript) -> any)?, -- chargeur injectable (tests) ; défaut : require
}

type CacheEntry = { module: any?, checkedAt: number }

local DEFAULT_RETRY_TIME = 5

local Services = {}

function Services.new(options: Options?): Locator
	local opts: Options = options or {}
	local retryTime = opts.retryTime or DEFAULT_RETRY_TIME
	local clock = opts.clock or os.clock
	local loader: (ModuleScript) -> any = opts.loader or (require :: any)
	local cache: { [string]: CacheEntry } = {}

	local function folder(): Instance?
		if opts.folder then
			return opts.folder
		end
		local serverRoot = script.Parent and script.Parent.Parent
		return serverRoot and serverRoot:FindFirstChild("Services")
	end

	local function get(name: string): any?
		local entry = cache[name]
		local time = clock()
		if entry and (entry.module ~= nil or time - entry.checkedAt < retryTime) then
			return entry.module
		end
		local root = folder()
		local module = root and root:FindFirstChild(name)
		local loaded: any? = nil
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(loader, module)
			if ok and type(result) == "table" then
				loaded = result
			end
		end
		cache[name] = { module = loaded, checkedAt = time }
		return loaded
	end

	local function scope(tag: string): Scope
		-- service.method(...) protégé : (false, nil) si le service ou la méthode manque, ou si l'appel échoue (journalisé).
		local function call(name: string, method: string, ...: any): (boolean, any)
			local service = get(name)
			local fn = service and service[method]
			if type(fn) ~= "function" then
				return false, nil
			end
			local ok, result = pcall(fn, ...)
			if not ok then
				Log.warn(tag, name .. "." .. method .. " :", result)
				return false, nil
			end
			return true, result
		end

		-- Abonnement à un Signal d'un autre service ; une erreur du gestionnaire est journalisée sans casser l'émetteur.
		local function connect(serviceName: string, signalName: string, handler: (...any) -> ()): boolean
			local service = get(serviceName)
			local signal = service and service[signalName]
			if type(signal) == "table" and type(signal.Connect) == "function" then
				signal:Connect(function(...)
					local ok, err = pcall(handler, ...)
					if not ok then
						Log.error(tag, serviceName .. "." .. signalName, err)
					end
				end)
				return true
			end
			Log.debug(tag, "signal absent :", serviceName .. "." .. signalName)
			return false
		end

		return { get = get, call = call, connect = connect }
	end

	local function reset()
		table.clear(cache)
	end

	return { get = get, scope = scope, reset = reset }
end

-- Localisateur par défaut, partagé par tous les services (un seul cache).
local default = Services.new()

Services.get = default.get
Services.scope = default.scope
Services.reset = default.reset

return Services
