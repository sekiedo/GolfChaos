--!strict
--[[
	InputController — entrées du joueur local : appareil courant, actions liées, boutons tactiles.

	Contrat (docs/ARCHITECTURE.md §9) :
	  InputController.GetDevice() -> "KeyboardMouse" | "Touch" | "Gamepad"   (déduit de la dernière entrée)
	  InputController.DeviceChanged : Signal(nouveauDevice, ancienDevice)
	  InputController.Bind(action, callback(state, input?), touches...)        (priorité « Gameplay »)
	  InputController.Unbind(action)

	Compléments propres à ce module :
	  InputController.Priorities = { Gameplay, Aim, Modal }
	  InputController.BindAtPriority(action, priorite, callback, touches...)
	  InputController.IsBound(action) -> boolean
	  InputController.Trigger(action, state?)                    -- déclenche l'action par code (bouton d'UI)
	  InputController.GetKeyLabel(action, device?) -> string     -- libellé de la touche liée pour cet appareil
	  InputController.GetKeyCodeLabel(keyCode) -> string         -- libellé d'une touche (disposition du clavier)
	  InputController.GetLastInputTime() -> number               -- os.clock() de la dernière entrée du joueur
	  InputController.Activity : Signal()                        -- au plus une fois par seconde quand le joueur agit
	  Boutons tactiles (équivalent tactile d'une action liée ; visibles seulement si l'action est liée) :
	  InputController.SetTouchButton(action, { text, slot?, color?, indicator?, visible? } | nil)
	  InputController.SetTouchButtonVisible(action, visible)
	  InputController.SetTouchButtonText(action, text)
	  InputController.SetTouchButtonActive(action, active)       -- état « enclenché » (bascule, verrou...)
	  InputController.StartCooldown(action, secondes)            -- attente affichée localement (le serveur décide)
	  InputController.SetTouchControlsSuppressed(raison, masque) -- masque tous les boutons (menus plein écran)

	Règles :
	  - callback(state, input) reçoit un Enum.UserInputState : Begin, Change (molette, sticks), End ou Cancel
	    (Cancel = l'entrée a été reprise par une action prioritaire : à traiter comme un relâchement).
	  - callback peut retourner false pour laisser passer l'entrée aux actions de priorité inférieure ;
	    sinon l'entrée est consommée (ex. Espace ne fait pas sauter pendant la visée).
	  - Les Enum.KeyCode sont des positions physiques (disposition QWERTY US) : sur un clavier AZERTY,
	    KeyCode.Q est la touche « A ». Les textes d'aide affichent donc toujours GetKeyLabel / GetKeyCodeLabel,
	    jamais une lettre écrite en dur.
	  - Les liaisons passent par ContextActionService (priorités, consommation des entrées par défaut du
	    PlayerModule : saut, zoom...). Une migration vers l'Input Action System resterait locale à ce module.
	  - Aucun effet de bord au require : écouteurs branchés dans Init, interface créée dans Start.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage.Shared
local Signal = require(Shared.Util.Signal)
local Trove = require(Shared.Util.Trove)
local Log = require(Shared.Util.Log)
local Locale = require(Shared.Locale)

export type Device = "KeyboardMouse" | "Touch" | "Gamepad"
export type InputKey = Enum.KeyCode | Enum.UserInputType | Enum.PlayerActions
export type ActionCallback = (state: Enum.UserInputState, input: InputObject?) -> boolean?
export type TouchSlot = "ActionA" | "ActionB" | "ActionC" | "ActionD" | "LeftUpper" | "LeftLower" | "TopRight"
export type TouchButtonOptions = {
	text: string, -- libellé déjà traduit (Locale.t)
	slot: TouchSlot?, -- emplacement à l'écran (défaut "ActionA")
	color: Color3?, -- couleur de fond
	indicator: boolean?, -- true : aussi affiché au clavier/manette comme indicateur (touche + attente)
	visible: boolean?, -- visibilité demandée (défaut true)
}

type Binding = {
	action: string,
	casName: string,
	callback: ActionCallback,
	keys: { InputKey },
	priority: number,
}

type ButtonUi = {
	button: TextButton,
	label: TextLabel,
	stroke: UIStroke,
	overlay: Frame,
	countdown: TextLabel,
	badge: TextLabel,
}

type TouchButton = {
	action: string,
	options: TouchButtonOptions,
	visible: boolean,
	active: boolean,
	pressedInput: InputObject?,
	cooldownEndsAt: number,
	cooldownTotal: number,
	cooldownThread: thread?,
	ui: ButtonUi?,
	trove: Trove.Trove,
}

local InputController = {}
InputController.Priority = 0

-- Niveaux de priorité (ContextActionService) : plus haut = servi en premier.
InputController.Priorities = {
	Gameplay = Enum.ContextActionPriority.High.Value, -- au-dessus des contrôles par défaut (saut, caméra)
	Aim = Enum.ContextActionPriority.High.Value + 100, -- visée : prioritaire sur le combat et le déplacement
	Modal = Enum.ContextActionPriority.High.Value + 500, -- séquences modales (survol d'intro, menus)
}

InputController.DeviceChanged = Signal.new()
InputController.Activity = Signal.new()

local ACTION_PREFIX = "GolfChaos_"
local MOUSE_SWITCH_DELTA = 3 -- pixels : un micro-déplacement de souris ne bascule pas l'appareil
local STICK_SWITCH_THRESHOLD = 0.35 -- un stick qui dérive légèrement ne bascule pas l'appareil
local TRIGGER_SWITCH_THRESHOLD = 0.3
local ACTIVITY_INTERVAL = 1 -- secondes entre deux signaux Activity

local BUTTON_BACKGROUND = Color3.fromRGB(18, 20, 28)
local BUTTON_STROKE = Color3.fromRGB(255, 255, 255)
local BUTTON_ACTIVE_STROKE = Color3.fromRGB(255, 214, 64)
local BUTTON_TEXT = Color3.fromRGB(255, 255, 255)
local INDICATOR_SCALE = 0.72

local localPlayer = Players.LocalPlayer

local state = {
	device = "KeyboardMouse" :: Device,
	initialized = false,
	lastInputTime = os.clock(),
	lastActivityFire = 0,
	gui = nil :: ScreenGui?,
}

local bindings: { [string]: Binding } = {}
local touchButtons: { [string]: TouchButton } = {}
local suppressedReasons: { [string]: boolean } = {}
local runtimeTrove: Trove.Trove = Trove.new()

--------------------------------------------------------------------------------
-- Classification des entrées
--------------------------------------------------------------------------------

local function isGamepadInputType(inputType: Enum.UserInputType): boolean
	return string.sub(inputType.Name, 1, 7) == "Gamepad"
end

local function isGamepadKeyCode(keyCode: Enum.KeyCode): boolean
	local name = keyCode.Name
	return string.sub(name, 1, 6) == "Button" or string.sub(name, 1, 4) == "DPad" or string.sub(name, 1, 10) == "Thumbstick"
end

local function isKeyboardMouseInputType(inputType: Enum.UserInputType): boolean
	return inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseButton3
		or inputType == Enum.UserInputType.MouseWheel
		or inputType == Enum.UserInputType.MouseMovement
end

-- Appareil correspondant à une entrée, ou nil si l'entrée n'est pas assez franche pour basculer.
local function deviceFromInput(input: InputObject, isChange: boolean): Device?
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif inputType == Enum.UserInputType.MouseMovement then
		if input.Delta.Magnitude >= MOUSE_SWITCH_DELTA then
			return "KeyboardMouse"
		end
		return nil
	elseif isKeyboardMouseInputType(inputType) then
		return "KeyboardMouse"
	elseif isGamepadInputType(inputType) then
		if isChange then
			local keyCode = input.KeyCode
			local position = input.Position
			if keyCode == Enum.KeyCode.Thumbstick1 or keyCode == Enum.KeyCode.Thumbstick2 then
				if Vector2.new(position.X, position.Y).Magnitude < STICK_SWITCH_THRESHOLD then
					return nil
				end
			elseif keyCode == Enum.KeyCode.ButtonL2 or keyCode == Enum.KeyCode.ButtonR2 then
				if position.Z < TRIGGER_SWITCH_THRESHOLD then
					return nil
				end
			end
		end
		return "Gamepad"
	end
	return nil
end

-- Appareil par défaut quand aucune entrée n'a encore été vue (ou après débranchement d'une manette).
local function platformDefaultDevice(allowGamepad: boolean): Device
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	if allowGamepad and UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	end
	return "KeyboardMouse"
end

-- UserInputService.PreferredInput (récent) : lu par pcall pour rester compatible.
local function preferredInputDevice(): Device?
	local ok, preferred = pcall(function(): any
		return (UserInputService :: any).PreferredInput
	end)
	if not ok or typeof(preferred) ~= "EnumItem" then
		return nil
	end
	local name = (preferred :: EnumItem).Name
	if name == "Touch" then
		return "Touch"
	elseif name == "Gamepad" or name == "MicroGamepad" then
		return "Gamepad"
	elseif name == "KeyboardAndMouse" then
		return "KeyboardMouse"
	end
	return nil
end

local function initialDevice(): Device
	local preferred = preferredInputDevice()
	if preferred then
		return preferred
	end
	local lastType = UserInputService:GetLastInputType()
	if lastType == Enum.UserInputType.Touch then
		return "Touch"
	elseif isGamepadInputType(lastType) then
		return "Gamepad"
	elseif isKeyboardMouseInputType(lastType) then
		return "KeyboardMouse"
	end
	return platformDefaultDevice(true)
end

--------------------------------------------------------------------------------
-- Libellés de touches
--------------------------------------------------------------------------------

local function localizedKeyName(name: string): string?
	local key = "controls.key." .. name
	if Locale.has(key) or Locale.has(key, "fr") then
		return Locale.t(key)
	end
	return nil
end

function InputController.GetKeyCodeLabel(keyCode: Enum.KeyCode): string
	-- 1. Touches spéciales et manette : libellé traduit (Espace, Ctrl, A, LT...).
	local localized = localizedKeyName(keyCode.Name)
	if localized then
		return localized
	end
	-- 2. Lettres et chiffres : caractère réel selon la disposition du clavier (AZERTY, QWERTZ...).
	local ok, text = pcall(function(): string
		return UserInputService:GetStringForKeyCode(keyCode)
	end)
	if ok and type(text) == "string" and text ~= "" and text ~= " " then
		return string.upper(text)
	end
	return keyCode.Name
end

local function keyMatchesDevice(key: InputKey, device: Device): boolean
	local enumType = (key :: any).EnumType
	if enumType == Enum.KeyCode then
		local isPad = isGamepadKeyCode(key :: any)
		if device == "Gamepad" then
			return isPad
		end
		return device == "KeyboardMouse" and not isPad
	elseif enumType == Enum.UserInputType then
		if device == "Gamepad" then
			return isGamepadInputType(key :: any)
		end
		return device == "KeyboardMouse" and isKeyboardMouseInputType(key :: any)
	end
	return false
end

function InputController.GetKeyLabel(action: string, device: Device?): string
	local target: Device = device or state.device
	if target == "Touch" then
		local entry = touchButtons[action]
		return if entry then entry.options.text else ""
	end
	local binding = bindings[action]
	if not binding then
		return ""
	end
	for _, key in binding.keys do
		if keyMatchesDevice(key, target) then
			local enumType = (key :: any).EnumType
			if enumType == Enum.KeyCode then
				return InputController.GetKeyCodeLabel(key :: any)
			end
			local name = (key :: any).Name :: string
			return localizedKeyName(name) or name
		end
	end
	return ""
end

--------------------------------------------------------------------------------
-- Boutons tactiles
--------------------------------------------------------------------------------

-- Position (centre, AnchorPoint 0.5) et taille d'un emplacement. Les emplacements « Action » entourent
-- le bouton de saut par défaut de Roblox sans le recouvrir (petits écrans : saut 70 px ; grands : 120 px).
local function slotPlacement(slot: TouchSlot, viewport: Vector2): (UDim2, number)
	local small = math.min(viewport.X, viewport.Y) <= 500
	local size = if small then 56 else 76
	if slot == "ActionA" then -- à gauche du saut
		return (if small then UDim2.new(1, -150, 1, -52) else UDim2.new(1, -240, 1, -110)), size
	elseif slot == "ActionB" then -- au-dessus du saut
		return (if small then UDim2.new(1, -62, 1, -140) else UDim2.new(1, -110, 1, -268)), size
	elseif slot == "ActionC" then -- en diagonale, en haut à gauche du saut
		return (if small then UDim2.new(1, -140, 1, -125) else UDim2.new(1, -228, 1, -232)), size
	elseif slot == "ActionD" then -- plus à gauche
		return (if small then UDim2.new(1, -222, 1, -48) else UDim2.new(1, -350, 1, -100)), size
	elseif slot == "LeftUpper" then -- bord gauche, au-dessus du milieu (zone du stick, masqué pendant la visée)
		return UDim2.new(0, if small then 50 else 72, 0.5, if small then -36 else -48), size
	elseif slot == "LeftLower" then
		return UDim2.new(0, if small then 50 else 72, 0.5, if small then 36 else 48), size
	end
	-- TopRight : sous la barre supérieure, à droite (ex. « Passer »).
	return UDim2.new(1, if small then -60 else -90, 0, if small then 40 else 64), size
end

local function shouldShowButton(entry: TouchButton): boolean
	if not entry.visible or next(suppressedReasons) ~= nil then
		return false
	end
	if bindings[entry.action] == nil then
		return false
	end
	if state.device == "Touch" then
		return true
	end
	return entry.options.indicator == true
end

local function applyButtonLayout(entry: TouchButton)
	local ui = entry.ui
	local gui = state.gui
	if not ui or not gui then
		return
	end
	local position, size = slotPlacement(entry.options.slot or "ActionA", gui.AbsoluteSize)
	local indicatorMode = state.device ~= "Touch"
	local finalSize = if indicatorMode then math.floor(size * INDICATOR_SCALE) else size
	ui.button.Position = position
	ui.button.Size = UDim2.fromOffset(finalSize, finalSize)
end

local function applyButtonLook(entry: TouchButton)
	local ui = entry.ui
	if not ui then
		return
	end
	local show = shouldShowButton(entry)
	ui.button.Visible = show
	if not show then
		return
	end
	local indicatorMode = state.device ~= "Touch"
	ui.button.Active = not indicatorMode
	ui.button.BackgroundColor3 = entry.options.color or BUTTON_BACKGROUND
	ui.button.BackgroundTransparency = if indicatorMode then 0.45 else 0.2
	ui.label.Text = entry.options.text
	ui.stroke.Color = if entry.active then BUTTON_ACTIVE_STROKE else BUTTON_STROKE
	ui.stroke.Thickness = if entry.active then 3 else 2
	local keyLabel = if indicatorMode then InputController.GetKeyLabel(entry.action) else ""
	ui.badge.Visible = keyLabel ~= ""
	ui.badge.Text = keyLabel
	applyButtonLayout(entry)
end

local function releaseButton(entry: TouchButton, inputState: Enum.UserInputState)
	if not entry.pressedInput then
		return
	end
	entry.pressedInput = nil
	local ui = entry.ui
	if ui then
		ui.button.BackgroundTransparency = if state.device ~= "Touch" then 0.45 else 0.2
	end
	if bindings[entry.action] then
		InputController.Trigger(entry.action, inputState)
	end
end

local function stopCooldownThread(entry: TouchButton)
	local thread = entry.cooldownThread
	entry.cooldownThread = nil
	if thread and thread ~= coroutine.running() and coroutine.status(thread) ~= "dead" then
		pcall(task.cancel, thread)
	end
end

local function runCooldown(entry: TouchButton)
	stopCooldownThread(entry)
	local ui = entry.ui
	if not ui then
		return
	end
	if entry.cooldownEndsAt <= os.clock() then
		ui.overlay.Visible = false
		ui.countdown.Text = ""
		ui.label.TextTransparency = 0
		return
	end
	entry.cooldownThread = task.spawn(function()
		while true do
			local current = entry.ui
			if not current then
				break
			end
			local remaining = entry.cooldownEndsAt - os.clock()
			if remaining <= 0 then
				current.overlay.Visible = false
				current.countdown.Text = ""
				current.label.TextTransparency = 0
				break
			end
			local progress = 1 - remaining / math.max(entry.cooldownTotal, 1e-3)
			current.overlay.Visible = true
			current.overlay.BackgroundTransparency = 0.3 + 0.6 * math.clamp(progress, 0, 1)
			current.countdown.Text = if remaining >= 1 then tostring(math.ceil(remaining)) else ""
			current.label.TextTransparency = 0.55
			task.wait(0.05)
		end
		entry.cooldownThread = nil
	end)
end

local function buildButtonUi(entry: TouchButton, parent: ScreenGui): ButtonUi
	local button = Instance.new("TextButton")
	button.Name = entry.action
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = ""
	button.Selectable = false -- hors de la navigation manette des menus
	button.BackgroundColor3 = entry.options.color or BUTTON_BACKGROUND
	button.BackgroundTransparency = 0.2

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = BUTTON_STROKE
	stroke.Thickness = 2
	stroke.Transparency = 0.15
	stroke.Parent = button

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.84, 0.46)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = BUTTON_TEXT
	label.TextStrokeTransparency = 0.6
	label.Text = entry.options.text
	label.ZIndex = 2
	label.Parent = button
	local sizeLimit = Instance.new("UITextSizeConstraint")
	sizeLimit.MaxTextSize = 18
	sizeLimit.MinTextSize = 7
	sizeLimit.Parent = label

	local overlay = Instance.new("Frame")
	overlay.Name = "Cooldown"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.3
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 3
	overlay.Parent = button
	local overlayCorner = Instance.new("UICorner")
	overlayCorner.CornerRadius = UDim.new(0.5, 0)
	overlayCorner.Parent = overlay

	local countdown = Instance.new("TextLabel")
	countdown.Name = "Countdown"
	countdown.AnchorPoint = Vector2.new(0.5, 0.5)
	countdown.Position = UDim2.fromScale(0.5, 0.5)
	countdown.Size = UDim2.fromScale(0.6, 0.5)
	countdown.BackgroundTransparency = 1
	countdown.Font = Enum.Font.GothamBold
	countdown.TextScaled = true
	countdown.TextColor3 = BUTTON_TEXT
	countdown.Text = ""
	countdown.ZIndex = 4
	countdown.Parent = button

	-- Pastille de touche (mode indicateur au clavier / à la manette).
	local badge = Instance.new("TextLabel")
	badge.Name = "Key"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(0.15, 0.15)
	badge.Size = UDim2.new(0, 26, 0, 20)
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
	badge.BackgroundTransparency = 0.05
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 13
	badge.TextColor3 = Color3.fromRGB(20, 20, 26)
	badge.Text = ""
	badge.Visible = false
	badge.ZIndex = 5
	badge.Parent = button
	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 6)
	badgeCorner.Parent = badge
	local badgePadding = Instance.new("UIPadding")
	badgePadding.PaddingLeft = UDim.new(0, 4)
	badgePadding.PaddingRight = UDim.new(0, 4)
	badgePadding.Parent = badge

	entry.trove:Connect(button.InputBegan, function(input: InputObject)
		local inputType = input.UserInputType
		if inputType ~= Enum.UserInputType.Touch and inputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if entry.pressedInput ~= nil or not button.Active or not shouldShowButton(entry) then
			return
		end
		entry.pressedInput = input
		button.BackgroundTransparency = 0.05
		InputController.Trigger(entry.action, Enum.UserInputState.Begin)
	end)

	button.Parent = parent
	entry.trove:Add(button)
	return {
		button = button,
		label = label,
		stroke = stroke,
		overlay = overlay,
		countdown = countdown,
		badge = badge,
	}
