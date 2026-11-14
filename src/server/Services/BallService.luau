--!strict
--[[
	BallService — balles de golf : création, visée, frappes, physique, trou, dangers et pénalités
	(docs/ARCHITECTURE.md §8 et §11, priorité 20). Stratégie détaillée : docs/PHYSIQUE_RESEAU.md.

	INTENTIONS CLIENT (toutes précédées du RoundId courant, attribut GameState.RoundId) :
	  Golf.AimState(roundId, isAiming)   Golf.SwingStart(roundId)   Golf.ResetBall(roundId)
	  Golf.Shoot(roundId, direction, loft, puissanceIndicative?, type?)   type "Drive" | "Chip" | "Putt" | "Guided"
	  Une balle d'entraînement (attribut de balle Practice = true) accepte aussi roundId = 0.
	  Le serveur revalide tout : manche, phase, état de la balle, KO, véhicule, gel / éblouissement / géant,
	  trou terminé, distance joueur–balle, délais, type de frappe, règle du putt (green ou près du trou), cible
	  du tir guidé ; il RECALCULE la puissance depuis l'heure serveur de Golf.SwingStart (valeur client bornée à
	  ± Shot.PowerTolerance ; un écart > Shot.PowerReportDeviation est signalé à NetworkValidation).
	  Quitter la visée (Golf.AimState false) est toujours accepté : cela ne fait que retirer une capacité.

	RETOURS AUX CLIENTS
	  Golf.AimCancelled(raison) au tireur (raisons : AIM_CANCEL_REASONS, textes "golf.aimCancelled.<raison>") ;
	  Golf.ShotAccepted({ strokes, power, shotType, forced, reason, boost, targetUserId }) au tireur ;
	  Golf.Holed(userId, { strokes, fromDistance, holeInOne, effectId, shotType, wasPutt, gimme, practice }) à tous ;
	  Golf.BallReset(raison, pénalité) au propriétaire (textes "golf.reset.<raison>", repli "golf.reset.generic") ;
	  Core.NotifyKey(clé, variables) pour les messages courts (clés de Locale/fr|en/Golf.luau) ;
	  Effects.Sound / Effects.Play / Effects.Burst pour les retours sonores et visuels (purement cosmétiques).

	BALLE DE PARTIE / BALLE D'ENTRAÎNEMENT
	  Partie : frappes en phase "Playing" seulement, et si le prédicat SetCanShoot(fn) l'autorise ; vent ; KO.
	  Entraînement (créée pendant Ball.PracticePhases, ou SpawnBall(..., { practice = true })) : frappes en toute
	  phase, sans vent ni KO (Ball.PracticeWind, Ball.PracticeBallsCanHitPlayers), prédicat SetCanShoot ignoré.
	  Capture du trou : phase "Playing" uniquement (Cup.RequirePlayingPhase). Hors de cette phase, aucune pénalité
	  automatique n'est ajoutée à une balle de partie (les résultats sont figés à HoleEnd).

	PHYSIQUE (serveur, à chaque Heartbeat, balles "Moving" uniquement)
	  Part non ancrée, propriété réseau SERVEUR (SetNetworkOwner(nil) à chaque départ), pas fixe 240 Hz réglé
	  dans default.project.json, gravité réduite (VectorForce de compensation). Dans l'ordre :
	   1. balayage Spherecast position précédente -> actuelle, confirmé par un rayon central : une balle dont le
	      centre a franchi une surface est replacée devant elle et réfléchie (anti-traversée) ;
	   2. trou : test balayé segment–cercle (BallMath.cupCapture) -> capture sous la vitesse de capture,
	      ressortie déviée (« lip-out ») au-dessus ;
	   3. sol (Spherecast vers le bas) et surface : attribut "Surface" de la Part ou de son modèle, sinon
	      matériau (Config.MaterialSurface) -> frottement, rebond, traînée et résistance au roulement ;
	   4. dangers : altitude de vide (CourseService.GetCurrent().killY, sinon Ball.KillHeight), volumes balisés
	      "GolfHazard" (attribut Hazard), eau du Terrain, hors-limites CourseService.IsOutOfBounds ;
	   5. tir guidé, vent et traînée de l'air en vol, roulement au sol, vitesse plafonnée ;
	   6. impacts sur les joueurs (CombatService.BallHit décide du KO) ;
	   7. « gimme » (balle presque arrêtée au bord du trou), arrêt (vitesse + pente), blocage, durée maximale.
	  Position valide : dernier arrêt NATUREL de la balle (les dangers y ramènent). Golf.ResetBall sur une balle
	  arrêtée la ramène à l'endroit du coup précédent (« coup et distance », pénalité Hazards.Penalties.stuck) ;
	  sur une balle en mouvement, à la dernière position valide.
	  Les skins ne changent RIEN : même Part, même taille et même densité pour tous ; l'attribut Skin est visuel.

	API
	  SpawnBall(player, position, opts?) -> BasePart?     opts = { practice: boolean?, snap: boolean? }
	  PlaceBall(player, position, snap?) -> BasePart?      RemoveBall(player)      RemoveAll()
	  GetBall(player) / GetState(player) / GetAllBalls() / GetLastValid(player)
	  IsPractice(player) / IsAiming(player) / IsCharging(player)
	  GetStrokes(player) / ResetStrokes(player) / AddPenalty(player, count, reason?)
	  SetCup(position?, radius?) / GetCup()   SetWind(v) / GetWind()   SetCanShoot(fn?)   SetBallCollisions(enabled)
	  CancelAim(player, reason, blockSeconds?)              ForceShot(player, reason) -> boolean  (Corne Tonitruante)
	  ApplyBallImpulse(player, velocity, source) -> boolean FreezeBall(player, seconds) -> boolean
	  ResetToLastValid(player, reason, penalty) -> boolean  SetShotBoost(player, mult, seconds) / ClearShotBoost(player)
	  RefreshSkin(player)                                   (à appeler par CosmeticService après un équipement)
	  CreateSimBall(position, opts?) -> BasePart?   StepSim(ball, shot?, timeout?) -> SimResult   RemoveSimBall(ball)
	  Signaux : Shot(player, strokes, power, ShotInfo), Rested(player, position), Holed(player, HoledInfo),
	            Respawned(player, reason), PlayerHit(attacker, victim)

	ATTRIBUTS POSÉS
	  Balle : OwnerUserId, State ("Resting" | "Moving" | "Holed" | "Frozen"), Skin, Surface (position de jeu),
	          Practice, GuidedTargetUserId (0 = aucun), ShotBoost (1 = aucune frappe amplifiée en attente).
	  Joueur : Strokes, Aiming.
	  Personnage : AnimState ("Address" en visée, "Charging" après Golf.SwingStart, "Swing" ~0,6 s après la frappe ;
	          jamais par-dessus "KO"), ShotType (type de la dernière frappe : variante de l'animation de swing).

	CONTRAT CLIENT (GolfAimController) : pendant la visée, orienter le personnage selon la convention d'adresse
	(lookVector = visée × Y, BallMath.addressLook) : la frappe forcée de la Corne en déduit la direction.
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.Gameplay)
local Sounds = require(Shared.Config.Sounds)
local BallMath = require(Shared.Logic.BallMath)
local Locale = require(Shared.Locale)
local GameState = require(Shared.Util.GameState)
local Log = require(Shared.Util.Log)
local Net = require(Shared.Net)
local SignalModule = require(Shared.Util.Signal)
local TroveModule = require(Shared.Util.Trove)
local Validate = require(Shared.Util.Validate)

local CollisionService = require(script.Parent.CollisionService)
local CombatService = require(script.Parent.CombatService)
local MovementService = require(script.Parent.MovementService)
local NetworkValidation = require(script.Parent.NetworkValidation)
local Hazards = require(script.Parent.Parent.Ball.Hazards)

type Signal = SignalModule.Signal
type Connection = SignalModule.Connection
type Trove = TroveModule.Trove
type ShotTypeDef = Config.ShotTypeDef
type SurfaceDef = Config.SurfaceDef

local Types = require(script.Parent.Parent.Ball.Types)
export type BallState = Types.BallState
export type SpawnOptions = Types.SpawnOptions
export type ShotInfo = Types.ShotInfo
export type HoledInfo = Types.HoledInfo
export type SimShot = Types.SimShot
export type SimOutcome = Types.SimOutcome
export type SimResult = Types.SimResult
type ShotOptions = Types.ShotOptions
type GuidedState = Types.GuidedState
type BallData = Types.BallData

--------------------------------------------------------------------------------
-- Réglages
--------------------------------------------------------------------------------

local BALL = Config.Ball
local ANTI = Config.AntiTunneling
local STUCK = Config.Stuck
local CUP = Config.Cup
local HAZARDS = Config.Hazards
local WIND = Config.Wind
local SHOT = Config.Shot
local SHOT_TYPES = Config.ShotTypes
local GUIDED = Config.Guided
local BALL_HIT = Config.BallHit
local FEEDBACK = Config.Feedback
local COLLISION = Config.Collision
local SURFACES = Config.Surfaces
local DEFAULT_SURFACE: string = Config.DefaultSurface

-- Valeurs absentes de Config/Gameplay : REPLIS LOCAUX (à déplacer dans Config/Gameplay, voir le rapport d'intégration).
local SNAP_RAY_UP = 2.5 -- [repli] départ du rayon de pose au-dessus de la position demandée (studs)
local SNAP_RAY_DEPTH = 60 -- [repli] profondeur sondée sous la position demandée (studs)
local SNAP_CLEARANCE = 0.02 -- [repli] jeu laissé entre la balle posée et le sol (studs)
local LANDING_FX_MIN_SPEED = 14 -- [repli] vitesse verticale d'impact minimale pour l'effet d'atterrissage (studs/s)
local LANDING_FX_COOLDOWN = 0.35 -- [repli] délai entre deux effets d'atterrissage d'une même balle (s)
local MAX_AIM_BLOCK_SECONDS = 30 -- [repli] borne de CancelAim(..., blockSeconds)
local MAX_FREEZE_SECONDS = 30 -- [repli] borne de FreezeBall
local AIM_CHARGE_GRACE = 1 -- [repli] jauge tenue plus de Shot.MaxSwingTime + 1 s : visée annulée
local RUNTIME_CACHE_TIME = 0.5 -- [repli] période de relecture de CourseService.GetCurrent() (s)
local MAX_SIM_BALLS = 16 -- [repli] balles de simulation simultanées
local SIM_DEFAULT_TIMEOUT = 20 -- [repli] StepSim : attente par défaut (s)
local SIM_MAX_TIMEOUT = 120 -- [repli] StepSim : attente maximale (s)

local AIM_LOCK = "Aim" -- verrou MovementService (retiré automatiquement à la réapparition)
local HAZARD_KINDS = Hazards.KINDS
local MATCH_PHASES: { [string]: boolean } = {
	Loading = true,
	HoleIntro = true,
	Countdown = true,
	Playing = true,
	HoleEnd = true,
	HoleResults = true,
}
local AIM_ANIM_STATES: { [string]: boolean } = { Address = true, Charging = true }

-- Raisons envoyées par Golf.AimCancelled (texte client : "golf.aimCancelled.<raison>").
local AIM_CANCEL_REASONS: { string } = {
	"stun", -- joueur KO
	"horn", -- visée interrompue par la Corne (posée par ItemService via CancelAim)
	"too_far", -- trop loin de la balle
	"invalid", -- requête incohérente (jauge absente, direction ou type invalides, délai de jauge)
	"unavailable", -- personnage absent, spectateur, frappe interdite par MatchService
	"respawn", -- réapparition, balle replacée
	"phase", -- phase de partie sans frappe, ou requête d'une ancienne manche
	"no_target", -- tir guidé sans cible valide
	"ball_moving", -- la balle roule encore (ou vient d'être poussée)
	"ball_frozen", -- balle gelée
	"finished", -- trou terminé / balle dans le trou
	"vehicle", -- joueur en voiturette
	"status", -- gelé, ébloui ou géant
	"blocked", -- visée bloquée temporairement (CancelAim avec blockSeconds)
	"cooldown", -- frappes trop rapprochées
	"putt_not_allowed", -- putt hors du green et loin du trou
	"guided_cooldown", -- tir guidé en recharge
}
-- Raisons envoyées par Golf.BallReset (texte client : "golf.reset.<raison>", repli "golf.reset.generic").
local RESET_REASONS: { string } = { "water", "oob", "lava", "void", "stuck" }
-- Clés envoyées par Core.NotifyKey.
local NOTIFY_KEYS: { string } = { "golf.lipOut", "golf.ball.frozen", "golf.penalty.added", "golf.reset.refused", "golf.reset.generic" }
-- Sons joués (Config/Sounds).
local SOUND_NAMES: { string } = { "ball_hit_drive", "ball_hit_putt", "ball_cup_drop", "sand_thud" }

--------------------------------------------------------------------------------
-- Module et état
--------------------------------------------------------------------------------

local BallService = {}
BallService.Priority = 20

BallService.Shot = SignalModule.new() :: Signal -- (player, strokes, power, ShotInfo)
BallService.Rested = SignalModule.new() :: Signal -- (player, position)
BallService.Holed = SignalModule.new() :: Signal -- (player, HoledInfo)
BallService.Respawned = SignalModule.new() :: Signal -- (player, reason)
BallService.PlayerHit = SignalModule.new() :: Signal -- (attacker, victim)

local balls: { [Player]: BallData } = {}
local sims: { [BasePart]: BallData } = {}
local strokes: { [Player]: number } = {}
local guidedReadyAt: { [Player]: number } = {}
local swingTokens: { [Player]: number } = {}
local playerTroves: { [Player]: Trove } = {}
local characterList: { Instance } = {}

local serviceTrove: Trove? = nil
local ballsFolder: Folder? = nil
local simFolder: Folder? = nil
local solidParams: RaycastParams? = nil -- ce que « voit » une balle : sol, murs, obstacles (groupe Balls)
local hitOverlap: OverlapParams? = nil
local random: Random? = nil

local cupPosition: Vector3? = nil
local cupRadius: number = CUP.Radius
local wind: Vector3 = Vector3.zero
local canShootPredicate: ((Player) -> boolean)? = nil
local predicateErrorLogged = false
local settingsCache: { [string]: any }? = nil
local settingsCacheValid = false
local runtimeCache: any = nil
local runtimeCheckedAt = -math.huge
local simCounter = 0
local supportTimer = 0
local aimWatchTimer = 0
local initialized = false
local started = false

--------------------------------------------------------------------------------
-- Utilitaires
--------------------------------------------------------------------------------

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function ballRadius(): number
	return BALL.Diameter / 2
end

local function currentPhase(): string
	local phase = GameState.read("Phase")
	return if type(phase) == "string" then phase else "Lobby"
end

local function isPracticePhase(phase: string): boolean
	return table.find(BALL.PracticePhases, phase) ~= nil
end

local function getRandom(): Random
	local generator = random
	if not generator then
		generator = Random.new()
		random = generator
	end
	return generator
end

-- Service facultatif chargé à la demande (aucun cycle de require au démarrage) ; nil s'il n'existe pas.
local optionalService = require(script.Parent.Parent.Util.Services).get

-- MatchSettings décodés depuis GameState.SettingsJson (cache invalidé à chaque changement).
local function readSettings(): { [string]: any }?
	if settingsCacheValid then
		return settingsCache
	end
	settingsCacheValid = true
	settingsCache = nil
	local json = GameState.read("SettingsJson")
	if type(json) == "string" and json ~= "" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
		if ok and type(decoded) == "table" then
			settingsCache = decoded
		end
	end
	return settingsCache
end

-- Trou chargé par CourseService (HoleRuntime) ou nil ; relu au plus toutes les RUNTIME_CACHE_TIME s.
local function currentRuntime(): any
	local clock = os.clock()
	if clock - runtimeCheckedAt < RUNTIME_CACHE_TIME then
		return runtimeCache
	end
	runtimeCheckedAt = clock
	runtimeCache = nil
	local CourseService = optionalService("CourseService")
	if CourseService and type(CourseService.GetCurrent) == "function" then
		local ok, runtime = pcall(CourseService.GetCurrent)
		if ok and type(runtime) == "table" then
			runtimeCache = runtime
		end
	end
	return runtimeCache
end

local function killHeight(): number
	local runtime = currentRuntime()
	if runtime and Validate.isFiniteNumber(runtime.killY) then
		return runtime.killY
	end
	return BALL.KillHeight
end

local function publish(name: string, value: any)
	local ok, err = pcall(GameState.set, name, value)
	if not ok then
		Log.debug("Ball", "GameState." .. name .. " non publié :", err)
	end
end

local function clampMagnitude(vector: Vector3, maxMagnitude: number): Vector3
	local magnitude = vector.Magnitude
	if magnitude > maxMagnitude and magnitude > 0 then
		return vector * (maxMagnitude / magnitude)
	end
	return vector
end

-- Position finie depuis un Vector3 ou un CFrame, sinon nil.
local function toPosition(value: any): Vector3?
	if typeof(value) == "CFrame" then
		if not Validate.isFiniteCFrame(value) then
			return nil
		end
		return (value :: CFrame).Position
	end
	if Validate.isFiniteVector3(value) then
		return value :: Vector3
	end
	return nil
end

local function cancelThread(handle: thread?)
	if handle and handle ~= coroutine.running() and coroutine.status(handle) ~= "dead" then
		pcall(task.cancel, handle)
	end
end

-- Délai rattaché à une Trove : annulé si la Trove est nettoyée, retiré de la Trove une fois exécuté.
local function schedule(trove: Trove, seconds: number, callback: () -> ()): thread
	local handle: thread? = nil
	handle = task.delay(math.max(0, seconds), function()
		if handle then
			trove:Remove(handle)
		end
		callback()
	end)
	local created = handle :: thread
	trove:Add(created)
	return created
end

local function unschedule(trove: Trove, handle: thread?)
	if handle then
		trove:Remove(handle)
		cancelThread(handle)
	end
end

--------------------------------------------------------------------------------
-- Retours cosmétiques (effets, sons, messages)
--------------------------------------------------------------------------------

local function fireEffect(name: string?, params: { [string]: any }, unreliable: boolean?)
	if not FEEDBACK.Enabled or name == nil or name == "" then
		return
	end
	Net.fireAll(if unreliable then "Effects.Burst" else "Effects.Play", name, params)
end

local function fireSound(name: string, position: Vector3?)
	Net.fireAll("Effects.Sound", name, position)
end

local function notifyKey(player: Player?, key: string, vars: { [string]: any }?)
	if player then
		Net.fire("Core.NotifyKey", player, key, vars)
	end
end

--------------------------------------------------------------------------------
-- Surfaces
--------------------------------------------------------------------------------

local function surfaceDef(name: string): SurfaceDef
	return SURFACES[name] or SURFACES[DEFAULT_SURFACE]
end

local function makeProperties(surfaceName: string): PhysicalProperties
	local surface = surfaceDef(surfaceName)
	-- Poids 100 : les propriétés de la balle l'emportent sur celles du sol (comportement identique partout).
	return PhysicalProperties.new(BALL.Density, surface.Friction, surface.Elasticity, 100, 100)
end

-- Surface touchée : attribut "Surface" de la Part (ou de son modèle parent), sinon matériau, sinon défaut.
local function surfaceFromHit(instance: Instance, material: Enum.Material): string
	local attribute = instance:GetAttribute("Surface")
	if type(attribute) ~= "string" then
		local parent = instance.Parent
		if parent and parent:IsA("Model") then
			attribute = parent:GetAttribute("Surface")
		end
	end
	if type(attribute) == "string" and SURFACES[attribute] ~= nil then
		return attribute
	end
	local byMaterial = Config.MaterialSurface[material]
	if byMaterial ~= nil and SURFACES[byMaterial] ~= nil then
		return byMaterial
	end
	return DEFAULT_SURFACE
end

--------------------------------------------------------------------------------
-- Instances
--------------------------------------------------------------------------------

local function refreshSolidFilter()
	local params = solidParams
	if not params then
		return
	end
	local list: { Instance } = {}
	if ballsFolder then
		table.insert(list, ballsFolder)
	end
	if simFolder then
		table.insert(list, simFolder)
	end
	params.FilterDescendantsInstances = list
end

local function ensureFolder(name: string): Folder
	local existing = Workspace:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = Workspace
	return folder
end

-- Workspace.Balls et Workspace.SimBalls (recréés si un script les a supprimés).
local function ensureFolders(): (Folder, Folder)
	local changed = false
	local main = ballsFolder
	if not main or main.Parent ~= Workspace then
		main = ensureFolder(BALL.FolderName)
		ballsFolder = main
		changed = true
	end
	local simulation = simFolder
	if not simulation or simulation.Parent ~= Workspace then
		simulation = ensureFolder(BALL.SimFolderName)
		simFolder = simulation
		changed = true
	end
	if changed then
		refreshSolidFilter()
	end
	return main :: Folder, simulation :: Folder
end

-- Part de référence : taille, densité et collision IDENTIQUES pour tous (le skin est affiché par le client).
local function buildBallInstance(name: string, position: Vector3, ownerUserId: number, practice: boolean): (BasePart, Trail?, VectorForce)
	local diameter = BALL.Diameter
	local ball = Instance.new("Part")
	ball.Name = name
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(diameter, diameter, diameter)
	ball.Color = BALL.Color
	ball.Material = Enum.Material.SmoothPlastic
	ball.TopSurface = Enum.SurfaceType.Smooth
	ball.BottomSurface = Enum.SurfaceType.Smooth
	ball.Anchored = true
	ball.CanCollide = true
	ball.CanQuery = true
	ball.CanTouch = true
	ball.CustomPhysicalProperties = makeProperties(DEFAULT_SURFACE)
	ball.CFrame = CFrame.new(position)
	if not CollisionService.AssignPart(ball, "Balls") then
		ball.CollisionGroup = Config.CollisionGroups.Balls
	end
	ball:SetAttribute("OwnerUserId", ownerUserId)
	ball:SetAttribute("State", "Resting")
	ball:SetAttribute("Skin", "")
	ball:SetAttribute("Surface", DEFAULT_SURFACE)
	ball:SetAttribute("Practice", practice)
	ball:SetAttribute("GuidedTargetUserId", 0)
	ball:SetAttribute("ShotBoost", 1)
	CollectionService:AddTag(ball, BALL.Tag)

	-- Traînée pendant le vol (le client peut la masquer localement).
	local trail: Trail? = nil
	if BALL.ServerTrail then
		local top = Instance.new("Attachment")
		top.Name = "TrailTop"
		top.Position = Vector3.new(0, diameter * 0.4, 0)
		top.Parent = ball
		local bottom = Instance.new("Attachment")
		bottom.Name = "TrailBottom"
		bottom.Position = Vector3.new(0, -diameter * 0.4, 0)
		bottom.Parent = ball
		local newTrail = Instance.new("Trail")
		newTrail.Name = "BallTrail"
		newTrail.Attachment0 = top
		newTrail.Attachment1 = bottom
		newTrail.Lifetime = BALL.TrailLifetime
		newTrail.LightEmission = 0.6
		newTrail.FaceCamera = true
		newTrail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		newTrail.Transparency = NumberSequence.new(0.2, 1)
		newTrail.Enabled = false
		newTrail.Parent = ball
		trail = newTrail
	end

	-- Gravité réduite : la VectorForce compense (1 - GravityScale) de la gravité du monde (réglée au départ).
	local center = Instance.new("Attachment")
	center.Name = "CenterAttachment"
	center.Parent = ball
	local force = Instance.new("VectorForce")
	force.Name = "GravityCompensation"
	force.Attachment0 = center
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Parent = ball
	return ball, trail, force
end

local function newData(
	owner: Player?,
	ball: BasePart,
	trail: Trail?,
	force: VectorForce,
	position: Vector3,
	practice: boolean,
	sim: boolean
): BallData
	local trove = TroveModule.new()
	trove:Add(ball)
	return {
		ball = ball,
		trove = trove,
		owner = owner,
		userId = if owner then owner.UserId else 0,
		sim = sim,
		practice = practice,
		practiceExplicit = false,
		removed = false,
		state = "Resting",
		trail = trail,
		gravityForce = force,
		aiming = false,
		swingStartAt = nil,
		aimBlockedUntil = 0,
		lastShotAt = -math.huge,
		moveStartAt = 0,
		lastPosition = position,
		restTimer = 0,
		gimmeTimer = 0,
		stuckAnchor = position,
		stuckTimer = 0,
		hazardTimer = 0,
		grounded = true,
		groundNormal = Vector3.yAxis,
		surface = DEFAULT_SURFACE,
		maxSpeed = BALL.MaxSpeed,
		hitCooldowns = {},
		lipOutUntil = 0,
		landingFxAt = 0,
		externalImpulse = false,
		windEnabled = false,
		lastValid = position,
		shotOrigin = position,
		shotType = SHOT.DefaultType,
		shotFromDistance = nil,
		frozenUntil = 0,
		frozenResume = nil,
		frozenThread = nil,
		boost = 1,
		boostUntil = 0,
		boostThread = nil,
		sinkTween = nil,
		guided = nil,
		simDone = nil,
		simStart = position,
		simMaxY = position.Y,
		errors = 0,
	}
end

--------------------------------------------------------------------------------
-- Sondes spatiales
--------------------------------------------------------------------------------

-- Sol sous la balle : sphère réduite (Spherecast) lancée vers le bas, `extra` studs sous le bas de la balle.
-- Une sphère (et non un rayon) détecte aussi l'appui sur une arête (balle en équilibre au bord d'un rebord).
local function groundProbe(position: Vector3, extra: number): RaycastResult?
	local params = solidParams
	if not params then
		return nil
	end
	local radius = ballRadius()
	local castRadius = radius * ANTI.CastRadiusScale
	local reach = (radius - castRadius) + extra
	return Workspace:Spherecast(position, castRadius, Vector3.new(0, -reach, 0), params)
end

local function snapToGround(position: Vector3): Vector3
	local params = solidParams
	if not params then
		return position
	end
	local origin = position + Vector3.new(0, SNAP_RAY_UP, 0)
	local result = Workspace:Raycast(origin, Vector3.new(0, -(SNAP_RAY_UP + SNAP_RAY_DEPTH), 0), params)
	if result then
		return result.Position + Vector3.new(0, ballRadius() + SNAP_CLEARANCE, 0)
	end
	return position
end

--------------------------------------------------------------------------------
-- États de la balle
--------------------------------------------------------------------------------

local function setState(data: BallData, state: BallState)
	data.state = state
	data.ball:SetAttribute("State", state)
end

local function applySurface(data: BallData, surface: string)
	if data.surface == surface then
		return
	end
	data.surface = surface
	data.ball.CustomPhysicalProperties = makeProperties(surface)
	data.ball:SetAttribute("Surface", surface)
end

-- Relit la surface sous une balle immobile (position de jeu affichée, règle du putt).
local function refreshLie(data: BallData): string
	local ok, result = pcall(groundProbe, data.ball.Position, BALL.SupportProbeExtra)
	if ok and result then
		data.groundNormal = result.Normal
		applySurface(data, surfaceFromHit(result.Instance, result.Material))
	end
	return data.surface
end

local function stopGuided(data: BallData)
	if data.guided then
		data.guided = nil
		data.ball:SetAttribute("GuidedTargetUserId", 0)
	end
end

local function cancelSink(data: BallData)
	local tween = data.sinkTween
	if tween then
		data.sinkTween = nil
		tween:Cancel()
		data.trove:Remove(tween)
		tween:Destroy()
	end
end

local function clearFreeze(data: BallData)
	unschedule(data.trove, data.frozenThread)
	data.frozenThread = nil
	data.frozenUntil = 0
	data.frozenResume = nil
end

local function clearBoost(data: BallData)
	unschedule(data.trove, data.boostThread)
	data.boostThread = nil
	data.boost = 1
	data.boostUntil = 0
	data.ball:SetAttribute("ShotBoost", 1)
end

-- Multiplicateur de frappe amplifiée à appliquer (consommé), 1 si aucun ou expiré.
local function consumeBoost(data: BallData): number
	local value = data.boost
	local active = value > 1 and now() <= data.boostUntil
	if value ~= 1 then
		clearBoost(data)
	end
	return if active then value else 1
end

-- Immobilise (ancre) la balle, éventuellement à une nouvelle position.
local function immobilize(data: BallData, position: Vector3?)
	local ball = data.ball
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.Anchored = true
	if position then
		ball.CFrame = CFrame.new(position)
	end
	-- Une Part ancrée conserve sa vitesse (effet « tapis roulant ») : remise à zéro après l'ancrage.
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	local trail = data.trail
	if trail then
		trail.Enabled = false
	end
	stopGuided(data)
	data.lastPosition = ball.Position
end

-- Libère la balle (physique serveur) avec une vitesse initiale.
local function release(data: BallData, velocity: Vector3)
	local ball = data.ball
	data.gravityForce.Force = Vector3.new(0, ball:GetMass() * Workspace.Gravity * (1 - BALL.GravityScale), 0)
	ball.Anchored = false
	-- Propriété réseau serveur à CHAQUE désancrage : l'ancrage fait perdre le réglage précédent.
	pcall(function()
		ball:SetNetworkOwner(nil)
	end)
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.AssemblyLinearVelocity = velocity
	local position = ball.Position
	data.moveStartAt = now()
	data.lastPosition = position
	data.stuckAnchor = position
	data.stuckTimer = 0
	data.restTimer = 0
	data.gimmeTimer = 0
	data.hazardTimer = 0
	data.grounded = false
	setState(data, "Moving")
	local trail = data.trail
	if trail then
		trail.Enabled = true
	end
end

--------------------------------------------------------------------------------
-- Coups, visée et animations
--------------------------------------------------------------------------------

local function addStrokes(player: Player, amount: number): number
	local value = (strokes[player] or 0) + amount
	strokes[player] = value
	if player.Parent then
		player:SetAttribute("Strokes", value)
	end
	return value
end

local function setAimAnim(player: Player, value: string)
	local character = player.Character
	if character and character:GetAttribute("AnimState") ~= "KO" then
		character:SetAttribute("AnimState", value)
	end
end

local function clearAimAnim(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local current = character:GetAttribute("AnimState")
	if type(current) == "string" and AIM_ANIM_STATES[current] then
		character:SetAttribute("AnimState", "")
	end
end

-- AnimState = "Swing" pendant Shot.SwingAnimTime (jamais par-dessus un KO) ; ShotType choisit la variante.
local function playSwingAnim(player: Player, shotType: string)
	local character = player.Character
	if not character or character:GetAttribute("AnimState") == "KO" then
		return
	end
	local token = (swingTokens[player] or 0) + 1
	swingTokens[player] = token
	character:SetAttribute("ShotType", shotType)
	character:SetAttribute("AnimState", "Swing")
	local function finish()
		if swingTokens[player] == token and character.Parent and character:GetAttribute("AnimState") == "Swing" then
			character:SetAttribute("AnimState", "")
		end
	end
	local trove = playerTroves[player]
	if trove then
		schedule(trove, SHOT.SwingAnimTime, finish)
	else
		task.delay(SHOT.SwingAnimTime, finish)
	end
end

-- Quitte la visée SANS prévenir le client (l'appelant envoie Golf.AimCancelled si nécessaire).
local function leaveAim(player: Player, data: BallData)
	local wasAiming = data.aiming
	data.aiming = false
	data.swingStartAt = nil
	if wasAiming then
		if player.Parent then
			player:SetAttribute("Aiming", false)
		end
		MovementService.Unlock(player, AIM_LOCK)
		clearAimAnim(player)
	end
end

local function enterAim(player: Player, data: BallData)
	data.aiming = true
	data.swingStartAt = nil
	player:SetAttribute("Aiming", true)
	MovementService.Lock(player, AIM_LOCK)
	setAimAnim(player, "Address")
end

--------------------------------------------------------------------------------
-- Cosmétiques (purement visuels)
--------------------------------------------------------------------------------

-- Identifiant du cosmétique équipé dans un emplacement (CosmeticService.GetEquipped), ou nil.
local function equippedId(player: Player, slot: string): string?
	local CosmeticService = optionalService("CosmeticService")
	if not CosmeticService or type(CosmeticService.GetEquipped) ~= "function" then
		return nil
	end
	local ok, equipped = pcall(CosmeticService.GetEquipped, player)
	if not ok or type(equipped) ~= "table" then
		return nil
	end
	local value = equipped[slot]
	if type(value) == "string" and value ~= "" then
		return value
	end
	if type(value) == "table" and type(value.id) == "string" and value.id ~= "" then
		return value.id
	end
	return nil
end

local function applySkin(player: Player, data: BallData)
	local skin = equippedId(player, "Ball") or ""
	if data.ball:GetAttribute("Skin") ~= skin then
		data.ball:SetAttribute("Skin", skin)
	end
end

--------------------------------------------------------------------------------
-- Trou
--------------------------------------------------------------------------------

-- Trou courant : celui de SetCup, sinon (repli) celui du trou chargé par CourseService.
local function getCup(): (Vector3?, number)
	if cupPosition then
		return cupPosition, cupRadius
	end
	local runtime = currentRuntime()
	if runtime and Validate.isFiniteVector3(runtime.cupPosition) then
		return runtime.cupPosition, Validate.clampNumber(runtime.cupRadius, CUP.MinRadius, CUP.MaxRadius, CUP.Radius)
	end
	return nil, cupRadius
end

local function cupParams(radius: number): BallMath.CupParams
	return {
		radius = radius,
		tolerance = CUP.CaptureTolerance,
		captureSpeed = CUP.CaptureSpeed,
		edgeSpeedFactor = CUP.EdgeSpeedFactor,
		verticalAbove = CUP.VerticalAbove,
		verticalBelow = CUP.VerticalBelow,
	}
end

local function captureAllowed(data: BallData): boolean
	if data.sim then
		return true
	end
	if data.owner == nil then
		return false
	end
	return not CUP.RequirePlayingPhase or currentPhase() == "Playing"
end

local function withinGimme(position: Vector3, cup: Vector3): boolean
	local dy = position.Y - cup.Y
	return dy <= CUP.VerticalAbove and dy >= -CUP.VerticalBelow and BallMath.flatDistance(position, cup) <= CUP.GimmeRadius
end

--------------------------------------------------------------------------------
-- Balles de simulation : résultats
--------------------------------------------------------------------------------

local function simResult(data: BallData, outcome: SimOutcome, hazard: string?, position: Vector3?): SimResult
	local at = position or data.ball.Position
	return {
		outcome = outcome,
		position = at,
		start = data.simStart,
		hazard = hazard,
		elapsed = if data.moveStartAt > 0 then math.max(0, now() - data.moveStartAt) else 0,
		distance = BallMath.flatDistance(data.simStart, at),
		maxHeight = math.max(0, data.simMaxY - data.simStart.Y),
		surface = data.surface,
	}
end

local function finishSim(data: BallData, outcome: SimOutcome, hazard: string?, position: Vector3?)
	local signal = data.simDone
	if signal then
		signal:Fire(simResult(data, outcome, hazard, position))
	end
end

local function destroyData(data: BallData)
	if data.removed then
		return
	end
	if data.sim then
		finishSim(data, "Removed", nil, nil)
	end
	data.removed = true
	data.guided = nil
	data.trove:Destroy()
	local signal = data.simDone
	if signal then
		data.simDone = nil
		signal:Destroy()
	end
end

--------------------------------------------------------------------------------
-- Règles de frappe
--------------------------------------------------------------------------------

local function phaseAllowsShot(data: BallData, phase: string): boolean
	if data.practice then
		return true
	end
	return phase == "Playing"
end

-- Prédicat de MatchService (balles de partie uniquement) ; une erreur vaut refus.
local function canShoot(player: Player, data: BallData): boolean
	if data.practice then
		return true
	end
	local predicate = canShootPredicate
	if not predicate then
		return true
	end
	local ok, result = pcall(predicate, player)
	if not ok then
		if not predicateErrorLogged then
			predicateErrorLogged = true
			Log.warn("Ball", "SetCanShoot : prédicat en erreur :", result)
		end
		return false
	end
	return result == true
end

local function hasActiveEffect(player: Player, effectId: string): boolean
	local ItemService = optionalService("ItemService")
	if ItemService and type(ItemService.HasEffect) == "function" then
		local ok, result = pcall(ItemService.HasEffect, player, effectId)
		return ok and result == true
	end
	return false
end

local function statusBlocksAim(player: Player, character: Model): boolean
	for _, name in SHOT.AimBlockingCharacterAttributes do
		if character:GetAttribute(name) == true or player:GetAttribute(name) == true then
			return true
		end
	end
	for _, effectId in SHOT.AimBlockingEffects do
		if hasActiveEffect(player, effectId) then
			return true
		end
	end
	return false
end

-- Raison empêchant de viser / frapper, ou nil. maxDistance nil : pas de contrôle de distance.
local function aimRefusal(player: Player, data: BallData, maxDistance: number?): string?
	if data.state == "Moving" then
		return "ball_moving"
	elseif data.state == "Holed" then
		return "finished"
	elseif data.state == "Frozen" then
		return "ball_frozen"
	end
	if not phaseAllowsShot(data, currentPhase()) then
		return "phase"
	end
	if not data.practice and player:GetAttribute("HoleFinished") == true then
		return "finished"
	end
	if player:GetAttribute("Spectating") == true then
		return "unavailable"
	end
	if CombatService.IsKnockedOut(player) or player:GetAttribute("KnockedOut") == true then
		return "stun"
	end
	local character, humanoid, root = NetworkValidation.GetAliveCharacter(player)
	if not character or not humanoid or not root then
		return "unavailable"
	end
	if humanoid.SeatPart ~= nil or player:GetAttribute("InVehicle") == true then
		return "vehicle"
	end
	if statusBlocksAim(player, character) then
		return "status"
	end
	if now() < data.aimBlockedUntil then
		return "blocked"
	end
	if not canShoot(player, data) then
		return "unavailable"
	end
	if maxDistance ~= nil and (root.Position - data.ball.Position).Magnitude > maxDistance then
		return "too_far"
	end
	return nil
end

-- RoundId courant obligatoire ; 0 accepté pour une balle d'entraînement.
local function roundAccepted(player: Player, data: BallData, roundId: number): boolean
	return NetworkValidation.CheckRound(player, roundId, data.practice)
end

local function puttAllowedFor(data: BallData): boolean
	local cup = getCup()
	local distance = if cup then BallMath.flatDistance(data.ball.Position, cup) else nil
	return BallMath.puttAllowed(refreshLie(data), distance, SHOT.PuttSurfaces, SHOT.PuttMaxCupDistance)
end

-- Période de la jauge (identique côté client) : suit la vitesse de jeu si Shot.GaugeFollowsGameSpeed.
local function gaugePeriod(): number
	if not SHOT.GaugeFollowsGameSpeed then
		return SHOT.PowerPeriod
	end
	local settings = readSettings()
	local speed = if settings and type(settings.gameSpeed) == "number" then settings.gameSpeed else nil
	return BallMath.powerPeriod(SHOT.PowerPeriod, BallMath.effectiveGameSpeed(currentPhase(), speed))
end

local function guidedAllowed(data: BallData): boolean
	return GUIDED.Enabled and (not data.practice or GUIDED.AllowPractice)
end

--------------------------------------------------------------------------------
-- Tir guidé (règles : Config/Gameplay.Guided)
--------------------------------------------------------------------------------

local function guidedPoint(target: Player): Vector3?
	local _, _, root = NetworkValidation.GetAliveCharacter(target)
	if not root then
		return nil
	end
	return root.Position + Vector3.new(0, GUIDED.AimHeight, 0)
end

local function guidedEligible(owner: Player, target: Player): boolean
	if target == owner or target.Parent ~= Players then
		return false
	end
	local character = target.Character
	if not character or character:GetAttribute("Invisible") == true then
		return false
	end
	if CombatService.IsKnockedOut(target) or CombatService.IsDodging(target) then
		return false
	end
	return CombatService.CanAffect(owner, target) -- adversaire, non protégé, en jeu, phase de combat
end

-- Ligne de vue « balle » : le décor bloque, les avatars non (groupe de collision Balls).
local function clearLine(from: Vector3, to: Vector3): boolean
	local params = solidParams
	if not params then
		return true
	end
	return Workspace:Raycast(from, to - from, params) == nil
end

-- Cible du tir guidé depuis les positions SERVEUR (cône élargi de Guided.ServerConeSlackDeg).
local function pickGuidedTarget(owner: Player, origin: Vector3, direction: Vector3): (Player?, Vector3?)
	local rules: BallMath.LockRules = {
		range = GUIDED.LockRange,
		minDistance = GUIDED.LockMinDistance,
		coneDeg = GUIDED.LockConeDeg + GUIDED.ServerConeSlackDeg,
		maxVerticalOffset = GUIDED.MaxVerticalOffset,
		angleWeight = GUIDED.AngleWeight,
	}
	local candidates: { BallMath.LockCandidate } = {}
	local targets: { Player } = {}
	local points: { Vector3 } = {}
	local maxReach = GUIDED.LockRange + GUIDED.MaxVerticalOffset
	for _, other in Players:GetPlayers() do
		if other == owner then
			continue
		end
		local point = guidedPoint(other)
		if not point then
			continue
		end
		local eligible = guidedEligible(owner, other)
		local visible = eligible and (point - origin).Magnitude <= maxReach and clearLine(origin, point)
		table.insert(targets, other)
		table.insert(points, point)
		table.insert(candidates, { position = point, eligible = eligible, lineOfSight = visible })
	end
	local index = BallMath.pickLockTarget(origin, direction, candidates, rules)
	if index == nil then
		return nil, nil
	end
	return targets[index], points[index]
end

local function startGuided(data: BallData, target: Player)
	local time = now()
	data.guided = {
		target = target,
		startedAt = time,
		nextCheckAt = time + GUIDED.LosCheckInterval,
		losLostAt = nil,
		airborne = false,
	}
	data.ball:SetAttribute("GuidedTargetUserId", target.UserId)
end

-- Un pas de guidage ; rompt le verrou selon les règles (durée, sol, cible inéligible, ligne de vue perdue).
local function stepGuided(data: BallData, position: Vector3, velocity: Vector3, dt: number, time: number): Vector3
	local guided = data.guided
	if not guided then
		return velocity
	end
	local owner = data.owner
	if not owner or time - guided.startedAt > GUIDED.MaxHomingTime then
		stopGuided(data)
		return velocity
	end
	if GUIDED.StopHomingOnGround and guided.airborne and data.grounded then
		stopGuided(data)
		return velocity
	end
	local target = guided.target
	local point = guidedPoint(target)
	if not point then
		stopGuided(data)
		return velocity
	end
	if time >= guided.nextCheckAt then
		guided.nextCheckAt = time + GUIDED.LosCheckInterval
		if not guidedEligible(owner, target) then
			stopGuided(data)
			return velocity
		end
		if clearLine(position, point) then
			guided.losLostAt = nil
		else
			local lostAt = guided.losLostAt or time
			guided.losLostAt = lostAt
			if time - lostAt >= GUIDED.LosGraceTime then
				stopGuided(data)
				return velocity
			end
		end
	end
	return BallMath.homingStep(velocity, point - position, math.rad(GUIDED.MaxTurnRateDeg), dt)
end

--------------------------------------------------------------------------------
-- Capture du trou
--------------------------------------------------------------------------------

local function capture(data: BallData, point: Vector3, cup: Vector3, gimme: boolean)
	local owner = data.owner
	if owner and data.aiming then
		leaveAim(owner, data)
	end
	clearFreeze(data)
	cancelSink(data)
	immobilize(data, point)
	setState(data, "Holed")

	-- Animation : la balle (ancrée) glisse au centre du trou et s'y enfonce.
	local ball = data.ball
	local tween = TweenService:Create(
		ball,
		TweenInfo.new(CUP.SinkTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = CFrame.new(cup.X, cup.Y - CUP.SinkDepth, cup.Z) }
	)
	data.sinkTween = tween
	data.trove:Add(tween)
	tween.Completed:Once(function(playbackState: Enum.PlaybackState)
		if playbackState == Enum.PlaybackState.Completed and not data.removed and data.state == "Holed" and data.sinkTween == tween then
			ball.Transparency = 1
		end
	end)
	tween:Play()

	if data.sim then
		finishSim(data, "Holed", nil, point)
		return
	end
	if not owner then
		return
	end
	local external = data.externalImpulse
	local count = strokes[owner] or 0
	local info: HoledInfo = {
		strokes = count,
		shotDistance = if external then 0 else BallMath.flatDistance(data.shotOrigin, point),
		fromDistance = if external then 0 else (data.shotFromDistance or BallMath.flatDistance(data.shotOrigin, cup)),
		wasPutt = not external and data.shotType == "Putt",
		holeInOne = not external and not data.practice and count == 1,
		shotType = data.shotType,
		gimme = gimme,
		external = external,
		practice = data.practice,
	}
	fireSound("ball_cup_drop", cup)
	Net.fireAll("Golf.Holed", owner.UserId, {
		strokes = info.strokes,
		fromDistance = info.fromDistance,
		holeInOne = info.holeInOne,
		effectId = equippedId(owner, "HoleEffect"),
		shotType = info.shotType,
		wasPutt = info.wasPutt,
		gimme = gimme,
		practice = data.practice,
	})
	Log.debug("Ball", owner.Name, "dans le trou en", count, if gimme then "(gimme)" else "")
	BallService.Holed:Fire(owner, info)
end

-- Balle trop rapide passée sur le trou : légère déviation et perte de vitesse (une fois par passage).
local function lipOut(data: BallData, velocity: Vector3, closest: Vector3, cup: Vector3, time: number): Vector3
	if time < data.lipOutUntil then
		return velocity
	end
	data.lipOutUntil = time + CUP.LipOutCooldown
	if not data.sim then
		notifyKey(data.owner, "golf.lipOut")
	end
	return BallMath.lipOutDeflect(velocity, closest, cup, CUP.LipOutDeflectDeg, CUP.LipOutSpeedKeep)
end

--------------------------------------------------------------------------------
-- Dangers et replacement
--------------------------------------------------------------------------------

local detectHazard = Hazards.detect

-- Pénalité automatique d'un danger (0 : simulation, poussée extérieure, ou hors phase de jeu).
local function hazardPenalty(data: BallData, reason: string): number
	if data.sim or data.owner == nil then
		return 0
	end
	if data.externalImpulse and HAZARDS.WaiveForExternalImpulse then
		return 0
	end
	if not data.practice and currentPhase() ~= "Playing" then
		return 0
	end
	local value = HAZARDS.Penalties[reason]
	return if type(value) == "number" then value else 1
end

-- Replace la balle (dernière position valide ou `destination`), ajoute la pénalité et prévient le joueur.
local function resetBall(data: BallData, reason: string, penalty: number?, effectAt: Vector3?, destination: Vector3?): number
	local owner = data.owner
	if owner and data.aiming then
		leaveAim(owner, data)
		Net.fire("Golf.AimCancelled", owner, "respawn")
	end
	local amount = if penalty ~= nil then penalty else hazardPenalty(data, reason)
	amount = math.floor(math.clamp(amount, 0, HAZARDS.MaxPenalty))
	if data.sim then
		local isHazard = HAZARD_KINDS[reason] == true
		finishSim(data, if isHazard then "Hazard" else "Stuck", if isHazard then reason else nil, effectAt or data.ball.Position)
	end
	clearFreeze(data)
	cancelSink(data)
	local target = destination or data.lastValid
	immobilize(data, target)
	data.ball.Transparency = 0
	setState(data, "Resting")
	data.lastValid = target
	data.externalImpulse = false
	refreshLie(data)
	if effectAt and not data.sim then
		local effect = FEEDBACK.HazardEffects[reason]
		if type(effect) == "string" and effect ~= "" then
			fireEffect(effect, { position = effectAt, radius = FEEDBACK.LavaEffectRadius })
		end
	end
	if owner then
		if amount > 0 then
			addStrokes(owner, amount)
		end
		BallService.Respawned:Fire(owner, reason)
		Net.fire("Golf.BallReset", owner, reason, amount)
	end
	return amount
end

--------------------------------------------------------------------------------
-- Arrêt, atterrissage
--------------------------------------------------------------------------------

-- natural = arrêt reconnu par la règle vitesse + pente (la position devient « valide ») ;
-- false = immobilisation forcée (blocage, durée maximale) : la dernière position valide est conservée.
local function settle(data: BallData, natural: boolean)
	local position = data.ball.Position
	local cup = getCup()
	if cup and captureAllowed(data) and withinGimme(position, cup) then
		capture(data, position, cup, true)
		return
	end
	immobilize(data, nil)
	setState(data, "Resting")
	refreshLie(data)
	if natural then
		data.lastValid = position
	end
	if data.sim then
		finishSim(data, "Resting", nil, position)
		return
	end
	local owner = data.owner
	if owner then
		applySkin(owner, data)
		BallService.Rested:Fire(owner, position)
	end
end

local function onLanding(data: BallData, ground: RaycastResult, velocity: Vector3, time: number)
	if data.sim then
		return
	end
	local impact = -velocity.Y
	if impact < LANDING_FX_MIN_SPEED or time - data.landingFxAt < LANDING_FX_COOLDOWN then
		return
	end
	data.landingFxAt = time
	if data.surface == "Sand" then
		fireEffect("SandPuff", { position = ground.Position }, true)
		fireSound("sand_thud", ground.Position)
	end
end

--------------------------------------------------------------------------------
-- Impacts sur les joueurs
--------------------------------------------------------------------------------

local function playerFromPart(part: Instance): Player?
	local current = part.Parent
	while current and current ~= Workspace do
		if current:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(current)
			if player then
				return player
			end
		end
		current = current.Parent
	end
	return nil
end

-- Requête spatiale serveur (la balle ne touche jamais physiquement un avatar) ; CombatService décide du KO.
local function checkPlayerHits(data: BallData, velocity: Vector3, position: Vector3, time: number): boolean
	local owner = data.owner
	if not owner or data.sim then
		return false
	end
	if data.practice and not BALL.PracticeBallsCanHitPlayers then
		return false
	end
	if velocity.Magnitude < BALL_HIT.MinSpeed then
		return false
	end
	local params = hitOverlap
	if not params or #characterList == 0 then
		return false
	end
	local parts = Workspace:GetPartBoundsInRadius(position, ballRadius() + BALL_HIT.HitRadiusExtra, params)
	if #parts == 0 then
		return false
	end
	local seen: { [Player]: boolean } = {}
	for _, part in parts do
		local victim = playerFromPart(part)
		if not victim or victim == owner or seen[victim] then
			continue
		end
		seen[victim] = true
		local last = data.hitCooldowns[victim]
		if last ~= nil and time - last < BALL_HIT.HitCooldown then
			continue
		end
		data.hitCooldowns[victim] = time
		if CombatService.BallHit(owner, victim, velocity) then
			data.ball.AssemblyLinearVelocity = velocity * BALL_HIT.BallSlowdown
			fireEffect(FEEDBACK.BallHitEffect, { position = position })
			BallService.PlayerHit:Fire(owner, victim)
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Anti-traversée
--------------------------------------------------------------------------------

-- Balayage entre deux Heartbeat. Retourne (position corrigée, vitesse réfléchie) si le CENTRE de la balle a
-- franchi une surface (confirmation par un rayon central), sinon (nil, vitesse inchangée).
local function sweepCorrection(from: Vector3, to: Vector3, velocity: Vector3, radius: number): (Vector3?, Vector3)
	local params = solidParams
	local delta = to - from
	local distance = delta.Magnitude
	if not params or distance < ANTI.MinSweepDistance or distance > ANTI.MaxSweepDistance then
		return nil, velocity
	end
	local ok, hit = pcall(function(): RaycastResult?
		return Workspace:Spherecast(from, radius * ANTI.CastRadiusScale, delta, params)
	end)
	if not ok or hit == nil then
		return nil, velocity
	end
	local contact: RaycastResult = hit
	if ANTI.ConfirmWithCenterRay then
		local centerHit = Workspace:Raycast(from, delta, params)
		if centerHit == nil then
			return nil, velocity -- contact rasant (sol de roulement, bordure) : le moteur s'en charge
		end
		contact = centerHit
	end
	local placed = contact.Position + contact.Normal * (radius + ANTI.SkinDistance)
	local elasticity = surfaceDef(surfaceFromHit(contact.Instance, contact.Material)).Elasticity
	return placed, BallMath.reflect(velocity, contact.Normal, elasticity, ANTI.TangentialKeep)
end

--------------------------------------------------------------------------------
-- Pas de simulation d'une balle en mouvement
--------------------------------------------------------------------------------

local function stepBall(data: BallData, dt: number, time: number)
	local ball = data.ball
	local previous = data.lastPosition
	local position = ball.Position
	local velocity = ball.AssemblyLinearVelocity
	if not BallMath.isFiniteVector(position) or not BallMath.isFiniteVector(velocity) then
		-- État physique corrompu : retour à la dernière position valide, sans pénalité.
		resetBall(data, "stuck", 0, nil, nil)
		return
	end
	local radius = ballRadius()

	-- 1. Anti-traversée.
	if ANTI.Enabled then
		local corrected, reflected = sweepCorrection(previous, position, velocity, radius)
		if corrected then
			position = corrected
			velocity = reflected
			ball.CFrame = CFrame.new(corrected) * ball.CFrame.Rotation
			ball.AssemblyLinearVelocity = reflected
		end
	end
	if data.sim and position.Y > data.simMaxY then
		data.simMaxY = position.Y
	end

	-- 2. Trou : segment balayé depuis la position précédente (une balle rapide ne « saute » pas le trou).
	local cup, holeRadius = getCup()
	local canCapture = cup ~= nil and captureAllowed(data)
	if cup and canCapture then
		local result, closest = BallMath.cupCapture(previous, position, BallMath.flat(velocity).Magnitude, cup, cupParams(holeRadius))
		if result == "captured" and closest then
			capture(data, closest, cup, false)
			return
		elseif result == "lipOut" and closest then
			velocity = lipOut(data, velocity, closest, cup, time)
		end
	end

	-- 3. Sol et surface.
	local ground = groundProbe(position, BALL.GroundRayExtra)
	local wasGrounded = data.grounded
	data.grounded = ground ~= nil
	if ground then
		data.groundNormal = ground.Normal
		applySurface(data, surfaceFromHit(ground.Instance, ground.Material))
		if not wasGrounded then
			onLanding(data, ground, velocity, time)
		end
	else
		local guided = data.guided
		if guided then
			guided.airborne = true
		end
	end

	-- 4. Dangers.
	if position.Y < killHeight() then
		resetBall(data, "void", nil, position, nil)
		return
	end
	local hazard, hazardAt = detectHazard(data, previous, position, dt)
	if hazard then
		resetBall(data, hazard, nil, hazardAt, nil)
		return
	end

	-- 5. Forces : guidage, vent et traînée de l'air en vol, roulement au sol, plafond de vitesse.
	velocity = stepGuided(data, position, velocity, dt, time)
	if data.grounded then
		if math.abs(velocity.Y) < BALL.DragMaxVerticalSpeed then
			local before = velocity.Magnitude
			local surface = surfaceDef(data.surface)
			velocity = BallMath.rollStep(velocity, surface.Drag, surface.RollResistance, dt)
			-- Même rapport sur la rotation : sinon le frottement remettrait la balle à sa vitesse de roulement.
			if before > 1e-6 then
				ball.AssemblyAngularVelocity *= velocity.Magnitude / before
			end
		end
	else
		velocity = BallMath.airStep(velocity, if data.windEnabled then wind else Vector3.zero, BALL.AirDrag, dt)
	end
	velocity = clampMagnitude(velocity, data.maxSpeed)
	ball.AssemblyLinearVelocity = velocity

	-- 6. Impacts sur les joueurs.
	if checkPlayerHits(data, velocity, position, time) then
		velocity = ball.AssemblyLinearVelocity
	end

	-- 7. Arrêt : gimme, repos, blocage, durée maximale.
	local speed = velocity.Magnitude
	if cup and canCapture and speed < BALL.RestSpeed and withinGimme(position, cup) then
		data.gimmeTimer += dt
		if data.gimmeTimer >= CUP.GimmeDelay then
			capture(data, position, cup, true)
			return
		end
	else
		data.gimmeTimer = 0
	end
	if data.grounded and speed < BALL.RestSpeed then
		data.restTimer += dt
		if data.restTimer >= BALL.RestTime then
			local gravity = BallMath.effectiveGravity(Workspace.Gravity, BALL.GravityScale)
			if BallMath.canRestOnSlope(data.groundNormal, gravity, surfaceDef(data.surface).RollResistance, BALL.RestSlopeMargin) then
				settle(data, true)
				return
			end
		end
	else
		data.restTimer = 0
	end
	if (position - data.stuckAnchor).Magnitude > STUCK.MinDisplacement then
		data.stuckAnchor = position
		data.stuckTimer = 0
	else
		data.stuckTimer += dt
	end
	if data.stuckTimer >= STUCK.Time or time - data.moveStartAt > BALL.MaxMoveTime then
		if data.grounded then
			settle(data, false)
		else
			resetBall(data, "stuck", 0, nil, nil)
		end
		return
	end
	data.lastPosition = position
end

--------------------------------------------------------------------------------
-- Instance disparue (supprimée par un autre script ou par le moteur)
--------------------------------------------------------------------------------

local function rebuildPlayerBall(data: BallData)
	local old = data.ball
	local folder = ensureFolders()
	local ball, trail, force = buildBallInstance(old.Name, data.lastValid, data.userId, data.practice)
	local skin = old:GetAttribute("Skin")
	ball:SetAttribute("Skin", if type(skin) == "string" then skin else "")
	data.trove:Remove(old)
	pcall(function()
		old:Destroy()
	end)
	cancelSink(data)
	data.ball = ball
	data.trail = trail
	data.gravityForce = force
	data.trove:Add(ball)
	data.guided = nil
	data.surface = DEFAULT_SURFACE
	data.state = "Resting"
	data.lastPosition = data.lastValid
	data.boost = 1
	data.boostUntil = 0
	ball.Parent = folder
	refreshLie(data)
	Log.warn("Ball", "instance de balle disparue, recréée à la dernière position valide :", ball.Name)
end

local function handleMissingInstance(data: BallData)
	if data.sim then
		sims[data.ball] = nil
		destroyData(data)
		return
	end
	local owner = data.owner
	if owner and data.aiming then
		leaveAim(owner, data)
		Net.fire("Golf.AimCancelled", owner, "respawn")
	end
	clearFreeze(data)
	unschedule(data.trove, data.boostThread)
	data.boostThread = nil
	rebuildPlayerBall(data)
	if owner then
		BallService.Respawned:Fire(owner, "stuck")
		Net.fire("Golf.BallReset", owner, "stuck", 0)
	end
end

--------------------------------------------------------------------------------
-- Boucles
--------------------------------------------------------------------------------

local function processBall(data: BallData, dt: number, time: number)
	if data.removed or data.state ~= "Moving" then
		return
	end
	if data.ball.Parent == nil then
		handleMissingInstance(data)
		return
	end
	local ok, err = pcall(stepBall, data, dt, time)
	if not ok then
		data.errors += 1
		if data.errors <= BALL.ErrorLogLimit then
			Log.warn("Ball", "erreur de simulation :", data.ball.Name, err)
		end
	end
end

-- Balles immobiles : support disparu (plateforme, glace temporaire) -> la balle retombe, sans pénalité.
local function checkRestingSupport()
	for _, data in table.clone(balls) do
		if data.removed then
			continue
		end
		if data.ball.Parent == nil then
			handleMissingInstance(data)
			continue
		end
		if data.state ~= "Resting" then
			continue
		end
		local ok, ground = pcall(groundProbe, data.ball.Position, BALL.SupportProbeExtra)
		if ok and ground == nil then
			local owner = data.owner
			if owner and data.aiming then
				BallService.CancelAim(owner, "ball_moving")
			end
			data.externalImpulse = true
			data.maxSpeed = BALL.MaxSpeed
			data.windEnabled = false
			release(data, Vector3.zero)
		end
	end
	for _, data in table.clone(sims) do
		if not data.removed and data.ball.Parent == nil then
			handleMissingInstance(data)
		end
	end
end

-- Joueurs en visée : distance de sortie, phase, état ; jauge tenue trop longtemps.
local function watchAims(time: number)
	for player, data in table.clone(balls) do
		if not data.aiming or data.removed then
			continue
		end
		local refusal = aimRefusal(player, data, SHOT.AimExitDistance + SHOT.DistanceTolerance)
		if refusal then
			BallService.CancelAim(player, refusal)
		else
			local swingStartAt = data.swingStartAt
			if swingStartAt ~= nil and time - swingStartAt > SHOT.MaxSwingTime + AIM_CHARGE_GRACE then
				BallService.CancelAim(player, "invalid")
			end
		end
	end
end

local function onHeartbeat(dt: number)
	local time = now()
	-- Copies : un écouteur de signal peut retirer ou créer des balles pendant le parcours.
	for _, data in table.clone(balls) do
		processBall(data, dt, time)
	end
	if next(sims) ~= nil then
		for _, data in table.clone(sims) do
			processBall(data, dt, time)
		end
	end
	supportTimer += dt
	if supportTimer >= BALL.RestingSupportInterval then
		supportTimer = 0
		checkRestingSupport()
	end
	aimWatchTimer += dt
	if aimWatchTimer >= SHOT.AimWatchInterval then
		aimWatchTimer = 0
		watchAims(time)
	end
end

--------------------------------------------------------------------------------
-- Départ d'un coup
--------------------------------------------------------------------------------

local function launchShot(
	player: Player,
	data: BallData,
	aim: Vector3,
	loftRaw: number?,
	power: number,
	shotType: string,
	opts: ShotOptions
): ShotInfo
	local def: ShotTypeDef = SHOT_TYPES[shotType]
	local loft = BallMath.clampLoft(loftRaw, def)
	local boost = consumeBoost(data)
	local velocity = BallMath.launchVelocity(aim, loft, power, def) * boost
	local ball = data.ball
	local origin = ball.Position
	local cup = getCup()
	local time = now()

	leaveAim(player, data)
	data.lastShotAt = time
	data.shotOrigin = origin
	data.shotType = shotType
	data.shotFromDistance = if cup then BallMath.flatDistance(origin, cup) else nil
	data.externalImpulse = false
	data.hitCooldowns = {}
	data.lipOutUntil = 0
	data.maxSpeed = BALL.MaxSpeed * boost -- frappe amplifiée : plafond relevé pour ce coup
	data.windEnabled = not data.practice or BALL.PracticeWind
	local count = addStrokes(player, 1)

	ball.CFrame = ball.CFrame + Vector3.new(0, BALL.LiftOff, 0)
	release(data, velocity)

	local target = opts.target
	if target then
		startGuided(data, target)
		guidedReadyAt[player] = time + GUIDED.Cooldown
		if GUIDED.EndsProtection then
			CombatService.EndProtection(player)
		end
	end

	playSwingAnim(player, shotType)
	fireSound(if shotType == "Putt" then "ball_hit_putt" else "ball_hit_drive", origin)

	local info: ShotInfo = {
		shotType = shotType,
		loft = loft,
		power = power,
		speed = velocity.Magnitude,
		origin = origin,
		direction = aim,
		fromDistance = data.shotFromDistance,
		forced = opts.forced,
		reason = opts.reason,
		practice = data.practice,
		boost = boost,
		targetUserId = if target then target.UserId else 0,
	}
	Net.fire("Golf.ShotAccepted", player, {
		strokes = count,
		power = power,
		shotType = shotType,
		forced = opts.forced,
		reason = opts.reason,
		boost = boost,
		targetUserId = info.targetUserId,
	})
	BallService.Shot:Fire(player, count, power, info)
	return info
end

--------------------------------------------------------------------------------
-- Intentions client
--------------------------------------------------------------------------------

local function onAimState(player: Player, roundId: number, isAiming: boolean)
	local data = balls[player]
	if not isAiming then
		-- Quitter la visée est toujours accepté (aucune capacité gagnée).
		if data then
			leaveAim(player, data)
		end
		return
	end
	if not data then
		NetworkValidation.Report(player, "no_ball")
		Net.fire("Golf.AimCancelled", player, "unavailable")
		return
	end
	if not roundAccepted(player, data, roundId) then
		Net.fire("Golf.AimCancelled", player, "phase")
		return
	end
	if data.aiming then
		return
	end
	local refusal = aimRefusal(player, data, SHOT.AimEnterDistance + SHOT.DistanceTolerance)
	if refusal then
		if refusal == "too_far" then
			NetworkValidation.Report(player, "aim_too_far")
		end
		Net.fire("Golf.AimCancelled", player, refusal)
		return
	end
	enterAim(player, data)
end

local function onSwingStart(player: Player, roundId: number)
	local data = balls[player]
	if not data or not roundAccepted(player, data, roundId) then
		return
	end
	if not data.aiming or data.state ~= "Resting" then
		return
	end
	data.swingStartAt = now() -- horodatage SERVEUR : seule référence du calcul de la puissance
	setAimAnim(player, "Charging")
end

local function onShoot(player: Player, roundId: number, direction: Vector3, loft: number, clientPower: number?, shotTypeRaw: string?)
	local data = balls[player]
	if not data then
		NetworkValidation.Report(player, "no_ball")
		return
	end
	if not roundAccepted(player, data, roundId) then
		BallService.CancelAim(player, "phase")
		return
	end
	if not data.aiming then
		NetworkValidation.Report(player, "shot_without_aim")
		Net.fire("Golf.AimCancelled", player, "invalid")
		return
	end
	local swingStartAt = data.swingStartAt
	if swingStartAt == nil then
		NetworkValidation.Report(player, "shot_without_swing")
		BallService.CancelAim(player, "invalid")
		return
	end
	local aim = Validate.flatUnit(direction)
	if not aim then
		NetworkValidation.Report(player, "shot_direction")
		BallService.CancelAim(player, "invalid")
		return
	end
	local shotType = BallMath.resolveShotType(shotTypeRaw, SHOT_TYPES, SHOT.DefaultType)
	if shotType == nil or (shotType == "Guided" and not guidedAllowed(data)) then
		NetworkValidation.Report(player, "shot_type", { value = tostring(shotTypeRaw) })
		BallService.CancelAim(player, "invalid")
		return
	end
	local time = now()
	local elapsed = time - swingStartAt
	if elapsed < SHOT.MinSwingTime or elapsed > SHOT.MaxSwingTime then
		NetworkValidation.Report(player, "swing_timing", { elapsed = elapsed })
		BallService.CancelAim(player, "invalid")
		return
	end
	if time - data.lastShotAt < SHOT.Cooldown then
		NetworkValidation.Report(player, "shot_cooldown")
		BallService.CancelAim(player, "cooldown")
		return
	end
	local refusal = aimRefusal(player, data, SHOT.AimEnterDistance + SHOT.DistanceTolerance)
	if refusal then
		if refusal == "too_far" then
			NetworkValidation.Report(player, "shot_too_far")
		end
		BallService.CancelAim(player, refusal)
		return
	end
	if shotType == "Putt" and not puttAllowedFor(data) then
		NetworkValidation.Report(player, "putt_refused")
		BallService.CancelAim(player, "putt_not_allowed")
		return
	end
	local target: Player? = nil
	if shotType == "Guided" then
		if time < (guidedReadyAt[player] or 0) then
			BallService.CancelAim(player, "guided_cooldown")
			return
		end
		local ballPosition = data.ball.Position
		local chosen, point = pickGuidedTarget(player, ballPosition, aim)
		if not chosen or not point then
			BallService.CancelAim(player, "no_target") -- aucun coup compté
			return
		end
		target = chosen
		aim = Validate.flatUnit(point - ballPosition) or aim -- départ vers la cible, le guidage corrige ensuite
	end

	-- Puissance autoritaire : recalculée depuis l'heure serveur de Golf.SwingStart.
	local period = gaugePeriod()
	local serverValue = BallMath.powerAtTime(elapsed, period)
	if clientPower ~= nil and math.abs(clientPower - serverValue) > SHOT.PowerReportDeviation then
		NetworkValidation.Report(player, "power_deviation", { client = clientPower, server = serverValue })
	end
	local power = BallMath.serverPower(elapsed, clientPower, period, SHOT.PowerTolerance)
	launchShot(player, data, aim, loft, power, shotType, { forced = false, reason = nil, target = target })
end

-- Raison de refus de Golf.ResetBall, ou nil.
local function resetRefusal(player: Player, data: BallData): string?
	if data.state == "Holed" then
		return "holed"
	elseif data.state == "Frozen" then
		return "frozen"
	end
	if not phaseAllowsShot(data, currentPhase()) then
		return "phase"
	end
	if not data.practice and player:GetAttribute("HoleFinished") == true then
		return "finished"
	end
	if data.state == "Moving" then
		if now() - data.lastShotAt < BALL.ResetMinDelay then
			return "too_soon"
		end
		return nil
	end
	-- Balle arrêtée : « coup et distance » vers le départ du coup précédent.
	if (data.ball.Position - data.shotOrigin).Magnitude <= BALL.ResetMinDistance then
		return "already_valid"
	end
	return nil
end

local function onResetBall(player: Player, roundId: number)
	local data = balls[player]
	if not data then
		NetworkValidation.Report(player, "no_ball")
		return
	end
	if not roundAccepted(player, data, roundId) then
		return
	end
	local refusal = resetRefusal(player, data)
	if refusal then
		NetworkValidation.Report(player, "reset_refused", { reason = refusal })
		notifyKey(player, "golf.reset.refused")
		return
	end
	local destination = if data.state == "Resting" then data.shotOrigin else data.lastValid
	local penalty = if data.practice or currentPhase() == "Playing" then (HAZARDS.Penalties.stuck or 1) else 0
	resetBall(data, "stuck", penalty, nil, destination)
end

--------------------------------------------------------------------------------
-- API publique : balles
--------------------------------------------------------------------------------

function BallService.SpawnBall(player: Player, position: Vector3 | CFrame, opts: SpawnOptions?): BasePart?
	if not isPlayer(player) or player.Parent ~= Players then
		Log.warn("Ball", "SpawnBall : joueur invalide")
		return nil
	end
	local requested = toPosition(position)
	if not requested then
		Log.warn("Ball", "SpawnBall : position invalide pour", player.Name)
		return nil
	end
	local options: SpawnOptions = opts or {}
	local folder = ensureFolders()
	local target = if options.snap == false then requested else snapToGround(requested)
	BallService.RemoveBall(player)
	local practice = if options.practice ~= nil then options.practice == true else isPracticePhase(currentPhase())
	local ball, trail, force = buildBallInstance("GolfBall_" .. player.UserId, target, player.UserId, practice)
	local data = newData(player, ball, trail, force, target, practice, false)
	data.practiceExplicit = options.practice ~= nil
	balls[player] = data
	ball.Parent = folder
	refreshLie(data)
	applySkin(player, data)
	strokes[player] = 0
	player:SetAttribute("Strokes", 0)
	player:SetAttribute("Aiming", false)
	return ball
end

function BallService.PlaceBall(player: Player, position: Vector3 | CFrame, snap: boolean?): BasePart?
	local data = balls[player]
	if not data then
		return BallService.SpawnBall(player, position, { snap = snap })
	end
	local requested = toPosition(position)
	if not requested then
		Log.warn("Ball", "PlaceBall : position invalide pour", player.Name)
		return data.ball
	end
	local target = if snap == false then requested else snapToGround(requested)
	if data.aiming then
		leaveAim(player, data)
		Net.fire("Golf.AimCancelled", player, "respawn")
	end
	if data.ball.Parent == nil then
		rebuildPlayerBall(data)
	end
	clearFreeze(data)
	cancelSink(data)
	-- Balle d'entraînement implicite replacée pendant une partie : elle devient une balle de partie.
	if data.practice and not data.practiceExplicit and not isPracticePhase(currentPhase()) then
		data.practice = false
		data.ball:SetAttribute("Practice", false)
	end
	immobilize(data, target)
	data.ball.Transparency = 0
	setState(data, "Resting")
	data.lastValid = target
	data.shotOrigin = target
	data.shotFromDistance = nil
	data.externalImpulse = false
	refreshLie(data)
	applySkin(player, data)
	return data.ball
end

function BallService.RemoveBall(player: Player)
	local data = balls[player]
	if not data then
		return
	end
	balls[player] = nil
	if data.aiming then
		leaveAim(player, data)
		Net.fire("Golf.AimCancelled", player, "unavailable")
	end
	destroyData(data)
end

-- Toutes les balles (et balles de simulation) : appelé par MatchService en fin de trou.
function BallService.RemoveAll()
	local owners: { Player } = {}
	for player in balls do
		table.insert(owners, player)
	end
	for _, player in owners do
		BallService.RemoveBall(player)
	end
	local simulations: { BallData } = {}
	for _, data in sims do
		table.insert(simulations, data)
	end
	table.clear(sims)
	for _, data in simulations do
		destroyData(data)
	end
	table.clear(guidedReadyAt)
end

function BallService.GetBall(player: Player): BasePart?
	local data = balls[player]
	return if data then data.ball else nil
end

function BallService.GetState(player: Player): BallState?
	local data = balls[player]
	return if data then data.state else nil
end

function BallService.GetAllBalls(): { [Player]: BasePart }
	local result: { [Player]: BasePart } = {}
	for player, data in balls do
		result[player] = data.ball
	end
	return result
end

function BallService.GetLastValid(player: Player): Vector3?
	local data = balls[player]
	return if data then data.lastValid else nil
end

function BallService.IsPractice(player: Player): boolean
	local data = balls[player]
	return data ~= nil and data.practice
end

function BallService.IsAiming(player: Player): boolean
	local data = balls[player]
	return data ~= nil and data.aiming
end

function BallService.IsCharging(player: Player): boolean
	local data = balls[player]
	return data ~= nil and data.aiming and data.swingStartAt ~= nil
end

function BallService.RefreshSkin(player: Player)
	local data = balls[player]
	if data and not data.removed then
		applySkin(player, data)
	end
end

--------------------------------------------------------------------------------
-- API publique : coups et pénalités
--------------------------------------------------------------------------------

function BallService.GetStrokes(player: Player): number
	return strokes[player] or 0
end

function BallService.ResetStrokes(player: Player)
	if not isPlayer(player) then
		return
	end
	strokes[player] = 0
	if player.Parent then
		player:SetAttribute("Strokes", 0)
	end
end

-- Ajoute des coups de pénalité (appel explicite d'un service : appliqué quelle que soit la phase).
function BallService.AddPenalty(player: Player, count: number, reason: string?)
	if not isPlayer(player) then
		return
	end
	local amount = math.floor(Validate.clampNumber(count, 0, HAZARDS.MaxPenalty, 0))
	if amount <= 0 then
		return
	end
	local total = addStrokes(player, amount)
	notifyKey(player, "golf.penalty.added", { n = amount })
	Log.debug("Ball", player.Name, "pénalité +" .. amount, reason or "", "total", total)
end

--------------------------------------------------------------------------------
-- API publique : trou, vent, règles
--------------------------------------------------------------------------------

-- position nil : aucun trou (repli sur CourseService s'il a un trou chargé).
function BallService.SetCup(position: Vector3?, radius: number?)
	if position == nil then
		cupPosition = nil
		cupRadius = CUP.Radius
		return
	end
	if not Validate.isFiniteVector3(position) then
		Log.warn("Ball", "SetCup : position invalide")
		return
	end
	cupPosition = position
	cupRadius = Validate.clampNumber(radius, CUP.MinRadius, CUP.MaxRadius, CUP.Radius)
	publish("CupPosition", position)
end

function BallService.GetCup(): (Vector3?, number)
	return getCup()
end

-- Accélération horizontale du vent (studs/s²), bornée à Wind.MaxAcceleration.
function BallService.SetWind(vector: Vector3?)
	local value = Vector3.zero
	if vector ~= nil and Validate.isFiniteVector3(vector) then
		value = clampMagnitude(Vector3.new(vector.X, 0, vector.Z), WIND.MaxAcceleration)
	end
	wind = value
	if WIND.PublishToGameState then
		publish("Wind", value)
	end
end

function BallService.GetWind(): Vector3
	return wind
end

-- Prédicat de MatchService pour les balles de PARTIE (nil : aucune restriction supplémentaire).
function BallService.SetCanShoot(predicate: ((Player) -> boolean)?)
	canShootPredicate = if type(predicate) == "function" then predicate else nil
	predicateErrorLogged = false
end

-- Interactions physiques entre balles (CollisionService) ; imposé jusqu'au prochain changement de phase ou
-- de réglages (Collision.SyncBallCollisionsWithSettings).
function BallService.SetBallCollisions(enabled: boolean)
	CollisionService.SetBallCollisions(enabled == true)
end

--------------------------------------------------------------------------------
-- API publique : visée, frappes forcées, effets des objets
--------------------------------------------------------------------------------

function BallService.CancelAim(player: Player, reason: string?, blockSeconds: number?)
	local data = balls[player]
	if not data then
		return
	end
	local wasAiming = data.aiming
	leaveAim(player, data)
	if blockSeconds ~= nil and Validate.isFiniteNumber(blockSeconds) and blockSeconds > 0 then
		data.aimBlockedUntil = math.max(data.aimBlockedUntil, now() + math.min(blockSeconds, MAX_AIM_BLOCK_SECONDS))
	end
	if wasAiming then
		Net.fire("Golf.AimCancelled", player, if type(reason) == "string" and reason ~= "" then reason else "unavailable")
	end
end

-- Frappe prématurée (Corne Tonitruante) : joueur qui charge -> frappe immédiate à la puissance serveur
-- courante ; joueur qui vise -> frappe faible et imprécise (Shot.ForcedShotWhenAiming = "weak") ou refus.
-- Direction : convention d'adresse (le client oriente le personnage, regard = visée × Y).
function BallService.ForceShot(player: Player, reason: string?): boolean
	local data = balls[player]
	if not data or not data.aiming or data.state ~= "Resting" then
		return false
	end
	local why = if type(reason) == "string" and reason ~= "" then reason else "forced"
	local refusal = aimRefusal(player, data, nil)
	if refusal then
		BallService.CancelAim(player, refusal)
		return false
	end
	local _, _, root = NetworkValidation.GetAliveCharacter(player)
	if not root then
		return false
	end
	local aim = BallMath.aimFromAddressLook(root.CFrame.LookVector)
		or Validate.flatUnit(data.ball.Position - root.Position)
		or Vector3.new(0, 0, -1)
	local shotType: string = if puttAllowedFor(data) then SHOT.ForcedShotTypeNearCup else SHOT.ForcedShotType
	if SHOT_TYPES[shotType] == nil or shotType == "Guided" then
		shotType = SHOT.DefaultType
	end
	local power: number
	local swingStartAt = data.swingStartAt
	if swingStartAt ~= nil then
		power = BallMath.powerAtTime(now() - swingStartAt, gaugePeriod())
	elseif SHOT.ForcedShotWhenAiming == "weak" then
		local generator = getRandom()
		local low = math.min(SHOT.ForcedWeakPowerMin, SHOT.ForcedWeakPowerMax)
		local high = math.max(SHOT.ForcedWeakPowerMin, SHOT.ForcedWeakPowerMax)
		power = generator:NextNumber(low, high)
		local spread = math.rad(math.abs(SHOT.ForcedWeakSpreadDeg))
		aim = BallMath.rotateAroundY(aim, generator:NextNumber(-spread, spread))
	else
		return false
	end
	launchShot(player, data, aim, nil, math.clamp(power, 0, 1), shotType, { forced = true, reason = why, target = nil })
	return true
end

local function applyImpulseTo(data: BallData, velocity: Vector3, source: string?): boolean
	if typeof(velocity) ~= "Vector3" or not BallMath.isFiniteVector(velocity) then
		return false
	end
	if data.removed or data.state == "Holed" or data.state == "Frozen" then
		return false
	end
	if data.ball.Parent == nil then
		return false
	end
	local delta = clampMagnitude(velocity, BALL.MaxSpeed)
	if delta.Magnitude < 1e-3 then
		return false
	end
	stopGuided(data)
	if data.state == "Resting" then
		local owner = data.owner
		if owner and data.aiming then
			BallService.CancelAim(owner, "ball_moving")
		end
		data.maxSpeed = BALL.MaxSpeed
		data.windEnabled = not data.sim and (not data.practice or BALL.PracticeWind)
		release(data, delta)
	else
		local ball = data.ball
		ball.AssemblyLinearVelocity = clampMagnitude(ball.AssemblyLinearVelocity + delta, data.maxSpeed)
	end
	data.externalImpulse = true
	Log.debug("Ball", data.ball.Name, "impulsion", source or "?", string.format("%.1f studs/s", delta.Magnitude))
	return true
end

-- Variation de vitesse imposée par un objet (Tromblon, Rayon Satellite, Méga Burger, éclair...). Une balle
-- poussée qui tombe dans un danger n'est pas pénalisée (Hazards.WaiveForExternalImpulse).
function BallService.ApplyBallImpulse(player: Player, velocity: Vector3, source: string?): boolean
	local data = balls[player]
	if not data then
		return false
	end
	return applyImpulseTo(data, velocity, source)
end

local function thaw(data: BallData)
	if data.removed or data.state ~= "Frozen" then
		return
	end
	local resume = data.frozenResume
	data.frozenThread = nil
	data.frozenUntil = 0
	data.frozenResume = nil
	if resume == "Moving" then
		data.maxSpeed = BALL.MaxSpeed
		release(data, Vector3.zero) -- la balle gelée en l'air retombe et s'arrête normalement
	else
		setState(data, "Resting")
	end
end

-- Gel de la balle (Boule Givrante) : immobile et injouable pendant `seconds` ; un nouveau gel prolonge.
function BallService.FreezeBall(player: Player, seconds: number): boolean
	local data = balls[player]
	if not data or data.removed or data.state == "Holed" then
		return false
	end
	local duration = Validate.clampNumber(seconds, 0, MAX_FREEZE_SECONDS, 0)
	if duration <= 0 then
		return false
	end
	if data.aiming then
		BallService.CancelAim(player, "ball_frozen")
	end
	if data.state ~= "Frozen" then
		data.frozenResume = if data.state == "Moving" then "Moving" else "Resting"
		immobilize(data, nil)
		setState(data, "Frozen")
	end
	data.frozenUntil = math.max(data.frozenUntil, now() + duration)
	unschedule(data.trove, data.frozenThread)
	data.frozenThread = schedule(data.trove, data.frozenUntil - now(), function()
		thaw(data)
	end)
	notifyKey(player, "golf.ball.frozen", { n = math.ceil(duration) })
	return true
end

-- Replace la balle à sa dernière position valide avec `penalty` coups (0..Hazards.MaxPenalty).
function BallService.ResetToLastValid(player: Player, reason: string?, penalty: number?): boolean
	local data = balls[player]
	if not data or data.removed or data.state == "Holed" then
		return false
	end
	if data.ball.Parent == nil then
		rebuildPlayerBall(data)
	end
	local why = if type(reason) == "string" and reason ~= "" then reason else "stuck"
	local amount = math.floor(Validate.clampNumber(penalty, 0, HAZARDS.MaxPenalty, 0))
	local effectAt = if HAZARD_KINDS[why] then data.ball.Position else nil
	resetBall(data, why, amount, effectAt, nil)
	return true
end

-- Frappe amplifiée en attente (Club Propulseur) : le prochain coup dans `seconds` s est multiplié (plafond
-- de vitesse relevé d'autant pour ce coup). Bornes : Shot.ShotBoostMaxMultiplier / Shot.ShotBoostMaxDuration.
function BallService.SetShotBoost(player: Player, multiplier: number, seconds: number?): boolean
	local data = balls[player]
	if not data or data.removed or data.state == "Holed" then
		return false
	end
	local value = Validate.clampNumber(multiplier, 1, SHOT.ShotBoostMaxMultiplier, 1)
	local duration = Validate.clampNumber(seconds, 0, SHOT.ShotBoostMaxDuration, SHOT.ShotBoostMaxDuration)
	if value <= 1 or duration <= 0 then
		clearBoost(data)
		return false
	end
	unschedule(data.trove, data.boostThread)
	data.boost = value
	data.boostUntil = now() + duration
	data.ball:SetAttribute("ShotBoost", value)
	data.boostThread = schedule(data.trove, duration, function()
		data.boostThread = nil
		if not data.removed and data.boost == value then
			clearBoost(data)
		end
	end)
	return true
end

function BallService.ClearShotBoost(player: Player)
	local data = balls[player]
	if data and not data.removed then
		clearBoost(data)
	end
end

--------------------------------------------------------------------------------
-- API publique : balles de simulation (outils de validation des trous)
--------------------------------------------------------------------------------

local function emptySimResult(position: Vector3): SimResult
	return {
		outcome = "Removed",
		position = position,
		start = position,
		hazard = nil,
		elapsed = 0,
		distance = 0,
		maxHeight = 0,
		surface = DEFAULT_SURFACE,
	}
end

local function simVelocity(shot: SimShot): (Vector3?, string)
	local shotType = BallMath.resolveShotType(shot.shotType, SHOT_TYPES, SHOT.DefaultType) or SHOT.DefaultType
	local imposed = shot.velocity
	if imposed ~= nil then
		if not Validate.isFiniteVector3(imposed) then
			return nil, shotType
		end
		return clampMagnitude(imposed, BALL.MaxSpeed), shotType
	end
	local direction = Validate.flatUnit(shot.direction)
	if not direction then
		return nil, shotType
	end
	local power = Validate.clampNumber(shot.power, 0, 1, 1)
	return BallMath.launchVelocity(direction, shot.loft, power, SHOT_TYPES[shotType]), shotType
end

-- Attend l'issue d'une balle de simulation (repos, trou, danger, blocage) ou le délai.
local function waitSim(data: BallData, limit: number): SimResult
	local signal = data.simDone
	if not signal then
		signal = SignalModule.new()
		data.simDone = signal
	end
	local thread = coroutine.running()
	local done = false
	local connection: Connection? = nil
	local timer: thread? = nil
	connection = (signal :: Signal):Once(function(result: SimResult)
		if done then
			return
		end
		done = true
		cancelThread(timer)
		task.spawn(thread, result)
	end)
	timer = task.delay(limit, function()
		if done then
			return
		end
		done = true
		if connection then
			connection:Disconnect()
		end
		task.spawn(thread, simResult(data, "Timeout", nil, nil))
	end)
	return coroutine.yield()
end

-- Balle sans propriétaire : mêmes règles physiques, ni coups, ni KO, ni signaux ; capture du trou en toute phase.
function BallService.CreateSimBall(position: Vector3 | CFrame, opts: SpawnOptions?): BasePart?
	local requested = toPosition(position)
	if not requested then
		Log.warn("Ball", "CreateSimBall : position invalide")
		return nil
	end
	local count = 0
	for _ in sims do
		count += 1
	end
	if count >= MAX_SIM_BALLS then
		Log.warn("Ball", "CreateSimBall : trop de balles de simulation (" .. count .. ")")
		return nil
	end
	local _, folder = ensureFolders()
	local target = if opts and opts.snap == false then requested else snapToGround(requested)
	simCounter += 1
	local ball, trail, force = buildBallInstance("SimBall_" .. simCounter, target, 0, false)
	local data = newData(nil, ball, trail, force, target, false, true)
	sims[ball] = data
	ball.Parent = folder
	refreshLie(data)
	return ball
end

-- Lance (si `shot` est fourni et la balle immobile) puis ATTEND l'issue de la balle de simulation.
-- Doit être appelé depuis un fil qui peut céder (outil de validation, DevBridge).
function BallService.StepSim(ball: BasePart, shot: SimShot?, timeout: number?): SimResult
	local data = sims[ball]
	if not data or data.removed then
		local at = if typeof(ball) == "Instance" and ball:IsA("BasePart") then ball.Position else Vector3.zero
		return emptySimResult(at)
	end
	if data.ball.Parent == nil then
		handleMissingInstance(data)
		return emptySimResult(data.lastValid)
	end
	if shot ~= nil and data.state == "Resting" then
		local velocity, shotType = simVelocity(shot)
		if velocity == nil then
			Log.warn("Ball", "StepSim : tir invalide")
			return simResult(data, "Resting", nil, nil)
		end
		local start = data.ball.Position
		local cup = getCup()
		data.simStart = start
		data.simMaxY = start.Y
		data.shotOrigin = start
		data.shotType = shotType
		data.shotFromDistance = if cup then BallMath.flatDistance(start, cup) else nil
		data.externalImpulse = false
		data.maxSpeed = BALL.MaxSpeed
		data.windEnabled = shot.wind == true
		data.ball.CFrame = data.ball.CFrame + Vector3.new(0, BALL.LiftOff, 0)
		release(data, velocity)
	end
	if data.state ~= "Moving" then
		return simResult(data, if data.state == "Holed" then "Holed" else "Resting", nil, nil)
	end
	return waitSim(data, Validate.clampNumber(timeout, 0.1, SIM_MAX_TIMEOUT, SIM_DEFAULT_TIMEOUT))
end

function BallService.RemoveSimBall(ball: BasePart)
	local data = sims[ball]
	if data then
		sims[ball] = nil
		destroyData(data)
	end
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

local function refreshHitFilter()
	if hitOverlap then
		hitOverlap.FilterDescendantsInstances = characterList
	end
end

local function addCharacter(character: Model)
	if table.find(characterList, character) == nil then
		table.insert(characterList, character)
		refreshHitFilter()
	end
end

local function removeCharacter(character: Model)
	local index = table.find(characterList, character)
	if index then
		table.remove(characterList, index)
		refreshHitFilter()
	end
end

local function setupPlayer(player: Player)
	if playerTroves[player] then
		return
	end
	local trove = TroveModule.new()
	playerTroves[player] = trove
	trove:Connect(player.CharacterAdded, function(character: Model)
		addCharacter(character)
	end)
	trove:Connect(player.CharacterRemoving, function(character: Model)
		removeCharacter(character)
		BallService.CancelAim(player, "respawn")
	end)
	if player.Character then
		addCharacter(player.Character)
	end
end

local function cleanupPlayer(player: Player)
	BallService.RemoveBall(player)
	if player.Character then
		removeCharacter(player.Character)
	end
	strokes[player] = nil
	guidedReadyAt[player] = nil
	swingTokens[player] = nil
	local trove = playerTroves[player]
	if trove then
		playerTroves[player] = nil
		trove:Destroy()
	end
	-- Aucune référence au joueur parti ne survit dans les autres balles.
	for _, data in balls do
		data.hitCooldowns[player] = nil
		local guided = data.guided
		if guided and guided.target == player then
			stopGuided(data)
		end
	end
end

-- Interactions entre balles : réglage d'hôte pendant une partie, valeur par défaut à l'accueil.
local function syncBallCollisions()
	if not COLLISION.SyncBallCollisionsWithSettings then
		return
	end
	local enabled = COLLISION.BallBallDefault
	if MATCH_PHASES[currentPhase()] then
		local settings = readSettings()
		if settings and type(settings.ballCollisions) == "boolean" then
			enabled = settings.ballCollisions
		end
	end
	CollisionService.SetBallCollisions(enabled)
end

local function onPhaseChanged()
	syncBallCollisions()
	local phase = currentPhase()
	for player, data in table.clone(balls) do
		if data.aiming and not phaseAllowsShot(data, phase) then
			BallService.CancelAim(player, "phase")
		end
	end
end

-- Studio : vérifie que les clés de traduction envoyées aux clients et les sons joués existent.
local function checkContent()
	local missing: { string } = {}
	local function checkKey(key: string)
		if not Locale.has(key, "fr") or not Locale.has(key, "en") then
			table.insert(missing, key)
		end
	end
	for _, reason in AIM_CANCEL_REASONS do
		checkKey("golf.aimCancelled." .. reason)
	end
	for _, reason in RESET_REASONS do
		checkKey("golf.reset." .. reason)
	end
	for _, key in NOTIFY_KEYS do
		checkKey(key)
	end
	if #missing > 0 then
		Log.warn("Ball", "textes manquants (Locale fr/en) :", table.concat(missing, ", "))
	end
	for _, name in SOUND_NAMES do
		if Sounds[name] == nil then
			Log.warn("Ball", "son absent de Config/Sounds :", name)
		end
	end
end

function BallService.Init()
	if initialized then
		return
	end
	initialized = true
	local trove = TroveModule.new()
	serviceTrove = trove
	getRandom()

	local solid = RaycastParams.new()
	solid.FilterType = Enum.RaycastFilterType.Exclude
	solid.IgnoreWater = true
	solid.RespectCanCollide = true
	local okGroup, groupError = pcall(function()
		-- Les requêtes « voient » exactement ce que heurte une balle (ni avatars, ni voiturettes, ni décor léger).
		solid.CollisionGroup = Config.CollisionGroups.Balls
	end)
	if not okGroup then
		Log.warn("Ball", "groupe de collision des requêtes non appliqué :", groupError)
	end
	solidParams = solid
	ensureFolders()
	refreshSolidFilter()

	local hits = OverlapParams.new()
	hits.FilterType = Enum.RaycastFilterType.Include
	hits.FilterDescendantsInstances = {}
	hitOverlap = hits

	-- Volumes dangereux balisés (Parts ou Models ; attribut Hazard = "water" | "oob" | "lava" | "void").
	Hazards.start(trove)

	trove:Connect(Players.PlayerAdded, setupPlayer)
	trove:Connect(Players.PlayerRemoving, cleanupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end

	-- Un joueur mis KO quitte immédiatement la visée.
	trove:Connect(CombatService.KnockedOut, function(victim: any)
		if isPlayer(victim) then
			BallService.CancelAim(victim, "stun")
		end
	end)

	trove:Add(GameState.changed("Phase", function()
		onPhaseChanged()
	end))
	trove:Add(GameState.changed("SettingsJson", function()
		settingsCacheValid = false
		syncBallCollisions()
	end))
	syncBallCollisions()

	Net.on("Golf.AimState", onAimState)
	Net.on("Golf.SwingStart", onSwingStart)
	Net.on("Golf.Shoot", onShoot)
	Net.on("Golf.ResetBall", onResetBall)

	if RunService:IsStudio() then
		checkContent()
	end
end

function BallService.Start()
	if started then
		return
	end
	started = true
	local trove = serviceTrove
	if not trove then
		trove = TroveModule.new()
		serviceTrove = trove
	end
	trove:Connect(RunService.Heartbeat, onHeartbeat)
end

return BallService
