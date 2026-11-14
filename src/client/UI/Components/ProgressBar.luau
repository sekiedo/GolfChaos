--!strict
--[[
	ProgressBar — barre de progression cartoon (rail encre, remplissage coloré avec reflet, texte optionnel).

	  local bar = ProgressBar.new({ value = 0.3, color = Theme.Colors.Success, parent = frame, showText = true })
	  bar.Set(0.75)             -- animé (instantané si effets réduits)
	  bar.Set(1, false)         -- sans animation
	  bar.SetColor(c)   bar.SetText("12 / 20")   bar.Get()

	Props : value (0..1) ; color (Primary) ; height (px design, 22) ; showText (pourcentage centré) ;
	+ communs (name, parent, position, size, anchorPoint, layoutOrder, zIndex, visible).
]]

local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Base)

export type ProgressBarProps = {
	value: number?,
	color: Color3?,
	height: number?,
	showText: boolean?,
	name: string?,
	parent: Instance?,
	position: UDim2?,
	size: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

export type ProgressBarApi = {
	Instance: Frame,
	Set: (value: number, animate: boolean?) -> (),
	Get: () -> number,
	SetColor: (color: Color3) -> (),
	SetText: (text: string?) -> (),
}

local ProgressBar = {}

local function sanitize(value: any): number
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(value, 0, 1)
end

function ProgressBar.new(props: ProgressBarProps): ProgressBarApi
	local height = props.height or 22
	local value = sanitize(props.value)
	local customText: string? = nil

	local root = Instance.new("Frame")
	root.Name = props.name or "Progression"
	root.BorderSizePixel = 0
	root.BackgroundColor3 = Theme.Colors.Ink
	root.Size = props.size or UDim2.new(1, 0, 0, height)
	Base.corner(root, "Pill")
	Base.stroke(root, Theme.Colors.Ink, Theme.StrokeWidth.Normal)

	local fill = Instance.new("Frame")
	fill.Name = "Remplissage"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = props.color or Theme.Colors.Primary
	fill.Size = UDim2.fromScale(value, 1)
	fill.ClipsDescendants = true
	Base.corner(fill, "Pill")
	fill.Parent = root

	local shine = Instance.new("Frame")
	shine.Name = "Reflet"
	shine.BorderSizePixel = 0
	shine.BackgroundColor3 = Theme.Colors.White
	shine.BackgroundTransparency = 0.7
	shine.Position = UDim2.new(0, 6, 0, 3)
	shine.Size = UDim2.new(1, -12, 0.28, 0)
	Base.corner(shine, "Pill")
	shine.Parent = fill

	local text = Base.newText("Texte", "Small", "Heavy", Theme.Colors.Paper)
	text.Size = UDim2.fromScale(1, 1)
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.ZIndex = 2
	text.Visible = props.showText == true
	Base.textStroke(text, 2)
	text.Parent = root

	local function renderText()
		text.Text = customText or string.format("%d %%", math.floor(value * 100 + 0.5))
	end
	renderText()

	local api = {} :: ProgressBarApi
	api.Instance = root

	function api.Set(newValue: number, animate: boolean?)
		value = sanitize(newValue)
		local goal = { Size = UDim2.fromScale(value, 1) }
		if animate == false then
			fill.Size = goal.Size
		else
			Theme.tween(fill, Theme.Motion.Slow, goal, Enum.EasingStyle.Quad)
		end
		fill.Visible = value > 0.001
		renderText()
	end

	function api.Get(): number
		return value
	end

	function api.SetColor(color: Color3)
		fill.BackgroundColor3 = color
	end

	function api.SetText(newText: string?)
		customText = newText
		if newText then
			text.Visible = true
		end
		renderText()
	end

	fill.Visible = value > 0.001
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

return ProgressBar
