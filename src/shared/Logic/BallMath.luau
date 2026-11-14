--!strict
--[[
	BallMath : mathématiques PURES de la balle de golf (aucune instance, aucun service, aucun état global).
	Partagé par le serveur (autorité), l'aperçu client (jauge, trajectoire, cible verrouillée) et les outils
	de validation. Les paramètres d'équilibrage sont passés explicitement (tables de Config/Gameplay) :
	les fonctions restent testables sans moteur.

	Jauge
	  powerAtTime(elapsed, period)                     onde triangulaire 0 -> 1 -> 0 (port de Config.PowerAtTime)
	  serverPower(elapsed, clientPower?, period, tol)  puissance autoritaire (valeur client bornée à ± tol)
	  powerPeriod(basePeriod, gameSpeed?)               période de jauge selon la vitesse de jeu
	  effectiveGameSpeed(phase?, settingsSpeed?)        vitesse de jeu appliquée (1 hors partie)
	Frappes
	  resolveShotType(requested?, shotTypes, default)   type de frappe validé (nil si inconnu)
	  clampLoft(loft?, def) / launchSpeed(power, def) / launchVelocity(direction, loft?, power, def)
	  puttAllowed(surface?, distanceToCup?, surfaces, maxDistance)
	  addressLook(aim) / aimFromAddressLook(look)       convention d'adresse du golfeur droitier
	Vol
	  effectiveGravity(worldGravity, scale)             gravité subie par la balle
	  positionAt / velocityAt                           solution exacte : accélération constante + traînée linéaire
	  airStep(velocity, wind, drag, dt)                 pas de vol (vent + traînée), la gravité est gérée par le moteur
	  predictTrajectory(origin, velocity, params)       points échantillonnés de la trajectoire en vol
	Roulement
	  surfaceDragFactor(drag, dt) / rollStep(velocity, drag, resistance, dt) / canRestOnSlope(normal, g, R, margin)
	Trou
	  horizontalSegmentPointDistance(a, b, p)           distance horizontale segment–point (+ paramètre t)
	  segmentCircleInterval(a, b, center, radius)       portion [t0, t1] du segment dans le cercle (plan XZ)
	  captureSpeedAt(distance, radius, speed, edge) / cupCapture(previous, current, hSpeed, cup, params)
	  lipOutDeflect(velocity, closest, cup, deg, keep)  balle trop rapide qui « lèche » le trou
	Rebonds, guidage, cônes
	  reflect(velocity, normal, elasticity, tangentialKeep?)
	  angleBetween(a, b) / rotateAroundY(v, radians) / flat(v) / flatDistance(a, b)
	  homingStep(velocity, toTarget, maxTurnRate, dt) / coneCheck(origin, forward, point, deg, range, flat?)
	  pickLockTarget(origin, forward, candidates, rules) sélection de la cible du tir guidé
]]

export type ShotTypeDef = {
	MinLoft: number,
	MaxLoft: number,
	DefaultLoft: number,
	MinSpeed: number,
	MaxSpeed: number,
	PowerScale: number,
	PowerCurve: number,
}

export type PredictParams = {
	gravity: number, -- accélération verticale vers le bas subie par la balle (studs/s², positive)
	wind: Vector3?, -- accélération du vent (studs/s²)
	drag: number?, -- traînée de l'air (1/s), 0 par défaut
	step: number?, -- pas d'échantillonnage (s), défaut 1/30
	maxTime: number?, -- durée maximale simulée (s), défaut 6
	maxPoints: number?, -- nombre maximal de points (origine comprise), défaut 240
	floorY: number?, -- arrêt quand la trajectoire passe sous cette altitude
	-- Facultatif : test de collision fourni par l'appelant (ex. Raycast client) ; retourne le point d'impact.
	collide: ((from: Vector3, to: Vector3) -> Vector3?)?,
}

export type CupParams = {
	radius: number, -- rayon du trou
	tolerance: number?, -- marge ajoutée au rayon
	captureSpeed: number, -- vitesse horizontale max au centre
	edgeSpeedFactor: number?, -- réduction relative de la vitesse max au bord (0..1)
	verticalAbove: number, -- hauteur max du centre de la balle au-dessus du niveau du trou
	verticalBelow: number, -- profondeur max sous le niveau du trou
}

