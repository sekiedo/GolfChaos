--!strict
--[[
	IconButton — bouton rond (ou carré arrondi) portant un glyphe texte (aucune image téléversée) ; même relief
	cartoon que Button (face, lèvre, contour encre), cible tactile >= 44 px, sélectionnable à la manette.

	  local close = IconButton.new({ glyph = "✕", variant = "Danger", size = "Small", parent = header,
	                                 labelKey = "ui.close", onActivated = function() ... end })
	  close.Activated:Connect(fn)   close.SetGlyph("☰")   close.SetEnabled(false)   close.SetVariant("Dark")

	Props : glyph ; variant (Dark par défaut) ; size ("Small" 44, "Medium" 52, "Large" 64 px design) ;
	shape ("Circle" défaut | "Rounded") ; labelKey (+ labelVars : petit libellé affiché sous le bouton, utile
	en tactile) ; onActivated ; sound (défaut "ui_click", "" = muet) ; disabled ; + communs (name, parent,
	position, anchorPoint, layoutOrder, zIndex, visible).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)

local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Base)

export type IconButtonProps = {
	glyph: string?,
	variant: string?,
	size: string?,
	shape: string?,
	labelKey: string?,
	labelVars: { [string]: any }?,
	onActivated: (() -> ())?,
	sound: string?,
	disabled: boolean?,
	name: string?,
	parent: Instance?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

export type IconButtonApi = {
	Instance: TextButton,
	Activated: Signal.Signal,
	SetGlyph: (glyph: string) -> (),
	SetEnabled: (enabled: boolean) -> (),
	IsEnabled: () -> boolean,
	SetVariant: (variant: string) -> (),
	SetActive: (active: boolean) -> (),
}

local SIZES: { [string]: { px: number, text: string } } = {
	Small = { px = Theme.Touch.Small, text = "Heading" },
	Medium = { px = Theme.Touch.Medium, text = "Heading" },
	Large = { px = Theme.Touch.Large, text = "Title" },
}

local ACTIVATE_DEBOUNCE = 0.12

local IconButton = {}

function IconButton.new(props: IconButtonProps): IconButtonApi
	local dims = SIZES[props.size or "Small"] or SIZES.Small
	local px = dims.px
	local lip = Theme.Touch.Lip
	local variantName = props.variant or "Dark"
	local enabled = props.disabled ~= true
	local active = false
	local radius: (string | number) = if props.shape == "Rounded" then "Medium" else "Pill"

	local root = Instance.new("TextButton")
	root.Name = props.name or "BoutonIcone"
	root.AutoButtonColor = false
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Text = ""
	root.Size = UDim2.fromOffset(px, px + lip)
	Base.makeSelectable(root, if props.shape == "Rounded" then "Rounded" else "Pill")
	root.Selectable = enabled
	local trove = Base.lifetime(root)

	local scale = Instance.new("UIScale")
	scale.Parent = root

	local lipFrame = Instance.new("Frame")
	lipFrame.Name = "Levre"
	lipFrame.BorderSizePixel = 0
	lipFrame.Position = UDim2.fromOffset(0, lip)
	lipFrame.Size = UDim2.fromOffset(px, px)
	Base.corner(lipFrame, radius)
	Base.stroke(lipFrame, Theme.Colors.Ink, Theme.StrokeWidth.Normal)
	lipFrame.Parent = root

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.BorderSizePixel = 0
	face.Size = UDim2.fromOffset(px, px)
	face.ZIndex = 2
	Base.corner(face, radius)
	local faceStroke = Base.stroke(face, Theme.Colors.Ink, Theme.StrokeWidth.Normal)
	face.Parent = root

	local shine = Instance.new("Frame")
	shine.Name = "Reflet"
	shine.BorderSizePixel = 0
	shine.BackgroundColor3 = Theme.Colors.White
	shine.BackgroundTransparency = 0.8
	shine.AnchorPoint = Vector2.new(0.5, 0)
	shine.Position = UDim2.new(0.5, 0, 0, 4)
	shine.Size = UDim2.new(0.62, 0, 0.3, 0)
	shine.ZIndex = 2
	Base.corner(shine, "Pill")
	shine.Parent = face

	local glyph = Base.newText("Glyphe", dims.text, "Display")
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.TextXAlignment = Enum.TextXAlignment.Center
	glyph.TextScaled = false
	glyph.ZIndex = 3
	glyph.Text = props.glyph or ""
	glyph.Parent = face

	local caption: TextLabel? = nil
	if props.labelKey then
		local text = Base.newText("Legende", "Caption", "Bold", Theme.Colors.Paper)
		text.AnchorPoint = Vector2.new(0.5, 0)
		text.Position = UDim2.new(0.5, 0, 1, 2)
		text.Size = UDim2.fromOffset(px + 40, 16)
		text.TextXAlignment = Enum.TextXAlignment.Center
		text.ZIndex = 3
		Base.textStroke(text, 1.5)
		Base.setText(text, nil, props.labelKey, props.labelVars)
		text.Parent = root
		caption = text
	end

	local feedback = Base.attachFeedback(root, {
		colorTarget = face,
		movers = { face },
		pressOffset = lip - 1,
		scale = scale,
		hoverScale = 1.06,
	}, trove)

	local function applyStyle()
		local style = Theme.variant(if enabled then variantName else "Disabled")
		local base = style.background
		if active and enabled then
			base = Theme.Colors.Primary
			style = Theme.variant("Primary")
		end
		face.BackgroundColor3 = base
		face.BackgroundTransparency = if style.transparency >= 1 then 0.6 else 0
		lipFrame.BackgroundColor3 = style.lip
		lipFrame.Visible = style.transparency < 1
		faceStroke.Color = style.stroke
		glyph.TextColor3 = style.text
		feedback.SetColors(base, style.hover, style.pressed)
	end
	applyStyle()

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

	local api = {} :: IconButtonApi
	api.Instance = root
	api.Activated = activated

	function api.SetGlyph(text: string)
		glyph.Text = text
	end

	function api.SetEnabled(value: boolean)
		if enabled == value then
			return
		end
		enabled = value
		root.Selectable = value
		feedback.SetEnabled(value)
		applyStyle()
	end

	function api.IsEnabled(): boolean
		return enabled
	end

	function api.SetVariant(variant: string)
		variantName = variant
		applyStyle()
	end

	-- État « enclenché » (bascule) : face jaune vif.
	function api.SetActive(value: boolean)
		active = value
		applyStyle()
	end

	local _ = caption
	return api
end

return IconButton