end

local function materializeButton(entry: TouchButton)
	local gui = state.gui
	if entry.ui or not gui then
		return
	end
	entry.ui = buildButtonUi(entry, gui)
	applyButtonLook(entry)
	runCooldown(entry)
end

local function refreshTouchButton(action: string)
	local entry = touchButtons[action]
	if not entry then
		return
	end
	if entry.pressedInput and not shouldShowButton(entry) then
		releaseButton(entry, Enum.UserInputState.Cancel)
	end
	applyButtonLook(entry)
end

local function refreshAllTouchButtons()
	for action in touchButtons do
		refreshTouchButton(action)
	end
end

local function destroyTouchButton(entry: TouchButton)
	if entry.pressedInput then
		releaseButton(entry, Enum.UserInputState.Cancel)
	end
	stopCooldownThread(entry)
	entry.ui = nil
	entry.trove:Clean()
end

function InputController.SetTouchButton(action: string, options: TouchButtonOptions?)
	local existing = touchButtons[action]
	if options == nil then
		if existing then
			touchButtons[action] = nil
			destroyTouchButton(existing)
		end
		return
	end
	local resolved = options :: TouchButtonOptions
	if existing then
		local slotChanged = existing.options.slot ~= resolved.slot
		existing.options = table.clone(resolved)
		existing.visible = resolved.visible ~= false
		if slotChanged then
			applyButtonLayout(existing)
		end
		refreshTouchButton(action)
		return
	end
	local entry: TouchButton = {
		action = action,
		options = table.clone(resolved),
		visible = resolved.visible ~= false,
		active = false,
		pressedInput = nil,
		cooldownEndsAt = 0,
		cooldownTotal = 0,
		cooldownThread = nil,
		ui = nil,
		trove = Trove.new(),
	}
	touchButtons[action] = entry
	materializeButton(entry)
