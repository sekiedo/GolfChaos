--!strict
--[[
	Hud/ControlsBar — barre d'aide des commandes (bas de l'écran), texte seul (glyphes et libellés de touches,
	aucune image). Le texte est composé par HUDController selon l'appareil courant.

	  local bar = ControlsBar.new(parent)
	  bar.SetText(texte)   bar.SetVisible(bool)   bar.Instance   bar.Destroy()
]]

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Kit = require(script.Parent.Kit)

export type ControlsBar = {
	Instance: Frame,
	SetText: (text: string) -> (),
	SetVisible: (visible: boolean) -> (),
	Destroy: () -> (),
}

local ControlsBar = {}

function ControlsBar.new(parent: Instance): ControlsBar
	local root = Instance.new("Frame")
	root.Name = "AideCommandes"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -8)
	root.Size = UDim2.new(0.8, 0, 0, 30)
	root.BackgroundColor3 = Theme.Colors.Backdrop
	root.BackgroundTransparency = Theme.backgroundTransparency(0.45)
	root.BorderSizePixel = 0
	Base.corner(root, "Pill")
	Base.padding(root, 0, 14, 2)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(980, 30)
	constraint.Parent = root
	root.Parent = parent

	local label = Kit.text(root, "Texte", "Small", "Bold", Theme.Colors.Paper, true)
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center

	local api = {} :: ControlsBar
	api.Instance = root

	function api.SetText(text: string)
		label.Text = text
		root.Visible = text ~= "" and root:GetAttribute("Masque") ~= true
	end

	function api.SetVisible(visible: boolean)
		root:SetAttribute("Masque", not visible)
		root.Visible = visible and label.Text ~= ""
	end

	function api.Destroy()
		root:Destroy()
	end

	return api
end

return ControlsBar
