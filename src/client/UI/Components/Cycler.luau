--!strict
--[[
	Cycler — sélecteur de valeur façon liste déroulante, compatible manette : [◀]  Valeur  [▶].
	Clic / toucher sur une flèche : valeur précédente / suivante ; clic au centre (ou A) : valeur suivante.
	Manette / clavier : Gauche / Droite quand le sélecteur est focalisé (la sélection reste dessus).
	Des points sous la valeur indiquent la position dans la liste.

	  local mode = Cycler.new({ options = { { value = "FreeForAll", key = "match.mode.FreeForAll" }, ... },
	                            value = "FreeForAll", width = 280, parent = row,
	                            onChanged = function(value) ... end })
	  mode.Set("Teams", true)   mode.Get()   mode.SetOptions(options, value?)   mode.SetEnabled(false)

	Props : options ({ value: any, key: string?, vars?, text: string? }) ; value ; onChanged ; width (px design,
	260) ; wrap (true : boucle en fin de liste) ; disabled ; showDots (true si <= 8 options) ; + communs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)

local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Base)

export type CyclerOption = { value: any, key: string?, vars: { [string]: any }?, text: string? }

export type CyclerProps = {
	options: { CyclerOption },
	value: any?,
	onChanged: ((value: any) -> ())?,
	width: number?,
	wrap: boolean?,
	disabled: boolean?,
	showDots: boolean?,
	name: string?,
	parent: Instance?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

export type CyclerApi = {
	Instance: TextButton,
	Changed: Signal.Signal,
	Set: (value: any, silent: boolean?) -> (),
	Get: () -> any,
	SetOptions: (options: { CyclerOption }, value: any?) -> (),
	SetEnabled: (enabled: boolean) -> (),
}

local HEIGHT = Theme.Touch.Min
local ARROW_W = Theme.Touch.Min
local STICK_THRESHOLD = 0.6
local STICK_REPEAT = 0.22

local Cycler = {}

function Cycler.new(props: CyclerProps): CyclerApi
	local width = props.width or 260
	local options = props.options
	local wrap = props.wrap ~= false
	local enabled = props.disabled ~= true
	local index = 1
	for i, option in options do
		if option.value == props.value then
			index = i
			break
		end
	end

	local root = Instance.new("TextButton")
	root.Name = props.name or "Selecteur"
	root.AutoButtonColor = false
	root.BackgroundTransparency = 1
	root.Text = ""
	root.Size = UDim2.fromOffset(width, HEIGHT)
	Base.makeSelectable(root, "Rounded")
	root.Selectable = enabled
	root.NextSelectionLeft = root
	root.NextSelectionRight = root
	local trove = Base.lifetime(root)

	local body = Instance.new("Frame")
	body.Name = "Corps"
	body.BorderSizePixel = 0
	body.BackgroundColor3 = Theme.Colors.NightRaised
	body.Size = UDim2.fromScale(1, 1)
	Base.corner(body, "Medium")
	Base.stroke(body, Theme.Colors.Ink, Theme.StrokeWidth.Normal)
	body.Parent = root

	local function makeArrow(name: string, glyph: string, anchorX: number): (TextButton, Frame)
		local arrow = Instance.new("TextButton")
		arrow.Name = name
		arrow.AutoButtonColor = false
		arrow.Selectable = false
		arrow.Text = ""
		arrow.BackgroundTransparency = 1
		arrow.AnchorPoint = Vector2.new(anchorX, 0.5)
		arrow.Position = UDim2.new(anchorX, if anchorX == 0 then 3 else -3, 0.5, 0)
		arrow.Size = UDim2.fromOffset(ARROW_W - 6, HEIGHT - 6)
		arrow.ZIndex = 3
		arrow.Parent = body

		local face = Instance.new("Frame")
		face.Name = "Face"
		face.BorderSizePixel = 0
		face.BackgroundColor3 = Theme.Colors.Primary
		face.Size = UDim2.fromScale(1, 1)
		face.ZIndex = 3
		Base.corner(face, "Small")
		Base.stroke(face, Theme.Colors.Ink, Theme.StrokeWidth.Thin)
		face.Parent = arrow

		local text = Base.newText("Glyphe", "Body", "Display", Theme.Colors.Ink)
		text.Size = UDim2.fromScale(1, 1)
		text.TextXAlignment = Enum.TextXAlignment.Center
		text.ZIndex = 4
		text.Text = glyph
		text.Parent = face
		return arrow, face
	end

	local leftArrow, leftFace = makeArrow("Precedent", "◀", 0)
	local rightArrow, rightFace = makeArrow("Suivant", "▶", 1)

	local valueLabel = Base.newText("Valeur", "Body", "Bold", Theme.Colors.Paper)
	valueLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	valueLabel.Position = UDim2.new(0.5, 0, 0.5, -3)
	valueLabel.Size = UDim2.new(1, -ARROW_W * 2 - 4, 1, -10)
	valueLabel.TextXAlignment = Enum.TextXAlignment.Center
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
	valueLabel.ZIndex = 2
	valueLabel.Parent = body

	local dots = Instance.new("Frame")
	dots.Name = "Points"
	dots.BackgroundTransparency = 1
	dots.AnchorPoint = Vector2.new(0.5, 1)
	dots.Position = UDim2.new(0.5, 0, 1, -4)
	dots.Size = UDim2.new(1, -ARROW_W * 2, 0, 6)
	dots.ZIndex = 2
	Base.list(dots, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	dots.Parent = body

	local changed = Signal.new()
	trove:Add(changed)

	local function rebuildDots()
		for _, child in dots:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local show = if props.showDots ~= nil then props.showDots else #options <= 8
		dots.Visible = show and #options > 1
		if not dots.Visible then
			return
		end
		for i = 1, #options do
			local dot = Instance.new("Frame")
			dot.Name = "Point" .. i
			dot.BorderSizePixel = 0
			dot.Size = UDim2.fromOffset(5, 5)
			dot.LayoutOrder = i
			dot.ZIndex = 2
			Base.corner(dot, "Pill")
			dot.Parent = dots
		end
	end

	local function render()
		local option = options[index]
		if option then
			if option.key then
				Base.setText(valueLabel, nil, option.key, option.vars)
			else
				Base.setText(valueLabel, option.text or tostring(option.value), nil, nil)
			end
		else
			Base.setText(valueLabel, "—", nil, nil)
		end
		valueLabel.TextColor3 = if enabled then Theme.Colors.Paper else Theme.Colors.DisabledText
		local canPrev = enabled and #options > 1 and (wrap or index > 1)
		local canNext = enabled and #options > 1 and (wrap or index < #options)
		leftFace.BackgroundColor3 = if canPrev then Theme.Colors.Primary else Theme.Colors.Disabled
		rightFace.BackgroundColor3 = if canNext then Theme.Colors.Primary else Theme.Colors.Disabled
		leftArrow.Visible = enabled
		rightArrow.Visible = enabled
		for _, child in dots:GetChildren() do
			if child:IsA("Frame") then
				child.BackgroundColor3 = if child.LayoutOrder == index then Theme.Colors.Primary else Theme.Colors.PaperDim
				child.BackgroundTransparency = if child.LayoutOrder == index then 0 else 0.5
			end
		end
	end

	local function step(direction: number)
		if not enabled or #options < 2 then
			return
		end
		local target = index + direction
		if target < 1 or target > #options then
			if not wrap then
				Base.playSound("ui_error", 0.6)
				return
			end
			target = ((target - 1) % #options) + 1
		end
		index = target
		render()
		Base.playSound("ui_click", 0.8)
		-- Petit rebond de la valeur (coupé si effets réduits).
		if not Theme.isReducedMotion() then
			valueLabel.Position = UDim2.new(0.5, direction * 10, 0.5, -3)
			Theme.tween(valueLabel, Theme.Motion.Normal, { Position = UDim2.new(0.5, 0, 0.5, -3) }, Enum.EasingStyle.Back)
		end
		local option = options[index]
		changed:Fire(option.value)
		Base.safeCall(props.onChanged, option.value)
	end

	trove:Connect(leftArrow.Activated, function()
		step(-1)
	end)
	trove:Connect(rightArrow.Activated, function()
		step(1)
	end)
	trove:Connect(root.Activated, function()
		step(1)
	end)
	trove:Connect(root.SelectionGained, function()
		if enabled then
			Base.playSound("ui_hover")
		end
		Theme.fade(body, Theme.Motion.Fast, { BackgroundColor3 = Theme.Colors.NightHover })
	end)
	trove:Connect(root.SelectionLost, function()
		Theme.fade(body, Theme.Motion.Fast, { BackgroundColor3 = Theme.Colors.NightRaised })
	end)
	trove:Connect(root.MouseEnter, function()
		Theme.fade(body, Theme.Motion.Fast, { BackgroundColor3 = Theme.Colors.NightHover })
	end)
	trove:Connect(root.MouseLeave, function()
		if GuiService.SelectedObject ~= root then
			Theme.fade(body, Theme.Motion.Fast, { BackgroundColor3 = Theme.Colors.NightRaised })
		end
	end)

	trove:Connect(UserInputService.InputBegan, function(input: InputObject)
		if GuiService.SelectedObject ~= root then
			return
		end
		if input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.Left then
			step(-1)
		elseif input.KeyCode == Enum.KeyCode.DPadRight or input.KeyCode == Enum.KeyCode.Right then
			step(1)
		end
	end)
	local lastStick = 0
	trove:Connect(UserInputService.InputChanged, function(input: InputObject)
		if input.KeyCode ~= Enum.KeyCode.Thumbstick1 or GuiService.SelectedObject ~= root then
			return
		end
		local x = input.Position.X
		if math.abs(x) < STICK_THRESHOLD then
			lastStick = 0
			return
		end
		local now = os.clock()
		if now - lastStick >= STICK_REPEAT then
			lastStick = now
			step(if x > 0 then 1 else -1)
		end
	end)

	rebuildDots()
	render()

	local api = {} :: CyclerApi
	api.Instance = root
	api.Changed = changed

	function api.Set(value: any, silent: boolean?)
		for i, option in options do
			if option.value == value then
				if i ~= index then
					index = i
					render()
					if not silent then
						changed:Fire(option.value)
						Base.safeCall(props.onChanged, option.value)
					end
				end
				return
			end
		end
	end

	function api.Get(): any
		local option = options[index]
		return if option then option.value else nil
	end

	function api.SetOptions(newOptions: { CyclerOption }, value: any?)
		local current = if value ~= nil then value else api.Get()
		options = newOptions
		index = 1
		for i, option in options do
			if option.value == current then
				index = i
				break
			end
		end
		rebuildDots()
		render()
	end

	function api.SetEnabled(newEnabled: boolean)
		enabled = newEnabled
		root.Selectable = newEnabled
		render()
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

return Cycler