export type CupResult = "captured" | "lipOut" | "miss"

export type LockCandidate = {
	position: Vector3, -- point visé (torse de la cible)
	eligible: boolean, -- règles de jeu déjà vérifiées par l'appelant (adversaire, non protégé, non invisible...)
	lineOfSight: boolean, -- ligne de vue depuis l'origine (raycast de l'appelant)
}

export type LockRules = {
	range: number,
	minDistance: number,
	coneDeg: number, -- demi-angle du cône horizontal
	maxVerticalOffset: number,
	angleWeight: number,
}

local BallMath = {}

local EPSILON = 1e-9
local DRAG_EPSILON = 1e-6 -- en dessous, la traînée est négligée (formules paraboliques exactes)
local MATCH_PHASES: { [string]: boolean } = {
	Loading = true,
	HoleIntro = true,
	Countdown = true,
	Playing = true,
	HoleEnd = true,
	HoleResults = true,
}

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function isFiniteVector(value: Vector3): boolean
	return isFinite(value.X) and isFinite(value.Y) and isFinite(value.Z)
end

local function flat(value: Vector3): Vector3
	return Vector3.new(value.X, 0, value.Z)
end

BallMath.isFinite = isFinite
BallMath.isFiniteVector = isFiniteVector
BallMath.flat = flat

-- Distance dans le plan horizontal (XZ).
function BallMath.flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

--------------------------------------------------------------------------------
-- Jauge de puissance
--------------------------------------------------------------------------------

-- Onde triangulaire 0 -> 1 -> 0 de période `period` (port de Config.PowerAtTime du prototype).
-- Toute entrée invalide (négative, NaN, infinie, période nulle) donne 0.
function BallMath.powerAtTime(elapsed: number, period: number): number
	if not isFinite(elapsed) or elapsed <= 0 or not isFinite(period) or period <= 0 then
		return 0
	end
	local phase = (elapsed / period) % 1
	if phase < 0.5 then
		return phase * 2
	end
	return (1 - phase) * 2
end

-- Puissance autoritaire : recalculée depuis le temps serveur ; la valeur client (latence, affichage) n'est
-- acceptée qu'à ± tolerance de la valeur serveur. Résultat toujours dans [0, 1].
function BallMath.serverPower(elapsed: number, clientPower: number?, period: number, tolerance: number): number
	local serverValue = BallMath.powerAtTime(elapsed, period)
	local power = serverValue
	if clientPower ~= nil and isFinite(clientPower) then
		local margin = if isFinite(tolerance) then math.max(0, tolerance) else 0
		power = math.clamp(clientPower, serverValue - margin, serverValue + margin)
	end
	return math.clamp(power, 0, 1)
end

-- Période de la jauge pour une vitesse de jeu donnée (bornée à 0,5..2).
function BallMath.powerPeriod(basePeriod: number, gameSpeed: number?): number
	local speed = if gameSpeed ~= nil and isFinite(gameSpeed) then math.clamp(gameSpeed, 0.5, 2) else 1
	return basePeriod / speed
end

-- Vitesse de jeu effectivement appliquée : celle des réglages pendant une partie, 1 à l'accueil.
function BallMath.effectiveGameSpeed(phase: string?, settingsSpeed: number?): number
	if phase == nil or not MATCH_PHASES[phase] then
		return 1
	end
	if settingsSpeed == nil or not isFinite(settingsSpeed) then
		return 1
	end
	return math.clamp(settingsSpeed, 0.5, 2)
end

--------------------------------------------------------------------------------
-- Frappes
--------------------------------------------------------------------------------

-- Type de frappe validé : nil/"" -> défaut ; inconnu -> nil (requête invalide).
function BallMath.resolveShotType(requested: string?, shotTypes: { [string]: any }, default: string): string?
	if requested == nil or requested == "" then
		return default
	end
	if shotTypes[requested] ~= nil then
		return requested
	end
	return nil
end

-- Angle de frappe borné au type ; une valeur absente ou invalide donne l'angle par défaut du type.
function BallMath.clampLoft(loft: number?, def: ShotTypeDef): number
	if loft == nil or not isFinite(loft) then
		return def.DefaultLoft
	end
	return math.clamp(loft, def.MinLoft, def.MaxLoft)
