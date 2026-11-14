--!strict
--[[
	HoleIntro — présentation du trou pendant le survol de caméra : bandes cinéma haut / bas, carte en bas à
	gauche avec « Trou n/N », nom du trou (Locale "hole.<id>.name", sinon GameState.HoleName), par, biome,
	mode de jeu et phrase de particularité (Locale "hole.<id>.feature" si elle existe).
	Entrée glissée (fondu seul si effets réduits), sortie en fondu. Non modal.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trove = require(Shared.Util.Trove)
local Locale = require(Shared.Locale)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Label = require(UI.Components.Label)
local Util = require(script.Parent.Util)

local HoleIntro = {}

local BAR_HEIGHT = 64
local IN_TIME = 0.45
local OUT_TIME = 0.3

local BIOME_COLORS: { [string]: Color3 } = {
	Coast = Color3.fromRGB(77, 196, 255),
	Forest = Color3.fromRGB(91, 209, 91),
	Desert = Color3.fromRGB(255, 190, 92),
	Snow = Color3.fromRGB(205, 232, 255),
	City = Color3.fromRGB(190, 160, 255),
	Training = Color3.fromRGB(255, 201, 60),
}

local function chip(parent: Instance, name: string, color: Color3, order: number): (Frame, TextLabel)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Size = UDim2.fromOffset(0, 34)
	frame.LayoutOrder = order
	Base.corner(frame, "Pill")
	Base.stroke(frame, Theme.Colors.Ink, Theme.StrokeWidth.Normal)
	Base.padding(frame, nil, 14, 0)
	frame.Parent = parent
	local text = Base.newText("Texte", "Body", "Heavy", Theme.textOn(color))
	text.AutomaticSize = Enum.AutomaticSize.X
	text.Size = UDim2.fromOffset(0, 34)
	text.Parent = frame
	return frame, text
end

function HoleIntro.new(ctx: any): any
	local screen: any = { DisplayOrder = Theme.Layers.Phase }

	local showTrove = Trove.new()
	local topBar: Frame
	local bottomBar: Frame
	local card: CanvasGroup
	local holeNumber: TextLabel
	local nameLabel: Label.LabelApi
	local parText: TextLabel
	local biomeChip: Frame
	local biomeText: TextLabel
	local modeText: TextLabel
	local modeChip: Frame
	local featureLabel: Label.LabelApi
	local cardRest = UDim2.new(0, 32, 1, -BAR_HEIGHT - 24)

	function screen.Build(_self: any, gui: ScreenGui)
		topBar = Instance.new("Frame")
		topBar.Name = "BandeHaut"
		topBar.BorderSizePixel = 0
		topBar.BackgroundColor3 = Theme.Colors.Backdrop
		topBar.Size = UDim2.new(1, 0, 0, BAR_HEIGHT)
		topBar.Position = UDim2.fromOffset(0, -BAR_HEIGHT)
		topBar.Parent = gui

		bottomBar = Instance.new("Frame")
		bottomBar.Name = "BandeBas"
		bottomBar.BorderSizePixel = 0
		bottomBar.BackgroundColor3 = Theme.Colors.Backdrop
		bottomBar.AnchorPoint = Vector2.new(0, 1)
		bottomBar.Size = UDim2.new(1, 0, 0, BAR_HEIGHT)
		bottomBar.Position = UDim2.new(0, 0, 1, BAR_HEIGHT)
		bottomBar.Parent = gui

		card = Instance.new("CanvasGroup")
		card.Name = "Carte"
		card.BackgroundTransparency = 1
		card.AnchorPoint = Vector2.new(0, 1)
		card.Position = cardRest
		card.Size = UDim2.fromOffset(560, 230)
		card.GroupTransparency = 1
		card.Parent = gui
		ctx.Manager.AttachScale(card)

		local shadow = Instance.new("Frame")
		shadow.Name = "Ombre"
		shadow.BorderSizePixel = 0
		shadow.BackgroundColor3 = Theme.Colors.Ink
		shadow.BackgroundTransparency = 0.25
		shadow.Position = UDim2.fromOffset(6, 12)
		shadow.Size = UDim2.new(1, -12, 1, -12)
		Base.corner(shadow, "Large")
		shadow.Parent = card

		local face = Instance.new("Frame")
		face.Name = "Face"
		face.BorderSizePixel = 0
		face.BackgroundColor3 = Theme.Colors.Night
		face.Position = UDim2.fromOffset(0, 6)
		face.Size = UDim2.new(1, -12, 1, -12)
		Base.corner(face, "Large")
		Base.stroke(face, Theme.Colors.Ink, Theme.StrokeWidth.Thick)
		Base.padding(face, Theme.Spacing.L)
		Base.list(face, Enum.FillDirection.Vertical, 6)
		face.Parent = card

		-- Numéro du trou dans une étiquette jaune.
		local numberTag = Instance.new("Frame")
		numberTag.Name = "Numero"
		numberTag.BorderSizePixel = 0
		numberTag.BackgroundColor3 = Theme.Colors.Primary
		numberTag.AutomaticSize = Enum.AutomaticSize.X
		numberTag.Size = UDim2.fromOffset(0, 32)
		numberTag.LayoutOrder = 1
		Base.corner(numberTag, "Small")
		Base.stroke(numberTag, Theme.Colors.Ink, Theme.StrokeWidth.Normal)
		Base.padding(numberTag, nil, 12, 0)
		numberTag.Parent = face
		holeNumber = Base.newText("Texte", "Body", "Display", Theme.Colors.Ink)
		holeNumber.AutomaticSize = Enum.AutomaticSize.X
		holeNumber.Size = UDim2.fromOffset(0, 32)
		holeNumber.Parent = numberTag

		nameLabel = Label.new({
			name = "Nom",
			style = "Display",
			font = "Display",
			stroke = 4,
			color = Theme.Colors.Paper,
			truncate = true,
			wrap = false,
			size = UDim2.new(1, 0, 0, 58),
			layoutOrder = 2,
			parent = face,
		})

		local chips = Instance.new("Frame")
		chips.Name = "Pastilles"
		chips.BackgroundTransparency = 1
		chips.Size = UDim2.new(1, 0, 0, 38)
		chips.LayoutOrder = 3
		Base.list(chips, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		chips.Parent = face

		local _, par = chip(chips, "Par", Theme.Colors.Success, 1)
		parText = par
		biomeChip, biomeText = chip(chips, "Biome", Theme.Colors.Secondary, 2)
		local modeFrame, mode = chip(chips, "Mode", Theme.Colors.NightRaised, 3)
		modeChip = modeFrame
		modeText = mode
		modeText.TextColor3 = Theme.Colors.Paper

		featureLabel = Label.new({
			name = "Particularite",
			style = "Body",
			font = "Bold",
			color = Theme.Colors.PaperDim,
			wrap = true,
			layoutOrder = 4,
			parent = face,
		})
	end

	local function fill()
		local index = Util.attr("HoleIndex")
		local count = Util.attr("HoleCount")
		if type(index) == "number" and type(count) == "number" and count > 0 then
			holeNumber.Text = string.upper(Locale.t("match.intro.hole", { index = index, count = count }))
		else
			holeNumber.Text = string.upper(Locale.t("match.phase.HoleIntro"))
		end

		local holeId = Util.attr("HoleId")
		local nameKey = if type(holeId) == "string" then "hole." .. holeId .. ".name" else ""
		if nameKey ~= "" and Locale.has(nameKey, "fr") then
			nameLabel.SetKey(nameKey)
		else
			local fallback = Util.attr("HoleName")
			nameLabel.SetText(if type(fallback) == "string" and fallback ~= "" then fallback else "?")
		end

		local par = Util.attr("HolePar")
		parText.Text = Locale.t("match.intro.par", { par = if type(par) == "number" then par else "?" })

		local biome = Util.attr("HoleBiome")
		if type(biome) == "string" and biome ~= "" then
			biomeChip.Visible = true
			local color = BIOME_COLORS[biome] or Theme.Colors.Secondary
			biomeChip.BackgroundColor3 = color
			biomeText.TextColor3 = Theme.textOn(color)
			local biomeKey = "lobby.value.biome." .. biome
			biomeText.Text = if Locale.has(biomeKey, "fr") then Locale.t(biomeKey) else biome
		else
			biomeChip.Visible = false
		end

		local mode = Util.attr("Mode")
		local modeKey = if type(mode) == "string" then "match.mode." .. mode else ""
		modeChip.Visible = modeKey ~= "" and Locale.has(modeKey, "fr")
		if modeChip.Visible then
			modeText.Text = Locale.t(modeKey)
		end

		local featureKey = if type(holeId) == "string" then "hole." .. holeId .. ".feature" else ""
		if featureKey ~= "" and Locale.has(featureKey, "fr") then
			featureLabel.SetKey(featureKey)
			featureLabel.Instance.Visible = true
		else
			featureLabel.Instance.Visible = false
		end
	end

	function screen.Show(_self: any, _args: any, wasVisible: boolean)
		fill()
		if wasVisible then
			return
		end
		showTrove:Clean()
		local folder = Util.gameState()
		if folder then
			for _, name in { "HoleId", "HoleName", "HolePar", "HoleBiome", "HoleIndex", "HoleCount", "Mode" } do
				showTrove:Connect(folder:GetAttributeChangedSignal(name), fill)
			end
		end
		card.GroupTransparency = 1
		Theme.fade(card, IN_TIME, { GroupTransparency = 0 })
		if Theme.isReducedMotion() then
			topBar.Position = UDim2.fromOffset(0, 0)
			bottomBar.Position = UDim2.new(0, 0, 1, 0)
			card.Position = cardRest
		else
			topBar.Position = UDim2.fromOffset(0, -BAR_HEIGHT)
			bottomBar.Position = UDim2.new(0, 0, 1, BAR_HEIGHT)
			Theme.tween(topBar, IN_TIME, { Position = UDim2.fromOffset(0, 0) })
			Theme.tween(bottomBar, IN_TIME, { Position = UDim2.new(0, 0, 1, 0) })
			card.Position = cardRest - UDim2.fromOffset(160, 0)
			Theme.tween(card, IN_TIME + 0.1, { Position = cardRest }, Enum.EasingStyle.Back)
		end
	end

	function screen.Hide(_self: any): number?
		showTrove:Clean()
		Theme.fade(card, OUT_TIME, { GroupTransparency = 1 })
		Theme.tween(topBar, OUT_TIME, { Position = UDim2.fromOffset(0, -BAR_HEIGHT) })
		Theme.tween(bottomBar, OUT_TIME, { Position = UDim2.new(0, 0, 1, BAR_HEIGHT) })
		return OUT_TIME
	end

	function screen.Destroy(_self: any)
		showTrove:Clean()
	end

	return screen
end

return HoleIntro
