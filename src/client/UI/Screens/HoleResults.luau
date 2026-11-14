--!strict
--[[
	HoleResults — tableau des résultats du trou (message Match.HoleResults) :
	  { holeId, holeName, par, results = { HoleResult }, teamScores = { Red, Blue }, teamWinner }
	Lignes classées (arrivés par ordre d'arrivée, puis les autres par coups) : rang (médailles 1-3), nom +
	marqueur d'équipe (glyphe + libellé), coups, libellé par rapport au par (birdie, par, bogey…) ou statut
	(temps écoulé, abandon…), points de la manche, bonus. La ligne du joueur local est mise en évidence.
	En mode Équipes : cartes des deux équipes avec leur score et le gagnant du trou. Pied : « Trou suivant dans
	n s » / « Podium dans n s » (GameState.PhaseEndsAt). Lignes qui glissent l'une après l'autre (sans
	animation si effets réduits). Non modal.
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
local Grid = require(UI.Components.Grid)
local TeamMarker = require(UI.Components.TeamMarker)
local Util = require(script.Parent.Util)

local HoleResults = {}

local ROW_HEIGHT = 52
local STAGGER = 0.06
local MEDALS: { [number]: Color3 } = {
	[1] = Color3.fromRGB(255, 205, 60),
	[2] = Color3.fromRGB(200, 210, 225),
	[3] = Color3.fromRGB(222, 141, 82),
}

type Column = { id: string, width: number, key: string, align: Enum.TextXAlignment }

local COLUMNS: { Column } = {
	{ id = "rank", width = 64, key = "match.results.rank", align = Enum.TextXAlignment.Center },
	{ id = "player", width = 0, key = "match.results.player", align = Enum.TextXAlignment.Left },
	{ id = "strokes", width = 76, key = "match.results.strokes", align = Enum.TextXAlignment.Center },
	{ id = "score", width = 150, key = "match.results.toPar", align = Enum.TextXAlignment.Center },
	{ id = "points", width = 84, key = "match.results.points", align = Enum.TextXAlignment.Center },
	{ id = "bonuses", width = 170, key = "match.results.bonuses", align = Enum.TextXAlignment.Left },
}

local function scoreColor(strokes: number, par: number): Color3
	local diff = strokes - par
	if strokes == 1 or diff <= -2 then
		return Theme.Colors.Accent
	elseif diff == -1 then
		return Theme.Colors.Success
	elseif diff == 0 then
		return Theme.Colors.Secondary
	elseif diff == 1 then
		return Theme.Colors.Warning
	end
	return Theme.Colors.Danger
end

-- Classement d'affichage : arrivés (ordre d'arrivée) puis non arrivés (moins de coups d'abord).
local function sortResults(results: { any }): { any }
	local list = {}
	for _, entry in results do
		if type(entry) == "table" then
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a, b)
		local aDone = a.finished == true
		local bDone = b.finished == true
		if aDone ~= bDone then
			return aDone
		end
		if aDone then
			return (tonumber(a.finishOrder) or math.huge) < (tonumber(b.finishOrder) or math.huge)
		end
		local ap, bp = tonumber(a.points) or 0, tonumber(b.points) or 0
		if ap ~= bp then
			return ap > bp
		end
		return (tonumber(a.strokes) or math.huge) < (tonumber(b.strokes) or math.huge)
	end)
	return list
end

-- Cellule de tableau (cadre transparent de largeur fixe ou flexible).
local function cell(row: Instance, column: Column, order: number, flexWidth: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = column.id
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = order
	if column.width > 0 then
		frame.Size = UDim2.new(0, column.width, 1, 0)
	else
		frame.Size = UDim2.new(1, -flexWidth, 1, 0)
	end
	frame.Parent = row
	return frame
end

function HoleResults.new(ctx: any): any
	local screen: any = { DisplayOrder = Theme.Layers.Results }

	local showTrove = Trove.new()
	local contentTrove = Trove.new()
	local holder: Frame
	local panel: Panel.PanelApi
	local subtitle: Label.LabelApi
	local header: Frame
	local list: Grid.GridApi
	local teamRow: Frame
	local teamRed: TextLabel
	local teamBlue: TextLabel
	local teamWinner: Label.LabelApi
	local footer: Label.LabelApi
	local waiting: Label.LabelApi

	local function visibleColumns(): ({ Column }, number)
		local columns = {}
		local fixed = 0
		for _, column in COLUMNS do
			if column.id == "bonuses" and Theme.isCompact() then
				continue
			end
			table.insert(columns, column)
			fixed += column.width
		end
		return columns, fixed + 8 * (#columns - 1)
	end

	local function buildHeader()
		for _, child in header:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local columns, fixed = visibleColumns()
		for index, column in columns do
			local frame = cell(header, column, index, fixed)
			local text = Base.newText("Texte", "Caption", "Heavy", Theme.Colors.PaperDim)
			text.Size = UDim2.fromScale(1, 1)
			text.TextXAlignment = column.align
			Base.setText(text, nil, column.key, nil)
			text.Parent = frame
		end
	end

	function screen.Build(_self: any, gui: ScreenGui)
		holder = Instance.new("Frame")
		holder.Name = "Support"
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.52)
		holder.Size = UDim2.fromScale(0.95, 0.86)
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize = Vector2.new(880, 620)
		limit.Parent = holder
		holder.Parent = gui
		ctx.Manager.AttachScale(holder)

		panel = Panel.new({
			name = "Panneau",
			titleKey = "match.phase.HoleResults",
			size = UDim2.fromScale(1, 1),
			parent = holder,
		})
		local content = panel.Content
		Base.list(content, Enum.FillDirection.Vertical, Theme.Spacing.S)

		subtitle = Label.new({
			name = "SousTitre",
			style = "Heading",
			font = "Display",
			alignX = Enum.TextXAlignment.Center,
			color = Theme.Colors.Primary,
			stroke = true,
			size = UDim2.new(1, 0, 0, 32),
			layoutOrder = 1,
			parent = content,
		})

		teamRow = Instance.new("Frame")
		teamRow.Name = "Equipes"
		teamRow.BackgroundTransparency = 1
		teamRow.Size = UDim2.new(1, 0, 0, 76)
		teamRow.LayoutOrder = 2
		teamRow.Visible = false
		Base.list(teamRow, Enum.FillDirection.Horizontal, Theme.Spacing.M, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		teamRow.Parent = content

		local function teamCard(team: string, order: number): TextLabel
			local style = Theme.team(team)
			local color = if style then style.color else Theme.Colors.NightRaised
			local cardFrame = Instance.new("Frame")
			cardFrame.Name = "Equipe" .. team
			cardFrame.BorderSizePixel = 0
			cardFrame.BackgroundColor3 = Theme.darken(color, 0.55)
			cardFrame.Size = UDim2.fromOffset(190, 46)
			cardFrame.LayoutOrder = order
			Base.corner(cardFrame, "Medium")
			Base.stroke(cardFrame, color, Theme.StrokeWidth.Thick)
			Base.padding(cardFrame, nil, 10, 0)
			cardFrame.Parent = teamRow
			TeamMarker.new({ team = team, size = "Medium", position = UDim2.new(0, 0, 0.5, 0), anchorPoint = Vector2.new(0, 0.5), parent = cardFrame })
			local score = Base.newText("Score", "Heading", "Display", Theme.Colors.Paper)
			score.AnchorPoint = Vector2.new(1, 0.5)
			score.Position = UDim2.new(1, 0, 0.5, 0)
			score.Size = UDim2.fromOffset(80, 40)
			score.TextXAlignment = Enum.TextXAlignment.Right
			Base.textStroke(score, 2)
			score.Parent = cardFrame
			return score
		end
		teamRed = teamCard("Red", 1)
		teamWinner = Label.new({
			name = "Gagnant",
			style = "Body",
			font = "Heavy",
			alignX = Enum.TextXAlignment.Center,
			color = Theme.Colors.Paper,
			size = UDim2.fromOffset(220, 46),
			layoutOrder = 2,
			parent = teamRow,
		})
		teamBlue = teamCard("Blue", 3)

		header = Instance.new("Frame")
		header.Name = "EnTete"
		header.BackgroundTransparency = 1
		header.Size = UDim2.new(1, -24, 0, 22)
		header.LayoutOrder = 3
		Base.list(header, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		Base.padding(header, nil, 8, 0)
		header.Parent = content

		list = Grid.list({
			name = "Lignes",
			gap = 6,
			size = UDim2.new(1, 0, 1, -190),
			layoutOrder = 4,
			parent = content,
		})

		waiting = Label.new({
			name = "Attente",
			key = "results.waiting",
			style = "Heading",
			alignX = Enum.TextXAlignment.Center,
			color = Theme.Colors.PaperDim,
			size = UDim2.new(1, 0, 0, 40),
			visible = false,
			parent = list.Instance,
		})

		footer = Label.new({
			name = "Pied",
			style = "Body",
			font = "Heavy",
			alignX = Enum.TextXAlignment.Center,
			color = Theme.Colors.PaperDim,
			size = UDim2.new(1, 0, 0, 28),
			layoutOrder = 5,
			parent = content,
		})

		buildHeader()
		Theme.Changed:Connect(function(what: any)
			if what == "layout" and header.Parent then
				buildHeader()
			end
		end)
	end

	local function buildRow(entry: any, index: number, par: number, localId: number): Frame
		local columns, fixed = visibleColumns()
		local isLocal = entry.userId == localId
		local finished = entry.finished == true
		local strokes = tonumber(entry.strokes) or 0
		local entryPar = tonumber(entry.par) or par

		local row = Instance.new("Frame")
		row.Name = "Ligne" .. index
		row.BorderSizePixel = 0
		row.BackgroundColor3 = if isLocal then Theme.Colors.NightHover else Theme.Colors.NightRaised
		row.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
		row.LayoutOrder = index
		Base.corner(row, "Medium")
		Base.stroke(row, if isLocal then Theme.Colors.Primary else Theme.Colors.Ink, if isLocal then Theme.StrokeWidth.Thick else Theme.StrokeWidth.Thin)

		local inner = Instance.new("Frame")
		inner.Name = "Cellules"
		inner.BackgroundTransparency = 1
		inner.Size = UDim2.fromScale(1, 1)
		Base.list(inner, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		Base.padding(inner, nil, 8, 0)
		inner.Parent = row

		for order, column in columns do
			local frame = cell(inner, column, order, fixed)
			if column.id == "rank" then
				local rank = if finished then tonumber(entry.finishOrder) else nil
				local medal = rank and MEDALS[rank]
				local badge = Instance.new("Frame")
				badge.Name = "Medaille"
				badge.BorderSizePixel = 0
				badge.AnchorPoint = Vector2.new(0.5, 0.5)
				badge.Position = UDim2.fromScale(0.5, 0.5)
				badge.Size = UDim2.fromOffset(44, 36)
				badge.BackgroundColor3 = medal or Theme.Colors.Night
				Base.corner(badge, "Pill")
				Base.stroke(badge, Theme.Colors.Ink, Theme.StrokeWidth.Thin)
				badge.Parent = frame
				local text = Base.newText("Rang", "Small", "Heavy", if medal then Theme.Colors.Ink else Theme.Colors.Paper)
				text.Size = UDim2.fromScale(1, 1)
				text.TextXAlignment = Enum.TextXAlignment.Center
				text.Text = if rank then Util.rankText(rank) else Locale.t("results.notFinished")
				text.Parent = badge
			elseif column.id == "player" then
				local box = Instance.new("Frame")
				box.Name = "Joueur"
				box.BackgroundTransparency = 1
				box.Size = UDim2.fromScale(1, 1)
				Base.list(box, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
				box.Parent = frame
				if type(entry.team) == "string" and Theme.team(entry.team) then
					TeamMarker.new({ team = entry.team, size = "Small", showLabel = not Theme.isCompact(), layoutOrder = 1, parent = box })
				end
				local name = Base.newText("Nom", "Body", "Heavy", Theme.Colors.Paper)
				name.Size = UDim2.new(1, -110, 1, 0)
				name.TextTruncate = Enum.TextTruncate.AtEnd
				name.LayoutOrder = 2
				name.Text = Util.playerName(entry.userId, entry.name)
					.. (if isLocal then "  (" .. Locale.t("ui.you") .. ")" else "")
				name.Parent = box
			elseif column.id == "strokes" then
				local text = Base.newText("Coups", "Heading", "Display", Theme.Colors.Paper)
				text.Size = UDim2.fromScale(1, 1)
				text.TextXAlignment = Enum.TextXAlignment.Center
				text.Text = if strokes > 0 then tostring(strokes) else Locale.t("results.notFinished")
				text.Parent = frame
			elseif column.id == "score" then
				local pill = Instance.new("Frame")
				pill.Name = "Etiquette"
				pill.BorderSizePixel = 0
				pill.AnchorPoint = Vector2.new(0.5, 0.5)
				pill.Position = UDim2.fromScale(0.5, 0.5)
				pill.Size = UDim2.new(1, -4, 0, 34)
				Base.corner(pill, "Pill")
				Base.stroke(pill, Theme.Colors.Ink, Theme.StrokeWidth.Thin)
				pill.Parent = frame
				local text = Base.newText("Texte", "Small", "Heavy")
				text.Size = UDim2.fromScale(1, 1)
				text.TextXAlignment = Enum.TextXAlignment.Center
				text.TextTruncate = Enum.TextTruncate.AtEnd
				text.Parent = pill
				if finished and strokes > 0 then
					local color = scoreColor(strokes, entryPar)
					local key, vars = Util.scoreKey(strokes, entryPar)
					pill.BackgroundColor3 = color
					text.TextColor3 = Theme.textOn(color)
					text.Text = Locale.t(key, vars) .. "  (" .. Util.toParText(strokes, entryPar) .. ")"
				else
					local status = if type(entry.status) == "string" then entry.status else "TimeOut"
					pill.BackgroundColor3 = Theme.Colors.Disabled
					text.TextColor3 = Theme.Colors.Paper
					local statusKey = "match.status." .. status
					text.Text = if Locale.has(statusKey, "fr") then Locale.t(statusKey) else status
				end
			elseif column.id == "points" then
				local points = tonumber(entry.points) or 0
				local text = Base.newText("Points", "Heading", "Display", if points > 0 then Theme.Colors.Primary else Theme.Colors.PaperDim)
				text.Size = UDim2.fromScale(1, 1)
				text.TextXAlignment = Enum.TextXAlignment.Center
				text.Text = if points > 0 then Locale.t("match.bonus.points", { points = points }) else "0"
				Base.textStroke(text, 2)
				text.Parent = frame
			elseif column.id == "bonuses" then
				local box = Instance.new("Frame")
				box.Name = "Bonus"
				box.BackgroundTransparency = 1
				box.Size = UDim2.fromScale(1, 1)
				box.ClipsDescendants = true
				Base.list(box, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
				box.Parent = frame
				local bonuses = if type(entry.bonuses) == "table" then entry.bonuses else {}
				for bonusIndex, bonus in bonuses do
					if type(bonus) ~= "string" or bonusIndex > 3 then
						continue
					end
					local chip = Instance.new("Frame")
					chip.Name = "Bonus" .. bonusIndex
					chip.BorderSizePixel = 0
					chip.BackgroundColor3 = Theme.Colors.Accent
					chip.AutomaticSize = Enum.AutomaticSize.X
					chip.Size = UDim2.fromOffset(0, 24)
					chip.LayoutOrder = bonusIndex
					Base.corner(chip, "Pill")
					Base.padding(chip, nil, 8, 0)
					chip.Parent = box
					local text = Base.newText("Texte", "Caption", "Heavy", Theme.textOn(Theme.Colors.Accent))
					text.AutomaticSize = Enum.AutomaticSize.X
					text.Size = UDim2.fromOffset(0, 24)
					local bonusKey = "match.bonus." .. bonus
					text.Text = if Locale.has(bonusKey, "fr") then Locale.t(bonusKey) else bonus
					text.Parent = chip
				end
			end
		end
		return row
	end

	local function render(payload: any)
		contentTrove:Clean()
		for _, child in list.Instance:GetChildren() do
			if child:IsA("GuiObject") and child ~= waiting.Instance then
				child:Destroy()
			end
		end
		local index = Util.attr("HoleIndex")
		local count = Util.attr("HoleCount")
		if type(index) == "number" and type(count) == "number" and count > 0 then
			panel.SetTitle(Locale.t("match.results.title", { index = index, count = count }))
		else
			panel.SetTitleKey("match.phase.HoleResults")
		end

		if type(payload) ~= "table" then
			subtitle.SetText("")
			waiting.SetKey("results.waiting")
			waiting.Instance.Visible = true
			teamRow.Visible = false
			return
		end

		local par = tonumber(payload.par) or tonumber(Util.attr("HolePar")) or 3
		local holeName = payload.holeName
		local holeId = payload.holeId
		if type(holeId) == "string" and Locale.has("hole." .. holeId .. ".name", "fr") then
			holeName = Locale.t("hole." .. holeId .. ".name")
		end
		subtitle.SetText(Locale.t("results.holeLine", { name = if type(holeName) == "string" then holeName else "?", par = par }))

		local results = if type(payload.results) == "table" then sortResults(payload.results) else {}
		waiting.Instance.Visible = #results == 0
		if #results == 0 then
			waiting.SetKey("results.empty")
		end

		local localId = Util.localPlayer().UserId
		local reduced = Theme.isReducedMotion()
		for rowIndex, entry in results do
			local row = buildRow(entry, rowIndex, par, localId)
			if reduced then
				row.Parent = list.Instance
			else
				-- Glissement en cascade : chaque ligne part de la droite, transparente.
				local group = Instance.new("CanvasGroup")
				group.Name = "Entree" .. rowIndex
				group.BackgroundTransparency = 1
				group.Size = UDim2.new(1, -8, 0, ROW_HEIGHT + 4)
				group.LayoutOrder = rowIndex
				group.GroupTransparency = 1
				row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
				row.Position = UDim2.fromOffset(60, 2)
				row.Parent = group
				group.Parent = list.Instance
				contentTrove:Add(task.delay((rowIndex - 1) * STAGGER, function()
					Theme.fade(group, 0.22, { GroupTransparency = 0 })
					Theme.tween(row, 0.3, { Position = UDim2.fromOffset(0, 2) }, Enum.EasingStyle.Back)
				end))
			end
		end

		-- Équipes.
		local scores = payload.teamScores
		local isTeams = type(scores) == "table" and (Util.attr("Mode") == "Teams" or payload.teamWinner ~= nil)
		teamRow.Visible = isTeams == true
		if isTeams then
			local red = tonumber(scores.Red) or 0
			local blue = tonumber(scores.Blue) or 0
			teamRed.Text = tostring(red)
			teamBlue.Text = tostring(blue)
			local winner = payload.teamWinner
			if winner == "Red" then
				teamWinner.SetKey("results.team.winnerRed")
				teamWinner.SetColor(Theme.Teams.Red.text)
			elseif winner == "Blue" then
				teamWinner.SetKey("results.team.winnerBlue")
				teamWinner.SetColor(Theme.Teams.Blue.text)
			else
				teamWinner.SetKey("results.team.draw")
				teamWinner.SetColor(Theme.Colors.Paper)
			end
		end
		list.Instance.Size = UDim2.new(1, 0, 1, if isTeams then -190 else -110)
		list.ScrollToTop()
	end

	local function refreshFooter()
		local left = Util.secondsLeft(Util.attr("PhaseEndsAt"))
		if not left then
			footer.SetText("")
			return
		end
		local index = Util.attr("HoleIndex")
		local count = Util.attr("HoleCount")
		local last = type(index) == "number" and type(count) == "number" and index >= count
		footer.SetText(Locale.t(if last then "results.toPodium" else "results.next", { seconds = math.ceil(left) }))
	end

	function screen.Show(_self: any, args: any, wasVisible: boolean)
		render(if args ~= nil then args else ctx.GetHoleResults())
		if wasVisible then
			return
		end
		showTrove:Clean()
		showTrove:Add(task.spawn(function()
			while true do
				refreshFooter()
				task.wait(0.25)
			end
		end))
		if not Theme.isReducedMotion() then
			holder.Position = UDim2.fromScale(0.5, 0.6)
			Theme.tween(holder, 0.35, { Position = UDim2.fromScale(0.5, 0.52) }, Enum.EasingStyle.Back)
		else
			holder.Position = UDim2.fromScale(0.5, 0.52)
		end
	end

	function screen.Hide(_self: any): number?
		showTrove:Clean()
		contentTrove:Clean()
		return 0
	end

	function screen.Destroy(_self: any)
		showTrove:Clean()
		contentTrove:Clean()
	end

	return screen
end

return HoleResults
