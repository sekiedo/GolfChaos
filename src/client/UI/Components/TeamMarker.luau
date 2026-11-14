--!strict
--[[
	TeamMarker — marqueur d'équipe accessible : pastille colorée portant le glyphe de l'équipe (◆ rouge, ● bleu)
	+ libellé traduit. L'équipe se lit sans percevoir les couleurs (glyphe et texte).

	  local marker = TeamMarker.new({ team = "Red", size = "Small", parent = row })
	  marker.SetTeam("Blue")   marker.SetTeam(nil)   -- sans équipe : masqué si hideWhenNone, sinon « Sans équipe »

	Props : team ; size ("Small" 24 px | "Medium" 30 px | "Large" 40 px) ; showLabel (true) ; hideWhenNone (false) ;
	+ communs (name, parent, position, anchorPoint, layoutOrder, zIndex, visible).
]]

local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Base)

export type TeamMarkerProps = {
	team: string?,
	size: string?,
	showLabel: boolean?,
	hideWhenNone: boolean?,
	name: string?,
	parent: Instance?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

export type TeamMarkerApi = {
	Instance: Frame,
	SetTeam: (team: string?) -> (),
}

local SIZES: { [string]: { px: number, text: string } } = {
	Small = { px = 24, text = "Caption" },
	Medium = { px = 30, text = "Small" },
	Large = { px = 40, text = "Body" },
}

local TeamMarker = {}

function TeamMarker.new(props: TeamMarkerProps): TeamMarkerApi
	local dims = SIZES[props.size or "Medium"] or SIZES.Medium
	local showLabel = props.showLabel ~= false

	local root = Instance.new("Frame")
	root.Name = props.name or "MarqueurEquipe"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.AutomaticSize = Enum.AutomaticSize.X
	root.Size = UDim2.fromOffset(dims.px, dims.px)
	Base.list(root, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)

	local chip = Instance.new("Frame")
	chip.Name = "Pastille"
	chip.BorderSizePixel = 0
	chip.Size = UDim2.fromOffset(dims.px, dims.px)
	chip.LayoutOrder = 1
	local chipCorner = Base.corner(chip, "Pill")
	Base.stroke(chip, Theme.Colors.Ink, Theme.StrokeWidth.Thin)
	chip.Parent = root

	local glyph = Base.newText("Glyphe", dims.text, "Heavy", Theme.Colors.Ink)
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.TextXAlignment = Enum.TextXAlignment.Center
	glyph.Parent = chip

	local label = Base.newText("Libelle", dims.text, "Bold", Theme.Colors.Paper)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, dims.px)
	label.LayoutOrder = 2
	label.Visible = showLabel
	label.Parent = root

	local api = {} :: TeamMarkerApi
	api.Instance = root

	function api.SetTeam(team: string?)
		local style = Theme.team(team)
		if not style then
			root.Visible = props.hideWhenNone ~= true and props.visible ~= false
			chip.BackgroundColor3 = Theme.Colors.Disabled
			chipCorner.CornerRadius = UDim.new(0.5, 0)
			glyph.Text = "–"
			glyph.TextColor3 = Theme.Colors.Paper
			label.TextColor3 = Theme.Colors.PaperDim
			Base.setText(label, nil, "ui.team.none", nil)
			return
		end
		root.Visible = props.visible ~= false
		chip.BackgroundColor3 = style.color
		chipCorner.CornerRadius = if style.shape == "Diamond" then UDim.new(0, 6) else UDim.new(0.5, 0)
		glyph.Text = style.glyph
		glyph.TextColor3 = Theme.textOn(style.color)
		label.TextColor3 = style.text
		Base.setText(label, nil, style.labelKey, nil)
	end

	Base.applyCommon(root, {
		position = props.position,
		anchorPoint = props.anchorPoint,
		layoutOrder = props.layoutOrder,
		zIndex = props.zIndex,
	})
	api.SetTeam(props.team)
	if props.parent then
		root.Parent = props.parent
	end
	return api
end

return TeamMarker
