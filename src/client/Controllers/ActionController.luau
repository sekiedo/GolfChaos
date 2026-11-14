--!strict
--[[
	ActionController — actions de combat cartoon du joueur local (priorité 35).

	  Saut      : contrôle Roblox par défaut (Espace / A / bouton tactile).
	  Plongeon  : Q / X manette / bouton tactile « Plonger » -> Combat.Dive(roundId, direction)
	              direction = déplacement en cours, sinon l'orientation de l'avatar.
	  Poing     : F / B manette (hors visée) / bouton tactile « Poing » -> Combat.Punch(roundId, regard)
	              regard = direction horizontale de la caméra (le serveur retombe sur l'orientation de
	              l'avatar si l'écart dépasse Gameplay.Punch.FacingToleranceDeg).
	  Sprint    : non proposé (MovementService n'expose aucun sprint validé par le serveur).

	RoundId : 0 pendant l'accueil (Lobby / Preparing, accepté par CombatService), sinon GameState.RoundId.
	Désactivé pendant la visée (GolfAimController.IsAiming), un KO (attribut joueur KnockedOut), en voiturette
	(InVehicle), pour un spectateur ou hors des phases de combat (Gameplay.KO.AllowedPhases) : l'entrée passe
	alors aux actions de priorité inférieure. Les délais affichés sont locaux et indicatifs : le serveur décide
	(retour Combat.Feedback(action, ok, raison)).

	API : IsEnabled() -> boolean ; Changed : Signal() (disponibilité des actions modifiée)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Trove = require(Shared.Util.Trove)
local Log = require(Shared.Util.Log)
local GameState = require(Shared.Util.GameState)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local Gameplay = require(Shared.Config.Gameplay)

local InputController = require(script.Parent.InputController)

local ActionController = {}
ActionController.Priority = 35
ActionController.Changed = Signal.new()

local PUNCH = Gameplay.Punch
local DIVE = Gameplay.Dive
local LOBBY_PHASES: { [string]: boolean } = { Lobby = true, Preparing = true }
local REFRESH_INTERVAL = 0.2

local localPlayer = Players.LocalPlayer

local state = {
	initialized = false,
	started = false,
	gameState = nil :: Folder?,
	enabled = false,
	punchReadyAt = 0,
	diveReadyAt = 0,
	refreshTimer = 0,
}

local runtimeTrove = Trove.new()

--------------------------------------------------------------------------------
-- Modules facultatifs (chargés paresseusement, pas de cycle de require)
--------------------------------------------------------------------------------

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

local function isAiming(): boolean
	local aim = optionalController("GolfAimController")
	if aim and type(aim.IsAiming) == "function" then
		local ok, value = pcall(aim.IsAiming)
		return ok and value == true
	end
	return localPlayer:GetAttribute("Aiming") == true
end

local function toast(text: string, kind: string?)
	local hud = optionalController("HUDController")
	if hud and type(hud.ShowToast) == "function" then
		pcall(hud.ShowToast, text, kind)
	end
end

local function playSound(name: string, position: Vector3?)
	local effects = optionalController("EffectsController")
	if effects and type(effects.PlaySound) == "function" then
		pcall(effects.PlaySound, name, { position = position })
	end
end

--------------------------------------------------------------------------------
-- Lectures
--------------------------------------------------------------------------------

local function phase(): string
	local folder = state.gameState
	local value = if folder then folder:GetAttribute("Phase") else nil
	return if type(value) == "string" then value else "Lobby"
end

local function roundId(): number
	if LOBBY_PHASES[phase()] then
		return 0
	end
	local folder = state.gameState
	local value = if folder then folder:GetAttribute("RoundId") else nil
	if type(value) == "number" and value == value then
		return math.floor(value)
	end
	return 0
end

local function getCharacterParts(): (BasePart?, Humanoid?)
	local character = localPlayer.Character
	if not character then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return (if root and root:IsA("BasePart") then root else nil), humanoid
end

local function flatUnit(vector: Vector3): Vector3?
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 0.05 or flat.Magnitude ~= flat.Magnitude then
		return nil
	end
	return flat.Unit
end

-- Les actions sont-elles disponibles maintenant ?
local function computeEnabled(): boolean
	if table.find(Gameplay.KO.AllowedPhases, phase()) == nil then
		return false
	end
	if localPlayer:GetAttribute("KnockedOut") == true or localPlayer:GetAttribute("InVehicle") == true then
		return false
	end
	if localPlayer:GetAttribute("Spectating") == true then
		return false
	end
	if not LOBBY_PHASES[phase()] and localPlayer:GetAttribute("HoleFinished") == true then
		return false
	end
	if isAiming() then
		return false
	end
	local root, humanoid = getCharacterParts()
	if not root or not humanoid or humanoid.Health <= 0 or humanoid.SeatPart ~= nil then
		return false
	end
	local character = localPlayer.Character
	if character and character:GetAttribute("Frozen") == true then
		return false
	end
	return true
end

local function refreshEnabled()
	local enabled = computeEnabled()
	if enabled == state.enabled then
		return
	end
	state.enabled = enabled
	InputController.SetTouchButtonVisible("CombatPunch", enabled)
	InputController.SetTouchButtonVisible("CombatDive", enabled)
	ActionController.Changed:Fire()
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

local function doPunch(): boolean
	refreshEnabled()
	if not state.enabled then
		return false
	end
	local now = os.clock()
	if now < state.punchReadyAt then
		return true -- consommée : délai local en cours
	end
	local root = getCharacterParts()
	if not root then
		return false
	end
	local camera = Workspace.CurrentCamera
	local direction = (if camera then flatUnit(camera.CFrame.LookVector) else nil) or flatUnit(root.CFrame.LookVector)
	if not direction then
		return false
	end
	state.punchReadyAt = now + PUNCH.Cooldown
	InputController.StartCooldown("CombatPunch", PUNCH.Cooldown)
	Net.send("Combat.Punch", roundId(), direction)
	playSound("punch_swish", root.Position)
	return true
end

local function doDive(): boolean
	refreshEnabled()
	if not state.enabled then
		return false
	end
	local now = os.clock()
	if now < state.diveReadyAt then
		return true
	end
	local root, humanoid = getCharacterParts()
	if not root or not humanoid then
		return false
	end
	local direction = flatUnit(humanoid.MoveDirection) or flatUnit(root.CFrame.LookVector)
	if not direction then
		return false
	end
	state.diveReadyAt = now + DIVE.Cooldown
	InputController.StartCooldown("CombatDive", DIVE.Cooldown)
	Net.send("Combat.Dive", roundId(), direction)
	playSound("dive_whoosh", root.Position)
	return true
end

local function onFeedback(action: any, ok: any, reason: any)
	if ok == true then
		if action == "punch" then
			local root = getCharacterParts()
			playSound("ko_bonk", if root then root.Position else nil)
		end
		return
	end
	local key = if type(reason) == "string" then "aim.combat." .. reason else "aim.combat.default"
	if not (Locale.has(key) or Locale.has(key, "fr")) then
		key = "aim.combat.default"
	end
	-- Un raté n'est pas une erreur : message discret ; les autres refus sont signalés.
	toast(Locale.t(key), if reason == "miss" then "info" else "warn")
	-- Refus serveur : le délai local est levé pour ne pas bloquer le joueur à tort.
	if reason ~= "cooldown" then
		if action == "punch" then
			state.punchReadyAt = math.min(state.punchReadyAt, os.clock() + 0.25)
		elseif action == "dive" then
			state.diveReadyAt = math.min(state.diveReadyAt, os.clock() + 0.25)
		end
	end
end

--------------------------------------------------------------------------------
-- API et cycle de vie
--------------------------------------------------------------------------------

function ActionController.IsEnabled(): boolean
	return state.enabled
end

function ActionController.Init()
	if state.initialized then
		return
	end
	state.initialized = true

	InputController.Bind("CombatPunch", function(inputState: Enum.UserInputState): boolean?
		if inputState ~= Enum.UserInputState.Begin then
			return false
		end
		return doPunch()
	end, Enum.KeyCode.F, Enum.KeyCode.ButtonB)
	InputController.Bind("CombatDive", function(inputState: Enum.UserInputState): boolean?
		if inputState ~= Enum.UserInputState.Begin then
			return false
		end
		return doDive()
	end, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
	InputController.SetTouchButton("CombatPunch", {
		text = Locale.t("controls.action.punch"),
		slot = "ActionB",
		color = Color3.fromRGB(255, 92, 92),
		indicator = false,
		visible = false,
	})
	InputController.SetTouchButton("CombatDive", {
		text = Locale.t("controls.action.dive"),
		slot = "ActionA",
		color = Color3.fromRGB(77, 166, 255),
		indicator = false,
		visible = false,
	})
	runtimeTrove:Add(function()
		InputController.Unbind("CombatPunch")
		InputController.Unbind("CombatDive")
		InputController.SetTouchButton("CombatPunch", nil)
		InputController.SetTouchButton("CombatDive", nil)
	end)

	runtimeTrove:Add(Net.listen("Combat.Feedback", onFeedback))
	for _, attribute in { "KnockedOut", "InVehicle", "Spectating", "HoleFinished", "Aiming" } do
		runtimeTrove:Connect(localPlayer:GetAttributeChangedSignal(attribute), refreshEnabled)
	end
end

function ActionController.Start()
	if state.started then
		return
	end
	state.started = true
	local ok, folder = pcall(GameState.get)
	if ok and typeof(folder) == "Instance" then
		state.gameState = folder :: Folder
		runtimeTrove:Connect((folder :: Folder):GetAttributeChangedSignal("Phase"), refreshEnabled)
	else
		Log.warn("Action", "GameState indisponible : combat limité à l'accueil")
	end
	-- Rafraîchissement léger (visée, personnage, siège) sans boucle active.
	runtimeTrove:Connect(RunService.Heartbeat, function(dt: number)
		state.refreshTimer += dt
		if state.refreshTimer >= REFRESH_INTERVAL then
			state.refreshTimer = 0
			refreshEnabled()
		end
	end)
	local aim = optionalController("GolfAimController")
	if aim and type(aim.StateChanged) == "table" then
		runtimeTrove:Connect(aim.StateChanged, refreshEnabled)
	end
	refreshEnabled()
end

return ActionController
