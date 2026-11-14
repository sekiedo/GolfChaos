--!strict
--[[
	ChallengesController — ouvre l'écran Défis et félicite à la réussite d'un défi.

	  ChallengesController.Open(category?) / Close() / Toggle()
	Progress.AchievementCompleted(achievementId, pièces) -> toast « ui.notify.achievement » (nom + pièces versées
	par le serveur) ; l'écran Défis ouvert se met à jour tout seul au Data.Sync suivant.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Locale = require(Shared.Locale)
local Achievements = require(Shared.Config.Achievements)

local UI = script.Parent.Parent:WaitForChild("UI")
local ScreenManager = require(UI.ScreenManager)

local ChallengesController = {}
ChallengesController.Priority = 62

function ChallengesController.Open(category: string?)
	ScreenManager.Show("Challenges", category)
end

function ChallengesController.Close()
	ScreenManager.Hide("Challenges")
end

function ChallengesController.Toggle()
	ScreenManager.Toggle("Challenges")
end

function ChallengesController.Start()
	Net.listen("Progress.AchievementCompleted", function(achievementId: any, coins: any)
		local def = if type(achievementId) == "string" then Achievements.get(achievementId) else nil
		if not def then
			return
		end
		local module = script.Parent:FindFirstChild("NotificationController")
		local ok, notifications = pcall(function()
			return require(module :: ModuleScript) :: any
		end)
		if ok and type(notifications) == "table" and type(notifications.NotifyKey) == "function" then
			pcall(notifications.NotifyKey, "ui.notify.achievement", {
				name = Locale.t(def.nameKey),
				coins = if type(coins) == "number" then coins else def.reward,
			}, "success")
		end
	end)
end

return ChallengesController
