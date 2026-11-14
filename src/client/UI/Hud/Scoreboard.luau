--!strict
--[[
	Hud/Scoreboard — tableau des scores compact (droite) : rang, repère d'équipe (glyphe + couleur), nom,
	coups, coche « terminé ». Le joueur local est mis en avant (cadre + « (toi) »).

	  local board = Scoreboard.new(parent)
	  board.SetRows({ ScoreRow })     déjà triées (HUDController : arrivés d'abord, puis distance au trou)
	  board.Instance   board.Destroy()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared.Locale)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Kit = require(script.Parent.Kit)

export type ScoreRow = {
	userId: number,
	name: string,
	team: string?, -- "Red" | "Blue" | nil (mode Équipes seulement)
	strokes: number,
	finished: boolean,
	isLocal: boolean,
}

export type Scoreboard = {
	Instance: Frame,
	SetRows: (rows: { ScoreRow }) -> (),
	Destroy: () -> (),
}

type RowUi = {
	frame: Frame,
	stroke: UIStroke,
	rank: TextLabel,
	marker: TextLabel,
	name: TextLabel,
	strokes: TextLabel,
	status: TextLabel,
}

local MAX_ROWS = 8
local ROW_HEIGHT = 26

local Scoreboard = {}

local function buildRow(parent: Instance, index: number): RowUi
	local frame = Instance.new("Frame")
	frame.Name = "Ligne" .. index
	frame.BackgroundColor3 = Theme.Colors.NightRaised
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	frame.LayoutOrder = index
	frame.Visible = false
	Base.corner(frame, "Small")
	local stroke = Base.stroke(frame, Theme.Colors.Primary, 2)
	stroke.Enabled = false

	local rank = Kit.text(frame, "Rang", "Small", "Display", Theme.Colors.PaperDim, true)
	rank.Position = UDim2.fromOffset(4, 0)
	rank.Size = UDim2.new(0, 26, 1, 0)
	rank.TextXAlignment = Enum.TextXAlignment.Center

	local marker = Kit.text(frame, "Equipe", "Small", "Display", Theme.Colors.Paper, true)
	marker.Position = UDim2.fromOffset(30, 0)
	marker.Size = UDim2.new(0, 18, 1, 0)
	marker.TextXAlignment = Enum.TextXAlignment.Center

	local name = Kit.text(frame, "Nom", "Small", "Bold", Theme.Colors.Paper, true)
	name.Position = UDim2.fromOffset(50, 0)
	name.Size = UDim2.new(1, -50 - 64, 1, 0)
	name.TextTruncate = Enum.TextTruncate.AtEnd

	local strokes = Kit.text(frame, "Coups", "Small", "Display", Theme.Colors.Paper, true)
	strokes.AnchorPoint = Vector2.new(1, 0)
	strokes.Position = UDim2.new(1, -30, 0, 0)
	strokes.Size = UDim2.new(0, 30, 1, 0)
	strokes.TextXAlignment = Enum.TextXAlignment.Right

	local status = Kit.text(frame, "Etat", "Small", "Display", Theme.Colors.Success, true)
	status.AnchorPoint = Vector2.new(1, 0)
	status.Position = UDim2.new(1, -4, 0, 0)
	status.Size = UDim2.new(0, 22, 1, 0)
	status.TextXAlignment = Enum.TextXAlignment.Center

	frame.Parent = parent
	return { frame = frame, stroke = stroke, rank = rank, marker = marker, name = name, strokes = strokes, status = status }
end

function Scoreboard.new(parent: Instance): Scoreboard
	local root = Kit.panel(parent, "Scores")
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.new(1, -12, 0, 88)
	root.Size = UDim2.fromOffset(250, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	Base.padding(root, 8, 8, 8)
	Base.list(root, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center)

	local title = Kit.text(root, "Titre", "Caption", "Heavy", Theme.Colors.PaperDim, true)
	title.Size = UDim2.new(1, 0, 0, 16)
	title.LayoutOrder = 0
	Base.setText(title, nil, "hud.scoreboard.title")

	local rows: { RowUi } = {}
	for index = 1, MAX_ROWS do
		rows[index] = buildRow(root, index)
	end
	local more = Kit.text(root, "Plus", "Caption", "Bold", Theme.Colors.PaperDim, true)
	more.Size = UDim2.new(1, 0, 0, 16)
	more.LayoutOrder = MAX_ROWS + 1
	more.TextXAlignment = Enum.TextXAlignment.Center
	more.Visible = false

	local api = {} :: Scoreboard
	api.Instance = root

	function api.SetRows(list: { ScoreRow })
		local count = #list
		if count == 0 then
			more.Visible = true
			more.Text = Locale.t("hud.scoreboard.empty")
		else
			more.Visible = count > MAX_ROWS
			more.Text = Locale.t("hud.scoreboard.more", { n = count - MAX_ROWS })
		end
		for index, ui in rows do
			local row = list[index]
			if not row then
				ui.frame.Visible = false
				continue
			end
			ui.frame.Visible = true
			ui.rank.Text = tostring(index)
			local style = Theme.team(row.team)
			if style then
				ui.marker.Text = style.glyph
				ui.marker.TextColor3 = style.color
			else
				ui.marker.Text = "•"
				ui.marker.TextColor3 = Theme.Colors.PaperDim
			end
			ui.name.Text = if row.isLocal then Locale.t("hud.scoreboard.you", { name = row.name }) else row.name
			ui.name.TextColor3 = if row.isLocal then Theme.Colors.Primary else Theme.Colors.Paper
			ui.stroke.Enabled = row.isLocal
			ui.strokes.Text = Locale.t("hud.scoreboard.strokes", { n = row.strokes })
			ui.status.Text = if row.finished then Locale.t("hud.scoreboard.done") else Locale.t("hud.scoreboard.playing")
			ui.status.TextColor3 = if row.finished then Theme.Colors.Success else Theme.Colors.PaperDim
			ui.frame.BackgroundTransparency = if row.finished then 0.15 else 0.4
		end
	end

	function api.Destroy()
		root:Destroy()
	end

	api.SetRows({})
	return api
end

return Scoreboard
