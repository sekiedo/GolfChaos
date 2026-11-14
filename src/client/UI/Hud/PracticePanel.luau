--!strict
--[[
	Hud/PracticePanel — panneau fin d'entraînement affiché à l'accueil (attribut joueur Practice) :
	titre, consigne et nombre de coups d'essai.

	  local practice = PracticePanel.new(parent)
	  practice.SetStrokes(n)   practice.SetVisible(bool)   practice.Instance   practice.Destroy()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared.Locale)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Kit = require(script.Parent.Kit)

export type PracticePanel = {
	Instance: Frame,
	SetStrokes: (strokes: number?) -> (),
	SetVisible: (visible: boolean) -> (),
	Destroy: () -> (),
}

local PracticePanel = {}

function PracticePanel.new(parent: Instance): PracticePanel
	local root = Kit.panel(parent, "Entrainement", Theme.Colors.Night, 0.15)
	root.Position = UDim2.fromOffset(12, 12)
	root.Size = UDim2.fromOffset(280, 72)
	root.Visible = false
	Base.padding(root, 8, 12, 6)

	local badge, badgeText = Kit.pill(root, "Badge", Theme.Colors.Success)
	badge.Position = UDim2.fromOffset(0, 0)
	Base.setText(badgeText, nil, "hud.practice.title")

	local strokes = Kit.text(root, "Coups", "Small", "Heavy", Theme.Colors.Primary, true)
	strokes.AnchorPoint = Vector2.new(1, 0)
	strokes.Position = UDim2.new(1, 0, 0, 2)
	strokes.Size = UDim2.new(0.5, 0, 0, 22)
	strokes.TextXAlignment = Enum.TextXAlignment.Right

	local body = Kit.text(root, "Consigne", "Small", "Bold", Theme.Colors.Paper, true)
	body.Position = UDim2.fromOffset(0, 32)
	body.Size = UDim2.new(1, 0, 0, 22)
	Base.setText(body, nil, "hud.practice.body")

	local api = {} :: PracticePanel
	api.Instance = root

	function api.SetStrokes(value: number?)
		local n = if type(value) == "number" then math.max(0, math.floor(value)) else 0
		strokes.Text = Locale.t("hud.practice.strokes", { n = n })
	end

	function api.SetVisible(visible: boolean)
		if visible and not root.Visible then
			Kit.bump(root, 1.08)
		end
		root.Visible = visible
	end

	function api.Destroy()
		root:Destroy()
	end

	api.SetStrokes(0)
	return api
end

return PracticePanel
