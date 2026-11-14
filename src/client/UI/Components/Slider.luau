--!strict
--[[
	Slider — curseur de valeur (rail, remplissage coloré, poignée ronde, valeur affichée en texte).
	Souris / tactile : glisser ou toucher le rail. Manette / clavier : quand le curseur est sélectionné,
	Gauche / Droite (croix, stick, flèches) changent la valeur d'un pas (la sélection reste sur le curseur).

	  local volume = Slider.new({ min = 0, max = 1, step = 0.05, value = 0.8, parent = row,
	                              format = function(v) return math.round(v * 100) .. " %" end,
	                              onChanged = function(v) ... end })      -- à chaque changement de valeur
	  volume.Set(0.5, true)   volume.Get()   volume.SetEnabled(false)   volume.Changed:Connect(fn)
	  volume.Released:Connect(fn)   -- fin d'un glissement (ou pas manette) : valeur définitive

	Props : min, max, step ; value ; format(v) -> string ; onChanged ; onReleased ; width (px design, 220) ;
	disabled ; color (remplissage, Secondary) ; + communs (name, parent, position, anchorPoint, layoutOrder,
	zIndex, visible).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)

local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Base)

export type SliderProps = {
	min: number,
	max: number,
	step: number?,
	value: number?,
	format: ((value: number) -> string)?,
	onChanged: ((value: number) -> ())?,
	onReleased: ((value: number) -> ())?,
	width: number?,
	disabled: boolean?,
	color: Color3?,
	name: string?,
	parent: Instance?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

export type SliderApi = {
	Instance: TextButton,
	Changed: Signal.Signal,
	Released: Signal.Signal,
	Set: (value: number, silent: boolean?) -> (),
	Get: () -> number,
	SetEnabled: (enabled: boolean) -> (),
}

local HEIGHT = Theme.Touch.Min
local TRACK_H = 14
local KNOB = 30
local VALUE_W = 72
local STICK_THRESHOLD = 0.6
local STICK_REPEAT = 0.16

local LEFT_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.DPadLeft] = true,
	[Enum.KeyCode.Left] = true,
}
local RIGHT_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.DPadRight] = true,
	[Enum.KeyCode.Right] = true,
}

local Slider = {}

