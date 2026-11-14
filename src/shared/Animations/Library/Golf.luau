--!strict
--[[
	Golf : poses procédurales du golfeur DROITIER (adresse, armé en boucle, swing, chip, putt).

	Hypothèse de placement : pendant la visée, le personnage fait face à la balle et la cible est à SA GAUCHE
	(-X local). GolfAimController peut l'orienter ainsi : lookVector = directionDeVisée:Cross(Vector3.yAxis).
	Les deux mains suivent un ARC devant la poitrine (IK à deux segments, Kit.reach) : elles restent jointes
	sur le grip pendant tout le swing. Le club, soudé à la main droite, est réorienté vers la balle par
	AnimationController (champ club = true) quel que soit le sens de son attachement Grip.

	Aucune puissance n'est répliquée : l'armé (« Charging ») oscille entre demi et plein backswing, comme une
	jauge qui monte et descend. Les animations sont purement visuelles : le serveur décide de tout.
]]

local Kit = require(script.Parent.Kit)

type Pose = Kit.Pose

local R, YXZ = Kit.R, Kit.YXZ
local TAU = math.pi * 2

--------------------------------------------------------------------------------
-- Arc des mains (repère de l'UpperTorso)
--------------------------------------------------------------------------------

local ARC_CENTER = Kit.CLUB_PIVOT -- le manche prolonge « ARC_CENTER -> mains » (voir AnimationController)
local DIR_ADDRESS = Vector3.new(0.02, -1.1, -0.42)
local DIR_TOP = Vector3.new(0.85, 0.62, -0.2) -- mains au-dessus de l'épaule droite
local DIR_FINISH = Vector3.new(-0.85, 0.62, -0.2) -- mains au-dessus de l'épaule gauche
local UNIT_ADDRESS, UNIT_TOP, UNIT_FINISH = DIR_ADDRESS.Unit, DIR_TOP.Unit, DIR_FINISH.Unit
local RADIUS_ADDRESS = DIR_ADDRESS.Magnitude
local RADIUS_HIGH = 1.05
local GRIP_GAP = 0.17 -- main droite plus loin sur le manche que la main gauche

local POLE_L = Vector3.new(-0.35, -0.2, 1) -- coudes vers le corps à l'adresse
local POLE_R = Vector3.new(0.35, -0.2, 1)
local POLE_R_TOP = Vector3.new(0.35, -1, 0.25) -- coude droit vers le sol au sommet
local POLE_L_FINISH = Vector3.new(-0.35, -1, 0.25) -- coude gauche vers le sol au finish

-- p : -1 = finish, 0 = adresse, 1 = sommet du backswing (légers dépassements tolérés).
local function handPath(p: number): (Vector3, Vector3)
	local dir: Vector3
	local radius: number
	if p >= 0 then
		local a = math.min(p, 1.15)
		dir = Kit.slerp(UNIT_ADDRESS, UNIT_TOP, a)
		radius = RADIUS_ADDRESS + (RADIUS_HIGH - RADIUS_ADDRESS) * math.min(a, 1)
	else
		local a = math.min(-p, 1.15)
		dir = Kit.slerp(UNIT_ADDRESS, UNIT_FINISH, a)
		radius = RADIUS_ADDRESS + (RADIUS_HIGH - RADIUS_ADDRESS) * math.min(a, 1)
	end
	return ARC_CENTER + dir * radius, dir
end

local function poles(p: number): (Vector3, Vector3)
	if p >= 0 then
		return POLE_L, POLE_R:Lerp(POLE_R_TOP, math.clamp(p, 0, 1))
	end
	return POLE_L:Lerp(POLE_L_FINISH, math.clamp(-p, 0, 1)), POLE_R
end

--------------------------------------------------------------------------------
-- Pose de swing paramétrée
--------------------------------------------------------------------------------

type SwingParams = {
	p: number, -- position des mains sur l'arc
	waistX: number, -- inclinaison du buste (négatif = penché vers la balle)
	waistY: number, -- rotation des épaules (négatif = vers la droite, backswing)
	waistZ: number,
	rootY: number, -- rotation des hanches
	neckX: number,
	neckY: number, -- tête : compense la rotation pour garder les yeux sur la balle
	cock: number, -- armé des poignets
	kneeL: number,
	kneeR: number,
	heelR: number, -- 0..1 : talon droit levé (finish)
	kickL: number, -- genou gauche rentré vers la balle (backswing)
}

local HIP_FLEX = 10
local SPREAD = 5

local function addressParams(): SwingParams
	return {
		p = 0,
		waistX = -26,
		waistY = 0,
		waistZ = 0,
		rootY = 0,
		neckX = -14,
		neckY = 0,
		cock = 0,
		kneeL = -20,
		kneeR = -20,
		heelR = 0,
		kickL = 0,
	}
end

local function swingPose(s: SwingParams): Pose
	local pose: Pose = {}
	local dropL = Kit.legDrop(HIP_FLEX, s.kneeL)
	local dropR = Kit.legDrop(HIP_FLEX, s.kneeR)
	local drop = 0.7 * math.min(dropL, dropR) + 0.3 * math.max(dropL, dropR)
	pose.Root = CFrame.new(0, -drop, 0) * R(0, s.rootY, 0)
	pose.Waist = R(s.waistX, s.waistY, s.waistZ)
	pose.Neck = YXZ(s.neckX, s.neckY, 0)
	local left, dir = handPath(s.p)
	local poleL, poleR = poles(s.p)
	Kit.arms(pose, left, left + dir * GRIP_GAP, poleL, poleR)
	pose.RightWrist = R(s.cock, 0, 0)
	pose.LeftWrist = R(s.cock * 0.8, 0, 0)
	-- Contre-rotation des hanches : les pieds restent plantés pendant que le bassin tourne.
	pose.LeftHip = R(HIP_FLEX, -s.rootY, -SPREAD + s.kickL)
	pose.RightHip = R(HIP_FLEX - 6 * s.heelR, -s.rootY * (1 - 0.6 * s.heelR), SPREAD)
	pose.LeftKnee = R(s.kneeL, 0, 0)
	pose.RightKnee = R(s.kneeR, 0, 0)
	pose.LeftAnkle = R(-(HIP_FLEX + s.kneeL), 0, SPREAD * 0.5)
	pose.RightAnkle = R(-(HIP_FLEX + s.kneeR) * (1 - s.heelR), 0, -SPREAD * 0.5)
	return pose
end

-- Progression d'un swing : 0 = sommet, 1 = impact (descente accélérée), 2 = finish (décélération).
local function swingProgress(t: number, impactAt: number, finishAt: number): number
	if t <= 0 then
		return 0
	elseif t < impactAt then
		return Kit.ease("inQuad", t / impactAt)
	elseif t < finishAt then
		return 1 + Kit.ease("outQuad", (t - impactAt) / (finishAt - impactAt))
	end
	return 2
end

local function linear(keys: { { number } }): Kit.Curve
	return Kit.curve(keys, "linear")
end

--------------------------------------------------------------------------------
-- Coup plein
--------------------------------------------------------------------------------

local addressLook = Kit.curve({ { 1.7, 0 }, { 2.1, 1 }, { 2.5, 1 }, { 2.9, 0 } }, "sine")

local function addressJoints(t: number): Pose
	local time = t % 3.2
	local s = addressParams()
	local waggle = Kit.window(time, 0.1, 1.5, 0.3)
	s.p = 0.06 * Kit.wave(time, 0.7) * waggle
	s.cock = 6 * Kit.wave(time, 0.7) * waggle
	s.waistX = -26 + 1.2 * Kit.wave(time, 3.2)
	local look = addressLook(time) -- coup d'œil vers la cible (à gauche)
	s.neckY = 42 * look
	s.neckX = -14 + 8 * look
	return swingPose(s)
end

local function chargeJoints(t: number): Pose
	local b = 0.35 + 0.65 * (0.5 - 0.5 * math.cos(TAU * t / 1.6))
	local shake = math.max(0, (b - 0.85) / 0.15) * Kit.wave(t, 0.09)
	local s = addressParams()
	s.p = b + 0.012 * shake
	s.waistX = -26 + 6 * b
	s.waistY = -48 * b + 1.5 * shake
	s.waistZ = 3 * b
	s.rootY = -14 * b
	s.neckY = 55 * b
	s.cock = 35 * b
	s.kneeL = -20 - 6 * b
	s.kneeR = -20 + 6 * b
	s.kickL = 5 * b
	return swingPose(s)
end

local swingCurves = {
	p = linear({ { 0, 1 }, { 0.5, 0.5 }, { 1, 0 }, { 1.4, -0.45 }, { 2, -1 } }),
	waistX = linear({ { 0, -20 }, { 1, -24 }, { 1.4, -12 }, { 2, -2 } }),
	waistY = linear({ { 0, -48 }, { 0.5, -20 }, { 1, 12 }, { 1.4, 45 }, { 2, 62 } }),
	waistZ = linear({ { 0, 3 }, { 1, 0 }, { 2, -6 } }),
	rootY = linear({ { 0, -14 }, { 0.5, 5 }, { 1, 20 }, { 1.4, 32 }, { 2, 40 } }),
	neckX = linear({ { 0, -14 }, { 1, -14 }, { 1.5, -4 }, { 2, 4 } }),
	neckY = linear({ { 0, 55 }, { 0.5, 20 }, { 1, -30 }, { 1.4, -32 }, { 2, -12 } }),
	cock = linear({ { 0, 35 }, { 0.5, 28 }, { 1, 0 }, { 1.4, -10 }, { 2, 30 } }),
	kneeL = linear({ { 0, -26 }, { 1, -16 }, { 2, -8 } }),
	kneeR = linear({ { 0, -14 }, { 1, -24 }, { 2, -42 } }),
	heelR = linear({ { 0.8, 0 }, { 1.8, 1 } }),
	kickL = linear({ { 0, 5 }, { 1, 0 } }),
}

local chipCurves = {
	p = linear({ { 0, 0.5 }, { 1, 0 }, { 2, -0.5 } }),
	waistX = linear({ { 0, -25 }, { 1, -26 }, { 2, -14 } }),
	waistY = linear({ { 0, -20 }, { 1, 6 }, { 2, 32 } }),
	waistZ = linear({ { 0, 1 }, { 2, -3 } }),
	rootY = linear({ { 0, -4 }, { 1, 10 }, { 2, 22 } }),
	neckX = linear({ { 0, -14 }, { 1, -14 }, { 2, -6 } }),
	neckY = linear({ { 0, 22 }, { 1, -16 }, { 2, -28 } }),
	cock = linear({ { 0, 20 }, { 1, 0 }, { 2, 8 } }),
	kneeL = linear({ { 0, -23 }, { 2, -14 } }),
	kneeR = linear({ { 0, -21 }, { 2, -28 } }),
	heelR = linear({ { 1, 0 }, { 2, 0.35 } }),
	kickL = linear({ { 0, 2 }, { 1, 0 } }),
}

type SwingCurves = typeof(swingCurves)

local function curvedSwing(curves: SwingCurves, u: number, t: number, finishAt: number): Pose
	local s: SwingParams = {
		p = curves.p(u),
		waistX = curves.waistX(u),
		waistY = curves.waistY(u),
		waistZ = curves.waistZ(u),
		rootY = curves.rootY(u),
		neckX = curves.neckX(u),
		neckY = curves.neckY(u),
		cock = curves.cock(u),
		kneeL = curves.kneeL(u),
		kneeR = curves.kneeR(u),
		heelR = curves.heelR(u),
		kickL = curves.kickL(u),
	}
	if t > finishAt then
		-- maintien vivant du finish : respiration légère
		local alive = math.min(1, (t - finishAt) / 0.4)
		s.waistX += 0.8 * alive * Kit.wave(t - finishAt, 2.4)
		s.neckX += 1.5 * alive * Kit.wave(t - finishAt, 2.4, 0.25)
	end
	return swingPose(s)
end

local function swingJoints(t: number): Pose
	return curvedSwing(swingCurves, swingProgress(t, 0.2, 0.58), t, 0.58)
end

--------------------------------------------------------------------------------
-- Chip (demi-swing)
--------------------------------------------------------------------------------

local function chipChargeJoints(t: number): Pose
	local b = 0.18 + 0.32 * (0.5 - 0.5 * math.cos(TAU * t / 1.4))
	local s = addressParams()
	s.p = b
	s.waistX = -27 + 4 * b
	s.waistY = -40 * b
	s.waistZ = 2 * b
	s.rootY = -8 * b
	s.neckY = 45 * b
	s.cock = 40 * b
	s.kneeL = -22 - 3 * b
	s.kneeR = -22 + 3 * b
	s.kickL = 3 * b
	return swingPose(s)
end

local function chipJoints(t: number): Pose
	return curvedSwing(chipCurves :: any, swingProgress(t, 0.16, 0.45), t, 0.45)
end

--------------------------------------------------------------------------------
-- Putt (pendule des épaules, poignets bloqués)
--------------------------------------------------------------------------------

local PUTT_LEFT = Vector3.new(0, -0.62, -0.62)
local PUTT_GAP = Vector3.new(0.05, -0.14, -0.02)
local PUTT_POLE_L = Vector3.new(-0.9, -0.3, 0.8) -- coudes écartés
local PUTT_POLE_R = Vector3.new(0.9, -0.3, 0.8)
local PUTT_BACK = 0.42 -- amplitude maximale du retour (studs)

local function puttPose(x: number, neckX: number, neckY: number, breath: number): Pose
	local pose: Pose = {}
	local drop = Kit.legs(pose, 8, -14, 2, 0)
	pose.Root = CFrame.new(0, -drop, 0)
	pose.Waist = R(-34 + breath, 0, 6 * x / PUTT_BACK) -- bascule des épaules en pendule
	pose.Neck = YXZ(neckX, neckY, 0)
	local left = PUTT_LEFT + Vector3.new(x, 0.25 * x * x, 0)
	Kit.arms(pose, left, left + PUTT_GAP, PUTT_POLE_L, PUTT_POLE_R)
	pose.RightWrist = R(-20, 0, 0) -- manche du putter plus vertical
	pose.LeftWrist = R(-10, 0, 0)
	return pose
end

local puttAddressLook = Kit.curve({ { 1.4, 0 }, { 1.8, 1 }, { 2.2, 1 }, { 2.6, 0 } }, "sine")

local function puttAddressJoints(t: number): Pose
	local time = t % 3
	local x = 0.03 * Kit.wave(time, 0.9) * Kit.window(time, 0.1, 1.2, 0.2)
	local look = puttAddressLook(time)
	return puttPose(x, -22 + 10 * look, 40 * look, 1.2 * Kit.wave(time, 3))
end

local function puttChargeJoints(t: number): Pose
	local x = 0.12 + 0.3 * (0.5 - 0.5 * math.cos(TAU * t / 1.4))
	return puttPose(x, -22, 0, 0)
end

local puttStroke = Kit.curve({ { 0, PUTT_BACK }, { 0.32, -0.3 } }, "sine")
local puttWatch = Kit.curve({ { 0.4, 0 }, { 0.75, 1 } }, "sine")

local function puttJoints(t: number): Pose
	local look = puttWatch(t) -- suit la balle qui roule vers le trou (à gauche)
	local breath = if t > 0.9 then 0.8 * Kit.wave(t - 0.9, 2.4) else 0
	return puttPose(puttStroke(t), -22 + 6 * look, 38 * look, breath)
end

--------------------------------------------------------------------------------
-- Définitions
--------------------------------------------------------------------------------

return {
	{
		id = "golf_address",
		duration = 3.2,
		looped = true,
		priority = 50,
		blendIn = 0.25,
		blendOut = 0.25,
		club = true,
		joints = addressJoints,
		tags = { "golf" },
	},
	{
		id = "golf_charge",
		duration = 1.6,
		looped = true,
		priority = 60,
		blendIn = 0.18,
		blendOut = 0.15,
		club = true,
		joints = chargeJoints,
		tags = { "golf" },
	},
	{
		id = "golf_swing",
		duration = 1.0,
		looped = false,
		hold = true,
		priority = 70,
		blendIn = 0.06,
		blendOut = 0.3,
		club = true,
		joints = swingJoints,
		tags = { "golf" },
	},
	{
		id = "golf_chip_charge",
		duration = 1.4,
		looped = true,
		priority = 60,
		blendIn = 0.18,
		blendOut = 0.15,
		club = true,
		joints = chipChargeJoints,
		tags = { "golf" },
	},
	{
		id = "golf_chip",
		duration = 0.8,
		looped = false,
		hold = true,
		priority = 70,
		blendIn = 0.06,
		blendOut = 0.3,
		club = true,
		joints = chipJoints,
		tags = { "golf" },
	},
	{
		id = "golf_putt_address",
		duration = 3.0,
		looped = true,
		priority = 50,
		blendIn = 0.25,
		blendOut = 0.25,
		club = true,
		joints = puttAddressJoints,
		tags = { "golf", "putt" },
	},
	{
		id = "golf_putt_charge",
		duration = 1.4,
		looped = true,
		priority = 60,
		blendIn = 0.18,
		blendOut = 0.15,
		club = true,
		joints = puttChargeJoints,
		tags = { "golf", "putt" },
	},
	{
		id = "golf_putt",
		duration = 0.9,
		looped = false,
		hold = true,
		priority = 70,
		blendIn = 0.08,
		blendOut = 0.3,
		club = true,
		joints = puttJoints,
		tags = { "golf", "putt" },
	},
}
