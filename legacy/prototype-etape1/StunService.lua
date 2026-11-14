--[[
	ServerScriptService/Services/StunService  (ModuleScript)
	--------------------------------------------------------
	Étourdissement + ragdoll, 100 % serveur. Réutilisé par la balle (étape 1)
	puis par les pouvoirs (étape 3 : roquette, laser, duel, mines, voiturette...).

	  StunService.Stun(player, duration?, knockVelocity?) -> boolean
	  StunService.IsStunned(player) -> boolean
	  StunService.Stunned   (event : player, duration)
	  StunService.Recovered (event : player)

	Pendant le stun le serveur prend le NetworkOwnership du personnage : il peut ainsi appliquer
	l'impulsion de recul de façon fiable (un client propriétaire écraserait la vélocité).
	Attribut joueur répliqué : "Stunned" (bool).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MovementService = require(script.Parent.MovementService)

local StunService = {}

local stunnedEvent = Instance.new("BindableEvent")
local recoveredEvent = Instance.new("BindableEvent")
StunService.Stunned = stunnedEvent.Event
StunService.Recovered = recoveredEvent.Event

local states = {} -- [player] = { EndTime, Character, Humanoid, Ragdoll }
local immuneUntil = {} -- [player] = timestamp

local function now()
	return workspace:GetServerTimeNow()
end

local function setOwnership(character, serverOwned)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored then
			pcall(function()
				if serverOwned then
					part:SetNetworkOwner(nil)
				else
					part:SetNetworkOwnershipAuto()
				end
			end)
		end
	end
end

-- Remplace chaque Motor6D du rig (R6 ou R15) par un BallSocketConstraint.
local function startRagdoll(character, humanoid, knockVelocity)
	local root = character:FindFirstChild("HumanoidRootPart")
	local look = root.CFrame.LookVector

	local record = {
		Folder = Instance.new("Folder"),
		Motors = {},
		Attachments = {},
		CanCollide = {},
		RequiresNeck = humanoid.RequiresNeck,
		Facing = Vector3.new(look.X, 0, look.Z),
	}
	record.Folder.Name = "Ragdoll"
	record.Folder.Parent = character

	-- Sans ça, désactiver le cou tue le personnage.
	humanoid.RequiresNeck = false
	humanoid.PlatformStand = true

	for _, descendant in character:GetDescendants() do
		if
			descendant:IsA("Motor6D")
			and descendant.Part0
			and descendant.Part1
			and not descendant:FindFirstAncestorWhichIsA("Accessory")
			and not descendant:FindFirstAncestorWhichIsA("Tool")
		then
			local motor = descendant

			local attachment0 = Instance.new("Attachment")
			attachment0.Name = "RagdollAttachment0"
			attachment0.CFrame = motor.C0
			attachment0.Parent = motor.Part0

			local attachment1 = Instance.new("Attachment")
			attachment1.Name = "RagdollAttachment1"
			attachment1.CFrame = motor.C1
			attachment1.Parent = motor.Part1

			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = attachment0
			socket.Attachment1 = attachment1
			socket.LimitsEnabled = true
			socket.TwistLimitsEnabled = true
			socket.UpperAngle = if motor.Name == "Neck" then 40 else 70
			socket.TwistLowerAngle = -30
			socket.TwistUpperAngle = 30
			socket.Parent = record.Folder

			-- Évite que les membres voisins se repoussent (tremblements).
			local noCollide = Instance.new("NoCollisionConstraint")
			noCollide.Part0 = motor.Part0
			noCollide.Part1 = motor.Part1
			noCollide.Parent = record.Folder

			motor.Enabled = false
			table.insert(record.Motors, motor)
			table.insert(record.Attachments, attachment0)
			table.insert(record.Attachments, attachment1)
		end
	end

	-- Les membres doivent toucher le sol pendant le ragdoll.
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") and part ~= root then
			record.CanCollide[part] = part.CanCollide
			part.CanCollide = true
		end
	end

	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	setOwnership(character, true)

	if knockVelocity then
		for _, part in character:GetChildren() do
			if part:IsA("BasePart") then
				part.AssemblyLinearVelocity = knockVelocity
			end
		end
	end

	return record
end

local function stopRagdoll(character, humanoid, record)
	for _, motor in record.Motors do
		if motor.Parent then
			motor.Enabled = true
		end
	end
	record.Folder:Destroy()
	for _, attachment in record.Attachments do
		attachment:Destroy()
	end
	for part, canCollide in record.CanCollide do
		if part.Parent then
			part.CanCollide = canCollide
		end
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		local facing = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if facing.Magnitude < 0.2 then
			facing = record.Facing
		end
		if facing.Magnitude < 0.1 then
			facing = Vector3.new(0, 0, -1)
		end
		-- On redresse l'avatar, légèrement au-dessus du sol pour ne pas le coincer dedans.
		local position = root.Position + Vector3.new(0, 2.5, 0)
		root.CFrame = CFrame.lookAt(position, position + facing)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	setOwnership(character, false)

	humanoid.RequiresNeck = record.RequiresNeck
	humanoid.PlatformStand = false
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
end

local function recover(player, state)
	states[player] = nil
	player:SetAttribute("Stunned", false)
	MovementService.Unlock(player, "Stun")

	if player.Character == state.Character and state.Character.Parent and state.Humanoid.Health > 0 then
		stopRagdoll(state.Character, state.Humanoid, state.Ragdoll)
	end

	immuneUntil[player] = now() + Config.Stun.Immunity
	recoveredEvent:Fire(player)
end

function StunService.IsStunned(player)
	return states[player] ~= nil
end

-- Retourne true si le joueur est (ou reste) étourdi, false s'il est immunisé / mort.
function StunService.Stun(player, duration, knockVelocity)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return false
	end

	duration = duration or Config.Stun.Duration
	local time = now()

	local existing = states[player]
	if existing then
		-- Déjà étourdi : on prolonge seulement.
		existing.EndTime = math.max(existing.EndTime, time + duration)
		return true
	end
	if (immuneUntil[player] or 0) > time then
		return false
	end

	local state = {
		EndTime = time + duration,
		Character = character,
		Humanoid = humanoid,
	}
	states[player] = state

	player:SetAttribute("Stunned", true)
	MovementService.Lock(player, "Stun")
	state.Ragdoll = startRagdoll(character, humanoid, knockVelocity)
	stunnedEvent:Fire(player, duration)

	task.spawn(function()
		while states[player] == state and now() < state.EndTime do
			task.wait(0.05)
		end
		if states[player] == state then
			recover(player, state)
		end
	end)

	return true
end

function StunService.Init()
	local function setupPlayer(player)
		player:SetAttribute("Stunned", false)
		player.CharacterRemoving:Connect(function()
			states[player] = nil
			player:SetAttribute("Stunned", false)
		end)
	end

	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		immuneUntil[player] = nil
	end)
end

return StunService
