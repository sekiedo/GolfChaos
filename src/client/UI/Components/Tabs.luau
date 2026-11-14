--!strict
--[[
	Tabs — rangée d'onglets en pastilles (onglet actif en couleur vive, surélevé) ; LB / RB (manette) passent
	à l'onglet précédent / suivant quand la rangée est visible.

	  local tabs = Tabs.new({ tabs = { { id = "audio", key = "settings.tab.audio", glyph = "♪" }, ... },
	                          selected = "audio", parent = header, onChanged = function(id) ... end })
	  tabs.Select("display")   tabs.GetSelected()   tabs.Changed:Connect(function(id) end)
	  tabs.Next() / tabs.Previous()   tabs.GetButton(id) -> TextButton?

	Props : tabs ; selected ; onChanged ; shoulderButtons (true) ; + communs (name, parent, position, size,
	anchorPoint, layoutOrder, zIndex, visible). La rangée défile horizontalement si elle dépasse.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)

local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Base)

export type TabDef = { id: string, key: string?, text: string?, glyph: string? }

export type TabsProps = {
	tabs: { TabDef },
	selected: string?,
	onChanged: ((id: string) -> ())?,
	shoulderButtons: boolean?,
	name: string?,
	parent: Instance?,
	position: UDim2?,
	size: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

export type TabsApi = {
	Instance: ScrollingFrame,
	Changed: Signal.Signal,
	Select: (id: string, silent: boolean?) -> (),
	GetSelected: () -> string,
	Next: () -> (),
	Previous: () -> (),
	GetButton: (id: string) -> TextButton?,
}

type TabUi = { id: string, button: TextButton, face: Frame, label: TextLabel, feedback: Base.FeedbackApi }

local TAB_HEIGHT = Theme.Touch.Small

local Tabs = {}

-- Vrai si l'objet et tous ses ancêtres sont visibles (ScreenGui activé compris).
local function isShown(object: Instance): boolean
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

function Tabs.new(props: TabsProps): TabsApi
	local root = Instance.new("ScrollingFrame")
	root.Name = props.name or "Onglets"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = props.size or UDim2.new(1, 0, 0, TAB_HEIGHT + 10)
	root.ScrollingDirection = Enum.ScrollingDirection.X
	root.AutomaticCanvasSize = Enum.AutomaticSize.X
	root.CanvasSize = UDim2.new()
	root.ScrollBarThickness = 0
	root.Selectable = false
	root.ClipsDescendants = true
	Base.list(root, Enum.FillDirection.Horizontal, Theme.Spacing.S, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	Base.padding(root, nil, 4, 2)
	local trove = Base.lifetime(root)

	local changed = Signal.new()
	trove:Add(changed)

	local uis: { TabUi } = {}
	local selected = props.selected or (if props.tabs[1] then props.tabs[1].id else "")

	local function render()
		for _, ui in uis do
			local active = ui.id == selected
			local style = Theme.variant(if active then "Primary" else "Dark")
			ui.label.TextColor3 = style.text
			ui.feedback.SetColors(style.background, style.hover, style.pressed)
			Theme.tween(ui.face, Theme.Motion.Fast, { Position = UDim2.fromOffset(0, if active then 0 else 3) })
		end
	end

	local api = {} :: TabsApi

	local function select(id: string, silent: boolean?)
		if id == selected then
			return
		end
		local found = false
		for _, ui in uis do
			if ui.id == id then
				found = true
				break
			end
		end
		if not found then
			return
		end
		selected = id
		render()
		if not silent then
			changed:Fire(id)
			Base.safeCall(props.onChanged, id)
		end
	end

	for index, def in props.tabs do
		local button = Instance.new("TextButton")
		button.Name = "Onglet_" .. def.id
		button.AutoButtonColor = false
		button.BackgroundTransparency = 1
		button.Text = ""
		button.LayoutOrder = index
		button.AutomaticSize = Enum.AutomaticSize.X
		button.Size = UDim2.fromOffset(0, TAB_HEIGHT + 4)
		Base.makeSelectable(button, "Pill")
		button.Parent = root

		local face = Instance.new("Frame")
		face.Name = "Face"
		face.BorderSizePixel = 0
		face.AutomaticSize = Enum.AutomaticSize.X
		face.Size = UDim2.fromOffset(0, TAB_HEIGHT)
		Base.corner(face, "Pill")
		Base.stroke(face, Theme.Colors.Ink, Theme.StrokeWidth.Normal)
		Base.padding(face, nil, 18, 0)
		face.Parent = button

		local label = Base.newText("Libelle", "Body", "Display")
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromOffset(0, TAB_HEIGHT)
		label.TextXAlignment = Enum.TextXAlignment.Center
		if def.key then
			Base.setText(label, nil, def.key, nil)
		else
			label.Text = def.text or def.id
		end
		if def.glyph and def.glyph ~= "" then
			-- Le glyphe précède le libellé (retraduction : la clé est réappliquée puis le glyphe ré-ajouté).
			local glyph = def.glyph
			local function decorate()
				local text = label.Text
				if string.sub(text, 1, #glyph) ~= glyph then
					label.Text = glyph .. "  " .. text
				end
			end
			label:GetPropertyChangedSignal("Text"):Connect(decorate)
			decorate()
		end
		label.Parent = face

		local feedback = Base.attachFeedback(button, { colorTarget = face }, trove)
		trove:Connect(button.Activated, function()
			if def.id ~= selected then
				Base.playSound("ui_click")
			end
			select(def.id)
		end)
		table.insert(uis, { id = def.id, button = button, face = face, label = label, feedback = feedback })
	end

	-- Navigation manette horizontale entre onglets (pas d'échappement accidentel vers le haut).
	for index, ui in uis do
		local previous = uis[index - 1]
		local nextUi = uis[index + 1]
		if previous then
			ui.button.NextSelectionLeft = previous.button
		end
		if nextUi then
			ui.button.NextSelectionRight = nextUi.button
		end
	end

	local function step(delta: number)
		if #uis == 0 then
			return
		end
		local current = 1
		for index, ui in uis do
			if ui.id == selected then
				current = index
				break
			end
		end
		local target = ((current - 1 + delta) % #uis) + 1
		Base.playSound("ui_click")
		select(uis[target].id)
	end

	if props.shoulderButtons ~= false then
		trove:Connect(UserInputService.InputBegan, function(input: InputObject)
			if input.KeyCode ~= Enum.KeyCode.ButtonL1 and input.KeyCode ~= Enum.KeyCode.ButtonR1 then
				return
			end
			if not isShown(root) then
				return
			end
			step(if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1)
		end)
	end

	render()

	api.Instance = root
	api.Changed = changed
	api.Select = select

	function api.GetSelected(): string
		return selected
	end

	function api.Next()
		step(1)
	end

	function api.Previous()
		step(-1)
	end

	function api.GetButton(id: string): TextButton?
		for _, ui in uis do
			if ui.id == id then
				return ui.button
			end
		end
		return nil
	end

	Base.applyCommon(root, {
		position = props.position,
		anchorPoint = props.anchorPoint,
		layoutOrder = props.layoutOrder,
		zIndex = props.zIndex,
		visible = props.visible,
	})
	if props.parent then
		root.Parent = props.parent
	end
	return api
end

return Tabs
