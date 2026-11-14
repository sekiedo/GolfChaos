--!strict
--[[
	Challenges — écran Défis : les succès internes de Config.Achievements, par catégorie, avec barre de
	progression (Achievements.progress sur les statistiques du profil), récompense en pièces et coche une fois
	réussi. Lecture seule : la progression et les récompenses sont calculées et versées par le serveur
	(AchievementService) ; l'écran suit les instantanés Data.Sync.

	Show(args) : args = nom de catégorie ("Golf", "Items"...) pour ouvrir directement sur un onglet.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trove = require(Shared.Util.Trove)
local Locale = require(Shared.Locale)
local Achievements = require(Shared.Config.Achievements)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Label = require(UI.Components.Label)
local Modal = require(UI.Components.Modal)
local Tabs = require(UI.Components.Tabs)
local Grid = require(UI.Components.Grid)
local ProgressBar = require(UI.Components.ProgressBar)
local Util = require(script.Parent.Util)

local Challenges = {}

local CATEGORIES = {
	{ id = "All", key = "challenges.cat.All", glyph = "★" },
	{ id = "Golf", key = "challenges.cat.Golf", glyph = "⛳" },
	{ id = "Precision", key = "challenges.cat.Precision", glyph = "◎" },
	{ id = "Exploration", key = "challenges.cat.Exploration", glyph = "⚐" },
	{ id = "Items", key = "challenges.cat.Items", glyph = "✚" },
	{ id = "Survival", key = "challenges.cat.Survival", glyph = "♥" },
	{ id = "Team", key = "challenges.cat.Team", glyph = "⚔" },
	{ id = "Vehicles", key = "challenges.cat.Vehicles", glyph = "☸" },
	{ id = "Victory", key = "challenges.cat.Victory", glyph = "♛" },
}

local function snapshot(): any
	local controller = Util.controller("ProfileController")
	return if controller then controller.Get() else {}
end

function Challenges.new(ctx: any): any
	local screen: any = { DisplayOrder = Theme.Layers.Menu + 1, Modal = true }

	local showTrove = Trove.new()
	local modal: Modal.ModalApi
	local tabs: Tabs.TabsApi
	local list: Grid.GridApi
	local summary: Label.LabelApi
	local current = "All"

	local function isDone(def: any, snap: any, progress: number): boolean
		local record = snap.achievements and snap.achievements[def.id]
		return (type(record) == "table" and record.done == true) or progress >= def.target
	end

	local function addRow(def: any, order: number, snap: any)
		local progress = Achievements.progress(def, snap.stats, snap.sets, snap.events)
		local done = isDone(def, snap, progress)

		local row = Instance.new("Frame")
		row.Name = "Defi_" .. def.id
		row.BorderSizePixel = 0
		row.BackgroundColor3 = if done then Theme.Colors.NightHover else Theme.Colors.NightRaised
		row.Size = UDim2.new(1, -10, 0, 92)
		row.LayoutOrder = order
		Base.corner(row, "Medium")
		Base.stroke(row, if done then Theme.Colors.Success else Theme.Colors.Ink, Theme.StrokeWidth.Thin)
		Base.padding(row, nil, Theme.Spacing.M, Theme.Spacing.S)
		row.Parent = list.Instance

		Label.new({
			name = "Nom",
			text = (if done then "✔ " else "") .. Locale.t(def.nameKey),
			style = "Body",
			font = "Heavy",
			color = if done then Theme.Colors.Success else Theme.Colors.Paper,
			truncate = true,
			size = UDim2.new(1, -150, 0, 24),
			parent = row,
		})
		Label.new({
			name = "Reward",
			text = Locale.t("challenges.reward", { n = def.reward }),
			style = "Small",
			font = "Heavy",
			color = Theme.Colors.Primary,
			alignX = Enum.TextXAlignment.Right,
			anchorPoint = Vector2.new(1, 0),
			position = UDim2.new(1, 0, 0, 0),
			size = UDim2.fromOffset(140, 24),
			parent = row,
		})
		Label.new({
			name = "Description",
			text = Locale.t(def.descKey),
			style = "Caption",
			font = "Bold",
			color = Theme.Colors.PaperDim,
			truncate = true,
			position = UDim2.fromOffset(0, 26),
			size = UDim2.new(1, 0, 0, 20),
			parent = row,
		})
		local bar = ProgressBar.new({
			name = "Progression",
			value = progress / math.max(1, def.target),
			color = if done then Theme.Colors.Success else Theme.Colors.Secondary,
			height = 20,
			showText = false,
			anchorPoint = Vector2.new(0, 1),
			position = UDim2.new(0, 0, 1, 0),
			size = UDim2.new(1, 0, 0, 20),
			parent = row,
		})
		if def.target > 1 then
			bar.SetText(Locale.t("challenges.progress", { a = progress, b = def.target }))
		end
	end

	function screen.Refresh(_self: any)
		local snap = snapshot()
		list.Clear()
		local total, finished, order = 0, 0, 0
		for _, def in Achievements.List do
			total += 1
			local progress = Achievements.progress(def, snap.stats, snap.sets, snap.events)
			local done = isDone(def, snap, progress)
			if done then
				finished += 1
			end
			if current == "All" or def.category == current then
				order += 1
				-- Les défis en cours d'abord (plus proches de la fin en premier), les réussis à la fin.
				addRow(def, (if done then 1000 else 0) + order, snap)
			end
		end
		summary.SetText(Locale.t("challenges.summary", { done = finished, total = total }))
	end

	function screen.Build(_self: any, gui: ScreenGui)
		modal = Modal.new({
			parent = gui,
			titleKey = "challenges.title",
			size = Vector2.new(780, 640),
			scroll = false,
			onClose = function()
				ctx.Manager.Hide("Challenges")
			end,
		})
		tabs = Tabs.new({
			name = "Categories",
			tabs = CATEGORIES,
			selected = current,
			size = UDim2.new(1, 0, 0, 56),
			parent = modal.Content,
			onChanged = function(id: string)
				current = id
				screen:Refresh()
				list.ScrollToTop()
			end,
		})
		summary = Label.new({
			name = "Resume",
			text = "",
			style = "Small",
			font = "Heavy",
			color = Theme.Colors.PaperDim,
			alignX = Enum.TextXAlignment.Right,
			position = UDim2.fromOffset(0, 60),
			size = UDim2.new(1, -8, 0, 24),
			parent = modal.Content,
		})
		list = Grid.list({
			name = "Liste",
			gap = Theme.Spacing.S,
			position = UDim2.fromOffset(0, 90),
			size = UDim2.new(1, 0, 1, -90),
			parent = modal.Content,
		})
	end

	function screen.Show(_self: any, args: any, wasVisible: boolean)
		if type(args) == "string" then
			for _, category in CATEGORIES do
				if category.id == args then
					current = args
					tabs.Select(args, true)
				end
			end
		end
		screen:Refresh()
		if wasVisible then
			return
		end
		showTrove:Clean()
		modal.Open()
		local controller = Util.controller("ProfileController")
		if controller then
			showTrove:Add(controller.Changed:Connect(function()
				screen:Refresh()
			end))
			controller.RequestSync()
		end
	end

	function screen.Hide(_self: any): number?
		showTrove:Clean()
		return modal.Close()
	end

	function screen.GetDefaultSelection(_self: any): GuiObject?
		return tabs.GetButton(tabs.GetSelected())
	end

	function screen.Destroy(_self: any)
		showTrove:Clean()
	end

	return screen
end

return Challenges
