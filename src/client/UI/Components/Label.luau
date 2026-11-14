--!strict
--[[
	Label — texte stylé du thème (police, taille suivie sur écran compact, couleur contrastée, contour cartoon).

	  local title = Label.new({ key = "settings.title", style = "Title", stroke = true, parent = frame })
	  title.SetText("Texte déjà traduit")   title.SetKey("ui.ok")   title.SetColor(Theme.Colors.Primary)

	Props : text | key (+ vars) ; style ("Body" par défaut : Caption, Small, Body, Button, Heading, Title, Display,
	Hero) ; font (Display, Body, Bold, Heavy, Mono ; défaut selon le style) ; color (Paper) ; transparency ;
	stroke (true | épaisseur) ; strokeColor (défaut : Ink ou Paper, l'opposé du texte) ; alignX ; alignY ;
	wrap (true) ; autoSize ("Y" si aucune taille fournie, sinon "None" ; aussi "X", "XY") ; richText ; truncate ;
	maxSize (Vector2) ; + communs (name, parent, position, size, anchorPoint, layoutOrder, zIndex, visible).
	Un texte fourni par clé (key) est retraduit automatiquement quand la langue change.

	Label.teamBadge({ team = "Red" | "Blue" | nil, compact?, size? ("Small" | "Medium"), ... })
	  -> { Instance, SetTeam(team) } : pastille d'équipe avec une forme dessinée (losange rouge, rond bleu) et le
	  libellé traduit ; reste lisible sans percevoir les couleurs (compact = forme seule).
]]

local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Base)

export type LabelProps = {
	text: string?,
	key: string?,
	vars: { [string]: any }?,
	style: string?,
	font: string?,
	color: Color3?,
	transparency: number?,
	stroke: (boolean | number)?,
	strokeColor: Color3?,
	alignX: Enum.TextXAlignment?,
	alignY: Enum.TextYAlignment?,
	wrap: boolean?,
	autoSize: string?,
	richText: boolean?,
	truncate: boolean?,
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

export type LabelApi = {
	Instance: TextLabel,
	SetText: (text: string) -> (),
	SetKey: (key: string, vars: { [string]: any }?) -> (),
	SetColor: (color: Color3) -> (),
	SetStyle: (style: string, font: string?) -> (),
}

export type TeamBadgeProps = {
	team: string?,
	compact: boolean?,
	size: string?,
	name: string?,
	parent: Instance?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

export type TeamBadgeApi = {
	Instance: Frame,
	SetTeam: (team: string?) -> (),
}

local Label = {}

local function lineHeight(style: string): number
	return Theme.textSize(style) + 8
end

local function strokeThickness(style: string): number
	return math.clamp(Theme.textSize(style) / 12, 1.5, 5)
end

function Label.new(props: LabelProps): LabelApi
	local style = props.style or "Body"
	local color = props.color or Theme.Colors.Paper
	local label = Base.newText(props.name or "Texte", style, props.font, color)
	label.TextTransparency = props.transparency or 0
	label.TextWrapped = props.wrap ~= false
	label.RichText = props.richText == true
	label.TextXAlignment = props.alignX or Enum.TextXAlignment.Left
	label.TextYAlignment = props.alignY or Enum.TextYAlignment.Center
	if props.truncate then
		label.TextTruncate = Enum.TextTruncate.AtEnd
	end

	local autoSize = props.autoSize or (if props.size then "None" else "Y")
	if autoSize == "X" then
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = props.size or UDim2.fromOffset(0, lineHeight(style))
	elseif autoSize == "Y" then
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.Size = props.size or UDim2.new(1, 0, 0, 0)
	elseif autoSize == "XY" then
		label.AutomaticSize = Enum.AutomaticSize.XY
		label.Size = props.size or UDim2.new()
	else
		label.Size = props.size or UDim2.new(1, 0, 0, lineHeight(style))
	end

	if props.maxSize then
		local constraint = Instance.new("UISizeConstraint")
		constraint.MaxSize = props.maxSize
		constraint.Parent = label
	end

	local textStroke: UIStroke? = nil
	if props.stroke then
		local thickness = if type(props.stroke) == "number" then props.stroke else strokeThickness(style)
		textStroke = Base.textStroke(label, thickness, props.strokeColor or Theme.textOn(color))
	end

	Base.setText(label, props.text, props.key, props.vars)
	Base.applyCommon(label, {
		position = props.position,
		anchorPoint = props.anchorPoint,
		layoutOrder = props.layoutOrder,
		zIndex = props.zIndex,
		visible = props.visible,
	})
	Base.mount(label, props)

	local api = {} :: LabelApi
	api.Instance = label

	function api.SetText(text: string)
		Base.setText(label, text, nil, nil)
	end

	function api.SetKey(key: string, vars: { [string]: any }?)
		Base.setText(label, nil, key, vars)
	end

	function api.SetColor(newColor: Color3)
		label.TextColor3 = newColor
		if textStroke and not props.strokeColor then
			textStroke.Color = Theme.textOn(newColor)
		end
	end

	function api.SetStyle(newStyle: string, font: string?)
		Theme.applyText(label, newStyle, font)
		if textStroke and type(props.stroke) ~= "number" then
			textStroke.Thickness = strokeThickness(newStyle)
		end
	end

	return api
end

function Label.teamBadge(props: TeamBadgeProps): TeamBadgeApi
	local small = props.size == "Small"
	local height = if small then 26 else 32
	local markerSize = if small then 11 else 13

	local frame = Instance.new("Frame")
	frame.Name = props.name or "BadgeEquipe"
	frame.BorderSizePixel = 0
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Size = UDim2.fromOffset(height, height)
	Base.corner(frame, "Pill")
	Base.stroke(frame, Theme.Colors.Ink, 2)
	Base.padding(frame, nil, if props.compact then 6 else 10, 0)
	Base.list(frame, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

	local marker = Instance.new("Frame")
	marker.Name = "Marqueur"
	marker.BorderSizePixel = 0
	marker.Size = UDim2.fromOffset(markerSize, markerSize)
	marker.LayoutOrder = 1
	local markerCorner = Base.corner(marker, 2)
	marker.Parent = frame

	local text = Base.newText("Libelle", if small then "Caption" else "Small", "Bold")
	text.AutomaticSize = Enum.AutomaticSize.X
	text.Size = UDim2.fromOffset(0, height)
	text.LayoutOrder = 2
	text.Visible = props.compact ~= true
	text.Parent = frame

	local api = {} :: TeamBadgeApi
	api.Instance = frame

	function api.SetTeam(team: string?)
		local style = Theme.team(team)
		local fill = if style then style.color else Theme.Colors.NightRaised
		local ink = Theme.textOn(fill)
		frame.BackgroundColor3 = fill
		text.TextColor3 = ink
		marker.BackgroundColor3 = ink
		if style and style.shape == "Diamond" then
			marker.Visible = true
			marker.Rotation = 45
			markerCorner.CornerRadius = UDim.new(0, 2)
		elseif style then
			marker.Visible = true
			marker.Rotation = 0
			markerCorner.CornerRadius = UDim.new(0.5, 0)
		else
			marker.Visible = false
		end
		Base.setText(text, nil, if style then style.labelKey else "ui.team.none", nil)
	end

	api.SetTeam(props.team)
	Base.applyCommon(frame, {
		position = props.position,
		anchorPoint = props.anchorPoint,
		layoutOrder = props.layoutOrder,
		zIndex = props.zIndex,
		visible = props.visible,
	})
	if props.parent then
		frame.Parent = props.parent
	end
	return api
end

return Label
