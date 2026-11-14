--[[
	StarterGui/AimGui/PowerMeter  (ModuleScript, enfant du ScreenGui "AimGui")
	--------------------------------------------------------------------------
	Jauge de puissance oscillante, angle de frappe, aide contextuelle, boutons tactiles et toasts.
	Toute l'interface est construite par code : le ScreenGui "AimGui" peut rester vide dans Studio.
	Utilisé par AimController :   local ui = PowerMeter.new(screenGui)

	  ui:SetVisible(bool)   ui:SetPower(0..1)   ui:SetCharging(bool)   ui:SetLoft(deg)
	  ui:SetPrompt(text|nil)   ui:ShowToast(text, kind)
	  ui.SwingActivated / ui.CancelActivated  (BindableEvent, boutons tactiles)
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local PowerMeter = {}
PowerMeter.__index = PowerMeter

local DARK = Color3.fromRGB(18, 20, 28)
local WHITE = Color3.fromRGB(255, 255, 255)
local FONT = Enum.Font.GothamBold

local TOAST_COLORS = {
	hit = Color3.fromRGB(60, 170, 90),
	warn = Color3.fromRGB(200, 90, 60),
	info = Color3.fromRGB(60, 110, 200),
}

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function newLabel(parent, name, position, size, text, textSize)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = FONT
	label.Text = text
	label.TextSize = textSize
	label.TextColor3 = WHITE
	label.TextStrokeTransparency = 0.5
	label.TextWrapped = true
	label.Parent = parent
	return label
end

local function newButton(parent, name, position, size, text, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.15
	button.Font = FONT
	button.Text = text
	button.TextSize = 16
	button.TextColor3 = WHITE
	button.AutoButtonColor = true
	button.Visible = false
	button.Parent = parent
	addCorner(button, 60)
	return button
end

function PowerMeter.new(screenGui)
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 10
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local self = setmetatable({}, PowerMeter)
	self.SwingActivated = Instance.new("BindableEvent")
	self.CancelActivated = Instance.new("BindableEvent")
	self._visible = false
	self._charging = false
	self._toastToken = 0
	self._promptText = nil
	self._isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	-- Panneau principal ------------------------------------------------------
	local root = Instance.new("Frame")
	root.Name = "PowerMeter"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -36)
	root.Size = UDim2.fromOffset(460, 118)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = screenGui

	self._title = newLabel(root, "Title", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 22), "PUISSANCE  0%", 16)

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.new(0, 0, 0, 26)
	bar.Size = UDim2.new(1, 0, 0, 28)
	bar.BackgroundColor3 = DARK
	bar.BackgroundTransparency = 0.1
	bar.ClipsDescendants = true
	bar.Parent = root
	addCorner(bar, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Color = WHITE
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = bar

	-- Dégradé vert -> jaune -> rouge sur toute la largeur ; un cache sombre se rétracte de droite à gauche.
	local gradientFrame = Instance.new("Frame")
	gradientFrame.Name = "Gradient"
	gradientFrame.Size = UDim2.new(1, 0, 1, 0)
	gradientFrame.BackgroundColor3 = WHITE
	gradientFrame.BorderSizePixel = 0
	gradientFrame.Parent = bar
	addCorner(gradientFrame, 14)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 220, 90)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(250, 220, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 60, 50)),
	})
	gradient.Parent = gradientFrame

	local cover = Instance.new("Frame")
	cover.Name = "Cover"
	cover.AnchorPoint = Vector2.new(1, 0)
	cover.Position = UDim2.new(1, 0, 0, 0)
	cover.Size = UDim2.new(1, 0, 1, 0)
	cover.BackgroundColor3 = DARK
	cover.BorderSizePixel = 0
	cover.Parent = bar
	addCorner(cover, 14)
	self._cover = cover

	self._loft = newLabel(root, "Loft", UDim2.new(0, 0, 0, 58), UDim2.new(1, 0, 0, 20), "", 15)
	self._hint = newLabel(root, "Hint", UDim2.new(0, 0, 0, 80), UDim2.new(1, 0, 0, 36), "", 13)
	self._hint.TextTransparency = 0.15
	self._root = root

	-- Boutons tactiles ---------------------------------------------------------
	self._swingButton = newButton(screenGui, "SwingButton", UDim2.new(1, -30, 1, -150), UDim2.fromOffset(120, 120), "LANCER", Color3.fromRGB(40, 150, 80))
	self._swingButton.TextSize = 20
	self._swingButton.Activated:Connect(function()
		self.SwingActivated:Fire()
	end)
	self._cancelButton = newButton(screenGui, "CancelButton", UDim2.new(1, -40, 1, -285), UDim2.fromOffset(90, 90), "ANNULER", Color3.fromRGB(150, 60, 50))
	self._cancelButton.Activated:Connect(function()
		self.CancelActivated:Fire()
	end)

	-- Invite ("E : viser") -----------------------------------------------------
	local prompt = newLabel(screenGui, "Prompt", UDim2.new(0.5, -160, 1, -170), UDim2.fromOffset(320, 36), "", 20)
	prompt.Visible = false
	self._prompt = prompt

	-- Toast ---------------------------------------------------------------------
	local toast = newLabel(screenGui, "Toast", UDim2.new(0.5, -230, 0, 80), UDim2.fromOffset(460, 44), "", 20)
	toast.BackgroundColor3 = DARK
	toast.BackgroundTransparency = 1
	toast.TextTransparency = 1
	toast.TextStrokeTransparency = 1
	addCorner(toast, 12)
	self._toast = toast

	self:SetLoft(28)
	self:SetCharging(false)
	return self
