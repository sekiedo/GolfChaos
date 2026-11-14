--!strict
--[[
	Panel — panneau cartoon : ombre portée en couches (cadre décalé foncé), face arrondie à gros contour encre,
	bandeau de titre optionnel (ruban coloré qui déborde en haut), zone de contenu avec marges.

	  local panel = Panel.new({ titleKey = "settings.title", size = UDim2.fromOffset(640, 480),
	                            anchorPoint = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.5),
	                            parent = gui })
	  panel.Content   -- Frame où placer les enfants (UIPadding déjà posé)
	  panel.SetTitle("Texte") / panel.SetTitleKey("menu.title") / panel.SetColor(Theme.Colors.NightRaised)

	Props : title | titleKey (+ titleVars) ; titleVariant (Primary par défaut : couleur du ruban) ; color (Night) ;
	transparency (fond, 0 par défaut, ajusté à la préférence Roblox de transparence) ; shadow (true) ;
	radius ("Large") ; padding (Spacing.L) ; strokeColor ; maxSize (Vector2 : contrainte de taille) ;
	+ communs (name, parent, position, size, anchorPoint, layoutOrder, zIndex, visible).
	Instance est le conteneur transparent (à positionner / animer) ; Face est le fond visible.
]]

local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Base)

export type PanelProps = {
	title: string?,
	titleKey: string?,
	titleVars: { [string]: any }?,
	titleVariant: string?,
	color: Color3?,
	transparency: number?,
	shadow: boolean?,
	radius: (string | number)?,
	padding: number?,
	strokeColor: Color3?,
	maxSize: Vector2?,
	name: string?,
	parent: Instance?,
	position: UDim2?,
	size: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

export type PanelApi = {
	Instance: Frame,
	Face: Frame,
	Content: Frame,
	Title: TextLabel?,
	SetTitle: (text: string) -> (),
	SetTitleKey: (key: string, vars: { [string]: any }?) -> (),
	SetColor: (color: Color3) -> (),
}

local SHADOW_OFFSET = 6
local TITLE_HEIGHT = 44

local Panel = {}

function Panel.new(props: PanelProps): PanelApi
	local radius = props.radius or "Large"
	local hasTitle = props.title ~= nil or props.titleKey ~= nil
	local padding = props.padding or Theme.Spacing.L

	local root = Instance.new("Frame")
	root.Name = props.name or "Panneau"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = props.size or UDim2.fromOffset(480, 320)
	if props.maxSize then
		local constraint = Instance.new("UISizeConstraint")
		constraint.MaxSize = props.maxSize
		constraint.Parent = root
	end

	-- Ombre en deux couches (une proche plus dense, une large plus diffuse) : relief sans image.
	if props.shadow ~= false then
		local far = Instance.new("Frame")
		far.Name = "OmbreLarge"
		far.BorderSizePixel = 0
		far.BackgroundColor3 = Theme.Colors.Backdrop
		far.BackgroundTransparency = 0.72
		far.Position = UDim2.fromOffset(SHADOW_OFFSET + 3, SHADOW_OFFSET + 5)
		far.Size = UDim2.fromScale(1, 1)
		far.ZIndex = 0
		Base.corner(far, radius)
		far.Parent = root

		local near = Instance.new("Frame")
		near.Name = "Ombre"
		near.BorderSizePixel = 0
		near.BackgroundColor3 = Theme.Colors.Ink
		near.BackgroundTransparency = 0.25
		near.Position = UDim2.fromOffset(0, SHADOW_OFFSET)
		near.Size = UDim2.fromScale(1, 1)
		near.ZIndex = 0
		Base.corner(near, radius)
		near.Parent = root
	end

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.BorderSizePixel = 0
	face.BackgroundColor3 = props.color or Theme.Colors.Night
	face.BackgroundTransparency = Theme.backgroundTransparency(props.transparency or 0)
	face.Size = UDim2.fromScale(1, 1)
	face.ZIndex = 1
	Base.corner(face, radius)
	Base.stroke(face, props.strokeColor or Theme.Colors.Ink, Theme.StrokeWidth.Thick)
	face.Parent = root

	-- Liseré clair intérieur (effet « bonbon » des panneaux cartoon).
	local rim = Instance.new("Frame")
	rim.Name = "Lisere"
	rim.BackgroundTransparency = 1
	rim.BorderSizePixel = 0
	rim.Position = UDim2.fromOffset(4, 4)
	rim.Size = UDim2.new(1, -8, 1, -8)
	rim.ZIndex = 1
	Base.corner(rim, if type(radius) == "number" then math.max(0, radius - 4) else radius)
	local rimStroke = Base.stroke(rim, Theme.Colors.White, 1.5)
	rimStroke.Transparency = 0.82
	rim.Parent = face

	local content = Instance.new("Frame")
	content.Name = "Contenu"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ZIndex = 2
	local top = if hasTitle then TITLE_HEIGHT * 0.5 + 6 else 0
	content.Position = UDim2.fromOffset(0, top)
	content.Size = UDim2.new(1, 0, 1, -top)
	content.ClipsDescendants = false
	Base.padding(content, padding)
	content.Parent = face

	local titleLabel: TextLabel? = nil
	if hasTitle then
		local style = Theme.variant(props.titleVariant or "Primary")
		local ribbon = Instance.new("Frame")
		ribbon.Name = "Ruban"
		ribbon.BorderSizePixel = 0
		ribbon.AnchorPoint = Vector2.new(0.5, 0.5)
		ribbon.Position = UDim2.new(0.5, 0, 0, 0)
		ribbon.Size = UDim2.fromOffset(0, TITLE_HEIGHT)
		ribbon.AutomaticSize = Enum.AutomaticSize.X
		ribbon.BackgroundColor3 = style.background
		ribbon.ZIndex = 4
		Base.corner(ribbon, "Pill")
		Base.stroke(ribbon, Theme.Colors.Ink, Theme.StrokeWidth.Thick)
		Base.padding(ribbon, nil, 26, 0)
		ribbon.Parent = root

		local ribbonLip = Instance.new("Frame")
		ribbonLip.Name = "LevreRuban"
		ribbonLip.BorderSizePixel = 0
		ribbonLip.AnchorPoint = Vector2.new(0.5, 0.5)
		ribbonLip.Position = UDim2.new(0.5, 0, 0, 5)
		ribbonLip.Size = UDim2.fromOffset(0, TITLE_HEIGHT)
		ribbonLip.AutomaticSize = Enum.AutomaticSize.X
		ribbonLip.BackgroundColor3 = style.lip
		ribbonLip.ZIndex = 3
		Base.corner(ribbonLip, "Pill")
		Base.stroke(ribbonLip, Theme.Colors.Ink, Theme.StrokeWidth.Thick)
		Base.padding(ribbonLip, nil, 26, 0)
		ribbonLip.Parent = root

		local text = Base.newText("Titre", "Heading", "Display", style.text)
		text.AutomaticSize = Enum.AutomaticSize.X
		text.Size = UDim2.fromOffset(0, TITLE_HEIGHT)
		text.TextXAlignment = Enum.TextXAlignment.Center
		text.ZIndex = 5
		Base.setText(text, props.title, props.titleKey, props.titleVars)
		text.Parent = ribbon

		-- Le fantôme de texte donne à la lèvre la même largeur que le ruban.
		local ghost = Base.newText("Fantome", "Heading", "Display", style.lip)
		ghost.AutomaticSize = Enum.AutomaticSize.X
		ghost.Size = UDim2.fromOffset(0, TITLE_HEIGHT)
		ghost.TextTransparency = 1
		ghost.ZIndex = 3
		ghost.Parent = ribbonLip
		text:GetPropertyChangedSignal("Text"):Connect(function()
			ghost.Text = text.Text
		end)
		ghost.Text = text.Text
		titleLabel = text
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

	local api = {} :: PanelApi
	api.Instance = root
	api.Face = face
	api.Content = content
	api.Title = titleLabel

	function api.SetTitle(text: string)
		if titleLabel then
			Base.setText(titleLabel, text, nil, nil)
		end
	end

	function api.SetTitleKey(key: string, vars: { [string]: any }?)
		if titleLabel then
			Base.setText(titleLabel, nil, key, vars)
		end
	end

	function api.SetColor(color: Color3)
		face.BackgroundColor3 = color
	end

	return api
end

-- Encart secondaire (fond légèrement plus clair, contour fin) pour grouper des lignes dans un panneau.
function Panel.inset(props: { name: string?, parent: Instance?, size: UDim2?, position: UDim2?, layoutOrder: number?, color: Color3?, padding: number? }): Frame
	local frame = Instance.new("Frame")
	frame.Name = props.name or "Encart"
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = props.color or Theme.Colors.NightRaised
	frame.Size = props.size or UDim2.new(1, 0, 0, 0)
	if props.position then
		frame.Position = props.position
	end
	if props.layoutOrder then
		frame.LayoutOrder = props.layoutOrder
	end
	Base.corner(frame, "Medium")
	Base.stroke(frame, Theme.Colors.Ink, Theme.StrokeWidth.Thin)
	Base.padding(frame, props.padding or Theme.Spacing.M)
	if props.parent then
		frame.Parent = props.parent
	end
	return frame
end

return Panel