end

function InputController.SetTouchButtonVisible(action: string, visible: boolean)
	local entry = touchButtons[action]
	if entry and entry.visible ~= visible then
		entry.visible = visible
		refreshTouchButton(action)
	end
end

function InputController.SetTouchButtonText(action: string, text: string)
	local entry = touchButtons[action]
	if entry and entry.options.text ~= text then
		entry.options.text = text
		refreshTouchButton(action)
	end
end

function InputController.SetTouchButtonActive(action: string, active: boolean)
	local entry = touchButtons[action]
	if entry and entry.active ~= active then
		entry.active = active
		refreshTouchButton(action)
	end
end

function InputController.StartCooldown(action: string, seconds: number)
	local entry = touchButtons[action]
	if not entry or type(seconds) ~= "number" or seconds ~= seconds then
		return
	end
	local duration = math.clamp(seconds, 0, 60)
	entry.cooldownTotal = duration
	entry.cooldownEndsAt = os.clock() + duration
	runCooldown(entry)
end

function InputController.SetTouchControlsSuppressed(reason: string, suppressed: boolean)
	if suppressed then
		suppressedReasons[reason] = true
	else
		suppressedReasons[reason] = nil
	end
	refreshAllTouchButtons()
end

--------------------------------------------------------------------------------
-- Liaisons d'actions
--------------------------------------------------------------------------------

