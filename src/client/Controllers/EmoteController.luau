--!strict
--[[
	EmoteController — ouvre l'écran de choix d'émote (touche V, ou bouton « Émotes » du menu).

	  EmoteController.Open() / Close() / Toggle()
	Hors des phases où le joueur peut bouger librement (visée, véhicule, KO...), le serveur refuse l'émote
	(EmoteService) : l'écran reste ouvrable, le refus est silencieux. Échap / B ferment l'écran (MenuController).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared.Util.Log)

local UI = script.Parent.Parent:WaitForChild("UI")
local ScreenManager = require(UI.ScreenManager)

local EmoteController = {}
EmoteController.Priority = 63

local ACTION = "GC_EmoteMenu"

function EmoteController.Open()
	ScreenManager.Show("Emotes")
end

function EmoteController.Close()
	ScreenManager.Hide("Emotes")
end

function EmoteController.Toggle()
	if ScreenManager.IsVisible("Emotes") then
		ScreenManager.Hide("Emotes")
	elseif ScreenManager.GetTopModal() == nil then
		ScreenManager.Show("Emotes")
	end
end

function EmoteController.Start()
	local module = script.Parent:FindFirstChild("InputController")
	local ok, input = pcall(function()
		return require(module :: ModuleScript) :: any
	end)
	if not ok or type(input) ~= "table" or type(input.BindAtPriority) ~= "function" then
		Log.warn("Emote", "InputController indisponible : touche V inactive")
		return
	end
	local bound, err = pcall(input.BindAtPriority, ACTION, input.Priorities.Gameplay, function(state: Enum.UserInputState): boolean?
		if state == Enum.UserInputState.Begin then
			EmoteController.Toggle()
		end
		return nil
	end, Enum.KeyCode.V)
	if not bound then
		Log.warn("Emote", "liaison de la touche V impossible :", err)
	end
end

return EmoteController
