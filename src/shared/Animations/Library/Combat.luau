--!strict
--[[
	Combat : poses procédurales du combat cartoon — frappe (revers du bras droit, club en main ou non),
	plongeon « superman », KO étourdi sur jambes en coton, puis relevé avec secouement de tête.
	Pilotées par l'attribut de personnage AnimState ("Punch" | "Dive" | "KO") posé par CombatService.
	Purement visuelles : la portée, le recul et la durée du KO sont décidés par le serveur.
]]

local Kit = require(script.Parent.Kit)

type Pose = Kit.Pose

local R, YXZ = Kit.R, Kit.YXZ
local TAU = math.pi * 2

--------------------------------------------------------------------------------
-- Frappe
--------------------------------------------------------------------------------

local function stance(pose: Pose, hip: number, knee: number, spread: number): number
	return Kit.legs(pose, hip, knee, spread, 0)
end

local punchWindup: Pose = {}
do
	local drop = stance(punchWindup, 12, -22, 4)
	punchWindup.Root = CFrame.new(0, -drop, 0) * R(0, -10, 0)
	punchWindup.Waist = R(-6, -38, 0)
	punchWindup.Neck = YXZ(0, 28, 0)
	punchWindup.RightShoulder = Kit.armFrame(Vector3.new(0.8, 0.1, 0.55), Vector3.new(0, 0.7, -0.7))
	punchWindup.RightElbow = R(75)
	punchWindup.LeftShoulder = Kit.armFrame(Vector3.new(-0.2, -0.55, -0.8), Vector3.new(0.5, 0.8, 0))
	punchWindup.LeftElbow = R(85)
end

local punchStrike: Pose = {}
do
	local drop = stance(punchStrike, 10, -18, 4)
	punchStrike.Root = CFrame.new(0, -drop, 0) * R(-4, 14, 0)
	punchStrike.Waist = R(-10, 42, 0)
	punchStrike.Neck = YXZ(-4, -34, 0)
	punchStrike.RightShoulder = Kit.armFrame(Vector3.new(-0.55, 0.05, -0.83), Vector3.new(-0.6, 0, 0.3))
	punchStrike.RightElbow = R(12)
	punchStrike.LeftShoulder = Kit.armFrame(Vector3.new(-0.35, -0.75, 0.55), Vector3.new(0, 0.3, -1))
	punchStrike.LeftElbow = R(40)
	punchStrike.RightHip = R(16, -10, 4)
	punchStrike.RightKnee = R(-26)
	punchStrike.LeftHip = R(6, -10, -4)
	punchStrike.LeftKnee = R(-10)
end

local punchOvershoot = Kit.merge(punchStrike, {
	Waist = R(-10, 50, 0),
	RightShoulder = Kit.armFrame(Vector3.new(-0.75, 0.05, -0.62), Vector3.new(-0.5, 0, 0.5)),
	RightElbow = R(18),
})

local punchJoints = Kit.keyframes({
	duration = 0.5,
	looped = false,
	keys = {
		{ time = 0, pose = {} },
		{ time = 0.12, pose = punchWindup, ease = "outQuad" },
		{ time = 0.22, pose = punchStrike, ease = "inCubic" },
		{ time = 0.3, pose = punchOvershoot, ease = "outQuad" },
		{ time = 0.5, pose = {}, ease = "sine" },
	},
})

--------------------------------------------------------------------------------
-- Plongeon
--------------------------------------------------------------------------------

local diveCrouch: Pose = {
	Root = CFrame.new(0, -0.38, 0) * R(-12, 0, 0),
	Waist = R(-15, 0, 0),
	Neck = R(12, 0, 0),
	LeftHip = R(45, 0, -4),
	RightHip = R(45, 0, 4),
	LeftKnee = R(-80),
	RightKnee = R(-80),
	LeftAnkle = R(35),
	RightAnkle = R(35),
	LeftShoulder = R(-40, 0, -10),
	RightShoulder = R(-40, 0, 10),
	LeftElbow = R(15),
	RightElbow = R(15),
}

local diveFlight: Pose = {
	Root = R(-78, 0, 0), -- corps presque horizontal autour du bassin
	Waist = R(6, 0, 0),
	Neck = R(40, 0, 0), -- regarde devant malgré le buste couché
	LeftShoulder = R(168, 0, -8), -- bras tendus au-dessus de la tête
	RightShoulder = R(168, 0, 8),
	LeftElbow = R(5),
	RightElbow = R(5),
	LeftHip = R(-8, 0, -6),
	RightHip = R(-8, 0, 6),
	LeftKnee = R(-12),
	RightKnee = R(-12),
	LeftAnkle = R(-35),
	RightAnkle = R(-35),
}

local diveKeys = Kit.keyframes({
	duration = 0.75,
	looped = false,
	keys = {
		{ time = 0, pose = diveCrouch },
		{ time = 0.16, pose = diveFlight, ease = "outQuad" },
	},
})