local function invokeCallback(binding: Binding, inputState: Enum.UserInputState, input: InputObject?): boolean?
	local ok, result = xpcall(binding.callback, debug.traceback, inputState, input)
	if not ok then
		Log.error("Input", "action " .. binding.action .. " :", result)
		return nil
	end
	return result
end

function InputController.BindAtPriority(action: string, priority: number, callback: ActionCallback, ...: InputKey)
	assert(type(action) == "string" and action ~= "", "InputController.Bind : nom d'action invalide")
	assert(type(callback) == "function", "InputController.Bind : callback manquant pour " .. action)
	local existing = bindings[action]
	if existing then
		ContextActionService:UnbindAction(existing.casName)
	end
	local keys: { InputKey } = { ... }
	local binding: Binding = {
		action = action,
		casName = ACTION_PREFIX .. action,
		callback = callback,
		keys = keys,
		priority = priority,
	}
	bindings[action] = binding
	if #keys > 0 then
		ContextActionService:BindActionAtPriority(
			binding.casName,
			function(_actionName: string, inputState: Enum.UserInputState, inputObject: InputObject): Enum.ContextActionResult?
				if bindings[action] ~= binding then
					return Enum.ContextActionResult.Pass
				end
				local result = invokeCallback(binding, inputState, inputObject)
				if result == false then
					return Enum.ContextActionResult.Pass
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			priority,
			table.unpack(keys)
		)
	end
	refreshTouchButton(action)
