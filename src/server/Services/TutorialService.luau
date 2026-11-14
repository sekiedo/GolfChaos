--!strict
--[[
	TutorialService — enregistre la fin du tutoriel par points lumineux (priorité 60).

	Le client (TutorialController) envoie « Tutorial.Complete » quand le joueur termine ou saute le tutoriel ;
	le serveur pose profile.tutorialDone = true (une seule fois, aucun gain de jeu).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Services = require(script.Parent.Parent.Util.Services)
local services = Services.scope("Tutorial")

local TutorialService = {}
TutorialService.Priority = 60

function TutorialService.Init()
	Net.on("Tutorial.Complete", function(player: Player)
		local data = services.get("PlayerDataService")
		if data and type(data.Update) == "function" then
			pcall(data.Update, player, function(profile: any): boolean
				if profile.tutorialDone == true then
					return false
				end
				profile.tutorialDone = true
				return true
			end)
		end
	end)
end

function TutorialService.Start() end

return TutorialService
