--!strict
--[[
	Course.PathMath — géométrie pure de CourseService (zones de danger, progression le long du chemin, listes
	défensives). Extrait de CourseService sans changement de comportement ; aucun état, aucun service.

	  zoneContains(zone, point) / inAnyZone(zones, point)
	  progressAlong(points, cumulative, position) -> studs le long de la polyligne
	  cumulativeLengths(points) -> (cumul, total)
	  inBox(position, bounds, margin) (plan horizontal)
	  vectorList(value) / cframeList(value) : listes filtrées des valeurs finies
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Validate = require(Shared.Util.Validate)

local PathMath = {}

export type Bounds = { min: Vector3, max: Vector3 }

export type Zone = {
	kind: string,
	shape: "box" | "cylinder",
	cframe: CFrame,
	size: Vector3,
}

function PathMath.zoneContains(zone: Zone, point: Vector3): boolean
	local localPoint = zone.cframe:PointToObjectSpace(point)
	local size = zone.size
	if zone.shape == "cylinder" then
		local radius = size.X / 2
		return localPoint.X * localPoint.X + localPoint.Z * localPoint.Z <= radius * radius
			and math.abs(localPoint.Y) <= size.Y / 2
	end
	return math.abs(localPoint.X) <= size.X / 2
		and math.abs(localPoint.Y) <= size.Y / 2
		and math.abs(localPoint.Z) <= size.Z / 2
end

function PathMath.inAnyZone(zones: { Zone }, point: Vector3): boolean
	for _, zone in zones do
		if PathMath.zoneContains(zone, point) then
			return true
		end
	end
	return false
end

-- Progression (studs) du point le plus proche de la polyligne.
function PathMath.progressAlong(points: { Vector3 }, cumulative: { number }, position: Vector3): number
	local count = #points
	if count == 0 then
		return 0
	end
	if count == 1 then
		return 0
	end
	local bestDistance = math.huge
	local bestProgress = 0
	for index = 1, count - 1 do
		local a = points[index]
		local b = points[index + 1]
		local segment = b - a
		local lengthSquared = segment:Dot(segment)
		local t = 0
		if lengthSquared > 1e-6 then
			t = math.clamp((position - a):Dot(segment) / lengthSquared, 0, 1)
		end
		local closest = a + segment * t
		local distance = (position - closest).Magnitude
		if distance < bestDistance then
			bestDistance = distance
			bestProgress = cumulative[index] + math.sqrt(lengthSquared) * t
		end
	end
	return bestProgress
end

function PathMath.inBox(position: Vector3, bounds: Bounds, margin: number): boolean
	return position.X >= bounds.min.X - margin
		and position.X <= bounds.max.X + margin
		and position.Z >= bounds.min.Z - margin
		and position.Z <= bounds.max.Z + margin
end

function PathMath.vectorList(value: any): { Vector3 }
	local list: { Vector3 } = {}
	if type(value) == "table" then
		for _, item in value do
			if Validate.isFiniteVector3(item) then
				table.insert(list, item)
			end
		end
	end
	return list
end

function PathMath.cframeList(value: any): { CFrame }
	local list: { CFrame } = {}
	if type(value) == "table" then
		for _, item in value do
			if Validate.isFiniteCFrame(item) then
				table.insert(list, item)
			end
		end
	end
	return list
end

function PathMath.cumulativeLengths(points: { Vector3 }): ({ number }, number)
	local cumulative: { number } = {}
	local total = 0
	for index, point in points do
		if index > 1 then
			total += (point - points[index - 1]).Magnitude
		end
		cumulative[index] = total
	end
	return cumulative, total
end

return PathMath
