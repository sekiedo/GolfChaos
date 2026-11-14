--!strict
--[[
	Hud/InfoPanel — informations de jeu (haut droite) : vent (flèche relative à la caméra + force),
	distance de sa balle au trou, position dans la course.

	  local info = InfoPanel.new(parent)
	  info.SetWind(Vector3)   info.SetDistance(studs?)   info.SetPosition(rang?, total?, arrivé?)
	  info.Render()           (à chaque image : oriente la flèche du vent selon la caméra)
	  info.Instance   info.Destroy()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared.Locale)
local Gameplay = require(Shared.Config.Gameplay)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Kit = require(script.Parent.Kit)

export type InfoPanel = {
	Instance: Frame,
	SetWind: (wind: Vector3?) -> (),
	SetDistance: (studs: number?) -> (),
	SetPosition: (rank: number?, total: number?, finished: boolean?) -> (),
	Render: () -> (),
	Destroy: () -> (),
}

local InfoPanel = {}

local function chip(parent: Instance, name: string, order: number, titleKey: string): (Frame, TextLabel)
	local frame = Kit.panel(parent, name)
	frame.Size = UDim2.fromOffset(96, 66)
	frame.LayoutOrder = order
	local title = Kit.text(frame, "Titre", "Caption", "Heavy", Theme.Colors.PaperDim, true)
	title.Position = UDim2.fromOffset(0, 5)
	title.Size = UDim2.new(1, 0, 0, 16)
	title.TextXAlignment = Enum.TextXAlignment.Center
	Base.setText(title, nil, titleKey)
	local value = Kit.text(frame, "Valeur", "Heading", "Display", Theme.Colors.Paper, true)
	value.Position = UDim2.fromOffset(6, 24)
	value.Size = UDim2.new(1, -12, 1, -30)
	value.TextXAlignment = Enum.TextXAlignment.Center
	return frame, value
end

function InfoPanel.new(parent: Instance): InfoPanel
	local root = Instance.new("Frame")
	root.Name = "Infos"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.new(1, -12, 0, 12)
	root.Size = UDim2.fromOffset(312, 66)
	Base.list(root, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Top)
	root.Parent = parent

	local windFrame, windValue = chip(root, "Vent", 1, "hud.wind.title")
	windValue.Size = UDim2.new(0.55, -4, 1, -30)
	windValue.Position = UDim2.new(0.45, 0, 0, 24)
	windValue.TextXAlignment = Enum.TextXAlignment.Left
	local arrow = Kit.text(windFrame, "Fleche", "Title", "Display", Theme.Colors.Secondary, true)
	arrow.Position = UDim2.new(0, 4, 0, 22)
	arrow.Size = UDim2.new(0.45, -4, 1, -28)
	arrow.TextXAlignment = Enum.TextXAlignment.Center
	arrow.Text = "▲"

	local _, distanceValue = chip(root, "Distance", 2, "hud.distance.title")
	local positionFrame, positionValue = chip(root, "Place", 3, "hud.position.title")

	local current = { wind = Vector3.zero, rank = 0 }

	local api = {} :: InfoPanel
	api.Instance = root

	function api.SetWind(wind: Vector3?)
		local value = if typeof(wind) == "Vector3" and wind.Magnitude == wind.Magnitude then Vector3.new(wind.X, 0, wind.Z) else Vector3.zero
		current.wind = value
		local strength = value.Magnitude
		if strength < 0.05 then
			windValue.Text = Locale.t("hud.wind.calm")
			arrow.Text = "○"
			arrow.Rotation = 0
			arrow.TextColor3 = Theme.Colors.PaperDim
		else
			windValue.Text = Locale.t("hud.wind.value", { n = math.floor(strength + 0.5) })
			arrow.Text = "▲"
			local strong = strength >= (Gameplay.Wind.Strengths.Strong or 12)
			arrow.TextColor3 = if strong then Theme.Colors.Warning else Theme.Colors.Secondary
		end
	end

	function api.SetDistance(studs: number?)
		if type(studs) == "number" and studs == studs and studs < math.huge then
			distanceValue.Text = Locale.t("hud.distance.value", { n = math.floor(studs + 0.5) })
		else
			distanceValue.Text = Locale.t("hud.distance.unknown")
		end
	end

	function api.SetPosition(rank: number?, total: number?, finished: boolean?)
		if type(rank) ~= "number" or rank <= 0 or type(total) ~= "number" or total <= 0 then
			positionValue.Text = Locale.t("hud.distance.unknown")
			positionValue.TextColor3 = Theme.Colors.Paper
			current.rank = 0
			return
		end
		positionValue.Text = Locale.t("hud.position.value", { rank = Kit.ordinal(rank), total = total })
		positionValue.TextColor3 = if rank == 1 then Theme.Colors.Primary else Theme.Colors.Paper
		if finished then
			positionValue.Text = "✓ " .. positionValue.Text
		end
		if rank ~= current.rank then
			if current.rank ~= 0 and rank < current.rank then
				Kit.bump(positionFrame, 1.15)
			end
			current.rank = rank
		end
	end

	function api.Render()
		local wind = current.wind
		local camera = Workspace.CurrentCamera
		if not camera or wind.Magnitude < 0.05 then
			return
		end
		local look = camera.CFrame.LookVector
		local forward = Vector3.new(look.X, 0, look.Z)
		if forward.Magnitude < 1e-3 then
			return
		end
		forward = forward.Unit
		local right = forward:Cross(Vector3.yAxis)
		arrow.Rotation = math.deg(math.atan2(wind:Dot(right), wind:Dot(forward)))
	end

	function api.Destroy()
		root:Destroy()
	end

	api.SetWind(nil)
	api.SetDistance(nil)
	api.SetPosition(nil, nil, false)
	return api
end

return InfoPanel
