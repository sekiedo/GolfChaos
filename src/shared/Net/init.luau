--!strict
--[[
	Net : API réseau unique et typée. Aucun autre module ne crée de RemoteEvent.

	DÉFINITIONS — un fichier par fonctionnalité dans Net/Remotes/*.luau :
	    return {
	        ["Golf.Shoot"] = { kind = "Event", dir = "ToServer", args = { "integer", "Vector3", "number", "number?" }, rate = 4, burst = 3 },
	        ["Match.Event"] = { kind = "Event", dir = "ToClient" },
	    }
	  kind  "Event" (RemoteEvent fiable) | "Unreliable" (UnreliableRemoteEvent) | "Function" (RemoteFunction, client -> serveur uniquement)
	  dir   "ToServer" | "ToClient" | "Both"
	  args  spécification des arguments client -> serveur (voir Util/Validate.checkArgs). Vérifiée AVANT
	        le handler ; les arguments surnuméraires sont rejetés. Obligatoire pour dir ToServer/Both.
	  rate  appels/seconde autorisés par joueur (seau à jetons), défaut 10 ; burst = capacité, défaut = rate.

	SERVEUR
	    Net.on(name, function(player, ...) end)            -- un seul handler par remote
	    Net.onInvoke(name, function(player, ...) return ... end)
	    Net.fire(name, player, ...)   Net.fireAll(name, ...)   Net.fireList(name, players, ...)
	    Net.fireAllExcept(name, player, ...)
	    Net.getStats() -> { [name] = { accepted, rejectedRate, rejectedArgs, rejectedDir, errors } }
	    Net.resetStats()
	CLIENT
	    Net.send(name, ...)           Net.listen(name, function(...) end) -> RBXScriptConnection
	    Net.invoke(name, ...) -> ...  (RemoteFunction ; à n'utiliser que pour des requêtes courtes)

	Le client n'envoie que des INTENTIONS ; le serveur décide de tout (voir docs/ARCHITECTURE.md §Sécurité).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Validate = require(script.Parent.Util.Validate)
local Log = require(script.Parent.Util.Log)

export type RemoteKind = "Event" | "Unreliable" | "Function"
export type RemoteDirection = "ToServer" | "ToClient" | "Both"
export type RemoteDef = {
	kind: RemoteKind,
	dir: RemoteDirection,
	args: { string }?,
	rate: number?,
	burst: number?,
}

type Stats = { accepted: number, rejectedRate: number, rejectedArgs: number, rejectedDir: number, errors: number }

local FOLDER_NAME = "Remotes"
-- En mode Édition de Studio, IsServer() et IsClient() sont tous deux vrais : Net se comporte alors comme
-- un client inerte (aucun remote créé), ce qui permet de require les modules dans les tests unitaires.
local IS_SERVER = RunService:IsServer() and not RunService:IsClient()

local Net = {}

-- Collecte des définitions ------------------------------------------------------
local definitions: { [string]: RemoteDef } = {}
do
	local remotesFolder = script:FindFirstChild("Remotes")
	if remotesFolder then
		for _, module in remotesFolder:GetChildren() do
			if module:IsA("ModuleScript") then
				local ok, result = pcall(require, module)
				if not ok or type(result) ~= "table" then
					Log.error("Net", "définitions illisibles :", module.Name, result)
					continue
				end
				for name, def in result :: { [string]: RemoteDef } do
					if definitions[name] then
						Log.error("Net", "remote défini deux fois :", name, "(" .. module.Name .. ")")
					else
						definitions[name] = def
					end
				end
			end
		end
	end
end

local function getDef(name: string): RemoteDef
	local def = definitions[name]
	if not def then
		error("Remote inconnu : " .. tostring(name), 3)
	end
	return def
end

local function className(kind: RemoteKind): string
	if kind == "Unreliable" then
		return "UnreliableRemoteEvent"
	elseif kind == "Function" then
		return "RemoteFunction"
	end
	return "RemoteEvent"
end

function Net.getDefinitions(): { [string]: RemoteDef }
	return table.clone(definitions)
end

--------------------------------------------------------------------------------
-- SERVEUR
--------------------------------------------------------------------------------
if IS_SERVER then
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	local remotes: { [string]: Instance } = {}
	for name, def in definitions do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new(className(def.kind))
			remote.Name = name
			remote.Parent = folder
		end
		remotes[name] = remote :: Instance
	end

	local stats: { [string]: Stats } = {}
	local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}
	local handled: { [string]: boolean } = {}

	local function stat(name: string): Stats
		local entry = stats[name]
		if not entry then
			entry = { accepted = 0, rejectedRate = 0, rejectedArgs = 0, rejectedDir = 0, errors = 0 }
			stats[name] = entry
		end
		return entry
	end

	local function takeToken(player: Player, name: string, def: RemoteDef): boolean
		local rate = def.rate or 10
		local burst = def.burst or rate
		local perPlayer = buckets[player]
		if not perPlayer then
			perPlayer = {}
			buckets[player] = perPlayer
		end
		local now = os.clock()
		local bucket = perPlayer[name]
		if not bucket then
			bucket = { tokens = burst, last = now }
			perPlayer[name] = bucket
		end
		bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.last) * rate)
		bucket.last = now
		if bucket.tokens < 1 then
			return false
		end
		bucket.tokens -= 1
		return true
	end

	-- Contrôle commun à tous les appels client -> serveur. Retourne true si l'appel peut être traité.
	local function gate(player: Player, name: string, def: RemoteDef, ...: any): boolean
		local entry = stat(name)
		if def.dir == "ToClient" then
			entry.rejectedDir += 1
			return false
		end
		if not takeToken(player, name, def) then
			entry.rejectedRate += 1
			return false
		end
		local spec = def.args
		if not spec then
			-- Un remote client -> serveur sans spécification est une erreur de conception.
			entry.rejectedArgs += 1
			Log.warn("Net", "remote sans spécification d'arguments refusé :", name)
			return false
		end
		local ok, reason = Validate.checkArgs(spec, ...)
		if not ok then
			entry.rejectedArgs += 1
			Log.debug("Net", "arguments rejetés", name, player.Name, reason)
			return false
		end
		entry.accepted += 1
		return true
	end

	function Net.on(name: string, handler: (Player, ...any) -> ())
		local def = getDef(name)
		assert(def.kind ~= "Function", "Net.on : utiliser Net.onInvoke pour " .. name)
		assert(not handled[name], "Net.on : handler déjà enregistré pour " .. name)
		handled[name] = true
		local remote = remotes[name] :: any
		remote.OnServerEvent:Connect(function(player: Player, ...: any)
			if not gate(player, name, def, ...) then
				return
			end
			local ok, err = xpcall(handler, debug.traceback, player, ...)
			if not ok then
				stat(name).errors += 1
				Log.error("Net", "handler " .. name .. " :", err)
			end
		end)
	end

	function Net.onInvoke(name: string, handler: (Player, ...any) -> ...any)
		local def = getDef(name)
		assert(def.kind == "Function", "Net.onInvoke : " .. name .. " n'est pas une Function")
		assert(not handled[name], "Net.onInvoke : handler déjà enregistré pour " .. name)
		handled[name] = true
		local remote = remotes[name] :: any
		remote.OnServerInvoke = function(player: Player, ...: any)
			if not gate(player, name, def, ...) then
				return nil
			end
			local results = table.pack(xpcall(handler, debug.traceback, player, ...))
			if not results[1] then
				stat(name).errors += 1
				Log.error("Net", "invoke " .. name .. " :", results[2])
				return nil
			end
			return table.unpack(results, 2, results.n)
		end
	end

	local function checkOutgoing(name: string): any
		local def = getDef(name)
		assert(def.kind ~= "Function", "Le serveur n'invoque jamais le client (" .. name .. ")")
		assert(def.dir ~= "ToServer", "Remote " .. name .. " est client -> serveur uniquement")
		return remotes[name]
	end

	function Net.fire(name: string, player: Player, ...: any)
		local remote = checkOutgoing(name)
		if player.Parent == Players then
			remote:FireClient(player, ...)
		end
	end

	function Net.fireAll(name: string, ...: any)
		checkOutgoing(name):FireAllClients(...)
	end

	function Net.fireList(name: string, players: { Player }, ...: any)
		local remote = checkOutgoing(name)
		for _, player in players do
			if player.Parent == Players then
				remote:FireClient(player, ...)
			end
		end
	end

	function Net.fireAllExcept(name: string, excluded: Player, ...: any)
		local remote = checkOutgoing(name)
		for _, player in Players:GetPlayers() do
			if player ~= excluded then
				remote:FireClient(player, ...)
			end
		end
	end

	function Net.getStats(): { [string]: Stats }
		local copy = {}
		for name, entry in stats do
			copy[name] = table.clone(entry)
		end
		return copy
	end

	function Net.resetStats()
		table.clear(stats)
	end

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)

	-- Remotes client -> serveur sans handler : on compte tout de même les appels (détection d'abus).
	task.defer(function()
		for name, def in definitions do
			if not handled[name] and def.kind ~= "Function" and def.dir ~= "ToClient" then
				(remotes[name] :: any).OnServerEvent:Connect(function(player: Player, ...: any)
					if not handled[name] then
						gate(player, name, def, ...)
					end
				end)
			end
		end
	end)
else
	--------------------------------------------------------------------------------
	-- CLIENT
	--------------------------------------------------------------------------------
	local folder: Instance? = nil
	local cache: { [string]: Instance } = {}

	local function getRemote(name: string): any
		getDef(name)
		local cached = cache[name]
		if cached then
			return cached
		end
		if not folder then
			folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 60)
			if not folder then
				error("Net : dossier Remotes introuvable (serveur non démarré ?)")
			end
		end
		local remote = (folder :: Instance):WaitForChild(name, 30)
		if not remote then
			error("Net : remote introuvable côté client : " .. name)
		end
		cache[name] = remote
		return remote
	end

	function Net.send(name: string, ...: any)
		local def = getDef(name)
		assert(def.dir ~= "ToClient", "Remote " .. name .. " est serveur -> client uniquement")
		assert(def.kind ~= "Function", "Utiliser Net.invoke pour " .. name)
		getRemote(name):FireServer(...)
	end

	function Net.listen(name: string, handler: (...any) -> ()): RBXScriptConnection
		local def = getDef(name)
		assert(def.dir ~= "ToServer", "Remote " .. name .. " est client -> serveur uniquement")
		return getRemote(name).OnClientEvent:Connect(function(...)
			local ok, err = xpcall(handler, debug.traceback, ...)
			if not ok then
				Log.error("Net", "écouteur " .. name .. " :", err)
			end
		end)
	end

	function Net.invoke(name: string, ...: any): ...any
		local def = getDef(name)
		assert(def.kind == "Function", "Net.invoke : " .. name .. " n'est pas une Function")
		return getRemote(name):InvokeServer(...)
	end
end

return Net
