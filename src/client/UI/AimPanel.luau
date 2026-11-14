--!strict
--[[
	AimPanel — panneau de visée du golf (jauge de puissance cartoon, type de coup, angle, distance, vent,
	invite, aide contextuelle, messages courts, boutons tactiles).

	  local panel = AimPanel.new()          -- crée son propre ScreenGui « AimPanel » sous PlayerGui
	  panel:SetVisible(bool)                 panneau principal (l'invite et les messages restent indépendants)
	  panel:SetPower(0..1)                   position de la jauge
	  panel:SetCharging(bool)                jauge active (pulsation, titre « Frappe au bon moment ! »)
	  panel:SetLoft(degrés)                  panel:SetShotType("Drive" | "Chip" | "Putt" | "Guided")
	  panel:SetDistance(studs?)              distance au trou (nil = inconnue)
	  panel:SetWind(Vector3)                 flèche relative à la caméra + intensité
	  panel:SetPrompt(texte?)                invite (ex. « E : viser ») ; nil = masquée
	  panel:SetHint(texte)                   ligne d'aide sous le panneau ("" = masquée)
	  panel:SetSweetSpot(puissance?)         repère ◆ de la puissance conseillée (nil = masqué)
	  panel:SetSuggestion(texte?)            pastille de conseil (ex. « Putt conseillé »)
	  panel:ShowMessage(texte, genre?)       message court ("info" | "warn" | "good"), fondu automatique
	  panel:Destroy()
	  Signaux (Util/Signal) : SwingActivated, CancelActivated, ShotTypeActivated, LoftChanged(delta)

	Les boutons tactiles (Frapper, Annuler, Coup, Angle ±) n'apparaissent que si l'appareil courant est tactile
	(InputController.GetDevice()). Bandes de couleur de la jauge doublées de libellés (jamais la couleur seule).
	Animations coupées quand les effets sont réduits (Theme.isReducedMotion) ; tailles suivies sur téléphone.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Trove = require(Shared.Util.Trove)
local Locale = require(Shared.Locale)

local Theme = require(script.Parent.Theme)
local Base = require(script.Parent.Components.Base)
local Button = require(script.Parent.Components.Button)

export type AimPanel = {
	SwingActivated: Signal.Signal,
	CancelActivated: Signal.Signal,
	ShotTypeActivated: Signal.Signal,
	LoftChanged: Signal.Signal,
	SetVisible: (self: AimPanel, visible: boolean) -> (),
	SetPower: (self: AimPanel, power: number) -> (),
	SetCharging: (self: AimPanel, charging: boolean) -> (),
	SetLoft: (self: AimPanel, degrees: number) -> (),
	SetShotType: (self: AimPanel, shotType: string) -> (),
	SetDistance: (self: AimPanel, studs: number?) -> (),
	SetWind: (self: AimPanel, wind: Vector3) -> (),
	SetPrompt: (self: AimPanel, text: string?) -> (),
	SetHint: (self: AimPanel, text: string) -> (),
	SetSweetSpot: (self: AimPanel, power: number?) -> (),
	SetSuggestion: (self: AimPanel, text: string?) -> (),
	ShowMessage: (self: AimPanel, text: string, kind: string?) -> (),
	IsVisible: (self: AimPanel) -> boolean,
	Destroy: (self: AimPanel) -> (),
}

type Band = { from: number, to: number, color: Color3, key: string }

-- Bandes de la jauge : couleur + libellé (lisible sans percevoir les couleurs).
local BANDS: { Band } = {
	{ from = 0, to = 0.4, color = Theme.Colors.Success, key = "aim.panel.bandLow" },
	{ from = 0.4, to = 0.7, color = Theme.Colors.Primary, key = "aim.panel.bandMid" },
	{ from = 0.7, to = 0.9, color = Theme.Colors.Warning, key = "aim.panel.bandHigh" },
	{ from = 0.9, to = 1, color = Theme.Colors.Danger, key = "aim.panel.bandMax" },
}

local MESSAGE_TIME = 2.6
local CARD_MIN_WIDTH = 330
local CARD_MAX_WIDTH = 600
local CARD_HEIGHT = 156
local CARD_BOTTOM = 64 -- place laissée à la ligne d'aide sous le panneau

local localPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Aides
--------------------------------------------------------------------------------

local inputModule: any = nil
local inputLooked = false

local function getInput(): any
	if not inputLooked then
		inputLooked = true
		local ui = script.Parent
		local client = if ui then ui.Parent else nil
		local controllers = if client then client:FindFirstChild("Controllers") else nil
		local module = if controllers then controllers:FindFirstChild("InputController") else nil
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				inputModule = result
			end
		end
	end
	return inputModule
end

local function currentDevice(): string
	local input = getInput()
	if input and type(input.GetDevice) == "function" then
		local ok, device = pcall(input.GetDevice)
		if ok and type(device) == "string" then
			return device
		end
	end
	return "KeyboardMouse"
end

-- Texte stylé avec contour cartoon et taille bornée (TextScaled + contrainte : lisible sur téléphone).
local function newText(parent: Instance, name: string, size: string, font: string?, color: Color3?, scaled: boolean?): TextLabel
	local label = Base.newText(name, size, font, color)
	Base.textStroke(label, 2)
	if scaled then
		label.TextScaled = true
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MinTextSize = 11
		constraint.MaxTextSize = math.max(12, Theme.textSize(size))
		constraint.Parent = label
	end
	label.Parent = parent
	return label
end

local function newFrame(parent: Instance, name: string, color: Color3, transparency: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

-- Pastille d'information (titre + valeur) ; bouton si `clickable`.
local function newChip(parent: Instance, name: string, order: number, clickable: boolean): (GuiObject, TextLabel, TextLabel)
	local chip: GuiObject
	if clickable then
		local button = Instance.new("TextButton")
		button.Text = ""
		button.AutoButtonColor = true
		Base.makeSelectable(button, "Rounded")
		chip = button
	else
		chip = Instance.new("Frame")
	end
	chip.Name = name
	chip.BackgroundColor3 = Theme.Colors.NightRaised
	chip.BorderSizePixel = 0
	chip.Size = UDim2.new(0.25, -6, 1, 0)
	chip.LayoutOrder = order
	Base.corner(chip, "Medium")
	Base.stroke(chip, Theme.Colors.Ink, Theme.StrokeWidth.Thin)
	local title = newText(chip, "Titre", "Caption", "Heavy", Theme.Colors.PaperDim, true)
	title.Size = UDim2.new(1, -10, 0.42, 0)
	title.Position = UDim2.new(0, 5, 0, 2)
	title.TextXAlignment = Enum.TextXAlignment.Center
	local value = newText(chip, "Valeur", "Body", "Display", Theme.Colors.Paper, true)
	value.Size = UDim2.new(1, -10, 0.56, -2)
	value.Position = UDim2.new(0, 5, 0.42, 0)
	value.TextXAlignment = Enum.TextXAlignment.Center
	chip.Parent = parent
	return chip, title, value
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local AimPanel = {}
AimPanel.__index = AimPanel

function AimPanel.new(): AimPanel
	local self = setmetatable({}, AimPanel) :: any
	local trove = Trove.new()
	self._trove = trove
	self._visible = false
	self._charging = false
	self._power = 0
	self._wind = Vector3.zero
	self._promptText = nil :: string?
	self._messageToken = 0
	self._destroyed = false

	self.SwingActivated = Signal.new()
	self.CancelActivated = Signal.new()
	self.ShotTypeActivated = Signal.new()
	self.LoftChanged = Signal.new()
	trove:Add(self.SwingActivated)
	trove:Add(self.CancelActivated)
	trove:Add(self.ShotTypeActivated)
	trove:Add(self.LoftChanged)

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("AimPanel")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "AimPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 6
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	trove:Add(gui)
	self._gui = gui

	local scale = Instance.new("UIScale")
	scale.Scale = Theme.getScale()
	scale.Parent = gui
	trove:Connect(Theme.Changed, function(what: any)
		if what == "layout" then
			scale.Scale = Theme.getScale()
		end
	end)

	-- Carte principale --------------------------------------------------------
	local card = newFrame(gui, "Carte", Theme.Colors.Night, Theme.backgroundTransparency(0.08))
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -CARD_BOTTOM)
	card.Size = UDim2.new(0.5, 0, 0, CARD_HEIGHT)
	card.Visible = false
	Base.corner(card, "Large")
	local cardStroke = Base.stroke(card, Theme.Colors.Ink, Theme.StrokeWidth.Thick)
	Base.padding(card, 10, 12, 10)
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(CARD_MIN_WIDTH, 0)
	sizeConstraint.MaxSize = Vector2.new(CARD_MAX_WIDTH, math.huge)
	sizeConstraint.Parent = card
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card
	self._card = card
	self._cardStroke = cardStroke
	self._cardScale = cardScale

	-- Rangée des pastilles : coup, angle, distance, vent.
	local chips = newFrame(card, "Pastilles", Theme.Colors.Night, 1)
	chips.Size = UDim2.new(1, 0, 0, 46)
	Base.list(chips, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

	local shotChip, shotTitle, shotValue = newChip(chips, "Coup", 1, true)
	shotTitle.Text = Locale.t("aim.panel.shotTitle")
	self._shotValue = shotValue
	self._shotTitle = shotTitle
	trove:Connect((shotChip :: TextButton).Activated, function()
		Base.playSound("ui_click")
		self.ShotTypeActivated:Fire()
	end)

	local _, loftTitle, loftValue = newChip(chips, "Angle", 2, false)
	loftTitle.Text = Locale.t("aim.panel.loftTitle")
	self._loftValue = loftValue

	local _, distanceTitle, distanceValue = newChip(chips, "Distance", 3, false)
	distanceTitle.Text = "⛳"
	self._distanceValue = distanceValue

	local windChip, windTitle, windValue = newChip(chips, "Vent", 4, false)
	windTitle.Text = Locale.t("aim.panel.windTitle")
	windValue.Size = UDim2.new(0.62, -6, 0.56, -2)
	windValue.Position = UDim2.new(0.38, 0, 0.42, 0)
	windValue.TextXAlignment = Enum.TextXAlignment.Left
	local windArrow = newText(windChip, "Fleche", "Heading", "Display", Theme.Colors.Secondary, true)
	windArrow.Text = "▲"
	windArrow.Size = UDim2.new(0.36, 0, 0.56, -2)
	windArrow.Position = UDim2.new(0.02, 0, 0.42, 0)
	windArrow.TextXAlignment = Enum.TextXAlignment.Center
	self._windValue = windValue
	self._windArrow = windArrow

	-- Titre et valeur de la jauge.
	local gaugeHeader = newFrame(card, "EnteteJauge", Theme.Colors.Night, 1)
	gaugeHeader.Position = UDim2.new(0, 0, 0, 52)
	gaugeHeader.Size = UDim2.new(1, 0, 0, 24)
	local powerTitle = newText(gaugeHeader, "Titre", "Body", "Heavy", Theme.Colors.Paper, true)
	powerTitle.Size = UDim2.new(0.7, 0, 1, 0)
	powerTitle.Text = Locale.t("aim.panel.power")
	local powerValue = newText(gaugeHeader, "Valeur", "Heading", "Display", Theme.Colors.Primary, true)
	powerValue.AnchorPoint = Vector2.new(1, 0)
	powerValue.Position = UDim2.new(1, 0, 0, -2)
	powerValue.Size = UDim2.new(0.3, 0, 1, 4)
	powerValue.TextXAlignment = Enum.TextXAlignment.Right
	powerValue.Text = "—"
	self._powerTitle = powerTitle
	self._powerValue = powerValue

	-- Jauge : bandes vives, cache sombre au-delà de la puissance, aiguille, repère idéal.
	local gauge = newFrame(card, "Jauge", Theme.Colors.Ink, 0)
	gauge.Position = UDim2.new(0, 0, 0, 80)
	gauge.Size = UDim2.new(1, 0, 0, 36)
	Base.corner(gauge, "Pill")
	Base.stroke(gauge, Theme.Colors.Ink, Theme.StrokeWidth.Thick)
	local track = newFrame(gauge, "Piste", Theme.Colors.Ink, 1)
	track.Position = UDim2.fromOffset(4, 4)
	track.Size = UDim2.new(1, -8, 1, -8)
	track.ClipsDescendants = true
	Base.corner(track, "Pill")
	for index, band in BANDS do
		local segment = newFrame(track, "Bande" .. index, band.color, 0)
		segment.Position = UDim2.new(band.from, 0, 0, 0)
		segment.Size = UDim2.new(band.to - band.from, 0, 1, 0)
		local shine = newFrame(segment, "Reflet", Color3.new(1, 1, 1), 0.72)
		shine.Size = UDim2.new(1, 0, 0.32, 0)
		shine.Position = UDim2.new(0, 0, 0.1, 0)
		if index > 1 then
			local separator = newFrame(track, "Separateur" .. index, Theme.Colors.Ink, 0.2)
			separator.Position = UDim2.new(band.from, -1, 0, 0)
			separator.Size = UDim2.new(0, 2, 1, 0)
			separator.ZIndex = 2
		end
	end
	local cover = newFrame(track, "Cache", Theme.Colors.Ink, 0.38)
	cover.ZIndex = 3
	cover.Position = UDim2.new(0, 0, 0, 0)
	cover.Size = UDim2.new(1, 0, 1, 0)
	self._cover = cover

	local sweet = newFrame(gauge, "ZoneIdeale", Color3.new(1, 1, 1), 0)
	sweet.AnchorPoint = Vector2.new(0.5, 0.5)
	sweet.Size = UDim2.new(0, 4, 1, 6)
	sweet.Position = UDim2.new(0.5, 0, 0.5, 0)
	sweet.ZIndex = 4
	sweet.Visible = false
	Base.stroke(sweet, Theme.Colors.Ink, 1.5)
	local sweetGlyph = newText(sweet, "Glyphe", "Body", "Display", Color3.new(1, 1, 1), false)
	sweetGlyph.AnchorPoint = Vector2.new(0.5, 1)
	sweetGlyph.Position = UDim2.new(0.5, 0, 0, 2)
	sweetGlyph.Size = UDim2.fromOffset(24, 20)
	sweetGlyph.TextXAlignment = Enum.TextXAlignment.Center
	sweetGlyph.Text = "◆"
	self._sweet = sweet

	local needle = newFrame(gauge, "Aiguille", Color3.new(1, 1, 1), 0)
	needle.AnchorPoint = Vector2.new(0.5, 0.5)
	needle.Size = UDim2.new(0, 8, 1, 14)
	needle.Position = UDim2.new(0, 0, 0.5, 0)
	needle.ZIndex = 5
	Base.corner(needle, "Pill")
	Base.stroke(needle, Theme.Colors.Ink, Theme.StrokeWidth.Normal)
	self._needle = needle

	-- Libellés des bandes (sous la jauge).
	local bandLabels = newFrame(card, "LibellesBandes", Theme.Colors.Night, 1)
	bandLabels.Position = UDim2.new(0, 0, 0, 118)
	bandLabels.Size = UDim2.new(1, 0, 0, 18)
	for index, band in BANDS do
		local label = newText(bandLabels, "Libelle" .. index, "Caption", "Heavy", Theme.Colors.PaperDim, true)
		label.Position = UDim2.new(band.from, 0, 0, 0)
		label.Size = UDim2.new(band.to - band.from, 0, 1, 0)
		label.TextXAlignment = Enum.TextXAlignment.Center
		Base.setText(label, nil, band.key)
	end

	-- Pastille de conseil (au-dessus de la carte).
	local suggestion = newFrame(gui, "Conseil", Theme.Colors.Secondary, 0)
	suggestion.AnchorPoint = Vector2.new(0.5, 1)
	suggestion.Position = UDim2.new(0.5, 0, 1, -(CARD_BOTTOM + CARD_HEIGHT + 8))
	suggestion.Size = UDim2.fromOffset(0, 30)
	suggestion.AutomaticSize = Enum.AutomaticSize.X
	suggestion.Visible = false
	Base.corner(suggestion, "Pill")
	Base.stroke(suggestion, Theme.Colors.Ink, Theme.StrokeWidth.Normal)
	Base.padding(suggestion, 0, 14, 0)
	local suggestionText = newText(suggestion, "Texte", "Small", "Heavy", Theme.Colors.Ink, false)
	suggestionText.Size = UDim2.new(0, 0, 1, 0)
	suggestionText.AutomaticSize = Enum.AutomaticSize.X
	suggestionText.TextXAlignment = Enum.TextXAlignment.Center
	for _, child in suggestionText:GetChildren() do
		if child:IsA("UIStroke") then
			child:Destroy()
		end
	end
	self._suggestion = suggestion
	self._suggestionText = suggestionText

	-- Ligne d'aide (sous la carte).
	local hint = newText(gui, "Aide", "Small", "Bold", Theme.Colors.Paper, true)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -14)
	hint.Size = UDim2.new(0.9, 0, 0, 40)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.TextWrapped = true
	hint.Visible = false
	self._hint = hint

	-- Invite (indépendante du panneau : visible aussi hors visée).
	local prompt = newFrame(gui, "Invite", Theme.Colors.Primary, 0)
	prompt.AnchorPoint = Vector2.new(0.5, 0.5)
	prompt.Position = UDim2.new(0.5, 0, 0.7, 0)
	prompt.Size = UDim2.fromOffset(0, 44)
	prompt.AutomaticSize = Enum.AutomaticSize.X
	prompt.Visible = false
	Base.corner(prompt, "Pill")
	Base.stroke(prompt, Theme.Colors.Ink, Theme.StrokeWidth.Thick)
	Base.padding(prompt, 0, 20, 0)
	local promptScale = Instance.new("UIScale")
	promptScale.Parent = prompt
	local promptText = Base.newText("Texte", "Button", "Display", Theme.Colors.Ink)
	promptText.Size = UDim2.new(0, 0, 1, 0)
	promptText.AutomaticSize = Enum.AutomaticSize.X
	promptText.TextXAlignment = Enum.TextXAlignment.Center
	promptText.Parent = prompt
	self._prompt = prompt
	self._promptLabel = promptText
	self._promptScale = promptScale

	-- Message court (haut d'écran).
	local message = newFrame(gui, "Message", Theme.Colors.Night, 0)
	message.AnchorPoint = Vector2.new(0.5, 0)
	message.Position = UDim2.new(0.5, 0, 0.2, 0)
	message.Size = UDim2.fromOffset(0, 46)
	message.AutomaticSize = Enum.AutomaticSize.X
	message.Visible = false
	Base.corner(message, "Pill")
	local messageStroke = Base.stroke(message, Theme.Colors.Ink, Theme.StrokeWidth.Thick)
	Base.padding(message, 0, 22, 0)
	local messageText = newText(message, "Texte", "Heading", "Display", Theme.Colors.Paper, false)
	messageText.Size = UDim2.new(0, 0, 1, 0)
	messageText.AutomaticSize = Enum.AutomaticSize.X
	messageText.TextXAlignment = Enum.TextXAlignment.Center
	self._message = message
	self._messageText = messageText
	self._messageStroke = messageStroke

	-- Boutons tactiles ---------------------------------------------------------
	local touchRoot = newFrame(gui, "Tactile", Theme.Colors.Night, 1)
	touchRoot.Size = UDim2.fromScale(1, 1)
	touchRoot.Visible = false
	self._touchRoot = touchRoot

	local swing = Button.new({
		key = "controls.action.swing",
		icon = "⛳",
		variant = "Success",
		size = "Large",
		width = 168,
		parent = touchRoot,
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, -24, 1, -190),
		onActivated = function()
			self.SwingActivated:Fire()
		end,
	})
	local cancel = Button.new({
		key = "controls.action.cancel",
		icon = "✕",
		variant = "Danger",
		size = "Small",
		width = 140,
		parent = touchRoot,
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, -38, 1, -268),
		onActivated = function()
			self.CancelActivated:Fire()
		end,
	})
	local shotButton = Button.new({
		key = "controls.action.shotType",
		icon = "⇄",
		variant = "Secondary",
		size = "Small",
		width = 128,
		parent = touchRoot,
		anchorPoint = Vector2.new(0, 0.5),
		position = UDim2.new(0, 20, 0.42, 0),
		onActivated = function()
			self.ShotTypeActivated:Fire()
		end,
	})
	local loftUp = Button.new({
		key = "controls.action.loftUp",
		icon = "▲",
		variant = "Dark",
		size = "Small",
		width = 128,
		parent = touchRoot,
		anchorPoint = Vector2.new(0, 0.5),
		position = UDim2.new(0, 20, 0.42, 58),
		onActivated = function()
			self.LoftChanged:Fire(1)
		end,
	})
	local loftDown = Button.new({
		key = "controls.action.loftDown",
		icon = "▼",
		variant = "Dark",
		size = "Small",
		width = 128,
		parent = touchRoot,
		anchorPoint = Vector2.new(0, 0.5),
		position = UDim2.new(0, 20, 0.42, 116),
		onActivated = function()
			self.LoftChanged:Fire(-1)
		end,
	})
	self._swingButton = swing
	for _, api in { swing, cancel, shotButton, loftUp, loftDown } do
		trove:Add(api.Instance)
	end

	-- Appareil courant : boutons tactiles seulement sur écran tactile.
	local input = getInput()
	if input and type(input.DeviceChanged) == "table" then
		trove:Connect(input.DeviceChanged, function()
			self:_refreshTouch()
		end)
	end

	-- Animation : flèche du vent relative à la caméra, pulsation pendant la charge.
	trove:Connect(RunService.RenderStepped, function()
		self:_render()
	end)

	gui.Parent = playerGui
	self:SetPower(0)
	self:SetLoft(0)
	self:SetShotType("Drive")
	self:SetDistance(nil)
	self:SetWind(Vector3.zero)
	return self :: AimPanel
end

--------------------------------------------------------------------------------
-- Rendu continu
--------------------------------------------------------------------------------

function AimPanel._render(self: any)
	if not self._visible then
		return
	end
	-- Flèche du vent : ▲ = vent qui pousse vers l'avant de la caméra.
	local camera = Workspace.CurrentCamera
	local wind: Vector3 = self._wind
	if camera and wind.Magnitude > 0.05 then
		local look = camera.CFrame.LookVector
		local forward = Vector3.new(look.X, 0, look.Z)
		if forward.Magnitude > 1e-3 then
			forward = forward.Unit
			local right = forward:Cross(Vector3.yAxis)
			local angle = math.deg(math.atan2(wind:Dot(right), wind:Dot(forward)))
			self._windArrow.Rotation = angle
		end
	end
	-- Pulsation de la carte pendant la charge (coupée si les effets sont réduits).
	if self._charging and not Theme.isReducedMotion() then
		local t = os.clock()
		self._cardScale.Scale = 1 + 0.012 * math.sin(t * 10)
		local glow = 0.5 + 0.5 * math.sin(t * 8)
		self._cardStroke.Color = Theme.Colors.Ink:Lerp(Theme.Colors.Primary, glow)
	end
end

function AimPanel._refreshTouch(self: any)
	self._touchRoot.Visible = self._visible and currentDevice() == "Touch"
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function AimPanel.SetVisible(self: any, visible: boolean)
	if self._destroyed then
		return
	end
	local card: Frame = self._card
	if visible == self._visible then
		return
	end
	self._visible = visible
	if visible then
		card.Visible = true
		card.Position = UDim2.new(0.5, 0, 1, -CARD_BOTTOM + 40)
		Theme.tween(card, Theme.Motion.Slow, { Position = UDim2.new(0.5, 0, 1, -CARD_BOTTOM) }, Enum.EasingStyle.Back)
	else
		card.Visible = false
		self:SetCharging(false)
		self._suggestion.Visible = false
	end
	self._hint.Visible = visible and self._hint.Text ~= ""
	self:_refreshTouch()
end

function AimPanel.IsVisible(self: any): boolean
	return self._visible
end

function AimPanel.SetPower(self: any, power: number)
	if self._destroyed then
		return
	end
	local p = if type(power) == "number" and power == power then math.clamp(power, 0, 1) else 0
	self._power = p
	self._needle.Position = UDim2.new(p, 0, 0.5, 0)
	self._cover.Position = UDim2.new(p, 0, 0, 0)
	self._cover.Size = UDim2.new(1 - p, 0, 1, 0)
	if self._charging then
		self._powerValue.Text = Locale.t("aim.panel.powerValue", { n = math.floor(p * 100 + 0.5) })
		local color = BANDS[1].color
		for _, band in BANDS do
			if p >= band.from then
				color = band.color
			end
		end
		self._powerValue.TextColor3 = color
	end
end

function AimPanel.SetCharging(self: any, charging: boolean)
	if self._destroyed or self._charging == charging then
		return
	end
	self._charging = charging
	if charging then
		self._powerTitle.Text = Locale.t("aim.panel.charging")
		self:SetPower(self._power)
		Base.playSound("ui_click")
	else
		self._powerTitle.Text = Locale.t("aim.panel.power")
		self._powerValue.Text = "—"
		self._powerValue.TextColor3 = Theme.Colors.Primary
		self._cardScale.Scale = 1
		self._cardStroke.Color = Theme.Colors.Ink
		self:SetPower(0)
	end
	local swing = self._swingButton
	if swing then
		swing.SetVariant(if charging then "Warning" else "Success")
	end
end

function AimPanel.SetLoft(self: any, degrees: number)
	if self._destroyed then
		return
	end
	local value = if type(degrees) == "number" and degrees == degrees then math.floor(degrees + 0.5) else 0
	self._loftValue.Text = string.format("%d°", value)
end

function AimPanel.SetShotType(self: any, shotType: string)
	if self._destroyed then
		return
	end
	local key = "aim.shot." .. tostring(shotType)
	self._shotValue.Text = if Locale.has(key) or Locale.has(key, "fr") then Locale.t(key) else tostring(shotType)
	local color = if shotType == "Putt"
		then Theme.Colors.Success
		elseif shotType == "Chip" then Theme.Colors.Accent
		elseif shotType == "Guided" then Theme.Colors.Danger
		else Theme.Colors.Primary
	self._shotValue.TextColor3 = Theme.lighten(color, 0.1)
end

function AimPanel.SetDistance(self: any, studs: number?)
	if self._destroyed then
		return
	end
	if type(studs) == "number" and studs == studs and studs < math.huge then
		self._distanceValue.Text = tostring(math.floor(studs + 0.5))
	else
		self._distanceValue.Text = "?"
	end
end

function AimPanel.SetWind(self: any, wind: Vector3)
	if self._destroyed then
		return
	end
	local value = if typeof(wind) == "Vector3" and wind.Magnitude == wind.Magnitude then Vector3.new(wind.X, 0, wind.Z) else Vector3.zero
	self._wind = value
	local strength = value.Magnitude
	if strength < 0.05 then
		self._windValue.Text = Locale.t("aim.panel.windCalm")
		self._windArrow.Text = "○"
		self._windArrow.Rotation = 0
	else
		self._windValue.Text = Locale.t("aim.panel.wind", { n = math.floor(strength + 0.5) })
		self._windArrow.Text = "▲"
	end
end

function AimPanel.SetPrompt(self: any, text: string?)
	if self._destroyed then
		return
	end
	local prompt: Frame = self._prompt
	if text == nil or text == "" then
		self._promptText = nil
		prompt.Visible = false
		return
	end
	local changed = self._promptText ~= text
	self._promptText = text
	self._promptLabel.Text = text
	if not prompt.Visible then
		prompt.Visible = true
		if not Theme.isReducedMotion() then
			self._promptScale.Scale = 0.6
			Theme.tween(self._promptScale, Theme.Motion.Slow, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	elseif changed then
		self._promptScale.Scale = 1
	end
end

function AimPanel.SetHint(self: any, text: string)
	if self._destroyed then
		return
	end
	local value = if type(text) == "string" then text else ""
	self._hint.Text = value
	self._hint.Visible = self._visible and value ~= ""
end

function AimPanel.SetSweetSpot(self: any, power: number?)
	if self._destroyed then
		return
	end
	if type(power) == "number" and power == power and power > 0.01 and power <= 1 then
		self._sweet.Visible = true
		self._sweet.Position = UDim2.new(power, 0, 0.5, 0)
	else
		self._sweet.Visible = false
	end
end

function AimPanel.SetSuggestion(self: any, text: string?)
	if self._destroyed then
		return
	end
	if text == nil or text == "" then
		self._suggestion.Visible = false
	else
		self._suggestionText.Text = text
		self._suggestion.Visible = self._visible
	end
end

function AimPanel.ShowMessage(self: any, text: string, kind: string?)
	if self._destroyed or type(text) ~= "string" or text == "" then
		return
	end
	self._messageToken += 1
	local token = self._messageToken
	local message: Frame = self._message
	local color = if kind == "warn" then Theme.Colors.Danger elseif kind == "good" then Theme.Colors.Success else Theme.Colors.Secondary
	self._messageStroke.Color = color
	self._messageText.Text = text
	message.BackgroundTransparency = Theme.backgroundTransparency(0.05)
	self._messageText.TextTransparency = 0
	message.Visible = true
	if not Theme.isReducedMotion() then
		message.Position = UDim2.new(0.5, 0, 0.2, -16)
		Theme.tween(message, Theme.Motion.Normal, { Position = UDim2.new(0.5, 0, 0.2, 0) }, Enum.EasingStyle.Back)
	end
	if kind == "warn" then
		Base.playSound("ui_error")
	end
	task.delay(MESSAGE_TIME, function()
		if self._destroyed or token ~= self._messageToken then
			return
		end
		Theme.fade(message, 0.3, { BackgroundTransparency = 1 })
		Theme.fade(self._messageText, 0.3, { TextTransparency = 1 })
		task.delay(0.32, function()
			if not self._destroyed and token == self._messageToken then
				message.Visible = false
			end
		end)
	end)
end

function AimPanel.Destroy(self: any)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._trove:Clean()
end

return AimPanel