local function diveJoints(t: number): Pose
	local pose = diveKeys(t)
	if t > 0.16 then
		-- battements de jambes et bras qui frétillent pendant le vol
		local amount = math.min(1, (t - 0.16) / 0.2)
		local kick = 8 * amount * math.sin(TAU * t * 3)
		Kit.add(pose, "LeftHip", R(kick, 0, 0))
		Kit.add(pose, "RightHip", R(-kick, 0, 0))
		local wobble = 4 * amount * math.sin(TAU * t * 2.2)
		Kit.add(pose, "LeftShoulder", R(0, 0, -wobble))
		Kit.add(pose, "RightShoulder", R(0, 0, wobble))
	end
	return pose
end

--------------------------------------------------------------------------------
-- KO : étourdi, jambes en coton, tête qui tourne
--------------------------------------------------------------------------------

local KO_PERIOD = 1.6

local function koJoints(t: number): Pose
	local w = TAU * t / KO_PERIOD
	local pose: Pose = {}
	local hip = 24
	local buckle = 0.5 + 0.5 * math.sin(w * 2 + 1) -- les genoux flanchent deux fois par cycle
	local knee = -48 - 10 * buckle
	local drop = Kit.legDrop(hip, knee)
	pose.Root = CFrame.new(0, -drop, 0) * R(-8 + 4 * math.cos(w), 0, 6 * math.sin(w))
	pose.LeftHip = R(hip, 6, 7) -- genoux rentrés
	pose.RightHip = R(hip, -6, -7)
	pose.LeftKnee = R(knee, 0, -8)
	pose.RightKnee = R(knee, 0, 8)
	pose.LeftAnkle = R(-(hip + knee), 0, 0)
	pose.RightAnkle = R(-(hip + knee), 0, 0)
	pose.Waist = R(-24 + 6 * math.cos(w + 0.6), 0, 10 * math.sin(w + 0.6))
	pose.Neck = R(-10 + 12 * math.cos(w + 1.2), 0, 18 * math.sin(w + 1.2)) -- tête qui roule
	local swing = math.sin(w + 2)
	local sway = math.cos(w + 2)
	pose.LeftShoulder = R(12 + 14 * swing, 0, -6 - 8 * sway) -- bras ballants en retard
	pose.RightShoulder = R(12 - 14 * swing, 0, 6 + 8 * sway)
	pose.LeftElbow = R(18 + 6 * swing)
	pose.RightElbow = R(18 - 6 * swing)
	pose.LeftWrist = R(0, 0, 10 * swing)
	pose.RightWrist = R(0, 0, -10 * swing)
	return pose
end

--------------------------------------------------------------------------------
-- Relevé après un KO
--------------------------------------------------------------------------------

local koStart = koJoints(0)

local function standing(neck: CFrame, shake: number): Pose
	local pose: Pose = {
		Root = CFrame.new(0, -0.04, 0),
		Waist = R(-10, 0, 0),
		Neck = neck,
		LeftShoulder = R(8, 0, -4 - shake),
		RightShoulder = R(8, 0, 4 + shake),
		LeftElbow = R(20),
		RightElbow = R(20),
	}
	Kit.legs(pose, 8, -16, 2, 0)
	return pose
end

local getupJoints = Kit.keyframes({
	duration = 1,
	looped = false,
	keys = {
		{ time = 0, pose = koStart },
		{ time = 0.3, pose = standing(R(-12, 0, 8), 0), ease = "outQuad" },
		{ time = 0.42, pose = standing(YXZ(-6, 28, 0), 14), ease = "sine" },
		{ time = 0.54, pose = standing(YXZ(-6, -28, 0), -10), ease = "sine" },
		{ time = 0.66, pose = standing(YXZ(-6, 22, 0), 10), ease = "sine" },
		{ time = 0.78, pose = standing(YXZ(-4, -10, 0), 0), ease = "sine" },
		{ time = 1, pose = {}, ease = "sine" },
	},
})

--------------------------------------------------------------------------------
-- Définitions
--------------------------------------------------------------------------------

return {
	{
		id = "combat_punch",
		duration = 0.5,
		looped = false,
		priority = 80,
		blendIn = 0.05,
		blendOut = 0.15,
		joints = punchJoints,
		tags = { "combat" },
	},
	{
		id = "combat_dive",
		duration = 0.75,
		looped = false,
		hold = true,
		priority = 85,
		blendIn = 0.06,
		blendOut = 0.25,
		joints = diveJoints,
		tags = { "combat" },
	},
	{
		id = "combat_ko",
		duration = KO_PERIOD,
		looped = true,
		priority = 100,
		blendIn = 0.15,
		blendOut = 0.3,
		calm = 0.6,
		joints = koJoints,
		tags = { "combat" },
	},
	{
		id = "combat_getup",
		duration = 1,
		looped = false,
		priority = 95,
		blendIn = 0.08,
		blendOut = 0.25,
		joints = getupJoints,
		tags = { "combat" },
	},
}
