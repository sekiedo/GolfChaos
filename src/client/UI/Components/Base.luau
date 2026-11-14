--!strict
--[[
	Base — aides internes partagées par les composants d'interface (aucun effet de bord au require).

	  Base.applyCommon(objet, props)              Name, Position, Size, AnchorPoint, LayoutOrder, ZIndex, Visible
	  Base.mount(objet, props)                    parente en dernier (props.parent)
	  Base.corner(parent, rayon?) / Base.stroke(parent, couleur?, épaisseur?, mode?) / Base.textStroke(texte, ...)
	  Base.padding(parent, tout?, horizontal?, vertical?) / Base.list(parent, sens, écart, alignH?, alignV?)
	  Base.newText(nom, taille?, police?, couleur?) -> TextLabel     texte stylé Theme, fond transparent
	  Base.setText(objet, texte?, clé?, vars?)    texte direct, ou clé Locale suivie (retraduite au changement de langue)
	  Base.makeSelectable(objet, forme?)          sélectionnable à la manette, cadre de sélection stylé
	  Base.attachFeedback(bouton, options, trove) survol / sélection / appui (mouvement coupé si effets réduits)
	  Base.playSound(nom?, volume?)               son d'interface via EffectsController (s'il existe), volume
	                                              relatif multiplié par le réglage local uiVolume
	  Base.getController(nom) -> module?          contrôleur client chargé paresseusement (pcall, mis en cache)
	  Base.safeCall(fn, ...)                      appel protégé d'un callback d'écran (erreur journalisée)
	  Base.lifetime(objet) -> Trove               nettoyée automatiquement à la destruction de l'objet
	  Base.isGamepad() -> boolean                 dernier appareil = manette (InputController)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared.Locale)
local Log = require(Shared.Util.Log)
local Trove = require(Shared.Util.Trove)

local Theme = require(script.Parent.Parent.Theme)

