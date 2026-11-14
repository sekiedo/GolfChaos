--!strict
--[[
	Logic/HoleValidator : validation PURE d'un Types.HoleDef (aucun service moteur ; calculs Vector3/CFrame).
	Règles : docs/FORMAT_TROUS.md §11. Réglages : Config/Course (Path, Green, Tee, Validation...).

	  local result = HoleValidator.validate(def)
	  -- result = { ok, errors = { string }, warnings = { string },
	  --            metrics = { pathLength, maxSlopeDeg, maxGap, nodeCount, elevation, turnCount, maxTurnDeg } }
	  local summary = HoleValidator.validateAll(Holes.all())
	  -- summary = { ok, total, failed, errorCount, warningCount, duplicates, results = { [id] = result },
	  --             messages = { "COT-01 : ..." } }

	Outils géométriques partagés (utilisés aussi par server/Course/HoleBuilder, coordonnées LOCALES du trou) :
	  HoleValidator.nodeKind(node), nodeWidth(node), nodeSurface(node)
	  HoleValidator.pathLength(path), segmentSlopeDeg(a, b), horizontal(v)
	  HoleValidator.pointAtDistance(path, d) -> (position, directionHorizontale, indexSegment)
	  HoleValidator.distanceToPath(path, point) -> (distanceHorizontaleAuCentre, indexSegment, t, abscisse, largeur)
	  HoleValidator.greenSurfaceY(def, point) -> altitude du green (inclinaison comprise)
	  HoleValidator.estimateTime(def, pathLength) -> secondes
]]

local Types = require(script.Parent.Parent.Types)
local Course = require(script.Parent.Parent.Config.Course)

type HoleDef = Types.HoleDef
type PathNode = Types.PathNode

export type Metrics = {
	pathLength: number,
	maxSlopeDeg: number,
	maxGap: number,
	nodeCount: number,
	elevation: number, -- dénivelé total (max - min des nœuds)
	turnCount: number, -- virages de plus de 20°
	maxTurnDeg: number,
}

export type Result = {
	ok: boolean,
	errors: { string },
	warnings: { string },
	metrics: Metrics,
}

export type Summary = {
	ok: boolean,
	total: number,
	failed: number,
	errorCount: number,
	warningCount: number,
	duplicates: { string },
	results: { [string]: Result },
	messages: { string },
}

local HoleValidator = {}

local PATH = Course.Path
local GREEN = Course.Green
local TEE = Course.Tee
local VALID = Course.Validation

-- Liste fermée des obstacles reconnus (doit correspondre à server/Course/Obstacles.luau).
HoleValidator.ObstacleKinds = table.clone(Course.ObstacleKinds)

local function toSet(list: { string }): { [string]: boolean }
	local set = {}
	for _, value in list do
		set[value] = true
	end
	return set
end

local OBSTACLE_SET = toSet(Course.ObstacleKinds)
local PROP_SET = toSet(Course.PropKinds)
local SURFACE_SET = toSet(Course.Surfaces)
local KIND_SET = toSet(Course.SegmentKinds)
local HAZARD_SET = toSet(Course.HazardKinds)
local BIOME_SET = toSet(Course.Biomes)

--------------------------------------------------------------------------------
-- Outils numériques
--------------------------------------------------------------------------------

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isFiniteVector(value: any): boolean
	return typeof(value) == "Vector3" and isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)
end

local function isInteger(value: any): boolean
	return isFiniteNumber(value) and math.floor(value) == value
end

local function fmt(v: Vector3): string
	return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
end

