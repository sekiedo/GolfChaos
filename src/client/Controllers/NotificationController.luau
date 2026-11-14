--!strict
--[[
	NotificationController — notifications courtes (toasts) en haut de l'écran.

	  NotificationController.Notify(texte, type?, opts?)          texte déjà traduit
	  NotificationController.NotifyKey(clé, vars?, type?, opts?)  clé Locale (préféré)
	  opts = { title: string?, duration: number?, sound: string? ("" = muet) }
	  Types : "info" | "success" | "warn" | "error" | "hit" | "achievement" | "coins"

	Sources réseau écoutées (si les remotes existent) : Core.Notify (texte, type), Core.NotifyKey (clé, vars, type?),
	Match.Announce (clé, vars), Progress.AchievementCompleted (id, pièces).
	File : au plus MAX_VISIBLE toasts affichés, les suivants attendent ; un message identique encore affiché est
	regroupé (« ×2 ») au lieu d'être répété ; un message identique déjà affiché il y a moins de DEDUPE_WINDOW s
	est ignoré.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Log = require(Shared.Util.Log)
local Locale = require(Shared.Locale)

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Toast = require(UI.Components.Toast)

local NotificationController = {}
NotificationController.Priority = 60

type Options = { title: string?, duration: number?, sound: string? }
type Request = { text: string, kind: string, title: string?, duration: number, sound: string? }
type Active = { text: string, toast: Toast.ToastApi, count: number, token: number, duration: number }

local MAX_VISIBLE = 3
local MAX_QUEUE = 12
local DEFAULT_DURATION = 3.5
local MIN_DURATION = 1.5
local MAX_DURATION = 10
local DEDUPE_WINDOW = 2

local KIND_SOUNDS: { [string]: string } = {
	error = "ui_error",
	achievement = "coins_reward",
	coins = "coins_reward",
}

local KNOWN_KINDS: { [string]: boolean } = {
	info = true,
	success = true,
	warn = true,
	error = true,
	hit = true,
	achievement = true,
	coins = true,
}

local gui: ScreenGui? = nil
local stack: Frame? = nil
local queue: { Request } = {}
local active: { Active } = {}
local recent: { [string]: number } = {}
local order = 0

local function normalizeKind(kind: any): string
	if type(kind) == "string" and KNOWN_KINDS[kind] then
		return kind
	end
	return "info"
end

local function ensureGui(): Frame?
	if stack and stack.Parent then
		return stack
	end
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "GC_Notifications"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = Theme.Layers.Notifications
	screen.Parent = playerGui
	gui = screen

	local frame = Instance.new("Frame")
	frame.Name = "Pile"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 56)
	frame.Size = UDim2.new(0.9, 0, 1, -120)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(440, math.huge)
	limit.Parent = frame
	Base.list(frame, Enum.FillDirection.Vertical, Theme.Spacing.S, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	frame.Parent = screen
	local scale = Instance.new("UIScale")
	scale.Scale = Theme.getScale()
	scale.Parent = frame
	Theme.Changed:Connect(function(what: any)
		if what == "layout" then
			scale.Scale = Theme.getScale()
		end
	end)
	stack = frame
	return frame
end

local pump: () -> ()

local function removeActive(entry: Active)
	local index = table.find(active, entry)
	if index then
		table.remove(active, index)
	end
	entry.toast.Dismiss()
	task.defer(pump)
end

local function armTimer(entry: Active)
	entry.token += 1
	local token = entry.token
	task.delay(entry.duration, function()
		if entry.token == token then
			removeActive(entry)
		end
	end)
end

pump = function()
	local parent = ensureGui()
	if not parent then
		return
	end
	while #active < MAX_VISIBLE and #queue > 0 do
		local request = table.remove(queue, 1) :: Request
		order += 1
		local toast = Toast.new({
			text = request.text,
			kind = request.kind,
			title = request.title,
			layoutOrder = order,
			parent = parent,
		})
		toast.Show()
		local sound = request.sound
		if sound == nil then
			sound = KIND_SOUNDS[request.kind]
		end
		if sound and sound ~= "" then
			Base.playSound(sound)
		end
		local entry: Active = { text = request.text, toast = toast, count = 1, token = 0, duration = request.duration }
		table.insert(active, entry)
		armTimer(entry)
	end
end

function NotificationController.Notify(text: any, kind: any, opts: Options?)
	if type(text) ~= "string" or text == "" then
		return
	end
	text = string.sub(text, 1, 300)
	local options = opts or {}
	local now = os.clock()

	-- Regroupement : même texte encore affiché -> compteur et minuterie relancée.
	for _, entry in active do
		if entry.text == text then
			entry.count += 1
			entry.toast.SetCount(entry.count)
			armTimer(entry)
			recent[text] = now
			return
		end
	end
	-- Déduplication : même texte affiché très récemment ou déjà en attente.
	local last = recent[text]
	if last and now - last < DEDUPE_WINDOW then
		return
	end
	for _, request in queue do
		if request.text == text then
			return
		end
	end
	recent[text] = now
	if #queue >= MAX_QUEUE then
		table.remove(queue, 1)
	end
	local duration = if type(options.duration) == "number" and options.duration == options.duration
		then math.clamp(options.duration, MIN_DURATION, MAX_DURATION)
		else DEFAULT_DURATION + math.min(#text / 40, 3)
	table.insert(queue, {
		text = text,
		kind = normalizeKind(kind),
		title = options.title,
		duration = duration,
		sound = options.sound,
	})
	pump()
end

function NotificationController.NotifyKey(key: any, vars: any, kind: any, opts: Options?)
	if type(key) ~= "string" or key == "" then
		return
	end
	local variables = if type(vars) == "table" then vars else nil
	NotificationController.Notify(Locale.t(key, variables), kind, opts)
end

function NotificationController.Clear()
	table.clear(queue)
	for _, entry in table.clone(active) do
		removeActive(entry)
	end
end

local function listen(name: string, handler: (...any) -> ())
	if not Net.getDefinitions()[name] then
		return
	end
	local ok, err = pcall(Net.listen, name, handler)
	if not ok then
		Log.warn("Notify", "écoute impossible :", name, err)
	end
end

-- Annonces : type déduit de la clé (bonus et victoires en succès, avertissements en alerte).
local function announceKind(key: string): string
	if string.find(key, "holeInOne", 1, true) or string.find(key, "winner", 1, true) or string.find(key, "soloBest", 1, true) then
		return "achievement"
	elseif string.find(key, "birdie", 1, true) or string.find(key, "eagle", 1, true) or string.find(key, "albatross", 1, true)
		or string.find(key, "teamPoint", 1, true) or string.find(key, "firstFinish", 1, true) or string.find(key, "longShot", 1, true) then
		return "success"
	elseif string.find(key, "afk", 1, true) or string.find(key, "Warning", 1, true) or string.find(key, "overtime", 1, true)
		or string.find(key, "timeUp", 1, true) or string.find(key, "aborted", 1, true) or string.find(key, "strokeCap", 1, true) then
		return "warn"
	end
	return "info"
end

function NotificationController.Init() end

function NotificationController.Start()
	listen("Core.Notify", function(text: any, kind: any)
		NotificationController.Notify(text, kind)
	end)
	listen("Core.NotifyKey", function(key: any, vars: any, kind: any)
		NotificationController.NotifyKey(key, vars, kind)
	end)
	listen("Match.Announce", function(key: any, vars: any)
		if type(key) == "string" then
			NotificationController.NotifyKey(key, vars, announceKind(key))
		end
	end)
	listen("Progress.AchievementCompleted", function(achievementId: any, coins: any)
		if type(achievementId) ~= "string" then
			return
		end
		local nameKey = "ach." .. achievementId .. ".name"
		local name = if Locale.has(nameKey) or Locale.has(nameKey, "fr") then Locale.t(nameKey) else achievementId
		local amount = if type(coins) == "number" and coins == coins then math.floor(coins) else 0
		local text = if amount > 0
			then Locale.t("ui.notify.achievement", { name = name, coins = amount })
			else Locale.t("ui.notify.achievementNoCoins", { name = name })
		NotificationController.Notify(text, "achievement", { title = Locale.t("ui.notify.achievementTitle"), duration = 5 })
	end)
	-- Nettoyage périodique de la table de déduplication.
	task.spawn(function()
		while true do
			task.wait(30)
			local now = os.clock()
			for text, at in recent do
				if now - at > 30 then
					recent[text] = nil
				end
			end
		end
	end)
	local _ = gui
end

return NotificationController
