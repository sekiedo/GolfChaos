--[[
	ServerScriptService/Services/BallService  (ModuleScript)
	--------------------------------------------------------
	Autorité serveur sur les balles : création, validation des tirs, physique, friction par surface,
	eau / hors limites, impacts sur les joueurs.

	Sécurité : le client n'envoie que des INTENTIONS (viser, commencer la jauge, frapper avec une direction).
	Le serveur revalide tout : types, distance joueur-balle, état de la balle, étourdissement, cadence,
	et recalcule la puissance à partir du temps écoulé entre SwingStart et Shoot (le client ne peut pas
	envoyer "100 %" à volonté : sa valeur est bornée à ± PowerTolerance de la valeur serveur).

	NetworkOwnership : la balle appartient TOUJOURS au serveur (SetNetworkOwner(nil)). Sans cela Roblox
	la confie automatiquement au joueur le plus proche : physique non déterministe, triche possible
	(téléporter la balle dans le trou) et saccades pour les autres joueurs. La latence perçue du tireur est
	masquée côté client (caméra de suivi immédiate, voir AimController).

	API pour les étapes suivantes (GameManager, pouvoirs) :
	  Init()
	  SpawnBall(player, position|CFrame, snapToGround?) -> Part
	  PlaceBall(player, position|CFrame, snapToGround?)     téléporte la balle (départ d'un trou)
	  RemoveBall(player)
	  HoleBall(player)                                      balle rentrée (état "Holed")
	  GetBall(player) / GetState(player) / GetStrokes(player) / ResetStrokes(player)
	  CancelAim(player, reason?, blockSeconds?)             ex: corne de brume
	  SetWind(Vector3)                                      accélération du vent (studs/s²), biome Tempête
	  SetCanShoot(function(player) -> boolean)              le GameManager bloque les tirs hors manche
	  Événements : Shot(player, strokes, power) / Rested(player, position) /
	               Respawned(player, reason) / PlayerHit(attacker, victim)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local MovementService = require(script.Parent.MovementService)
local StunService = require(script.Parent.StunService)

local BallService = {}

local shotEvent = Instance.new("BindableEvent")
local restedEvent = Instance.new("BindableEvent")
local respawnedEvent = Instance.new("BindableEvent")
local playerHitEvent = Instance.new("BindableEvent")
BallService.Shot = shotEvent.Event
BallService.Rested = restedEvent.Event
BallService.Respawned = respawnedEvent.Event
BallService.PlayerHit = playerHitEvent.Event

local HAZARD_MESSAGES = {
	water = "Dans l'eau ! Pénalité : +%d coup(s)",
	oob = "Hors limites ! Pénalité : +%d coup(s)",
	void = "Balle tombée dans le vide ! Pénalité : +%d coup(s)",
}

local BALL_RADIUS = Config.Ball.Diameter / 2

local balls = {} -- [player] = data
local ballsFolder
local terrain = workspace.Terrain
local wind = Vector3.zero
local canShoot = function(_player)
	return true
end
local rateLimits = {}

local rayParams, hitParams, hazardParams
local characterModels = {}
local hazardParts = {}

--------------------------------------------------------------------------------
-- Utilitaires
--------------------------------------------------------------------------------

local function now()
	return workspace:GetServerTimeNow()
end

local function isFiniteNumber(value)
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isFiniteVector(value)
	return typeof(value) == "Vector3" and isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)
end

local function rateLimited(player, key, interval)
	local bucket = rateLimits[player]
	if not bucket then
		bucket = {}
		rateLimits[player] = bucket
	end
	local time = now()
	if bucket[key] and time - bucket[key] < interval then
		return true
	end
	bucket[key] = time
	return false
end

local function makeProperties(surfaceName)
	local surface = Config.Surfaces[surfaceName] or Config.Surfaces[Config.DefaultSurface]
	-- Poids 100 : les propriétés de la balle l'emportent sur celles du sol.
	return PhysicalProperties.new(Config.Ball.Density, surface.Friction, surface.Elasticity, 100, 100)
end

local function applySurface(data, surfaceName)
	if data.Surface == surfaceName then
		return
	end
	data.Surface = surfaceName
	data.Ball.CustomPhysicalProperties = makeProperties(surfaceName)
end

local function surfaceFromHit(result)
	local attribute = result.Instance:GetAttribute("Surface")
	if typeof(attribute) == "string" and Config.Surfaces[attribute] then
		return attribute
	end
	return Config.MaterialSurface[result.Material] or Config.DefaultSurface
end

local function isNear(player, ball, maxDistance)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	return (root.Position - ball.Position).Magnitude <= maxDistance
end

local function toPosition(value)
	if typeof(value) == "CFrame" then
		return value.Position
	end
	return value
end

local function snapToGround(position)
	local result = workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -80, 0), rayParams)
	if result then
		return result.Position + Vector3.new(0, BALL_RADIUS, 0)
	end
	return position