end

-- Vitesse de lancement : MinSpeed + (MaxSpeed - MinSpeed) × power^PowerCurve, puis × PowerScale.
function BallMath.launchSpeed(power: number, def: ShotTypeDef): number
	local p = if isFinite(power) then math.clamp(power, 0, 1) else 0
	local curve = if isFinite(def.PowerCurve) and def.PowerCurve > 0 then def.PowerCurve else 1
	local shaped = p ^ curve
	return (def.MinSpeed + (def.MaxSpeed - def.MinSpeed) * shaped) * def.PowerScale
end

-- Vitesse initiale : direction horizontale (normalisée ici), relevée de `loftDegrees` (borné au type).
-- Retourne Vector3.zero si la direction est invalide ou nulle.
function BallMath.launchVelocity(direction: Vector3, loftDegrees: number?, power: number, def: ShotTypeDef): Vector3
	local horizontal = flat(direction)
	if not isFiniteVector(horizontal) or horizontal.Magnitude < 1e-4 then
		return Vector3.zero
	end
	horizontal = horizontal.Unit
	local loft = math.rad(BallMath.clampLoft(loftDegrees, def))
	local speed = BallMath.launchSpeed(power, def)
	return (horizontal * math.cos(loft) + Vector3.yAxis * math.sin(loft)) * speed
end

-- Règle du putt : toujours permis sur une surface listée (green), sinon seulement près du trou.
function BallMath.puttAllowed(
	surface: string?,
	distanceToCup: number?,
	allowedSurfaces: { string },
	maxCupDistance: number
): boolean
	if surface ~= nil and table.find(allowedSurfaces, surface) ~= nil then
		return true
	end
	return distanceToCup ~= nil and isFinite(distanceToCup) and distanceToCup <= maxCupDistance
end

-- Convention d'adresse (golfeur droitier, voir shared/Animations/Library/Golf) : pendant la visée, le
-- personnage fait face à la balle et la cible est à SA GAUCHE : regard = visée × Y, visée = Y × regard.
-- Retournent nil pour une entrée invalide ou verticale.
function BallMath.addressLook(aim: Vector3): Vector3?
	local horizontal = flat(aim)
	if not isFiniteVector(horizontal) or horizontal.Magnitude < 1e-4 then
		return nil
	end
	return horizontal.Unit:Cross(Vector3.yAxis)
end

function BallMath.aimFromAddressLook(look: Vector3): Vector3?
	local horizontal = flat(look)
	if not isFiniteVector(horizontal) or horizontal.Magnitude < 1e-4 then
		return nil
	end
	return Vector3.yAxis:Cross(horizontal.Unit)
end

--------------------------------------------------------------------------------
-- Vol : solution exacte d'un mobile soumis à une accélération constante et à une traînée linéaire
--   dv/dt = accel - drag × v
--   v(t) = accel/drag + (v0 - accel/drag) e^(-drag t)
--   p(t) = p0 + (accel/drag) t + (v0 - accel/drag)(1 - e^(-drag t)) / drag
-- Sans traînée : parabole p(t) = p0 + v0 t + accel t² / 2.
--------------------------------------------------------------------------------

-- Gravité subie par la balle (studs/s², positive) : g du monde × fraction (VectorForce de compensation).
function BallMath.effectiveGravity(worldGravity: number, gravityScale: number): number
	if not isFinite(worldGravity) or not isFinite(gravityScale) then
		return 0
	end
	return math.max(0, worldGravity * gravityScale)
end

function BallMath.positionAt(origin: Vector3, velocity: Vector3, accel: Vector3, drag: number, t: number): Vector3
	if drag <= DRAG_EPSILON then
		return origin + velocity * t + accel * (0.5 * t * t)
	end
	local terminal = accel / drag
	local decay = 1 - math.exp(-drag * t)
	return origin + terminal * t + (velocity - terminal) * (decay / drag)
end

function BallMath.velocityAt(velocity: Vector3, accel: Vector3, drag: number, t: number): Vector3
	if drag <= DRAG_EPSILON then
		return velocity + accel * t
	end
	local terminal = accel / drag
	return terminal + (velocity - terminal) * math.exp(-drag * t)