end

function InputController.Bind(action: string, callback: ActionCallback, ...: InputKey)
	InputController.BindAtPriority(action, InputController.Priorities.Gameplay, callback, ...)
end

function InputController.Unbind(action: string)
	local binding = bindings[action]
	if not binding then
		return
	end
	local entry = touchButtons[action]
	if entry and entry.pressedInput then
		-- Relâchement propre d'un bouton maintenu (le callback voit encore l'action liée).
		releaseButton(entry, Enum.UserInputState.Cancel)
	end
	bindings[action] = nil
	ContextActionService:UnbindAction(binding.casName)
	refreshTouchButton(action)
end

function InputController.IsBound(action: string): boolean
	return bindings[action] ~= nil
end

function InputController.Trigger(action: string, inputState: Enum.UserInputState?)
	local binding = bindings[action]
	if binding then
		invokeCallback(binding, inputState or Enum.UserInputState.Begin, nil)
	end
end

--------------------------------------------------------------------------------
-- Appareil courant et activité
--------------------------------------------------------------------------------

local function setDevice(device: Device)
	if device == state.device then
		return
	end
	local previous = state.device
	state.device = device
	refreshAllTouchButtons()
	InputController.DeviceChanged:Fire(device, previous)
end

local function noteActivity()
	local now = os.clock()
	state.lastInputTime = now
	if now - state.lastActivityFire >= ACTIVITY_INTERVAL then
		state.lastActivityFire = now
		InputController.Activity:Fire()
	end
