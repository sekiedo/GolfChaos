--!strict
--[[
	HUDController — interface en jeu (priorité 40), widgets dans client/UI/Hud/*.

	  Carte du trou (n/N, nom localisé "hole.<id>.name" sinon GameState.HoleName, par, coups du joueur),
	  chronomètre de phase (PhaseEndsAt, heure serveur) + bandeau de prolongation (OvertimeEndsAt),
	  vent (flèche relative à la caméra + force), distance de sa balle au trou (CupPosition), position dans la
	  course (arrivés d'abord par ordre d'arrivée, puis distance au trou), tableau des scores compact
	  (nom, glyphe + couleur d'équipe, coups, coche), fil d'événements (Golf.Holed, Match.PlayerFinished,
	  Combat.KO), barre d'aide des commandes adaptée à l'appareil, cases d'objets (attributs Inventory /
	  SelectedSlot / InventoryCapacity).
	  Visible pendant HoleIntro / Countdown / Playing / HoleEnd ; à l'accueil, seul un panneau fin
	  d'entraînement est montré quand l'attribut joueur Practice est vrai (ou quand sa balle est une balle
	  d'entraînement). La barre d'aide et les objets se masquent pendant la visée (UI/AimPanel prend le relais).

	API : ShowToast(texte, genre?)   PushFeed(texte, genre?)   SetVisibleOverride(visible?)   IsMatchHudVisible()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trove = require(Shared.Util.Trove)
local Log = require(Shared.Util.Log)
local GameState = require(Shared.Util.GameState)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local Gameplay = require(Shared.Config.Gameplay)

local InputController = require(script.Parent.InputController)

local ClientRoot = script.Parent.Parent
local UI = ClientRoot:WaitForChild("UI")
local Theme = require(UI.Theme)

local HUDController = {}
HUDController.Priority = 40

local MATCH_PHASES: { [string]: boolean } = { HoleIntro = true, Countdown = true, Playing = true, HoleEnd = true }
local LOBBY_PHASES: { [string]: boolean } = { Lobby = true, Preparing = true }
local FAST_TICK = 0.1
local SLOW_TICK = 0.5
local DUPLICATE_WINDOW = 4 -- s : Match.PlayerFinished juste après Golf.Holed du même joueur n'est pas répété

local localPlayer = Players.LocalPlayer

type Widgets = {
	holeCard: any,
	timer: any,
	info: any,
	scoreboard: any,
	feed: any,
	controls: any,
	inventory: any,
	practice: any,
}

local state = {
	initialized = false,
	started = false,
	gameState = nil :: Folder?,
	gui = nil :: ScreenGui?,
	matchLayer = nil :: Frame?,
	widgets = nil :: Widgets?,
	override = nil :: boolean?,
	fastTimer = 0,
	slowTimer = 0,
	recentHoled = {} :: { [number]: number },
	aiming = false,
}

local runtimeTrove = Trove.new()

--------------------------------------------------------------------------------
-- Aides
--------------------------------------------------------------------------------

local function readGame(name: string): any
	local folder = state.gameState
	return if folder then folder:GetAttribute(name) else nil
end

local function phase(): string
	local value = readGame("Phase")
	return if type(value) == "string" then value else "Lobby"
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function requireWidget(name: string): any
	local folder = UI:FindFirstChild("Hud")
	local module = if folder then folder:FindFirstChild(name) else nil
	if not module or not module:IsA("ModuleScript") then
		Log.warn("HUD", "widget introuvable :", name)
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		Log.warn("HUD", "widget illisible :", name, result)
		return nil
	end
	return result
end

local function newWidget(name: string, ...: any): any
	local module = requireWidget(name)
	if not module or type(module.new) ~= "function" then
		return nil
	end
	local ok, widget = pcall(module.new, ...)
	if not ok then
		Log.warn("HUD", "création du widget en erreur :", name, widget)
		return nil
	end
	return widget
end

local function call(widget: any, method: string, ...: any)
	if widget and type(widget[method]) == "function" then
		local ok, err = pcall(widget[method], ...)
		if not ok then
			Log.debug("HUD", method, err)
		end
	end
end

local optionalCache: { [string]: any } = {}
local function optionalController(name: string): any
	local cached = optionalCache[name]
	if cached ~= nil then
		return cached or nil
	end
	local module = script.Parent:FindFirstChild(name)
	local result: any = false
	if module and module:IsA("ModuleScript") then
		local ok, loaded = pcall(require, module)
		if ok and type(loaded) == "table" then
			result = loaded
		end
	end
	optionalCache[name] = result
	return result or nil
end

local function playerName(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.DisplayName
	end
	return Locale.t("hud.feed.someone")
end

local function teamsMode(): boolean
	return readGame("Mode") == "Teams"
end

local function ballsFolder(): Instance?
	return Workspace:FindFirstChild(Gameplay.Ball.FolderName)
end

-- Balle de chaque joueur (par UserId).
local function ballsByOwner(): { [number]: BasePart }
	local map: { [number]: BasePart } = {}
	local folder = ballsFolder()
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") then
				local owner = child:GetAttribute("OwnerUserId")
				if type(owner) == "number" then
					map[owner] = child
				end
			end
		end
	end
	return map
end

local function ownBallIsPractice(): boolean
	local ball = ballsByOwner()[localPlayer.UserId]
	return ball ~= nil and ball:GetAttribute("Practice") == true
end

--------------------------------------------------------------------------------
-- Classement de course
--------------------------------------------------------------------------------

type Standing = {
	player: Player,
	finished: boolean,
	order: number,
	distance: number,
	strokes: number,
}

local function participants(): { Player }
	local list = {}
	local flagged = false
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Participant") == true then
			flagged = true
			table.insert(list, player)
		end
	end
	if not flagged then
		-- Aucun participant déclaré (test en solo) : tous les joueurs non spectateurs.
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("Spectating") ~= true then
				table.insert(list, player)
			end
		end
	end
	return list
end

local function computeStandings(): { Standing }
	local cup = readGame("CupPosition")
	local balls = ballsByOwner()
	local list: { Standing } = {}
	for _, player in participants() do
		local finished = player:GetAttribute("HoleFinished") == true
		local order = player:GetAttribute("FinishOrder")
		local strokes = player:GetAttribute("Strokes")
		local ball = balls[player.UserId]
		local distance = math.huge
		if typeof(cup) == "Vector3" and ball then
			local offset = ball.Position - cup
			distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
		end
		table.insert(list, {
			player = player,
			finished = finished,
			order = if type(order) == "number" and order > 0 then order else math.huge,
			distance = distance,
			strokes = if type(strokes) == "number" then strokes else 0,
		})
	end
	table.sort(list, function(a, b)
		if a.finished ~= b.finished then
			return a.finished
		end
		if a.finished then
			if a.order ~= b.order then
				return a.order < b.order
			end
			return a.strokes < b.strokes
		end
		if a.distance ~= b.distance then
			return a.distance < b.distance
		end
		return a.player.UserId < b.player.UserId
	end)
	return list
end

--------------------------------------------------------------------------------
-- Rafraîchissements
--------------------------------------------------------------------------------

local function refreshHole()
	local widgets = state.widgets
	if not widgets then
		return
	end
	local index = readGame("HoleIndex")
	local count = readGame("HoleCount")
	call(widgets.holeCard, "SetHole", if type(index) == "number" then index else nil, if type(count) == "number" then count else nil)
	local holeId = readGame("HoleId")
	local name = ""
	if type(holeId) == "string" and holeId ~= "" then
		local key = "hole." .. holeId .. ".name"
		if Locale.has(key) or Locale.has(key, "fr") then
			name = Locale.t(key)
		end
	end
	if name == "" then
		local fallback = readGame("HoleName")
		name = if type(fallback) == "string" then fallback else ""
	end
	call(widgets.holeCard, "SetName", name)
	local par = readGame("HolePar")
	call(widgets.holeCard, "SetPar", if type(par) == "number" then par else nil)
end

local function refreshStrokes()
	local widgets = state.widgets
	if not widgets then
		return
	end
	local strokes = localPlayer:GetAttribute("Strokes")
	local value = if type(strokes) == "number" then strokes else 0
	call(widgets.holeCard, "SetStrokes", value)
	call(widgets.practice, "SetStrokes", value)
end

local function refreshWind()
	local widgets = state.widgets
	if not widgets then
		return
	end
	local wind = readGame("Wind")
	call(widgets.info, "SetWind", if typeof(wind) == "Vector3" then wind else nil)
end

local function refreshInventory()
	local widgets = state.widgets
	if not widgets then
		return
	end
	local raw = localPlayer:GetAttribute("Inventory")
	local ids: { string } = {}
	if type(raw) == "string" and raw ~= "" then
		ids = string.split(raw, ",")
	end
	local capacity = localPlayer:GetAttribute("InventoryCapacity")
	local selected = localPlayer:GetAttribute("SelectedSlot")
	local cap = if type(capacity) == "number" then capacity elseif #ids > 0 then #ids else 0
	call(widgets.inventory, "SetSlots", ids, cap, if type(selected) == "number" then selected else 0)
end

local function keyLabel(action: string, fallback: Enum.KeyCode?): string
	local ok, label = pcall(InputController.GetKeyLabel, action)
	if ok and type(label) == "string" and label ~= "" then
		return label
	end
	if fallback then
		return InputController.GetKeyCodeLabel(fallback)
	end
	return "?"
end

local function refreshControls()
	local widgets = state.widgets
	if not widgets then
		return
	end
	local device = InputController.GetDevice()
	local text: string
	if device == "Touch" then
		text = Locale.t("hud.controls.touch", {
			aim = Locale.t("controls.action.aim"),
			punch = Locale.t("controls.action.punch"),
			dive = Locale.t("controls.action.dive"),
		})
	elseif device == "Gamepad" then
		text = Locale.t("hud.controls.gamepad", {
			jump = InputController.GetKeyCodeLabel(Enum.KeyCode.ButtonA),
			aim = keyLabel("GolfAim", Enum.KeyCode.ButtonL2),
			punch = keyLabel("CombatPunch", Enum.KeyCode.ButtonB),
			dive = keyLabel("CombatDive", Enum.KeyCode.ButtonX),
			reset = keyLabel("GolfResetBall", Enum.KeyCode.ButtonY),
		})
	else
		local move = InputController.GetKeyCodeLabel(Enum.KeyCode.W)
			.. InputController.GetKeyCodeLabel(Enum.KeyCode.A)
			.. InputController.GetKeyCodeLabel(Enum.KeyCode.S)
			.. InputController.GetKeyCodeLabel(Enum.KeyCode.D)
		text = Locale.t("hud.controls.kbm", {
			move = move,
			jump = InputController.GetKeyCodeLabel(Enum.KeyCode.Space),
			aim = keyLabel("GolfAim", Enum.KeyCode.E),
			punch = keyLabel("CombatPunch", Enum.KeyCode.F),
			dive = keyLabel("CombatDive", Enum.KeyCode.Q),
			reset = keyLabel("GolfResetBall", Enum.KeyCode.G),
		})
	end
	call(widgets.controls, "SetText", text)
end

local function isMatchVisible(): boolean
	if state.override ~= nil then
		return state.override :: boolean
	end
	return MATCH_PHASES[phase()] == true
end

local function refreshVisibility()
	local widgets = state.widgets
	local layer = state.matchLayer
	if not widgets or not layer then
		return
	end
	local matchVisible = isMatchVisible()
	layer.Visible = matchVisible
	local practice = LOBBY_PHASES[phase()] == true
		and (localPlayer:GetAttribute("Practice") == true or ownBallIsPractice())
		and state.override ~= false
	call(widgets.practice, "SetVisible", practice)
	call(widgets.controls, "SetVisible", not state.aiming and (matchVisible or practice))
	call(widgets.inventory, "SetVisible", not state.aiming and matchVisible)
	if not state.aiming and matchVisible then
		refreshInventory()
	end
end

-- Chronomètre, distance, position (toutes les 0,1 s).
local function fastTick()
	local widgets = state.widgets
	if not widgets or not isMatchVisible() then
		return
	end
	local now = serverNow()
	local endsAt = readGame("PhaseEndsAt")
	local remaining: number? = nil
	if type(endsAt) == "number" and endsAt > 0 then
		remaining = math.max(0, endsAt - now)
	end
	call(widgets.timer, "SetTime", remaining)
	local overtimeEnds = readGame("OvertimeEndsAt")
	local overtime: number? = nil
	if type(overtimeEnds) == "number" and overtimeEnds > now then
		overtime = overtimeEnds - now
	end
	call(widgets.timer, "SetOvertime", overtime)

	local cup = readGame("CupPosition")
	local ball = ballsByOwner()[localPlayer.UserId]
	if typeof(cup) == "Vector3" and ball and ball:GetAttribute("State") ~= "Holed" then
		local offset = ball.Position - cup
		call(widgets.info, "SetDistance", Vector3.new(offset.X, 0, offset.Z).Magnitude)
	else
		call(widgets.info, "SetDistance", nil)
	end
end

-- Classement et tableau des scores (toutes les 0,5 s).
local function slowTick()
	local widgets = state.widgets
	if not widgets or not isMatchVisible() then
		return
	end
	local standings = computeStandings()
	local rows = {}
	local myRank: number? = nil
	local myFinished = false
	local teams = teamsMode()
	for index, standing in standings do
		local player = standing.player
		if player == localPlayer then
			myRank = index
			myFinished = standing.finished
		end
		local team = player:GetAttribute("Team")
		table.insert(rows, {
			userId = player.UserId,
			name = player.DisplayName,
			team = if teams and type(team) == "string" and team ~= "" then team else nil,
			strokes = standing.strokes,
			finished = standing.finished,
			isLocal = player == localPlayer,
		})
	end
	call(widgets.scoreboard, "SetRows", rows)
	call(widgets.info, "SetPosition", myRank, #standings, myFinished)
end

--------------------------------------------------------------------------------
-- Événements ponctuels
--------------------------------------------------------------------------------

local function onHoled(userId: any, info: any)
	if type(userId) ~= "number" then
		return
	end
	local data = if type(info) == "table" then info else {}
	if data.practice == true then
		return -- coups d'entraînement : pas d'annonce
	end
	state.recentHoled[userId] = os.clock()
	local name = playerName(userId)
	local strokes = if type(data.strokes) == "number" then data.strokes else 0
	local text: string
	local kind = "holed"
	if data.holeInOne == true then
		text = Locale.t("hud.feed.holeInOne", { name = name })
		kind = "best"
	elseif strokes == 1 then
		text = Locale.t("hud.feed.holedOne", { name = name })
	else
		text = Locale.t("hud.feed.holed", { name = name, n = strokes })
	end
	call(state.widgets and state.widgets.feed, "Push", text, kind)
end

local function onPlayerFinished(data: any)
	if type(data) ~= "table" or type(data.userId) ~= "number" then
		return
	end
	local recent = state.recentHoled[data.userId]
	if recent and os.clock() - recent < DUPLICATE_WINDOW then
		return
	end
	local name = if type(data.name) == "string" then data.name else playerName(data.userId)
	local order = if type(data.finishOrder) == "number" then data.finishOrder else 0
	local strokes = if type(data.strokes) == "number" then data.strokes else 0
	local text = Locale.t("hud.feed.finished", {
		name = name,
		order = if order > 0 then Locale.t("hud.ordinal.n", { n = order }) else "",
		n = strokes,
	})
	if order > 0 then
		local key = "hud.ordinal." .. order
		if Locale.has(key) then
			text = Locale.t("hud.feed.finished", { name = name, order = Locale.t(key), n = strokes })
		end
	end
	call(state.widgets and state.widgets.feed, "Push", text, "holed")
end

local function onKO(victimId: any, attackerId: any, _source: any)
	if type(victimId) ~= "number" then
		return
	end
	local victim = playerName(victimId)
	local text: string
	if type(attackerId) == "number" and attackerId ~= 0 and attackerId ~= victimId then
		text = Locale.t("hud.feed.ko", { attacker = playerName(attackerId), victim = victim })
	else
		text = Locale.t("hud.feed.koAlone", { victim = victim })
	end
	call(state.widgets and state.widgets.feed, "Push", text, "ko")
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function build()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("HUD")
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 4
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	runtimeTrove:Add(gui)
	state.gui = gui

	local scale = Instance.new("UIScale")
	scale.Scale = Theme.getScale()
	scale.Parent = gui
	runtimeTrove:Connect(Theme.Changed, function(what: any)
		if what == "layout" then
			scale.Scale = Theme.getScale()
		end
	end)

	local matchLayer = Instance.new("Frame")
	matchLayer.Name = "Partie"
	matchLayer.BackgroundTransparency = 1
	matchLayer.Size = UDim2.fromScale(1, 1)
	matchLayer.Visible = false
	matchLayer.Parent = gui
	state.matchLayer = matchLayer

	local alwaysLayer = Instance.new("Frame")
	alwaysLayer.Name = "Toujours"
	alwaysLayer.BackgroundTransparency = 1
	alwaysLayer.Size = UDim2.fromScale(1, 1)
	alwaysLayer.Parent = gui

	local widgets: Widgets = {
		holeCard = newWidget("HoleCard", matchLayer),
		timer = newWidget("TimerBanner", matchLayer),
		info = newWidget("InfoPanel", matchLayer),
		scoreboard = newWidget("Scoreboard", matchLayer),
		feed = newWidget("Feed", matchLayer, alwaysLayer),
		controls = newWidget("ControlsBar", alwaysLayer),
		inventory = newWidget("Inventory", matchLayer),
		practice = newWidget("PracticePanel", alwaysLayer),
	}
	state.widgets = widgets
	gui.Parent = playerGui
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

function HUDController.ShowToast(text: string, kind: string?)
	local widgets = state.widgets
	call(widgets and widgets.feed, "Toast", text, kind)
end

function HUDController.PushFeed(text: string, kind: string?)
	local widgets = state.widgets
	call(widgets and widgets.feed, "Push", text, kind)
end

-- Force l'affichage (true), le masquage (false) ou revient à la règle des phases (nil). Ex. : écrans plein écran.
function HUDController.SetVisibleOverride(visible: boolean?)
	state.override = visible
	refreshVisibility()
end

function HUDController.IsMatchHudVisible(): boolean
	return isMatchVisible()
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function HUDController.Init()
	if state.initialized then
		return
	end
	state.initialized = true
	runtimeTrove:Add(Net.listen("Golf.Holed", onHoled))
	runtimeTrove:Add(Net.listen("Match.PlayerFinished", onPlayerFinished))
	runtimeTrove:Add(Net.listen("Combat.KO", onKO))
end

function HUDController.Start()
	if state.started then
		return
	end
	state.started = true
	build()

	local ok, folder = pcall(GameState.get)
	if ok and typeof(folder) == "Instance" then
		local gameState = folder :: Folder
		state.gameState = gameState
		runtimeTrove:Connect(gameState.AttributeChanged, function(name: string)
			if name == "Phase" then
				call(state.widgets and state.widgets.timer, "SetPhase", phase())
				if phase() == "HoleIntro" or phase() == "Loading" then
					call(state.widgets and state.widgets.feed, "Clear")
				end
				refreshVisibility()
				fastTick()
				slowTick()
			elseif name == "HoleIndex" or name == "HoleCount" or name == "HoleId" or name == "HoleName" or name == "HolePar" then
				refreshHole()
			elseif name == "Wind" then
				refreshWind()
			elseif name == "Mode" then
				slowTick()
			end
		end)
	else
		Log.warn("HUD", "GameState indisponible : HUD réduit")
	end

	for _, attribute in { "Strokes" } do
		runtimeTrove:Connect(localPlayer:GetAttributeChangedSignal(attribute), refreshStrokes)
	end
	for _, attribute in { "Inventory", "InventoryCapacity", "SelectedSlot" } do
		runtimeTrove:Connect(localPlayer:GetAttributeChangedSignal(attribute), refreshInventory)
	end
	runtimeTrove:Connect(localPlayer:GetAttributeChangedSignal("Practice"), refreshVisibility)
	runtimeTrove:Connect(InputController.DeviceChanged, refreshControls)
	Locale.onLanguageChanged(function()
		refreshHole()
		refreshControls()
		refreshStrokes()
		refreshWind()
	end)

	local aim = optionalController("GolfAimController")
	if aim and type(aim.StateChanged) == "table" then
		runtimeTrove:Connect(aim.StateChanged, function(mode: any)
			state.aiming = mode == "Aiming" or mode == "Charging"
			refreshVisibility()
		end)
	end

	runtimeTrove:Connect(RunService.Heartbeat, function(dt: number)
		state.fastTimer += dt
		state.slowTimer += dt
		if state.fastTimer >= FAST_TICK then
			state.fastTimer = 0
			fastTick()
		end
		if state.slowTimer >= SLOW_TICK then
			state.slowTimer = 0
			slowTick()
			-- Panneau d'entraînement : la balle d'entraînement peut apparaître sans changement d'attribut joueur.
			refreshVisibility()
		end
	end)
	runtimeTrove:Connect(RunService.RenderStepped, function()
		local widgets = state.widgets
		if widgets and isMatchVisible() then
			call(widgets.info, "Render")
		end
	end)

	call(state.widgets and state.widgets.timer, "SetPhase", phase())
	refreshHole()
	refreshStrokes()
	refreshWind()
	refreshControls()
	refreshInventory()
	refreshVisibility()
	fastTick()
	slowTick()
	-- Les libellés de touches dépendent des actions liées par les autres contrôleurs (Init) : rafraîchis ici.
	task.delay(1, refreshControls)
end

return HUDController
