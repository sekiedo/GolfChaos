--!strict
--[[
	MenuController — ouverture / fermeture des menus (contrat docs/ARCHITECTURE.md §9).

	  M (clavier), Start (manette) ou le bouton tactile « ☰ Menu » : ouvre / ferme le menu principal
	      (en préparation : le salon de la partie ; ailleurs : le menu principal, dont Réglages).
	  Échap / B : retour (ferme la modale du dessus via ScreenManager.Back) ; sans modale ouverte, l'entrée
	      passe aux autres actions (l'appareil garde son comportement par défaut).

	API :
	  MenuController.OpenMenu() / CloseMenu() / ToggleMenu()
	  MenuController.OpenSettings(onglet?)
	  MenuController.IsMenuOpen() -> boolean
	Le bouton « ☰ » (écran GC_MenuButton, en haut à droite sous la barre Roblox) est visible à l'accueil et en
	préparation (pendant les trous, le coin appartient au HUD ; M / Start restent actifs).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared.Util.Log)

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI.Theme)
local IconButton = require(UI.Components.IconButton)
local ScreenManager = require(UI.ScreenManager)

local MenuController = {}
MenuController.Priority = 50

local ACTION_MENU = "GC_Menu"
local ACTION_BACK = "GC_Back"

-- Phases où le bouton tactile reste visible (en plus de l'accueil et de la préparation sur tactile).
local BUTTON_PHASES: { [string]: boolean } = { Lobby = true, Preparing = true }
-- Pendant les trous, le coin haut droit appartient au HUD (infos, scores) : pas de bouton tactile.
local TOUCH_EXTRA_PHASES: { [string]: boolean } = {}

local inputController: any = nil
local uiController: any = nil
local menuGui: ScreenGui? = nil
local menuButton: IconButton.IconButtonApi? = nil

local function loadController(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
		Log.warn("Menu", "contrôleur illisible :", name, result)
	end
	return nil
end

local function currentPhase(): string
	if uiController and type(uiController.GetPhase) == "function" then
		local ok, phase = pcall(uiController.GetPhase)
		if ok and type(phase) == "string" then
			return phase
		end
	end
	return "Lobby"
end

local function lobbyState(): any
	if uiController and type(uiController.GetLobbyState) == "function" then
		local ok, state = pcall(uiController.GetLobbyState)
		if ok then
			return state
		end
	end
	return nil
end

function MenuController.IsMenuOpen(): boolean
	return ScreenManager.IsVisible("LobbyMenu") or ScreenManager.IsVisible("Settings")
end

function MenuController.OpenMenu()
	if currentPhase() == "Preparing" and not ScreenManager.IsVisible("HostSettings") then
		ScreenManager.Show("HostSettings", lobbyState())
		return
	end
	ScreenManager.Show("LobbyMenu")
end

function MenuController.CloseMenu()
	ScreenManager.Hide("Settings")
	ScreenManager.Hide("LobbyMenu")
end

function MenuController.ToggleMenu()
	local top = ScreenManager.GetTopModal()
	if top then
		-- Une modale est ouverte : la touche menu la referme (comportement attendu d'un bouton « pause »).
		ScreenManager.Hide(top)
		return
	end
	MenuController.OpenMenu()
end

function MenuController.OpenSettings(tab: string?)
	ScreenManager.Show("Settings", tab)
end

local function isTouch(): boolean
	if inputController and type(inputController.GetDevice) == "function" then
		local ok, device = pcall(inputController.GetDevice)
		if ok then
			return device == "Touch"
		end
	end
	return false
end

local function refreshButton()
	local gui = menuGui
	if not gui then
		return
	end
	local phase = currentPhase()
	gui.Enabled = BUTTON_PHASES[phase] == true or (TOUCH_EXTRA_PHASES[phase] == true and isTouch())
end

local function buildButton()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui", 30)
	if not playerGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "GC_MenuButton"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = Theme.Layers.MenuButton
	gui.Enabled = false
	gui.Parent = playerGui
	menuGui = gui

	local holder = Instance.new("Frame")
	holder.Name = "Support"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Position = UDim2.new(1, -12, 0, 8)
	holder.Size = UDim2.fromOffset(Theme.Touch.Medium, Theme.Touch.Medium + 24)
	holder.Parent = gui
	ScreenManager.AttachScale(holder)

	menuButton = IconButton.new({
		name = "Menu",
		glyph = "☰",
		variant = "Primary",
		size = "Medium",
		labelKey = "menu.button",
		parent = holder,
		onActivated = function()
			MenuController.ToggleMenu()
		end,
	})
	-- Le bouton n'entre pas dans la navigation manette (Start ouvre déjà le menu).
	local button = menuButton
	if button then
		button.Instance.Selectable = false
	end
end

function MenuController.Init()
	inputController = loadController("InputController")
	uiController = loadController("UIController")
end

function MenuController.Start()
	buildButton()

	if inputController and type(inputController.BindAtPriority) == "function" then
		local priority = (inputController.Priorities and inputController.Priorities.Modal) or 3000
		local ok, err = pcall(inputController.BindAtPriority, ACTION_MENU, priority, function(state: Enum.UserInputState): boolean?
			if state == Enum.UserInputState.Begin then
				MenuController.ToggleMenu()
			end
			return nil
		end, Enum.KeyCode.M, Enum.KeyCode.ButtonStart)
		if not ok then
			Log.warn("Menu", "liaison du menu impossible :", err)
		end
		ok, err = pcall(inputController.BindAtPriority, ACTION_BACK, priority, function(state: Enum.UserInputState): boolean?
			if state ~= Enum.UserInputState.Begin then
				-- Ne consomme le relâchement que si une modale est ouverte (sinon l'entrée continue son chemin).
				return if ScreenManager.GetTopModal() then nil else false
			end
			if ScreenManager.Back() then
				return nil
			end
			return false -- aucune modale : laisser passer B / Échap
		end, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
		if not ok then
			Log.warn("Menu", "liaison du retour impossible :", err)
		end
	else
		Log.warn("Menu", "InputController indisponible : raccourcis du menu inactifs")
	end

	if uiController and uiController.PhaseChanged then
		uiController.PhaseChanged:Connect(function()
			refreshButton()
		end)
	end
	if inputController and inputController.DeviceChanged then
		inputController.DeviceChanged:Connect(function()
			refreshButton()
		end)
	end
	refreshButton()
end

return MenuController
