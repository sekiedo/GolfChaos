--!strict
--[[
	VehicleController — commandes et retours du Kart-Caddie pour le joueur local (priorité 37).

	  R : remettre le kart à l'endroit (conducteur, délai de recharge côté serveur) -> Vehicles.Reset(roundId)
	  H : klaxon (cosmétique) -> Vehicles.Horn ; le serveur pose l'attribut HornAt sur le kart, le son est local
	  Vehicles.State(état | nil) : à bord, place, conducteur ou passager, points de structure, fin de vie.
	Monter se fait par l'invite de proximité du kart (serveur) ; descendre par le saut. Aucune vitesse n'est
	décidée ici : le serveur pilote le kart (voir VehicleService).

	API : IsRiding() -> boolean ; IsDriver() -> boolean ; GetState() -> table?
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameState = require(Shared.Util.GameState)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local Trove = require(Shared.Util.Trove)

local InputController = require(script.Parent.InputController)

local VehicleController = {}
VehicleController.Priority = 37

local localPlayer = Players.LocalPlayer
local runtimeTrove = Trove.new()
local current: { [string]: any }? = nil

local function toast(text: string, kind: string?)
	local module = script.Parent:FindFirstChild("HUDController")
	if module and module:IsA("ModuleScript") then
		local ok, hud = pcall(require, module)
		if ok and type(hud) == "table" and type(hud.ShowToast) == "function" then
			pcall(hud.ShowToast, text, kind)
		end
	end
end

local function roundId(): number
	local ok, folder = pcall(GameState.get)
	if ok and typeof(folder) == "Instance" then
		local value = (folder :: Folder):GetAttribute("RoundId")
		if type(value) == "number" and value == value then
			return math.floor(value)
		end
	end
	return 0
end

function VehicleController.IsRiding(): boolean
	return current ~= nil
end

function VehicleController.IsDriver(): boolean
	return current ~= nil and current.isDriver == true
end

function VehicleController.GetState(): { [string]: any }?
	return current
end

local function onState(payload: any)
	local previous = current
	if type(payload) == "table" then
		current = payload
		if previous == nil then
			toast(Locale.t(if payload.isDriver then "vehicle.board.driver" else "vehicle.board.passenger"), "info")
		elseif type(previous.structure) == "number" and type(payload.structure) == "number" and payload.structure < previous.structure then
			toast(Locale.t("vehicle.damaged", { n = math.max(payload.structure, 0) }), "warn")
		end
	else
		current = nil
	end
end

function VehicleController.Init()
	InputController.Bind("GC_VehicleReset", function(inputState: Enum.UserInputState): boolean?
		if inputState ~= Enum.UserInputState.Begin or not VehicleController.IsDriver() then
			return false
		end
		Net.send("Vehicles.Reset", roundId())
		return true
	end, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
	InputController.Bind("GC_VehicleHorn", function(inputState: Enum.UserInputState): boolean?
		if inputState ~= Enum.UserInputState.Begin or not VehicleController.IsDriver() then
			return false
		end
		Net.send("Vehicles.Horn")
		return true
	end, Enum.KeyCode.H, Enum.KeyCode.ButtonL3)
	runtimeTrove:Add(function()
		InputController.Unbind("GC_VehicleReset")
		InputController.Unbind("GC_VehicleHorn")
	end)
	runtimeTrove:Add(Net.listen("Vehicles.State", onState))
end

function VehicleController.Start()
	-- Sans véhicule : l'état local se vide quand l'attribut InVehicle disparaît (kart détruit, KO).
	runtimeTrove:Connect(localPlayer:GetAttributeChangedSignal("InVehicle"), function()
		if localPlayer:GetAttribute("InVehicle") ~= true then
			current = nil
		end
	end)
end

return VehicleController