end

function InputController.GetDevice(): Device
	return state.device
end

function InputController.GetLastInputTime(): number
	return state.lastInputTime
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function InputController.Init()
	if state.initialized then
		return
	end
	state.initialized = true
	state.device = initialDevice()

	runtimeTrove:Connect(UserInputService.InputBegan, function(input: InputObject)
		local device = deviceFromInput(input, false)
		if device then
			setDevice(device)
			noteActivity()
		end
	end)

	runtimeTrove:Connect(UserInputService.InputChanged, function(input: InputObject)
		local device = deviceFromInput(input, true)
		if device then
			setDevice(device)
			noteActivity()
		end
	end)

	runtimeTrove:Connect(UserInputService.InputEnded, function(input: InputObject)
		for _, entry in touchButtons do
			if entry.pressedInput == input then
				releaseButton(entry, Enum.UserInputState.End)
			end
		end
	end)

	runtimeTrove:Connect(UserInputService.GamepadDisconnected, function()
		if state.device == "Gamepad" and #UserInputService:GetConnectedGamepads() == 0 then
			setDevice(platformDefaultDevice(false))
		end
	end)

	-- Préférence d'entrée du moteur (si la propriété existe sur cette version).
	local okSignal, preferredSignal = pcall(function(): RBXScriptSignal
		return UserInputService:GetPropertyChangedSignal("PreferredInput" :: any)
	end)
	if okSignal and typeof(preferredSignal) == "RBXScriptSignal" then
		runtimeTrove:Connect(preferredSignal, function()
			local device = preferredInputDevice()
			if device then
				setDevice(device)
			end
		end)
	end

	Locale.onLanguageChanged(function()
		refreshAllTouchButtons()
	end)
end

function InputController.Start()
	local playerGui = localPlayer:WaitForChild("PlayerGui", 60)
	if not playerGui then
		Log.warn("Input", "PlayerGui introuvable : boutons tactiles indisponibles")
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "GolfChaosActions"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 8
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	pcall(function()
		(gui :: any).ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	gui.Parent = playerGui
	runtimeTrove:Add(gui)
	state.gui = gui

	runtimeTrove:Connect(gui:GetPropertyChangedSignal("AbsoluteSize"), function()
		for _, entry in touchButtons do
			applyButtonLayout(entry)
		end
	end)

	for _, entry in touchButtons do
		materializeButton(entry)
	end
end

return InputController
