--!strict
--[[
	MovementService — source unique de vérité pour WalkSpeed / JumpPower et contrôle de plausibilité des
	déplacements (docs/ARCHITECTURE.md §8 et §11, priorité 10).

	VERROUS : plusieurs systèmes peuvent bloquer un joueur en même temps (visée, KO, gel, phase...).
	Chacun pose un verrou nommé ; le joueur ne bouge que si aucun verrou n'existe.
	  Lock(player, reason) / Unlock(player, reason) / IsLocked(player, reason?) / UnlockAll(player)
	Les verrous appartiennent au JOUEUR (ils survivent à une réapparition), sauf ceux listés dans
	Config.Movement.LocksClearedOnRespawn ("Aim", "KO", "Frozen"...) : aucun état temporaire ne survit
	à une réapparition, mais un verrou de phase posé par MatchService reste en place.

	MODIFICATEURS : SetModifier(player, key, speedMult, jumpMult?, duration?) — même clé = remplacement
	(réutiliser rafraîchit la durée, sans cumul multiplicatif) ; expiration automatique ; produit de toutes
	les clés, borné. ClearModifier(player, key) / ClearModifiers(player) / GetMultipliers(player).

	PLAUSIBILITÉ : les personnages sont simulés par leur client (réactivité). Toutes les SampleInterval s,
	le serveur compare le déplacement du HumanoidRootPart à ce qu'autorisent la vitesse max (effets compris),
	la tolérance, une marge, la vitesse du sol porteur (voiturette, plateforme, tapis) et le saut.
	Exemptés : fenêtres AllowDisplacement (propulsion, téléportation, recul), réapparition récente, joueur
	assis / en véhicule (attribut InVehicle), KO (attribut KnockedOut), pièce ancrée.
	Une infraction est signalée à NetworkValidation ; le joueur n'est replacé à sa dernière position plausible
	qu'après ViolationsBeforeCorrection infractions dans la fenêtre (ou une téléportation flagrante).
	Les propulsions, téléportations et réapparitions autorisées par le jeu ne sont jamais punies.
	  AllowDisplacement(player, seconds, reason) / Teleport(player, cframe) / Refresh(player)

	VITESSE DE JEU : pendant une partie, MatchSettings.gameSpeed (lu dans GameState.SettingsJson) multiplie
	la vitesse de marche (Config.Movement.ApplyGameSpeed).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.Gameplay)
local BallMath = require(Shared.Logic.BallMath)
local GameState = require(Shared.Util.GameState)
local Log = require(Shared.Util.Log)
local TroveModule = require(Shared.Util.Trove)
local Validate = require(Shared.Util.Validate)

local NetworkValidation = require(script.Parent.NetworkValidation)

type Trove = TroveModule.Trove

type Modifier = {
	speed: number,
	jump: number,
	expiresAt: number?,
	thread: thread?,
}

type PlayerMovement = {
	trove: Trove,
	locks: { [string]: boolean },
	modifiers: { [string]: Modifier },
	exemptUntil: number,
	exemptReason: string,
	graceUntil: number,
	-- plausibilité
	lastSample: Vector3?,
	lastSampleTime: number,
	lastValid: CFrame?,
	peakSpeed: number, -- vitesse max appliquée depuis le dernier échantillon
	peakJump: number,
	violations: { number },
}

local MovementService = {}
MovementService.Priority = 10

local MOVEMENT = Config.Movement
local PLAUSIBILITY = Config.Movement.Plausibility

local states: { [Player]: PlayerMovement } = {}
local gameSpeed = 1
local initialized = false
local loopThread: thread? = nil
local probeParams: RaycastParams? = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function getState(player: Player): PlayerMovement?
	if not isPlayer(player) then
		return nil
	end
	local state = states[player]
	if not state and player.Parent == Players then
		state = {
			trove = TroveModule.new(),
			locks = {},
			modifiers = {},
			exemptUntil = 0,
			exemptReason = "",
			graceUntil = 0,
			lastSample = nil,
			lastSampleTime = 0,
			lastValid = nil,
			peakSpeed = 0,
			peakJump = 0,
			violations = {},
		}
		states[player] = state
	end
	return state
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function hasLocks(state: PlayerMovement): boolean
	return next(state.locks) ~= nil
end

-- Produit des modificateurs actifs, borné.
local function multipliers(state: PlayerMovement): (number, number)
	local speed, jump = 1, 1
	for _, modifier in state.modifiers do
		speed *= modifier.speed
		jump *= modifier.jump
	end
	return math.clamp(speed, MOVEMENT.MinSpeedMultiplier, MOVEMENT.MaxSpeedMultiplier),
		math.clamp(jump, 0, MOVEMENT.MaxJumpMultiplier)
end

-- Vitesse et saut qui s'appliqueraient sans verrou (référence du contrôle de plausibilité).
local function unlockedValues(state: PlayerMovement): (number, number)
	local speed, jump = multipliers(state)
	return MOVEMENT.WalkSpeed * gameSpeed * speed, MOVEMENT.JumpPower * jump
end

local function jumpHeight(jumpPower: number): number
	local gravity = Workspace.Gravity
	if gravity <= 0 then
		return 50
	end
	return (jumpPower * jumpPower) / (2 * gravity)
end

local function resetSamples(state: PlayerMovement, cframe: CFrame?)
	state.lastSample = if cframe then cframe.Position else nil
	state.lastSampleTime = now()
	state.lastValid = cframe
	state.violations = {}
	local speed, jump = unlockedValues(state)
	state.peakSpeed = speed
	state.peakJump = jump
end

--------------------------------------------------------------------------------
-- Application aux Humanoids
--------------------------------------------------------------------------------

function MovementService.Refresh(player: Player)
	local state = getState(player)
	if not state then
		return
	end
	local humanoid = getHumanoid(player)
	if not humanoid then
		return
	end
	local walk, jump = unlockedValues(state)
	state.peakSpeed = math.max(state.peakSpeed, walk)
	state.peakJump = math.max(state.peakJump, jump)
	humanoid.UseJumpPower = true
	if hasLocks(state) then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	else
		humanoid.WalkSpeed = walk
		humanoid.JumpPower = jump
	end
end

local function refreshAll()
	for _, player in Players:GetPlayers() do
		MovementService.Refresh(player)
	end
end

--------------------------------------------------------------------------------
-- Verrous
--------------------------------------------------------------------------------

function MovementService.Lock(player: Player, reason: string)
	local state = getState(player)
	if not state or type(reason) ~= "string" or reason == "" then
		return
	end
	if not state.locks[reason] then
		state.locks[reason] = true
		MovementService.Refresh(player)
	end
end

function MovementService.Unlock(player: Player, reason: string)
	local state = states[player]
	if not state or type(reason) ~= "string" then
		return
	end
	if state.locks[reason] then
		state.locks[reason] = nil
		MovementService.Refresh(player)
	end
end

function MovementService.UnlockAll(player: Player)
	local state = states[player]
	if not state then
		return
	end
	table.clear(state.locks)
	MovementService.Refresh(player)
end

function MovementService.IsLocked(player: Player, reason: string?): boolean
	local state = states[player]
	if not state then
		return false
	end
	if reason ~= nil then
		return state.locks[reason] == true
	end
	return hasLocks(state)
end

function MovementService.GetLocks(player: Player): { string }
	local list = {}
	local state = states[player]
	if state then
		for reason in state.locks do
			table.insert(list, reason)
		end
		table.sort(list)
	end
	return list
end

--------------------------------------------------------------------------------
-- Modificateurs
--------------------------------------------------------------------------------

local function removeModifier(state: PlayerMovement, key: string): boolean
	local modifier = state.modifiers[key]
	if not modifier then
		return false
	end
	state.modifiers[key] = nil
	local thread = modifier.thread
	if thread and thread ~= coroutine.running() and coroutine.status(thread) ~= "dead" then
		pcall(task.cancel, thread)
	end
	return true
end

-- Remplace (ou crée) le modificateur `key`. duration nil/<= 0 : jusqu'à ClearModifier/ClearModifiers.
function MovementService.SetModifier(player: Player, key: string, speedMult: number, jumpMult: number?, duration: number?)
	local state = getState(player)
	if not state or type(key) ~= "string" or key == "" then
		return
	end
	local speed = Validate.clampNumber(speedMult, 0, MOVEMENT.MaxSpeedMultiplier, 1)
	local jump = Validate.clampNumber(jumpMult, 0, MOVEMENT.MaxJumpMultiplier, 1)
	removeModifier(state, key)
	local modifier: Modifier = { speed = speed, jump = jump, expiresAt = nil, thread = nil }
	if duration ~= nil and Validate.isFiniteNumber(duration) and duration > 0 then
		modifier.expiresAt = now() + duration
		modifier.thread = task.delay(duration, function()
			local current = states[player]
			if current and current.modifiers[key] == modifier then
				current.modifiers[key] = nil
				MovementService.Refresh(player)
			end
		end)
	end
	state.modifiers[key] = modifier
	MovementService.Refresh(player)
end

function MovementService.ClearModifier(player: Player, key: string)
	local state = states[player]
	if state and removeModifier(state, key) then
		MovementService.Refresh(player)
	end
end

function MovementService.ClearModifiers(player: Player)
	local state = states[player]
	if not state then
		return
	end
	local keys = {}
	for key in state.modifiers do
		table.insert(keys, key)
	end
	for _, key in keys do
		removeModifier(state, key)
	end
	MovementService.Refresh(player)
end

function MovementService.GetMultipliers(player: Player): (number, number)
	local state = states[player]
	if not state then
		return 1, 1
	end
	return multipliers(state)
end

-- Vitesse de marche maximale actuellement autorisée (hors verrous), effets et vitesse de jeu compris.
function MovementService.GetMaxWalkSpeed(player: Player): number
	local state = states[player]
	if not state then
		return MOVEMENT.WalkSpeed * gameSpeed
	end
	local walk = unlockedValues(state)
	return walk
end

--------------------------------------------------------------------------------
-- Exemptions et téléportation serveur
--------------------------------------------------------------------------------

-- Exempte le joueur du contrôle de plausibilité pendant `seconds` (propulsion, recul, téléportation...).
function MovementService.AllowDisplacement(player: Player, seconds: number, reason: string?)
	local state = getState(player)
	if not state then
		return
	end
	local duration = Validate.clampNumber(seconds, 0, 30, 0)
	local untilTime = now() + duration
	if untilTime > state.exemptUntil then
		state.exemptUntil = untilTime
		state.exemptReason = if type(reason) == "string" then reason else "unspecified"
	end
end

function MovementService.IsExempt(player: Player): boolean
	local state = states[player]
	if not state then
		return false
	end
	local time = now()
	return time < state.exemptUntil or time < state.graceUntil
end

-- Téléportation serveur autorisée (jamais signalée comme triche).
function MovementService.Teleport(player: Player, cframe: CFrame): boolean
	local state = getState(player)
	local character = player.Character
	if not state or not character or not Validate.isFiniteCFrame(cframe) then
		return false
	end
	MovementService.AllowDisplacement(player, PLAUSIBILITY.TeleportGrace, "teleport")
	local root = getRoot(player)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	character:PivotTo(cframe)
	resetSamples(state, cframe)
	return true
end

--------------------------------------------------------------------------------
-- Contrôle de plausibilité
--------------------------------------------------------------------------------

-- Vitesse horizontale du sol porteur (voiturette, plateforme mobile, tapis roulant : AssemblyLinearVelocity).
local function floorSpeed(character: Model, root: BasePart): number
	local params = probeParams
	if not params then
		return 0
	end
	params.FilterDescendantsInstances = { character }
	local result = Workspace:Raycast(root.Position, Vector3.new(0, -PLAUSIBILITY.FloorProbeDepth, 0), params)
	if not result then
		return 0
	end
	local hit = result.Instance
	if hit:IsA("BasePart") then
		local velocity = hit.AssemblyLinearVelocity
		if BallMath.isFiniteVector(velocity) then
			return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		end
	end
	return 0
end

local function pruneViolations(state: PlayerMovement, time: number)
	local kept = {}
	for _, at in state.violations do
		if time - at <= PLAUSIBILITY.ViolationWindow then
			table.insert(kept, at)
		end
	end
	state.violations = kept
end

local function correct(player: Player, state: PlayerMovement, reason: string)
	local target = state.lastValid
	if not target then
		resetSamples(state, nil)
		return
	end
	NetworkValidation.Report(player, "movement_corrected", { reason = reason })
	Log.info("Movement", "position corrigée :", player.Name, reason)
	MovementService.Teleport(player, target)
end

local function checkPlayer(player: Player, state: PlayerMovement, time: number)
	local character = player.Character
	local humanoid = getHumanoid(player)
	local root = getRoot(player)
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		state.lastSample = nil
		return
	end
	local position = root.Position
	if not BallMath.isFiniteVector(position) then
		NetworkValidation.Report(player, "movement_nonfinite")
		correct(player, state, "nonfinite")
		return
	end

	local exempt = time < state.exemptUntil
		or time < state.graceUntil
		or humanoid.SeatPart ~= nil
		or player:GetAttribute("InVehicle") == true
		or player:GetAttribute("KnockedOut") == true
		or root.Anchored
	local last = state.lastSample
	if exempt or last == nil then
		-- Déplacement autorisé : la position courante devient la nouvelle référence plausible.
		resetSamples(state, root.CFrame)
		return
	end

	local dt = math.clamp(time - state.lastSampleTime, PLAUSIBILITY.MinDt, PLAUSIBILITY.MaxDt)
	local delta = position - last
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local rise = math.max(0, delta.Y)

	local unlockedWalk, unlockedJump = unlockedValues(state)
	local maxSpeed = math.max(state.peakSpeed, unlockedWalk)
	local allowedHorizontal = (maxSpeed * PLAUSIBILITY.Tolerance + floorSpeed(character, root)) * dt
		+ PLAUSIBILITY.Allowance
	local allowedRise = jumpHeight(math.max(state.peakJump, unlockedJump)) * PLAUSIBILITY.Tolerance
		+ PLAUSIBILITY.RiseAllowance
		+ allowedHorizontal * PLAUSIBILITY.SlopeFactor

	state.lastSample = position
	state.lastSampleTime = time
	state.peakSpeed = unlockedWalk
	state.peakJump = unlockedJump

	if horizontal <= allowedHorizontal and rise <= allowedRise then
		state.lastValid = root.CFrame
		return
	end

	-- Infraction : signalée ; correction seulement si répétée (ou flagrante).
	local ratio = math.max(horizontal / allowedHorizontal, rise / math.max(allowedRise, 1e-3))
	NetworkValidation.Report(player, "movement_speed", {
		horizontal = horizontal,
		allowed = allowedHorizontal,
		rise = rise,
		dt = dt,
	})
	pruneViolations(state, time)
	local weight = if ratio >= PLAUSIBILITY.FlagrantRatio then PLAUSIBILITY.ViolationsBeforeCorrection else 1
	for _ = 1, weight do
		table.insert(state.violations, time)
	end
	if #state.violations >= PLAUSIBILITY.ViolationsBeforeCorrection then
		correct(player, state, if weight > 1 then "flagrant" else "repeated")
	end
end

local function plausibilityLoop()
	while true do
		task.wait(PLAUSIBILITY.SampleInterval)
		if PLAUSIBILITY.Enabled then
			local time = now()
			for player, state in states do
				if player.Parent == Players then
					local ok, err = pcall(checkPlayer, player, state, time)
					if not ok then
						Log.warn("Movement", "contrôle de plausibilité :", player.Name, err)
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Vitesse de jeu (MatchSettings.gameSpeed pendant une partie)
--------------------------------------------------------------------------------

local function readGameSpeed(): number
	if not MOVEMENT.ApplyGameSpeed then
		return 1
	end
	local phase = GameState.read("Phase")
	local json = GameState.read("SettingsJson")
	local settingsSpeed: number? = nil
	if type(json) == "string" and json ~= "" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
		if ok and type(decoded) == "table" and type(decoded.gameSpeed) == "number" then
			settingsSpeed = decoded.gameSpeed
		end
	end
	return BallMath.effectiveGameSpeed(if type(phase) == "string" then phase else nil, settingsSpeed)
end

local function updateGameSpeed()
	local speed = readGameSpeed()
	if speed ~= gameSpeed then
		gameSpeed = speed
		refreshAll()
	end
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

local function onCharacterRemoving(player: Player)
	local state = states[player]
	if not state then
		return
	end
	local changed = false
	for _, reason in MOVEMENT.LocksClearedOnRespawn do
		if state.locks[reason] then
			state.locks[reason] = nil
			changed = true
		end
	end
	if MOVEMENT.ClearModifiersOnRespawn and next(state.modifiers) ~= nil then
		local keys = {}
		for key in state.modifiers do
			table.insert(keys, key)
		end
		for _, key in keys do
			removeModifier(state, key)
		end
		changed = true
	end
	state.lastSample = nil
	if changed then
		Log.debug("Movement", "états temporaires retirés à la disparition du personnage :", player.Name)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local state = getState(player)
	if not state then
		return
	end
	state.graceUntil = now() + PLAUSIBILITY.RespawnGrace
	resetSamples(state, nil)
	if character:FindFirstChildOfClass("Humanoid") then
		MovementService.Refresh(player)
		return
	end
	-- Le Humanoid peut arriver juste après le modèle : on attend dans un fil dédié (borné).
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and player.Character == character then
			MovementService.Refresh(player)
		end
	end)
end

local function setupPlayer(player: Player)
	local state = getState(player)
	if not state then
		return
	end
	state.trove:Connect(player.CharacterAdded, function(character: Model)
		onCharacterAdded(player, character)
	end)
	state.trove:Connect(player.CharacterRemoving, function()
		onCharacterRemoving(player)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

local function cleanupPlayer(player: Player)
	local state = states[player]
	if not state then
		return
	end
	for key in state.modifiers do
		local modifier = state.modifiers[key]
		local thread = modifier.thread
		if thread and coroutine.status(thread) ~= "dead" then
			pcall(task.cancel, thread)
		end
	end
	state.trove:Destroy()
	states[player] = nil
end

function MovementService.Init()
	if initialized then
		return
	end
	initialized = true

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	probeParams = params

	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(cleanupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end

	GameState.changed("Phase", updateGameSpeed)
	GameState.changed("SettingsJson", updateGameSpeed)
	updateGameSpeed()
end

function MovementService.Start()
	if loopThread == nil then
		loopThread = task.spawn(plausibilityLoop)
	end
end

return MovementService