end

function PowerMeter:SetVisible(visible)
	self._visible = visible
	self._root.Visible = visible
	local showTouch = visible and UserInputService.TouchEnabled
	self._swingButton.Visible = showTouch
	self._cancelButton.Visible = showTouch
end

function PowerMeter:SetPower(power)
	power = math.clamp(power, 0, 1)
	self._cover.Size = UDim2.new(1 - power, 0, 1, 0)
	self._title.Text = string.format("PUISSANCE  %d%%", math.floor(power * 100 + 0.5))
end

function PowerMeter:SetCharging(charging)
	self._charging = charging
	if charging then
		self._hint.Text = if self._isTouch then "Appuie sur LANCER au bon moment !" else "Re-clique (ou Espace) au bon moment !  •  Q : revenir à la visée"
		self._swingButton.Text = "FRAPPER !"
		self._title.TextColor3 = Color3.fromRGB(255, 230, 120)
	else
		self._hint.Text = if self._isTouch
			then "Glisse pour orienter  •  Appuie sur LANCER pour démarrer la jauge"
			else "Clic droit + glisser : orienter  •  Molette / R-F : angle  •  Espace ou clic : lancer la jauge  •  Q : annuler"
		self._swingButton.Text = "LANCER"
		self._title.TextColor3 = WHITE
		self:SetPower(0)
	end
end

function PowerMeter:SetLoft(degrees)
	self._loft.Text = string.format("Angle de frappe : %d°", math.floor(degrees + 0.5))
end

function PowerMeter:SetPrompt(text)
	if self._promptText == text then
		return
	end
	self._promptText = text
	self._prompt.Visible = text ~= nil
	if text then
		self._prompt.Text = text
	end
end

function PowerMeter:ShowToast(text, kind)
	local toast = self._toast
	self._toastToken += 1
	local token = self._toastToken

	toast.Text = text
	toast.BackgroundColor3 = TOAST_COLORS[kind] or DARK
	TweenService:Create(toast, TweenInfo.new(0.15), { BackgroundTransparency = 0.2, TextTransparency = 0, TextStrokeTransparency = 0.5 }):Play()

	task.delay(2.6, function()
		if self._toastToken == token then
			TweenService:Create(toast, TweenInfo.new(0.35), { BackgroundTransparency = 1, TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

return PowerMeter
