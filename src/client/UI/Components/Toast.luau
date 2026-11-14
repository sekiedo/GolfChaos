--!strict
--[[
	Toast — bulle de notification courte (pastille colorée selon le type + glyphe + texte), entrée glissée,
	sortie en fondu. La file, la déduplication et la durée sont gérées par NotificationController.

	  local toast = Toast.new({ text = "Bravo !", kind = "success", parent = stack })
	  toast.Show()              -- entrée animée (simple fondu si effets réduits)
	  toast.Dismiss() -> secondes jusqu'à la destruction (fondu de sortie)
	  toast.SetCount(3)         -- regroupement : « ×3 » quand le même message revient

	Types (kind) : "info" (défaut), "success", "warn", "error", "hit", "achievement", "coins".
	Chaque type a un glyphe distinct : le sens ne repose pas sur la seule couleur.
]]

local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Base)

export type ToastProps = {
	text: string,
	kind: string?,
	title: string?,
	name: string?,
	parent: Instance?,
	layoutOrder: number?,
}

export type ToastApi = {
	Instance: Frame,
	Show: () -> (),
	Dismiss: () -> number,
	SetText: (text: string) -> (),
	SetCount: (count: number) -> (),
}

type KindStyle = { color: Color3, glyph: string }

local KINDS: { [string]: KindStyle } = {
	info = { color = Theme.Colors.Secondary, glyph = "i" },
	success = { color = Theme.Colors.Success, glyph = "✓" },
	warn = { color = Theme.Colors.Warning, glyph = "!" },
	error = { color = Theme.Colors.Danger, glyph = "✕" },
	hit = { color = Theme.Colors.Danger, glyph = "✸" },
	achievement = { color = Theme.Colors.Accent, glyph = "★" },
	coins = { color = Theme.Colors.Primary, glyph = "◎" },
}

local WIDTH = 420
local IN_TIME = 0.25
local OUT_TIME = 0.2

local Toast = {}

function Toast.kindStyle(kind: string?): KindStyle
	return KINDS[kind or "info"] or KINDS.info
end

function Toast.new(props: ToastProps): ToastApi
	local style = Toast.kindStyle(props.kind)

	-- Le conteneur garde la place dans la pile ; la carte glisse à l'intérieur.
	local root = Instance.new("Frame")
	root.Name = props.name or "Toast"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.Size = UDim2.new(1, 0, 0, 0)
	root.LayoutOrder = props.layoutOrder or 0
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(WIDTH, math.huge)
	limit.Parent = root

	local group = Instance.new("CanvasGroup")
	group.Name = "Carte"
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.AutomaticSize = Enum.AutomaticSize.Y
	group.Size = UDim2.new(1, 0, 0, 0)
	group.GroupTransparency = 1
	group.Parent = root

	local card = Instance.new("Frame")
	card.Name = "Fond"
	card.BorderSizePixel = 0
	card.BackgroundColor3 = Theme.Colors.Night
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, -6, 0, 0)
	card.Position = UDim2.fromOffset(3, 3)
	Base.corner(card, "Medium")
	Base.stroke(card, Theme.Colors.Ink, Theme.StrokeWidth.Normal)
	Base.padding(card, nil, 10, 8)
	card.Parent = group

	local accent = Instance.new("Frame")
	accent.Name = "Bande"
	accent.BorderSizePixel = 0
	accent.BackgroundColor3 = style.color
	accent.Position = UDim2.fromOffset(-10, -8)
	accent.Size = UDim2.new(0, 8, 1, 16)
	Base.corner(accent, "Small")
	accent.Parent = card

	local row = Instance.new("Frame")
	row.Name = "Ligne"
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.Size = UDim2.new(1, 0, 0, 0)
	Base.list(row, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	row.Parent = card

	local badge = Instance.new("Frame")
	badge.Name = "Pastille"
	badge.BorderSizePixel = 0
	badge.BackgroundColor3 = style.color
	badge.Size = UDim2.fromOffset(34, 34)
	badge.LayoutOrder = 1
	Base.corner(badge, "Pill")
	Base.stroke(badge, Theme.Colors.Ink, Theme.StrokeWidth.Thin)
	badge.Parent = row

	local glyph = Base.newText("Glyphe", "Body", "Display", Theme.textOn(style.color))
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.TextXAlignment = Enum.TextXAlignment.Center
	glyph.Text = style.glyph
	glyph.Parent = badge

	local textBox = Instance.new("Frame")
	textBox.Name = "Textes"
	textBox.BackgroundTransparency = 1
	textBox.AutomaticSize = Enum.AutomaticSize.Y
	textBox.Size = UDim2.new(1, -96, 0, 0)
	textBox.LayoutOrder = 2
	Base.list(textBox, Enum.FillDirection.Vertical, 0)
	textBox.Parent = row

	if props.title and props.title ~= "" then
		local title = Base.newText("Titre", "Small", "Heavy", style.color)
		title.TextColor3 = Theme.ensureContrast(style.color, Theme.Colors.Night)
		title.AutomaticSize = Enum.AutomaticSize.Y
		title.Size = UDim2.new(1, 0, 0, 0)
		title.TextWrapped = true
		title.Text = props.title
		title.LayoutOrder = 1
		title.Parent = textBox
	end

	local message = Base.newText("Message", "Body", "Bold", Theme.Colors.Paper)
	message.AutomaticSize = Enum.AutomaticSize.Y
	message.Size = UDim2.new(1, 0, 0, 0)
	message.TextWrapped = true
	message.Text = props.text
	message.LayoutOrder = 2
	message.Parent = textBox

	local count = Base.newText("Compte", "Small", "Heavy", Theme.Colors.Primary)
	count.Size = UDim2.fromOffset(40, 24)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.LayoutOrder = 3
	count.Visible = false
	count.Parent = row

	local api = {} :: ToastApi
	api.Instance = root
	local dismissed = false

	function api.Show()
		Theme.fade(group, IN_TIME, { GroupTransparency = 0 })
		if not Theme.isReducedMotion() then
			group.Position = UDim2.fromOffset(0, -18)
			Theme.tween(group, IN_TIME, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
		end
	end

	function api.Dismiss(): number
		if dismissed then
			return 0
		end
		dismissed = true
		Theme.fade(group, OUT_TIME, { GroupTransparency = 1 })
		task.delay(OUT_TIME, function()
			root:Destroy()
		end)
		return OUT_TIME
	end

	function api.SetText(text: string)
		message.Text = text
	end

	function api.SetCount(n: number)
		count.Visible = n > 1
		count.Text = "×" .. tostring(n)
		if n > 1 and not Theme.isReducedMotion() then
			local scale = badge:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			scale.Parent = badge
			scale.Scale = 1.25
			Theme.tween(scale, Theme.Motion.Normal, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end

	if props.parent then
		root.Parent = props.parent
	end
	return api
end

return Toast
