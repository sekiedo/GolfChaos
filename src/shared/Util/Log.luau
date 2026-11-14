--!strict
--[[
	Log : journal homogène avec étiquette de module.
	  Log.info("Match", "trou chargé", holeId)
	  Log.warn("Net", "requête rejetée", player.Name)
	  Log.error("Boot", "échec", err)        -- n'interrompt pas l'exécution
	  Log.debug("Ball", ...)                 -- affiché seulement si Log.setDebug(true)
	Les erreurs sont aussi comptées (Log.getErrorCount()) pour les tests d'intégration, et les derniers
	avertissements/erreurs sont gardés en mémoire (Log.getRecent(n?, niveau?)) pour les outils de test Studio.
]]

local RunService = game:GetService("RunService")

local Log = {}

export type Entry = { at: number, level: "warn" | "error", text: string }

local RECENT_MAX = 200

local debugEnabled = false
local errorCount = 0
local recent: { Entry } = {}
local side = if RunService:IsServer() and not RunService:IsClient() then "S" elseif RunService:IsClient() then "C" else "?"

local function remember(level: "warn" | "error", text: string)
	table.insert(recent, { at = os.clock(), level = level, text = text })
	if #recent > RECENT_MAX then
		table.remove(recent, 1)
	end
end

local function format(tag: string, ...: any): string
	local parts = table.create(select("#", ...))
	for index = 1, select("#", ...) do
		parts[index] = tostring((select(index, ...)))
	end
	return string.format("[GolfChaos:%s][%s] %s", side, tag, table.concat(parts, " "))
end

function Log.setDebug(enabled: boolean)
	debugEnabled = enabled
end

function Log.debug(tag: string, ...: any)
	if debugEnabled then
		print(format(tag, ...))
	end
end

function Log.info(tag: string, ...: any)
	print(format(tag, ...))
end

function Log.warn(tag: string, ...: any)
	local text = format(tag, ...)
	remember("warn", text)
	warn(text)
end

function Log.error(tag: string, ...: any)
	errorCount += 1
	local text = format(tag, "ERREUR", ...)
	remember("error", text)
	warn(text)
end

function Log.getErrorCount(): number
	return errorCount
end

-- Derniers messages (du plus ancien au plus récent) ; level = "error" pour ne garder que les erreurs.
function Log.getRecent(count: number?, level: ("warn" | "error")?): { Entry }
	local wanted = math.clamp(math.floor(count or 50), 1, RECENT_MAX)
	local out: { Entry } = {}
	for index = #recent, 1, -1 do
		local entry = recent[index]
		if level == nil or entry.level == level then
			table.insert(out, 1, table.clone(entry))
			if #out >= wanted then
				break
			end
		end
	end
	return out
end

return Log
