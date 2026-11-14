--!strict
--[[
	Vehicle.KartBody — habillage visuel du kart-caddie (aucun asset, pièces procédurales).

	  KartBody.dress(model, chassis, color, size) -> Rig
	  KartBody.animate(rig, speed, steer, dt)     roule les 4 roues et braque les roues avant + le volant

	Toutes les pièces sont décoratives : Massless, sans collision ni requête. Les roues et le volant sont
	fixés par des Weld dont C0 est mis à jour pour l'animation. Avant du kart = -Z du châssis.
]]

local KartBody = {}

export type Wheel = { weld: Weld, position: Vector3, front: boolean, roll: number }
export type Rig = { wheels: { Wheel }, steering: Weld?, steeringBase: CFrame }

local WHEEL_RADIUS = 1.0
local WHEEL_WIDTH = 0.9
local MAX_STEER = 0.45

local function make(model: Instance, chassis: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CFrame = chassis.CFrame * offset
	p.Parent = model
	return p
end

local function deco(model: Instance, chassis: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = make(model, chassis, name, size, offset, color, material, shape)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = chassis
	weld.Part1 = p
	weld.Parent = p
	return p
end

local function movable(model: Instance, chassis: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): (Part, Weld)
	local p = make(model, chassis, name, size, offset, color, material, shape)
	local weld = Instance.new("Weld")
	weld.Part0 = chassis
	weld.Part1 = p
	weld.C0 = offset
	weld.Parent = p
	return p, weld
end

local function attach(parent: Part, child: Part)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = parent
	weld.Part1 = child
	weld.Parent = child
end

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- un cylindre Roblox a son axe sur X : on le redresse

function KartBody.dress(model: Instance, chassis: BasePart, color: Color3, size: Vector3): Rig
	local half = size / 2
	local top = half.Y
	local white = Color3.fromRGB(250, 248, 242)
	local dark = Color3.fromRGB(40, 40, 50)
	local bag = Color3.fromRGB(60, 130, 90)

	-- Carrosserie : capot, calandre, pare-chocs, bandeau blanc, ailes, marchepieds, phares.
	deco(model, chassis, "Capot", Vector3.new(size.X - 1, 1, 3.6), CFrame.new(0, top + 0.4, -half.Z + 2), color, Enum.Material.SmoothPlastic)
	deco(model, chassis, "Calandre", Vector3.new(size.X - 2, 1.2, 0.4), CFrame.new(0, 0.2, -half.Z - 0.1), white, Enum.Material.Metal)
	deco(model, chassis, "PareChocsAvant", Vector3.new(size.X + 0.4, 0.7, 0.9), CFrame.new(0, -half.Y + 0.6, -half.Z - 0.3), dark, Enum.Material.SmoothPlastic)
	deco(model, chassis, "PareChocsArriere", Vector3.new(size.X + 0.4, 0.7, 0.9), CFrame.new(0, -half.Y + 0.6, half.Z + 0.3), dark, Enum.Material.SmoothPlastic)
	deco(model, chassis, "Bandeau", Vector3.new(size.X + 0.1, 0.4, size.Z - 0.4), CFrame.new(0, 0.1, 0), white, Enum.Material.SmoothPlastic)
	deco(model, chassis, "Plancher", Vector3.new(size.X - 0.6, 0.3, size.Z - 2), CFrame.new(0, top + 0.15, 0), Color3.fromRGB(80, 84, 96), Enum.Material.Metal)
	for _, side in { -1, 1 } do
		deco(model, chassis, "Phare", Vector3.new(1.2, 1.2, 0.6), CFrame.new(side * (half.X - 1), 0.4, -half.Z - 0.3), Color3.fromRGB(255, 244, 190), Enum.Material.Neon, Enum.PartType.Ball)
		deco(model, chassis, "FeuArriere", Vector3.new(1, 0.6, 0.4), CFrame.new(side * (half.X - 0.8), 0.4, half.Z + 0.1), Color3.fromRGB(240, 60, 60), Enum.Material.Neon)
		for _, z in { -3.8, 3.8 } do
			deco(model, chassis, "Aile", Vector3.new(1.4, 0.4, 3.4), CFrame.new(side * (half.X + 0.4), WHEEL_RADIUS + 0.55, z), color, Enum.Material.SmoothPlastic)
		end
		deco(model, chassis, "Marchepied", Vector3.new(0.9, 0.3, 5), CFrame.new(side * (half.X + 0.4), -half.Y + 0.5, 0), dark, Enum.Material.Metal)
	end

	-- Dossiers de banquette et sacs de golf à l'arrière, clubs qui dépassent.
	for _, z in { -2.5, 0.5, 3.5 } do
		deco(model, chassis, "Dossier", Vector3.new(size.X - 1.4, 1.6, 0.5), CFrame.new(0, top + 1.8, z + 1.3), Color3.fromRGB(46, 50, 64), Enum.Material.Fabric)
	end
	for index, x in { -1.8, 0, 1.8 } do
		local lean = CFrame.Angles(math.rad(-12), 0, 0)
		deco(model, chassis, "SacGolf", Vector3.new(3.6, 1.3, 1.3), CFrame.new(x, top + 2, half.Z - 0.3) * lean * UPRIGHT, bag, Enum.Material.Fabric, Enum.PartType.Cylinder)
		for club = 1, 3 do
			deco(model, chassis, "ClubDepasse", Vector3.new(0.15, 1.6, 0.15), CFrame.new(x + (club - 2) * 0.3, top + 4.2 + (index % 2) * 0.2, half.Z - 0.6) * lean * CFrame.Angles(0, 0, math.rad((club - 2) * 8)), Color3.fromRGB(210, 214, 224), Enum.Material.Metal)
		end
	end

	-- Toit rayé sur quatre montants.
	local roofY = top + 5.6
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			deco(model, chassis, "Montant", Vector3.new(0.4, 5.2, 0.4), CFrame.new(sx * (half.X - 0.4), top + 2.8, sz * (half.Z - 2.2)), dark, Enum.Material.Metal)
		end
	end
	for index = 1, 7 do
		deco(model, chassis, "Toit", Vector3.new(size.X / 7 + 0.05, 0.35, size.Z - 3), CFrame.new(-size.X / 2 + (index - 0.5) * size.X / 7, roofY, 0), if index % 2 == 0 then white else color, Enum.Material.Fabric)
	end

	-- Volant (tourne avec la direction), devant le conducteur (siège en x = -1.6, z = -2.5).
	local steeringBase = CFrame.new(-1.6, top + 2.3, -half.Z + 1.4) * CFrame.Angles(math.rad(-65), 0, 0) * UPRIGHT
	local _, steeringWeld = movable(model, chassis, "Volant", Vector3.new(0.3, 1.6, 1.6), steeringBase, dark, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	deco(model, chassis, "Colonne", Vector3.new(0.3, 0.3, 1.8), CFrame.new(-1.6, top + 1.6, -half.Z + 1.8) * CFrame.Angles(math.rad(-25), 0, 0), dark, Enum.Material.Metal)

	-- Roues : pneu sombre, enjoliveur clair et rayon coloré (visible quand la roue tourne).
	local wheels: { Wheel } = {}
	local wheelZ = half.Z - 2.4
	for _, side in { -1, 1 } do
		for _, front in { true, false } do
			local position = Vector3.new(side * (half.X + 0.6), 0, if front then -wheelZ else wheelZ)
			local tire, weld = movable(model, chassis, "Roue", Vector3.new(WHEEL_WIDTH, WHEEL_RADIUS * 2, WHEEL_RADIUS * 2), CFrame.new(position), Color3.fromRGB(30, 30, 36), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
			local hub = make(tire, chassis, "Enjoliveur", Vector3.new(WHEEL_WIDTH + 0.1, WHEEL_RADIUS * 1.1, WHEEL_RADIUS * 1.1), CFrame.new(position), Color3.fromRGB(230, 232, 238), Enum.Material.Metal, Enum.PartType.Cylinder)
			attach(tire, hub)
			local bar = make(tire, chassis, "Rayon", Vector3.new(WHEEL_WIDTH + 0.15, 0.25, WHEEL_RADIUS * 1.7), CFrame.new(position), color, Enum.Material.SmoothPlastic)
			attach(tire, bar)
			table.insert(wheels, { weld = weld, position = position, front = front, roll = 0 })
		end
	end
	return { wheels = wheels, steering = steeringWeld, steeringBase = steeringBase }
end

function KartBody.animate(rig: Rig, speed: number, steer: number, dt: number)
	local yaw = -steer * MAX_STEER
	for _, wheel in rig.wheels do
		wheel.roll = (wheel.roll - speed * dt / WHEEL_RADIUS) % (math.pi * 2)
		local rotation = CFrame.Angles(wheel.roll, 0, 0)
		if wheel.front then
			rotation = CFrame.Angles(0, yaw, 0) * rotation
		end
		wheel.weld.C0 = CFrame.new(wheel.position) * rotation
	end
	if rig.steering then
		rig.steering.C0 = rig.steeringBase * CFrame.Angles(0, -steer * 1.6, 0)
	end
end

return KartBody
