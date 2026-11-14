--!strict
--[[
	UIController — racine de l'interface (contrat docs/ARCHITECTURE.md §9).

	Crée le ScreenManager, enregistre les écrans (UI/Screens/*), suit la phase de la partie (attribut
	GameState.Phase) et affiche l'écran correspondant :
	  Lobby        bannière de phase (+ bouton menu de MenuController) ; menu principal à la demande
	  Preparing    salon de l'hôte (HostSettings) + bannière
	  Loading      voile de chargement           HoleIntro    présentation du trou
	  Countdown    3-2-1-PARTEZ                   Playing / HoleEnd : rien (le HUD appartient à HUDController)
	  HoleResults  tableau du trou                Podium       podium final et récompenses
	Arrivée tardive : la phase courante est lue au démarrage. Core.ClientReady est envoyé une fois l'interface
	construite.

	API :
	  UIController.Screens / GetScreenManager()        le module ScreenManager
	  UIController.GetPhase() -> string
	  UIController.GetLobbyState() -> table?           dernier Lobby.State (ou état reconstruit depuis les attributs)
	  UIController.GetHoleResults() / GetPodium() / GetReward()   derniers messages reçus
	  UIController.LobbyChanged / HoleResultsReceived / PodiumReceived / RewardReceived / PhaseChanged : Signals
	  UIController.Ready : Signal()  /  UIController.IsReady()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Log = require(Shared.Util.Log)
local GameState = require(Shared.Util.GameState)
local MatchConfig = require(Shared.Config.Match)

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI.Theme)
local ScreenManager = require(UI.ScreenManager)

local UIController = {}
UIController.Priority = 10

UIController.Screens = ScreenManager
UIController.LobbyChanged = Signal.new()
UIController.HoleResultsReceived = Signal.new()
UIController.PodiumReceived = Signal.new()
UIController.RewardReceived = Signal.new()
UIController.PhaseChanged = Signal.new()
UIController.Ready = Signal.new()

-- Écrans enregistrés (nom = nom du module dans UI/Screens).
local SCREEN_MODULES = {
	"PhaseBanner",
	"Loading",
	"HoleIntro",
	"Countdown",
	"HoleResults",
	"Podium",
	"LobbyMenu",
	"HostSettings",
	"Settings",
	"Shop",
	"Customize",
	"Challenges",
	"Emotes",
}

-- Écran propre à chaque phase.
local PHASE_SCREEN: { [string]: string } = {
	Preparing = "HostSettings",
	Loading = "Loading",
	HoleIntro = "HoleIntro",
	Countdown = "Countdown",
	HoleResults = "HoleResults",
	Podium = "Podium",
}

-- Écrans liés à une phase : masqués dès que la phase change.
local TRANSIENT = { "Loading", "HoleIntro", "Countdown", "HoleResults", "Podium" }

local BANNER_PHASES: { [string]: boolean } = { Lobby = true, Preparing = true }

local cache = {
	lobby = nil :: any,
	holeResults = nil :: any,
	podium = nil :: any,
	reward = nil :: any,
}
local phase = "Lobby"
local ready = false

--------------------------------------------------------------------------------
-- État du salon (dernier Lobby.State, sinon reconstruit depuis les attributs répliqués)
--------------------------------------------------------------------------------

local function decodeSettings(): any
	local json = GameState.read("SettingsJson")
	if type(json) == "string" and json ~= "" then
		local ok, decoded = pcall(function()
			return game:GetService("HttpService"):JSONDecode(json)
		end)
		if ok and type(decoded) == "table" then
			return decoded
		end
	end
	return table.clone(MatchConfig.DefaultSettings :: any)
end

local function fallbackLobbyState(): any
	local players = {}
	for _, player in Players:GetPlayers() do
		local team = player:GetAttribute("Team")
		table.insert(players, {
			userId = player.UserId,
			name = player.DisplayName,
			ready = player:GetAttribute("Ready") == true,
			team = if type(team) == "string" and team ~= "" then team else nil,
			spectator = player:GetAttribute("Spectating") == true,
		})
	end
	local host = GameState.read("HostUserId")
	return {
		hostUserId = if type(host) == "number" then host else 0,
		settings = decodeSettings(),
		players = players,
		canStart = nil, -- inconnu : le serveur décidera
		fallback = true,
	}
end

function UIController.GetLobbyState(): any
	return cache.lobby or fallbackLobbyState()
end

function UIController.GetHoleResults(): any
	return cache.holeResults
end

function UIController.GetPodium(): any
	return cache.podium
end

function UIController.GetReward(): any
	return cache.reward
end

function UIController.GetPhase(): string
	return phase
end

function UIController.GetScreenManager(): any
	return ScreenManager
end

function UIController.IsReady(): boolean
	return ready
end

--------------------------------------------------------------------------------
-- Phases
--------------------------------------------------------------------------------

local function argsFor(name: string): any
	if name == "HoleResults" then
		return cache.holeResults
	elseif name == "Podium" then
		return cache.podium
	elseif name == "HostSettings" then
		return UIController.GetLobbyState()
	end
	return nil
end

local function applyPhase(newPhase: string, oldPhase: string?)
	local target = PHASE_SCREEN[newPhase]
	for _, name in TRANSIENT do
		if name ~= target then
			ScreenManager.Hide(name)
		end
	end
	if newPhase ~= "Preparing" then
		ScreenManager.Hide("HostSettings")
	end
	if newPhase ~= "Lobby" and newPhase ~= "Preparing" and (oldPhase == "Lobby" or oldPhase == "Preparing") then
		-- La partie démarre : on referme le menu principal.
		ScreenManager.Hide("LobbyMenu")
	end
	if BANNER_PHASES[newPhase] then
		ScreenManager.Show("PhaseBanner", newPhase)
	else
		ScreenManager.Hide("PhaseBanner")
	end
	if target and (target ~= "HostSettings" or oldPhase ~= "Preparing") then
		ScreenManager.Show(target, argsFor(target))
	end
end

local function onPhase(value: any)
	local newPhase = if type(value) == "string" and value ~= "" then value else "Lobby"
	if newPhase == phase and ready then
		return
	end
	local old = phase
	phase = newPhase
	if newPhase == "Loading" and old ~= "HoleResults" and old ~= "Loading" then
		-- Nouvelle partie : les résultats précédents ne doivent plus s'afficher.
		cache.podium = nil
		cache.reward = nil
	end
	applyPhase(newPhase, old)
	UIController.PhaseChanged:Fire(newPhase, old)
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

local function listen(name: string, handler: (...any) -> ())
	if not Net.getDefinitions()[name] then
		Log.warn("UI", "remote absent :", name)
		return
	end
	local ok, err = pcall(Net.listen, name, handler)
	if not ok then
		Log.warn("UI", "écoute impossible :", name, err)
	end
end

local function trackViewport()
	local cameraConnection: RBXScriptConnection? = nil
	local function bindCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		Theme.updateViewport(camera.ViewportSize)
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			Theme.updateViewport(camera.ViewportSize)
		end)
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	bindCamera()
end

function UIController.Init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui", 30)
	if not playerGui then
		error("PlayerGui introuvable")
	end
	ScreenManager.SetRoot(playerGui)
	Theme.bindSettings()

	local ctx = {
		Manager = ScreenManager,
		GetLobbyState = UIController.GetLobbyState,
		GetHoleResults = UIController.GetHoleResults,
		GetPodium = UIController.GetPodium,
		GetReward = UIController.GetReward,
		GetPhase = UIController.GetPhase,
		LobbyChanged = UIController.LobbyChanged,
		HoleResultsReceived = UIController.HoleResultsReceived,
		PodiumReceived = UIController.PodiumReceived,
		RewardReceived = UIController.RewardReceived,
		PhaseChanged = UIController.PhaseChanged,
	}

	local screensFolder = UI:FindFirstChild("Screens")
	for _, name in SCREEN_MODULES do
		local module = screensFolder and screensFolder:FindFirstChild(name)
		if not module or not module:IsA("ModuleScript") then
			Log.warn("UI", "écran manquant :", name)
			continue
		end
		local ok, result = xpcall(require, debug.traceback, module)
		if not ok or type(result) ~= "table" or type(result.new) ~= "function" then
			Log.error("UI", "écran illisible :", name, result)
			continue
		end
		local built, screen = xpcall(result.new, debug.traceback, ctx)
		if built and type(screen) == "table" then
			ScreenManager.Register(name, screen)
		else
			Log.error("UI", "écran non créé :", name, screen)
		end
	end
end

function UIController.Start()
	trackViewport()

	listen("Lobby.State", function(state: any)
		if type(state) ~= "table" then
			return
		end
		cache.lobby = state
		UIController.LobbyChanged:Fire(state)
	end)
	listen("Match.HoleResults", function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		cache.holeResults = payload
		UIController.HoleResultsReceived:Fire(payload)
		if ScreenManager.IsVisible("HoleResults") then
			ScreenManager.Show("HoleResults", payload)
		end
	end)
	listen("Match.Podium", function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		cache.podium = payload
		UIController.PodiumReceived:Fire(payload)
		if ScreenManager.IsVisible("Podium") then
			ScreenManager.Show("Podium", payload)
		end
	end)
	listen("Progress.MatchReward", function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		cache.reward = payload
		UIController.RewardReceived:Fire(payload)
	end)

	-- Focus manette : quand le joueur reprend la manette, la modale ouverte récupère la sélection.
	local input = script.Parent:FindFirstChild("InputController")
	if input and input:IsA("ModuleScript") then
		local ok, module = pcall(require, input)
		if ok and type(module) == "table" and module.DeviceChanged then
			module.DeviceChanged:Connect(function(device: any)
				if device == "Gamepad" then
					ScreenManager.FocusTop()
				end
			end)
			-- Boutons tactiles de jeu masqués tant qu'une modale (menu, réglages, salon) est ouverte.
			if type(module.SetTouchControlsSuppressed) == "function" then
				ScreenManager.Changed:Connect(function()
					pcall(module.SetTouchControlsSuppressed, "UIModal", ScreenManager.GetTopModal() ~= nil)
				end)
			end
		end
	end

	local okState, folder = pcall(GameState.get)
	if okState and folder then
		folder:GetAttributeChangedSignal("Phase"):Connect(function()
			onPhase(folder:GetAttribute("Phase"))
		end)
		onPhase(folder:GetAttribute("Phase"))
	else
		Log.warn("UI", "GameState indisponible : interface d'accueil par défaut")
		onPhase("Lobby")
	end

	ready = true
	UIController.Ready:Fire()
	if Net.getDefinitions()["Core.ClientReady"] then
		pcall(Net.send, "Core.ClientReady")
	end
end

return UIController
