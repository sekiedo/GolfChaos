--!strict
--[[
	Button — bouton cartoon (face colorée, lèvre 3D, contour encre) ; cible tactile >= 44 px ; sélectionnable
	à la manette avec le cadre de sélection du thème.

	  local play = Button.new({ key = "menu.play", variant = "Primary", size = "Large", parent = frame,
	                            onActivated = function() ... end })
	  play.Activated:Connect(fn)   play.SetEnabled(false)   play.SetKey("menu.ready")   play.SetVariant("Success")

	Props : text | key (+ vars) ; icon (glyphe affiché avant le texte) ; variant (Primary par défaut, Secondary,
	Success, Warning, Danger, Accent, Dark, Light, Ghost) ; size ("Small" 44 px, "Medium" 52 px, "Large" 64 px) ;
	width (px design) ou fill (toute la largeur), sinon largeur automatique (minimum selon la taille) ;
	onActivated ; sound (défaut "ui_click", "" = muet) ; disabled ; selectionOrder ; + communs (name, parent,
	position, anchorPoint, layoutOrder, zIndex, visible).
	Retour visuel : couleur au survol / à la sélection manette, enfoncement à l'appui (mouvement coupé quand
	les effets sont réduits). Une double activation accidentelle (< 0,12 s) est ignorée.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)

local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Base)

