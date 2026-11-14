--[[
	ServerScriptService/Services/CollisionService  (ModuleScript)
	-------------------------------------------------------------
	Groupes de collision :
	  - Balls      : ne collisionne ni avec les autres balles ni avec les personnages
	                 (les impacts sur les joueurs sont détectés par requête spatiale côté serveur,
	                  pour ne jamais pousser un avatar "physiquement" et rester maître du stun).
	  - Characters : tous les BaseParts des avatars (accessoires, outils, clubs soudés inclus).
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CollisionService = {}

local function register(name)
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end

local function assignCharacter(character)
	local groupName = Config.CollisionGroups.Character
	local function apply(instance)
		if instance:IsA("BasePart") then
			instance.CollisionGroup = groupName
		end
	end
	for _, descendant in character:GetDescendants() do
		apply(descendant)
	end
	character.DescendantAdded:Connect(apply)
end

function CollisionService.Init()
	local ballGroup = Config.CollisionGroups.Ball
	local characterGroup = Config.CollisionGroups.Character

	register(ballGroup)
	register(characterGroup)
	PhysicsService:CollisionGroupSetCollidable(ballGroup, ballGroup, false)
	PhysicsService:CollisionGroupSetCollidable(ballGroup, characterGroup, false)

	local function setupPlayer(player)
		player.CharacterAdded:Connect(assignCharacter)
		if player.Character then
			assignCharacter(player.Character)
		end
	end
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
end

return CollisionService
