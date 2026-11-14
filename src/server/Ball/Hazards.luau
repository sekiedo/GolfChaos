--!strict
--[[
	Ball.Hazards — détection des dangers pour BallService (extrait de BallService, comportement inchangé).

	  Hazards.KINDS                          types de danger valides ("water", "oob", "lava", "void")
	  Hazards.start(trove)                   crée les filtres de requête et suit les volumes balisés (Config.Hazards.Tag)
	  Hazards.detect(data, previous, position, dt) -> (type?, point?)
	      volumes balisés à chaque image (aucune allocation) ; eau du Terrain et limites du trou périodiquement
	      (Ball.HazardCheckInterval). `data` doit porter `grounded` et `hazardTimer` (champ modifié ici).

	Les volumes dangereux sont des Parts ou des Models balisés ; l'attribut Hazard (Part ou ancêtre balisé) choisit
	le type, sinon Hazards.DefaultKind. Un hors-limites n'est retenu que si la balle touche le sol (OobRequiresGround).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.Gameplay)

local optionalService = require(script.Parent.Parent.Util.Services).get

local BALL = Config.Ball
local HAZARDS = Config.Hazards

local Hazards = {}

Hazards.KINDS = { water = true, oob = true, lava = true, void = true } :: { [string]: boolean }

local roots: { Instance } = {}
local overlapParams: OverlapParams? = nil
local rayParams: RaycastParams? = nil

local function refreshFilters()
	if overlapParams then
		overlapParams.FilterDescendantsInstances = roots
	end
	if rayParams then
		rayParams.FilterDescendantsInstances = roots
	end
end

local function addRoot(instance: Instance)
	if table.find(roots, instance) == nil then
		table.insert(roots, instance)
		refreshFilters()
	end
end

local function removeRoot(instance: Instance)
	local index = table.find(roots, instance)
	if index then
		table.remove(roots, index)
		refreshFilters()
	end
end

function Hazards.start(trove: any)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = {}
	overlapParams = overlap

	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Include
	ray.IgnoreWater = true
	ray.FilterDescendantsInstances = {}
	rayParams = ray

	trove:Connect(CollectionService:GetInstanceAddedSignal(HAZARDS.Tag), addRoot)
	trove:Connect(CollectionService:GetInstanceRemovedSignal(HAZARDS.Tag), removeRoot)
	for _, instance in CollectionService:GetTagged(HAZARDS.Tag) do
		addRoot(instance)
	end
end

-- Type de danger d'une Part balisée (attribut Hazard sur la Part ou sur un ancêtre balisé).
local function kindOf(part: Instance): string
	local current: Instance? = part
	while current and current ~= Workspace do
		local kind = current:GetAttribute("Hazard")
		if type(kind) == "string" and Hazards.KINDS[kind] then
			return kind
		end
		if CollectionService:HasTag(current, HAZARDS.Tag) then
			break
		end
		current = current.Parent
	end
	return HAZARDS.DefaultKind
end

local function taggedHazard(previous: Vector3, position: Vector3, grounded: boolean): (string?, Vector3?)
	local overlap = overlapParams
	if #roots == 0 or not overlap then
		return nil, nil
	end
	for _, part in Workspace:GetPartBoundsInRadius(position, BALL.Diameter / 2, overlap) do
		local kind = kindOf(part)
		-- Hors limites : seulement quand la balle touche le sol (le survol est permis).
		if kind ~= "oob" or grounded or not HAZARDS.OobRequiresGround then
			return kind, position
		end
	end
	-- Volume mince traversé entre deux images (balle rapide) ; un hors-limites survolé reste permis.
	local ray = rayParams
	local delta = position - previous
	if ray and delta.Magnitude > BALL.Diameter then
		local result = Workspace:Raycast(previous, delta, ray)
		if result then
			local kind = kindOf(result.Instance)
			if kind ~= "oob" or not HAZARDS.OobRequiresGround then
				return kind, result.Position
			end
		end
	end
	return nil, nil
end

-- Eau du Terrain à la position (lecture de voxels, résolution 4).
local function inTerrainWater(position: Vector3): boolean
	if not BALL.TerrainWater then
		return false
	end
	local terrain = Workspace.Terrain
	local region = Region3.new(position - Vector3.new(2, 2, 2), position + Vector3.new(2, 2, 2)):ExpandToGrid(4)
	local ok, materials, occupancies = pcall(function(): (any, any)
		return terrain:ReadVoxels(region, 4)
	end)
	if not ok or materials == nil or occupancies == nil then
		return false
	end
	local size = materials.Size
	if typeof(size) ~= "Vector3" then
		return false
	end
	local minCorner = region.CFrame.Position - region.Size / 2
	local ix = math.clamp(math.floor((position.X - minCorner.X) / 4) + 1, 1, size.X)
	local iy = math.clamp(math.floor((position.Y - minCorner.Y) / 4) + 1, 1, size.Y)
	local iz = math.clamp(math.floor((position.Z - minCorner.Z) / 4) + 1, 1, size.Z)
	if materials[ix][iy][iz] ~= Enum.Material.Water then
		return false
	end
	local surfaceHeight = minCorner.Y + (iy - 1) * 4 + occupancies[ix][iy][iz] * 4
	return position.Y <= surfaceHeight
end

local function courseOutOfBounds(position: Vector3): boolean
	if not HAZARDS.UseCourseBounds then
		return false
	end
	local CourseService = optionalService("CourseService")
	if CourseService and type(CourseService.IsOutOfBounds) == "function" then
		local ok, result = pcall(CourseService.IsOutOfBounds, position)
		return ok and result == true
	end
	return false
end

-- Volumes balisés à chaque image ; contrôles coûteux (eau du Terrain, limites du trou) périodiques.
function Hazards.detect(data: { grounded: boolean, hazardTimer: number }, previous: Vector3, position: Vector3, dt: number): (string?, Vector3?)
	local kind, at = taggedHazard(previous, position, data.grounded)
	if kind then
		return kind, at
	end
	data.hazardTimer += dt
	if data.hazardTimer >= BALL.HazardCheckInterval then
		data.hazardTimer = 0
		if inTerrainWater(position) then
			return "water", position
		end
		if (data.grounded or not HAZARDS.OobRequiresGround) and courseOutOfBounds(position) then
			return "oob", position
		end
	end
	return nil, nil
end

return Hazards