function Slider.new(props: SliderProps): SliderApi
	local minimum = props.min
	local maximum = math.max(props.max, minimum + 1e-6)
	local step = props.step or (maximum - minimum) / 20
	local width = props.width or 220
	local enabled = props.disabled ~= true
	local fillColor = props.color or Theme.Colors.Secondary

	local function quantize(raw: number): number
		local clamped = math.clamp(raw, minimum, maximum)
		if step > 0 then
			clamped = minimum + math.floor((clamped - minimum) / step + 0.5) * step
		end
		-- Arrondi d'affichage (évite 0.30000000004).
		clamped = math.floor(clamped * 10000 + 0.5) / 10000
		return math.clamp(clamped, minimum, maximum)
	end

	local value = quantize(props.value or minimum)

	local root = Instance.new("TextButton")
	root.Name = props.name or "Curseur"
	root.AutoButtonColor = false
	root.BackgroundTransparency = 1
	root.Text = ""
	root.Size = UDim2.fromOffset(width + VALUE_W + 10, HEIGHT)
	Base.makeSelectable(root, "Rounded")
	root.Selectable = enabled
	-- La sélection manette reste sur le curseur à gauche/droite : ces directions règlent la valeur.
	root.NextSelectionLeft = root
	root.NextSelectionRight = root
	local trove = Base.lifetime(root)

	local trackHit = Instance.new("Frame")
	trackHit.Name = "ZoneRail"
	trackHit.BackgroundTransparency = 1
	trackHit.Size = UDim2.fromOffset(width, HEIGHT)
	trackHit.Parent = root

	local track = Instance.new("Frame")
	track.Name = "Rail"
	track.BorderSizePixel = 0
	track.BackgroundColor3 = Theme.Colors.Ink
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, KNOB / 2, 0.5, 0)
	track.Size = UDim2.new(1, -KNOB, 0, TRACK_H)
	Base.corner(track, "Pill")
	Base.stroke(track, Theme.Colors.Ink, Theme.StrokeWidth.Thin)
	track.Parent = trackHit

	local fill = Instance.new("Frame")
	fill.Name = "Remplissage"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = fillColor
	fill.Size = UDim2.fromScale(0, 1)
	Base.corner(fill, "Pill")
	fill.Parent = track

	local knob = Instance.new("Frame")
	knob.Name = "Poignee"
	knob.BorderSizePixel = 0
	knob.BackgroundColor3 = Theme.Colors.Paper
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(KNOB, KNOB)
	knob.ZIndex = 2
	Base.corner(knob, "Pill")
	Base.stroke(knob, Theme.Colors.Ink, Theme.StrokeWidth.Normal)
	knob.Parent = track

	local knobScale = Instance.new("UIScale")
	knobScale.Parent = knob

	local valueLabel = Base.newText("Valeur", "Body", "Bold", Theme.Colors.Paper)
	valueLabel.Position = UDim2.fromOffset(width + 10, 0)
	valueLabel.Size = UDim2.fromOffset(VALUE_W, HEIGHT)
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Parent = root

	local changed = Signal.new()
	local released = Signal.new()
	trove:Add(changed)
	trove:Add(released)

	local function formatValue(v: number): string
		if props.format then
			local ok, text = pcall(props.format, v)
			if ok and type(text) == "string" then
				return text
			end
		end
		return tostring(v)
	end

	local function render()
		local alpha = (value - minimum) / (maximum - minimum)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		valueLabel.Text = formatValue(value)
		fill.BackgroundColor3 = if enabled then fillColor else Theme.Colors.Disabled
		valueLabel.TextColor3 = if enabled then Theme.Colors.Paper else Theme.Colors.DisabledText
	end

	local function set(newValue: number, silent: boolean?)
		local q = quantize(newValue)
		if q == value then
			return
		end
		value = q
		render()
		if not silent then
			changed:Fire(value)
			Base.safeCall(props.onChanged, value)
		end
	end

	local function release()
		released:Fire(value)
		Base.safeCall(props.onReleased, value)
	end

	-- Glissement souris / tactile.
	local dragging: InputObject? = nil
	local function valueFromX(x: number): number
		local left = track.AbsolutePosition.X
		local w = math.max(track.AbsoluteSize.X, 1)
		return minimum + math.clamp((x - left) / w, 0, 1) * (maximum - minimum)
	end

	trove:Connect(root.InputBegan, function(input: InputObject)
		if not enabled then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			dragging = input
			Theme.tween(knobScale, Theme.Motion.Fast, { Scale = 1.15 })
			set(valueFromX(input.Position.X))
		end
	end)
	trove:Connect(UserInputService.InputChanged, function(input: InputObject)
		local drag = dragging
		if not drag then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input == drag then
			set(valueFromX(input.Position.X))
		end
	end)
	trove:Connect(UserInputService.InputEnded, function(input: InputObject)
		local drag = dragging
		if not drag then
			return
		end
		if input == drag or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = nil
			Theme.tween(knobScale, Theme.Motion.Fast, { Scale = 1 })
			Base.playSound("ui_click", 0.6)
			release()
		end
	end)

	-- Pas à pas (manette, clavier) quand le curseur est focalisé.
	local function nudge(direction: number)
		if not enabled then
			return
		end
		local before = value
		set(value + direction * step)
		if value ~= before then
			Base.playSound("ui_hover")
			release()
		end
	end

	trove:Connect(UserInputService.InputBegan, function(input: InputObject)
		if GuiService.SelectedObject ~= root then
			return
		end
		if LEFT_KEYS[input.KeyCode] then
			nudge(-1)
		elseif RIGHT_KEYS[input.KeyCode] then
			nudge(1)
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
			nudge(if x > 0 then 1 else -1)
		end
	end)

	trove:Connect(root.SelectionGained, function()
		if enabled then
			Base.playSound("ui_hover")
			Theme.tween(knobScale, Theme.Motion.Fast, { Scale = 1.12 })
		end
	end)
	trove:Connect(root.SelectionLost, function()
		Theme.tween(knobScale, Theme.Motion.Fast, { Scale = 1 })
	end)

	render()

	local api = {} :: SliderApi
	api.Instance = root
	api.Changed = changed
	api.Released = released
	api.Set = set

	function api.Get(): number
		return value
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

return Slider