end

local function inTerrainWater(position)
	local region = Region3.new(position - Vector3.new(2, 2, 2), position + Vector3.new(2, 2, 2)):ExpandToGrid(4)
	local ok, materials, occupancies = pcall(terrain.ReadVoxels, terrain, region, 4)
	if not ok then
		return false
	end
	local minCorner = region.CFrame.Position - region.Size / 2
	local size = materials.Size
	local ix = math.clamp(math.floor((position.X - minCorner.X) / 4) + 1, 1, size.X)
	local iy = math.clamp(math.floor((position.Y - minCorner.Y) / 4) + 1, 1, size.Y)
	local iz = math.clamp(math.floor((position.Z - minCorner.Z) / 4) + 1, 1, size.Z)
	if materials[ix][iy][iz] ~= Enum.Material.Water then
		return false
	end
	local surfaceHeight = minCorner.Y + (iy - 1) * 4 + occupancies[ix][iy][iz] * 4
	return position.Y <= surfaceHeight
end

-- Retourne "water" | "oob" | nil
local function detectHazard(position)
	if #hazardParts > 0 then
		local hits = workspace:GetPartBoundsInRadius(position, BALL_RADIUS, hazardParams)
		if #hits > 0 then
			local kind = hits[1]:GetAttribute("Hazard")
			return if typeof(kind) == "string" then kind else "water"
		end
	end
	if Config.Ball.TerrainWater and inTerrainWater(position) then
		return "water"
	end
	return nil
end

--------------------------------------------------------------------------------
-- Création de la balle
--------------------------------------------------------------------------------

local function createBallInstance(player, position)
	local diameter = Config.Ball.Diameter

	local ball = Instance.new("Part")
	ball.Name = "GolfBall_" .. player.UserId
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(diameter, diameter, diameter)
	ball.Color = Config.Ball.Color
	ball.Material = Enum.Material.SmoothPlastic
	ball.Anchored = true
	ball.CanCollide = true
	ball.CollisionGroup = Config.CollisionGroups.Ball
	ball.CustomPhysicalProperties = makeProperties(Config.DefaultSurface)
	ball.CFrame = CFrame.new(position)
	ball:SetAttribute("OwnerUserId", player.UserId)
	ball:SetAttribute("State", "Resting")
	CollectionService:AddTag(ball, "GolfBall")

	-- Traînée (activée uniquement pendant le vol)
	local top = Instance.new("Attachment")
	top.Name = "TrailTop"
	top.Position = Vector3.new(0, diameter * 0.4, 0)
	top.Parent = ball
	local bottom = Instance.new("Attachment")
	bottom.Name = "TrailBottom"
	bottom.Position = Vector3.new(0, -diameter * 0.4, 0)
	bottom.Parent = ball

	local trail = Instance.new("Trail")
	trail.Name = "BallTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.45
	trail.LightEmission = 0.6
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Enabled = false
	trail.Parent = ball

	-- Gravité réduite : on annule (1 - GravityScale) de la gravité de Workspace.
	local center = Instance.new("Attachment")
	center.Name = "CenterAttachment"
	center.Parent = ball
	local antiGravity = Instance.new("VectorForce")
	antiGravity.Name = "GravityCompensation"
	antiGravity.Attachment0 = center
	antiGravity.RelativeTo = Enum.ActuatorRelativeTo.World
	antiGravity.ApplyAtCenterOfMass = true
	antiGravity.Force = Vector3.new(0, ball.Mass * workspace.Gravity * (1 - Config.Ball.GravityScale), 0)
	antiGravity.Parent = ball

	return ball, trail
