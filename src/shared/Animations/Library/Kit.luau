--!strict
--[[
	Kit : boîte à outils des animations procédurales (calcul pur, aucune instance créée sauf dans Kit.sparkles,
	appelé uniquement par les fonctions fx côté client). Ce module n'est PAS une bibliothèque d'animations :
	le registre (Animations/init.luau) l'ignore lors du chargement.

	REPÈRE DES ARTICULATIONS (rig R15, attachements de rig non tournés) : la Transform d'une articulation
	s'exprime dans le repère de la pièce PARENTE, centrée sur le pivot : X = droite du personnage, Y = haut,
	Z = arrière (le personnage regarde vers -Z). Conventions (degrés, Kit.R(x, y, z) = CFrame.Angles) :
	  épaule / hanche   x > 0 : le membre part vers l'avant
	  RightShoulder z > 0 / LeftShoulder z < 0 : bras écarté sur le côté (hanches : idem pour les jambes)
	  coude             x > 0 : flexion (l'avant-bras remonte vers l'avant)
	  genou             x < 0 : flexion (le tibia part vers l'arrière)
	  cheville          x > 0 : pointe du pied relevée ; x < 0 : sur la pointe
	  cou / taille / racine   x > 0 : penché en arrière ; y > 0 : tourné vers la gauche ; z > 0 : incliné à gauche
	Les cibles de main (Kit.reach / Kit.arms) sont exprimées dans le repère de l'UpperTorso (origine en son centre).
]]

local Kit = {}

export type Pose = { [string]: CFrame }
export type Key = { time: number, pose: Pose, ease: string? }
export type KeyframeSpec = { duration: number, looped: boolean, keys: { Key } }
export type CurveKey = { number } -- { temps, valeur } ; l'adoucissement se choisit par courbe
export type Curve = (number) -> number

local IDENTITY = CFrame.identity
local rad = math.rad
local TAU = math.pi * 2

Kit.IDENTITY = IDENTITY

-- Liste officielle des articulations animables (noms R15 des Motor6D / AnimationConstraint).
Kit.JOINTS = {
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
	"RightHip",
	"RightKnee",
	"RightAnkle",
}

-- Proportions approximatives du rig R15 par défaut (échelle 1). Les poses restent lisibles même si le
-- rig réel diffère de 10 à 20 % : seules les cibles de main en dépendent.
Kit.SHOULDER_L = Vector3.new(-1.15, 0.55, 0)
Kit.SHOULDER_R = Vector3.new(1.15, 0.55, 0)
Kit.ARM_UPPER = 0.95 -- pivot d'épaule -> pivot de coude
Kit.ARM_LOWER = 1.1 -- pivot de coude -> prise de la main
Kit.THIGH = 0.95 -- hanche -> genou
Kit.SHIN = 0.9 -- genou -> cheville

--------------------------------------------------------------------------------
-- Rotations
--------------------------------------------------------------------------------

-- Rotation en degrés (ordre CFrame.Angles : le Y tourne autour de l'axe déjà incliné par X).
function Kit.R(x: number?, y: number?, z: number?): CFrame
	return CFrame.Angles(rad(x or 0), rad(y or 0), rad(z or 0))
end

-- Rotation en degrés, lacet d'abord autour de l'axe vertical du parent (pratique pour la tête).
function Kit.YXZ(x: number?, y: number?, z: number?): CFrame
	return CFrame.fromEulerAnglesYXZ(rad(x or 0), rad(y or 0), rad(z or 0))
end

-- Translation (studs) puis rotation (degrés).
function Kit.T(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	return CFrame.new(x, y, z) * Kit.R(rx, ry, rz)
end

local function perpendicular(v: Vector3): Vector3
	local other = if math.abs(v.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	return v:Cross(other).Unit
end

-- Rotation la plus courte qui amène la direction `from` sur `to`.
function Kit.between(from: Vector3, to: Vector3): CFrame
	if from.Magnitude < 1e-6 or to.Magnitude < 1e-6 then
		return IDENTITY
	end
	local a, b = from.Unit, to.Unit
	local dot = math.clamp(a:Dot(b), -1, 1)
	if dot > 0.999999 then
		return IDENTITY
	end
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-6 then
		return CFrame.fromAxisAngle(perpendicular(a), math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

-- Oriente un membre (repos le long de -Y) vers `dir`, puis le vrille de `twist` degrés autour de son axe.
function Kit.point(dir: Vector3, twist: number?): CFrame
	local rotation = Kit.between(Vector3.new(0, -1, 0), dir)
	if twist and twist ~= 0 then
		rotation *= CFrame.Angles(0, rad(twist), 0)
	end
	return rotation
end

local function frame(dir: Vector3, bend: Vector3, armLike: boolean): CFrame
	if dir.Magnitude < 1e-6 then
		return IDENTITY
	end
	local d = dir.Unit
	local y = -d
	local projected = bend - d * bend:Dot(d)
	if projected.Magnitude < 1e-4 then
		projected = perpendicular(d)
	end
	local z = if armLike then -projected.Unit else projected.Unit
	local x = y:Cross(z)
	return CFrame.fromMatrix(Vector3.zero, x, y, z)
end

-- Repère de bras : le bras pointe vers `dir` et l'avant-bras se replie vers `bend` (flexion du coude en +X).
function Kit.armFrame(dir: Vector3, bend: Vector3): CFrame
	return frame(dir, bend, true)
end

-- Repère de jambe : la cuisse pointe vers `dir` et le tibia se replie vers `bend` (flexion du genou en -X).
function Kit.legFrame(dir: Vector3, bend: Vector3): CFrame
	return frame(dir, bend, false)
end

-- IK à deux segments : (rotation d'épaule, rotation de coude) amenant la prise de la main sur `target`
-- (repère de l'UpperTorso). `pole` = direction vers laquelle pointe le coude.
function Kit.reach(shoulder: Vector3, target: Vector3, pole: Vector3): (CFrame, CFrame)
	local upper, lower = Kit.ARM_UPPER, Kit.ARM_LOWER
	local offset = target - shoulder
	local distance = offset.Magnitude
	if distance < 1e-4 then
		return IDENTITY, IDENTITY
	end
	local dir = offset / distance
	distance = math.clamp(distance, math.abs(upper - lower) + 0.05, upper + lower - 0.002)
	local along = (upper * upper - lower * lower + distance * distance) / (2 * distance)
	local height = math.sqrt(math.max(0, upper * upper - along * along))
	local side = pole - dir * pole:Dot(dir)
	if side.Magnitude < 1e-4 then
		side = perpendicular(dir)
	end
	side = side.Unit
	local elbow = dir * along + side * height
	local upperDir = elbow.Unit
	local lowerDir = (dir * distance - elbow).Unit
	local bendDir = lowerDir - upperDir * lowerDir:Dot(upperDir)
	if bendDir.Magnitude < 1e-3 then
		bendDir = -side -- bras tendu : l'avant-bras se replierait à l'opposé du coude
	end
	local shoulderCF = Kit.armFrame(upperDir, bendDir)
	local bend = math.acos(math.clamp(upperDir:Dot(lowerDir), -1, 1))
	return shoulderCF, CFrame.Angles(bend, 0, 0)
end

-- Pose les deux bras par IK (cibles et pôles dans le repère de l'UpperTorso).
function Kit.arms(pose: Pose, targetL: Vector3, targetR: Vector3, poleL: Vector3, poleR: Vector3)
	pose.LeftShoulder, pose.LeftElbow = Kit.reach(Kit.SHOULDER_L, targetL, poleL)
	pose.RightShoulder, pose.RightElbow = Kit.reach(Kit.SHOULDER_R, targetR, poleR)
end

-- Un seul bras par IK.
function Kit.arm(pose: Pose, side: "L" | "R", target: Vector3, pole: Vector3)
	if side == "L" then
		pose.LeftShoulder, pose.LeftElbow = Kit.reach(Kit.SHOULDER_L, target, pole)
	else
		pose.RightShoulder, pose.RightElbow = Kit.reach(Kit.SHOULDER_R, target, pole)
	end
end

-- Abaissement du bassin (studs) qui garde les pieds au sol pour une cuisse inclinée de `hip` degrés vers
-- l'avant et un genou plié de `knee` degrés (négatif).
function Kit.legDrop(hip: number, knee: number): number
	return Kit.THIGH * (1 - math.cos(rad(hip))) + Kit.SHIN * (1 - math.cos(rad(hip + knee)))
end

-- Jambes fléchies symétriques, pieds à plat. `spread` écarte les pieds (degrés), `turn` oriente les pointes.
-- Retourne l'abaissement de bassin conseillé (à mettre dans Root).
function Kit.legs(pose: Pose, hip: number, knee: number, spread: number?, turn: number?): number
	local s = spread or 0
	local tw = turn or 0
	pose.LeftHip = Kit.R(hip, tw, -s)
	pose.RightHip = Kit.R(hip, -tw, s)
	pose.LeftKnee = Kit.R(knee, 0, 0)
	pose.RightKnee = Kit.R(knee, 0, 0)
	pose.LeftAnkle = Kit.R(-(hip + knee), 0, s * 0.5)
	pose.RightAnkle = Kit.R(-(hip + knee), 0, -s * 0.5)
	return Kit.legDrop(hip, knee)
end

--------------------------------------------------------------------------------
-- Poses
--------------------------------------------------------------------------------

-- Symétrie gauche/droite d'une CFrame (plan YZ) : x -> -x.
function Kit.mirrorCF(cf: CFrame): CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return CFrame.new(-x, y, z, r00, -r01, -r02, -r10, r11, r12, -r20, r21, r22)
end

-- Pose miroir : échange gauche/droite et symétrise chaque rotation.
function Kit.mirror(pose: Pose): Pose
	local out: Pose = {}
	for name, cf in pose do
		local target = name
		if string.sub(name, 1, 4) == "Left" then
			target = "Right" .. string.sub(name, 5)
		elseif string.sub(name, 1, 5) == "Right" then
			target = "Left" .. string.sub(name, 6)
		end
		out[target] = Kit.mirrorCF(cf)
	end
	return out
end

-- Copie de `base` dont les articulations de `over` sont remplacées.
function Kit.merge(base: Pose, over: Pose?): Pose
	local out = table.clone(base)
	if over then
		for name, cf in over do
			out[name] = cf
		end
	end
	return out
end

-- Mélange articulation par articulation (une articulation absente vaut l'identité).
function Kit.blend(a: Pose, b: Pose, alpha: number): Pose
	if alpha <= 0 then
		return table.clone(a)
	elseif alpha >= 1 then
		return table.clone(b)
	end
	local out: Pose = {}
	for name, cf in a do
		out[name] = cf:Lerp(b[name] or IDENTITY, alpha)
	end
	for name, cf in b do
		if out[name] == nil then
			out[name] = IDENTITY:Lerp(cf, alpha)
		end
	end
	return out
end

-- Ajoute une rotation (ou CFrame) relative à une articulation : pose[joint] = extra * pose[joint].
function Kit.add(pose: Pose, joint: string, extra: CFrame)
	pose[joint] = extra * (pose[joint] or IDENTITY)
end

-- Réduit l'amplitude d'une CFrame (0 = identité, 1 = inchangée).
function Kit.scale(cf: CFrame, amount: number): CFrame
	return IDENTITY:Lerp(cf, amount)
end

--------------------------------------------------------------------------------
-- Temps et courbes
--------------------------------------------------------------------------------

local EASES: { [string]: (number) -> number } = {
	linear = function(a)
		return a
	end,
	sine = function(a)
		return 0.5 - 0.5 * math.cos(math.pi * a)
	end,
	inQuad = function(a)
		return a * a
	end,
	outQuad = function(a)
		return 1 - (1 - a) * (1 - a)
	end,
	inCubic = function(a)
		return a * a * a
	end,
	outCubic = function(a)
		local b = 1 - a
		return 1 - b * b * b
	end,
	outBack = function(a)
		local c1 = 1.70158
		local b = a - 1
		return 1 + (c1 + 1) * b * b * b + c1 * b * b
	end,
	-- arrivée très rapide puis immobilité (mouvements saccadés du robot)
	snap = function(a)
		local b = 1 - a
		return 1 - b * b * b * b * b
	end,
	step = function(a)
		return if a >= 1 then 1 else 0
	end,
}
Kit.EASES = EASES

function Kit.ease(name: string?, alpha: number): number
	local fn = EASES[name or "sine"] or EASES.sine
	return fn(math.clamp(alpha, 0, 1))
end

-- Sinus de période `period` (s) et de déphasage `phase` (tours).
function Kit.wave(t: number, period: number, phase: number?): number
	return math.sin(TAU * (t / period + (phase or 0)))
end

-- Impulsion douce 0 -> 1 -> 0 entre `start` et `finish` (rampe de `ramp` secondes de chaque côté).
function Kit.window(t: number, start: number, finish: number, ramp: number): number
	if t <= start or t >= finish then
		return 0
	end
	local up = math.clamp((t - start) / ramp, 0, 1)
	local down = math.clamp((finish - t) / ramp, 0, 1)
	return Kit.ease("sine", math.min(up, down))
end

-- Courbe scalaire par clés { temps, valeur } (triées), maintenue avant la première et après la dernière.
function Kit.curve(keys: { CurveKey }, easeName: string?): Curve
	assert(#keys >= 1, "Kit.curve : au moins une clé")
	return function(t: number): number
		if t <= keys[1][1] then
			return keys[1][2]
		end
		for index = 2, #keys do
			local b = keys[index]
			if t < b[1] then
				local a = keys[index - 1]
				local span = b[1] - a[1]
				local alpha = if span > 1e-6 then (t - a[1]) / span else 1
				local eased = Kit.ease(easeName, alpha)
				return a[2] + (b[2] - a[2]) * eased
			end
		end
		return keys[#keys][2]
	end
end

-- Interpolation sphérique entre deux directions unitaires.
function Kit.slerp(a: Vector3, b: Vector3, alpha: number): Vector3
	local dot = math.clamp(a:Dot(b), -1, 1)
	local theta = math.acos(dot) * alpha
	local relative = b - a * dot
	if relative.Magnitude < 1e-6 then
		return a:Lerp(b, alpha).Unit
	end
	return a * math.cos(theta) + relative.Unit * math.sin(theta)
end

-- Fonction joints(t) à partir de clés de pose interpolées (slerp par articulation).
-- Bouclée : le segment final relie la dernière clé à la première (à t = duration + première clé).
-- Non bouclée : la dernière pose est maintenue après la fin.
function Kit.keyframes(spec: KeyframeSpec): (number) -> Pose
	local keys = spec.keys
	local count = #keys
	assert(count >= 1, "Kit.keyframes : au moins une clé")
	local duration = math.max(spec.duration, 1e-3)
	local looped = spec.looped
	local names: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, key in keys do
		for name in key.pose do
			if not seen[name] then
				seen[name] = true
				table.insert(names, name)
			end
		end
	end
	local first, last = keys[1], keys[count]
	return function(t: number): Pose
		local time = if looped then t % duration else math.clamp(t, 0, duration)
		local a: Key, b: Key = first, first
		local alpha = 0
		if time < first.time or time >= last.time then
			if looped then
				a, b = last, first
				local span = first.time + duration - last.time
				local elapsed = if time >= last.time then time - last.time else time + duration - last.time
				alpha = if span > 1e-6 then elapsed / span else 1
			elseif time >= last.time then
				a, b = last, last
			end
		else
			local index = 1
			while index < count - 1 and keys[index + 1].time <= time do
				index += 1
			end
			a, b = keys[index], keys[index + 1]
			local span = b.time - a.time
			alpha = if span > 1e-6 then (time - a.time) / span else 1
		end
		local eased = Kit.ease(b.ease, alpha)
		local out: Pose = {}
		for _, name in names do
			local ca = a.pose[name] or IDENTITY
			local cb = b.pose[name] or IDENTITY
			if eased == 0 then
				out[name] = ca
			elseif eased == 1 then
				out[name] = cb
			else
				out[name] = ca:Lerp(cb, eased)
			end
		end
		return out
	end
end

--------------------------------------------------------------------------------
-- Effets (client uniquement, appelés par les fonctions fx des animations)
--------------------------------------------------------------------------------

-- Textures de particules INTÉGRÉES au moteur (aucun asset uploadé).
Kit.TEXTURES = {
	sparkles = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
	square = "rbxasset://textures/particles/SquareParticle.png",
}

export type SparkleProps = {
	texture: string?,
	color: ColorSequence?,
	size: number?,
	rate: number?,
	lifetime: number?,
	speed: number?,
	spread: number?,
	acceleration: Vector3?,
	lightEmission: number?,
	direction: Enum.NormalId?,
}

-- Crée un Attachment (enfant de `part`, à `offset`) portant un ParticleEmitter. Retourne l'Attachment.
function Kit.sparkles(part: BasePart, offset: CFrame, props: SparkleProps): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = "AnimFx"
	attachment.CFrame = offset
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "AnimFxEmitter"
	emitter.Texture = props.texture or Kit.TEXTURES.sparkles
	emitter.Color = props.color or ColorSequence.new(Color3.new(1, 1, 1))
	local size = props.size or 0.3
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(1, size * 0.3),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	local lifetime = props.lifetime or 0.8
	emitter.Lifetime = NumberRange.new(lifetime * 0.8, lifetime)
	emitter.Rate = props.rate or 10
	local speed = props.speed or 2
	emitter.Speed = NumberRange.new(speed * 0.8, speed)
	local spread = props.spread or 20
	emitter.SpreadAngle = Vector2.new(spread, spread)
	emitter.Acceleration = props.acceleration or Vector3.zero
	emitter.LightEmission = props.lightEmission or 0.4
	emitter.EmissionDirection = props.direction or Enum.NormalId.Top
	emitter.Parent = attachment
	attachment.Parent = part
	return attachment
end

-- Pièce du rig par nom (ou nil).
function Kit.part(model: Model, name: string): BasePart?
	local found = model:FindFirstChild(name)
	if found and found:IsA("BasePart") then
		return found
	end
	return nil
end

return Kit
