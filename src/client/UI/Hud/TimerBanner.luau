--!strict
--[[
	Hud/TimerBanner — chronomètre de phase (haut centre) et bandeau de prolongation.

	  local timer = TimerBanner.new(parent)
	  timer.SetPhase(phase)                 titre localisé "hud.phase.<Phase>"
	  timer.SetTime(secondes?)              nil = « --:-- » ; rouge + « ! » sous 10 s (jamais la couleur seule)
	  timer.SetOvertime(secondes?)          bandeau visible tant que secondes > 0
	  timer.Instance   timer.Destroy()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared.Locale)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Kit = require(script.Parent.Kit)

export type TimerBanner = {
	Instance: Frame,
	SetPhase: (phase: string) -> (),
	SetTime: (seconds: number?) -> (),
	SetOvertime: (seconds: number?) -> (),
	Destroy: () -> (),
}

local URGENT_SECONDS = 10

local TimerBanner = {}

function TimerBanner.new(parent: Instance): TimerBanner
	local root = Instance.new("Frame")
	root.Name = "Chrono"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, 10)
	root.Size = UDim2.fromOffset(220, 140)
	root.Parent = parent

	local pill = Kit.panel(root, "Pastille")
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.fromScale(0.5, 0)
	pill.Size = UDim2.fromOffset(170, 62)
	local pillStroke = pill:FindFirstChildOfClass("UIStroke")
	local title = Kit.text(pill, "Titre", "Caption", "Heavy", Theme.Colors.PaperDim, true)
	title.Position = UDim2.fromOffset(0, 4)
	title.Size = UDim2.new(1, 0, 0, 16)
	title.TextXAlignment = Enum.TextXAlignment.Center
	local time = Kit.text(pill, "Temps", "Title", "Display", Theme.Colors.Paper, true)
	time.Position = UDim2.fromOffset(0, 20)
	time.Size = UDim2.new(1, 0, 1, -24)
	time.TextXAlignment = Enum.TextXAlignment.Center

	local banner = Kit.panel(root, "Prolongation", Theme.Colors.Danger, 0)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 70)
	banner.Size = UDim2.fromOffset(300, 58)
	banner.Visible = false
	local bannerTitle = Kit.text(banner, "Titre", "Heading", "Display", Theme.Colors.Paper, true)
	bannerTitle.Position = UDim2.fromOffset(0, 4)
	bannerTitle.Size = UDim2.new(1, 0, 0, 26)
	bannerTitle.TextXAlignment = Enum.TextXAlignment.Center
	Base.setText(bannerTitle, nil, "hud.overtime.title")
	local bannerBody = Kit.text(banner, "Corps", "Small", "Bold", Theme.Colors.Paper, true)
	bannerBody.Position = UDim2.fromOffset(8, 30)
	bannerBody.Size = UDim2.new(1, -16, 0, 22)
	bannerBody.TextXAlignment = Enum.TextXAlignment.Center

	local current = { urgent = false, lastSecond = -1, overtime = false }

	local api = {} :: TimerBanner
	api.Instance = root

	function api.SetPhase(phase: string)
		local key = "hud.phase." .. phase
		title.Text = if Locale.has(key) or Locale.has(key, "fr") then Locale.t(key) else ""
	end

	function api.SetTime(seconds: number?)
		local urgent = type(seconds) == "number" and seconds > 0 and seconds <= URGENT_SECONDS
		local text = Kit.formatTime(seconds)
		time.Text = if urgent then "! " .. text .. " !" else text
		if urgent ~= current.urgent then
			current.urgent = urgent
			time.TextColor3 = if urgent then Theme.Colors.Danger else Theme.Colors.Paper
			if pillStroke then
				pillStroke.Color = if urgent then Theme.Colors.Danger else Theme.Colors.Ink
			end
		end
		if urgent and type(seconds) == "number" then
			local second = math.ceil(seconds)
			if second ~= current.lastSecond then
				current.lastSecond = second
				Kit.bump(pill, 1.08)
			end
		end
	end

	function api.SetOvertime(seconds: number?)
		local active = type(seconds) == "number" and seconds > 0
		if active ~= current.overtime then
			current.overtime = active
			banner.Visible = active
			if active then
				Kit.bump(banner, 1.3)
			end
		end
		if active then
			bannerBody.Text = Locale.t("hud.overtime.body", { time = Kit.formatTime(seconds) })
		end
	end

	function api.Destroy()
		root:Destroy()
	end

	api.SetPhase("Playing")
	api.SetTime(nil)
	return api
end

return TimerBanner
