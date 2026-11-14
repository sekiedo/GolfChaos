--!strict
--[[
	CombatService — KO cartoon, recul, protection, frappe de proximité, plongeon (docs/ARCHITECTURE.md §8,
	priorité 15). Port du StunService du prototype : « étourdissement » devient « KO » (attribut KnockedOut).

	  Knockout(victim, opts) -> (boolean, raison?)   opts = { attacker: Player?, source: string,
	                                                 duration: number?, knock: Vector3?, major: boolean? }
	  Knockback(player, velocity, opts?) -> boolean  recul sans KO (opts = { attacker?, source?, duration?, exemption? })
	  BallHit(owner, victim, velocity) -> boolean    impact d'une balle (appelé par BallService)
	  IsKnockedOut(player) / IsProtected(player) / IsDodging(player)
	  GrantProtection(player, seconds) / EndProtection(player)
	  CanAffect(attacker?, victim) -> boolean        / AffectRefusal(attacker?, victim) -> raison?
	  SetShieldHandler(fn(victim, info) -> "blocked" | "broken" | nil)   (fourni par ItemService)
	  Signaux : KnockedOut(victim, attacker?, source), Recovered(victim)
	  Intentions : Combat.Punch(roundId, direction), Combat.Dive(roundId, direction)

	RÈGLES (Config/Gameplay.KO, docs/MATRICE_INTERACTIONS.md) :
	  - Un joueur protégé (réapparition, 3 s, attribut Protected) ne peut être ni KO ni repoussé ; attaquer met
	    fin à sa propre protection.
	  - Anti-KO répété : même attaquant -> même victime = délai de 8 s ; immunité de 1,5 s après chaque relève ;
	    durées dégressives (× 0,75 puis × 0,5) quand la victime enchaîne 3 KO ou plus en 20 s ; pas de cumul
	    sur un joueur déjà KO.
	  - Alliés (MatchService.AreAllies, sinon attribut Team) protégés sauf tir ami activé (jamais en mode Équipes).
	  - Joueur ayant terminé le trou (HoleFinished) ou spectateur : ne peut ni affecter ni être affecté.
	  - Combat actif seulement pendant les phases KO.AllowedPhases (accueil, préparation, partie).
	  - Bouclier : "blocked" = coup absorbé (aucun KO) ; "broken" = bouclier détruit, le KO a lieu SANS fort
	    recul (jamais d'élimination).

	PROPRIÉTÉ RÉSEAU : pendant un KO, le serveur prend la propriété du personnage (ragdoll et recul fiables,
	un client ne peut pas écraser la vitesse), puis la rend au joueur à la relève. Les poussées sans KO
	(plongeon, recul) passent par une LinearVelocity répliquée : le client propriétaire la simule, sans
	changement de propriété ; MovementService exempte alors le joueur du contrôle de plausibilité.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.Gameplay)
local BallMath = require(Shared.Logic.BallMath)
local GameState = require(Shared.Util.GameState)
local Log = require(Shared.Util.Log)
local Net = require(Shared.Net)
local SignalModule = require(Shared.Util.Signal)
local TroveModule = require(Shared.Util.Trove)
local Validate = require(Shared.Util.Validate)

local MovementService = require(script.Parent.MovementService)
local NetworkValidation = require(script.Parent.NetworkValidation)

type Signal = SignalModule.Signal
type Trove = TroveModule.Trove

export type KnockoutOptions = {
	attacker: Player?,
	source: string,
	duration: number?,
	knock: Vector3?,
	major: boolean?,
}

export type KnockbackOptions = {
	attacker: Player?,
	source: string?,
	duration: number?, -- durée de la poussée (s)
	exemption: number?, -- exemption de plausibilité (s)
}

export type ShieldInfo = {
	attacker: Player?,
	source: string,
	major: boolean,
	duration: number,
	knock: Vector3,
}

export type ShieldResult = ("blocked" | "broken")?
export type ShieldHandler = (victim: Player, info: ShieldInfo) -> ShieldResult

type RagdollRecord = {
	folder: Folder,
	joints: { Instance }, -- Motor6D / AnimationConstraint désactivés
	attachments: { Attachment }, -- créées pour les rotules (Motor6D)
	collide: { [BasePart]: boolean },
	requiresNeck: boolean,
	facing: Vector3,
}

type KOState = {
	character: Model,
	humanoid: Humanoid,
	endsAt: number,
	attacker: Player?,
	source: string,
	ragdoll: RagdollRecord?,
	thread: thread?,
}

type PushState = {
	attachment: Attachment,
	mover: LinearVelocity,
	thread: thread?,
}

type CombatState = {
	trove: Trove,
	ko: KOState?,
	protectedUntil: number,
	protectionToken: number,
	protectionThread: thread?,
	immuneUntil: number,
	koHistory: { number }, -- horodatages des KO subis (fenêtre dégressive)
	lastKOBy: { [number]: number }, -- UserId de l'attaquant -> dernier KO infligé à ce joueur
	punchReadyAt: number,
	diveReadyAt: number,
	dodgeUntil: number,
	dodgeToken: number,
	animToken: number,
	push: PushState?,
}

local CombatService = {}
CombatService.Priority = 15

CombatService.KnockedOut = SignalModule.new() :: Signal
CombatService.Recovered = SignalModule.new() :: Signal

local KO = Config.KO
local PUNCH = Config.Punch
local DIVE = Config.Dive
local KNOCKBACK = Config.Knockback
local BALL_HIT = Config.BallHit

local LOBBY_PHASES: { [string]: boolean } = { Lobby = true, Preparing = true }

local states: { [Player]: CombatState } = {}
local shieldHandler: ShieldHandler? = nil
local lineOfSightParams: RaycastParams? = nil
local initialized = false

type ServiceCacheEntry = { module: any?, checkedAt: number }
local serviceCache: { [string]: ServiceCacheEntry } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

-- Service facultatif (chargé à la demande, sans cycle de require au démarrage) ; nil s'il n'existe pas.
local function optionalService(name: string): any?
	local entry = serviceCache[name]
	local time = os.clock()
	if entry and (entry.module ~= nil or time - entry.checkedAt < 5) then
		return entry.module
	end
	local module = script.Parent:FindFirstChild(name)
	local loaded: any? = nil
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			loaded = result
		end
	end
	serviceCache[name] = { module = loaded, checkedAt = time }
	return loaded
end

local function cancelThread(thread: thread?)
	if thread and thread ~= coroutine.running() and coroutine.status(thread) ~= "dead" then
		pcall(task.cancel, thread)
	end
end

local function getState(player: Player): CombatState?
	if not isPlayer(player) then
		return nil
	end
	local state = states[player]
	if not state and player.Parent == Players then
		state = {
			trove = TroveModule.new(),
			ko = nil,
			protectedUntil = 0,
			protectionToken = 0,
			protectionThread = nil,
			immuneUntil = 0,
			koHistory = {},
			lastKOBy = {},
			punchReadyAt = 0,
			diveReadyAt = 0,
			dodgeUntil = 0,
			dodgeToken = 0,
			animToken = 0,
			push = nil,
		}
		states[player] = state
	end
	return state
end

local function currentPhase(): string
	local phase = GameState.read("Phase")
	return if type(phase) == "string" then phase else "Lobby"
end

local function phaseAllowsCombat(): boolean
	return table.find(KO.AllowedPhases, currentPhase()) ~= nil
end

local function clampMagnitude(vector: Vector3, maxMagnitude: number): Vector3
	local magnitude = vector.Magnitude
	if magnitude > maxMagnitude and magnitude > 0 then
		return vector * (maxMagnitude / magnitude)
	end
	return vector
end

local function flatUnit(vector: Vector3): Vector3?
	return Validate.flatUnit(vector)
end

local function feedback(player: Player, action: string, ok: boolean, reason: string?)
	Net.fire("Combat.Feedback", player, action, ok, reason)
end

local function setTimedAnimState(player: Player, state: CombatState, value: string, duration: number)
	local character = player.Character
	if not character then
		return
	end
	if character:GetAttribute("AnimState") == "KO" then
		return
	end
	state.animToken += 1
	local token = state.animToken
	character:SetAttribute("AnimState", value)
	task.delay(duration, function()
		if state.animToken == token and character.Parent and character:GetAttribute("AnimState") == value then
			character:SetAttribute("AnimState", "")
		end
	end)
end

--------------------------------------------------------------------------------
-- Règles : alliés, joueurs terminés, protection
--------------------------------------------------------------------------------

local function areAllies(a: Player, b: Player): boolean
	local MatchService = optionalService("MatchService")
	if MatchService and type(MatchService.AreAllies) == "function" then
		local ok, result = pcall(MatchService.AreAllies, a, b)
		if ok then
			return result == true
		end
	end
	local teamA, teamB = a:GetAttribute("Team"), b:GetAttribute("Team")
	return type(teamA) == "string" and teamA ~= "" and teamA == teamB
end

local function friendlyFireEnabled(): boolean
	local MatchService = optionalService("MatchService")
	if MatchService and type(MatchService.GetSettings) == "function" then
		local ok, settings = pcall(MatchService.GetSettings)
		if ok and type(settings) == "table" then
			if settings.mode == "Teams" then
				return false -- règle : jamais de KO entre alliés en mode Équipes
			end
			return settings.friendlyFire == true
		end
	end
	return false
end

-- Terminé / spectateur ne comptent que pendant une partie (à l'accueil, tout le monde peut chahuter).
local function isOutOfPlay(player: Player): boolean
	if LOBBY_PHASES[currentPhase()] then
		return false
	end
	return player:GetAttribute("HoleFinished") == true or player:GetAttribute("Spectating") == true
end

local function isProtectedNow(player: Player): boolean
	local state = states[player]
	return state ~= nil and now() < state.protectedUntil
end

-- Raison pour laquelle `attacker` (nil = environnement) ne peut pas affecter `victim`, ou nil si permis.
function CombatService.AffectRefusal(attacker: Player?, victim: Player): string?
	if not isPlayer(victim) or victim.Parent ~= Players then
		return "invalid"
	end
	if not phaseAllowsCombat() then
		return "phase"
	end
	if isOutOfPlay(victim) then
		return "finished"
	end
	if attacker ~= nil then
		if not isPlayer(attacker) then
			return "invalid"
		end
		if attacker == victim then
			return nil -- effet sur soi (recul de son propre tir...) : toujours permis
		end
		if isOutOfPlay(attacker) then
			return "finished"
		end
		if areAllies(attacker, victim) and not friendlyFireEnabled() then
			return "ally"
		end
	end
	if isProtectedNow(victim) then
		return "protected"
	end
	return nil
end

function CombatService.CanAffect(attacker: Player?, victim: Player): boolean
	return CombatService.AffectRefusal(attacker, victim) == nil
end

function CombatService.IsKnockedOut(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.ko ~= nil
end

function CombatService.IsProtected(player: Player): boolean
	return isProtectedNow(player)
end

function CombatService.IsDodging(player: Player): boolean
	local state = states[player]
	return state ~= nil and now() < state.dodgeUntil
end

function CombatService.GrantProtection(player: Player, seconds: number)
	local state = getState(player)
	if not state then
		return
	end
	local duration = Validate.clampNumber(seconds, 0, 60, 0)
	if duration <= 0 then
		return
	end
	local time = now()
	state.protectedUntil = math.max(state.protectedUntil, time + duration)
	state.protectionToken += 1
	local token = state.protectionToken
	cancelThread(state.protectionThread)
	player:SetAttribute("Protected", true)
	state.protectionThread = task.delay(state.protectedUntil - time, function()
		if states[player] == state and state.protectionToken == token then
			state.protectedUntil = 0
			state.protectionThread = nil
			if player.Parent then
				player:SetAttribute("Protected", false)
			end
		end
	end)
end

function CombatService.EndProtection(player: Player)
	local state = states[player]
	if not state or state.protectedUntil <= 0 then
		return
	end
	state.protectedUntil = 0
	state.protectionToken += 1
	cancelThread(state.protectionThread)
	state.protectionThread = nil
	if player.Parent then
		player:SetAttribute("Protected", false)
	end
end

function CombatService.SetShieldHandler(handler: ShieldHandler?)
	if handler ~= nil and type(handler) ~= "function" then
		Log.warn("Combat", "SetShieldHandler : fonction attendue")
		return
	end
	shieldHandler = handler
end

local function consultShield(victim: Player, info: ShieldInfo): ShieldResult
	local handler = shieldHandler
	if not handler then
		return nil
	end
	local ok, result = pcall(handler, victim, info)
	if not ok then
		Log.warn("Combat", "gestionnaire de bouclier en erreur :", result)
		return nil
	end
	if result == "blocked" or result == "broken" then
		return result
	end
	return nil
end

--------------------------------------------------------------------------------
-- Ragdoll (port du prototype, compatible Motor6D et AnimationConstraint)
--------------------------------------------------------------------------------

local function setOwnership(character: Model, owner: Player?, auto: boolean)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant.Anchored then
			pcall(function()
				if auto then
					descendant:SetNetworkOwnershipAuto()
				else
					descendant:SetNetworkOwner(owner)
				end
			end)
		end
	end
end

local function makeSocket(record: RagdollRecord, a0: Attachment, a1: Attachment, isNeck: boolean)
	local socket = Instance.new("BallSocketConstraint")
	socket.Name = "RagdollSocket"
	socket.Attachment0 = a0
	socket.Attachment1 = a1
	socket.LimitsEnabled = true
	socket.TwistLimitsEnabled = true
	socket.UpperAngle = if isNeck then KO.RagdollNeckAngle else KO.RagdollUpperAngle
	socket.TwistLowerAngle = -KO.RagdollTwistAngle
	socket.TwistUpperAngle = KO.RagdollTwistAngle
	socket.Parent = record.folder

	-- Évite que deux membres voisins se repoussent (tremblements).
	local part0, part1 = a0.Parent, a1.Parent
	if part0 and part1 and part0:IsA("BasePart") and part1:IsA("BasePart") then
		local noCollide = Instance.new("NoCollisionConstraint")
		noCollide.Name = "RagdollNoCollide"
		noCollide.Part0 = part0
		noCollide.Part1 = part1
		noCollide.Parent = record.folder
	end
end

local function isCosmeticOrTool(instance: Instance): boolean
	return instance:FindFirstAncestorWhichIsA("Accessory") ~= nil or instance:FindFirstAncestorWhichIsA("Tool") ~= nil
end

local function startRagdoll(character: Model, humanoid: Humanoid, root: BasePart, knock: Vector3): RagdollRecord
	local look = root.CFrame.LookVector
	local folder = Instance.new("Folder")
	folder.Name = "Ragdoll"
	local record: RagdollRecord = {
		folder = folder,
		joints = {},
		attachments = {},
		collide = {},
		requiresNeck = humanoid.RequiresNeck,
		facing = Vector3.new(look.X, 0, look.Z),
	}

	-- Sans cela, désactiver le cou tue le personnage.
	humanoid.RequiresNeck = false
	humanoid.PlatformStand = true

	for _, descendant in character:GetDescendants() do
		if isCosmeticOrTool(descendant) then
			continue
		end
		if descendant:IsA("Motor6D") then
			local part0, part1 = descendant.Part0, descendant.Part1
			if part0 and part1 and descendant.Enabled then
				local a0 = Instance.new("Attachment")
				a0.Name = "RagdollAttachment0"
				a0.CFrame = descendant.C0
				a0.Parent = part0
				local a1 = Instance.new("Attachment")
				a1.Name = "RagdollAttachment1"
				a1.CFrame = descendant.C1
				a1.Parent = part1
				makeSocket(record, a0, a1, descendant.Name == "Neck")
				descendant.Enabled = false
				table.insert(record.joints, descendant)
				table.insert(record.attachments, a0)
				table.insert(record.attachments, a1)
			end
		elseif descendant:IsA("AnimationConstraint") then
			-- Rigs « AvatarJointUpgrade » : mêmes attachements, articulation désactivée le temps du KO.
			local a0, a1 = descendant.Attachment0, descendant.Attachment1
			if a0 and a1 and descendant.Enabled then
				makeSocket(record, a0, a1, descendant.Name == "Neck")
				descendant.Enabled = false
				table.insert(record.joints, descendant)
			end
		end
	end
	folder.Parent = character

	-- Les membres doivent toucher le sol pendant le ragdoll.
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") and child ~= root then
			record.collide[child] = child.CanCollide
			child.CanCollide = true
		end
	end

	-- Propriété serveur AVANT d'imposer l'état et la vitesse (un client écraserait la vitesse).
	setOwnership(character, nil, false)
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	if knock.Magnitude > 0 then
		for _, child in character:GetChildren() do
			if child:IsA("BasePart") then
				child.AssemblyLinearVelocity = knock
			end
		end
	end
	return record
end

local function destroyRagdollInstances(record: RagdollRecord)
	record.folder:Destroy()
	for _, attachment in record.attachments do
		attachment:Destroy()
	end
	table.clear(record.attachments)
end

local function stopRagdoll(player: Player, character: Model, humanoid: Humanoid, record: RagdollRecord)
	for _, joint in record.joints do
		if joint.Parent then
			if joint:IsA("Motor6D") then
				joint.Enabled = true
			elseif joint:IsA("Constraint") then
				joint.Enabled = true
			end
		end
	end
	destroyRagdollInstances(record)
	for part, canCollide in record.collide do
		if part.Parent then
			part.CanCollide = canCollide
		end
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local look = root.CFrame.LookVector
		local facing = Vector3.new(look.X, 0, look.Z)
		if facing.Magnitude < 0.2 then
			facing = record.facing
		end
		if facing.Magnitude < 0.1 then
			facing = Vector3.new(0, 0, -1)
		end
		-- Redressé légèrement au-dessus du sol pour ne pas rester coincé dedans.
		local position = root.Position + Vector3.new(0, KO.StandUpLift, 0)
		root.CFrame = CFrame.lookAt(position, position + facing.Unit)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end

	humanoid.RequiresNeck = record.requiresNeck
	humanoid.PlatformStand = false
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	if player.Parent == Players and player.Character == character then
		setOwnership(character, player, false)
	else
		setOwnership(character, nil, true)
	end
end

--------------------------------------------------------------------------------
-- KO
--------------------------------------------------------------------------------

local function ejectFromSeat(player: Player, humanoid: Humanoid)
	if not humanoid.SeatPart then
		return
	end
	local VehicleService = optionalService("VehicleService")
	if VehicleService and type(VehicleService.EjectPlayer) == "function" then
		local ok = pcall(VehicleService.EjectPlayer, player)
		if ok and not humanoid.SeatPart then
			return
		end
	end
	humanoid.Sit = false
	local seat = humanoid.SeatPart
	if seat then
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
end

local function endKnockout(player: Player, state: CombatState, restore: boolean)
	local ko = state.ko
	if not ko then
		return
	end
	state.ko = nil
	cancelThread(ko.thread)

	local record = ko.ragdoll
	if record then
		local alive = ko.character.Parent ~= nil and ko.humanoid.Parent ~= nil and ko.humanoid.Health > 0
		if restore and alive and player.Character == ko.character then
			local ok, err = pcall(stopRagdoll, player, ko.character, ko.humanoid, record)
			if not ok then
				Log.warn("Combat", "relève impossible :", player.Name, err)
				destroyRagdollInstances(record)
			end
		else
			destroyRagdollInstances(record)
		end
	end

	if player.Parent then
		player:SetAttribute("KnockedOut", false)
	end
	if ko.character.Parent and ko.character:GetAttribute("AnimState") == "KO" then
		ko.character:SetAttribute("AnimState", "")
	end
	MovementService.Unlock(player, "KO")
	state.immuneUntil = now() + KO.RecoverImmunity
	MovementService.AllowDisplacement(player, KO.PostRecoverExemption, "ko_recover")
	CombatService.Recovered:Fire(player)
end

local function recover(player: Player, ko: KOState)
	local state = states[player]
	if state and state.ko == ko then
		endKnockout(player, state, true)
	end
end

local function pruneHistory(state: CombatState, time: number)
	local kept = {}
	for _, at in state.koHistory do
		if time - at <= KO.DiminishingWindow then
			table.insert(kept, at)
		end
	end
	state.koHistory = kept
end

local function sanitizeKnock(knock: any): Vector3
	if typeof(knock) ~= "Vector3" or not BallMath.isFiniteVector(knock) then
		return Vector3.zero
	end
	return clampMagnitude(knock, KO.MaxKnockSpeed)
end

-- Met le joueur KO. Retourne (true) ou (false, raison) : "invalid" | "dead" | "knocked" | "phase" | "finished"
-- | "ally" | "protected" | "immune" | "repeat" | "blocked".
function CombatService.Knockout(victim: Player, opts: KnockoutOptions?): (boolean, string?)
	if not isPlayer(victim) or victim.Parent ~= Players then
		return false, "invalid"
	end
	local state = getState(victim)
	if not state then
		return false, "invalid"
	end
	if state.ko then
		return false, "knocked" -- pas de cumul : un joueur KO ne peut pas être enchaîné
	end
	local character, humanoid, root = NetworkValidation.GetAliveCharacter(victim)
	if not character or not humanoid or not root then
		return false, "dead"
	end

	local options: KnockoutOptions = opts or { source = "unknown" }
	local attacker: Player? = if isPlayer(options.attacker) then options.attacker else nil
	local source = if type(options.source) == "string" and options.source ~= "" then options.source else "unknown"
	local major = options.major == true

	local refusal = CombatService.AffectRefusal(attacker, victim)
	if refusal then
		return false, refusal
	end
	local time = now()
	if time < state.immuneUntil then
		return false, "immune"
	end
	if attacker and attacker ~= victim then
		local last = state.lastKOBy[attacker.UserId]
		if last ~= nil and time - last < KO.SameAttackerCooldown then
			return false, "repeat"
		end
	end

	local duration = Validate.clampNumber(options.duration, KO.MinDuration, KO.MaxDuration, KO.DefaultDuration)
	local knock = sanitizeKnock(options.knock)

	local shield = consultShield(victim, {
		attacker = attacker,
		source = source,
		major = major,
		duration = duration,
		knock = knock,
	})
	if shield == "blocked" then
		return false, "blocked"
	elseif shield == "broken" then
		knock *= KO.ShieldBrokenKnockScale -- bouclier brisé : KO sans fort recul (pas de chute dans le vide)
	end

	-- Durée dégressive si la victime enchaîne les KO.
	pruneHistory(state, time)
	local rank = #state.koHistory + 1
	local multipliers = KO.DiminishingMultipliers
	local multiplier = multipliers[math.min(rank, #multipliers)] or 1
	duration = math.max(KO.MinDuration, duration * multiplier)
	table.insert(state.koHistory, time)
	if attacker and attacker ~= victim then
		state.lastKOBy[attacker.UserId] = time
		if KO.AttackEndsProtection then
			CombatService.EndProtection(attacker)
		end
	end

	ejectFromSeat(victim, humanoid)

	local ko: KOState = {
		character = character,
		humanoid = humanoid,
		endsAt = time + duration,
		attacker = attacker,
		source = source,
		ragdoll = nil,
		thread = nil,
	}
	state.ko = ko
	victim:SetAttribute("KnockedOut", true)
	character:SetAttribute("AnimState", "KO")
	character:SetAttribute("Dodging", false)
	state.dodgeUntil = 0
	MovementService.Lock(victim, "KO")
	MovementService.AllowDisplacement(victim, duration + KO.PostRecoverExemption, "ko")

	local ok, result = pcall(startRagdoll, character, humanoid, root, knock)
	if ok then
		ko.ragdoll = result
	else
		Log.warn("Combat", "ragdoll impossible :", victim.Name, result)
	end
	ko.thread = task.delay(duration, recover, victim, ko)

	CombatService.KnockedOut:Fire(victim, attacker, source)
	Net.fireAll("Combat.KO", victim.UserId, if attacker then attacker.UserId else 0, source)
	Log.debug("Combat", victim.Name, "KO", source, string.format("%.2f s", duration))
	return true
end

--------------------------------------------------------------------------------
-- Poussées sans KO (recul, plongeon)
--------------------------------------------------------------------------------

local function clearPush(state: CombatState)
	local push = state.push
	if not push then
		return
	end
	state.push = nil
	cancelThread(push.thread)
	push.mover:Destroy()
	push.attachment:Destroy()
end

-- LinearVelocity répliquée : le client propriétaire du personnage la simule (pas de changement de propriété).
local function applyPush(state: CombatState, root: BasePart, velocity: Vector3, duration: number)
	clearPush(state)
	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatPushAttachment"
	local mover = Instance.new("LinearVelocity")
	mover.Name = "CombatPush"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.MaxForce = KNOCKBACK.MaxForce
	mover.VectorVelocity = velocity
	attachment.Parent = root
	mover.Parent = root

	local push: PushState = { attachment = attachment, mover = mover, thread = nil }
	state.push = push
	push.thread = task.delay(math.clamp(duration, 0.05, 2), function()
		if state.push == push then
			push.thread = nil
			clearPush(state)
		end
	end)
end

function CombatService.Knockback(player: Player, velocity: Vector3, opts: KnockbackOptions?): boolean
	if not isPlayer(player) or player.Parent ~= Players then
		return false
	end
	if typeof(velocity) ~= "Vector3" or not BallMath.isFiniteVector(velocity) then
		return false
	end
	local options: KnockbackOptions = opts or {}
	local attacker: Player? = if isPlayer(options.attacker) then options.attacker else nil
	if attacker ~= player and not CombatService.CanAffect(attacker, player) then
		return false
	end
	local state = getState(player)
	local _, _, root = NetworkValidation.GetAliveCharacter(player)
	if not state or not root then
		return false
	end
	local clamped = clampMagnitude(velocity, KO.MaxKnockSpeed)
	local source = if type(options.source) == "string" then options.source else "knockback"
	local exemption = Validate.clampNumber(options.exemption, 0, 10, KNOCKBACK.ExemptionTime)
	MovementService.AllowDisplacement(player, exemption, source)
	if attacker and attacker ~= player and KO.AttackEndsProtection then
		CombatService.EndProtection(attacker)
	end

	local ko = state.ko
	if ko then
		-- Ragdoll possédé par le serveur : application directe.
		for _, child in ko.character:GetChildren() do
			if child:IsA("BasePart") then
				child.AssemblyLinearVelocity = clamped
			end
		end
		return true
	end
	applyPush(state, root, clamped, Validate.clampNumber(options.duration, 0.05, 2, KNOCKBACK.PushTime))
	return true
end

--------------------------------------------------------------------------------
-- Impacts de balle (appelé par BallService)
--------------------------------------------------------------------------------

-- KO si la balle va assez vite, n'est pas celle de la victime, ne vient pas d'un allié et si la victime
-- n'est pas en plongeon. Retourne true si le KO a eu lieu.
function CombatService.BallHit(owner: Player?, victim: Player, velocity: Vector3): boolean
	if not isPlayer(victim) or owner == victim then
		return false
	end
	if typeof(velocity) ~= "Vector3" or not BallMath.isFiniteVector(velocity) then
		return false
	end
	if velocity.Magnitude < BALL_HIT.MinSpeed then
		return false
	end
	if BALL_HIT.DodgeAvoids and CombatService.IsDodging(victim) then
		return false
	end
	local knock = Vector3.new(0, BALL_HIT.KnockUp, 0)
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	if horizontal.Magnitude > 0.1 then
		knock += horizontal.Unit * BALL_HIT.Knockback
	end
	local ok = CombatService.Knockout(victim, {
		attacker = owner,
		source = "ball",
		duration = BALL_HIT.Duration,
		knock = knock,
		major = false,
	})
	return ok
end

--------------------------------------------------------------------------------
-- Intentions client : frappe de proximité et plongeon
--------------------------------------------------------------------------------

local function roundAccepted(player: Player, roundId: number): boolean
	if roundId == 0 and LOBBY_PHASES[currentPhase()] then
		return true
	end
	return NetworkValidation.CheckRound(player, roundId, false)
end

-- Raison empêchant le joueur d'agir, ou nil.
local function actionRefusal(player: Player, state: CombatState, allowOutOfPlay: boolean): string?
	if state.ko then
		return "knocked"
	end
	local character, humanoid = NetworkValidation.GetAliveCharacter(player)
	if not character or not humanoid then
		return "busy"
	end
	if not allowOutOfPlay and isOutOfPlay(player) then
		return "finished"
	end
	if humanoid.SeatPart ~= nil or player:GetAttribute("InVehicle") == true then
		return "busy"
	end
	if player:GetAttribute("Aiming") == true then
		return "busy"
	end
	if character:GetAttribute("Frozen") == true then
		return "busy"
	end
	return nil
end

local function characterList(): { Instance }
	local list = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(list, other.Character)
		end
	end
	return list
end

local function hasLineOfSight(from: Vector3, to: Vector3): boolean
	local params = lineOfSightParams
	if not params then
		return true
	end
	params.FilterDescendantsInstances = characterList()
	return Workspace:Raycast(from, to - from, params) == nil
end

-- Cible de la frappe de proximité depuis les positions SERVEUR : la plus centrée et la plus proche parmi
-- les adversaires affectables du cône. Sans cible affectable, retourne la raison du meilleur refus.
local function findPunchTarget(attacker: Player, root: BasePart, aim: Vector3): (Player?, string?)
	local bestTarget: Player? = nil
	local bestScore = math.huge
	local refusedReason: string? = nil
	local refusedScore = math.huge
	for _, other in Players:GetPlayers() do
		if other == attacker then
			continue
		end
		local _, _, otherRoot = NetworkValidation.GetAliveCharacter(other)
		if not otherRoot then
			continue
		end
		local offset = otherRoot.Position - root.Position
		if math.abs(offset.Y) > PUNCH.MaxHeightDelta then
			continue
		end
		local inCone, angle, distance = BallMath.coneCheck(root.Position, aim, otherRoot.Position, PUNCH.ConeDeg, PUNCH.Range, true)
		if not inCone or not hasLineOfSight(root.Position, otherRoot.Position) then
			continue
		end
		local score = angle * 2 + distance / PUNCH.Range
		local reason = CombatService.AffectRefusal(attacker, other)
		if reason == nil then
			if score < bestScore then
				bestScore = score
				bestTarget = other
			end
		elseif score < refusedScore then
			refusedScore = score
			refusedReason = reason
		end
	end
	if bestTarget then
		return bestTarget, nil
	end
	return nil, refusedReason or "miss"
end

local function onPunch(player: Player, roundId: number, direction: Vector3)
	if not roundAccepted(player, roundId) then
		return
	end
	local state = getState(player)
	if not state then
		return
	end
	local time = now()
	if time < state.punchReadyAt then
		feedback(player, "punch", false, "cooldown")
		return
	end
	local refusal = actionRefusal(player, state, false)
	if refusal then
		feedback(player, "punch", false, refusal)
		return
	end
	if not phaseAllowsCombat() then
		feedback(player, "punch", false, "busy")
		return
	end
	local _, _, root = NetworkValidation.GetAliveCharacter(player)
	if not root then
		return
	end
	state.punchReadyAt = time + PUNCH.Cooldown

	-- Direction : celle demandée si elle reste plausible par rapport à l'orientation serveur de l'avatar.
	local facing = flatUnit(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	local aim = flatUnit(direction)
	if not aim then
		NetworkValidation.Report(player, "punch_direction")
		aim = facing
	elseif BallMath.angleBetween(aim, facing) > math.rad(PUNCH.FacingToleranceDeg) then
		aim = facing
	end
	local finalAim: Vector3 = aim or facing

	setTimedAnimState(player, state, "Punch", PUNCH.AnimTime)
	if KO.AttackEndsProtection then
		CombatService.EndProtection(player)
	end

	local target, reason = findPunchTarget(player, root, finalAim)
	if not target then
		feedback(player, "punch", false, reason)
		return
	end
	local knock = finalAim * PUNCH.Knockback + Vector3.new(0, PUNCH.KnockUp, 0)
	local ok, why = CombatService.Knockout(target, {
		attacker = player,
		source = "punch",
		duration = PUNCH.Duration,
		knock = knock,
		major = false,
	})
	if ok then
		feedback(player, "punch", true, "ok")
	else
		feedback(player, "punch", false, if why == "blocked" then "shield" else why)
	end
end

local function setDodging(player: Player, state: CombatState, character: Model, window: number)
	state.dodgeUntil = now() + window
	state.dodgeToken += 1
	local token = state.dodgeToken
	character:SetAttribute("Dodging", true)
	task.delay(window, function()
		if state.dodgeToken == token then
			state.dodgeUntil = 0
			if character.Parent then
				character:SetAttribute("Dodging", false)
			end
		end
	end)
end

local function onDive(player: Player, roundId: number, direction: Vector3)
	if not roundAccepted(player, roundId) then
		return
	end
	local state = getState(player)
	if not state then
		return
	end
	local time = now()
	if time < state.diveReadyAt then
		feedback(player, "dive", false, "cooldown")
		return
	end
	-- Plonger ne gêne personne : permis aussi aux joueurs ayant terminé (ils restent intangibles).
	local refusal = actionRefusal(player, state, true)
	if refusal then
		feedback(player, "dive", false, refusal)
		return
	end
	if MovementService.IsLocked(player) then
		feedback(player, "dive", false, "busy")
		return
	end
	local character, _, root = NetworkValidation.GetAliveCharacter(player)
	if not character or not root then
		return
	end
	state.diveReadyAt = time + DIVE.Cooldown

	local dir = flatUnit(direction) or flatUnit(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	if flatUnit(direction) == nil then
		NetworkValidation.Report(player, "dive_direction")
	end
	local velocity = dir * DIVE.Speed + Vector3.new(0, DIVE.Lift, 0)
	MovementService.AllowDisplacement(player, DIVE.ExemptionTime, "dive")
	applyPush(state, root, velocity, DIVE.PushTime)
	setDodging(player, state, character, DIVE.DodgeWindow)
	setTimedAnimState(player, state, "Dive", DIVE.AnimTime)
	feedback(player, "dive", true, "ok")
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local state = getState(player)
	if not state then
		return
	end
	clearPush(state)
	state.dodgeUntil = 0
	state.dodgeToken += 1
	character:SetAttribute("AnimState", "")
	character:SetAttribute("Dodging", false)
	if KO.ProtectOnSpawn then
		CombatService.GrantProtection(player, KO.SpawnProtection)
	end
end

local function onCharacterRemoving(player: Player)
	local state = states[player]
	if not state then
		return
	end
	clearPush(state)
	state.dodgeUntil = 0
	state.dodgeToken += 1
	if state.ko then
		endKnockout(player, state, false)
	end
end

local function setupPlayer(player: Player)
	local state = getState(player)
	if not state then
		return
	end
	player:SetAttribute("KnockedOut", false)
	if player:GetAttribute("Protected") == nil then
		player:SetAttribute("Protected", false)
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
	clearPush(state)
	if state.ko then
		cancelThread(state.ko.thread)
		local record = state.ko.ragdoll
		if record then
			destroyRagdollInstances(record)
		end
		state.ko = nil
	end
	cancelThread(state.protectionThread)
	state.protectionToken += 1
	state.dodgeToken += 1
	state.animToken += 1
	state.trove:Destroy()
	states[player] = nil
	-- Les autres joueurs oublient l'historique lié à ce joueur (anti-KO répété).
	for _, other in states do
		other.lastKOBy[player.UserId] = nil
	end
end

function CombatService.Init()
	if initialized then
		return
	end
	initialized = true

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.RespectCanCollide = true
	lineOfSightParams = params

	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(cleanupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end

	Net.on("Combat.Punch", onPunch)
	Net.on("Combat.Dive", onDive)
end

function CombatService.Start() end

return CombatService
