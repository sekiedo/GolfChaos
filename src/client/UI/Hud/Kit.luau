--!strict
--[[
	Hud/Kit — petites briques partagées par les widgets du HUD (aucun effet de bord au require).

	  Kit.panel(parent, nom, couleur?, transparence?) -> Frame      carte cartoon (coins, contour encre)
	  Kit.text(parent, nom, taille, police?, couleur?, ajuste?) -> TextLabel
	        texte du thème avec contour ; ajuste = TextScaled borné (lisible sur téléphone)
	  Kit.pill(parent, nom, couleur) -> (Frame, TextLabel)          pastille à largeur automatique
	  Kit.formatTime(secondes) -> "m:ss"
	  Kit.ordinal(n) -> "1er" / "2e"...  (Locale hud.ordinal.*)
	  Kit.bump(objet, échelle?)                                      petit rebond (coupé si effets réduits)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared.Locale)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)

local Kit = {}

function Kit.panel(parent: Instance, name: string, color: Color3?, transparency: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color or Theme.Colors.Night
	frame.BackgroundTransparency = Theme.backgroundTransparency(transparency or 0.1)
	frame.BorderSizePixel = 0
	Base.corner(frame, "Large")
	Base.stroke(frame, Theme.Colors.Ink, Theme.StrokeWidth.Normal)
	frame.Parent = parent
	return frame
end

function Kit.text(parent: Instance, name: string, size: string, font: string?, color: Color3?, scaled: boolean?): TextLabel
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

function Kit.pill(parent: Instance, name: string, color: Color3): (Frame, TextLabel)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromOffset(0, 26)
	frame.AutomaticSize = Enum.AutomaticSize.X
	Base.corner(frame, "Pill")
	Base.stroke(frame, Theme.Colors.Ink, Theme.StrokeWidth.Thin)
	Base.padding(frame, 0, 10, 0)
	local label = Base.newText("Texte", "Small", "Heavy", Theme.textOn(color))
	label.Size = UDim2.new(0, 0, 1, 0)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Parent = frame
	frame.Parent = parent
	return frame, label
end

function Kit.formatTime(seconds: number?): string
	if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 or seconds == math.huge then
		return Locale.t("hud.timer.none")
	end
	local total = math.ceil(seconds)
	return string.format("%d:%02d", total // 60, total % 60)
end

function Kit.ordinal(n: number): string
	local key = "hud.ordinal." .. tostring(n)
	if Locale.has(key) then
		return Locale.t(key)
	end
	return Locale.t("hud.ordinal.n", { n = n })
end

function Kit.bump(object: GuiObject, amount: number?)
	if Theme.isReducedMotion() then
		return
	end
	local scale = object:FindFirstChild("Rebond")
	if not scale then
		local created = Instance.new("UIScale")
		created.Name = "Rebond"
		created.Parent = object
		scale = created
	end
	local uiScale = scale :: UIScale
	uiScale.Scale = amount or 1.25
	Theme.tween(uiScale, Theme.Motion.Slow, { Scale = 1 }, Enum.EasingStyle.Back)
end

return Kit
