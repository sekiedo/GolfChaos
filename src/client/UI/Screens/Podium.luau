--!strict
--[[
	Podium — fin de partie (message Match.Podium) :
	  { matchId, mode, standings = { { userId, name, team, points, strokes, rank } }, teamScores, winner }
	Gauche : les trois premiers sur des marches (2e, 1er, 3e) qui montent l'une après l'autre (immobiles si
	effets réduits), avec nom, marqueur d'équipe et points. Droite : classement complet, puis encart des
	récompenses (message Progress.MatchReward : { total, breakdown, eligible, reason? }) dès sa réception.
	En mode Équipes, le titre annonce l'équipe gagnante et le score des équipes. Pied : retour à l'accueil.
	Non modal.
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

local Podium = {}

local STEP_HEIGHTS: { [number]: number } = { [1] = 170, [2] = 120, [3] = 86 }
local STEP_COLORS: { [number]: Color3 } = {
	[1] = Color3.fromRGB(255, 205, 60),
	[2] = Color3.fromRGB(200, 210, 225),
	[3] = Color3.fromRGB(222, 141, 82),
}
local STEP_ORDER = { 2, 1, 3 } -- de gauche à droite
local REWARD_KEYS = { "base", "holes", "placement", "team", "solo", "performance", "cap" }

local function sortStandings(standings: any): { any }
	local list = {}
	if type(standings) == "table" then
		for _, entry in standings do
			if type(entry) == "table" then
				table.insert(list, entry)
			end
		end
	end
	table.sort(list, function(a, b)
		local ar, br = tonumber(a.rank) or math.huge, tonumber(b.rank) or math.huge
		if ar ~= br then
			return ar < br
		end
		return (tonumber(a.points) or 0) > (tonumber(b.points) or 0)
	end)
	return list
end

function Podium.new(ctx: any): any
	local screen: any = { DisplayOrder = Theme.Layers.Results }

	local showTrove = Trove.new()
	local contentTrove = Trove.new()
	local veil: Frame
	local holder: Frame
	local headline: Label.LabelApi
	local teamLine: Label.LabelApi
	local stage: Frame
	local standingsList: Grid.GridApi
	local rewardTitle: Label.LabelApi
	local rewardTotal: Label.LabelApi
	local rewardLines: Frame
	local footer: Label.LabelApi

	function screen.Build(_self: any, gui: ScreenGui)
		veil = Instance.new("Frame")
		veil.Name = "Voile"
		veil.BorderSizePixel = 0
		veil.BackgroundColor3 = Theme.Colors.Backdrop
		veil.BackgroundTransparency = 1
		veil.Size = UDim2.fromScale(1, 1)
		veil.Parent = gui
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Transparency = NumberSequence.new(0.6, 0.15)
		gradient.Parent = veil

		holder = Instance.new("Frame")
		holder.Name = "Support"
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.53)
		holder.Size = UDim2.fromScale(0.96, 0.88)
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize = Vector2.new(1040, 640)
		limit.Parent = holder
		holder.Parent = gui
		ctx.Manager.AttachScale(holder)

		local panel = Panel.new({
			name = "Panneau",
			titleKey = "match.podium.title",
			size = UDim2.fromScale(1, 1),
			parent = holder,
		})
		local content = panel.Content

		headline = Label.new({
			name = "Annonce",
			style = "Title",
			font = "Display",
			alignX = Enum.TextXAlignment.Center,
			color = Theme.Colors.Primary,
			stroke = 3,
			size = UDim2.new(1, 0, 0, 40),
			parent = content,
		})
		teamLine = Label.new({
			name = "ScoreEquipes",
			style = "Body",
			font = "Heavy",
			alignX = Enum.TextXAlignment.Center,
			color = Theme.Colors.Paper,
			size = UDim2.new(1, 0, 0, 24),
			position = UDim2.fromOffset(0, 40),
			parent = content,
		})

		-- Colonne gauche : marches du podium.
		stage = Instance.new("Frame")
		stage.Name = "Scene"
		stage.BackgroundTransparency = 1
		stage.Position = UDim2.fromOffset(0, 70)
		stage.Size = UDim2.new(0.56, -8, 1, -104)
		Base.list(stage, Enum.FillDirection.Horizontal, Theme.Spacing.S, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)
		stage.Parent = content

		-- Colonne droite : classement + récompenses.
		local side = Instance.new("Frame")
		side.Name = "Cote"
		side.BackgroundTransparency = 1
		side.AnchorPoint = Vector2.new(1, 0)
		side.Position = UDim2.new(1, 0, 0, 70)
		side.Size = UDim2.new(0.44, -8, 1, -104)
		side.Parent = content

		local standingsTitle = Label.new({
			name = "TitreClassement",
			key = "match.podium.standings",
			style = "Heading",
			font = "Display",
			color = Theme.Colors.Paper,
			size = UDim2.new(1, 0, 0, 30),
			parent = side,
		})
		local _ = standingsTitle
		standingsList = Grid.list({
			name = "Classement",
			gap = 4,
			position = UDim2.fromOffset(0, 32),
			size = UDim2.new(1, 0, 0.62, -32),
			parent = side,
		})

		local reward = Panel.inset({
			name = "Recompenses",
			position = UDim2.fromScale(0, 0.64),
			size = UDim2.new(1, 0, 0.36, 0),
			color = Theme.Colors.NightRaised,
			parent = side,
		})
		Base.list(reward, Enum.FillDirection.Vertical, 2)
		rewardTitle = Label.new({
			name = "Titre",
			key = "results.podium.rewardTitle",
			style = "Small",
			font = "Heavy",
			color = Theme.Colors.PaperDim,
			size = UDim2.new(1, 0, 0, 18),
			layoutOrder = 1,
			parent = reward,
		})
		rewardTotal = Label.new({
			name = "Total",
			style = "Heading",
			font = "Display",
			color = Theme.Colors.Primary,
			stroke = true,
			size = UDim2.new(1, 0, 0, 30),
			layoutOrder = 2,
			parent = reward,
		})
		rewardLines = Instance.new("Frame")
		rewardLines.Name = "Details"
		rewardLines.BackgroundTransparency = 1
		rewardLines.AutomaticSize = Enum.AutomaticSize.Y
		rewardLines.Size = UDim2.new(1, 0, 0, 0)
		rewardLines.LayoutOrder = 3
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.new(0.5, -4, 0, 18)
		grid.CellPadding = UDim2.fromOffset(4, 0)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = rewardLines
		rewardLines.Parent = reward

		footer = Label.new({
			name = "Pied",
			style = "Body",
			font = "Heavy",
			alignX = Enum.TextXAlignment.Center,
			color = Theme.Colors.PaperDim,
			anchorPoint = Vector2.new(0, 1),
			position = UDim2.fromScale(0, 1),
			size = UDim2.new(1, 0, 0, 26),
			parent = content,
		})
	end

	local function renderReward()
		for _, child in rewardLines:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local reward = ctx.GetReward()
		local _ = rewardTitle
		if type(reward) ~= "table" then
			rewardTotal.SetKey("results.podium.rewardPending")
			rewardTotal.SetColor(Theme.Colors.PaperDim)
			return
		end
		local total = tonumber(reward.total) or 0
		if reward.eligible == false then
			local reason = if type(reward.reason) == "string" then reward.reason else "unknown"
			local key = "results.podium.reason." .. reason
			rewardTotal.SetKey(if Locale.has(key, "fr") then key else "results.podium.reason.unknown")
			rewardTotal.SetColor(Theme.Colors.PaperDim)
			return
		end
		if total > 0 then
			rewardTotal.SetText("◎ " .. Locale.t("results.podium.rewardTotal", { coins = total }))
			rewardTotal.SetColor(Theme.Colors.Primary)
		else
			rewardTotal.SetKey("results.podium.rewardNone")
			rewardTotal.SetColor(Theme.Colors.PaperDim)
		end
		local breakdown = if type(reward.breakdown) == "table" then reward.breakdown else {}
		local order = 0
		for _, key in REWARD_KEYS do
			local amount = tonumber(breakdown[key])
			if amount and amount ~= 0 then
				order += 1
				local line = Base.newText("Ligne_" .. key, "Caption", "Bold", Theme.Colors.Paper)
				line.LayoutOrder = order
				line.TextTruncate = Enum.TextTruncate.AtEnd
				local labelKey = "results.reward." .. key
				line.Text = Locale.t("results.reward.line", {
					label = Locale.t(labelKey),
					coins = (if amount > 0 then "+" else "") .. tostring(math.floor(amount)),
				})
				line.Parent = rewardLines
			end
		end
	end

	local function winnerText(payload: any, standings: { any }): string
		local winner = payload.winner
		if winner == "Red" then
			return Locale.t("results.podium.winnerRed")
		elseif winner == "Blue" then
			return Locale.t("results.podium.winnerBlue")
		elseif winner == "Draw" or winner == "draw" then
			return Locale.t("results.podium.draw")
		end
		local name: string? = nil
		if type(winner) == "number" then
			for _, entry in standings do
				if entry.userId == winner then
					name = Util.playerName(entry.userId, entry.name)
				end
			end
			if not name then
				name = Util.playerName(winner, nil)
			end
		elseif type(winner) == "string" and winner ~= "" then
			name = winner
		elseif type(winner) == "table" and (winner.name or winner.userId) then
			name = Util.playerName(winner.userId, winner.name)
		elseif standings[1] then
			name = Util.playerName(standings[1].userId, standings[1].name)
		end
		if name then
			return Locale.t("results.podium.winner", { name = name })
		end
		return Locale.t("match.announce.matchEnd")
	end

	local function buildStep(entry: any?, place: number, delayTime: number)
		local column = Instance.new("Frame")
		column.Name = "Marche" .. place
		column.BackgroundTransparency = 1
		column.Size = UDim2.new(0.31, 0, 1, 0)
		column.LayoutOrder = table.find(STEP_ORDER, place) or place
		column.Parent = stage

		local height = STEP_HEIGHTS[place] or 80
		local color = STEP_COLORS[place] or Theme.Colors.NightRaised

		local block = Instance.new("Frame")
		block.Name = "Bloc"
		block.BorderSizePixel = 0
		block.BackgroundColor3 = color
		block.AnchorPoint = Vector2.new(0.5, 1)
		block.Position = UDim2.fromScale(0.5, 1)
		block.Size = UDim2.new(1, 0, 0, height)
		block.ClipsDescendants = false
		Base.corner(block, "Medium")
		Base.stroke(block, Theme.Colors.Ink, Theme.StrokeWidth.Thick)
		block.Parent = column

		local face = Instance.new("Frame")
		face.Name = "Dessus"
		face.BorderSizePixel = 0
		face.BackgroundColor3 = Theme.lighten(color, 0.25)
		face.Size = UDim2.new(1, 0, 0, 14)
		Base.corner(face, "Medium")
		face.Parent = block

		local numeral = Base.newText("Rang", "Display", "Display", Theme.Colors.Ink)
		numeral.Size = UDim2.new(1, 0, 0, 60)
		numeral.Position = UDim2.fromOffset(0, 16)
		numeral.TextXAlignment = Enum.TextXAlignment.Center
		numeral.Text = tostring(place)
		numeral.Parent = block

		-- Carte du joueur au-dessus de la marche.
		local cardFrame = Instance.new("Frame")
		cardFrame.Name = "Carte"
		cardFrame.BorderSizePixel = 0
		cardFrame.BackgroundColor3 = Theme.Colors.NightRaised
		cardFrame.AnchorPoint = Vector2.new(0.5, 1)
		cardFrame.Position = UDim2.new(0.5, 0, 1, -height - 10)
		cardFrame.Size = UDim2.new(1, 0, 0, 92)
		Base.corner(cardFrame, "Medium")
		Base.stroke(cardFrame, if place == 1 then Theme.Colors.Primary else Theme.Colors.Ink, Theme.StrokeWidth.Thick)
		Base.padding(cardFrame, 6)
		Base.list(cardFrame, Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		cardFrame.Parent = column

		if place == 1 then
			local crown = Base.newText("Couronne", "Title", "Display", Theme.Colors.Primary)
			crown.AnchorPoint = Vector2.new(0.5, 1)
			crown.Position = UDim2.new(0.5, 0, 1, -height - 104)
			crown.Size = UDim2.new(1, 0, 0, 36)
			crown.TextXAlignment = Enum.TextXAlignment.Center
			crown.Text = "★"
			Base.textStroke(crown, 3)
			crown.Parent = column
		end

		local name = Base.newText("Nom", "Body", "Heavy", Theme.Colors.Paper)
		name.Size = UDim2.new(1, 0, 0, 24)
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.LayoutOrder = 1
		name.Parent = cardFrame
		if entry then
			name.Text = Util.playerName(entry.userId, entry.name)
			if type(entry.team) == "string" and Theme.team(entry.team) then
				TeamMarker.new({ team = entry.team, size = "Small", layoutOrder = 2, parent = cardFrame })
			end
			local points = Base.newText("Points", "Heading", "Display", Theme.Colors.Primary)
			points.Size = UDim2.new(1, 0, 0, 28)
			points.TextXAlignment = Enum.TextXAlignment.Center
			points.LayoutOrder = 3
			points.Text = Locale.t("results.podium.points", { n = tonumber(entry.points) or 0 })
			Base.textStroke(points, 2)
			points.Parent = cardFrame
		else
			name.Text = Locale.t("ui.none")
			name.TextColor3 = Theme.Colors.PaperDim
		end

		if not Theme.isReducedMotion() then
			block.Size = UDim2.new(1, 0, 0, 0)
			cardFrame.Visible = false
			contentTrove:Add(task.delay(delayTime, function()
				Theme.tween(block, 0.45, { Size = UDim2.new(1, 0, 0, height) }, Enum.EasingStyle.Back)
				task.wait(0.35)
				cardFrame.Visible = true
				local scale = Instance.new("UIScale")
				scale.Scale = 0.4
				scale.Parent = cardFrame
				Theme.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end))
		end
	end

	local function buildStandingRow(entry: any, index: number, localId: number)
		local isLocal = entry.userId == localId
		local row = Instance.new("Frame")
		row.Name = "Ligne" .. index
		row.BorderSizePixel = 0
		row.BackgroundColor3 = if isLocal then Theme.Colors.NightHover else Theme.Colors.NightRaised
		row.Size = UDim2.new(1, -8, 0, 40)
		row.LayoutOrder = index
		Base.corner(row, "Small")
		Base.stroke(row, if isLocal then Theme.Colors.Primary else Theme.Colors.Ink, if isLocal then Theme.StrokeWidth.Normal else Theme.StrokeWidth.Thin)
		Base.padding(row, nil, 8, 0)
		Base.list(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		row.Parent = standingsList.Instance

		local rank = Base.newText("Rang", "Small", "Heavy", Theme.Colors.Primary)
		rank.Size = UDim2.fromOffset(48, 40)
		rank.Text = Util.rankText(tonumber(entry.rank) or index)
		rank.LayoutOrder = 1
		rank.Parent = row

		if type(entry.team) == "string" and Theme.team(entry.team) then
			TeamMarker.new({ team = entry.team, size = "Small", showLabel = false, layoutOrder = 2, parent = row })
		end

		local name = Base.newText("Nom", "Small", "Bold", Theme.Colors.Paper)
		name.Size = UDim2.new(1, -190, 1, 0)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.LayoutOrder = 3
		name.Text = Util.playerName(entry.userId, entry.name)
		name.Parent = row

		local points = Base.newText("Points", "Small", "Heavy", Theme.Colors.Primary)
		points.Size = UDim2.fromOffset(64, 40)
		points.TextXAlignment = Enum.TextXAlignment.Right
		points.LayoutOrder = 4
		points.Text = Locale.t("results.podium.points", { n = tonumber(entry.points) or 0 })
		points.Parent = row

		local strokes = Base.newText("Coups", "Caption", "Bold", Theme.Colors.PaperDim)
		strokes.Size = UDim2.fromOffset(56, 40)
		strokes.TextXAlignment = Enum.TextXAlignment.Right
		strokes.LayoutOrder = 5
		strokes.Text = if tonumber(entry.strokes) then Locale.t("results.podium.strokes", { n = entry.strokes }) else ""
		strokes.Parent = row
	end

	local function render(payload: any)
		contentTrove:Clean()
		for _, child in stage:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		standingsList.Clear()

		if type(payload) ~= "table" then
			headline.SetKey("match.announce.matchEnd")
			teamLine.SetText("")
			renderReward()
			return
		end
		local standings = sortStandings(payload.standings)
		headline.SetText(winnerText(payload, standings))

		local scores = payload.teamScores
		if payload.mode == "Teams" and type(scores) == "table" then
			teamLine.SetText(Locale.t("match.team.score", { red = tonumber(scores.Red) or 0, blue = tonumber(scores.Blue) or 0 }))
		else
			local localId = Util.localPlayer().UserId
			teamLine.SetText("")
			for _, entry in standings do
				if entry.userId == localId then
					teamLine.SetText(Locale.t("match.podium.yourRank", { rank = Util.rankText(tonumber(entry.rank) or 0) }))
				end
			end
		end

		-- Les trois premiers : rang 1..3 (ex æquo possibles : on prend les trois premières entrées).
		for _, place in STEP_ORDER do
			local entry = standings[place]
			buildStep(entry, place, 0.15 + (3 - place) * 0.35)
		end

		local localId = Util.localPlayer().UserId
		for index, entry in standings do
			buildStandingRow(entry, index, localId)
		end
		renderReward()
	end

	local function refreshFooter()
		local left = Util.secondsLeft(Util.attr("PhaseEndsAt"))
		if left then
			footer.SetText(Locale.t("results.podium.back", { seconds = math.ceil(left) }))
		else
			footer.SetText("")
		end
	end

	function screen.Show(_self: any, args: any, wasVisible: boolean)
		render(if args ~= nil then args else ctx.GetPodium())
		if wasVisible then
			return
		end
		showTrove:Clean()
		Theme.fade(veil, 0.4, { BackgroundTransparency = Theme.backgroundTransparency(0.2) })
		showTrove:Connect(ctx.RewardReceived, function()
			renderReward()
			Base.playSound("coins_reward")
		end)
		showTrove:Add(task.spawn(function()
			while true do
				refreshFooter()
				task.wait(0.25)
			end
		end))
		local effects = Util.controller("EffectsController")
		if effects and type(effects.PlaySound) == "function" then
			pcall(effects.PlaySound, "crowd_cheer", { maxDuration = 4, fadeOut = 1.2 })
		end
		if not Theme.isReducedMotion() then
			holder.Position = UDim2.fromScale(0.5, 0.62)
			Theme.tween(holder, 0.4, { Position = UDim2.fromScale(0.5, 0.53) }, Enum.EasingStyle.Back)
		end
	end

	function screen.Hide(_self: any): number?
		showTrove:Clean()
		contentTrove:Clean()
		Theme.fade(veil, 0.25, { BackgroundTransparency = 1 })
		return 0.25
	end

	function screen.Destroy(_self: any)
		showTrove:Clean()
		contentTrove:Clean()
	end

	return screen
end

return Podium
