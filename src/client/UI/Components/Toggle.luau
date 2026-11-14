--!strict
--[[
	Toggle — interrupteur cartoon (rail en pastille + bouton rond qui glisse) avec libellé d'état « Activé /
	Désactivé » : l'état ne repose jamais sur la seule couleur. Sélectionnable à la manette (A bascule).

	  local toggle = Toggle.new({ value = true, parent = row, onChanged = function(v) ... end })
	  toggle.Set(false, true)   toggle.Get()   toggle.SetEnabled(false)   toggle.Changed:Connect(fn)

	Props : value ; onChanged ; disabled ; showState (true : libellé à droite) ; onKey / offKey (défaut
	"ui.on" / "ui.off") ; + communs (name, parent, position, anchorPoint, layoutOrder, zIndex, visible).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)

local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Base)

export type ToggleProps = {
	value: boolean?,
	onChanged: ((value: boolean) -> ())?,
	disabled: boolean?,
	showState: boolean?,
	onKey: string?,
	offKey: string?,
	name: string?,
	parent: Instance?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

export type ToggleApi = {
	Instance: TextButton,
	Changed: Signal.Signal,
	Set: (value: boolean, silent: boolean?) -> (),
	Get: () -> boolean,
	SetEnabled: (enabled: boolean) -> (),
}

local TRACK_W = 76
local TRACK_H = Theme.Touch.Min
local KNOB = TRACK_H - 10
local STATE_W = 110

local Toggle = {}

function Toggle.new(props: ToggleProps): ToggleApi
	local value = props.value == true
	local enabled = props.disabled ~= true
	local showState = props.showState ~= false

	local root = Instance.new("TextButton")
	root.Name = props.name or "Interrupteur"
	root.AutoButtonColor = false
	root.BackgroundTransparency = 1
	root.Text = ""
	root.Size = UDim2.fromOffset(TRACK_W + (if showState then STATE_W + 8 else 0), TRACK_H)
	Base.makeSelectable(root, "Pill")
	root.Selectable = enabled
	local trove = Base.lifetime(root)

	local track = Instance.new("Frame")
	track.Name = "Rail"
	track.BorderSizePixel = 0
	track.Size = UDim2.fromOffset(TRACK_W, TRACK_H)
	Base.corner(track, "Pill")
	Base.stroke(track, Theme.Colors.Ink, Theme.StrokeWidth.Normal)
	track.Parent = root

	-- Ombre intérieure du rail (creux).
	local groove = Instance.new("Frame")
	groove.Name = "Creux"
	groove.BorderSizePixel = 0
	groove.BackgroundColor3 = Theme.Colors.Ink
	groove.BackgroundTransparency = 0.8
	groove.Position = UDim2.fromOffset(4, 4)
	groove.Size = UDim2.new(1, -8, 0, 6)
	Base.corner(groove, "Pill")
	groove.Parent = track

	local knob = Instance.new("Frame")
	knob.Name = "Bouton"
	knob.BorderSizePixel = 0
	knob.BackgroundColor3 = Theme.Colors.Paper
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Size = UDim2.fromOffset(KNOB, KNOB)
	knob.ZIndex = 2
	Base.corner(knob, "Pill")
	Base.stroke(knob, Theme.Colors.Ink, Theme.StrokeWidth.Normal)
	knob.Parent = track

	local mark = Base.newText("Marque", "Body", "Display", Theme.Colors.Ink)
	mark.Size = UDim2.fromScale(1, 1)
	mark.TextXAlignment = Enum.TextXAlignment.Center
	mark.ZIndex = 3
	mark.Parent = knob

	local stateLabel = Base.newText("Etat", "Body", "Bold", Theme.Colors.Paper)
	stateLabel.Position = UDim2.fromOffset(TRACK_W + 10, 0)
	stateLabel.Size = UDim2.fromOffset(STATE_W, TRACK_H)
	stateLabel.Visible = showState
	stateLabel.Parent = root

	local changed = Signal.new()
	trove:Add(changed)

	local function render(animate: boolean)
		local color = if not enabled then Theme.Colors.Disabled elseif value then Theme.Colors.Success else Theme.Colors.NightHover
		Theme.fade(track, Theme.Motion.Fast, { BackgroundColor3 = color })
		local target = if value then UDim2.new(0, TRACK_W - KNOB - 5, 0.5, 0) else UDim2.new(0, 5, 0.5, 0)
		if animate then
			Theme.tween(knob, Theme.Motion.Normal, { Position = target }, Enum.EasingStyle.Back)
		else
			knob.Position = target
		end
		mark.Text = if value then "✓" else ""
		stateLabel.TextColor3 = if enabled then Theme.Colors.Paper else Theme.Colors.DisabledText
		Base.setText(stateLabel, nil, if value then (props.onKey or "ui.on") else (props.offKey or "ui.off"), nil)
	end

	local api = {} :: ToggleApi

	local function set(newValue: boolean, silent: boolean?)
		if newValue == value then
			return
		end
		value = newValue
		render(true)
		if not silent then
			changed:Fire(value)
			Base.safeCall(props.onChanged, value)
		end
	end

	trove:Connect(root.Activated, function()
		if not enabled then
			Base.playSound("ui_error")
			return
		end
		Base.playSound("ui_click")
		set(not value)
	end)
	trove:Connect(root.SelectionGained, function()
		if enabled then
			Base.playSound("ui_hover")
		end
	end)
	trove:Connect(root.MouseEnter, function()
		if enabled then
			Theme.fade(knob, Theme.Motion.Fast, { BackgroundColor3 = Theme.Colors.White })
		end
	end)
	trove:Connect(root.MouseLeave, function()
		Theme.fade(knob, Theme.Motion.Fast, { BackgroundColor3 = Theme.Colors.Paper })
	end)

	render(false)

	api.Instance = root
	api.Changed = changed
	api.Set = set

	function api.Get(): boolean
		return value
	end

	function api.SetEnabled(newEnabled: boolean)
		enabled = newEnabled
		root.Selectable = newEnabled
		render(false)
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

return Toggle