function HoleValidator.horizontal(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local horizontal = HoleValidator.horizontal

--------------------------------------------------------------------------------
-- Nœuds et segments
--------------------------------------------------------------------------------

function HoleValidator.nodeKind(node: PathNode): string
	return node.kind or "ground"
end

function HoleValidator.nodeWidth(node: PathNode): number
	if node.w ~= nil then
		return node.w
	end
	local kind = node.kind or "ground"
	if kind == "bridge" or kind == "tunnel" then
		return PATH.BridgeDefaultWidth
	end
	return PATH.DefaultWidth
end

function HoleValidator.nodeSurface(node: PathNode): string
	if node.kind == "ice" then
		return "Ice"
	end
	return node.surface or "Fairway"
end

function HoleValidator.segmentSlopeDeg(a: Vector3, b: Vector3): number
	local run = horizontal(b - a).Magnitude
	local rise = math.abs(b.Y - a.Y)
	if run < 1e-6 then
		return if rise < 1e-6 then 0 else 90
	end
	return math.deg(math.atan(rise / run))
end

function HoleValidator.pathLength(path: { PathNode }): number
	local total = 0
	for index = 1, #path - 1 do
		total += (path[index + 1].p - path[index].p).Magnitude
	end
	return total
end

-- Point situé à la distance `d` le long du chemin (longueur 3D), direction horizontale du segment.
function HoleValidator.pointAtDistance(path: { PathNode }, d: number): (Vector3, Vector3, number)
	local remaining = math.max(d, 0)
	for index = 1, #path - 1 do
		local a, b = path[index].p, path[index + 1].p
		local length = (b - a).Magnitude
		local flat = horizontal(b - a)
		local dir = if flat.Magnitude > 1e-6 then flat.Unit else Vector3.new(0, 0, 1)
		if remaining <= length or index == #path - 1 then
			local t = if length > 1e-6 then math.clamp(remaining / length, 0, 1) else 0
			return a:Lerp(b, t), dir, index
		end
		remaining -= length
	end
	local only = path[1].p
	return only, Vector3.new(0, 0, 1), 1
end

-- Distance horizontale d'un point à la ligne centrale. Retourne aussi le segment, le paramètre t, l'abscisse
-- curviligne (longueur 3D depuis le départ) et la largeur interpolée du chemin à cet endroit.
function HoleValidator.distanceToPath(path: { PathNode }, point: Vector3): (number, number, number, number, number)
	local best, bestIndex, bestT, bestAlong, bestWidth = math.huge, 1, 0, 0, HoleValidator.nodeWidth(path[1])
	local along = 0
	local flatPoint = horizontal(point)
	for index = 1, #path - 1 do
		local a, b = path[index].p, path[index + 1].p
		local fa, fb = horizontal(a), horizontal(b)
		local ab = fb - fa
		local lengthSq = ab:Dot(ab)
		local t = if lengthSq > 1e-9 then math.clamp((flatPoint - fa):Dot(ab) / lengthSq, 0, 1) else 0
		local distance = (flatPoint - (fa + ab * t)).Magnitude
		local segLength = (b - a).Magnitude
		if distance < best then
			best, bestIndex, bestT = distance, index, t
			bestAlong = along + segLength * t
			local wa = HoleValidator.nodeWidth(path[index])
			local wb = HoleValidator.nodeWidth(path[index + 1])
			-- La largeur d'un segment suit celle de ses deux nœuds (pont : largeur du nœud de départ).
			local kind = HoleValidator.nodeKind(path[index])
			if kind == "bridge" or kind == "tunnel" then
				wb = wa
			end
			bestWidth = wa + (wb - wa) * t
		end
		along += segLength
	end
	return best, bestIndex, bestT, bestAlong, bestWidth
end

-- Normale du green (inclinaison `green.tilt` = degrés autour de X et de Z).
local function greenNormal(def: HoleDef): Vector3
	local tilt = def.green and def.green.tilt
	if tilt == nil or not isFiniteVector(tilt) then
		return Vector3.yAxis
	end
	return CFrame.Angles(math.rad(tilt.X), 0, math.rad(tilt.Z)).UpVector
end

HoleValidator.greenNormal = greenNormal

-- Altitude du dessus du green (hors léger relief Green.Raise) au droit de `point`.
function HoleValidator.greenSurfaceY(def: HoleDef, point: Vector3): number
	local center = def.path[#def.path].p
	local n = greenNormal(def)
	local offset = point - center
	return center.Y - (n.X * offset.X + n.Z * offset.Z) / n.Y
end

function HoleValidator.greenRadius(def: HoleDef): number
	return (def.green and def.green.radius) or GREEN.DefaultRadius
end

function HoleValidator.estimateTime(def: HoleDef, pathLength: number): number
	return pathLength * VALID.WanderFactor / VALID.WalkSpeed + (def.par + VALID.ExtraShots) * VALID.SecondsPerShot
end

-- Point dans un volume de danger (marge facultative), en coordonnées locales.
function HoleValidator.pointInHazard(hazard: Types.HazardDef, point: Vector3, margin: number?): boolean
	local m = margin or 0
	local offset = point - hazard.center
	if (hazard.shape or "box") == "cylinder" then
		local radius = hazard.size.X / 2 + m
		return horizontal(offset).Magnitude <= radius and math.abs(offset.Y) <= hazard.size.Y / 2 + m
	end
	local yaw = math.rad(hazard.yaw or 0)
	local localOffset = CFrame.Angles(0, -yaw, 0) * offset
	return math.abs(localOffset.X) <= hazard.size.X / 2 + m
		and math.abs(localOffset.Y) <= hazard.size.Y / 2 + m
		and math.abs(localOffset.Z) <= hazard.size.Z / 2 + m
end

--------------------------------------------------------------------------------
-- Validation d'un trou
--------------------------------------------------------------------------------

local function emptyMetrics(): Metrics
	return { pathLength = 0, maxSlopeDeg = 0, maxGap = 0, nodeCount = 0, elevation = 0, turnCount = 0, maxTurnDeg = 0 }
end

function HoleValidator.validate(def: HoleDef): Result
	local errors: { string } = {}
	local warnings: { string } = {}
	local metrics = emptyMetrics()

	local function err(message: string, ...: any)
		table.insert(errors, string.format(message, ...))
	end
	local function warn(message: string, ...: any)
		table.insert(warnings, string.format(message, ...))
	end

	if type(def) ~= "table" then
		err("définition absente ou invalide")
		return { ok = false, errors = errors, warnings = warnings, metrics = metrics }
	end
	local raw = def :: any

	-- Identité ---------------------------------------------------------------
	if type(raw.id) ~= "string" then
		err("id manquant")
	else
		local prefix = string.match(raw.id, VALID.IdPattern)
		if prefix == nil then
			err("id %q : format attendu PPP-NN (ex. COT-07)", raw.id)
		else
			local expected = Course.IdPrefixes[prefix]
			if expected == nil then
				err("id %q : préfixe inconnu (COT, FOR, DES, NEI, VIL, ENT)", raw.id)
			elseif expected ~= raw.biome then
				err("id %q : le préfixe %s impose le biome %s (trouvé %s)", raw.id, prefix, expected, tostring(raw.biome))
			end
		end
	end
	if type(raw.name) ~= "string" or #raw.name == 0 then
		err("name manquant")
	end
	if type(raw.feature) ~= "string" or #raw.feature == 0 then
		err("feature manquante")
	end
	if not BIOME_SET[raw.biome] then
		err("biome inconnu %s", tostring(raw.biome))
	end
	if not isInteger(raw.par) or raw.par < VALID.ParMin or raw.par > VALID.ParMax then
		err("par %s hors de %d..%d", tostring(raw.par), VALID.ParMin, VALID.ParMax)
	end
	if not isInteger(raw.difficulty) or raw.difficulty < VALID.DifficultyMin or raw.difficulty > VALID.DifficultyMax then
		err("difficulty %s hors de %d..%d", tostring(raw.difficulty), VALID.DifficultyMin, VALID.DifficultyMax)
	end
	if not isFiniteNumber(raw.targetTime) or raw.targetTime <= 0 then
		err("targetTime doit être un nombre > 0")
	elseif raw.targetTime < VALID.MinTargetTime or raw.targetTime > VALID.MaxTargetTime then
		warn("targetTime %.0f s hors de la plage conseillée %d..%d", raw.targetTime, VALID.MinTargetTime, VALID.MaxTargetTime)
	end
	if not isFiniteNumber(raw.seed) then
		err("seed doit être un nombre")
	end

	-- Chemin -----------------------------------------------------------------
	local path = raw.path
	if type(path) ~= "table" or #path < 2 then
		err("path doit contenir au moins 2 nœuds")
		return { ok = false, errors = errors, warnings = warnings, metrics = metrics }
	end
	metrics.nodeCount = #path
	if #path > PATH.MaxNodes then
		err("path : %d nœuds (maximum %d)", #path, PATH.MaxNodes)
	end
	for index, node in path do
		if type(node) ~= "table" or not isFiniteVector(node.p) then
			err("path[%d] : position p invalide", index)
			return { ok = false, errors = errors, warnings = warnings, metrics = metrics }
		end
		if node.w ~= nil and (not isFiniteNumber(node.w) or node.w <= 0 or node.w > PATH.MaxWidth) then
			err("path[%d] : largeur w %s invalide (0..%d)", index, tostring(node.w), PATH.MaxWidth)
		end
		if node.surface ~= nil and not SURFACE_SET[node.surface] then
			err("path[%d] : surface inconnue %s", index, tostring(node.surface))
		end
		if node.kind ~= nil and not KIND_SET[node.kind] then
			err("path[%d] : kind inconnu %s", index, tostring(node.kind))
		end
	end

	local minY, maxY = math.huge, -math.huge
	for _, node in path do
		minY = math.min(minY, node.p.Y)
		maxY = math.max(maxY, node.p.Y)
	end
	metrics.elevation = maxY - minY
	metrics.pathLength = HoleValidator.pathLength(path)

	for index = 1, #path - 1 do
		local node, nextNode = path[index], path[index + 1]
		local a, b = node.p, nextNode.p
		local kind = HoleValidator.nodeKind(node)
		local run = horizontal(b - a).Magnitude
		local segLength = (b - a).Magnitude
		if segLength < PATH.MinSegmentLength then
			err("path[%d]→[%d] : nœuds trop proches (%.2f studs)", index, index + 1, segLength)
		end
		local width = HoleValidator.nodeWidth(node)
		if kind == "bridge" or kind == "tunnel" then
			if width < PATH.MinBridgeWidth then
				err("path[%d] : %s trop étroit (%.1f < %d)", index, kind, width, PATH.MinBridgeWidth)
			end
		elseif kind ~= "gap" then
			if width < PATH.MinWidth then
				err("path[%d] : largeur %.1f < %d (minimum hors ponts et tunnels)", index, width, PATH.MinWidth)
			elseif width < PATH.NarrowWidth then
				warn("path[%d] : segment étroit (%.1f studs)", index, width)
			end
		end
		if kind == "gap" then
			metrics.maxGap = math.max(metrics.maxGap, run)
			if run > PATH.MaxGap then
				err("path[%d] : trou de %.1f studs > %d (le chemin principal doit rester praticable sans objet)", index, run, PATH.MaxGap)
			end
			if b.Y - a.Y > PATH.MaxGapRise then
				err("path[%d] : le trou monte de %.1f studs (maximum %.1f)", index, b.Y - a.Y, PATH.MaxGapRise)
			end
			if index == 1 or index == #path - 1 then
				err("path[%d] : un segment gap ne peut ni partir du départ ni arriver au green", index)
			end
		else
			local slope = HoleValidator.segmentSlopeDeg(a, b)
			metrics.maxSlopeDeg = math.max(metrics.maxSlopeDeg, slope)
			if slope > PATH.MaxSlopeDeg + 1e-6 then
				err("path[%d]→[%d] : pente %.1f° > %d°", index, index + 1, slope, PATH.MaxSlopeDeg)
			end
		end
	end

	-- Virages et pentes combinés.
	for index = 2, #path - 1 do
		local before = horizontal(path[index].p - path[index - 1].p)
		local after = horizontal(path[index + 1].p - path[index].p)
		if before.Magnitude > 1e-6 and after.Magnitude > 1e-6 then
			local turn = math.deg(math.acos(math.clamp(before.Unit:Dot(after.Unit), -1, 1)))
			metrics.maxTurnDeg = math.max(metrics.maxTurnDeg, turn)
			if turn > 20 then
				metrics.turnCount += 1
			end
			local slope = math.max(
				HoleValidator.segmentSlopeDeg(path[index - 1].p, path[index].p),
				HoleValidator.segmentSlopeDeg(path[index].p, path[index + 1].p)
			)
			if turn > PATH.TurnSlopeWarnTurnDeg and slope > PATH.TurnSlopeWarnSlopeDeg then
				warn("path[%d] : virage de %.0f° sur une pente de %.0f° (jointure imparfaite : aplanir le nœud)", index, turn, slope)
			end
			if turn > 100 then
				warn("path[%d] : virage très serré (%.0f°)", index, turn)
			end
		end
	end

	-- Entrée du green.
	local last = path[#path]
	local beforeLast = path[#path - 1]
	if HoleValidator.segmentSlopeDeg(beforeLast.p, last.p) > PATH.GreenApproachMaxSlopeDeg then
		warn("dernier segment pentu (%.1f°) : ajouter un nœud plat à l'entrée du green", HoleValidator.segmentSlopeDeg(beforeLast.p, last.p))
	end

	-- Longueur et durée cible.
	if isInteger(raw.par) and not VALID.LengthExempt[raw.id] then
		local range = VALID.ParLength[raw.par]
		if range and (metrics.pathLength < range[1] or metrics.pathLength > range[2]) then
			warn("longueur %.0f studs hors de la plage du par %d (%d..%d)", metrics.pathLength, raw.par, range[1], range[2])
		end
	end
	if isFiniteNumber(raw.targetTime) and raw.targetTime > 0 and isInteger(raw.par) then
		local estimate = HoleValidator.estimateTime(def, metrics.pathLength)
		local ratio = raw.targetTime / estimate
		if ratio < VALID.TargetTimeWarnLow or ratio > VALID.TargetTimeWarnHigh then
			warn("targetTime %.0f s éloigné de l'estimation %.0f s", raw.targetTime, estimate)
		end
	end

	-- Green et trou.
	local radius = HoleValidator.greenRadius(def)
	if raw.green ~= nil then
		if type(raw.green) ~= "table" or not isFiniteNumber(raw.green.radius) then
			err("green : rayon invalide")
		elseif raw.green.radius < GREEN.MinRadius or raw.green.radius > GREEN.MaxRadius then
			err("green : rayon %.1f hors de %d..%d", raw.green.radius, GREEN.MinRadius, GREEN.MaxRadius)
		end
		if raw.green.tilt ~= nil then
			if not isFiniteVector(raw.green.tilt) then
				err("green.tilt invalide")
			else
				local tiltDeg = math.deg(math.acos(math.clamp(greenNormal(def).Y, -1, 1)))
				if tiltDeg > GREEN.MaxTiltErrorDeg then
					err("green incliné de %.1f° (maximum %.1f°)", tiltDeg, GREEN.MaxTiltErrorDeg)
				elseif tiltDeg > GREEN.MaxTiltDeg then
					warn("green incliné de %.1f° : la balle risque de ne pas s'arrêter", tiltDeg)
				end
			end
		end
	end
	if not isFiniteVector(raw.cup) then
		err("cup invalide")
	else
		local cup: Vector3 = raw.cup
		local offset = horizontal(cup - last.p).Magnitude
		local allowed = radius - GREEN.CupEdgeMargin - Course.CupRadius
		if offset > allowed then
			err("cup à %.1f studs du centre du green (maximum %.1f pour un rayon %.1f)", offset, allowed, radius)
		end
		local surfaceY = HoleValidator.greenSurfaceY(def, cup)
		local dy = math.abs(cup.Y - surfaceY)
		if dy > Course.Cup.SnapError then
			err("cup.Y décalé de %.1f studs par rapport au green", dy)
		elseif dy > Course.Cup.SnapWarn then
			warn("cup.Y décalé de %.1f studs (recalé sur le green à la construction)", dy)
		end
	end

	-- Départ.
	local teePosition: Vector3 = path[1].p
	if raw.tee ~= nil then
		if type(raw.tee) ~= "table" or not isFiniteVector(raw.tee.position) then
			err("tee.position invalide")
		else
			teePosition = raw.tee.position
			local offset = horizontal(teePosition - path[1].p).Magnitude
			if offset > TEE.MaxOffsetFromFirstNode then
				err("tee à %.1f studs de path[1] (maximum %d)", offset, TEE.MaxOffsetFromFirstNode)
			end
			if math.abs(teePosition.Y - path[1].p.Y) > TEE.MaxRiseFromFirstNode then
				err("tee.position.Y doit rester à ±%d studs de path[1]", TEE.MaxRiseFromFirstNode)
			end
			if raw.tee.yaw ~= nil and not isFiniteNumber(raw.tee.yaw) then
				err("tee.yaw invalide")
			end
		end
	end

	-- Bornes.
	if raw.bounds ~= nil then
		local bounds = raw.bounds
		if type(bounds) ~= "table" or not isFiniteVector(bounds.min) or not isFiniteVector(bounds.max) then
			err("bounds invalides")
		else
			local bmin: Vector3, bmax: Vector3 = bounds.min, bounds.max
			if bmin.X >= bmax.X or bmin.Y >= bmax.Y or bmin.Z >= bmax.Z then
				err("bounds : min doit être strictement inférieur à max")
			end
			local function inside(v: Vector3): boolean
				return v.X >= bmin.X and v.X <= bmax.X and v.Y >= bmin.Y and v.Y <= bmax.Y and v.Z >= bmin.Z and v.Z <= bmax.Z
			end
			for index, node in path do
				if not inside(node.p) then
					err("bounds ne contiennent pas path[%d] %s", index, fmt(node.p))
				end
			end
			if isFiniteVector(raw.cup) and not inside(raw.cup) then
				err("bounds ne contiennent pas le trou")
			end
		end
	end

	-- Dangers.
	if raw.hazards ~= nil then
		for index, hazard in raw.hazards do
			if type(hazard) ~= "table" or not HAZARD_SET[hazard.kind] then
				err("hazards[%d] : kind inconnu", index)
				continue
			end
			if hazard.shape ~= nil and hazard.shape ~= "box" and hazard.shape ~= "cylinder" then
				err("hazards[%d] : shape inconnue %s", index, tostring(hazard.shape))
				continue
			end
			if not isFiniteVector(hazard.center) or not isFiniteVector(hazard.size) then
				err("hazards[%d] : center/size invalides", index)
				continue
			end
			local size: Vector3 = hazard.size
			if size.X < Course.Hazards.MinSize or size.Y < 0.5 or size.Z < Course.Hazards.MinSize then
				err("hazards[%d] : volume trop petit %s", index, fmt(size))
				continue
			end
			if hazard.yaw ~= nil and not isFiniteNumber(hazard.yaw) then
				err("hazards[%d] : yaw invalide", index)
				continue
			end
			if HoleValidator.pointInHazard(hazard, teePosition + Vector3.new(0, 1, 0), 2) then
				err("hazards[%d] (%s) recouvre le départ", index, hazard.kind)
			end
			if isFiniteVector(raw.cup) and HoleValidator.pointInHazard(hazard, raw.cup, Course.CupRadius + 2) then
				err("hazards[%d] (%s) recouvre le trou", index, hazard.kind)
			end
			for nodeIndex = 2, #path - 1 do
				local node = path[nodeIndex]
				local kind = HoleValidator.nodeKind(node)
				local previousKind = HoleValidator.nodeKind(path[nodeIndex - 1])
				local onGround = kind ~= "bridge" and kind ~= "gap" and previousKind ~= "bridge" and previousKind ~= "gap"
				if onGround and HoleValidator.pointInHazard(hazard, node.p + Vector3.new(0, 0.5, 0), 0) then
					warn("hazards[%d] (%s) recouvre path[%d] au sol : prévoir un pont", index, hazard.kind, nodeIndex)
				end
			end
		end
	end

	-- Obstacles.
	if raw.obstacles ~= nil then
		for index, obstacle in raw.obstacles do
			if type(obstacle) ~= "table" or type(obstacle.kind) ~= "string" then
				err("obstacles[%d] : kind manquant", index)
			elseif not OBSTACLE_SET[obstacle.kind] then
				err("obstacles[%d] : type inconnu %q", index, obstacle.kind)
			end
			if type(obstacle) == "table" then
				if not isFiniteVector(obstacle.center) then
					err("obstacles[%d] : center invalide", index)
				end
				if obstacle.size ~= nil and (not isFiniteVector(obstacle.size) or obstacle.size.X <= 0 or obstacle.size.Y <= 0 or obstacle.size.Z <= 0) then
					err("obstacles[%d] : size invalide", index)
				end
				if obstacle.yaw ~= nil and not isFiniteNumber(obstacle.yaw) then
					err("obstacles[%d] : yaw invalide", index)
				end
				if obstacle.params ~= nil and type(obstacle.params) ~= "table" then
					err("obstacles[%d] : params doit être une table", index)
				end
			end
		end
	end

	-- Accessoires.
	if raw.props ~= nil then
		for index, prop in raw.props do
			if type(prop) ~= "table" or not PROP_SET[prop.kind] then
				err("props[%d] : type inconnu %s", index, tostring(type(prop) == "table" and prop.kind or nil))
				continue
			end
			if not isFiniteVector(prop.position) then
				err("props[%d] : position invalide", index)
			end
			if prop.scale ~= nil and (not isFiniteNumber(prop.scale) or prop.scale < VALID.PropScaleMin or prop.scale > VALID.PropScaleMax) then
				err("props[%d] : scale hors de %.1f..%.1f", index, VALID.PropScaleMin, VALID.PropScaleMax)
			end
		end
	end

	-- Boîtes.
	local function checkBoxes(list: any, label: string)
		if list == nil then
			return
		end
		for index, position in list do
			if not isFiniteVector(position) then
				err("%s[%d] : position invalide", label, index)
				continue
			end
			local distance, _, _, _, width = HoleValidator.distanceToPath(path, position)
			local fromEdge = distance - width / 2
			local greenDistance = horizontal(position - last.p).Magnitude - radius
			fromEdge = math.min(fromEdge, greenDistance)
			if fromEdge > Course.Boxes.MaxDistanceError then
				err("%s[%d] à %.0f studs du chemin", label, index, fromEdge)
			elseif fromEdge > Course.Boxes.MaxDistanceFromPath then
				warn("%s[%d] à %.0f studs du chemin (raccourci ?)", label, index, fromEdge)
			end
		end
	end
	checkBoxes(raw.itemBoxes, "itemBoxes")
	checkBoxes(raw.mobilityBoxes, "mobilityBoxes")
	if isInteger(raw.par) and raw.par >= Course.Boxes.MinItemBoxesFromPar and raw.itemBoxes ~= nil and #raw.itemBoxes == 0 then
		warn("aucune boîte d'objet sur un par %d", raw.par)
	end

	-- Checkpoints fournis.
	if raw.checkpoints ~= nil then
		local previousAlong = -math.huge
		for index, position in raw.checkpoints do
			if not isFiniteVector(position) then
				err("checkpoints[%d] : position invalide", index)
				continue
			end
			local distance, _, _, along, width = HoleValidator.distanceToPath(path, position)
			if distance > width / 2 + Course.Checkpoint.MaxDistanceFromPath then
				err("checkpoints[%d] hors du chemin (%.1f studs du centre)", index, distance)
			end
			if along < previousAlong then
				warn("checkpoints[%d] : ordre non croissant le long du chemin", index)
			end
			if previousAlong > -math.huge and along - previousAlong > Course.Checkpoint.MaxSpacing then
				warn("checkpoints[%d] : %.0f studs depuis le précédent", index, along - previousAlong)
			end
			previousAlong = along
		end
	end

	-- Voiturettes.
	if raw.carts ~= nil then
		for index, cart in raw.carts do
			if typeof(cart) ~= "CFrame" then
				err("carts[%d] : CFrame attendu", index)
			end
		end
	end

	-- Raccourcis.
	if raw.shortcuts ~= nil then
		if #raw.shortcuts > VALID.MaxShortcuts then
			warn("plus de %d raccourcis", VALID.MaxShortcuts)
		end
		for index, shortcut in raw.shortcuts do
			if type(shortcut) ~= "table" or type(shortcut.description) ~= "string" or #shortcut.description == 0 then
				err("shortcuts[%d] : description manquante", index)
			elseif shortcut.requires ~= nil and type(shortcut.requires) ~= "string" then
				err("shortcuts[%d] : requires doit être un identifiant d'objet", index)
			end
		end
	end

	-- Divers.
	if raw.decorDensity ~= nil and (not isFiniteNumber(raw.decorDensity) or raw.decorDensity < 0 or raw.decorDensity > VALID.DecorDensityMax) then
		err("decorDensity hors de 0..%d", VALID.DecorDensityMax)
	end
	if raw.windBias ~= nil then
		if not isFiniteVector(raw.windBias) then
			err("windBias invalide")
		elseif raw.windBias.Magnitude > VALID.WindBiasWarn then
			warn("windBias fort (%.1f)", raw.windBias.Magnitude)
		end
	end

	return { ok = #errors == 0, errors = errors, warnings = warnings, metrics = metrics }
end

--------------------------------------------------------------------------------
-- Validation d'une liste
--------------------------------------------------------------------------------

function HoleValidator.validateAll(list: { HoleDef }): Summary
	local summary: Summary = {
		ok = true,
		total = 0,
		failed = 0,
		errorCount = 0,
		warningCount = 0,
		duplicates = {},
		results = {},
		messages = {},
	}
	local seen: { [string]: boolean } = {}
	for index, def in list do
		summary.total += 1
		local id = if type(def) == "table" and type((def :: any).id) == "string" then def.id else ("#" .. index)
		local result = HoleValidator.validate(def)
		if seen[id] then
			table.insert(summary.duplicates, id)
			table.insert(result.errors, "identifiant dupliqué")
			result.ok = false
		end
		seen[id] = true
		if not result.ok then
			summary.failed += 1
			summary.ok = false
		end
		summary.errorCount += #result.errors
		summary.warningCount += #result.warnings
		for _, message in result.errors do
			table.insert(summary.messages, string.format("%s : ERREUR %s", id, message))
		end
		for _, message in result.warnings do
			table.insert(summary.messages, string.format("%s : avertissement %s", id, message))
		end
		-- Un doublon garde le premier résultat sous son id, le second sous id#index.
		summary.results[if summary.results[id] then id .. "#" .. index else id] = result
	end
	return summary
end

return HoleValidator
