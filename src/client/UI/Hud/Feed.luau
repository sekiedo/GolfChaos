--!strict
--[[
	Hud/Feed — fil d'événements (gauche, sous la carte du trou) et message court central.

	  local feed = Feed.new(parent, parentDuMessage?)
	  feed.Push(texte, genre?)        genre : "holed" (⛳) | "ko" (✶) | "info" ; 5 lignes max, fondu après 6 s
	  feed.Toast(texte, genre?)       message court centré ("info" | "warn" | "good")
	  feed.Clear()   feed.Instance   feed.Destroy()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trove = require(Shared.Util.Trove)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Kit = require(script.Parent.Kit)

export type Feed = {
	Instance: Frame,
	Push: (text: string, kind: string?) -> (),
	Toast: (text: string, kind: string?) -> (),
	Clear: () -> (),
	Destroy: () -> (),
}

local MAX_LINES = 5
local LINE_TIME = 6
local TOAST_TIME = 2.4

local GLYPHS: { [string]: string } = { holed = "⛳", ko = "✶", info = "•", best = "★" }

local Feed = {}

function Feed.new(parent: Instance, toastParent: Instance?): Feed
	local trove = Trove.new()
	local root = Instance.new("Frame")
	root.Name = "Fil"
	root.BackgroundTransparency = 1
	root.Position = UDim2.fromOffset(12, 122)
	root.Size = UDim2.fromOffset(340, 200)
	Base.list(root, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left)
	root.Parent = parent
	trove:Add(root)

	local toast = Kit.panel(toastParent or parent, "MessageHUD")
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0.3, 0)
	toast.Size = UDim2.fromOffset(0, 42)
	toast.AutomaticSize = Enum.AutomaticSize.X
	toast.Visible = false
	Base.padding(toast, 0, 18, 0)
	local toastStroke = toast:FindFirstChildOfClass("UIStroke")
	local toastText = Kit.text(toast, "Texte", "Button", "Display", Theme.Colors.Paper, false)
	toastText.Size = UDim2.new(0, 0, 1, 0)
	toastText.AutomaticSize = Enum.AutomaticSize.X
	toastText.TextXAlignment = Enum.TextXAlignment.Center
	trove:Add(toast)

	local order = 0
	local toastToken = 0
	local lines: { Frame } = {}

	local function removeLine(line: Frame)
		local index = table.find(lines, line)
		if index then
			table.remove(lines, index)
		end
		line:Destroy()
	end

	local api = {} :: Feed
	api.Instance = root

	function api.Push(text: string, kind: string?)
		if type(text) ~= "string" or text == "" then
			return
		end
		order += 1
		local color = if kind == "holed"
			then Theme.Colors.Success
			elseif kind == "ko" then Theme.Colors.Danger
			elseif kind == "best" then Theme.Colors.Primary
			else Theme.Colors.Secondary
		local line = Instance.new("Frame")
		line.Name = "Ligne"
		line.BackgroundColor3 = Theme.Colors.Night
		line.BackgroundTransparency = Theme.backgroundTransparency(0.2)
		line.BorderSizePixel = 0
		line.Size = UDim2.fromOffset(0, 30)
		line.AutomaticSize = Enum.AutomaticSize.X
		line.LayoutOrder = order
		Base.corner(line, "Pill")
		Base.stroke(line, color, 2)
		Base.padding(line, 0, 10, 0)
		Base.list(line, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		local glyph = Base.newText("Glyphe", "Body", "Display", color)
		glyph.Size = UDim2.fromOffset(20, 26)
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		glyph.Text = GLYPHS[kind or "info"] or "•"
		glyph.LayoutOrder = 1
		glyph.Parent = line
		local label = Base.newText("Texte", "Small", "Bold", Theme.Colors.Paper)
		label.Size = UDim2.fromOffset(0, 26)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Text = text
		label.LayoutOrder = 2
		label.Parent = line
		line.Parent = root
		table.insert(lines, line)
		Kit.bump(line, 1.1)
		while #lines > MAX_LINES do
			removeLine(lines[1])
		end
		task.delay(LINE_TIME, function()
			if line.Parent then
				Theme.fade(line, 0.4, { BackgroundTransparency = 1 })
				Theme.fade(label, 0.4, { TextTransparency = 1 })
				Theme.fade(glyph, 0.4, { TextTransparency = 1 })
				task.delay(0.45, function()
					if line.Parent then
						removeLine(line)
					end
				end)
			end
		end)
	end

	function api.Toast(text: string, kind: string?)
		if type(text) ~= "string" or text == "" then
			return
		end
		toastToken += 1
		local token = toastToken
		local color = if kind == "warn" then Theme.Colors.Danger elseif kind == "good" then Theme.Colors.Success else Theme.Colors.Secondary
		if toastStroke then
			toastStroke.Color = color
		end
		toastText.Text = text
		toastText.TextTransparency = 0
		toast.BackgroundTransparency = Theme.backgroundTransparency(0.1)
		toast.Visible = true
		Kit.bump(toast, 1.15)
		task.delay(TOAST_TIME, function()
			if token ~= toastToken or not toast.Parent then
				return
			end
			Theme.fade(toast, 0.3, { BackgroundTransparency = 1 })
			Theme.fade(toastText, 0.3, { TextTransparency = 1 })
			task.delay(0.32, function()
				if token == toastToken and toast.Parent then
					toast.Visible = false
				end
			end)
		end)
	end

	function api.Clear()
		for _, line in table.clone(lines) do
			removeLine(line)
		end
	end

	function api.Destroy()
		api.Clear()
		trove:Clean()
	end

	return api
end

return Feed
