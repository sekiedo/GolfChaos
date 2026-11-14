--[[
	ServerScriptService/Services/MovementService  (ModuleScript)
	------------------------------------------------------------
	Source unique de vérité pour WalkSpeed / JumpPower.
	Plusieurs systèmes peuvent bloquer le joueur en même temps (visée, étourdissement...) :
	chacun pose un verrou nommé ("Aim", "Stun") et le joueur ne bouge que si plus aucun verrou n'existe.
	Le multiplicateur de vitesse (Café, étape 3) passe par l'attribut joueur "SpeedMultiplier".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MovementService = {}

local locks = {} -- [player] = { [reason] = true }

local function hasLocks(player)
	local set = locks[player]
	return set ~= nil and next(set) ~= nil
end

function MovementService.Refresh(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.UseJumpPower = true
	if hasLocks(player) then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	else
		local multiplier = player:GetAttribute("SpeedMultiplier")
		if typeof(multiplier) ~= "number" then
			multiplier = 1
		end
		humanoid.WalkSpeed = Config.WalkSpeed * multiplier
		humanoid.JumpPower = Config.JumpPower
	end
end

function MovementService.Lock(player, reason)
	local set = locks[player]
	if not set then
		set = {}
		locks[player] = set
	end
	set[reason] = true
	MovementService.Refresh(player)
end

function MovementService.Unlock(player, reason)
	local set = locks[player]
	if set then
		set[reason] = nil
	end
	MovementService.Refresh(player)
end

function MovementService.IsLocked(player, reason)
	local set = locks[player]
	if not set then
		return false
	end
	if reason then
		return set[reason] == true
	end
	return next(set) ~= nil
end

function MovementService.Init()
	local function setupPlayer(player)
		player.CharacterRemoving:Connect(function()
			locks[player] = nil
		end)
		player.CharacterAdded:Connect(function(character)
			locks[player] = nil
			if character:WaitForChild("Humanoid", 10) then
				MovementService.Refresh(player)
			end
		end)
		player:GetAttributeChangedSignal("SpeedMultiplier"):Connect(function()
			MovementService.Refresh(player)
		end)
		if player.Character then
			MovementService.Refresh(player)
		end
	end

	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		locks[player] = nil
	end)
end

return MovementService
