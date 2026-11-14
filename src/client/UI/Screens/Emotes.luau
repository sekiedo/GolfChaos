--!strict
--[[
	Emotes — écran de choix d'émote : jusqu'à 8 émotes (celles équipées dans Personnaliser, complétées par les
	émotes gratuites par défaut), jouées d'un clic, d'une touche 1..8 ou à la manette. « Arrêter » coupe
	l'émote en cours. Le serveur valide tout (EmoteService : possession, état du personnage, délai de 0,75 s).

	Show(args) : sans argument. La fenêtre se referme après le choix d'une émote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trove = require(Shared.Util.Trove)
local Locale = require(Shared.Locale)
local Cosmetics = require(Shared.Cosmetics)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Label = require(UI.Components.Label)
local Button = require(UI.Components.Button)
local Modal = require(UI.Components.Modal)
local Grid = require(UI.Components.Grid)
local Util = require(script.Parent.Util)

local Emotes = {}

local MAX_SLOTS = 8
local NUMBER_KEYS = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four,
	Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight,
}

-- Émotes proposées : équipées d'abord (dans l'ordre choisi), puis gratuites par défaut, 8 au plus.
function Emotes.list(equipped: any): { any }
	local result: { any } = {}
	local seen: { [string]: boolean } = {}
	local ids = if type(equipped) == "table" and type(equipped.Emotes) == "table" then equipped.Emotes else {}
	for _, id in ids do
		local def = Cosmetics.get(id)
		if def and def.slot == "Emote" and not seen[def.id] and #result < MAX_SLOTS then
			seen[def.id] = true
			table.insert(result, def)
		end
	end
	for _, def in Cosmetics.bySlot("Emote") do
		if def.unlock and def.unlock.kind == "Default" and not seen[def.id] and #result < MAX_SLOTS then
			seen[def.id] = true
			table.insert(result, def)
		end
	end
	return result
end

function Emotes.new(ctx: any): any
	local screen: any = { DisplayOrder = Theme.Layers.Menu + 1, Modal = true }

	local showTrove = Trove.new()
	local modal: Modal.ModalApi
	local grid: Grid.GridApi
	local hint: Label.LabelApi
	local shown: { any } = {}

	local function profile(): any
		return Util.controller("ProfileController")
	end

	local function play(index: number)
		local def = shown[index]
		local controller = profile()
		if def and controller then
			controller.PlayEmote(def.id)
			ctx.Manager.Hide("Emotes")
		end
	end

	function screen.Refresh(_self: any)
		grid.Clear()
		local controller = profile()
		local snap = if controller then controller.Get() else {}
		shown = Emotes.list(snap.equipped)
		for index, def in shown do
			local card = Instance.new("TextButton")
			card.Name = "Emote_" .. def.id
			card.AutoButtonColor = false
			card.Text = ""
			card.BorderSizePixel = 0
			card.BackgroundColor3 = Theme.Colors.NightRaised
			card.LayoutOrder = index
			Base.corner(card, "Medium")
			Base.stroke(card, Theme.Colors.Ink, Theme.StrokeWidth.Normal)
			Base.padding(card, nil, Theme.Spacing.S, Theme.Spacing.S)
			Base.makeSelectable(card, "Rect")
			card.Parent = grid.Instance
			Base.list(card, Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
			Label.new({ name = "Touche", text = tostring(index), style = "Heading", font = "Display", color = Theme.Colors.Primary, alignX = Enum.TextXAlignment.Center, size = UDim2.new(1, 0, 0, 32), layoutOrder = 1, parent = card })
			Label.new({ name = "Nom", text = Locale.t(def.nameKey), style = "Small", font = "Heavy", alignX = Enum.TextXAlignment.Center, truncate = true, size = UDim2.new(1, 0, 0, 36), layoutOrder = 2, parent = card })
			card.Activated:Connect(function()
				play(index)
			end)
		end
		hint.SetKey(if #shown == 0 then "emotes.empty" else "emotes.hint")
	end

	function screen.Build(_self: any, gui: ScreenGui)
		modal = Modal.new({
			parent = gui,
			titleKey = "emotes.title",
			size = Vector2.new(660, 520),
			scroll = false,
			onClose = function()
				ctx.Manager.Hide("Emotes")
			end,
		})
		hint = Label.new({
			name = "Aide",
			key = "emotes.hint",
			style = "Small",
			font = "Bold",
			color = Theme.Colors.PaperDim,
			alignX = Enum.TextXAlignment.Center,
			size = UDim2.new(1, 0, 0, 24),
			parent = modal.Content,
		})
		grid = Grid.new({
			name = "Emotes",
			cellSize = Vector2.new(140, 96),
			gap = Theme.Spacing.S,
			position = UDim2.fromOffset(0, 30),
			size = UDim2.new(1, 0, 1, -30 - 64),
			parent = modal.Content,
		})
		local footer = Instance.new("Frame")
		footer.Name = "Pied"
		footer.BackgroundTransparency = 1
		footer.AnchorPoint = Vector2.new(0, 1)
		footer.Position = UDim2.new(0, 0, 1, 0)
		footer.Size = UDim2.new(1, 0, 0, 56)
		Base.list(footer, Enum.FillDirection.Horizontal, Theme.Spacing.S, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		footer.Parent = modal.Content
		Button.new({
			name = "Arreter",
			key = "emotes.stop",
			icon = "■",
			variant = "Warning",
			size = "Small",
			layoutOrder = 1,
			parent = footer,
			onActivated = function()
				local controller = profile()
				if controller then
					controller.StopEmote()
				end
				ctx.Manager.Hide("Emotes")
			end,
		})
		Button.new({
			name = "Choisir",
			key = "emotes.customize",
			icon = "✎",
			variant = "Dark",
			size = "Small",
			layoutOrder = 2,
			parent = footer,
			onActivated = function()
				ctx.Manager.Hide("Emotes")
				ctx.Manager.Show("Customize", "Emote")
			end,
		})
	end

	function screen.Show(_self: any, _args: any, wasVisible: boolean)
		screen:Refresh()
		if wasVisible then
			return
		end
		showTrove:Clean()
		modal.Open()
		showTrove:Connect(UserInputService.InputBegan, function(input: InputObject, processed: boolean)
			if processed then
				return
			end
			local index = table.find(NUMBER_KEYS, input.KeyCode)
			if index then
				play(index)
			end
		end)
		local controller = profile()
		if controller then
			showTrove:Add(controller.Changed:Connect(function()
				screen:Refresh()
			end))
		end
	end

	function screen.Hide(_self: any): number?
		showTrove:Clean()
		return modal.Close()
	end

	function screen.GetDefaultSelection(_self: any): GuiObject?
		for _, child in grid.Instance:GetChildren() do
			if child:IsA("TextButton") then
				return child
			end
		end
		return nil
	end

	function screen.Destroy(_self: any)
		showTrove:Clean()
	end

	return screen
end

return Emotes
