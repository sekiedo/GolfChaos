--!strict
--[[
	Emotes : 13 émotes procédurales originales (accueils, célébrations, réactions, danses).

	Jouées par AnimationController quand EmoteService (serveur) pose les attributs de personnage
	EmoteStartedAt / Emote ; le temps de chaque émote part de EmoteStartedAt (heure serveur), si bien que
	tous les clients voient la même danse au même moment. Chaque émote est aussi un cosmétique de
	l'emplacement "Emote" portant le MÊME identifiant (Cosmetics/Catalog/Emotes.luau). Purement visuelles :
	aucun effet de jeu, aucun délai contourné.

	Repères et conventions des articulations : Library/Kit.luau (X = droite, Y = haut, Z = arrière ;
	épaule x > 0 = bras vers l'avant, genou x < 0 = flexion, cou/taille x > 0 = penché en arrière...).
	Les cibles de main (Kit.arm, Kit.arms, Kit.reach) sont exprimées dans le repère de l'UpperTorso.

	  id                    nom (fr)                  type
	  emote_wave            Grand coucou              ponctuelle 2,6 s
	  emote_golf_clap       Applaudissements polis    boucle 1,2 s
	  emote_fist_pump       Poing de la victoire      ponctuelle 2,3 s
	  emote_sprinkler       L'arroseur du green       boucle 2,4 s
	  emote_facepalm        Coup raté                 ponctuelle 2,8 s
	  emote_duck_waddle     Dandinement du canard     boucle 1 s
	  emote_noodle          Danse spaghetti           boucle 1,6 s
	  emote_caddie_bot      Caddie-robot              boucle 3,2 s (poses saccadées)
	  emote_champion_flex   Muscles de champion       boucle 3 s (étincelles dorées)
	  emote_bunker_tantrum  Colère du bunker          boucle 1 s (fumée de colère)
	  emote_flamingo        Flamant zen               boucle 5 s (lueurs ; perte d'équilibre comique)
	  emote_birdie_solo     Solo de birdie            boucle 1,6 s (air guitar, jingle « music »)
	  emote_royal_bow       Révérence royale          ponctuelle 3,2 s

	Étiquettes : "emote" (toutes), "music" (AnimationController joue le jingle emote_party au démarrage),
	"greeting" / "celebration" / "reaction" / "dance" (classement). calm = amplitude conservée en mode
	« effets réduits ». Les fonctions fx (client uniquement) créent des particules intégrées au moteur,
	détruites par AnimationController à l'arrêt de l'émote.
]]

local Kit = require(script.Parent.Kit)

type Pose = Kit.Pose

-- Même forme que Animations.AnimationDef (pas de require du registre : il charge cette bibliothèque).
type EmoteDef = {
	id: string,
	duration: number,
	looped: boolean,
	hold: boolean?,
	priority: number,
	blendIn: number,
	blendOut: number,
	calm: number?,
	joints: (t: number) -> Pose,
	fx: ((rig: Model) -> { Instance })?,
	tags: { string }?,
}

local R, YXZ = Kit.R, Kit.YXZ
local TAU = math.pi * 2

local PRIORITY = 20 -- sous le golf (50 à 70) et le combat (80 à 100)

--------------------------------------------------------------------------------
-- Outils communs
--------------------------------------------------------------------------------

-- Enveloppe appliquée à toute la pose : 0 = neutre, 1 = pose complète.
local function scaled(pose: Pose, amount: number): Pose
	if amount >= 1 then
		return pose
	end
	local alpha = math.max(amount, 0)
	local out: Pose = {}
	for name, cf in pose do
		out[name] = Kit.scale(cf, alpha)
	end
	return out
end

-- Jambes fléchies pieds à plat et bassin abaissé d'autant ; rotation et décalage facultatifs du bassin.
local function stance(pose: Pose, hip: number, knee: number, spread: number?, turn: number?, rootRotation: CFrame?, rootOffset: Vector3?)
	local drop = Kit.legs(pose, hip, knee, spread, turn)
	local offset = rootOffset or Vector3.zero
	pose.Root = CFrame.new(offset.X, offset.Y - drop, offset.Z) * (rootRotation or CFrame.identity)
end

local function colors(a: Color3, b: Color3): ColorSequence
	return ColorSequence.new(a, b)
end

--------------------------------------------------------------------------------
-- 1. Grand coucou : bras droit levé qui salue, main gauche sur la hanche, balancement
--------------------------------------------------------------------------------

local waveRaise = Kit.curve({ { 0, 0 }, { 0.35, 1 }, { 2.15, 1 }, { 2.6, 0 } }, "sine")
-- Bras levé vers le haut et l'extérieur ; l'avant-bras se replie vers l'intérieur (plan frontal).
local WAVE_UPPER = Kit.armFrame(Vector3.new(0.75, 0.62, -0.18), Vector3.new(-0.62, 0.75, 0))
local HIP_TARGET_L = Vector3.new(-1.0, -1.05, -0.05)
local HIP_POLE_L = Vector3.new(-1, 0.1, 0.5) -- coude vers l'extérieur et l'arrière

local function waveJoints(t: number): Pose
	local pose: Pose = {}
	local sway = Kit.wave(t, 1.3)
	local flick = Kit.wave(t, 0.42) -- va-et-vient rapide de l'avant-bras
	stance(pose, 4, -8, 3, 0, R(0, 0, 3 * sway))
	pose.Waist = R(2, -8, 4 + 3 * sway)
	pose.Neck = R(4, 6, -6 - 2 * sway)
	pose.RightShoulder = WAVE_UPPER
	pose.RightElbow = R(40 + 18 * flick)
	pose.RightWrist = R(18 * flick)
	Kit.arm(pose, "L", HIP_TARGET_L, HIP_POLE_L)
	pose.LeftWrist = R(0, 0, -15)
	return scaled(pose, waveRaise(t))
end

--------------------------------------------------------------------------------
-- 2. Applaudissements polis : petits claps à hauteur du menton, hochements approbateurs
--------------------------------------------------------------------------------

local CLAP_CENTER = Vector3.new(0, 0.05, -0.88)
local CLAP_POLE_L = Vector3.new(-0.8, -1, 0.2)
local CLAP_POLE_R = Vector3.new(0.8, -1, 0.2)
local CLAP_PERIOD = 0.4 -- trois claps par cycle de 1,2 s

local function golfClapJoints(t: number): Pose
	local pose: Pose = {}
	local beat = (t % CLAP_PERIOD) / CLAP_PERIOD
	local gap = 0.08 + 0.2 * math.sin(math.pi * beat) -- mains jointes au début de chaque temps
	local cycle = Kit.wave(t, 1.2)
	stance(pose, 3, -6, 2, 0, R(0, 4 * cycle, 0))
	pose.Waist = R(3, 6 * cycle, 0)
	pose.Neck = R(-5 + 3 * math.sin(TAU * beat), -4 * cycle, 4)
	Kit.arms(pose, CLAP_CENTER + Vector3.new(-gap, 0, 0), CLAP_CENTER + Vector3.new(gap, 0, 0), CLAP_POLE_L, CLAP_POLE_R)
	return pose
end

--------------------------------------------------------------------------------
-- 3. Poing de la victoire : deux « YES ! » du poing, élan, petit saut bras en V
--------------------------------------------------------------------------------

local PUMP_UP: Pose = {}
do
	stance(PUMP_UP, 10, -20, 6, 0)
	PUMP_UP.Waist = R(8, 10, 0)
	PUMP_UP.Neck = R(4, -6, 0)
	PUMP_UP.RightShoulder = Kit.armFrame(Vector3.new(1, 0.25, 0.05), Vector3.new(0, 1, 0))
	PUMP_UP.RightElbow = R(105)
	PUMP_UP.LeftShoulder = R(15, 0, -8)
	PUMP_UP.LeftElbow = R(30)
end

local PUMP_DOWN: Pose = {}
do
	stance(PUMP_DOWN, 18, -36, 6, 0)
	PUMP_DOWN.Waist = R(-14, -10, 0)
	PUMP_DOWN.Neck = R(-12, 0, 0)
	PUMP_DOWN.RightShoulder = Kit.armFrame(Vector3.new(0.3, -0.85, 0.4), Vector3.new(0, 0.4, -1))
	PUMP_DOWN.RightElbow = R(95)
	PUMP_DOWN.LeftShoulder = R(-20, 0, -10)
	PUMP_DOWN.LeftElbow = R(25)
end

local PUMP_CROUCH: Pose = {}
do
	stance(PUMP_CROUCH, 30, -60, 8, 0)
	PUMP_CROUCH.Waist = R(-20, 0, 0)
	PUMP_CROUCH.Neck = R(12, 0, 0)
	PUMP_CROUCH.LeftShoulder = R(-35, 0, -10)
	PUMP_CROUCH.RightShoulder = R(-35, 0, 10)
	PUMP_CROUCH.LeftElbow = R(20)
	PUMP_CROUCH.RightElbow = R(20)
end

-- Bras en V ; `lift` décolle le bassin (saut), `knee` fléchit les jambes à l'atterrissage.
local function victoryPose(lift: number, knee: number, pointed: boolean): Pose
	local pose: Pose = {}
	stance(pose, -knee * 0.5, knee, 6, 0, nil, Vector3.new(0, lift, 0))
	if pointed then
		pose.LeftAnkle = R(-25)
		pose.RightAnkle = R(-25)
	end
	pose.Waist = R(10, 0, 0)
	pose.Neck = R(14, 0, 0)
	pose.RightShoulder = Kit.armFrame(Vector3.new(0.55, 0.85, -0.05), Vector3.new(-0.6, 0.4, -0.2))
	pose.LeftShoulder = Kit.armFrame(Vector3.new(-0.55, 0.85, -0.05), Vector3.new(0.6, 0.4, -0.2))
	pose.RightElbow = R(20)
	pose.LeftElbow = R(20)
	return pose
end

local fistPumpJoints = Kit.keyframes({
	duration = 2.3,
	looped = false,
	keys = {
		{ time = 0, pose = {} },
		{ time = 0.25, pose = PUMP_UP, ease = "outQuad" },
		{ time = 0.45, pose = PUMP_DOWN, ease = "inCubic" },
		{ time = 0.65, pose = PUMP_UP, ease = "outQuad" },
		{ time = 0.85, pose = PUMP_DOWN, ease = "inCubic" },
		{ time = 1.1, pose = PUMP_CROUCH, ease = "sine" },
		{ time = 1.32, pose = victoryPose(0.55, -4, true), ease = "outQuad" },
		{ time = 1.55, pose = victoryPose(0, -26, false), ease = "inQuad" },
		{ time = 1.95, pose = victoryPose(0, -8, false), ease = "sine" },
		{ time = 2.3, pose = {}, ease = "sine" },
	},
})

--------------------------------------------------------------------------------
-- 4. L'arroseur du green : main derrière la tête, bras tendu qui balaie par à-coups
--------------------------------------------------------------------------------

local SPRINKLER_TICKS = 8
local SPRINKLER_TICK = 0.2
local SPRINKLER_SWEEP = SPRINKLER_TICKS * SPRINKLER_TICK -- 1,6 s de balayage saccadé
local SPRINKLER_PERIOD = 2.4 -- puis 0,8 s de retour rapide
local SPRINKLER_SPAN = 40 -- degrés de chaque côté
local HEAD_BACK_TARGET_L = Vector3.new(-0.15, 1.35, 0.55)
local HEAD_BACK_POLE_L = Vector3.new(-1, 0.7, 0.1)
local SPRINKLER_ARM = Kit.armFrame(Vector3.new(0.12, 0.05, -1), Vector3.new(0, 1, 0))

-- (orientation en degrés, creux des genoux 0..1) à l'instant t.
local function sprinklerPhase(t: number): (number, number)
	local time = t % SPRINKLER_PERIOD
	if time < SPRINKLER_SWEEP then
		local index = math.floor(time / SPRINKLER_TICK)
		local frac = (time - index * SPRINKLER_TICK) / SPRINKLER_TICK
		local snap = Kit.ease("snap", math.min(frac / 0.35, 1))
		local step = (index + snap) / SPRINKLER_TICKS
		local dip = math.sin(math.pi * math.min(frac / 0.5, 1))
		return SPRINKLER_SPAN - 2 * SPRINKLER_SPAN * step, dip
	end
	local alpha = (time - SPRINKLER_SWEEP) / (SPRINKLER_PERIOD - SPRINKLER_SWEEP)
	return -SPRINKLER_SPAN + 2 * SPRINKLER_SPAN * Kit.ease("sine", alpha), 0
end

local function sprinklerJoints(t: number): Pose
	local yaw, dip = sprinklerPhase(t)
	local pose: Pose = {}
	stance(pose, 8 + 5 * dip, -16 - 10 * dip, 5, 0, R(0, yaw * 0.35, 0))
	pose.Waist = R(2, yaw * 0.65, 0)
	pose.Neck = YXZ(-2, yaw * 0.15, 0)
	pose.RightShoulder = SPRINKLER_ARM
	pose.RightElbow = R(8)
	pose.RightWrist = R(-10 + 14 * dip)
	Kit.arm(pose, "L", HEAD_BACK_TARGET_L, HEAD_BACK_POLE_L)
	return pose
end

--------------------------------------------------------------------------------
-- 5. Coup raté : la main sur les yeux, la tête secouée, puis un grand soupir
--------------------------------------------------------------------------------

local facepalmRaise = Kit.curve({ { 0, 0 }, { 0.35, 1 }, { 2.2, 1 }, { 2.7, 0 } }, "sine")
local facepalmSlump = Kit.curve({ { 0, 0 }, { 0.5, 1 }, { 2.2, 1 }, { 2.8, 0 } }, "sine")
-- Paume devant les yeux, tête déjà baissée (cou -22°, buste -14°).
local FACE_SHOULDER, FACE_ELBOW = Kit.reach(Kit.SHOULDER_R, Vector3.new(0.05, 1.1, -0.9), Vector3.new(1, -0.6, -0.3))

local function facepalmJoints(t: number): Pose
	local raise = facepalmRaise(t)
	local slump = facepalmSlump(t)
	local shake = 12 * Kit.wave(t - 0.6, 0.7) * Kit.window(t, 0.6, 2.05, 0.25)
	local sigh = Kit.window(t, 2.1, 2.8, 0.2)
	local pose: Pose = {}
	stance(pose, 4, -4 - 10 * slump, 3, 0, nil, Vector3.new(0, -0.08 * slump - 0.05 * sigh, 0))
	pose.Waist = R(-14 * slump - 6 * sigh, 0, 0)
	pose.Neck = YXZ(-22 * raise + 10 * sigh, shake, 0)
	pose.RightShoulder = Kit.scale(FACE_SHOULDER, raise)
	pose.RightElbow = Kit.scale(FACE_ELBOW, raise)
	pose.RightWrist = R(-20 * raise)
	pose.LeftShoulder = R(4 * slump, 0, -4)
	pose.LeftElbow = R(10)
	return pose
end

--------------------------------------------------------------------------------
-- 6. Dandinement du canard : accroupi, ailes qui battent, tête qui picore, roulis
--------------------------------------------------------------------------------

local DUCK_HIP, DUCK_KNEE = 32, -58
local DUCK_WING_BEND_R = Vector3.new(-0.45, 0.5, -0.75) -- avant-bras replié vers la poitrine
local DUCK_WING_BEND_L = Vector3.new(0.45, 0.5, -0.75)

local function duckJoints(t: number): Pose
	local w = TAU * t -- période 1 s
	local s = math.sin(w)
	local liftL = math.max(0, s) -- pied gauche levé quand le corps bascule à droite
	local liftR = math.max(0, -s)
	local pose: Pose = {}
	pose.LeftHip = R(DUCK_HIP + 14 * liftL, 18, -10) -- pointes de pied vers l'extérieur
	pose.RightHip = R(DUCK_HIP + 14 * liftR, -18, 10)
	pose.LeftKnee = R(DUCK_KNEE - 22 * liftL)
	pose.RightKnee = R(DUCK_KNEE - 22 * liftR)
	pose.LeftAnkle = R(-(DUCK_HIP + DUCK_KNEE) + 8 * liftL, 0, 5)
	pose.RightAnkle = R(-(DUCK_HIP + DUCK_KNEE) + 8 * liftR, 0, -5)
	pose.Root = CFrame.new(0, -Kit.legDrop(DUCK_HIP, DUCK_KNEE) + 0.06 * math.abs(s), 0) * R(-6, 0, -10 * s)
	pose.Waist = R(-18, 0, 6 * s)
	local peck = math.sin(2 * w)
	pose.Neck = CFrame.new(0, 0, -0.12 * peck) * R(24 + 10 * peck, 0, -4 * s)
	local flap = 0.5 + 0.5 * math.sin(2 * w + 0.6)
	local a = math.rad(20 + 45 * flap)
	pose.RightShoulder = Kit.armFrame(Vector3.new(math.sin(a), -math.cos(a), 0.12), DUCK_WING_BEND_R)
	pose.LeftShoulder = Kit.armFrame(Vector3.new(-math.sin(a), -math.cos(a), 0.12), DUCK_WING_BEND_L)
	pose.RightElbow = R(135)
	pose.LeftElbow = R(135)
	pose.RightWrist = R(0, 0, -20)
	pose.LeftWrist = R(0, 0, 20)
	return pose
end

--------------------------------------------------------------------------------
-- 7. Danse spaghetti : ondulation qui court de l'épaule au poignet, hanches souples
--------------------------------------------------------------------------------

-- Bras « nouille » d'un côté (1 = droit, -1 = gauche) : l'onde se propage avec un retard par segment.
local function noodleArm(w: number, side: number, phase: number): (CFrame, CFrame, CFrame)
	local a = w + phase
	local shoulder = R(0, side * 20 * math.sin(a), side * (62 + 22 * math.sin(a)))
	local elbow = R(30 + 28 * math.sin(a - 0.9))
	local wrist = R(0, 0, side * 28 * math.sin(a - 1.8))
	return shoulder, elbow, wrist
end

local function noodleJoints(t: number): Pose
	local w = TAU * t / 1.6
	local s = math.sin(w)
	local liftL = math.max(0, s)
	local liftR = math.max(0, -s)
	local hipL, hipR = 7 + 10 * liftL, 7 + 10 * liftR
	local kneeL, kneeR = -14 - 22 * liftL, -14 - 22 * liftR
	local pose: Pose = {}
	pose.LeftHip = R(hipL, 0, -3)
	pose.RightHip = R(hipR, 0, 3)
	pose.LeftKnee = R(kneeL)
	pose.RightKnee = R(kneeR)
	pose.LeftAnkle = R(-(hipL + kneeL))
	pose.RightAnkle = R(-(hipR + kneeR))
	-- la jambe la plus tendue porte le corps : l'autre pied quitte le sol
	local drop = math.min(Kit.legDrop(hipL, kneeL), Kit.legDrop(hipR, kneeR))
	pose.Root = CFrame.new(0.18 * s, -drop - 0.04 * (1 + math.cos(2 * w)), 0) * R(0, 8 * s, -7 * s)
	pose.Waist = R(4 * math.cos(2 * w), -12 * s, 10 * math.sin(w + 0.7))
	pose.Neck = R(6 * math.cos(2 * w + 0.4), 10 * math.sin(w + 1.2), -14 * math.sin(w + 1.4))
	pose.RightShoulder, pose.RightElbow, pose.RightWrist = noodleArm(w, 1, 0)
	pose.LeftShoulder, pose.LeftElbow, pose.LeftWrist = noodleArm(w, -1, math.pi)
	return pose
end

--------------------------------------------------------------------------------
-- 8. Caddie-robot : enchaînement de poses mécaniques, arrivées sèches (adoucissement « snap »)
--------------------------------------------------------------------------------

local FORWARD = Vector3.new(0, 0, -1)
local UP = Vector3.new(0, 1, 0)
local DOWN = Vector3.new(0, -1, 0)

local function botPose(knee: number): Pose
	local pose: Pose = {}
	stance(pose, -knee * 0.5, knee, 4, 0)
	return pose
end

-- Bras à l'horizontale sur les côtés, avant-bras en équerre repliés vers `right` / `left`.
local function botArms(pose: Pose, right: Vector3, left: Vector3): Pose
	pose.RightShoulder = Kit.armFrame(Vector3.new(1, 0, 0), right)
	pose.LeftShoulder = Kit.armFrame(Vector3.new(-1, 0, 0), left)
	pose.RightElbow = R(90)
	pose.LeftElbow = R(90)
	return pose
end

-- Bras tendus devant (angle `pitch`), buste tourné de `yaw`.
local function botReach(knee: number, pitch: number, yaw: number, waistPitch: number, headTilt: number): Pose
	local pose = botPose(knee)
	pose.Waist = R(waistPitch, yaw, 0)
	pose.Neck = R(0, 0, headTilt)
	pose.RightShoulder = R(pitch, 0, 0)
	pose.LeftShoulder = R(pitch, 0, 0)
	pose.RightElbow = R(0)
	pose.LeftElbow = R(0)
	return pose
end

local BOT_SQUARE = botArms(botPose(-10), FORWARD, FORWARD)
local BOT_LOOK_LEFT = Kit.merge(BOT_SQUARE, { Neck = YXZ(0, 45, 0) })
local BOT_WAVE_A = Kit.merge(botArms(botPose(-10), UP, DOWN), { Neck = YXZ(0, 45, 0) })
local BOT_WAVE_B = Kit.merge(botArms(botPose(-10), DOWN, UP), { Neck = YXZ(0, -45, 0) })
local BOT_PUSH_RIGHT = botReach(-10, 90, -35, 0, 0)
local BOT_DUCK = botReach(-40, 60, -35, -10, 15)
local BOT_PUSH_LEFT = botReach(-10, 90, 35, 0, -15)
local BOT_RESET = Kit.merge(botArms(botPose(-6), FORWARD, FORWARD), {
	Root = CFrame.new(0, 0.08, 0),
	Neck = R(8, 0, 0),
})

local caddieBotJoints = Kit.keyframes({
	duration = 3.2,
	looped = true,
	keys = {
		{ time = 0, pose = BOT_SQUARE, ease = "snap" },
		{ time = 0.4, pose = BOT_LOOK_LEFT, ease = "snap" },
		{ time = 0.8, pose = BOT_WAVE_A, ease = "snap" },
		{ time = 1.2, pose = BOT_WAVE_B, ease = "snap" },
		{ time = 1.6, pose = BOT_PUSH_RIGHT, ease = "snap" },
		{ time = 2.0, pose = BOT_DUCK, ease = "snap" },
		{ time = 2.4, pose = BOT_PUSH_LEFT, ease = "snap" },
		{ time = 2.8, pose = BOT_RESET, ease = "snap" },
	},
})

--------------------------------------------------------------------------------
-- 9. Muscles de champion : double biceps, « crabe », pose de profil ; tremblement de l'effort
--------------------------------------------------------------------------------

local FLEX_BICEPS: Pose = {}
do
	stance(FLEX_BICEPS, 6, -12, 9, 10)
	FLEX_BICEPS.Waist = R(6, 0, 0)
	FLEX_BICEPS.Neck = R(6, 0, 0)
	FLEX_BICEPS.RightShoulder = Kit.armFrame(Vector3.new(1, 0.15, -0.05), Vector3.new(0, 1, -0.1))
	FLEX_BICEPS.LeftShoulder = Kit.armFrame(Vector3.new(-1, 0.15, -0.05), Vector3.new(0, 1, -0.1))
	FLEX_BICEPS.RightElbow = R(115)
	FLEX_BICEPS.LeftElbow = R(115)
end

local FLEX_CRAB: Pose = {}
do
	stance(FLEX_CRAB, 14, -28, 9, 10)
	FLEX_CRAB.Waist = R(-14, 0, 0)
	FLEX_CRAB.Neck = R(12, 0, 0)
	Kit.arms(
		FLEX_CRAB,
		Vector3.new(-0.28, -0.75, -0.8),
		Vector3.new(0.28, -0.75, -0.8),
		Vector3.new(-1, 0.4, 0.1),
		Vector3.new(1, 0.4, 0.1)
	)
end

local FLEX_SIDE: Pose = {}
do
	FLEX_SIDE.LeftHip = R(4, 10, -6)
	FLEX_SIDE.LeftKnee = R(-6)
	FLEX_SIDE.LeftAnkle = R(2)
	FLEX_SIDE.RightHip = R(18, 0, 4)
	FLEX_SIDE.RightKnee = R(-34)
	FLEX_SIDE.RightAnkle = R(-10) -- sur la pointe du pied
	FLEX_SIDE.Root = CFrame.new(0, -0.05, 0) * R(0, 15, 0)
	FLEX_SIDE.Waist = R(2, 22, 0)
	FLEX_SIDE.Neck = YXZ(4, -28, 0) -- regarde le public par-dessus l'épaule
	Kit.arms(
		FLEX_SIDE,
		Vector3.new(-0.6, -0.45, -0.95),
		Vector3.new(-0.42, -0.38, -0.88),
		Vector3.new(-1, -0.6, 0.2),
		Vector3.new(1, -0.3, 0.3)
	)
end

local flexKeys = Kit.keyframes({
	duration = 3,
	looped = true,
	keys = {
		{ time = 0, pose = FLEX_BICEPS, ease = "outBack" }, -- l'adoucissement sert au retour en boucle
		{ time = 0.7, pose = FLEX_BICEPS, ease = "linear" },
		{ time = 1.0, pose = FLEX_CRAB, ease = "outBack" },
		{ time = 1.7, pose = FLEX_CRAB, ease = "linear" },
		{ time = 2.0, pose = FLEX_SIDE, ease = "outBack" },
		{ time = 2.7, pose = FLEX_SIDE, ease = "linear" },
	},
})

local function flexJoints(t: number): Pose
	local pose = flexKeys(t)
	local shake = R(0.9 * Kit.wave(t, 0.1), 0, 0.9 * Kit.wave(t, 0.125))
	Kit.add(pose, "RightShoulder", shake)
	Kit.add(pose, "LeftShoulder", shake:Inverse())
	return pose
end

local GOLD = colors(Color3.fromRGB(255, 220, 100), Color3.fromRGB(255, 160, 40))

local function flexFx(rig: Model): { Instance }
	local torso = Kit.part(rig, "UpperTorso")
	if not torso then
		return {}
	end
	return {
		Kit.sparkles(torso, CFrame.new(0, 0.5, -0.4), {
			color = GOLD,
			size = 0.22,
			rate = 5,
			lifetime = 0.7,
			speed = 2.5,
			spread = 70,
			lightEmission = 0.6,
		}),
	}
end

--------------------------------------------------------------------------------
-- 10. Colère du bunker : piétinements, poings brandis qui tremblent, tête qui dit non, fumée
--------------------------------------------------------------------------------

local TANTRUM_HIP, TANTRUM_KNEE = 10, -18
local TANTRUM_ARM_R = Kit.armFrame(Vector3.new(0.6, 0.72, -0.2), Vector3.new(-0.55, 0.55, 0.3))
local TANTRUM_ARM_L = Kit.armFrame(Vector3.new(-0.6, 0.72, -0.2), Vector3.new(0.55, 0.55, 0.3))

local function tantrumJoints(t: number): Pose
	local w = TAU * t -- période 1 s
	local s = math.sin(w)
	-- racine carrée : la jambe monte vite, reste en l'air, puis frappe le sol d'un coup sec
	local liftL = math.sqrt(math.max(0, s))
	local liftR = math.sqrt(math.max(0, -s))
	local impact = (1 - math.abs(s)) ^ 6
	local hipL, kneeL = TANTRUM_HIP + 40 * liftL, TANTRUM_KNEE - 55 * liftL
	local hipR, kneeR = TANTRUM_HIP + 40 * liftR, TANTRUM_KNEE - 55 * liftR
	local pose: Pose = {}
	pose.LeftHip = R(hipL, 0, -4)
	pose.RightHip = R(hipR, 0, 4)
	pose.LeftKnee = R(kneeL)
	pose.RightKnee = R(kneeR)
	pose.LeftAnkle = R(-(hipL + kneeL))
	pose.RightAnkle = R(-(hipR + kneeR))
	pose.Root = CFrame.new(0, -Kit.legDrop(TANTRUM_HIP, TANTRUM_KNEE) - 0.08 * impact, 0) * R(-8, 0, 5 * s)
	pose.Waist = R(-12 - 4 * impact, 6 * math.sin(2 * w), 0)
	pose.Neck = YXZ(-8, 18 * math.sin(3 * w), 0)
	local shakeR = math.sin(4 * w)
	local shakeL = math.sin(4 * w + math.pi / 2)
	pose.RightShoulder = R(10 * shakeR, 0, 0) * TANTRUM_ARM_R
	pose.LeftShoulder = R(10 * shakeL, 0, 0) * TANTRUM_ARM_L
	pose.RightElbow = R(70 + 15 * shakeR)
	pose.LeftElbow = R(70 + 15 * shakeL)
	return pose
end

local function tantrumFx(rig: Model): { Instance }
	local head = Kit.part(rig, "Head")
	if not head then
		return {}
	end
	return {
		Kit.sparkles(head, CFrame.new(0, 0.7, 0), {
			texture = Kit.TEXTURES.smoke,
			color = colors(Color3.fromRGB(240, 240, 240), Color3.fromRGB(150, 150, 150)),
			size = 0.55,
			rate = 6,
			lifetime = 0.9,
			speed = 2.2,
			spread = 25,
			acceleration = Vector3.new(0, 2, 0),
			lightEmission = 0,
		}),
	}
end

--------------------------------------------------------------------------------
-- 11. Flamant zen : posture de l'arbre sur la jambe gauche, mains jointes ; perte d'équilibre comique
--------------------------------------------------------------------------------

local FLAMINGO_PERIOD = 5
local flamingoPanic = Kit.curve({ { 2.9, 0 }, { 3.2, 1 }, { 3.9, 1 }, { 4.5, 0 } }, "sine")
local ZEN_LS, ZEN_LE = Kit.reach(Kit.SHOULDER_L, Vector3.new(-0.07, 2.0, -0.15), Vector3.new(-1, 0.2, 0))
local ZEN_RS, ZEN_RE = Kit.reach(Kit.SHOULDER_R, Vector3.new(0.07, 2.0, -0.15), Vector3.new(1, 0.2, 0))
-- Cuisse droite ouverte vers l'avant et l'extérieur, tibia replié vers le genou gauche.
local FLAMINGO_THIGH = Kit.legFrame(Vector3.new(0.75, -0.45, -0.5), Vector3.new(-1, -0.1, 0.2))

local function flamingoJoints(t: number): Pose
	local time = t % FLAMINGO_PERIOD
	local panic = flamingoPanic(time)
	local wobble = 2.5 * Kit.wave(time, 2.5) * (1 - panic) + 9 * panic * Kit.wave(time, 0.9)
	local pose: Pose = {}
	pose.LeftHip = R(2, 0, 2)
	pose.LeftKnee = R(-6)
	pose.LeftAnkle = R(4, 0, -2)
	pose.RightHip = FLAMINGO_THIGH
	pose.RightKnee = R(-115)
	pose.RightAnkle = R(-20)
	pose.Root = CFrame.new(-0.18, -Kit.legDrop(2, -6), 0) * R(-4 * panic, 0, wobble)
	pose.Waist = R(-6 * panic, 0, -0.6 * wobble)
	pose.Neck = R(-4 + 12 * panic, 0, -0.3 * wobble)
	-- moulinets des bras pendant la perte d'équilibre (toujours du côté extérieur du corps)
	local a = TAU * time / 0.6
	local windR = Kit.point(Vector3.new(0.75 + 0.35 * math.cos(a), math.sin(a), -0.35))
	local windL = Kit.point(Vector3.new(-(0.75 + 0.35 * math.cos(a + math.pi)), math.sin(a + math.pi), -0.35))
	pose.RightShoulder = ZEN_RS:Lerp(windR, panic)
	pose.LeftShoulder = ZEN_LS:Lerp(windL, panic)
	pose.RightElbow = ZEN_RE:Lerp(R(10), panic)
	pose.LeftElbow = ZEN_LE:Lerp(R(10), panic)
	return pose
end

local function flamingoFx(rig: Model): { Instance }
	local head = Kit.part(rig, "Head")
	if not head then
		return {}
	end
	return {
		Kit.sparkles(head, CFrame.new(0, 1.1, 0), {
			texture = Kit.TEXTURES.glow,
			color = colors(Color3.fromRGB(180, 245, 225), Color3.fromRGB(150, 200, 255)),
			size = 0.35,
			rate = 3,
			lifetime = 1.4,
			speed = 0.6,
			spread = 40,
			acceleration = Vector3.new(0, 0.5, 0),
			lightEmission = 0.5,
		}),
	}
end

--------------------------------------------------------------------------------
-- 12. Solo de birdie : guitare imaginaire, fente rock, tête qui bat la mesure
--------------------------------------------------------------------------------

local GUITAR_POLE_L = Vector3.new(-0.2, -1, 0.3) -- coude gauche vers le bas (main sur le manche)
local GUITAR_POLE_R = Vector3.new(1, 0, 0.6) -- coude droit vers l'extérieur (main qui gratte)

local function birdieSoloJoints(t: number): Pose
	local w = TAU * t / 1.6
	local bob = 0.5 + 0.5 * math.cos(2 * w) -- deux temps par cycle
	local s = math.max(0, math.sin(w))
	local lean = s * s -- renversement rock une fois par cycle
	local hipL, kneeL = 22 + 6 * bob, -30 - 10 * bob
	local hipR, kneeR = -12, -14 - 6 * bob
	local pose: Pose = {}
	pose.LeftHip = R(hipL, 12, -8)
	pose.LeftKnee = R(kneeL)
	pose.LeftAnkle = R(-(hipL + kneeL))
	pose.RightHip = R(hipR, -8, 8)
	pose.RightKnee = R(kneeR)
	pose.RightAnkle = R(-(hipR + kneeR))
	local drop = 0.5 * (Kit.legDrop(hipL, kneeL) + Kit.legDrop(hipR, kneeR))
	pose.Root = CFrame.new(0, -drop - 0.05 * bob, 0) * R(0, 18, 0)
	pose.Waist = R(-8 + 20 * lean, -6, 0)
	pose.Neck = R(-6 - 16 * bob + 8 * lean, 0, 0)
	local fret = Vector3.new(-1.45 + 0.12 * math.sin(w), -0.15 + 0.05 * math.sin(2 * w), -0.75)
	local strum = Vector3.new(0.35, -0.75 + 0.18 * math.sin(4 * w), -0.6)
	Kit.arms(pose, fret, strum, GUITAR_POLE_L, GUITAR_POLE_R)
	pose.RightWrist = R(25 * math.sin(4 * w))
	return pose
end

local function birdieSoloFx(rig: Model): { Instance }
	local hand = Kit.part(rig, "RightHand")
	if not hand then
		return {}
	end
	return {
		Kit.sparkles(hand, CFrame.identity, {
			color = colors(Color3.fromRGB(110, 230, 255), Color3.fromRGB(255, 120, 220)),
			size = 0.2,
			rate = 8,
			lifetime = 0.6,
			speed = 3,
			spread = 50,
			lightEmission = 0.7,
		}),
	}
end

--------------------------------------------------------------------------------
-- 13. Révérence royale : grand geste du bras, pied en arrière, salut profond
--------------------------------------------------------------------------------

local BOW_FLOURISH: Pose = {
	Root = CFrame.new(0, -0.03, 0),
	Waist = R(6, 0, 0),
	Neck = YXZ(10, 10, 0),
	RightShoulder = Kit.armFrame(Vector3.new(0.75, 0.62, -0.25), Vector3.new(-0.3, 0.3, -0.9)),
	RightElbow = R(25),
	RightWrist = R(20),
	LeftShoulder = Kit.armFrame(Vector3.new(-0.85, -0.2, 0.45), Vector3.new(0.3, 0.2, 0.9)),
	LeftElbow = R(15),
	RightHip = R(-14, 0, 4),
	RightKnee = R(-10),
	RightAnkle = R(24),
	LeftHip = R(4, 0, -2),
	LeftKnee = R(-6),
	LeftAnkle = R(2),
}

local BOW_DEEP: Pose = {
	Root = CFrame.new(0, -0.14, 0),
	Waist = R(-52, 0, 0),
	Neck = R(-12, 0, 0),
	LeftShoulder = Kit.armFrame(Vector3.new(-0.6, -0.35, 0.72), Vector3.new(0.4, 0.4, 0.5)),
	LeftElbow = R(10),
	RightHip = R(-18, 0, 4),
	RightKnee = R(-22),
	RightAnkle = R(40),
	LeftHip = R(10, 0, -2),
	LeftKnee = R(-24),
	LeftAnkle = R(14),
}
Kit.arm(BOW_DEEP, "R", Vector3.new(0.25, -0.55, -0.7), Vector3.new(1, -0.3, 0.2)) -- main droite sur le ventre

local BOW_HOLD = Kit.merge(BOW_DEEP, { Waist = R(-56, 0, 0), Neck = R(-14, 0, 0) })

local royalBowJoints = Kit.keyframes({
	duration = 3.2,
	looped = false,
	keys = {
		{ time = 0, pose = {} },
		{ time = 0.55, pose = BOW_FLOURISH, ease = "outQuad" },
		{ time = 1.25, pose = BOW_DEEP, ease = "sine" },
		{ time = 2.3, pose = BOW_HOLD, ease = "linear" },
		{ time = 3.2, pose = {}, ease = "sine" },
	},
})

--------------------------------------------------------------------------------
-- Définitions
--------------------------------------------------------------------------------

local definitions: { EmoteDef } = {
	{
		id = "emote_wave",
		duration = 2.6,
		looped = false,
		priority = PRIORITY,
		blendIn = 0.15,
		blendOut = 0.3,
		calm = 0.8,
		joints = waveJoints,
		tags = { "emote", "greeting" },
	},
	{
		id = "emote_golf_clap",
		duration = 1.2,
		looped = true,
		priority = PRIORITY,
		blendIn = 0.25,
		blendOut = 0.3,
		calm = 0.9,
		joints = golfClapJoints,
		tags = { "emote", "reaction" },
	},
	{
		id = "emote_fist_pump",
		duration = 2.3,
		looped = false,
		priority = PRIORITY,
		blendIn = 0.1,
		blendOut = 0.3,
		calm = 0.65,
		joints = fistPumpJoints,
		tags = { "emote", "celebration" },
	},
	{
		id = "emote_sprinkler",
		duration = SPRINKLER_PERIOD,
		looped = true,
		priority = PRIORITY,
		blendIn = 0.25,
		blendOut = 0.3,
		calm = 0.7,
		joints = sprinklerJoints,
		tags = { "emote", "dance" },
	},
	{
		id = "emote_facepalm",
		duration = 2.8,
		looped = false,
		priority = PRIORITY,
		blendIn = 0.15,
		blendOut = 0.3,
		calm = 0.9,
		joints = facepalmJoints,
		tags = { "emote", "reaction" },
	},
	{
		id = "emote_duck_waddle",
		duration = 1,
		looped = true,
		priority = PRIORITY,
		blendIn = 0.3,
		blendOut = 0.3,
		calm = 0.6,
		joints = duckJoints,
		tags = { "emote", "dance" },
	},
	{
		id = "emote_noodle",
		duration = 1.6,
		looped = true,
		priority = PRIORITY,
		blendIn = 0.3,
		blendOut = 0.35,
		calm = 0.5,
		joints = noodleJoints,
		tags = { "emote", "dance" },
	},
	{
		id = "emote_caddie_bot",
		duration = 3.2,
		looped = true,
		priority = PRIORITY,
		blendIn = 0.2,
		blendOut = 0.3,
		calm = 0.7,
		joints = caddieBotJoints,
		tags = { "emote", "dance" },
	},
	{
		id = "emote_champion_flex",
		duration = 3,
		looped = true,
		priority = PRIORITY,
		blendIn = 0.2,
		blendOut = 0.3,
		calm = 0.7,
		joints = flexJoints,
		fx = flexFx,
		tags = { "emote", "celebration" },
	},
	{
		id = "emote_bunker_tantrum",
		duration = 1,
		looped = true,
		priority = PRIORITY,
		blendIn = 0.2,
		blendOut = 0.3,
		calm = 0.45,
		joints = tantrumJoints,
		fx = tantrumFx,
		tags = { "emote", "reaction" },
	},
	{
		id = "emote_flamingo",
		duration = FLAMINGO_PERIOD,
		looped = true,
		priority = PRIORITY,
		blendIn = 0.4,
		blendOut = 0.35,
		calm = 0.8,
		joints = flamingoJoints,
		fx = flamingoFx,
		tags = { "emote", "dance" },
	},
	{
		id = "emote_birdie_solo",
		duration = 1.6,
		looped = true,
		priority = PRIORITY,
		blendIn = 0.25,
		blendOut = 0.3,
		calm = 0.55,
		joints = birdieSoloJoints,
		fx = birdieSoloFx,
		tags = { "emote", "dance", "music" },
	},
	{
		id = "emote_royal_bow",
		duration = 3.2,
		looped = false,
		priority = PRIORITY,
		blendIn = 0.15,
		blendOut = 0.3,
		calm = 0.85,
		joints = royalBowJoints,
		tags = { "emote", "greeting" },
	},
}

return definitions