end

--------------------------------------------------------------------------------
-- États de la balle
--------------------------------------------------------------------------------

local function leaveAim(player, data)
	if data.Aiming then
		data.Aiming = false
		player:SetAttribute("Aiming", false)
		MovementService.Unlock(player, "Aim")
	end
	data.SwingStart = nil
end

local function settle(player, data)
	local ball = data.Ball
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.Anchored = true
	data.State = "Resting"
	ball:SetAttribute("State", "Resting")
	data.Trail.Enabled = false
	data.LastValid = CFrame.new(ball.Position)
	restedEvent:Fire(player, ball.Position)
end

local function respawnAtLastValid(player, data, reason)
	local ball = data.Ball
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.Anchored = true
	ball.CFrame = data.LastValid
	data.State = "Resting"
	ball:SetAttribute("State", "Resting")
	data.Trail.Enabled = false

	local penalty = Config.Ball.HazardPenalty
	data.Strokes += penalty
	player:SetAttribute("Strokes", data.Strokes)

	respawnedEvent:Fire(player, reason)
	local template = HAZARD_MESSAGES[reason] or HAZARD_MESSAGES.oob
	Net.Get("Notify"):FireClient(player, string.format(template, penalty), "warn")
end

local function launch(player, data, direction, loftDegrees, power)
	local ball = data.Ball

	data.Strokes += 1
	player:SetAttribute("Strokes", data.Strokes)
	leaveAim(player, data)

	data.State = "Moving"
	ball:SetAttribute("State", "Moving")
	data.RestTimer = 0
	data.HazardTimer = 0
	data.MoveStart = now()
	data.LastShotTime = data.MoveStart
	data.HitCooldowns = {}
	data.Trail.Enabled = true

	local loft = math.rad(loftDegrees)
	local speed = Config.Shot.MinSpeed + (Config.Shot.MaxSpeed - Config.Shot.MinSpeed) * power
	local velocity = (direction * math.cos(loft) + Vector3.new(0, math.sin(loft), 0)) * speed

	ball.CFrame = ball.CFrame + Vector3.new(0, 0.1, 0) -- décolle légèrement du sol
	ball.Anchored = false
	-- Propriété serveur explicite (voir l'en-tête du module).
	pcall(function()
		ball:SetNetworkOwner(nil)
	end)
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.AssemblyLinearVelocity = velocity -- équivaut à ApplyImpulse(velocity * ball.AssemblyMass)

	shotEvent:Fire(player, data.Strokes, power)
end

local function checkPlayerHits(player, data, ball, velocity, time)
	local radius = BALL_RADIUS + Config.Stun.HitRadiusExtra
	local parts = workspace:GetPartBoundsInRadius(ball.Position, radius, hitParams)
	for _, part in parts do
		local character = part:FindFirstAncestorOfClass("Model")
		local victim = character and Players:GetPlayerFromCharacter(character)
		if victim and victim ~= player then
			local last = data.HitCooldowns[victim]
			if not last or time - last > Config.Stun.HitCooldown then
				data.HitCooldowns[victim] = time

				local knock = Vector3.new(0, Config.Stun.BallKnockUp, 0)
				local flat = Vector3.new(velocity.X, 0, velocity.Z)
				if flat.Magnitude > 0.1 then
					knock += flat.Unit * Config.Stun.BallKnockback
				end

				if StunService.Stun(victim, Config.Stun.Duration, knock) then
					ball.AssemblyLinearVelocity = velocity * Config.Stun.BallSlowdown
					playerHitEvent:Fire(player, victim)
					Net.Get("Notify"):FireClient(player, victim.DisplayName .. " est assommé !", "hit")
					Net.Get("Notify"):FireClient(victim, "Assommé par " .. player.DisplayName .. " !", "warn")
					return
				end
			end
		end
	end
end

local function stepBall(player, data, dt, time)
	local ball = data.Ball
	if not ball.Parent then
		return
	end

	local position = ball.Position
	local velocity = ball.AssemblyLinearVelocity

	-- 1. Hors limites / eau
	if position.Y < Config.Ball.KillHeight then
		respawnAtLastValid(player, data, "void")
		return
	end
	data.HazardTimer += dt
	if data.HazardTimer >= 0.1 then
		data.HazardTimer = 0
		local hazard = detectHazard(position)
		if hazard then
			respawnAtLastValid(player, data, hazard)
			return
		end
	end

	-- 2. Sol et surface
	local result = workspace:Raycast(position, Vector3.new(0, -(BALL_RADIUS + Config.Ball.GroundRayExtra), 0), rayParams)
	local grounded = result ~= nil
	if result then
		applySurface(data, surfaceFromHit(result))
	end
	local surface = Config.Surfaces[data.Surface or Config.DefaultSurface]

	-- 3. Vent (en l'air) et friction de roulement (au sol)
	if not grounded and wind.Magnitude > 0 then
		velocity += wind * dt
	end
	if grounded and math.abs(velocity.Y) < Config.Ball.DragMaxVerticalSpeed then
		local factor = math.max(0, 1 - surface.Drag * dt)
		velocity *= factor
		ball.AssemblyAngularVelocity *= factor
	end
	if velocity.Magnitude > Config.Ball.MaxSpeed then
		velocity = velocity.Unit * Config.Ball.MaxSpeed
	end
	ball.AssemblyLinearVelocity = velocity

	-- 4. Impact sur un adversaire
	local speed = velocity.Magnitude
	if speed >= Config.Stun.BallMinSpeed then
		checkPlayerHits(player, data, ball, velocity, time)
	end

	-- 5. Arrêt de la balle
	if grounded and speed < Config.Ball.RestSpeed then
		data.RestTimer += dt
		if data.RestTimer >= Config.Ball.RestTime then
			settle(player, data)
			return
		end
	else
		data.RestTimer = 0
	end
	if time - data.MoveStart > Config.Ball.MaxMoveTime then
		settle(player, data)
	end
end

local function onHeartbeat(dt)
	local time = now()
	for player, data in balls do
		if data.State == "Moving" then
			stepBall(player, data, dt, time)
		end
	end
end

--------------------------------------------------------------------------------
-- Remotes (entrées client : toujours considérées comme non fiables)
--------------------------------------------------------------------------------

local function canEnterAim(player, data)
	if data.State ~= "Resting" then
		return "ball_moving"
	end
	if StunService.IsStunned(player) then
		return "stun"
	end
	if now() < (data.AimBlockedUntil or 0) then
		return "blocked"
	end
	if not canShoot(player) then
		return "unavailable"
	end
	if not isNear(player, data.Ball, Config.Shot.AimEnterDistance + Config.Shot.DistanceTolerance) then
		return "too_far"
	end
	return nil
end

local function onAimState(player, wantsAim)
	if typeof(wantsAim) ~= "boolean" then
		return
	end
	local data = balls[player]
	if not data then
		return
	end

	if not wantsAim then
		leaveAim(player, data)
		return
	end
	if data.Aiming then
		return
	end

	local refusal = canEnterAim(player, data)
	if refusal then
		Net.Get("AimCancelled"):FireClient(player, refusal)
		return
	end

	data.Aiming = true
	data.SwingStart = nil
	player:SetAttribute("Aiming", true)
	MovementService.Lock(player, "Aim")
end

local function onSwingStart(player)
	if rateLimited(player, "SwingStart", 0.1) then
		return
	end
	local data = balls[player]
	if data and data.Aiming and data.State == "Resting" then
		data.SwingStart = now()
	end
end

local function onShoot(player, direction, loftDegrees, clientPower)
	if rateLimited(player, "Shoot", 0.1) then
		return
	end
	local data = balls[player]
	if not data or data.State ~= "Resting" or not data.Aiming or not data.SwingStart then
		return
	end

	-- Types et valeurs : un exploiteur peut envoyer n'importe quoi (nil, NaN, inf, Vector3 géant...).
	if not isFiniteVector(direction) then
		BallService.CancelAim(player, "invalid")
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.05 then
		BallService.CancelAim(player, "invalid")
		return
	end
	flat = flat.Unit

	if not isFiniteNumber(loftDegrees) then
		loftDegrees = Config.Shot.DefaultLoft
	end
	loftDegrees = math.clamp(loftDegrees, Config.Shot.MinLoft, Config.Shot.MaxLoft)

	local time = now()
	local elapsed = time - data.SwingStart
	if elapsed < Config.Shot.MinSwingTime or elapsed > Config.Shot.MaxSwingTime then
		BallService.CancelAim(player, "invalid")
		return
	end
	if time - (data.LastShotTime or -math.huge) < Config.Shot.Cooldown then
		BallService.CancelAim(player, "invalid")
		return
	end
	if StunService.IsStunned(player) then
		BallService.CancelAim(player, "stun")
		return
	end
	if not canShoot(player) then
		BallService.CancelAim(player, "unavailable")
		return
	end
	if not isNear(player, data.Ball, Config.Shot.AimEnterDistance + Config.Shot.DistanceTolerance) then
		BallService.CancelAim(player, "too_far")
		return
	end

	-- Puissance autoritaire : recalculée depuis le temps serveur, la valeur client n'est qu'indicative.
	local serverPower = Config.PowerAtTime(elapsed)
	local power = serverPower
	if isFiniteNumber(clientPower) then
		local tolerance = Config.Shot.PowerTolerance
		power = math.clamp(clientPower, serverPower - tolerance, serverPower + tolerance)
	end
	power = math.clamp(power, 0, 1)

	launch(player, data, flat, loftDegrees, power)
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

function BallService.SpawnBall(player, position, snap)
	BallService.RemoveBall(player)

	local spawnPosition = toPosition(position)
	if snap ~= false then
		spawnPosition = snapToGround(spawnPosition)
	end

	local ball, trail = createBallInstance(player, spawnPosition)
	ball.Parent = ballsFolder

	balls[player] = {
		Ball = ball,
		Trail = trail,
		State = "Resting",
		Aiming = false,
		Strokes = 0,
		LastValid = CFrame.new(spawnPosition),
		HitCooldowns = {},
		RestTimer = 0,
		HazardTimer = 0,
		MoveStart = 0,
	}
	player:SetAttribute("Strokes", 0)
	player:SetAttribute("Aiming", false)
	return ball
end

function BallService.PlaceBall(player, position, snap)
	local data = balls[player]
	if not data then
		return BallService.SpawnBall(player, position, snap)
	end
	leaveAim(player, data)

	local target = toPosition(position)
	if snap ~= false then
		target = snapToGround(target)
	end

	local ball = data.Ball
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.Anchored = true
	ball.Transparency = 0
	ball.CFrame = CFrame.new(target)
	data.State = "Resting"
	ball:SetAttribute("State", "Resting")
	data.Trail.Enabled = false
	data.LastValid = CFrame.new(target)
	return ball
end

function BallService.HoleBall(player)
	local data = balls[player]
	if not data then
		return
	end
	leaveAim(player, data)
	local ball = data.Ball
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.Anchored = true
	ball.Transparency = 1
	data.State = "Holed"
	ball:SetAttribute("State", "Holed")
	data.Trail.Enabled = false
end

function BallService.RemoveBall(player)
	local data = balls[player]
	if not data then
		return
	end
	leaveAim(player, data)
	balls[player] = nil
	data.Ball:Destroy()
end

function BallService.GetBall(player)
	local data = balls[player]
	return data and data.Ball
end

function BallService.GetState(player)
	local data = balls[player]
	return data and data.State
end

function BallService.GetStrokes(player)
	local data = balls[player]
	return data and data.Strokes or 0
end

function BallService.ResetStrokes(player)
	local data = balls[player]
	if data then
		data.Strokes = 0
	end
	player:SetAttribute("Strokes", 0)
end

function BallService.CancelAim(player, reason, blockSeconds)
	local data = balls[player]
	if not data then
		return
	end
	local wasAiming = data.Aiming
	leaveAim(player, data)
	if blockSeconds then
		data.AimBlockedUntil = now() + blockSeconds
	end
	if wasAiming then
		Net.Get("AimCancelled"):FireClient(player, reason)
	end
end

function BallService.SetWind(vector)
	wind = if isFiniteVector(vector) then vector else Vector3.zero
end

function BallService.SetCanShoot(predicate)
	canShoot = predicate
end

--------------------------------------------------------------------------------
-- Initialisation
--------------------------------------------------------------------------------

function BallService.Init()
	ballsFolder = Instance.new("Folder")
	ballsFolder.Name = "Balls"
	ballsFolder.Parent = workspace

	-- Le raycast "voit" ce que le groupe Balls voit : ni personnages ni autres balles.
	rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { ballsFolder }
	rayParams.IgnoreWater = true
	rayParams.CollisionGroup = Config.CollisionGroups.Ball

	hitParams = OverlapParams.new()
	hitParams.FilterType = Enum.RaycastFilterType.Include
	hitParams.FilterDescendantsInstances = characterModels

	hazardParams = OverlapParams.new()
	hazardParams.FilterType = Enum.RaycastFilterType.Include
	hazardParams.FilterDescendantsInstances = hazardParts

	-- Zones d'eau / hors limites en Parts : tag CollectionService (attribut optionnel Hazard = "water" | "oob")
	local tag = Config.Ball.HazardTag
	local function addHazard(instance)
		if instance:IsA("BasePart") and not table.find(hazardParts, instance) then
			table.insert(hazardParts, instance)
			hazardParams.FilterDescendantsInstances = hazardParts
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(addHazard)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		local index = table.find(hazardParts, instance)
		if index then
			table.remove(hazardParts, index)
			hazardParams.FilterDescendantsInstances = hazardParts
		end
	end)
	for _, instance in CollectionService:GetTagged(tag) do
		addHazard(instance)
	end

	-- Personnages interrogeables pour les impacts
	local function trackPlayer(player)
		local function add(character)
			table.insert(characterModels, character)
			hitParams.FilterDescendantsInstances = characterModels
		end
		local function remove(character)
			local index = table.find(characterModels, character)
			if index then
				table.remove(characterModels, index)
			end
			hitParams.FilterDescendantsInstances = characterModels
			BallService.CancelAim(player, "respawn")
		end
		player.CharacterAdded:Connect(add)
		player.CharacterRemoving:Connect(remove)
		if player.Character then
			add(player.Character)
		end
	end
	Players.PlayerAdded:Connect(trackPlayer)
	for _, player in Players:GetPlayers() do
		trackPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		BallService.RemoveBall(player)
		rateLimits[player] = nil
	end)

	-- Un joueur étourdi quitte immédiatement le mode visée.
	StunService.Stunned:Connect(function(player)
		BallService.CancelAim(player, "stun")
	end)

	Net.Get("AimState").OnServerEvent:Connect(onAimState)
	Net.Get("SwingStart").OnServerEvent:Connect(onSwingStart)
	Net.Get("Shoot").OnServerEvent:Connect(onShoot)

	RunService.Heartbeat:Connect(onHeartbeat)
end

return BallService
