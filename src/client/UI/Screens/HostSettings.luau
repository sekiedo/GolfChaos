--!strict
--[[
	HostSettings — salon de la partie pendant la phase Preparing (modale, deux colonnes).

	Gauche : réglages de la partie (Types.MatchSettings) — mode, parcours, nombre de trous, ordre aléatoire,
	durée des trous, vent, vitesse de jeu, objets et fréquence, collisions entre balles, tir ami, arrivées en
	cours de partie, 16 joueurs (expérimental). L'hôte les modifie (Lobby.SetSetting(clé, valeur), validé par le
	serveur) ; les autres joueurs voient les mêmes contrôles en lecture seule.
	Droite : liste des joueurs (hôte, toi, prêt / pas prêt, équipe avec glyphe + libellé, spectateur), choix de
	l'équipe en mode Équipes (Lobby.SetTeam), bouton Prêt (Lobby.SetReady), pour l'hôte : Lancer
	(Lobby.Advance, actif selon canStart), Équilibrer les équipes (Lobby.BalanceTeams), Annuler (Lobby.Cancel).

	Données : Lobby.State { hostUserId, settings, players = { { userId, name, ready, team, spectator } }, canStart }
	(UIController en garde le dernier ; à défaut, état reconstruit depuis les attributs, rafraîchi chaque seconde).
	Retour (B / Échap) referme le panneau ; la bannière de phase permet de le rouvrir.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Trove = require(Shared.Util.Trove)
local Locale = require(Shared.Locale)
local Log = require(Shared.Util.Log)
local MatchConfig = require(Shared.Config.Match)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Base = require(UI.Components.Base)
local Label = require(UI.Components.Label)
local Button = require(UI.Components.Button)
local Modal = require(UI.Components.Modal)
local Grid = require(UI.Components.Grid)
local Toggle = require(UI.Components.Toggle)
local Slider = require(UI.Components.Slider)
local Cycler = require(UI.Components.Cycler)
local TeamMarker = require(UI.Components.TeamMarker)
local Util = require(script.Parent.Util)

local HostSettings = {}

type SettingControl = {
	key: string,
	Instance: GuiObject,
	Set: (value: any, silent: boolean?) -> (),
	SetEnabled: (enabled: boolean) -> (),
}

local FALLBACK_REFRESH = 1

local function send(name: string, ...: any)
	if not Net.getDefinitions()[name] then
		Log.warn("UI", "remote absent :", name)
		return
	end
	local ok, err = pcall(Net.send, name, ...)
	if not ok then
		Log.warn("UI", "envoi impossible :", name, err)
	end
end

local function enumOptions(values: { string }, prefix: string): { any }
	local options = {}
	for _, value in values do
		table.insert(options, { value = value, key = prefix .. value })
	end
	return options
end

local function playlistOptions(current: any): { any }
	local names = { "Quick3", "Front9", "Full18", "Mixed" }
	for _, biome in MatchConfig.Playlists.Biomes do
		table.insert(names, "Biome:" .. biome)
	end
	if current == "Custom" then
		table.insert(names, "Custom")
	end
	return enumOptions(names, "lobby.value.playlist.")
end

local function ruleOf(key: string): any
	return (MatchConfig.SettingRules :: any)[key] or {}
end

function HostSettings.new(ctx: any): any
	local screen: any = { DisplayOrder = Theme.Layers.Lobby, Modal = true }

	local showTrove = Trove.new()
	local modal: Modal.ModalApi
	local settingsList: Grid.GridApi
	local playersList: Grid.GridApi
	local controls: { SettingControl } = {}
	local controlByKey: { [string]: SettingControl } = {}
	local playlistControl: Cycler.CyclerApi
	local roleLabel: Label.LabelApi
	local countLabel: Label.LabelApi
	local statusLabel: Label.LabelApi
	local teamRow: Frame
	local teamButtons: { [string]: Button.ButtonApi } = {}
	local readyButton: Button.ButtonApi
	local startButton: Button.ButtonApi
	local balanceButton: Button.ButtonApi
	local cancelButton: Button.ButtonApi
	local hostRow: Frame

	local state: any = nil
	local localReady = false
	local localReadyPendingUntil = 0
	local isHost = false

	----------------------------------------------------------------------------
	-- Construction des lignes de réglages
	----------------------------------------------------------------------------

	local function sectionHeader(key: string, order: number)
		local header = Label.new({
			name = "Section_" .. key,
			key = key,
			style = "Heading",
			font = "Display",
			color = Theme.Colors.Primary,
			stroke = true,
			size = UDim2.new(1, -10, 0, 34),
			layoutOrder = order,
			parent = settingsList.Instance,
		})
		local _ = header
	end

	local function settingRow(key: string, order: number, control: GuiObject)
		local frame = Instance.new("Frame")
		frame.Name = "Reglage_" .. key
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = Theme.Colors.NightRaised
		frame.Size = UDim2.new(1, -10, 0, 70)
		frame.LayoutOrder = order
		Base.corner(frame, "Medium")
		Base.stroke(frame, Theme.Colors.Ink, Theme.StrokeWidth.Thin)
		Base.padding(frame, nil, Theme.Spacing.M, 6)
		frame.Parent = settingsList.Instance

		local width = control.Size.X.Offset
		local texts = Instance.new("Frame")
		texts.Name = "Textes"
		texts.BackgroundTransparency = 1
		texts.Size = UDim2.new(1, -(width + 10), 1, 0)
		Base.list(texts, Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		texts.Parent = frame
		Label.new({
			name = "Libelle",
			key = "lobby.setting." .. key,
			style = "Body",
			font = "Heavy",
			layoutOrder = 1,
			parent = texts,
		})
		Label.new({
			name = "Description",
			key = "lobby.setting." .. key .. ".desc",
			style = "Caption",
			font = "Bold",
			color = Theme.Colors.PaperDim,
			layoutOrder = 2,
			parent = texts,
		})
		control.AnchorPoint = Vector2.new(1, 0.5)
		control.Position = UDim2.new(1, 0, 0.5, 0)
		control.Parent = frame
	end

	local function register(key: string, api: any)
		local control: SettingControl = {
			key = key,
			Instance = api.Instance,
			Set = api.Set,
			SetEnabled = api.SetEnabled,
		}
		table.insert(controls, control)
		controlByKey[key] = control
	end

	local function addCycler(key: string, order: number, options: { any }, default: any): Cycler.CyclerApi
		local cycler = Cycler.new({
			name = "Selecteur",
			options = options,
			value = default,
			width = 250,
			disabled = true,
			onChanged = function(value: any)
				send("Lobby.SetSetting", key, value)
			end,
		})
		register(key, cycler)
		settingRow(key, order, cycler.Instance)
		return cycler
	end

	local function addToggle(key: string, order: number, default: boolean)
		local toggle = Toggle.new({
			name = "Interrupteur",
			value = default,
			disabled = true,
			onChanged = function(value: boolean)
				send("Lobby.SetSetting", key, value)
			end,
		})
		register(key, toggle)
		settingRow(key, order, toggle.Instance)
	end

	local function addSlider(key: string, order: number, default: number, format: (number) -> string, integer: boolean?)
		local rule = ruleOf(key)
		local slider = Slider.new({
			name = "Curseur",
			min = rule.min or 0,
			max = rule.max or 1,
			step = if integer then 1 else (rule.step or 0.05),
			value = default,
			format = format,
			width = 170,
			disabled = true,
			-- Envoi à la fin du geste (pas un message par pixel glissé).
			onReleased = function(value: number)
				send("Lobby.SetSetting", key, value)
			end,
		})
		register(key, slider)
		settingRow(key, order, slider.Instance)
	end

	local function multiplierText(value: number): string
		return Locale.t("lobby.value.multiplier", { value = string.format("%.2f", value) })
	end

	local function holesText(value: number): string
		local n = math.floor(value + 0.5)
		return if n == 1 then Locale.t("lobby.value.hole") else Locale.t("lobby.value.holes", { count = n })
	end

	----------------------------------------------------------------------------
	-- Construction
	----------------------------------------------------------------------------

	function screen.Build(_self: any, gui: ScreenGui)
		modal = Modal.new({
			parent = gui,
			titleKey = "lobby.title",
			size = Vector2.new(1000, 640),
			scroll = false,
			onClose = function()
				ctx.Manager.Hide("HostSettings")
			end,
		})
		local content = modal.Content
		local defaults: any = MatchConfig.DefaultSettings

		-- Colonne gauche : réglages.
		local left = Instance.new("Frame")
		left.Name = "Reglages"
		left.BackgroundTransparency = 1
		left.Size = UDim2.new(0.57, -8, 1, 0)
		left.Parent = content

		roleLabel = Label.new({
			name = "Role",
			style = "Small",
			font = "Bold",
			color = Theme.Colors.PaperDim,
			size = UDim2.new(1, 0, 0, 22),
			truncate = true,
			parent = left,
		})

		settingsList = Grid.list({
			name = "ListeReglages",
			gap = Theme.Spacing.S,
			position = UDim2.fromOffset(0, 26),
			size = UDim2.new(1, 0, 1, -26),
			parent = left,
		})

		local modes = (ruleOf("mode").values or { "FreeForAll", "Teams", "Solo", "Training" }) :: { string }
		local winds = (ruleOf("wind").values or { "Off", "Light", "Strong", "Random" }) :: { string }
		local frequencies = (ruleOf("itemFrequency").values or { "Low", "Normal", "High" }) :: { string }

		sectionHeader("menu.host.sectionGame", 1)
		addCycler("mode", 2, enumOptions(modes, "match.mode."), defaults.mode)
		playlistControl = addCycler("playlist", 3, playlistOptions(defaults.playlist), defaults.playlist)
		addSlider("holeCount", 4, defaults.holeCount, holesText, true)
		addToggle("shuffle", 5, defaults.shuffle)
		addSlider("timeScale", 6, defaults.timeScale, multiplierText)
		sectionHeader("menu.host.sectionRules", 10)
		addCycler("wind", 11, enumOptions(winds, "lobby.value.wind."), defaults.wind)
		addSlider("gameSpeed", 12, defaults.gameSpeed, multiplierText)
		addToggle("itemsEnabled", 13, defaults.itemsEnabled)
		addCycler("itemFrequency", 14, enumOptions(frequencies, "lobby.value.itemFrequency."), defaults.itemFrequency)
		addToggle("ballCollisions", 15, defaults.ballCollisions)
		addToggle("friendlyFire", 16, defaults.friendlyFire)
		addToggle("lateJoin", 17, defaults.lateJoin)
		addToggle("experimental16", 18, defaults.experimental16)

		-- Colonne droite : joueurs et actions.
		local right = Instance.new("Frame")
		right.Name = "Joueurs"
		right.BackgroundTransparency = 1
		right.AnchorPoint = Vector2.new(1, 0)
		right.Position = UDim2.fromScale(1, 0)
		right.Size = UDim2.new(0.43, -8, 1, 0)
		right.Parent = content

		countLabel = Label.new({
			name = "Compte",
			style = "Heading",
			font = "Display",
			color = Theme.Colors.Paper,
			stroke = true,
			size = UDim2.new(1, 0, 0, 30),
			parent = right,
		})

		local actionsHeight = 4 * (Theme.Touch.Small + Theme.Touch.Lip) + 3 * Theme.Spacing.S + 26
		playersList = Grid.list({
			name = "ListeJoueurs",
			gap = 6,
			position = UDim2.fromOffset(0, 32),
			size = UDim2.new(1, 0, 1, -32 - actionsHeight),
			parent = right,
		})

		local actions = Instance.new("Frame")
		actions.Name = "Actions"
		actions.BackgroundTransparency = 1
		actions.AnchorPoint = Vector2.new(0, 1)
		actions.Position = UDim2.fromScale(0, 1)
		actions.Size = UDim2.new(1, 0, 0, actionsHeight)
		Base.list(actions, Enum.FillDirection.Vertical, Theme.Spacing.S, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)
		actions.Parent = right

		statusLabel = Label.new({
			name = "Statut",
			style = "Small",
			font = "Heavy",
			alignX = Enum.TextXAlignment.Center,
			color = Theme.Colors.PaperDim,
			size = UDim2.new(1, 0, 0, 20),
			truncate = true,
			layoutOrder = 1,
			parent = actions,
		})

		teamRow = Instance.new("Frame")
		teamRow.Name = "ChoixEquipe"
		teamRow.BackgroundTransparency = 1
		teamRow.Size = UDim2.new(1, 0, 0, Theme.Touch.Small + Theme.Touch.Lip)
		teamRow.LayoutOrder = 2
		local teamLayout = Instance.new("UIGridLayout")
		teamLayout.CellSize = UDim2.new(1 / 3, -6, 1, 0)
		teamLayout.CellPadding = UDim2.fromOffset(8, 0)
		teamLayout.SortOrder = Enum.SortOrder.LayoutOrder
		teamLayout.Parent = teamRow
		teamRow.Parent = actions
		for index, team in MatchConfig.Lobby.TeamChoices do
			local style = Theme.team(team)
			teamButtons[team] = Button.new({
				name = "Equipe" .. team,
				key = if style then style.labelKey else "lobby.team.Auto",
				icon = if style then style.glyph else "⇄",
				variant = "Dark",
				size = "Small",
				fill = true,
				layoutOrder = index,
				parent = teamRow,
				onActivated = function()
					send("Lobby.SetTeam", team)
				end,
			})
		end

		readyButton = Button.new({
			name = "Pret",
			key = "lobby.action.ready",
			icon = "✓",
			variant = "Success",
			size = "Small",
			fill = true,
			layoutOrder = 3,
			parent = actions,
			onActivated = function()
				localReady = not localReady
				localReadyPendingUntil = os.clock() + 2
				send("Lobby.SetReady", localReady)
				screen._refreshActions()
			end,
		})

		hostRow = Instance.new("Frame")
		hostRow.Name = "Hote"
		hostRow.BackgroundTransparency = 1
		hostRow.Size = UDim2.new(1, 0, 0, Theme.Touch.Small + Theme.Touch.Lip)
		hostRow.LayoutOrder = 4
		local hostLayout = Instance.new("UIGridLayout")
		hostLayout.CellSize = UDim2.new(0.5, -4, 1, 0)
		hostLayout.CellPadding = UDim2.fromOffset(8, 0)
		hostLayout.SortOrder = Enum.SortOrder.LayoutOrder
		hostLayout.Parent = hostRow
		hostRow.Parent = actions

		balanceButton = Button.new({
			name = "Equilibrer",
			key = "lobby.action.balance",
			icon = "⇄",
			variant = "Secondary",
			size = "Small",
			fill = true,
			layoutOrder = 1,
			parent = hostRow,
			onActivated = function()
				send("Lobby.BalanceTeams")
			end,
		})
		cancelButton = Button.new({
			name = "Annuler",
			key = "lobby.action.cancel",
			icon = "✕",
			variant = "Danger",
			size = "Small",
			fill = true,
			layoutOrder = 2,
			parent = hostRow,
			onActivated = function()
				send("Lobby.Cancel")
			end,
		})

		startButton = Button.new({
			name = "Lancer",
			key = "lobby.action.start",
			icon = "▶",
			variant = "Primary",
			size = "Small",
			fill = true,
			layoutOrder = 5,
			parent = actions,
			onActivated = function()
				send("Lobby.Advance")
			end,
		})
	end

	----------------------------------------------------------------------------
	-- Rafraîchissement
	----------------------------------------------------------------------------

	local function playerRow(entry: any, index: number, hostId: number, localId: number, teamsMode: boolean)
		local isLocal = entry.userId == localId
		local row = Instance.new("Frame")
		row.Name = "Joueur" .. index
		row.BorderSizePixel = 0
		row.BackgroundColor3 = if isLocal then Theme.Colors.NightHover else Theme.Colors.NightRaised
		row.Size = UDim2.new(1, -10, 0, 48)
		row.LayoutOrder = (if entry.userId == hostId then 0 else 10) + index
		Base.corner(row, "Medium")
		Base.stroke(row, if isLocal then Theme.Colors.Primary else Theme.Colors.Ink, if isLocal then Theme.StrokeWidth.Normal else Theme.StrokeWidth.Thin)
		Base.padding(row, nil, 8, 0)
		Base.list(row, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		row.Parent = playersList.Instance

		-- Prêt : glyphe + texte (jamais la couleur seule).
		local ready = entry.ready == true
		local chip = Instance.new("Frame")
		chip.Name = "Pret"
		chip.BorderSizePixel = 0
		chip.BackgroundColor3 = if entry.spectator then Theme.Colors.Secondary elseif ready then Theme.Colors.Success else Theme.Colors.Disabled
		chip.Size = UDim2.fromOffset(30, 30)
		chip.LayoutOrder = 1
		Base.corner(chip, "Pill")
		Base.stroke(chip, Theme.Colors.Ink, Theme.StrokeWidth.Thin)
		chip.Parent = row
		local glyph = Base.newText("Glyphe", "Body", "Display", Theme.textOn(chip.BackgroundColor3))
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		glyph.Text = if entry.spectator then "◉" elseif ready then "✓" else "…"
		glyph.Parent = chip

		local name = Base.newText("Nom", "Body", "Heavy", Theme.Colors.Paper)
		name.Size = UDim2.new(1, -(if teamsMode then 230 else 150), 1, 0)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.LayoutOrder = 2
		name.Text = Util.playerName(entry.userId, entry.name)
		name.Parent = row

		local function tag(textKey: string, color: Color3, order: number)
			local frame = Instance.new("Frame")
			frame.Name = "Etiquette"
			frame.BorderSizePixel = 0
			frame.BackgroundColor3 = color
			frame.AutomaticSize = Enum.AutomaticSize.X
			frame.Size = UDim2.fromOffset(0, 22)
			frame.LayoutOrder = order
			Base.corner(frame, "Pill")
			Base.padding(frame, nil, 6, 0)
			frame.Parent = row
			local text = Base.newText("Texte", "Caption", "Heavy", Theme.textOn(color))
			text.AutomaticSize = Enum.AutomaticSize.X
			text.Size = UDim2.fromOffset(0, 22)
			Base.setText(text, nil, textKey, nil)
			text.Parent = frame
		end
		if entry.userId == hostId then
			tag("menu.host.hostTag", Theme.Colors.Primary, 3)
		end
		if isLocal then
			tag("menu.host.youTag", Theme.Colors.Secondary, 4)
		end
		if entry.spectator then
			tag("ui.spectator", Theme.Colors.Disabled, 5)
		elseif teamsMode then
			TeamMarker.new({ team = entry.team, size = "Small", layoutOrder = 6, parent = row })
		end
	end

	local function refreshActions()
		local teamsMode = state and type(state.settings) == "table" and state.settings.mode == "Teams"
		readyButton.SetKey(if localReady then "lobby.action.unready" else "lobby.action.ready")
		readyButton.SetVariant(if localReady then "Warning" else "Success")
		readyButton.SetIcon(if localReady then "✕" else "✓")
		teamRow.Visible = teamsMode == true
		hostRow.Visible = isHost
		balanceButton.SetEnabled(isHost and teamsMode == true)
		cancelButton.SetEnabled(isHost)
		startButton.Instance.Visible = isHost
		local canStart = if state and state.canStart ~= nil then state.canStart == true else true
		startButton.SetEnabled(isHost and canStart)
		if canStart and isHost then
			statusLabel.SetKey("menu.host.canStart")
			statusLabel.SetColor(Theme.Colors.Success)
		else
			statusLabel.SetKey("menu.host.waitingReady")
			statusLabel.SetColor(Theme.Colors.PaperDim)
		end
	end
	screen._refreshActions = refreshActions

	local function render(newState: any)
		if type(newState) ~= "table" then
			return
		end
		state = newState
		local localId = Util.localPlayer().UserId
		local hostId = tonumber(state.hostUserId) or 0
		isHost = hostId == localId
		local settings = if type(state.settings) == "table" then state.settings else {}

		roleLabel.SetKey(if isHost then "lobby.youAreHost" else "menu.host.readOnly")
		roleLabel.SetColor(if isHost then Theme.Colors.Primary else Theme.Colors.PaperDim)

		-- Contrôles : valeurs du serveur (sans renvoyer de message) et lecture seule hors hôte.
		playlistControl.SetOptions(playlistOptions(settings.playlist), settings.playlist)
		for _, control in controls do
			local value = settings[control.key]
			if value ~= nil then
				control.Set(value, true)
			end
			local enabled = isHost
			if control.key == "friendlyFire" and settings.mode == "Teams" then
				enabled = false
			elseif control.key == "itemFrequency" and settings.itemsEnabled == false then
				enabled = false
			end
			control.SetEnabled(enabled)
		end

		-- Joueurs.
		playersList.Clear()
		local players = if type(state.players) == "table" then state.players else {}
		local teamsMode = settings.mode == "Teams"
		local readyCount, total = 0, 0
		for index, entry in players do
			if type(entry) ~= "table" then
				continue
			end
			if not entry.spectator then
				total += 1
				if entry.ready then
					readyCount += 1
				end
			end
			if entry.userId == localId and os.clock() > localReadyPendingUntil then
				localReady = entry.ready == true
			end
			playerRow(entry, index, hostId, localId, teamsMode)
		end
		countLabel.SetText(Locale.t("lobby.players", { count = #players }) .. "   ·   " .. Locale.t("lobby.readyCount", { ready = readyCount, total = total }))

		-- Équipe du joueur local (bouton en couleur vive).
		local myTeam = Util.localPlayer():GetAttribute("Team")
		for _, entry in players do
			if type(entry) == "table" and entry.userId == localId and type(entry.team) == "string" then
				myTeam = entry.team
			end
		end
		for team, button in teamButtons do
			local selected = team == myTeam or (team == "Auto" and (myTeam == nil or myTeam == ""))
			local style = Theme.team(team)
			button.SetVariant(if selected then (if team == "Red" then "Danger" elseif team == "Blue" then "Secondary" else "Primary") else "Dark")
			local _ = style
		end
		refreshActions()
	end

	function screen.Show(_self: any, args: any, wasVisible: boolean)
		render(if type(args) == "table" then args else ctx.GetLobbyState())
		if wasVisible then
			return
		end
		showTrove:Clean()
		modal.Open()
		settingsList.ScrollToTop()
		showTrove:Connect(ctx.LobbyChanged, function(newState: any)
			render(newState)
		end)
		-- État reconstruit (aucun Lobby.State reçu) : rafraîchi régulièrement depuis les attributs.
		showTrove:Add(task.spawn(function()
			while true do
				task.wait(FALLBACK_REFRESH)
				local current = ctx.GetLobbyState()
				if type(current) == "table" and current.fallback then
					render(current)
				end
			end
		end))
	end

	function screen.Hide(_self: any): number?
		showTrove:Clean()
		return modal.Close()
	end

	function screen.GetDefaultSelection(_self: any): GuiObject?
		if isHost then
			local mode = controlByKey.mode
			return if mode then mode.Instance else readyButton.Instance
		end
		return readyButton.Instance
	end

	function screen.Destroy(_self: any)
		showTrove:Clean()
	end

	return screen
end

return HostSettings