export type CommonProps = {
	name: string?,
	parent: Instance?,
	position: UDim2?,
	size: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

export type FeedbackOptions = {
	colorTarget: GuiObject?, -- objet dont BackgroundColor3 suit l'état
	baseColor: Color3?,
	hoverColor: Color3?,
	pressedColor: Color3?,
	movers: { GuiObject }?, -- objets qui s'enfoncent à l'appui (face du bouton, contenu)
	pressOffset: number?, -- pixels design vers le bas
	scale: UIScale?, -- léger grossissement au survol
	hoverScale: number?,
	hoverSound: boolean?, -- petit son quand la manette sélectionne l'objet (défaut true)
}

export type FeedbackApi = {
	SetColors: (base: Color3, hover: Color3, pressed: Color3) -> (),
	SetEnabled: (enabled: boolean) -> (),
	Pulse: () -> (),
	Refresh: () -> (),
}

local Base = {}

--------------------------------------------------------------------------------
-- Propriétés communes et décorations
--------------------------------------------------------------------------------

function Base.applyCommon(object: GuiObject, props: CommonProps)
	if props.name then
		object.Name = props.name
	end
	if props.position then
		object.Position = props.position
	end
	if props.size then
		object.Size = props.size
	end
	if props.anchorPoint then
		object.AnchorPoint = props.anchorPoint
	end
	if props.layoutOrder then
		object.LayoutOrder = props.layoutOrder
	end
	if props.zIndex then
		object.ZIndex = props.zIndex
	end
	if props.visible ~= nil then
		object.Visible = props.visible
	end
end

function Base.mount(object: GuiObject, props: CommonProps)
	if props.parent then
		object.Parent = props.parent
	end
end

function Base.corner(parent: Instance, radius: (string | number)?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.corner(radius)
	corner.Parent = parent
	return corner
end

function Base.stroke(parent: Instance, color: Color3?, thickness: number?, mode: Enum.ApplyStrokeMode?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Colors.Ink
	stroke.Thickness = thickness or Theme.StrokeWidth.Normal
	stroke.ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

-- Contour du texte : garde un texte lisible sur n'importe quel fond (style cartoon).
function Base.textStroke(label: Instance, thickness: number?, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Color = color or Theme.Colors.Ink
	stroke.Thickness = thickness or 2
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return stroke
end

function Base.padding(parent: Instance, all: number?, horizontal: number?, vertical: number?): UIPadding
	local padding = Instance.new("UIPadding")
	local h = UDim.new(0, horizontal or all or 0)
	local v = UDim.new(0, vertical or all or 0)
	padding.PaddingLeft = h
	padding.PaddingRight = h
	padding.PaddingTop = v
	padding.PaddingBottom = v
	padding.Parent = parent
	return padding
end

function Base.list(
	parent: Instance,
	direction: Enum.FillDirection,
	gap: number,
	horizontal: Enum.HorizontalAlignment?,
	vertical: Enum.VerticalAlignment?
): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.Padding = UDim.new(0, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = horizontal or Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = vertical or Enum.VerticalAlignment.Top
	layout.Parent = parent
	return layout
end

-- TextLabel transparent déjà stylé (police, taille suivie, couleur).
function Base.newText(name: string, size: string?, font: string?, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.TextColor3 = color or Theme.Colors.Paper
	label.Text = ""
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	Theme.applyText(label, size or "Body", font)
	return label
end

--------------------------------------------------------------------------------
-- Textes traduits suivis (clés faibles : aucun objet n'est retenu en mémoire)
--------------------------------------------------------------------------------

type TextBinding = { key: string, vars: { [string]: any }? }

local boundTexts: { [Instance]: TextBinding } = setmetatable({}, { __mode = "k" }) :: any
local languageHooked = false

local function refreshBoundTexts()
	for object, binding in boundTexts do
		local ok, err = pcall(function()
			(object :: any).Text = Locale.t(binding.key, binding.vars)
		end)
		if not ok then
			Log.debug("UI", "texte non retraduit :", err)
		end
	end
end

function Base.setText(object: Instance, text: string?, key: string?, vars: { [string]: any }?)
	if key and key ~= "" then
		boundTexts[object] = { key = key, vars = vars }
		if not languageHooked then
			languageHooked = true
			Locale.onLanguageChanged(function()
				refreshBoundTexts()
			end)
		end
		(object :: any).Text = Locale.t(key, vars)
	else
		boundTexts[object] = nil;
		(object :: any).Text = text or ""
	end
end

--------------------------------------------------------------------------------
-- Manette, sons, appels protégés, durée de vie
--------------------------------------------------------------------------------

function Base.makeSelectable(object: GuiObject, shape: string?)
	object.Selectable = true
	object.SelectionImageObject = Theme.selectionImage(shape)
end

local controllersFolder: Instance? = nil
local controllersLooked = false
local cachedModules: { [string]: any } = {}

local function getController(name: string): any
	if cachedModules[name] ~= nil then
		return cachedModules[name]
	end
	if not controllersLooked then
		controllersLooked = true
		local components = script.Parent
		local ui = if components then components.Parent else nil
		local client = if ui then ui.Parent else nil
		controllersFolder = if client then client:FindFirstChild("Controllers") else nil
	end
	local folder = controllersFolder
	local module = if folder then folder:FindFirstChild(name) else nil
	local result: any = false
	if module and module:IsA("ModuleScript") then
		local ok, loaded = pcall(require, module)
		if ok and type(loaded) == "table" then
			result = loaded
		end
	end
	cachedModules[name] = result
	return result
end

-- Contrôleur client chargé paresseusement (nil s'il n'existe pas) : évite tout cycle de require.
function Base.getController(name: string): any
	local result = getController(name)
	return if result then result else nil
end

-- Volume relatif des sons d'interface (réglage local uiVolume de SettingsController, 1 par défaut).
local function uiVolume(): number
	local settings = getController("SettingsController")
	if settings and type(settings.Get) == "function" then
		local ok, value = pcall(settings.Get, "uiVolume")
		if ok and type(value) == "number" and value == value then
			return math.clamp(value, 0, 1)
		end
	end
	return 1
end

function Base.playSound(name: string?, volume: number?)
	if not name or name == "" then
		return
	end
	local effects = getController("EffectsController")
	if effects and type(effects.PlaySound) == "function" then
		local relative = uiVolume() * (volume or 1)
		if relative <= 0 then
			return
		end
		task.spawn(function()
			local ok, err = pcall(effects.PlaySound, name, { volume = relative })
			if not ok then
				Log.debug("UI", "son d'interface indisponible :", name, err)
			end
		end)
	end
end

function Base.isGamepad(): boolean
	local input = getController("InputController")
	if input and type(input.GetDevice) == "function" then
		local ok, device = pcall(input.GetDevice)
		if ok then
			return device == "Gamepad"
		end
	end
	local lastType = UserInputService:GetLastInputType()
	return string.sub(lastType.Name, 1, 7) == "Gamepad"
end

function Base.safeCall(callback: any, ...: any)
	if type(callback) ~= "function" then
		return
	end
	local ok, err = xpcall(callback, debug.traceback, ...)
	if not ok then
		Log.warn("UI", "callback d'interface en erreur :", err)
	end
end

function Base.lifetime(object: Instance): Trove.Trove
	local trove = Trove.new()
	trove:Connect(object.Destroying, function()
		trove:Clean()
	end)
	return trove
end

--------------------------------------------------------------------------------
-- Retour visuel survol / sélection manette / appui
--------------------------------------------------------------------------------

local PRESS_INPUTS: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

function Base.attachFeedback(button: GuiButton, options: FeedbackOptions, trove: Trove.Trove): FeedbackApi
	local colors = {
		base = options.baseColor,
		hover = options.hoverColor,
		pressed = options.pressedColor,
	}
	local movers = options.movers or {}
	local restPositions: { UDim2 } = {}
	for index, mover in movers do
		restPositions[index] = mover.Position
	end
	local pressOffset = options.pressOffset or 0
	local hoverScale = options.hoverScale or 1.03
	local playHoverSound = options.hoverSound ~= false

	local hovered = false
	local selected = false
	local pressed = false
	local enabled = true
	local pulseToken = 0

	local function render()
		local target = options.colorTarget
		local isHover = (hovered or selected) and enabled
		local isPressed = pressed and enabled
		if target then
			local color = if isPressed then colors.pressed elseif isHover then colors.hover else colors.base
			if color then
				Theme.fade(target, Theme.Motion.Fast, { BackgroundColor3 = color })
			end
		end
		-- Mouvement (enfoncement, grossissement) : coupé quand les animations sont réduites.
		local reduced = Theme.isReducedMotion()
		local offset = if isPressed and not reduced then pressOffset else 0
		for index, mover in movers do
			local rest = restPositions[index]
			Theme.tween(mover, Theme.Motion.Fast, { Position = rest + UDim2.fromOffset(0, offset) })
		end
		local scale = options.scale
		if scale then
			local value = if isHover and not isPressed and not reduced then hoverScale else 1
			Theme.tween(scale, Theme.Motion.Fast, { Scale = value })
		end
	end

	trove:Connect(button.MouseEnter, function()
		hovered = true
		render()
	end)
	trove:Connect(button.MouseLeave, function()
		hovered = false
		pressed = false
		render()
	end)
	trove:Connect(button.SelectionGained, function()
		selected = true
		if enabled and playHoverSound then
			Base.playSound("ui_hover")
		end
		render()
	end)
	trove:Connect(button.SelectionLost, function()
		selected = false
		pressed = false
		render()
	end)
	trove:Connect(button.InputBegan, function(input: InputObject)
		if PRESS_INPUTS[input.UserInputType] and enabled then
			pressed = true
			render()
		end
	end)
	trove:Connect(button.InputEnded, function(input: InputObject)
		if PRESS_INPUTS[input.UserInputType] and pressed then
			pressed = false
			render()
		end
	end)

	local api = {} :: FeedbackApi

	function api.SetColors(base: Color3, hover: Color3, pressedColor: Color3)
		colors.base = base
		colors.hover = hover
		colors.pressed = pressedColor
		render()
	end

	function api.SetEnabled(value: boolean)
		enabled = value
		if not value then
			pressed = false
		end
		render()
	end

	-- Bref enfoncement (activation à la manette ou au clavier, qui ne passe pas par InputBegan).
	function api.Pulse()
		if not enabled then
			return
		end
		pulseToken += 1
		local token = pulseToken
		pressed = true
		render()
		task.delay(0.09, function()
			if token == pulseToken and button.Parent then
				pressed = false
				render()
			end
		end)
	end

	function api.Refresh()
		render()
	end

	return api
end

return Base
