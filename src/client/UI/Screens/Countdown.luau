--!strict
--[[
	Countdown — compte à rebours 3-2-1-PARTEZ ! au centre de l'écran : chiffre géant dans une pastille,
	« pop » élastique à chaque seconde (coupé si effets réduits), bip à chaque chiffre, sifflet au départ.
	Sûr pour le mode sans flash : aucun voile plein écran, aucun clignotement, seulement des changements de
	couleur une fois par seconde.

	Synchronisé sur GameState.PhaseEndsAt (sinon Config.Match.Durations.Countdown depuis l'affichage).
	Quand la phase passe à Playing, l'écran affiche « Partez ! » un court instant avant de disparaître.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trove = require(Shared.Util.Trove)
local MatchConfig = require(Shared.Config.Match)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Label = require(UI.Components.Label)
local Util = require(script.Parent.Util)

local Countdown = {}

local POLL = 0.05
local GO_HOLD = 0.85
local POP_TIME = 0.35

local STEP_COLORS: { [number]: Color3 } = {
	[3] = Theme.Colors.Danger,
	[2] = Theme.Colors.Warning,
	[1] = Theme.Colors.Primary,
	[0] = Theme.Colors.Success,
}

function Countdown.new(ctx: any): any
	local screen: any = { DisplayOrder = Theme.Layers.Phase + 2 }

	local showTrove = Trove.new()
	local holder: Frame
	local disc: Frame
	local discLip: Frame
	local popScale: UIScale
	local number: Label.LabelApi
	local readyLabel: Label.LabelApi
	local shown = -1

	function screen.Build(_self: any, gui: ScreenGui)
		holder = Instance.new("Frame")
		holder.Name = "Centre"
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.42)
		holder.Size = UDim2.fromOffset(420, 300)
		holder.Parent = gui
		ctx.Manager.AttachScale(holder)

		popScale = Instance.new("UIScale")
		popScale.Name = "Pop"
		-- UIScale imbriqué : le cadre intérieur porte l'animation, le support porte l'échelle du thème.
		local inner = Instance.new("Frame")
		inner.Name = "Interieur"
		inner.BackgroundTransparency = 1
		inner.Size = UDim2.fromScale(1, 1)
		inner.Parent = holder
		popScale.Parent = inner

		discLip = Instance.new("Frame")
		discLip.Name = "Levre"
		discLip.BorderSizePixel = 0
		discLip.AnchorPoint = Vector2.new(0.5, 0.5)
		discLip.Position = UDim2.new(0.5, 0, 0.5, 10)
		discLip.Size = UDim2.fromOffset(200, 200)
		Base.corner(discLip, "Pill")
		Base.stroke(discLip, Theme.Colors.Ink, 6)
		discLip.Parent = inner

		disc = Instance.new("Frame")
		disc.Name = "Pastille"
		disc.BorderSizePixel = 0
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		disc.Position = UDim2.fromScale(0.5, 0.5)
		disc.Size = UDim2.fromOffset(200, 200)
		disc.ZIndex = 2
		Base.corner(disc, "Pill")
		Base.stroke(disc, Theme.Colors.Ink, 6)
		disc.Parent = inner

		local shine = Instance.new("Frame")
		shine.Name = "Reflet"
		shine.BorderSizePixel = 0
		shine.BackgroundColor3 = Theme.Colors.White
		shine.BackgroundTransparency = 0.75
		shine.AnchorPoint = Vector2.new(0.5, 0)
		shine.Position = UDim2.new(0.5, 0, 0, 14)
		shine.Size = UDim2.new(0.6, 0, 0.22, 0)
		shine.ZIndex = 2
		Base.corner(shine, "Pill")
		shine.Parent = disc

		number = Label.new({
			name = "Chiffre",
			style = "Hero",
			font = "Display",
			alignX = Enum.TextXAlignment.Center,
			stroke = 6,
			strokeColor = Theme.Colors.Ink,
			color = Theme.Colors.Paper,
			wrap = false,
			size = UDim2.new(1, 120, 1, 0),
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
			zIndex = 3,
			parent = inner,
		})

		readyLabel = Label.new({
			name = "Pret",
			key = "match.countdown.ready",
			style = "Title",
			font = "Display",
			alignX = Enum.TextXAlignment.Center,
			stroke = 4,
			color = Theme.Colors.Paper,
			size = UDim2.new(1, 0, 0, 44),
			position = UDim2.new(0.5, 0, 0, -6),
			anchorPoint = Vector2.new(0.5, 1),
			zIndex = 3,
			parent = holder,
		})
	end

	local function display(step: number)
		if step == shown then
			return
		end
		shown = step
		local color = STEP_COLORS[step] or Theme.Colors.Primary
		disc.BackgroundColor3 = color
		discLip.BackgroundColor3 = Theme.darken(color, 0.35)
		if step <= 0 then
			number.SetKey("match.countdown.go")
			readyLabel.Instance.Visible = false
			disc.Size = UDim2.fromOffset(380, 150)
			discLip.Size = UDim2.fromOffset(380, 150)
			Base.playSound("countdown_go", 1)
		else
			number.SetText(tostring(step))
			readyLabel.Instance.Visible = true
			disc.Size = UDim2.fromOffset(200, 200)
			discLip.Size = UDim2.fromOffset(200, 200)
			Base.playSound("countdown_beep", 1)
		end
		number.SetColor(Theme.Colors.Paper)
		if Theme.isReducedMotion() then
			popScale.Scale = 1
		else
			popScale.Scale = 1.45
			Theme.tween(popScale, POP_TIME, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
	end

	function screen.Show(_self: any, _args: any, wasVisible: boolean)
		if wasVisible then
			return
		end
		showTrove:Clean()
		shown = -1
		holder.Visible = true
		local fallbackEnd = Util.serverNow() + (MatchConfig.Durations.Countdown or 3)
		showTrove:Add(task.spawn(function()
			while true do
				local left = Util.secondsLeft(Util.attr("PhaseEndsAt"))
				if left == nil then
					left = math.max(0, fallbackEnd - Util.serverNow())
				end
				local step = math.clamp(math.ceil(left :: number), 0, 3)
				if step >= 1 then
					display(step)
				end
				task.wait(POLL)
			end
		end))
	end

	function screen.Hide(_self: any): number?
		showTrove:Clean()
		if Util.attr("Phase") == "Playing" then
			display(0)
			showTrove:Add(task.delay(GO_HOLD - 0.2, function()
				Theme.tween(popScale, 0.2, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end))
			return GO_HOLD
		end
		return 0
	end

	function screen.Destroy(_self: any)
		showTrove:Clean()
	end

	return screen
end

return Countdown