end

-- Un pas de vol appliqué par le serveur à chaque Heartbeat : vent + traînée (la gravité est intégrée par le
-- moteur physique). Solution exacte de dv/dt = wind - drag × v sur dt.
function BallMath.airStep(velocity: Vector3, wind: Vector3, drag: number, dt: number): Vector3
	if not isFinite(dt) or dt <= 0 then
		return velocity
	end
	local safeWind = if isFiniteVector(wind) then wind else Vector3.zero
	local safeDrag = if isFinite(drag) then math.max(0, drag) else 0
	return BallMath.velocityAt(velocity, safeWind, safeDrag, dt)
end

-- Trajectoire en vol échantillonnée (aperçu client, outils). Retourne (points, aTouché, duréeSimulée) ;
-- le premier point est l'origine. Avec drag = 0 et wind = 0, chaque point est exactement sur la parabole.
-- Approximation volontaire : ni rebond ni roulement (le serveur simule la suite avec le moteur physique).
function BallMath.predictTrajectory(origin: Vector3, velocity: Vector3, params: PredictParams): ({ Vector3 }, boolean, number)
	local points = { origin }
	if not isFiniteVector(origin) or not isFiniteVector(velocity) then
		return points, false, 0
	end
	local gravity = if isFinite(params.gravity) then params.gravity else 0
	local wind = params.wind or Vector3.zero
	if not isFiniteVector(wind) then
		wind = Vector3.zero
	end
	local drag = params.drag or 0
	if not isFinite(drag) or drag < 0 then
		drag = 0
	end
	local step = params.step or (1 / 30)
	if not isFinite(step) then
		step = 1 / 30
	end
	step = math.clamp(step, 1 / 240, 0.5)
	local maxTime = params.maxTime or 6
	if not isFinite(maxTime) then
		maxTime = 6
	end
	maxTime = math.clamp(maxTime, 0, 60)
	local maxPoints = params.maxPoints or 240
	if not isFinite(maxPoints) then
		maxPoints = 240
	end
	maxPoints = math.clamp(math.floor(maxPoints), 2, 4000)

	local accel = Vector3.new(wind.X, wind.Y - gravity, wind.Z)
	local floorY = params.floorY
	local collide = params.collide
	local previous = origin
	local index = 0
	local t = 0
	while #points < maxPoints and t < maxTime do
		index += 1
		-- t = index × step (et non une somme cumulée) : aucune dérive d'arrondi sur les longues trajectoires.
		t = math.min(index * step, maxTime)
		local point = BallMath.positionAt(origin, velocity, accel, drag, t)
		if collide then
			local hit = collide(previous, point)
			if hit ~= nil then
				table.insert(points, hit)
				return points, true, t
			end
		end
		if floorY ~= nil and point.Y <= floorY then
			local fall = previous.Y - point.Y
			local alpha = if fall > EPSILON then math.clamp((previous.Y - floorY) / fall, 0, 1) else 1
			table.insert(points, previous:Lerp(point, alpha))
			return points, true, t - step * (1 - alpha)
		end
		table.insert(points, point)
		previous = point
	end
	return points, false, t
end

--------------------------------------------------------------------------------
-- Roulement
--------------------------------------------------------------------------------

