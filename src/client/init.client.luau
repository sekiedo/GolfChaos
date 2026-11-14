--!strict
--[[
	Point d'entrée client UNIQUE (seul LocalScript du jeu).

	Charge chaque ModuleScript de Controllers/ puis démarre en deux phases (comme le serveur) :
	  1. Init()  — synchrone, ordre Priority croissante puis nom.
	  2. Start() — un thread par contrôleur.
	Les contrôleurs communiquent par require explicite et Signals ; jamais par _G.
	Statut publié pour les tests : script:GetAttribute("Booted") / ("BootFailures").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Log"))

type Entry = { name: string, module: any, priority: number }

local controllersFolder = script:WaitForChild("Controllers")
local entries: { Entry } = {}
local failures: { string } = {}

local function recordFailure(name: string, phase: string, err: any)
	table.insert(failures, name .. ":" .. phase)
	Log.error("Boot", string.format("%s (%s) : %s", name, phase, tostring(err)))
end

for _, module in controllersFolder:GetChildren() do
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
Log.info("Boot", string.format("%d contrôleurs démarrés, %d échec(s)", #entries, #failures))
