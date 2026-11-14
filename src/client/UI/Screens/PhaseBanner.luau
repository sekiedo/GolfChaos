--!strict
--[[
	PhaseBanner — petite bannière en haut de l'écran pendant l'accueil et la préparation : nom de la phase,
	chronomètre (GameState.PhaseEndsAt), hôte du salon ; en préparation, un bouton rouvre le salon s'il a été
	refermé. Non modale, ne prend jamais le focus manette.

	Show(args) : args = phase ("Lobby" | "Preparing").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trove = require(Shared.Util.Trove)
local Locale = require(Shared.Locale)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Label = require(UI.Components.Label)
local Button = require(UI.Components.Button)
local Util = require(script.Parent.Util)

local PhaseBanner = {}

local REFRESH = 0.25

function PhaseBanner.new(ctx: any): any
	local screen: any = {
		DisplayOrder = Theme.Layers.Banner,
		IgnoreGuiInset = false,
	}

	local showTrove = Trove.new()
	local currentPhase = "Lobby"
	local holder: Frame
	local scaleHost: Frame
	local phaseLabel: Label.LabelApi
	local timerChip: Frame
	local timerLabel: TextLabel
	local hostLabel: Label.LabelApi
	local reopen: Button.ButtonApi

	function screen.Build(_self: any, gui: ScreenGui)
		scaleHost = Instance.new("Frame")
		scaleHost.Name = "Bandeau"
		scaleHost.BackgroundTransparency = 1
		scaleHost.AnchorPoint = Vector2.new(0.5, 0)
		scaleHost.Position = UDim2.new(0.5, 0, 0, 8)
		scaleHost.AutomaticSize = Enum.AutomaticSize.XY
		scaleHost.Size = UDim2.new()
		scaleHost.Parent = gui
		ctx.Manager.AttachScale(scaleHost)

		local row = Instance.new("Frame")
		row.Name = "Ligne"
		row.BackgroundTransparency = 1
		row.AutomaticSize = Enum.AutomaticSize.XY
		row.Size = UDim2.new()
		Base.list(row, Enum.FillDirection.Horizontal, Theme.Spacing.S, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		row.Parent = scaleHost

		-- Pastille principale (ombre + face).
		holder = Instance.new("Frame")
		holder.Name = "Pastille"
		holder.BackgroundTransparency = 1
		holder.AutomaticSize = Enum.AutomaticSize.X
		holder.Size = UDim2.fromOffset(0, 48)
		holder.LayoutOrder = 1
		holder.Parent = row

		local shadow = Instance.new("Frame")
		shadow.Name = "Ombre"
		shadow.BorderSizePixel = 0
		shadow.BackgroundColor3 = Theme.Colors.Ink
		shadow.BackgroundTransparency = 0.3
		shadow.Position = UDim2.fromOffset(0, 4)
		shadow.Size = UDim2.fromScale(1, 1)
		Base.corner(shadow, "Pill")
		shadow.Parent = holder

		local face = Instance.new("Frame")
		face.Name = "Face"
		face.BorderSizePixel = 0
		face.BackgroundColor3 = Theme.Colors.Night
		face.AutomaticSize = Enum.AutomaticSize.X
		face.Size = UDim2.fromOffset(0, 48)
		face.ZIndex = 2
		Base.corner(face, "Pill")
		Base.stroke(face, Theme.Colors.Ink, Theme.StrokeWidth.Thick)
		Base.padding(face, nil, 8, 0)
		Base.list(face, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		face.Parent = holder

		local dot = Instance.new("Frame")
		dot.Name = "Golf"
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = Theme.Colors.Paper
		dot.Size = UDim2.fromOffset(28, 28)
		dot.LayoutOrder = 1
		dot.ZIndex = 2
		Base.corner(dot, "Pill")
		Base.stroke(dot, Theme.Colors.Ink, Theme.StrokeWidth.Thin)
		dot.Parent = face

		phaseLabel = Label.new({
			name = "Phase",
			style = "Heading",
			font = "Display",
			autoSize = "X",
			stroke = true,
			color = Theme.Colors.Primary,
			layoutOrder = 2,
			zIndex = 2,
			parent = face,
		})

		timerChip = Instance.new("Frame")
		timerChip.Name = "Chrono"
		timerChip.BorderSizePixel = 0
		timerChip.BackgroundColor3 = Theme.Colors.Primary
		timerChip.AutomaticSize = Enum.AutomaticSize.X
		timerChip.Size = UDim2.fromOffset(0, 32)
		timerChip.LayoutOrder = 3
		timerChip.ZIndex = 2
		Base.corner(timerChip, "Pill")
		Base.stroke(timerChip, Theme.Colors.Ink, Theme.StrokeWidth.Thin)
		Base.padding(timerChip, nil, 10, 0)
		timerChip.Parent = face

		timerLabel = Base.newText("Temps", "Body", "Mono", Theme.Colors.Ink)
		timerLabel.AutomaticSize = Enum.AutomaticSize.X
		timerLabel.Size = UDim2.fromOffset(0, 32)
		timerLabel.ZIndex = 2
		timerLabel.Parent = timerChip

		hostLabel = Label.new({
			name = "Hote",
			style = "Small",
			font = "Bold",
			autoSize = "X",
			color = Theme.Colors.PaperDim,
			layoutOrder = 4,
			zIndex = 2,
			parent = face,
		})

		reopen = Button.new({
			name = "RouvrirSalon",
			key = "menu.host.reopen",
			icon = "⚑",
			variant = "Secondary",
			size = "Small",
			layoutOrder = 2,
			parent = row,
			onActivated = function()
				ctx.Manager.Show("HostSettings", ctx.GetLobbyState())
			end,
		})
		reopen.Instance.Visible = false
	end

	local function refresh()
		phaseLabel.SetKey(if currentPhase == "Preparing" then "menu.banner.preparing" else "menu.banner.lobby")
		local left = Util.secondsLeft(Util.attr("PhaseEndsAt"))
		timerChip.Visible = left ~= nil
		if left then
			timerLabel.Text = Util.formatClock(left)
			timerChip.BackgroundColor3 = if left <= 10 then Theme.Colors.Warning else Theme.Colors.Primary
		end
		local hostId = Util.attr("HostUserId")
		if type(hostId) == "number" and hostId > 0 then
			local state = ctx.GetLobbyState()
			local fallbackName: string? = nil
			if state and type(state.players) == "table" then
				for _, entry in state.players do
					if type(entry) == "table" and entry.userId == hostId then
						fallbackName = entry.name
					end
				end
			end
			hostLabel.SetText(Locale.t("menu.banner.host", { name = Util.playerName(hostId, fallbackName) }))
			hostLabel.Instance.Visible = true
		else
			hostLabel.Instance.Visible = currentPhase == "Preparing"
			hostLabel.SetKey("menu.banner.noHost")
		end
		reopen.Instance.Visible = currentPhase == "Preparing" and not ctx.Manager.IsVisible("HostSettings")
	end

	function screen.Show(_self: any, args: any, wasVisible: boolean)
		currentPhase = if args == "Preparing" then "Preparing" else "Lobby"
		if not wasVisible then
			showTrove:Clean()
			if not Theme.isReducedMotion() then
				scaleHost.Position = UDim2.new(0.5, 0, 0, -70)
				Theme.tween(scaleHost, Theme.Motion.Slow, { Position = UDim2.new(0.5, 0, 0, 8) }, Enum.EasingStyle.Back)
			else
				scaleHost.Position = UDim2.new(0.5, 0, 0, 8)
			end
			showTrove:Add(task.spawn(function()
				while true do
					refresh()
					task.wait(REFRESH)
				end
			end))
			showTrove:Connect(ctx.Manager.Changed, function(name: any)
				if name == "HostSettings" then
					refresh()
				end
			end)
		end
		refresh()
	end

	function screen.Hide(_self: any): number?
		showTrove:Clean()
		return 0
	end

	function screen.Destroy(_self: any)
		showTrove:Clean()
	end

	return screen
end

return PhaseBanner
