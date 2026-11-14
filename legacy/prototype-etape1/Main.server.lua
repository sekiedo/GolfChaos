--[[
	ServerScriptService/Main  (Script)
	----------------------------------
	Point d'entrée serveur : initialise les services dans l'ordre.
	Étape 2 : on ajoutera MapService / ScoreService / GameManager ici.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Services = ServerScriptService:WaitForChild("Services")

local CollisionService = require(Services.CollisionService)
local MovementService = require(Services.MovementService)
local StunService = require(Services.StunService)
local BallService = require(Services.BallService)

-- L'ordre compte : les groupes de collision d'abord, la balle en dernier.
CollisionService.Init()
MovementService.Init()
StunService.Init()
BallService.Init()

-- Test de l'étape 1 : une balle devant chaque joueur à son premier spawn.
-- (Le GameManager de l'étape 2 remplacera ce bloc : désactive Config.Debug.AutoSpawnBall.)
if Config.Debug.AutoSpawnBall then
	local function onCharacterAdded(player, character)
		if BallService.GetBall(player) then
			return
		end
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root then
			BallService.SpawnBall(player, root.Position + root.CFrame.LookVector * 12)
		end
	end

	local function onPlayerAdded(player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end
