--!strict
--[[
	Outils partagés par les écrans (aucun effet de bord au require).

	  Util.serverNow() -> number                   heure serveur (workspace:GetServerTimeNow)
	  Util.secondsLeft(finServeur) -> number?      secondes restantes (nil si 0 / invalide)
	  Util.formatClock(secondes) -> "1:05"
	  Util.rankText(rang) -> "1er" / "2e"…         (clés match.rank.*)
	  Util.scoreKey(coups, par) -> clé, vars       libellé birdie / par / bogey… (clés results.score.*)
	  Util.toParText(coups, par) -> "-1" / "E" / "+2"
	  Util.controller(nom) -> module?              contrôleur client chargé paresseusement (pcall)
	  Util.notify(clé, vars?, type?)               toast via NotificationController (s'il existe)
	  Util.gameState() -> Folder?                  dossier GameState sans attente bloquante longue
	  Util.attr(nom) -> any                        attribut de GameState (nil si indisponible)
	  Util.localPlayer() -> Player
	  Util.decodeSettings() -> { [string]: any }?  MatchSettings depuis l'attribut SettingsJson
	  Util.isShown(objet) -> boolean               visible jusqu'à un ScreenGui activé
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared.Locale)
local Log = require(Shared.Util.Log)

local Util = {}

function Util.serverNow(): number
	local ok, now = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok and type(now) == "number" then now else os.time()
end

function Util.secondsLeft(endsAt: any): number?
	if type(endsAt) ~= "number" or endsAt ~= endsAt or endsAt <= 0 then
		return nil
	end
	return math.max(0, endsAt - Util.serverNow())
end

function Util.formatClock(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

function Util.rankText(rank: any): string
	if type(rank) ~= "number" or rank < 1 then
		return Locale.t("ui.none")
	end
	local n = math.floor(rank)
	if n <= 3 then
		return Locale.t("match.rank." .. n)
	end
	return Locale.t("match.rank.n", { n = n })
end

-- Libellé du score d'un trou par rapport au par (golf).
function Util.scoreKey(strokes: number, par: number): (string, { [string]: any }?)
	if strokes == 1 then
		return "results.score.holeInOne", nil
	end
	local diff = strokes - par
	if diff <= -4 then
		return "results.score.condor", nil
	elseif diff == -3 then
		return "results.score.albatross", nil
	elseif diff == -2 then
		return "results.score.eagle", nil
	elseif diff == -1 then
		return "results.score.birdie", nil
	elseif diff == 0 then
		return "results.score.par", nil
	elseif diff == 1 then
		return "results.score.bogey", nil
	elseif diff == 2 then
		return "results.score.doubleBogey", nil
	end
	return "results.score.over", { n = diff }
end

function Util.toParText(strokes: number, par: number): string
	local diff = strokes - par
	if diff == 0 then
		return "E"
	elseif diff > 0 then
		return "+" .. diff
	end
	return tostring(diff)
end

local controllerCache: { [string]: any } = {}

function Util.controller(name: string): any
	local cached = controllerCache[name]
	if cached ~= nil then
		return if cached then cached else nil
	end
	local result: any = false
	local ui = script.Parent.Parent
	local client = ui and ui.Parent
	local folder = client and client:FindFirstChild("Controllers")
	local module = folder and folder:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, loaded = pcall(require, module)
		if ok and type(loaded) == "table" then
			result = loaded
		else
			Log.debug("UI", "contrôleur illisible :", name, loaded)
		end
	end
	controllerCache[name] = result
	return if result then result else nil
end

function Util.notify(key: string, vars: { [string]: any }?, kind: string?)
	local notifications = Util.controller("NotificationController")
	if notifications and type(notifications.NotifyKey) == "function" then
		pcall(notifications.NotifyKey, key, vars, kind or "info")
	end
end

function Util.gameState(): Folder?
	local folder = ReplicatedStorage:FindFirstChild("GameState")
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

function Util.attr(name: string): any
	local folder = Util.gameState()
	return if folder then folder:GetAttribute(name) else nil
end

function Util.localPlayer(): Player
	return Players.LocalPlayer
end

function Util.decodeSettings(): { [string]: any }?
	local json = Util.attr("SettingsJson")
	if type(json) ~= "string" or json == "" then
		return nil
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
	if ok and type(decoded) == "table" then
		return decoded
	end
	return nil
end

function Util.isShown(object: Instance): boolean
	local current: Instance? = object
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		elseif current:IsA("LayerCollector") then
			return current.Enabled
		end
		current = current.Parent
	end
	return false
end

-- Nom de joueur affichable (DisplayName si présent sur le serveur, sinon le nom transmis).
function Util.playerName(userId: any, fallback: any): string
	if type(userId) == "number" then
		local player = Players:GetPlayerByUserId(userId)
		if player then
			return player.DisplayName
		end
	end
	return if type(fallback) == "string" and fallback ~= "" then fallback else "?"
end

return Util