-- Facteur de freinage exponentiel (indépendant de la fréquence d'images) : e^(-drag × dt) dans ]0, 1].
function BallMath.surfaceDragFactor(drag: number, dt: number): number
	if not isFinite(drag) or not isFinite(dt) or drag <= 0 or dt <= 0 then
		return 1
	end
	return math.exp(-drag * dt)
end

-- Un pas de roulement : freinage proportionnel (Drag) puis constant (RollResistance), sans inversion de sens.
function BallMath.rollStep(velocity: Vector3, drag: number, resistance: number, dt: number): Vector3
	local speed = velocity.Magnitude
	if speed < EPSILON or not isFinite(speed) then
		return Vector3.zero
	end
	local afterDrag = speed * BallMath.surfaceDragFactor(drag, dt)
	local safeResistance = if isFinite(resistance) then math.max(0, resistance) else 0
	local safeDt = if isFinite(dt) then math.max(0, dt) else 0
	local afterResistance = math.max(0, afterDrag - safeResistance * safeDt)
	return velocity * (afterResistance / speed)
end

-- La balle peut-elle rester immobile sur cette pente ? (composante de gravité le long de la pente
-- inférieure au freinage constant de la surface, avec une marge)
function BallMath.canRestOnSlope(normal: Vector3, gravity: number, resistance: number, margin: number): boolean
	if not isFiniteVector(normal) or normal.Magnitude < EPSILON then
		return false
	end
	local up = math.clamp(normal.Unit.Y, -1, 1)
	if up <= 0 then
		return false -- plafond ou paroi renversée
	end
	local sinSlope = math.sqrt(math.max(0, 1 - up * up))
	return gravity * sinSlope <= resistance * margin + 1e-6
end

--------------------------------------------------------------------------------
-- Trou
--------------------------------------------------------------------------------

-- Distance HORIZONTALE (plan XZ) entre le point p et le segment [a, b] ; retourne aussi t ∈ [0, 1],
-- paramètre du point le plus proche (a + (b - a) t).
function BallMath.horizontalSegmentPointDistance(a: Vector3, b: Vector3, p: Vector3): (number, number)
	local abx, abz = b.X - a.X, b.Z - a.Z
	local apx, apz = p.X - a.X, p.Z - a.Z
	local lengthSquared = abx * abx + abz * abz
	local t = 0
	if lengthSquared > EPSILON then
		t = math.clamp((apx * abx + apz * abz) / lengthSquared, 0, 1)
	end
	local cx = a.X + abx * t - p.X
	local cz = a.Z + abz * t - p.Z
	return math.sqrt(cx * cx + cz * cz), t
end

-- Portion du segment [a, b] dont la projection horizontale est dans le cercle (centre, rayon) :
-- retourne (t0, t1) avec 0 <= t0 <= t1 <= 1, ou (nil, nil) si le segment reste dehors.
function BallMath.segmentCircleInterval(a: Vector3, b: Vector3, center: Vector3, radius: number): (number?, number?)
	if not isFinite(radius) or radius <= 0 then
		return nil, nil
	end
	local dx, dz = b.X - a.X, b.Z - a.Z
	local fx, fz = a.X - center.X, a.Z - center.Z
	local quadA = dx * dx + dz * dz
	local quadC = fx * fx + fz * fz - radius * radius
	if quadA < EPSILON then
		-- Déplacement horizontal nul : dedans ou dehors sur tout le pas.
		if quadC <= 0 then
			return 0, 1
		end
		return nil, nil
	end
	local quadB = 2 * (fx * dx + fz * dz)
	local discriminant = quadB * quadB - 4 * quadA * quadC
	if discriminant < 0 then
		return nil, nil
	end
	local root = math.sqrt(discriminant)
	local t0 = (-quadB - root) / (2 * quadA)
	local t1 = (-quadB + root) / (2 * quadA)
	if t1 < 0 or t0 > 1 then
		return nil, nil
	end
	return math.max(t0, 0), math.min(t1, 1)
end

-- Vitesse horizontale max de capture à une distance donnée du centre (plus faible près du bord).
function BallMath.captureSpeedAt(distance: number, radius: number, captureSpeed: number, edgeSpeedFactor: number): number
	if radius <= 0 then
		return 0
	end
	local ratio = math.clamp(distance / radius, 0, 1)
	return captureSpeed * (1 - math.clamp(edgeSpeedFactor, 0, 1) * ratio)
end

-- Test BALAYÉ segment–cylindre : la balle est passée de `previous` à `current` pendant le pas.
--   "captured" : la portion du segment située au-dessus du trou (cercle de capture) traverse la tranche
--                verticale [cup.Y - verticalBelow, cup.Y + verticalAbove], assez lentement ;
--   "lipOut"   : elle passe sur le trou mais trop vite (la balle ressort) ;
--   "miss"     : à côté ou au-dessus.
-- Une balle rapide qui traverse tout le trou entre deux pas est donc détectée (pas de test ponctuel).
-- Le second résultat est le point du segment le plus proche du centre (nil si "miss").
function BallMath.cupCapture(
	previous: Vector3,
	current: Vector3,
	horizontalSpeed: number,
	cup: Vector3,
	params: CupParams
): (CupResult, Vector3?)
	local radius = params.radius + (params.tolerance or 0)
	if radius <= 0 or not isFiniteVector(previous) or not isFiniteVector(current) or not isFiniteVector(cup) then
		return "miss", nil
	end
	local t0, t1 = BallMath.segmentCircleInterval(previous, current, cup, radius)
	if t0 == nil or t1 == nil then
		return "miss", nil
	end
	local y0 = previous.Y + (current.Y - previous.Y) * t0
	local y1 = previous.Y + (current.Y - previous.Y) * t1
	local low, high = math.min(y0, y1), math.max(y0, y1)
	if high < cup.Y - params.verticalBelow or low > cup.Y + params.verticalAbove then
		return "miss", nil
	end
	-- Le point le plus proche du centre appartient forcément à [t0, t1] (distance convexe le long du segment).
	local distance, t = BallMath.horizontalSegmentPointDistance(previous, current, cup)
	local closest = previous:Lerp(current, math.clamp(t, t0, t1))
	local maxSpeed = BallMath.captureSpeedAt(distance, radius, params.captureSpeed, params.edgeSpeedFactor or 0)
	if not isFinite(horizontalSpeed) or horizontalSpeed > maxSpeed then
		return "lipOut", closest
	end
	return "captured", closest
end

-- Balle trop rapide passée sur le trou : sa direction horizontale tourne de `deflectDeg` degrés en
-- s'écartant du centre (côté du point de passage) et sa vitesse horizontale est multipliée par `keep`.
-- Passage exactement au centre : côté droit de la trajectoire (déterministe). Composante verticale inchangée.
function BallMath.lipOutDeflect(velocity: Vector3, closest: Vector3, cup: Vector3, deflectDeg: number, keep: number): Vector3
	local horizontal = flat(velocity)
	local speed = horizontal.Magnitude
	if speed < 1e-6 or not isFinite(speed) then
		return velocity
	end
	local direction = horizontal / speed
	local offset = flat(closest - cup)
	local perpendicular = offset - direction * offset:Dot(direction)
	if perpendicular.Magnitude < 1e-4 then
		perpendicular = direction:Cross(Vector3.yAxis)
	end
	local side = perpendicular.Unit
	local angle = math.rad(math.clamp(if isFinite(deflectDeg) then deflectDeg else 0, 0, 89))
	local turned = (direction * math.cos(angle) + side * math.sin(angle)).Unit
	local factor = math.clamp(if isFinite(keep) then keep else 1, 0, 1)
	local newSpeed = speed * factor
	return Vector3.new(turned.X * newSpeed, velocity.Y, turned.Z * newSpeed)
end

--------------------------------------------------------------------------------
-- Rebonds, guidage, cônes
--------------------------------------------------------------------------------

-- Réflexion sur une surface de normale `normal` : composante normale inversée × élasticité,
-- composante tangentielle × tangentialKeep. Une vitesse qui s'éloigne déjà de la surface est inchangée.
function BallMath.reflect(velocity: Vector3, normal: Vector3, elasticity: number, tangentialKeep: number?): Vector3
	if not isFiniteVector(normal) or normal.Magnitude < EPSILON then
		return velocity
	end
	local n = normal.Unit
	local into = velocity:Dot(n)
	if into >= 0 then
		return velocity
	end
	local normalPart = n * into
	local tangent = velocity - normalPart
	local e = if isFinite(elasticity) then math.clamp(elasticity, 0, 1) else 0
	local keep = tangentialKeep or 1
	if not isFinite(keep) then
		keep = 1
	end
	return tangent * math.clamp(keep, 0, 1) - normalPart * e
end

-- Angle (radians, 0..π) entre deux vecteurs ; π si l'un d'eux est nul ou invalide.
function BallMath.angleBetween(a: Vector3, b: Vector3): number
	if not isFiniteVector(a) or not isFiniteVector(b) or a.Magnitude < EPSILON or b.Magnitude < EPSILON then
		return math.pi
	end
	return math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1))
