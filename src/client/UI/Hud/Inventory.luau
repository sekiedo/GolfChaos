--!strict
--[[
	Hud/Inventory — cases d'objets (bas centre), alimentées par les attributs joueur posés par ItemService :
	Inventory (ids séparés par des virgules, "" = case vide), SelectedSlot, InventoryCapacity.
	Affichage seul : l'utilisation des objets appartient à InventoryController.

	  local inv = Inventory.new(parent)
	  inv.SetSlots(ids, capacité, sélection)   inv.SetVisible(bool)   inv.Instance   inv.Destroy()
	La case choisie est signalée par un cadre épais ET un repère ▲ (jamais la couleur seule).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared.Locale)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Kit = require(script.Parent.Kit)

export type Inventory = {
	Instance: Frame,
	SetSlots: (ids: { string }, capacity: number, selected: number) -> (),
	SetVisible: (visible: boolean) -> (),
	Destroy: () -> (),
}

type SlotUi = {
	frame: Frame,
	stroke: UIStroke,
	glyph: TextLabel,
	name: TextLabel,
	number: TextLabel,
	marker: TextLabel,
}

local MAX_SLOTS = 4
local SLOT_SIZE = 62

local itemsConfig: any = nil
local itemsLooked = false

local function itemDef(id: string): any
	if not itemsLooked then
		itemsLooked = true
		local config = Shared:FindFirstChild("Config")
		local module = if config then config:FindFirstChild("Items") else nil
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				itemsConfig = result
			end
		end
	end
	if itemsConfig and type(itemsConfig.ById) == "table" then
		return itemsConfig.ById[id]
	end
	return nil
end

local Inventory = {}

function Inventory.new(parent: Instance): Inventory
	local root = Instance.new("Frame")
	root.Name = "Objets"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -48)
	root.Size = UDim2.fromOffset((SLOT_SIZE + 8) * MAX_SLOTS, SLOT_SIZE + 22)
	Base.list(root, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	root.Parent = parent

	local slots: { SlotUi } = {}
	for index = 1, MAX_SLOTS do
		local frame = Kit.panel(root, "Case" .. index, Theme.Colors.Night, 0.15)
		frame.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
		frame.LayoutOrder = index
		local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke
		local glyph = Kit.text(frame, "Glyphe", "Title", "Display", Theme.Colors.Paper, true)
		glyph.Position = UDim2.fromOffset(4, 4)
		glyph.Size = UDim2.new(1, -8, 0.62, -4)
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		local name = Kit.text(frame, "Nom", "Caption", "Bold", Theme.Colors.PaperDim, true)
		name.Position = UDim2.new(0, 3, 0.62, 0)
		name.Size = UDim2.new(1, -6, 0.38, -3)
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local number = Kit.text(frame, "Numero", "Caption", "Heavy", Theme.Colors.Paper, false)
		number.Position = UDim2.fromOffset(5, 2)
		number.Size = UDim2.fromOffset(14, 14)
		number.Text = Locale.t("hud.inventory.slot", { n = index })
		local marker = Kit.text(frame, "Repere", "Small", "Display", Theme.Colors.Primary, false)
		marker.AnchorPoint = Vector2.new(0.5, 0)
		marker.Position = UDim2.new(0.5, 0, 1, 2)
		marker.Size = UDim2.fromOffset(20, 16)
		marker.TextXAlignment = Enum.TextXAlignment.Center
		marker.Text = "▲"
		marker.Visible = false
		slots[index] = { frame = frame, stroke = stroke, glyph = glyph, name = name, number = number, marker = marker }
	end

	local previous: { string } = {}
	local hidden = false

	local api = {} :: Inventory
	api.Instance = root

	function api.SetSlots(ids: { string }, capacity: number, selected: number)
		local cap = math.clamp(math.floor(capacity), 0, MAX_SLOTS)
		root.Visible = cap > 0 and not hidden
		for index, ui in slots do
			local active = index <= cap
			ui.frame.Visible = active
			if not active then
				continue
			end
			local id = ids[index] or ""
			local def = if id ~= "" then itemDef(id) else nil
			if id == "" then
				ui.glyph.Text = ""
				ui.name.Text = Locale.t("hud.inventory.empty")
				ui.frame.BackgroundColor3 = Theme.Colors.Night
			else
				ui.glyph.Text = if def and type(def.glyph) == "string" then def.glyph else "?"
				local nameKey = if def and type(def.nameKey) == "string" then def.nameKey else ("item." .. id .. ".name")
				ui.name.Text = Locale.t(nameKey)
				local color = if def and typeof(def.color) == "Color3" then def.color else Theme.Colors.NightRaised
				ui.frame.BackgroundColor3 = Theme.Colors.Night:Lerp(color, 0.35)
			end
			local isSelected = index == selected and id ~= ""
			ui.stroke.Color = if isSelected then Theme.Colors.Primary else Theme.Colors.Ink
			ui.stroke.Thickness = if isSelected then Theme.StrokeWidth.Thick + 1 else Theme.StrokeWidth.Normal
			ui.marker.Visible = isSelected
			if id ~= "" and previous[index] ~= id then
				Kit.bump(ui.frame, 1.25)
			end
			previous[index] = id
		end
	end

	function api.SetVisible(visible: boolean)
		hidden = not visible
		if not visible then
			root.Visible = false
		end
	end

	function api.Destroy()
		root:Destroy()
	end

	return api
end

return Inventory
