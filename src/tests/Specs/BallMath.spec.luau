--!strict
-- Tests de la logique pure de la balle (jauge, frappes, trou, trajectoire, guidage, verrouillage).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallMath = require(Shared.Logic.BallMath)
local Gameplay = require(Shared.Config.Gameplay)

return function(t)
	local SHOT_TYPES = Gameplay.ShotTypes
	local PERIOD = Gameplay.Shot.PowerPeriod
	local CUP = Gameplay.Cup
	local CUP_PARAMS: BallMath.CupParams = {
		radius = CUP.Radius,
		tolerance = CUP.CaptureTolerance,
		captureSpeed = CUP.CaptureSpeed,
		edgeSpeedFactor = CUP.EdgeSpeedFactor,
		verticalAbove = CUP.VerticalAbove,
		verticalBelow = CUP.VerticalBelow,
	}
	local CAPTURE_RADIUS = CUP.Radius + CUP.CaptureTolerance
	local BALL_RADIUS = Gameplay.Ball.Diameter / 2

	t.describe("Jauge de puissance", function()
		t.it("suit l'onde triangulaire 0 -> 1 -> 0", function()
			t.expect(BallMath.powerAtTime(0, PERIOD)).toBe(0)
			t.expect(BallMath.powerAtTime(PERIOD / 4, PERIOD)).toBeCloseTo(0.5, 1e-9)
			t.expect(BallMath.powerAtTime(PERIOD / 2, PERIOD)).toBeCloseTo(1, 1e-9)
			t.expect(BallMath.powerAtTime(PERIOD * 3 / 4, PERIOD)).toBeCloseTo(0.5, 1e-9)
			t.expect(BallMath.powerAtTime(PERIOD * 1.25, PERIOD)).toBeCloseTo(0.5, 1e-9)
		end)

		t.it("reste dans [0, 1] et donne 0 pour une entrée invalide", function()
			for index = 0, 200 do
				local power = BallMath.powerAtTime(index * 0.037, PERIOD)
				t.expect(power).toBeGreaterThanOrEqual(0)
				t.expect(power).toBeLessThanOrEqual(1)
			end
			t.expect(BallMath.powerAtTime(-1, PERIOD)).toBe(0)
			t.expect(BallMath.powerAtTime(0 / 0, PERIOD)).toBe(0)
			t.expect(BallMath.powerAtTime(math.huge, PERIOD)).toBe(0)
			t.expect(BallMath.powerAtTime(1, 0)).toBe(0)
		end)

		t.it("borne la puissance client autour de la valeur recalculée par le serveur", function()
			local tolerance = Gameplay.Shot.PowerTolerance
			local elapsed = PERIOD / 4 -- valeur serveur : 0,5
			t.expect(BallMath.serverPower(elapsed, 1, PERIOD, tolerance)).toBeCloseTo(0.5 + tolerance, 1e-9)
			t.expect(BallMath.serverPower(elapsed, 0, PERIOD, tolerance)).toBeCloseTo(0.5 - tolerance, 1e-9)
			t.expect(BallMath.serverPower(elapsed, 0.55, PERIOD, tolerance)).toBeCloseTo(0.55, 1e-9)
			t.expect(BallMath.serverPower(elapsed, nil, PERIOD, tolerance)).toBeCloseTo(0.5, 1e-9)
			t.expect(BallMath.serverPower(elapsed, 0 / 0, PERIOD, tolerance)).toBeCloseTo(0.5, 1e-9)
			t.expect(BallMath.serverPower(PERIOD / 2, 5, PERIOD, tolerance)).toBe(1)
		end)

		t.it("n'applique la vitesse de jeu que pendant une partie", function()
			t.expect(BallMath.effectiveGameSpeed("Lobby", 1.5)).toBe(1)
			t.expect(BallMath.effectiveGameSpeed("Playing", 1.5)).toBe(1.5)
			t.expect(BallMath.effectiveGameSpeed("Playing", 10)).toBe(2)
			t.expect(BallMath.effectiveGameSpeed("Playing", nil)).toBe(1)
			t.expect(BallMath.powerPeriod(1.6, 2)).toBeCloseTo(0.8, 1e-9)
		end)
	end)

	t.describe("Types de frappe et vitesse de lancement", function()
		t.it("valide le type demandé", function()
			t.expect(BallMath.resolveShotType(nil, SHOT_TYPES, "Drive")).toBe("Drive")
			t.expect(BallMath.resolveShotType("", SHOT_TYPES, "Drive")).toBe("Drive")
			t.expect(BallMath.resolveShotType("Chip", SHOT_TYPES, "Drive")).toBe("Chip")
			t.expect(BallMath.resolveShotType("Putt", SHOT_TYPES, "Drive")).toBe("Putt")
			t.expect(BallMath.resolveShotType("Laser", SHOT_TYPES, "Drive")).toBeNil()
		end)

		t.it("reste dans les bornes de vitesse et d'angle de chaque type", function()
			for _, def in SHOT_TYPES do
				local minSpeed = def.MinSpeed * def.PowerScale
				local maxSpeed = def.MaxSpeed * def.PowerScale
				for step = 0, 10 do
					local speed = BallMath.launchSpeed(step / 10, def)
					t.expect(speed).toBeGreaterThanOrEqual(minSpeed - 1e-9)
					t.expect(speed).toBeLessThanOrEqual(maxSpeed + 1e-9)
				end
				t.expect(BallMath.launchSpeed(0, def)).toBeCloseTo(minSpeed, 1e-9)
				t.expect(BallMath.launchSpeed(1, def)).toBeCloseTo(maxSpeed, 1e-9)
				t.expect(BallMath.launchSpeed(5, def)).toBeCloseTo(maxSpeed, 1e-9)
				t.expect(BallMath.launchSpeed(-3, def)).toBeCloseTo(minSpeed, 1e-9)
				t.expect(BallMath.launchSpeed(0 / 0, def)).toBeCloseTo(minSpeed, 1e-9)

				local low = BallMath.launchVelocity(Vector3.new(1, 0, 0), -90, 1, def)
				local high = BallMath.launchVelocity(Vector3.new(1, 0, 0), 90, 1, def)
				t.expect(math.deg(math.asin(low.Unit.Y))).toBeCloseTo(def.MinLoft, 1e-4)
				t.expect(math.deg(math.asin(high.Unit.Y))).toBeCloseTo(def.MaxLoft, 1e-4)
				t.expect(high.Magnitude).toBeCloseTo(maxSpeed, 1e-4)
				local default = BallMath.launchVelocity(Vector3.new(0, 0, 1), nil, 0.5, def)
				t.expect(math.deg(math.asin(default.Unit.Y))).toBeCloseTo(def.DefaultLoft, 1e-4)
			end
		end)

		t.it("respecte les règles du drive, du chip et du putt", function()
			local drive, chip, putt = SHOT_TYPES.Drive, SHOT_TYPES.Chip, SHOT_TYPES.Putt
			t.expect(drive.MinLoft).toBe(8)
			t.expect(drive.MaxLoft).toBe(60)
			t.expect(chip.MinLoft).toBe(48)
			t.expect(chip.MaxLoft).toBe(60)
			t.expect(chip.PowerScale).toBeCloseTo(0.6, 1e-9)
			t.expect(putt.MinLoft).toBe(0)
			t.expect(putt.MaxLoft).toBe(3)
			t.expect(BallMath.launchSpeed(1, putt)).toBeCloseTo(60, 1e-9)
			-- Même jauge que le drive, mais 60 % de la vitesse.
			t.expect(BallMath.launchSpeed(0.7, chip)).toBeCloseTo(BallMath.launchSpeed(0.7, drive) * 0.6, 1e-4)
			-- Courbe du putt : plus lent qu'une jauge linéaire à mi-puissance (précision des petits putts).
			t.expect(BallMath.launchSpeed(0.5, putt)).toBeLessThan((putt.MinSpeed + putt.MaxSpeed) / 2)
		end)

		t.it("normalise la direction et refuse une direction nulle ou invalide", function()
			local velocity = BallMath.launchVelocity(Vector3.new(0, 50, 10), 0, 1, SHOT_TYPES.Putt)
			t.expect(velocity.X).toBeCloseTo(0, 1e-9)
			t.expect(velocity.Y).toBeCloseTo(0, 1e-9)
			t.expect(velocity.Z).toBeCloseTo(60, 1e-4)
			t.expect(BallMath.launchVelocity(Vector3.new(0, 5, 0), 20, 1, SHOT_TYPES.Drive)).toBe(Vector3.zero)
			t.expect(BallMath.launchVelocity(Vector3.new(0 / 0, 0, 1), 20, 1, SHOT_TYPES.Drive)).toBe(Vector3.zero)
		end)

		t.it("n'autorise le putt que sur le green ou près du trou", function()
			local surfaces = Gameplay.Shot.PuttSurfaces
			local maxDistance = Gameplay.Shot.PuttMaxCupDistance
			t.expect(BallMath.puttAllowed("Green", 200, surfaces, maxDistance)).toBeTruthy()
			t.expect(BallMath.puttAllowed("Fairway", maxDistance - 1, surfaces, maxDistance)).toBeTruthy()
			t.expect(BallMath.puttAllowed("Fairway", maxDistance + 1, surfaces, maxDistance)).toBeFalsy()
			t.expect(BallMath.puttAllowed("Rough", nil, surfaces, maxDistance)).toBeFalsy()
			t.expect(BallMath.puttAllowed(nil, 0 / 0, surfaces, maxDistance)).toBeFalsy()
		end)

		t.it("convertit la convention d'adresse dans les deux sens", function()
			local aim = Vector3.new(3, 0, -4).Unit
			local look = BallMath.addressLook(aim)
			t.expect(look).notToBeNil()
			t.expect(math.abs((look :: Vector3):Dot(aim))).toBeLessThan(1e-9)
			local back = BallMath.aimFromAddressLook(look :: Vector3)
			t.expect(((back :: Vector3) - aim).Magnitude).toBeLessThan(1e-9)
			t.expect(BallMath.addressLook(Vector3.yAxis)).toBeNil()
		end)
	end)

	t.describe("Capture du trou (test balayé segment–cercle)", function()
		local cup = Vector3.new(10, 5, -4)
		local rolling = BALL_RADIUS -- centre d'une balle qui roule sur le green

		t.it("capture une balle qui traverse tout le trou en un seul pas", function()
			local previous = cup + Vector3.new(-2.5, rolling, 0)
			local current = cup + Vector3.new(2.5, rolling, 0)
			-- Les deux extrémités sont hors du trou : un test ponctuel la manquerait.
			t.expect(BallMath.flatDistance(previous, cup)).toBeGreaterThan(CAPTURE_RADIUS)
			t.expect(BallMath.flatDistance(current, cup)).toBeGreaterThan(CAPTURE_RADIUS)
			local result, closest = BallMath.cupCapture(previous, current, 20, cup, CUP_PARAMS)
			t.expect(result).toBe("captured")
			t.expect(closest).notToBeNil()
			t.expect(BallMath.flatDistance(closest :: Vector3, cup)).toBeCloseTo(0, 1e-4)
		end)

		t.it("fait ressortir une balle trop rapide qui passe sur le trou", function()
			local previous = cup + Vector3.new(-2.5, rolling, 0)
			local current = cup + Vector3.new(2.5, rolling, 0)
			local result = BallMath.cupCapture(previous, current, CUP.CaptureSpeed + 30, cup, CUP_PARAMS)
			t.expect(result).toBe("lipOut")
		end)

		t.it("ignore une balle lente qui passe à côté", function()
			local side = CAPTURE_RADIUS + 0.3
			local previous = cup + Vector3.new(-3, rolling, side)
			local current = cup + Vector3.new(3, rolling, side)
			local result, closest = BallMath.cupCapture(previous, current, 5, cup, CUP_PARAMS)
			t.expect(result).toBe("miss")
			t.expect(closest).toBeNil()
		end)

		t.it("ignore une balle qui survole le trou", function()
			local previous = cup + Vector3.new(-3, 4, 0)
			local current = cup + Vector3.new(3, 4, 0)
			t.expect((BallMath.cupCapture(previous, current, 5, cup, CUP_PARAMS))).toBe("miss")
		end)

		t.it("capture une balle qui plonge dans le trou depuis les airs", function()
			local previous = cup + Vector3.new(-1.2, 3, 0)
			local current = cup + Vector3.new(0.3, rolling, 0)
			t.expect((BallMath.cupCapture(previous, current, 10, cup, CUP_PARAMS))).toBe("captured")
		end)

		t.it("est plus exigeante au bord qu'au centre", function()
			local speed = 25
			local center = BallMath.cupCapture(cup + Vector3.new(-3, rolling, 0), cup + Vector3.new(3, rolling, 0), speed, cup, CUP_PARAMS)
			local edgeOffset = CAPTURE_RADIUS - 0.2
			local edge = BallMath.cupCapture(
				cup + Vector3.new(-3, rolling, edgeOffset),
				cup + Vector3.new(3, rolling, edgeOffset),
				speed,
				cup,
				CUP_PARAMS
			)
			t.expect(center).toBe("captured")
			t.expect(edge).toBe("lipOut")
		end)

		t.it("calcule la portion du segment au-dessus du trou", function()
			local t0, t1 = BallMath.segmentCircleInterval(Vector3.new(-2, 0, 0), Vector3.new(2, 0, 0), Vector3.zero, 1)
			t.expect(t0).toBeCloseTo(0.25, 1e-9)
			t.expect(t1).toBeCloseTo(0.75, 1e-9)
			local n0, n1 = BallMath.segmentCircleInterval(Vector3.new(-2, 0, 3), Vector3.new(2, 0, 3), Vector3.zero, 1)
			t.expect(n0).toBeNil()
			t.expect(n1).toBeNil()
			local distance, at = BallMath.horizontalSegmentPointDistance(Vector3.new(-2, 7, 1), Vector3.new(2, -3, 1), Vector3.zero)
			t.expect(distance).toBeCloseTo(1, 1e-9)
			t.expect(at).toBeCloseTo(0.5, 1e-9)
		end)

		t.it("dévie une balle ressortie en l'écartant du trou et la ralentit", function()
			local velocity = Vector3.new(40, -2, 0)
			local closest = cup + Vector3.new(0, rolling, 0.5) -- passage côté +Z du centre
			local deflected = BallMath.lipOutDeflect(velocity, closest, cup, CUP.LipOutDeflectDeg, CUP.LipOutSpeedKeep)
			t.expect(deflected.Z).toBeGreaterThan(0)
			t.expect(deflected.Y).toBe(-2)
			local horizontal = Vector3.new(deflected.X, 0, deflected.Z)
			t.expect(horizontal.Magnitude).toBeCloseTo(40 * CUP.LipOutSpeedKeep, 1e-4)
			t.expect(math.deg(BallMath.angleBetween(horizontal, Vector3.xAxis))).toBeCloseTo(CUP.LipOutDeflectDeg, 1e-4)
		end)
	end)

	t.describe("Trajectoire prédite", function()
		t.it("suit exactement la parabole analytique sans traînée ni vent", function()
			local origin = Vector3.new(3, 10, -7)
			local velocity = Vector3.new(40, 55, -12)
			local gravity = BallMath.effectiveGravity(196.2, Gameplay.Ball.GravityScale)
			local step = 1 / 30
			local points, hit = BallMath.predictTrajectory(origin, velocity, {
				gravity = gravity,
				wind = Vector3.zero,
				drag = 0,
				step = step,
				maxTime = 2,
				maxPoints = 1000,
			})
			t.expect(hit).toBeFalsy()
			t.expect(#points).toBeGreaterThanOrEqual(60)
			for index, point in points do
				local time = math.min((index - 1) * step, 2)
				local expected = origin + velocity * time + Vector3.new(0, -0.5 * gravity * time * time, 0)
				t.expect((point - expected).Magnitude).toBeLessThan(1e-4)
			end
		end)

		t.it("s'arrête sur le sol demandé", function()
			local points, hit = BallMath.predictTrajectory(Vector3.new(0, 1, 0), Vector3.new(30, 30, 0), {
				gravity = 98.1,
				floorY = 0,
				step = 1 / 60,
				maxTime = 10,
			})
			t.expect(hit).toBeTruthy()
			t.expect(points[#points].Y).toBeCloseTo(0, 1e-4)
		end)

		t.it("raccourcit la trajectoire avec la traînée et la dévie avec le vent", function()
			local origin = Vector3.zero
			local velocity = Vector3.new(60, 40, 0)
			local params = { gravity = 98.1, step = 0.05, maxTime = 1 }
			local plain = BallMath.predictTrajectory(origin, velocity, params)
			local dragged = BallMath.predictTrajectory(origin, velocity, { gravity = 98.1, step = 0.05, maxTime = 1, drag = 0.5 })
			local windy = BallMath.predictTrajectory(origin, velocity, { gravity = 98.1, step = 0.05, maxTime = 1, wind = Vector3.new(0, 0, 10) })
			t.expect(dragged[#dragged].X).toBeLessThan(plain[#plain].X)
			t.expect(windy[#windy].Z).toBeCloseTo(0.5 * 10 * 1 * 1, 1e-4)
			-- Pas de vol serveur cohérent avec la solution exacte.
			local stepped = BallMath.airStep(velocity, Vector3.new(0, 0, 10), 0.5, 0.25)
			local exact = BallMath.velocityAt(velocity, Vector3.new(0, 0, 10), 0.5, 0.25)
			t.expect((stepped - exact).Magnitude).toBeLessThan(1e-9)
		end)
	end)

	t.describe("Roulement et rebonds", function()
		t.it("freine sans jamais inverser le sens", function()
			local velocity = Vector3.new(5, 0, 2)
			local slowed = BallMath.rollStep(velocity, 0.9, 5, 1 / 60)
			t.expect(slowed.Magnitude).toBeLessThan(velocity.Magnitude)
			t.expect(slowed:Dot(velocity)).toBeGreaterThan(0)
			t.expect(BallMath.rollStep(velocity, 5.5, 24, 1)).toBe(Vector3.zero)
			t.expect(BallMath.surfaceDragFactor(0.9, 0)).toBe(1)
		end)

		t.it("décide si la balle peut rester immobile sur une pente", function()
			local gravity = BallMath.effectiveGravity(196.2, Gameplay.Ball.GravityScale)
			local sand = Gameplay.Surfaces.Sand
			local ice = Gameplay.Surfaces.Ice
			local margin = Gameplay.Ball.RestSlopeMargin
			local gentle = Vector3.new(math.sin(math.rad(5)), math.cos(math.rad(5)), 0)
			local steep = Vector3.new(math.sin(math.rad(45)), math.cos(math.rad(45)), 0)
			t.expect(BallMath.canRestOnSlope(Vector3.yAxis, gravity, ice.RollResistance, margin)).toBeTruthy()
			t.expect(BallMath.canRestOnSlope(gentle, gravity, sand.RollResistance, margin)).toBeTruthy()
			t.expect(BallMath.canRestOnSlope(steep, gravity, ice.RollResistance, margin)).toBeFalsy()
			t.expect(BallMath.canRestOnSlope(Vector3.new(0, -1, 0), gravity, sand.RollResistance, margin)).toBeFalsy()
		end)

		t.it("réfléchit la vitesse selon l'élasticité", function()
			local reflected = BallMath.reflect(Vector3.new(10, -5, 0), Vector3.yAxis, 0.5, 0.9)
			t.expect(reflected.X).toBeCloseTo(9, 1e-9)
			t.expect(reflected.Y).toBeCloseTo(2.5, 1e-9)
			local away = Vector3.new(1, 3, 0)
			t.expect(BallMath.reflect(away, Vector3.yAxis, 0.5, 0.9)).toBe(away)
		end)
	end)

	t.describe("Guidage et verrouillage", function()
		t.it("ne tourne jamais plus vite que la limite et conserve la vitesse", function()
			local maxRate = math.rad(Gameplay.Guided.MaxTurnRateDeg)
			local dt = 1 / 60
			local velocity = Vector3.new(100, 10, 0)
			local position = Vector3.zero
			local target = Vector3.new(-50, 0, 80)
			for frame = 1, 240 do
				target += Vector3.new(math.sin(frame * 0.1) * 2, 0, math.cos(frame * 0.07) * 2)
				local nextVelocity = BallMath.homingStep(velocity, target - position, maxRate, dt)
				t.expect(BallMath.angleBetween(velocity, nextVelocity)).toBeLessThanOrEqual(maxRate * dt + 1e-4)
				t.expect(nextVelocity.Magnitude).toBeCloseTo(velocity.Magnitude, 1e-4)
				velocity = nextVelocity
				position += velocity * dt
			end
		end)

		t.it("tourne de la limite même face à une cible exactement opposée", function()
			local maxRate = math.rad(90)
			local turned = BallMath.homingStep(Vector3.new(0, 0, 50), Vector3.new(0, 0, -10), maxRate, 0.1)
			t.expect(BallMath.angleBetween(Vector3.new(0, 0, 50), turned)).toBeCloseTo(maxRate * 0.1, 1e-4)
			t.expect(turned.Magnitude).toBeCloseTo(50, 1e-4)
		end)

		t.it("s'aligne directement quand l'écart est sous la limite", function()
			local turned = BallMath.homingStep(Vector3.new(30, 0, 0), Vector3.new(10, 0.1, 0), math.rad(120), 1 / 60)
			t.expect(BallMath.angleBetween(turned, Vector3.new(10, 0.1, 0))).toBeLessThan(1e-4)
		end)

		t.it("choisit la cible valide la plus centrée", function()
			local guided = Gameplay.Guided
			local rules: BallMath.LockRules = {
				range = guided.LockRange,
				minDistance = guided.LockMinDistance,
				coneDeg = guided.LockConeDeg,
				maxVerticalOffset = guided.MaxVerticalOffset,
				angleWeight = guided.AngleWeight,
			}
			local origin = Vector3.zero
			local forward = Vector3.new(1, 0, 0)
			local candidates: { BallMath.LockCandidate } = {
				{ position = Vector3.new(30, 0, 12), eligible = true, lineOfSight = true }, -- dans le cône, décentré
				{ position = Vector3.new(40, 1, 1), eligible = true, lineOfSight = true }, -- le plus centré
				{ position = Vector3.new(20, 0, 0), eligible = false, lineOfSight = true }, -- protégé / allié
				{ position = Vector3.new(25, 0, 0), eligible = true, lineOfSight = false }, -- derrière un mur
				{ position = Vector3.new(2, 0, 0), eligible = true, lineOfSight = true }, -- trop proche
				{ position = Vector3.new(0, 0, 30), eligible = true, lineOfSight = true }, -- hors du cône
				{ position = Vector3.new(500, 0, 0), eligible = true, lineOfSight = true }, -- hors de portée
			}
			local index = BallMath.pickLockTarget(origin, forward, candidates, rules)
			t.expect(index).toBe(2)
			local none = BallMath.pickLockTarget(origin, Vector3.new(-1, 0, 0), candidates, rules)
			t.expect(none).toBeNil()
		end)

		t.it("teste les cônes et les rotations horizontales", function()
			local inside = BallMath.coneCheck(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(1, 3, -5), 30, 10, true)
			local outside = BallMath.coneCheck(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(5, 0, -1), 30, 10, true)
			t.expect(inside).toBeTruthy()
			t.expect(outside).toBeFalsy()
			local rotated = BallMath.rotateAroundY(Vector3.new(1, 2, 0), math.rad(90))
			t.expect((rotated - Vector3.new(0, 2, -1)).Magnitude).toBeLessThan(1e-9)
		end)
	end)
end