end

-- Rotation d'un vecteur autour de l'axe vertical (radians, sens trigonométrique vu de dessus : +X vers -Z).
function BallMath.rotateAroundY(vector: Vector3, radians: number): Vector3
	if not isFinite(radians) then
		return vector
	end
	local c, s = math.cos(radians), math.sin(radians)
	return Vector3.new(vector.X * c + vector.Z * s, vector.Y, -vector.X * s + vector.Z * c)
end

-- Un pas de guidage : oriente `velocity` vers `toTarget` d'au plus maxTurnRate × dt radians,
-- en conservant la norme. Entrées invalides ou nulles : vitesse inchangée.
function BallMath.homingStep(velocity: Vector3, toTarget: Vector3, maxTurnRate: number, dt: number): Vector3
	local speed = velocity.Magnitude
	if speed < EPSILON or not isFinite(speed) then
		return velocity
	end
	if not isFiniteVector(toTarget) or toTarget.Magnitude < EPSILON then
		return velocity
	end
	if not isFinite(maxTurnRate) or not isFinite(dt) or maxTurnRate <= 0 or dt <= 0 then
		return velocity
	end
	local u = velocity / speed
	local w = toTarget.Unit
	local angle = math.acos(math.clamp(u:Dot(w), -1, 1))
	local maxStep = maxTurnRate * dt
	if angle <= maxStep then
		return w * speed
	end
	local axis = u:Cross(w)
	if axis.Magnitude < 1e-6 then
		-- Cible exactement opposée : n'importe quel axe perpendiculaire convient.
		axis = u:Cross(Vector3.yAxis)
		if axis.Magnitude < 1e-6 then
			axis = u:Cross(Vector3.xAxis)
		end
	end
	local k = axis.Unit
	-- Rotation de Rodrigues autour d'un axe perpendiculaire à u (k · u = 0).
	local rotated = u * math.cos(maxStep) + k:Cross(u) * math.sin(maxStep)
	return rotated.Unit * speed
