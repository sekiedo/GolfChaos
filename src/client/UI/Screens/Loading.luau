--!strict
--[[
	Loading — voile de chargement entre deux trous : fond dégradé, titre « Chargement du trou n/N », balle de
	golf qui rebondit (immobile si effets réduits), astuces qui défilent toutes les quelques secondes.
	Entrée / sortie en fondu (aucun flash). Non modal.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trove = require(Shared.Util.Trove)
local Locale = require(Shared.Locale)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Label = require(UI.Components.Label)
local Panel = require(UI.Components.Panel)
local Util = require(script.Parent.Util)

local Loading = {}

local TIP_COUNT = 12
local TIP_PERIOD = 5.5
local FADE_IN = 0.25
local FADE_OUT = 0.35
local BOUNCE_PERIOD = 0.7

function Loading.new(ctx: any): any
	local screen: any = { DisplayOrder = Theme.Layers.Loading }

	local showTrove = Trove.new()
	local group: CanvasGroup
	local title: Label.LabelApi
	local tipText: Label.LabelApi
	local ball: Frame
	local ballShadow: Frame
	local dots: TextLabel
	local tipIndex = math.random(1, TIP_COUNT)

	function screen.Build(_self: any, gui: ScreenGui)
		group = Instance.new("CanvasGroup")
		group.Name = "Voile"
		group.BorderSizePixel = 0
		group.BackgroundColor3 = Theme.Colors.Night
		group.Size = UDim2.fromScale(1, 1)
		group.GroupTransparency = 1
		group.Parent = gui

		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(Theme.Colors.NightRaised, Theme.Colors.Backdrop)
		gradient.Parent = group

		-- Motif de pastilles discrètes (relief cartoon du fond).
		for index = 1, 14 do
			local blob = Instance.new("Frame")
			blob.Name = "Pastille" .. index
			blob.BorderSizePixel = 0
			blob.BackgroundColor3 = Theme.Colors.White
			blob.BackgroundTransparency = 0.94
			local size = 60 + (index * 37) % 120
			blob.Size = UDim2.fromOffset(size, size)
			blob.AnchorPoint = Vector2.new(0.5, 0.5)
			blob.Position = UDim2.fromScale(((index * 0.173) % 1), ((index * 0.317) % 1))
			Base.corner(blob, "Pill")
			blob.Parent = group
		end

		local center = Instance.new("Frame")
		center.Name = "Centre"
		center.BackgroundTransparency = 1
		center.AnchorPoint = Vector2.new(0.5, 0.5)
		center.Position = UDim2.fromScale(0.5, 0.45)
		center.Size = UDim2.new(0.9, 0, 0, 260)
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize = Vector2.new(720, 260)
		limit.Parent = center
		center.Parent = group
		ctx.Manager.AttachScale(center)

		-- Balle qui rebondit et son ombre.
		local stage = Instance.new("Frame")
		stage.Name = "Scene"
		stage.BackgroundTransparency = 1
		stage.AnchorPoint = Vector2.new(0.5, 0)
		stage.Position = UDim2.fromScale(0.5, 0)
		stage.Size = UDim2.fromOffset(120, 120)
		stage.Parent = center

		ballShadow = Instance.new("Frame")
		ballShadow.Name = "OmbreBalle"
		ballShadow.BorderSizePixel = 0
		ballShadow.BackgroundColor3 = Theme.Colors.Backdrop
		ballShadow.BackgroundTransparency = 0.5
		ballShadow.AnchorPoint = Vector2.new(0.5, 0.5)
		ballShadow.Position = UDim2.new(0.5, 0, 1, -8)
		ballShadow.Size = UDim2.fromOffset(54, 12)
		Base.corner(ballShadow, "Pill")
		ballShadow.Parent = stage

		ball = Instance.new("Frame")
		ball.Name = "Balle"
		ball.BorderSizePixel = 0
		ball.BackgroundColor3 = Theme.Colors.Paper
		ball.AnchorPoint = Vector2.new(0.5, 1)
		ball.Position = UDim2.new(0.5, 0, 1, -12)
		ball.Size = UDim2.fromOffset(56, 56)
		Base.corner(ball, "Pill")
		Base.stroke(ball, Theme.Colors.Ink, Theme.StrokeWidth.Thick)
		ball.Parent = stage
		-- Alvéoles de la balle.
		for index, offset in { Vector2.new(0.35, 0.35), Vector2.new(0.62, 0.3), Vector2.new(0.5, 0.58), Vector2.new(0.3, 0.66), Vector2.new(0.7, 0.64) } do
			local dimple = Instance.new("Frame")
			dimple.Name = "Alveole" .. index
			dimple.BorderSizePixel = 0
			dimple.BackgroundColor3 = Theme.Colors.PaperDim
			dimple.AnchorPoint = Vector2.new(0.5, 0.5)
			dimple.Position = UDim2.fromScale(offset.X, offset.Y)
			dimple.Size = UDim2.fromOffset(8, 8)
			Base.corner(dimple, "Pill")
			dimple.Parent = ball
		end

		local titleRow = Instance.new("Frame")
		titleRow.Name = "LigneTitre"
		titleRow.BackgroundTransparency = 1
		titleRow.Position = UDim2.fromOffset(0, 128)
		titleRow.Size = UDim2.new(1, 0, 0, 56)
		titleRow.Parent = center

		title = Label.new({
			name = "Titre",
			style = "Display",
			font = "Display",
			alignX = Enum.TextXAlignment.Center,
			stroke = 4,
			color = Theme.Colors.Primary,
			size = UDim2.fromScale(1, 1),
			parent = titleRow,
		})

		dots = Base.newText("Points", "Title", "Display", Theme.Colors.Paper)
		dots.Size = UDim2.new(1, 0, 0, 32)
		dots.Position = UDim2.fromOffset(0, 186)
		dots.TextXAlignment = Enum.TextXAlignment.Center
		dots.Text = "• • •"
		dots.Parent = center

		-- Encart des astuces en bas de l'écran.
		local tipHolder = Instance.new("Frame")
		tipHolder.Name = "Astuces"
		tipHolder.BackgroundTransparency = 1
		tipHolder.AnchorPoint = Vector2.new(0.5, 1)
		tipHolder.Position = UDim2.new(0.5, 0, 1, -28)
		tipHolder.Size = UDim2.new(0.9, 0, 0, 120)
		local tipLimit = Instance.new("UISizeConstraint")
		tipLimit.MaxSize = Vector2.new(760, 120)
		tipLimit.Parent = tipHolder
		tipHolder.Parent = group
		ctx.Manager.AttachScale(tipHolder)

		local tipPanel = Panel.new({
			name = "PanneauAstuce",
			titleKey = "menu.loading.tip",
			titleVariant = "Secondary",
			size = UDim2.fromScale(1, 1),
			padding = Theme.Spacing.M,
			parent = tipHolder,
		})
		tipText = Label.new({
			name = "Astuce",
			style = "Body",
			font = "Bold",
			alignX = Enum.TextXAlignment.Center,
			wrap = true,
			size = UDim2.fromScale(1, 1),
			parent = tipPanel.Content,
		})
	end

	local function setTitle()
		local index = Util.attr("HoleIndex")
		local count = Util.attr("HoleCount")
		if type(index) == "number" and type(count) == "number" and index > 0 and count > 0 then
			title.SetText(Locale.t("match.loading.hole", { index = index, count = count }))
		else
			title.SetKey("menu.loading.title")
		end
	end

	local function showTip(animate: boolean)
		tipIndex = (tipIndex % TIP_COUNT) + 1
		tipText.SetKey("menu.tip." .. tipIndex)
		if animate then
			tipText.Instance.TextTransparency = 1
			Theme.fade(tipText.Instance, 0.3, { TextTransparency = 0 })
		end
	end

	function screen.Show(_self: any, _args: any, wasVisible: boolean)
		setTitle()
		if wasVisible then
			return
		end
		showTrove:Clean()
		Theme.fade(group, FADE_IN, { GroupTransparency = 0 })
		showTip(false)

		local folder = Util.gameState()
		if folder then
			showTrove:Connect(folder:GetAttributeChangedSignal("HoleIndex"), setTitle)
			showTrove:Connect(folder:GetAttributeChangedSignal("HoleCount"), setTitle)
		end

		-- Astuces et points animés (texte seulement : pas de clignotement brutal).
		showTrove:Add(task.spawn(function()
			local elapsed = 0
			local step = 0
			while true do
				task.wait(0.4)
				elapsed += 0.4
				step = (step % 3) + 1
				dots.Text = string.rep("• ", step) .. string.rep("  ", 3 - step)
				if elapsed >= TIP_PERIOD then
					elapsed = 0
					showTip(true)
				end
			end
		end))

		-- Rebond de la balle (désactivé si effets réduits).
		if not Theme.isReducedMotion() then
			showTrove:Add(task.spawn(function()
				while true do
					Theme.tween(ball, BOUNCE_PERIOD / 2, { Position = UDim2.new(0.5, 0, 1, -64) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
					Theme.tween(ballShadow, BOUNCE_PERIOD / 2, { Size = UDim2.fromOffset(30, 8) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
					task.wait(BOUNCE_PERIOD / 2)
					Theme.tween(ball, BOUNCE_PERIOD / 2, { Position = UDim2.new(0.5, 0, 1, -12) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					Theme.tween(ballShadow, BOUNCE_PERIOD / 2, { Size = UDim2.fromOffset(54, 12) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					task.wait(BOUNCE_PERIOD / 2)
				end
			end))
		end
	end

	function screen.Hide(_self: any): number?
		showTrove:Clean()
		Theme.fade(group, FADE_OUT, { GroupTransparency = 1 })
		return FADE_OUT
	end

	function screen.Destroy(_self: any)
		showTrove:Clean()
	end

	return screen
end

return Loading
