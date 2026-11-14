--!strict
--[[
	Hud/HoleCard — carte du trou (haut gauche) : « Trou n/N », par, nom du trou, coups du joueur et écart au par.

	  local card = HoleCard.new(parent)
	  card.SetHole(index, count)   card.SetName(texte)   card.SetPar(par)   card.SetStrokes(coups)
	  card.Instance   card.Destroy()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared.Locale)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Kit = require(script.Parent.Kit)

export type HoleCard = {
	Instance: Frame,
	SetHole: (index: number?, count: number?) -> (),
	SetName: (text: string) -> (),
	SetPar: (par: number?) -> (),
	SetStrokes: (strokes: number?) -> (),
	Destroy: () -> (),
}

local HoleCard = {}

function HoleCard.new(parent: Instance): HoleCard
	local root = Kit.panel(parent, "CarteTrou")
	root.Position = UDim2.fromOffset(12, 12)
	root.Size = UDim2.fromOffset(300, 98)
	Base.padding(root, 10, 12, 8)

	local badges = Instance.new("Frame")
	badges.Name = "Badges"
	badges.BackgroundTransparency = 1
	badges.Size = UDim2.new(1, -84, 0, 26)
	Base.list(badges, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	badges.Parent = root
	local holeBadge, holeText = Kit.pill(badges, "Trou", Theme.Colors.Primary)
	holeBadge.LayoutOrder = 1
	local parBadge, parText = Kit.pill(badges, "Par", Theme.Colors.Secondary)
	parBadge.LayoutOrder = 2

	local name = Kit.text(root, "Nom", "Heading", "Display", Theme.Colors.Paper, true)
	name.Position = UDim2.fromOffset(0, 32)
	name.Size = UDim2.new(1, -84, 0, 26)
	name.TextTruncate = Enum.TextTruncate.AtEnd

	local toPar = Kit.text(root, "EcartPar", "Small", "Bold", Theme.Colors.PaperDim, true)
	toPar.Position = UDim2.fromOffset(0, 60)
	toPar.Size = UDim2.new(1, -84, 0, 20)

	-- Bloc des coups (à droite).
	local strokesBox = Instance.new("Frame")
	strokesBox.Name = "Coups"
	strokesBox.AnchorPoint = Vector2.new(1, 0.5)
	strokesBox.Position = UDim2.new(1, 0, 0.5, 0)
	strokesBox.Size = UDim2.fromOffset(74, 74)
	strokesBox.BackgroundColor3 = Theme.Colors.NightRaised
	strokesBox.BorderSizePixel = 0
	Base.corner(strokesBox, "Medium")
	Base.stroke(strokesBox, Theme.Colors.Ink, Theme.StrokeWidth.Normal)
	strokesBox.Parent = root
	local strokesTitle = Kit.text(strokesBox, "Titre", "Caption", "Heavy", Theme.Colors.PaperDim, true)
	strokesTitle.Size = UDim2.new(1, 0, 0, 18)
	strokesTitle.Position = UDim2.fromOffset(0, 4)
	strokesTitle.TextXAlignment = Enum.TextXAlignment.Center
	Base.setText(strokesTitle, nil, "hud.strokes")
	local strokesValue = Kit.text(strokesBox, "Valeur", "Display", "Display", Theme.Colors.Primary, true)
	strokesValue.Size = UDim2.new(1, 0, 1, -24)
	strokesValue.Position = UDim2.fromOffset(0, 22)
	strokesValue.TextXAlignment = Enum.TextXAlignment.Center

	local current = { par = 0, strokes = 0 }

	local function refreshToPar()
		if current.par <= 0 then
			toPar.Text = ""
			return
		end
		local diff = current.strokes - current.par
		if current.strokes <= 0 then
			toPar.Text = Locale.t("hud.par", { n = current.par })
			toPar.TextColor3 = Theme.Colors.PaperDim
		elseif diff == 0 then
			toPar.Text = "= " .. Locale.t("hud.toPar.even")
			toPar.TextColor3 = Theme.Colors.PaperDim
		elseif diff < 0 then
			toPar.Text = "▼ " .. Locale.t("hud.toPar.under", { n = -diff })
			toPar.TextColor3 = Theme.Colors.Success
		else
			toPar.Text = "▲ " .. Locale.t("hud.toPar.over", { n = diff })
			toPar.TextColor3 = Theme.Colors.Warning
		end
	end

	local api = {} :: HoleCard
	api.Instance = root

	function api.SetHole(index: number?, count: number?)
		if type(index) ~= "number" or index <= 0 then
			holeText.Text = Locale.t("hud.holeSingle", { n = "?" })
		elseif type(count) == "number" and count > 0 then
			holeText.Text = Locale.t("hud.hole", { n = index, total = count })
		else
			holeText.Text = Locale.t("hud.holeSingle", { n = index })
		end
	end

	function api.SetName(text: string)
		name.Text = if text ~= "" then text else Locale.t("hud.holeNameUnknown")
	end

	function api.SetPar(par: number?)
		current.par = if type(par) == "number" then par else 0
		parBadge.Visible = current.par > 0
		parText.Text = Locale.t("hud.par", { n = current.par })
		refreshToPar()
	end

	function api.SetStrokes(strokes: number?)
		local value = if type(strokes) == "number" then math.max(0, math.floor(strokes)) else 0
		local changed = value ~= current.strokes
		current.strokes = value
		strokesValue.Text = Locale.t("hud.strokesValue", { n = value })
		refreshToPar()
		if changed and value > 0 then
			Kit.bump(strokesBox, 1.2)
		end
	end

	function api.Destroy()
		root:Destroy()
	end

	api.SetHole(nil, nil)
	api.SetName("")
	api.SetPar(nil)
	api.SetStrokes(0)
	return api
end

return HoleCard