end

-- Le point est-il dans le cône (demi-angle en degrés) de sommet `origin`, d'axe `forward`, de portée `range` ?
-- flatTest = true : test dans le plan horizontal (angle et distance horizontaux).
-- Retourne (dansLeCône, angleRadians, distance).
function BallMath.coneCheck(
	origin: Vector3,
	forward: Vector3,
	point: Vector3,
	halfAngleDeg: number,
	range: number,
	flatTest: boolean?
): (boolean, number, number)
	local offset = point - origin
	local axis = forward
	if flatTest then
		offset = flat(offset)
		axis = flat(axis)
	end
	if not isFiniteVector(offset) then
		return false, math.pi, math.huge
	end
	local distance = offset.Magnitude
	if distance > range then
		return false, math.pi, distance
	end
	if distance < EPSILON then
		return true, 0, 0
	end
	local angle = BallMath.angleBetween(axis, offset)
	return angle <= math.rad(halfAngleDeg), angle, distance
end

-- Sélection de la cible du tir guidé parmi des candidats (règles de jeu et ligne de vue déjà évaluées par
-- l'appelant) : cône horizontal, distances min/max, écart d'altitude, puis plus petit score
-- angle × angleWeight + distance / range. Retourne (indice, score) ou (nil, nil).
function BallMath.pickLockTarget(origin: Vector3, forward: Vector3, candidates: { LockCandidate }, rules: LockRules): (number?, number?)
	local axis = flat(forward)
	if not isFiniteVector(axis) or axis.Magnitude < 1e-4 or not isFiniteVector(origin) then
		return nil, nil
	end
	local range = math.max(rules.range, EPSILON)
	local bestIndex: number? = nil
	local bestScore = math.huge
	for index, candidate in candidates do
		if not candidate.eligible or not candidate.lineOfSight or not isFiniteVector(candidate.position) then
			continue
		end
		if math.abs(candidate.position.Y - origin.Y) > rules.maxVerticalOffset then
			continue
		end
		local inCone, angle, distance = BallMath.coneCheck(origin, axis, candidate.position, rules.coneDeg, range, true)
		if not inCone or distance < rules.minDistance then
			continue
		end
		local score = angle * rules.angleWeight + distance / range
		if score < bestScore then
			bestScore = score
			bestIndex = index
		end
	end
	if bestIndex == nil then
		return nil, nil
	end
	return bestIndex, bestScore
end

return BallMath