export type ButtonProps = {
	text: string?,
	key: string?,
	vars: { [string]: any }?,
	icon: string?,
	variant: string?,
	size: string?,
	width: number?,
	fill: boolean?,
	onActivated: (() -> ())?,
	sound: string?,
	disabled: boolean?,
	selectionOrder: number?,
	name: string?,
	parent: Instance?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

export type ButtonApi = {
	Instance: TextButton,
	Activated: Signal.Signal,
	SetText: (text: string) -> (),
	SetKey: (key: string, vars: { [string]: any }?) -> (),
	SetEnabled: (enabled: boolean) -> (),
	IsEnabled: () -> boolean,
	SetVariant: (variant: string) -> (),
	SetIcon: (icon: string?) -> (),
}

type SizeSpec = { height: number, minWidth: number, text: string, padding: number }

local SIZES: { [string]: SizeSpec } = {
	Small = { height = Theme.Touch.Small, minWidth = 96, text = "Body", padding = 14 },
	Medium = { height = Theme.Touch.Medium, minWidth = 140, text = "Button", padding = 18 },
	Large = { height = Theme.Touch.Large, minWidth = 200, text = "Heading", padding = 24 },
}

local ACTIVATE_DEBOUNCE = 0.12
local MAX_LABEL_WIDTH = 420

local Button = {}

function Button.new(props: ButtonProps): ButtonApi
	local dims = SIZES[props.size or "Medium"] or SIZES.Medium
	local lip = Theme.Touch.Lip
	local variantName = props.variant or "Primary"
	local enabled = props.disabled ~= true
	local style = Theme.variant(if enabled then variantName else "Disabled")

	local root = Instance.new("TextButton")
	root.Name = props.name or "Bouton"
	root.AutoButtonColor = false
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Text = ""
	if props.width then
		root.Size = UDim2.fromOffset(props.width, dims.height + lip)
	elseif props.fill then
		root.Size = UDim2.new(1, 0, 0, dims.height + lip)
	else
		root.Size = UDim2.fromOffset(0, dims.height + lip)
		root.AutomaticSize = Enum.AutomaticSize.X
	end
	Base.makeSelectable(root, "Rounded")
	root.Selectable = enabled
	if props.selectionOrder then
		root.SelectionOrder = props.selectionOrder
	end
	local trove = Base.lifetime(root)

	local scale = Instance.new("UIScale")
	scale.Parent = root

	-- Lèvre (relief cartoon sous la face).
	local lipFrame = Instance.new("Frame")
	lipFrame.Name = "Levre"
	lipFrame.BorderSizePixel = 0
	lipFrame.Position = UDim2.fromOffset(0, lip)
	lipFrame.Size = UDim2.new(1, 0, 1, -lip)
	lipFrame.ZIndex = 1
	Base.corner(lipFrame, "Medium")
	Base.stroke(lipFrame, Theme.Colors.Ink, Theme.StrokeWidth.Normal)
	lipFrame.Parent = root

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.BorderSizePixel = 0
	face.Size = UDim2.new(1, 0, 1, -lip)
	face.ZIndex = 2
	Base.corner(face, "Medium")
	local faceStroke = Base.stroke(face, style.stroke, Theme.StrokeWidth.Normal)
	face.Parent = root

	-- Reflet clair en haut de la face (volume cartoon).
	local shine = Instance.new("Frame")
	shine.Name = "Reflet"
	shine.BorderSizePixel = 0
	shine.BackgroundColor3 = Theme.Colors.White
	shine.BackgroundTransparency = 0.82
	shine.Position = UDim2.fromOffset(6, 4)
	shine.Size = UDim2.new(1, -12, 0.34, 0)
	shine.ZIndex = 2
	Base.corner(shine, "Small")
	shine.Parent = face

	local content = Instance.new("Frame")
	content.Name = "Contenu"
	content.BackgroundTransparency = 1
	content.ZIndex = 3
	if props.width or props.fill then
		content.Size = UDim2.new(1, 0, 1, -lip)
	else
		content.AutomaticSize = Enum.AutomaticSize.X
		content.Size = UDim2.fromOffset(0, dims.height)
		local minimum = Instance.new("UISizeConstraint")
		minimum.MinSize = Vector2.new(dims.minWidth, 0)
		minimum.Parent = content
	end
	Base.padding(content, nil, dims.padding, 0)
	Base.list(content, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	content.Parent = root

	local iconLabel = Base.newText("Icone", dims.text, "Display", style.text)
	iconLabel.AutomaticSize = Enum.AutomaticSize.X
	iconLabel.Size = UDim2.fromOffset(0, dims.height)
	iconLabel.TextXAlignment = Enum.TextXAlignment.Center
	iconLabel.LayoutOrder = 1
	iconLabel.ZIndex = 3
	iconLabel.Text = props.icon or ""
	iconLabel.Visible = props.icon ~= nil and props.icon ~= ""
	iconLabel.Parent = content

	local textLabel = Base.newText("Libelle", dims.text, "Display", style.text)
	textLabel.AutomaticSize = Enum.AutomaticSize.X
	textLabel.Size = UDim2.fromOffset(0, dims.height)
	textLabel.TextXAlignment = Enum.TextXAlignment.Center
	textLabel.TextTruncate = Enum.TextTruncate.AtEnd
	textLabel.LayoutOrder = 2
	textLabel.ZIndex = 3
	local labelLimit = Instance.new("UISizeConstraint")
	local maxWidth = if props.width then math.max(24, props.width - dims.padding * 2) else MAX_LABEL_WIDTH
	labelLimit.MaxSize = Vector2.new(maxWidth, math.huge)
	labelLimit.Parent = textLabel
	textLabel.Parent = content
	Base.setText(textLabel, props.text, props.key, props.vars)

	local feedback = Base.attachFeedback(root, {
		colorTarget = face,
		baseColor = style.background,
		hoverColor = style.hover,
		pressedColor = style.pressed,
		movers = { face, content },
		pressOffset = lip - 1,
		scale = scale,
		hoverScale = 1.03,
	}, trove)

	local function applyStyle(newStyle: Theme.VariantStyle)
		style = newStyle
		local ghost = newStyle.transparency >= 1
		face.BackgroundColor3 = newStyle.background
		face.BackgroundTransparency = if ghost then 0.65 else 0
		shine.Visible = not ghost
		lipFrame.Visible = not ghost
		lipFrame.BackgroundColor3 = newStyle.lip
		faceStroke.Color = newStyle.stroke
		faceStroke.Thickness = if ghost then Theme.StrokeWidth.Thin else Theme.StrokeWidth.Normal
		textLabel.TextColor3 = newStyle.text
		iconLabel.TextColor3 = newStyle.text
		feedback.SetColors(newStyle.background, newStyle.hover, newStyle.pressed)
	end
	applyStyle(style)

	local activated = Signal.new()
	trove:Add(activated)

	local lastActivation = 0
	trove:Connect(root.Activated, function()
		if not enabled then
			return
		end
		local now = os.clock()
		if now - lastActivation < ACTIVATE_DEBOUNCE then
			return
		end
		lastActivation = now
		if Base.isGamepad() then
			feedback.Pulse()
		end
		Base.playSound(if props.sound == nil then "ui_click" else props.sound)
		activated:Fire()
		Base.safeCall(props.onActivated)
	end)

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

	local api = {} :: ButtonApi
	api.Instance = root
	api.Activated = activated

	function api.SetText(text: string)
		Base.setText(textLabel, text, nil, nil)
	end

	function api.SetKey(key: string, vars: { [string]: any }?)
		Base.setText(textLabel, nil, key, vars)
	end

	function api.SetEnabled(value: boolean)
		if enabled == value then
			return
		end
		enabled = value
		root.Selectable = value
		applyStyle(Theme.variant(if value then variantName else "Disabled"))
		feedback.SetEnabled(value)
	end

	function api.IsEnabled(): boolean
		return enabled
	end

	function api.SetVariant(variant: string)
		variantName = variant
		if enabled then
			applyStyle(Theme.variant(variant))
		end
	end

	function api.SetIcon(icon: string?)
		iconLabel.Text = icon or ""
		iconLabel.Visible = icon ~= nil and icon ~= ""
	end

	return api
end

return Button
