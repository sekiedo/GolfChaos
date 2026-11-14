--!strict
--[[
Ball.Types — types de BallService (extraits de BallService ; re-exportés par lui, donc sans changement pour les appelants).

Types publics : BallState, SpawnOptions, ShotInfo, HoledInfo, SimShot, SimOutcome, SimResult.
Types internes (BallData...) : exportés ici pour le service et ses modules voisins, hors API du service.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SignalModule = require(Shared.Util.Signal)
local TroveModule = require(Shared.Util.Trove)

type Signal = SignalModule.Signal
type Trove = TroveModule.Trove

--------------------------------------------------------------------------------
-- Types publics
--------------------------------------------------------------------------------

export type BallState = "Resting" | "Moving" | "Holed" | "Frozen"

export type SpawnOptions = {
	practice: boolean?, -- balle d'entraînement ; défaut : selon la phase (Ball.PracticePhases)
	snap: boolean?, -- pose au sol sous la position demandée (défaut true)
}

export type ShotInfo = {
	shotType: string,
	loft: number, -- degrés, borné au type
	power: number, -- puissance retenue par le serveur (0..1)
	speed: number, -- vitesse de lancement (studs/s)
	origin: Vector3, -- position de la balle au départ du coup
	direction: Vector3, -- direction horizontale unitaire
	fromDistance: number?, -- distance horizontale départ–trou (nil si aucun trou)
	forced: boolean, -- frappe forcée (ForceShot)
	reason: string?, -- motif de la frappe forcée ("horn"...)
	practice: boolean,
	boost: number, -- multiplicateur de frappe amplifiée appliqué (1 = aucun)
	targetUserId: number, -- cible du tir guidé (0 = aucune)
}

export type HoledInfo = {
	strokes: number, -- coups + pénalités du trou
	shotDistance: number, -- distance horizontale parcourue par le coup gagnant (0 si poussée extérieure)
	fromDistance: number, -- distance horizontale départ du coup gagnant–trou (0 si poussée extérieure)
	wasPutt: boolean,
	holeInOne: boolean,
	shotType: string,
	gimme: boolean, -- balle presque arrêtée tombée du bord
	external: boolean, -- balle poussée dans le trou par un tiers (objet) : pas de bonus de distance
	practice: boolean,
}

export type SimShot = {
	velocity: Vector3?, -- vitesse initiale imposée (prioritaire, plafonnée à Ball.MaxSpeed)
	direction: Vector3?, -- sinon : direction horizontale...
	loft: number?, -- ...angle (défaut : celui du type)...
	power: number?, -- ...puissance 0..1 (défaut 1)...
	shotType: string?, -- ...et type de frappe (défaut Shot.DefaultType)
	wind: boolean?, -- appliquer le vent courant (défaut false : résultat reproductible)
}

export type SimOutcome = "Resting" | "Holed" | "Hazard" | "Stuck" | "Timeout" | "Removed"

export type SimResult = {
	outcome: SimOutcome,
	position: Vector3, -- position finale (ou point d'entrée dans le danger)
	start: Vector3,
	hazard: string?, -- type de danger si outcome = "Hazard"
	elapsed: number, -- durée du mouvement (s)
	distance: number, -- distance horizontale départ–arrivée
	maxHeight: number, -- hauteur maximale atteinte au-dessus du départ
	surface: string, -- surface sous la balle à la fin
}

--------------------------------------------------------------------------------
-- Types internes
--------------------------------------------------------------------------------

export type ShotOptions = {
	forced: boolean,
	reason: string?,
	target: Player?,
}

export type GuidedState = {
	target: Player,
	startedAt: number,
	nextCheckAt: number,
	losLostAt: number?,
	airborne: boolean, -- la balle a quitté le sol au moins une fois depuis la frappe
}

export type BallData = {
	ball: BasePart,
	trove: Trove, -- durée de vie de la balle (instance, tween, délais)
	owner: Player?, -- nil pour une balle de simulation
	userId: number,
	sim: boolean,
	practice: boolean,
	practiceExplicit: boolean, -- type demandé explicitement à la création
	removed: boolean,
	state: BallState,
	trail: Trail?,
	gravityForce: VectorForce,
	-- visée
	aiming: boolean,
	swingStartAt: number?, -- heure serveur de Golf.SwingStart (jauge en cours)
	aimBlockedUntil: number,
	lastShotAt: number,
	-- mouvement
	moveStartAt: number,
	lastPosition: Vector3, -- position au Heartbeat précédent (balayage, trou)
	restTimer: number,
	gimmeTimer: number,
	stuckAnchor: Vector3,
	stuckTimer: number,
	hazardTimer: number,
	grounded: boolean,
	groundNormal: Vector3,
	surface: string,
	maxSpeed: number,
	hitCooldowns: { [Player]: number },
	lipOutUntil: number,
	landingFxAt: number,
	externalImpulse: boolean, -- mouvement courant causé par un tiers (dispense de pénalité de danger)
	windEnabled: boolean,
	-- positions de référence
	lastValid: Vector3,
	shotOrigin: Vector3,
	shotType: string,
	shotFromDistance: number?,
	-- états temporaires
	frozenUntil: number,
	frozenResume: BallState?,
	frozenThread: thread?,
	boost: number,
	boostUntil: number,
	boostThread: thread?,
	sinkTween: Tween?,
	guided: GuidedState?,
	-- simulation
	simDone: Signal?,
	simStart: Vector3,
	simMaxY: number,
	errors: number,
}

return {}
