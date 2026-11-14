--!strict
--[[
	CosmeticBrowser — construit les écrans Boutique et Personnaliser (même présentation, deux modes).

	  CosmeticBrowser.new(ctx, "shop" | "customize", screenName) -> écran (contrat ScreenManager)

	  Boutique       tous les cosmétiques, un onglet par emplacement ; acheter avec des pièces (ou voir la
	                 condition de déblocage). Prix, possession et déblocage restent décidés par le serveur.
	  Personnaliser  les cosmétiques possédés : équiper, retirer une émote, choisir la couleur (variante),
	                 enregistrer / porter un des 3 ensembles.

	Les données viennent de ProfileController (Data.Sync) ; chaque action est une intention envoyée au serveur
	(Shop.Buy / Equip / SetVariant / SaveLoadout / UseLoadout) dont le résultat revient par Shop.Result
	(toasts : ShopController). L'écran se rafraîchit à chaque instantané reçu.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trove = require(Shared.Util.Trove)
local Locale = require(Shared.Locale)
local Cosmetics = require(Shared.Cosmetics)
local Status = require(Shared.Cosmetics.Status)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Label = require(UI.Components.Label)
local Button = require(UI.Components.Button)
local Modal = require(UI.Components.Modal)
local Tabs = require(UI.Components.Tabs)
local Grid = require(UI.Components.Grid)
local Cycler = require(UI.Components.Cycler)
local Util = require(script.Parent.Util)

local CosmeticBrowser = {}

local SLOTS = {
	{ id = "Head", key = "shop.tab.Head", glyph = "♛" },
	{ id = "Face", key = "shop.tab.Face", glyph = "☺" },
	{ id = "Outfit", key = "shop.tab.Outfit", glyph = "♟" },
	{ id = "Shoes", key = "shop.tab.Shoes", glyph = "⛸" },
	{ id = "Club", key = "shop.tab.Club", glyph = "⚑" },
	{ id = "Ball", key = "shop.tab.Ball", glyph = "●" },
	{ id = "HoleEffect", key = "shop.tab.HoleEffect", glyph = "✦" },
	{ id = "Emote", key = "shop.tab.Emote", glyph = "♫" },
}

local RARITY_COLORS: { [string]: Color3 } = {
	Common = Theme.Colors.PaperDim,
	Rare = Theme.Colors.Secondary,
	Epic = Theme.Colors.Accent,
	Legendary = Theme.Colors.Primary,
}

local LOADOUTS = 3
local MAX_EMOTES = 8

local function profile(): any
	return Util.controller("ProfileController")
end

local function snapshot(): any
	local controller = profile()
	return if controller then controller.Get() else {}
end

-- Texte de l'état d'un cosmétique (ligne de la carte et du détail).
local function stateText(def: any, state: string, snap: any): string
	if state == "equipped" then
		return Locale.t("shop.state.equipped")
	elseif state == "owned" then
		return Locale.t("shop.state.owned")
	elseif state == "locked" then
		local info = Status.unlock(def, snap)
		local vars: { [string]: any } = if info.vars then table.clone(info.vars) else {}
		if vars.nameKey then
			vars.name = Locale.t(vars.nameKey)
		end
		return Locale.t(info.textKey, vars)
	end
	return Locale.t("shop.price", { n = def.price })
end

function CosmeticBrowser.new(ctx: any, mode: string, screenName: string): any
	local screen: any = { DisplayOrder = Theme.Layers.Menu + 1, Modal = true }
	local isShop = mode == "shop"

	local showTrove = Trove.new()
	local modal: Modal.ModalApi
	local tabs: Tabs.TabsApi
	local grid: Grid.GridApi
	local coinsLabel: Label.LabelApi
	local detail: Frame
	local detailName: Label.LabelApi
	local detailDesc: Label.LabelApi
	local detailState: Label.LabelApi
	local actionButton: Button.ButtonApi
	local variantHolder: Frame
	local variantCycler: Cycler.CyclerApi? = nil
	local emoteCount: Label.LabelApi? = nil

	local currentSlot = "Head"
	local selectedId: string? = nil
	local rebuilding = false

	local function selectedDef(): any
		return if selectedId then Cosmetics.get(selectedId) else nil
	end

	local function visibleDefs(): { any }
		local snap = snapshot()
		local result = {}
		for _, def in Cosmetics.bySlot(currentSlot :: any) do
			if isShop or Status.isOwned(def, snap) then
				table.insert(result, def)
			end
		end
		return result
	end

	-- Détail et bouton d'action ------------------------------------------------------------------
	local function refreshVariants(def: any, snap: any)
		if variantCycler then
			variantCycler.Instance:Destroy()
			variantCycler = nil
		end
		local owned = def ~= nil and Status.isOwned(def, snap)
		local count = if def and def.variants then #def.variants else 0
		variantHolder.Visible = not isShop and owned and count > 1
		if not variantHolder.Visible then
			return
		end
		local options = {}
		for index, variant in def.variants do
			local text = if variant.nameKey and Locale.has(variant.nameKey) then Locale.t(variant.nameKey)
				else Locale.t("customize.colorN", { n = index })
			table.insert(options, { value = index, text = text })
		end
		local cycler = Cycler.new({
			name = "Couleur",
			options = options,
			value = Status.variantOf(def, snap),
			width = 220,
			onChanged = function(value: any)
				local controller = profile()
				if controller and not rebuilding and type(value) == "number" then
					controller.SetVariant(def.id, value)
				end
			end,
		})
		cycler.Instance.Parent = variantHolder
		variantCycler = cycler
	end

	local function refreshDetail()
		local def = selectedDef()
		local snap = snapshot()
		if not def then
			detail.Visible = false
			return
		end
		detail.Visible = true
		detailName.SetText(Locale.t(def.nameKey))
		detailDesc.SetText(
			Locale.t("shop.rarity." .. def.rarity) .. (if def.descKey and Locale.has(def.descKey) then " — " .. Locale.t(def.descKey) else "")
		)
		local state = Status.of(def, snap)
		detailState.SetText(stateText(def, state, snap))
		local controller = profile()
		if state == "buyable" then
			actionButton.SetKey("shop.buy")
			actionButton.SetVariant("Success")
			actionButton.SetEnabled(true)
		elseif state == "poor" then
			actionButton.SetKey("shop.state.poor")
			actionButton.SetVariant("Dark")
			actionButton.SetEnabled(false)
		elseif state == "locked" then
			actionButton.SetKey("shop.state.lockedShort")
			actionButton.SetVariant("Dark")
			actionButton.SetEnabled(false)
		elseif state == "owned" then
			actionButton.SetKey("shop.equip")
			actionButton.SetVariant("Primary")
			actionButton.SetEnabled(controller ~= nil)
		else -- équipé
			if def.slot == "Emote" then
				actionButton.SetKey("shop.unequip")
				actionButton.SetVariant("Warning")
				actionButton.SetEnabled(controller ~= nil)
			else
				actionButton.SetKey("shop.state.equipped")
				actionButton.SetVariant("Dark")
				actionButton.SetEnabled(false)
			end
		end
		refreshVariants(def, snap)
	end

	-- Cartes ---------------------------------------------------------------------------------------
	local function addCard(def: any, order: number, snap: any)
		local state = Status.of(def, snap)
		local card = Instance.new("TextButton")
		card.Name = "Carte_" .. def.id
		card.AutoButtonColor = false
		card.Text = ""
		card.BorderSizePixel = 0
		card.BackgroundColor3 = if def.id == selectedId then Theme.Colors.NightHover else Theme.Colors.NightRaised
		card.LayoutOrder = order
		Base.corner(card, "Medium")
		Base.stroke(card, if state == "equipped" then Theme.Colors.Success else RARITY_COLORS[def.rarity] or Theme.Colors.Ink, Theme.StrokeWidth.Normal)
		Base.padding(card, nil, Theme.Spacing.S, Theme.Spacing.S)
		Base.makeSelectable(card, "Rect")
		card.Parent = grid.Instance

		Base.list(card, Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)

		-- Pastilles de couleur (variantes) : aperçu sans modèle 3D.
		local swatches = Instance.new("Frame")
		swatches.Name = "Pastilles"
		swatches.BackgroundTransparency = 1
		swatches.Size = UDim2.new(1, 0, 0, 34)
		swatches.LayoutOrder = 1
		Base.list(swatches, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		swatches.Parent = card
		local variantIndex = Status.variantOf(def, snap)
		local variant = if def.variants then def.variants[variantIndex] else nil
		local colors = if variant and variant.colors then variant.colors else { RARITY_COLORS[def.rarity] or Theme.Colors.Paper }
		for index = 1, math.min(#colors, 4) do
			local dot = Instance.new("Frame")
			dot.Name = "Pastille" .. index
			dot.Size = UDim2.fromOffset(26, 26)
			dot.BackgroundColor3 = colors[index]
			dot.BorderSizePixel = 0
			dot.LayoutOrder = index
			Base.corner(dot, "Pill")
			Base.stroke(dot, Theme.Colors.Ink, Theme.StrokeWidth.Thin)
			dot.Parent = swatches
		end

		Label.new({
			name = "Nom",
			text = Locale.t(def.nameKey),
			style = "Small",
			font = "Heavy",
			alignX = Enum.TextXAlignment.Center,
			truncate = true,
			size = UDim2.new(1, 0, 0, 36),
			layoutOrder = 2,
			parent = card,
		})
		Label.new({
			name = "Etat",
			text = stateText(def, state, snap),
			style = "Caption",
			font = "Bold",
			color = if state == "equipped" then Theme.Colors.Success
				elseif state == "buyable" then Theme.Colors.Primary
				elseif state == "poor" or state == "locked" then Theme.Colors.PaperDim
				else Theme.Colors.Paper,
			alignX = Enum.TextXAlignment.Center,
			truncate = true,
			size = UDim2.new(1, 0, 0, 20),
			layoutOrder = 3,
			parent = card,
		})

		card.Activated:Connect(function()
			selectedId = def.id
			screen:Refresh()
		end)
	end

	local function refreshGrid()
		grid.Clear()
		local snap = snapshot()
		local defs = visibleDefs()
		if selectedId then
			local def = selectedDef()
			if not def or def.slot ~= currentSlot then
				selectedId = nil
			end
		end
		if not selectedId and #defs > 0 then
			selectedId = defs[1].id
		end
		for index, def in defs do
			addCard(def, index, snap)
		end
		if #defs == 0 then
			Label.new({
				name = "Vide",
				key = if isShop then "shop.empty" else "customize.empty",
				style = "Body",
				color = Theme.Colors.PaperDim,
				alignX = Enum.TextXAlignment.Center,
				size = UDim2.new(1, 0, 0, 60),
				parent = grid.Instance,
			})
		end
	end

	local function refreshHeader()
		local controller = profile()
		local coins = if controller then controller.GetCoins() else 0
		coinsLabel.SetText(Locale.t("shop.coins", { n = coins }))
		local counter = emoteCount
		if counter then
			local equipped = snapshot().equipped
			local list = if type(equipped) == "table" and type(equipped.Emotes) == "table" then equipped.Emotes else {}
			counter.SetText(Locale.t("customize.emotesCount", { n = #list, max = MAX_EMOTES }))
			counter.Instance.Visible = currentSlot == "Emote"
		end
	end

	function screen.Refresh(_self: any)
		rebuilding = true
		refreshHeader()
		refreshGrid()
		refreshDetail()
		rebuilding = false
	end

	local function onAction()
		local def = selectedDef()
		local controller = profile()
		if not def or not controller then
			return
		end
		local state = Status.of(def, snapshot())
		if state == "buyable" then
			controller.Buy(def.id)
		elseif state == "owned" then
			controller.Equip(def.slot, def.id)
		elseif state == "equipped" and def.slot == "Emote" then
			controller.Equip("Emote", def.id)
		end
	end

	function screen.Build(_self: any, gui: ScreenGui)
		modal = Modal.new({
			parent = gui,
			titleKey = if isShop then "shop.title" else "customize.title",
			size = Vector2.new(900, 660),
			scroll = false,
			onClose = function()
				ctx.Manager.Hide(screenName)
			end,
		})
		local content = modal.Content

		tabs = Tabs.new({
			name = "Onglets",
			tabs = SLOTS,
			selected = currentSlot,
			size = UDim2.new(1, 0, 0, 56),
			parent = content,
			onChanged = function(id: string)
				currentSlot = id
				selectedId = nil
				screen:Refresh()
				grid.ScrollToTop()
			end,
		})

		coinsLabel = Label.new({
			name = "Pieces",
			text = "",
			style = "Body",
			font = "Heavy",
			color = Theme.Colors.Primary,
			alignX = Enum.TextXAlignment.Right,
			position = UDim2.fromOffset(0, 60),
			size = UDim2.new(1, -8, 0, 28),
			parent = content,
		})
		if not isShop then
			emoteCount = Label.new({
				name = "NbEmotes",
				text = "",
				style = "Small",
				font = "Bold",
				color = Theme.Colors.PaperDim,
				alignX = Enum.TextXAlignment.Left,
				position = UDim2.fromOffset(8, 60),
				size = UDim2.new(0.5, 0, 0, 28),
				parent = content,
			})
		end

		local bottomHeight = if isShop then 130 else 190
		grid = Grid.new({
			name = "Cartes",
			cellSize = Vector2.new(150, 112),
			gap = Theme.Spacing.S,
			position = UDim2.fromOffset(0, 92),
			size = UDim2.new(1, 0, 1, -92 - bottomHeight - 8),
			parent = content,
		})

		detail = Instance.new("Frame")
		detail.Name = "Detail"
		detail.BackgroundColor3 = Theme.Colors.NightRaised
		detail.BorderSizePixel = 0
		detail.AnchorPoint = Vector2.new(0, 1)
		detail.Position = UDim2.new(0, 0, 1, 0)
		detail.Size = UDim2.new(1, -6, 0, bottomHeight)
		Base.corner(detail, "Medium")
		Base.stroke(detail, Theme.Colors.Ink, Theme.StrokeWidth.Thin)
		Base.padding(detail, nil, Theme.Spacing.M, Theme.Spacing.S)
		detail.Parent = content

		local texts = Instance.new("Frame")
		texts.Name = "Textes"
		texts.BackgroundTransparency = 1
		texts.Size = UDim2.new(1, -190, 0, 84)
		Base.list(texts, Enum.FillDirection.Vertical, 0)
		texts.Parent = detail
		detailName = Label.new({ name = "Nom", text = "", style = "Heading", font = "Heavy", truncate = true, size = UDim2.new(1, 0, 0, 30), layoutOrder = 1, parent = texts })
		detailDesc = Label.new({ name = "Description", text = "", style = "Caption", font = "Bold", color = Theme.Colors.PaperDim, size = UDim2.new(1, 0, 0, 36), layoutOrder = 2, parent = texts })
		detailState = Label.new({ name = "Etat", text = "", style = "Small", font = "Heavy", color = Theme.Colors.Primary, size = UDim2.new(1, 0, 0, 20), layoutOrder = 3, parent = texts })

		actionButton = Button.new({
			name = "Action",
			key = "shop.buy",
			variant = "Success",
			size = "Medium",
			width = 170,
			anchorPoint = Vector2.new(1, 0),
			position = UDim2.new(1, 0, 0, 0),
			parent = detail,
			onActivated = onAction,
		})

		variantHolder = Instance.new("Frame")
		variantHolder.Name = "Variantes"
		variantHolder.BackgroundTransparency = 1
		variantHolder.AnchorPoint = Vector2.new(1, 0)
		variantHolder.Position = UDim2.new(1, 0, 0, 60)
		variantHolder.Size = UDim2.fromOffset(220, Theme.Touch.Min)
		variantHolder.Visible = false
		variantHolder.Parent = detail

		if not isShop then
			local row = Instance.new("Frame")
			row.Name = "Ensembles"
			row.BackgroundTransparency = 1
			row.AnchorPoint = Vector2.new(0, 1)
			row.Position = UDim2.new(0, 0, 1, 0)
			row.Size = UDim2.new(1, 0, 0, 52)
			Base.list(row, Enum.FillDirection.Horizontal, Theme.Spacing.S, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
			row.Parent = detail
			for index = 1, LOADOUTS do
				Button.new({
					name = "Porter" .. index,
					key = "customize.useLoadout",
					vars = { n = index },
					variant = "Secondary",
					size = "Small",
					layoutOrder = index * 2 - 1,
					parent = row,
					onActivated = function()
						local controller = profile()
						if controller then
							controller.UseLoadout(index)
						end
					end,
				})
				Button.new({
					name = "Enregistrer" .. index,
					key = "customize.saveLoadout",
					vars = { n = index },
					variant = "Dark",
					size = "Small",
					layoutOrder = index * 2,
					parent = row,
					onActivated = function()
						local controller = profile()
						if controller then
							controller.SaveLoadout(index)
						end
					end,
				})
			end
		end
	end

	function screen.Show(_self: any, args: any, wasVisible: boolean)
		if type(args) == "string" and table.find({ "Head", "Face", "Outfit", "Shoes", "Club", "Ball", "HoleEffect", "Emote" }, args) then
			currentSlot = args
			tabs.Select(args, true)
		end
		screen:Refresh()
		if wasVisible then
			return
		end
		showTrove:Clean()
		modal.Open()
		local controller = profile()
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

return CosmeticBrowser
