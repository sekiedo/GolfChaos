--!strict
--[[
	Point d'entrée serveur UNIQUE (seul Script serveur du jeu).

	Charge chaque ModuleScript de Services/ puis démarre en deux phases :
	  1. Init()  — synchrone, dans l'ordre (Priority croissante puis nom) : créer l'état, brancher les remotes,
	               se connecter aux signaux des autres services. Ne pas faire d'attente longue ici.
	  2. Start() — dans un thread par service (task.spawn) : boucles, construction du monde, etc.
	Les noms en minuscules (init/start) sont aussi acceptés.

	Un service qui échoue est isolé (journalisé) : les autres continuent. L'état de démarrage est publié
	pour les tests : ServerScriptService.Server:GetAttribute("BootFailures") / ("Booted").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Log"))

type Entry = { name: string, module: any, priority: number }

local servicesFolder = script:WaitForChild("Services")
local entries: { Entry } = {}
local failures: { string } = {}

local function recordFailure(name: string, phase: string, err: any)
	table.insert(failures, name .. ":" .. phase)
	Log.error("Boot", string.format("%s (%s) : %s", name, phase, tostring(err)))
end

for _, module in servicesFolder:GetChildren() do
	if module:IsA("ModuleScript") then
		local ok, result = xpcall(require, debug.traceback, module)
		if ok then
			local priority = if type(result) == "table" and type(result.Priority) == "number" then result.Priority else 100
			table.insert(entries, { name = module.Name, module = result, priority = priority })
		else
			recordFailure(module.Name, "require", result)
		end
	end
end

table.sort(entries, function(a, b)
	if a.priority ~= b.priority then
		return a.priority < b.priority
	end
	return a.name < b.name
end)

local function lifecycle(entry: Entry, upper: string, lower: string): ((...any) -> ...any)?
	local module = entry.module
	if type(module) ~= "table" then
		return nil
	end
	local fn = module[upper] or module[lower]
	if type(fn) == "function" then
		return fn
	end
	return nil
end

for _, entry in entries do
	local init = lifecycle(entry, "Init", "init")
	if init then
		local ok, err = xpcall(init, debug.traceback)
		if not ok then
			recordFailure(entry.name, "Init", err)
		end
	end
end

for _, entry in entries do
	local start = lifecycle(entry, "Start", "start")
	if start then
		task.spawn(function()
			local ok, err = xpcall(start, debug.traceback)
			if not ok then
				recordFailure(entry.name, "Start", err)
				script:SetAttribute("BootFailures", table.concat(failures, ","))
			end
		end)
	end
end

script:SetAttribute("BootFailures", table.concat(failures, ","))
script:SetAttribute("Booted", true)
Log.info("Boot", string.format("%d services démarrés, %d échec(s)", #entries, #failures))
