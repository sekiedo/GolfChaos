--!strict
--[[
	Logic.ItemGeometry — géométrie pure des objets (cônes, rayons, orientation), sans Workspace ni raycast.
	Le décor (lignes de vue) est géré par ItemService ; ici seulement les mathématiques.

	  ItemGeometry.flat(v) -> Vector3                       composante verticale retirée
	  ItemGeometry.inCone(origin, forward, point, halfAngleDeg, range) -> boolean
	  ItemGeometry.facing(from, to, forward, minDot) -> boolean      `forward` regarde-t-il vers `to` ?
	  ItemGeometry.rayDistance(origin, dir, point) -> (t, perpendiculaire)   dir unitaire ; t peut être négatif
	  ItemGeometry.rayHitsSphere(origin, dir, center, radius, maxDistance) -> t?   première intersection
	  ItemGeometry.sortAlongRay(origin, dir, points, radius, maxDistance) -> { { index, t } }   triés par t
	  ItemGeometry.knockDirection(from, to) -> Vector3       direction horizontale de l'attaquant vers la victime
	  ItemGeometry.falloff(distance, full, max) -> 1..0      1 jusqu'à `full`, décroît linéairement jusqu'à `max`
	  ItemGeometry.bestPlaced(candidates, excludeId?) -> id? plus petite distance restante (candidats {id, remaining})
]]

local ItemGeometry = {}

function ItemGeometry.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function ItemGeometry.inCone(origin: Vector3, forward: Vector3, point: Vector3, halfAngleDeg: number, range: number): boolean
	local offset = point - origin
	local distance = offset.Magnitude
	if distance > range then
		return false
	end
	if distance < 1e-3 then
		return true
	end
	if forward.Magnitude < 1e-6 then
		return false
	end
	local cosine = offset.Unit:Dot(forward.Unit)
	return cosine >= math.cos(math.rad(halfAngleDeg))
end

function ItemGeometry.facing(from: Vector3, to: Vector3, forward: Vector3, minDot: number): boolean
	local toward = to - from
	if toward.Magnitude < 1e-3 or forward.Magnitude < 1e-6 then
		return true
	end
	return toward.Unit:Dot(forward.Unit) >= minDot
end

function ItemGeometry.rayDistance(origin: Vector3, dir: Vector3, point: Vector3): (number, number)
	local offset = point - origin
	local t = offset:Dot(dir)
	local closest = origin + dir * t
	return t, (point - closest).Magnitude
end

function ItemGeometry.rayHitsSphere(origin: Vector3, dir: Vector3, center: Vector3, radius: number, maxDistance: number): number?
	local t, perpendicular = ItemGeometry.rayDistance(origin, dir, center)
	if perpendicular > radius then
		return nil
	end
	local half = math.sqrt(math.max(0, radius * radius - perpendicular * perpendicular))
	local entry = t - half
	local hit = if entry >= 0 then entry elseif t + half >= 0 then 0 else nil
	if hit == nil or hit > maxDistance then
		return nil
	end
	return hit
end

function ItemGeometry.sortAlongRay(origin: Vector3, dir: Vector3, points: { Vector3 }, radius: number, maxDistance: number): { { index: number, t: number } }
	local hits: { { index: number, t: number } } = {}
	for index, point in points do
		local t = ItemGeometry.rayHitsSphere(origin, dir, point, radius, maxDistance)
		if t then
			table.insert(hits, { index = index, t = t })
		end
	end
	table.sort(hits, function(a, b)
		return a.t < b.t
	end)
	return hits
end

function ItemGeometry.knockDirection(from: Vector3, to: Vector3): Vector3
	local flat = ItemGeometry.flat(to - from)
	if flat.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

function ItemGeometry.falloff(distance: number, full: number, max: number): number
	if distance <= full then
		return 1
	end
	if distance >= max or max <= full then
		return 0
	end
	return 1 - (distance - full) / (max - full)
end

function ItemGeometry.bestPlaced(candidates: { { id: any, remaining: number } }, excludeId: any?): any?
	local best: any? = nil
	local bestRemaining = math.huge
	for _, candidate in candidates do
		if candidate.id ~= excludeId and candidate.remaining < bestRemaining then
			best = candidate.id
			bestRemaining = candidate.remaining
		end
	end
	return best
end

return ItemGeometry
