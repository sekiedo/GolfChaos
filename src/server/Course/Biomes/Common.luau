--!strict
--[[
	Course/Biomes/Common : décor procédural commun à tous les biomes (appelé par HoleBuilder après la géométrie).

	  Common.decorate(def, build, palette, rng, density)
	    def      Types.HoleDef (coordonnées locales)
	    build    HoleBuilder.BuildResult (folder non encore parenté, origin, bounds, killY, floorY, lowestY...)
	    palette  Config/Biomes.<biome>.palette
	    rng      Random déterministe (graine du trou) : même trou = même décor
	    density  0..3 (HoleDef.decorDensity × densité du biome)

	Produit :
	  - le sol de fond (sous la zone mortelle) ou, pour la Côte, la mer (volume de danger "water" balisé
	    GolfHazard) avec son fond et des plages au pied des falaises (dossier Backdrop, collidable, Surface Sand) ;
	  - des accessoires de bordure posés sur le rebord extérieur du chemin, jamais sur le fairway, le green, le
	    départ, les dangers ou les obstacles ;
	  - des accessoires lointains sur le sol de fond / la plage ;
	  - un fond adapté au biome : îles lointaines (Côte), murs d'arbres (Forêt), dunes et mesas (Désert), pics
	    enneigés (Neige), blocs d'immeubles (Ville), anneau d'arbres (Entraînement).
	Respecte le budget : min(Config/Course.Decor.MaxParts, MaxPartsPerHole - pièces déjà construites - réserve
	pour les obstacles). Tout le décor (dossier Decor) est non bloquant ; seul le dossier Backdrop collisionne.
	Les modules Biomes/<Biome>.luau (écrits par les auteurs de biomes) ont la même signature et s'exécutent après.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Course = require(Shared.Config.Course)
local Biomes = require(Shared.Config.Biomes)
local HoleValidator = require(Shared.Logic.HoleValidator)
local Props = require(script.Parent.Parent.Props)

type HoleDef = Types.HoleDef
type Palette = { [string]: { Color3 } }
type WeightedKind = Biomes.WeightedKind

local Common = {}

local DECOR = Course.Decor
local PATH = Course.Path
local UP = Vector3.yAxis
local MAX_PART_SIZE = 2048
local OBSTACLE_RESERVE = 80 -- pièces gardées pour les obstacles construits ensuite par Obstacles.luau
local BEACH_WIDTH = 12
local BEACH_RAISE = 0.6 -- dessus de la plage au-dessus du niveau de la mer

type Context = {
	def: HoleDef,
	build: any,
	origin: Vector3,
	biome: Biomes.BiomeDef,
	palette: Palette,
	rng: Random,
	density: number,
	budget: number,
	used: number,
	decor: Instance,
	backdrop: Instance,
	seaTop: number?,
}

--------------------------------------------------------------------------------
-- Outils
--------------------------------------------------------------------------------

local function folderNamed(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function basePart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, collide: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = collide
	part.CanQuery = collide
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(math.min(size.X, MAX_PART_SIZE), math.min(size.Y, MAX_PART_SIZE), math.min(size.Z, MAX_PART_SIZE))
	part.CFrame = cf
	part.Color = color
	part.Material = material
	part.Parent = parent
	return part
end

local function charge(ctx: Context, parts: number): boolean
	if ctx.used + parts > ctx.budget then
		return false
	end
	ctx.used += parts
	return true
end

local function pickWeighted(ctx: Context, list: { WeightedKind }): WeightedKind?
	local total = 0
	for _, entry in list do
		total += entry.weight
	end
	if total <= 0 then
		return nil
	end
	local roll = ctx.rng:NextNumber() * total
	for _, entry in list do
		roll -= entry.weight
		if roll <= 0 then
			return entry
		end
	end
	return list[#list]
end

local function rollScale(ctx: Context, entry: WeightedKind, factor: number?): number
	local range = entry.scale or { 1, 1 }
	return (range[1] + (range[2] - range[1]) * ctx.rng:NextNumber()) * (factor or 1)
end

-- Place un accessoire de décor (non bloquant) ; false si le budget est épuisé.
local function placeProp(ctx: Context, kind: string, position: Vector3, scale: number, params: { [string]: any }?): boolean
	local cf = CFrame.new(position) * CFrame.Angles(0, ctx.rng:NextNumber() * math.pi * 2, 0)
	local model = Props.make(kind, cf, scale, ctx.rng, ctx.palette, params)
	if model == nil then
		return true
	end
	local parts = Props.partCount(model)
	if not charge(ctx, parts) then
		model:Destroy()
		return false
	end
	model.Parent = ctx.decor
	return true
end

-- Vrai si le point (monde) est hors du couloir de jeu, du green, du départ, des dangers et des obstacles.
local function isClear(ctx: Context, world: Vector3, clearance: number, allowEdge: boolean?): boolean
	local def = ctx.def
	local localPoint = world - ctx.origin
	local distance, _, _, _, width = HoleValidator.distanceToPath(def.path, localPoint)
	local corridor = width / 2 + (if allowEdge then 0 else PATH.RoughWidth + PATH.EdgeLipOverhang)
	if distance < corridor + clearance then
		return false
	end
	local green = def.path[#def.path].p
	if HoleValidator.horizontal(localPoint - green).Magnitude < HoleValidator.greenRadius(def) + Course.Green.FringeWidth + 1.5 + clearance then
		return false
	end
	local teePosition = if def.tee then def.tee.position else def.path[1].p
	if HoleValidator.horizontal(localPoint - teePosition).Magnitude < Course.Tee.BoxWidth / 2 + clearance then
		return false
	end
	for _, hazard in def.hazards or {} do
		local probe = Vector3.new(localPoint.X, hazard.center.Y, localPoint.Z)
		if HoleValidator.pointInHazard(hazard, probe, clearance) then
			return false
		end
	end
	for _, obstacle in def.obstacles or {} do
		local size = obstacle.size or Vector3.new(6, 6, 6)
		local radius = math.max(size.X, size.Z) / 2
		if HoleValidator.horizontal(localPoint - obstacle.center).Magnitude < radius + clearance + 2 then
			return false
		end
	end
	for _, prop in def.props or {} do
		if HoleValidator.horizontal(localPoint - prop.position).Magnitude < 4 * (prop.scale or 1) then
			return false
		end
	end
	return true
end

local function isGroundSegment(def: HoleDef, index: number): boolean
	local kind = HoleValidator.nodeKind(def.path[index])
	return kind == "ground" or kind == "ice" or kind == "tunnel"
end

--------------------------------------------------------------------------------
-- Sol de fond, mer, plages
--------------------------------------------------------------------------------

local function boundsInfo(ctx: Context): (Vector3, Vector3)
	local bounds = ctx.build.bounds
	local center = (bounds.min + bounds.max) / 2
	local size = bounds.max - bounds.min
	return center, size
end

local function buildFloor(ctx: Context)
	local center, size = boundsInfo(ctx)
	local floorY: number = ctx.build.floorY
	local margin = DECOR.GroundMargin
	local floorSize = Vector3.new(size.X + margin * 2, 4, size.Z + margin * 2)
	local floorStyle = ctx.biome.floor
	local floor = basePart(ctx.backdrop, "Floor", floorSize, CFrame.new(center.X, floorY - 2, center.Z), floorStyle.color, floorStyle.material, true)
	floor:SetAttribute("Surface", "Rough")
	charge(ctx, 1)
end

local function buildSea(ctx: Context)
	local center, size = boundsInfo(ctx)
	local lowest: number = ctx.build.lowestY
	local seaTop = lowest - Course.SeaBelowPath
	ctx.seaTop = seaTop
	local margin = DECOR.GroundMargin + 400
	local seaSize = Vector3.new(size.X + margin * 2, Course.SeaDepth, size.Z + margin * 2)
	local water = ctx.biome.water
	local sea = basePart(ctx.backdrop, "Sea", seaSize, CFrame.new(center.X, seaTop - Course.SeaDepth / 2, center.Z), water.color:Lerp(Color3.fromRGB(20, 90, 160), 0.35), Enum.Material.SmoothPlastic, false)
	sea.CanQuery = true -- requêtes spatiales de BallService
	sea.CanTouch = true
	sea.Transparency = 0.12
	sea.Reflectance = 0.08
	sea.CastShadow = false
	sea:SetAttribute("Hazard", "water")
	CollectionService:AddTag(sea, "GolfHazard")
	charge(ctx, 1)
end

-- Plages au pied des falaises : bandes de sable le long des segments au sol, disques aux nœuds, au green et au départ.
local function buildBeaches(ctx: Context)
	local seaTop = ctx.seaTop
	if seaTop == nil then
		return
	end
	local def = ctx.def
	local origin = ctx.origin
	local sand = Biomes.surfaceStyle(ctx.biome, "Sand")
	local top = seaTop + BEACH_RAISE
	local thickness = 3
	local function disc(center: Vector3, radius: number)
		if not charge(ctx, 1) then
			return
		end
		local part = basePart(ctx.backdrop, "Beach", Vector3.new(thickness, radius * 2, radius * 2), CFrame.new(center.X, top - thickness / 2, center.Z) * CFrame.Angles(0, 0, math.pi / 2), sand.color, sand.material, true)
		part.Shape = Enum.PartType.Cylinder
		part:SetAttribute("Surface", "Sand")
	end
	local outer = PATH.RoughWidth + PATH.EdgeLipOverhang
	for index = 1, #def.path - 1 do
		if not isGroundSegment(def, index) then
			continue
		end
		local a = origin + def.path[index].p
		local b = origin + def.path[index + 1].p
		local fa, fb = Vector3.new(a.X, top, a.Z), Vector3.new(b.X, top, b.Z)
		local run = (fb - fa).Magnitude
		if run < 1 then
			continue
		end
		local wa = HoleValidator.nodeWidth(def.path[index])
		local wb = HoleValidator.nodeWidth(def.path[index + 1])
		local width = math.max(wa, wb) + (outer + BEACH_WIDTH) * 2
		if not charge(ctx, 1) then
			return
		end
		local cf = CFrame.lookAt((fa + fb) / 2 - UP * (thickness / 2), (fa + fb) / 2 - UP * (thickness / 2) + (fb - fa))
		local part = basePart(ctx.backdrop, "Beach", Vector3.new(width, thickness, run), cf, sand.color, sand.material, true)
		part:SetAttribute("Surface", "Sand")
		if index > 1 and isGroundSegment(def, index - 1) then
			disc(a, wa / 2 + outer + BEACH_WIDTH)
		end
	end
	local green = origin + def.path[#def.path].p
	disc(green, HoleValidator.greenRadius(def) + Course.Green.FringeWidth + BEACH_WIDTH + 2)
	local teeLocal = if def.tee then def.tee.position else def.path[1].p
	disc(origin + teeLocal, Course.Tee.BoxWidth / 2 + BEACH_WIDTH * 0.6)
end

--------------------------------------------------------------------------------
-- Accessoires de bordure et lointains
--------------------------------------------------------------------------------

-- Bordure : sur le rebord extérieur du chemin (au-delà du fairway), un emplacement tous les VergeSpacing studs.
local function scatterVerge(ctx: Context)
	local def = ctx.def
	local verge = ctx.biome.verge
	if #verge == 0 then
		return
	end
	local pathLength = HoleValidator.pathLength(def.path)
	local chance = math.clamp(DECOR.VergeChance * ctx.density, 0, 0.95)
	local distance = DECOR.VergeSpacing * 0.5
	while distance < pathLength do
		local position, dir, segIndex = HoleValidator.pointAtDistance(def.path, distance)
		if isGroundSegment(def, segIndex) then
			local side = Vector3.new(dir.Z, 0, -dir.X)
			local width = HoleValidator.nodeWidth(def.path[segIndex])
			for _, sign in { 1, -1 } do
				if ctx.rng:NextNumber() < chance then
					local lateral = width / 2 + PATH.RoughWidth - 1 + ctx.rng:NextNumber() * 1.2
					local localPoint = position + side * sign * lateral
					local world = ctx.origin + localPoint - UP * PATH.RoughDrop
					-- Le point de bordure ne doit pas retomber sur un autre segment (virages serrés).
					local clearOfPath = true
					local d, _, _, _, w = HoleValidator.distanceToPath(def.path, localPoint)
					if d < w / 2 + 2 then
						clearOfPath = false
					end
					if clearOfPath and isClear(ctx, world, 0, true) then
						local entry = pickWeighted(ctx, verge)
						if entry and not placeProp(ctx, entry.kind, world, rollScale(ctx, entry)) then
							return
						end
					end
				end
			end
		end
		distance += DECOR.VergeSpacing
	end
end

-- Lointains : sur le sol de fond (ou la plage / la mer pour la Côte), à bonne distance du couloir.
local function scatterFar(ctx: Context)
	local far = ctx.biome.far
	if #far == 0 then
		return
	end
	local center, size = boundsInfo(ctx)
	local wanted = math.floor(DECOR.FarProps * ctx.density + 0.5)
	local attempts = wanted * DECOR.MaxAttemptsFactor
	local placed = 0
	local baseY: number = if ctx.seaTop then (ctx.seaTop :: number) + BEACH_RAISE else ctx.build.floorY
	while placed < wanted and attempts > 0 do
		attempts -= 1
		local x = center.X + (ctx.rng:NextNumber() - 0.5) * (size.X + DECOR.FarDistance[2])
		local z = center.Z + (ctx.rng:NextNumber() - 0.5) * (size.Z + DECOR.FarDistance[2])
		local world = Vector3.new(x, baseY, z)
		if isClear(ctx, world, DECOR.FarDistance[1] * 0.5) then
			local entry = pickWeighted(ctx, far)
			if entry then
				local kind = entry.kind
				local y = baseY
				-- Sur la Côte, seuls les objets flottants vont en mer ; le reste va sur la plage ou un îlot.
				if ctx.seaTop and (kind == "buoy" or kind == "boat") then
					y = ctx.seaTop :: number
				elseif ctx.seaTop then
					-- Petit îlot de sable sous l'objet.
					if charge(ctx, 1) then
						local sand = Biomes.surfaceStyle(ctx.biome, "Sand")
						local islet = basePart(ctx.decor, "Islet", Vector3.new(3, 12 + ctx.rng:NextNumber() * 8, 12 + ctx.rng:NextNumber() * 8), CFrame.new(x, (ctx.seaTop :: number) + BEACH_RAISE - 1.5, z) * CFrame.Angles(0, 0, math.pi / 2), sand.color, sand.material, false)
						islet.Shape = Enum.PartType.Cylinder
						islet.CastShadow = false
					end
				end
				if not placeProp(ctx, kind, Vector3.new(x, y, z), rollScale(ctx, entry, if ctx.seaTop then 1 else 1.4)) then
					return
				end
				placed += 1
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Fonds par biome (anneau lointain hors des bornes)
--------------------------------------------------------------------------------

local function ringPoints(ctx: Context, count: number, extra: number): { Vector3 }
	local center, size = boundsInfo(ctx)
	local radius = math.max(size.X, size.Z) / 2 + extra
	local points: { Vector3 } = {}
	local offset = ctx.rng:NextNumber() * math.pi * 2
	for index = 1, count do
		local angle = offset + (index / count) * math.pi * 2 + (ctx.rng:NextNumber() - 0.5) * 0.25
		local r = radius + (ctx.rng:NextNumber() - 0.5) * 40
		table.insert(points, Vector3.new(center.X + math.cos(angle) * r, 0, center.Z + math.sin(angle) * r))
	end
	return points
end

local function backdropSea(ctx: Context)
	local seaTop = ctx.seaTop or ctx.build.lowestY
	local sand = Biomes.surfaceStyle(ctx.biome, "Sand")
	for _, point in ringPoints(ctx, 6, 90) do
		if not charge(ctx, 3) then
			return
		end
		local radius = 22 + ctx.rng:NextNumber() * 20
		local islet = basePart(ctx.decor, "FarIsland", Vector3.new(4, radius * 2, radius * 2), CFrame.new(point.X, seaTop + 0.5, point.Z) * CFrame.Angles(0, 0, math.pi / 2), sand.color, sand.material, false)
		islet.Shape = Enum.PartType.Cylinder
		local rockColor = ctx.palette.rock and ctx.palette.rock[1] or Color3.fromRGB(200, 192, 176)
		local hill = basePart(ctx.decor, "FarHill", Vector3.new(radius * 1.3, radius * 0.9, radius * 1.1), CFrame.new(point.X, seaTop + radius * 0.2, point.Z) * CFrame.Angles(0.3, ctx.rng:NextNumber() * 3, 0.25), rockColor, Enum.Material.SmoothPlastic, false)
		hill.CastShadow = false
		local foliage = ctx.palette.foliage and ctx.palette.foliage[1] or Color3.fromRGB(76, 184, 76)
		basePart(ctx.decor, "FarCanopy", Vector3.new(radius * 0.9, radius * 0.5, radius * 0.8), CFrame.new(point.X, seaTop + radius * 0.55, point.Z) * CFrame.Angles(0.2, ctx.rng:NextNumber() * 3, -0.2), foliage, Enum.Material.SmoothPlastic, false)
		for _ = 1, 2 do
			local p = Vector3.new(point.X + (ctx.rng:NextNumber() - 0.5) * radius, seaTop + 1, point.Z + (ctx.rng:NextNumber() - 0.5) * radius)
			if not placeProp(ctx, "palm", p, 1.6 + ctx.rng:NextNumber()) then
				return
			end
		end
	end
	-- Un phare lointain sur le premier îlot du fond (repère visuel de la Côte).
	local points = ringPoints(ctx, 1, 150)
	placeProp(ctx, "lighthouse", Vector3.new(points[1].X, seaTop, points[1].Z), 2)
end

local function backdropForest(ctx: Context)
	local floorY: number = ctx.build.floorY
	for _, point in ringPoints(ctx, 34, 70) do
		local kind = if ctx.rng:NextNumber() < 0.6 then "pine" else "tree"
		if not placeProp(ctx, kind, Vector3.new(point.X, floorY, point.Z), 3 + ctx.rng:NextNumber() * 1.5) then
			return
		end
	end
end

local function backdropDesert(ctx: Context)
	local floorY: number = ctx.build.floorY
	local rockColors = ctx.palette.rock or { Color3.fromRGB(214, 140, 90) }
	for index, point in ringPoints(ctx, 16, 90) do
		if index % 2 == 0 then
			-- Mesa : trois strates.
			if not charge(ctx, 3) then
				return
			end
			local width = 50 + ctx.rng:NextNumber() * 40
			local height = 40 + ctx.rng:NextNumber() * 50
			local yaw = CFrame.Angles(0, ctx.rng:NextNumber() * math.pi, 0)
			local color = rockColors[ctx.rng:NextInteger(1, #rockColors)]
			local base = CFrame.new(point.X, floorY, point.Z) * yaw
			basePart(ctx.decor, "Mesa", Vector3.new(width, height * 0.5, width * 0.8), base * CFrame.new(0, height * 0.25, 0), color, Enum.Material.Sandstone, false)
			basePart(ctx.decor, "Mesa", Vector3.new(width * 0.85, height * 0.3, width * 0.68), base * CFrame.new(0, height * 0.65, 0), color:Lerp(Color3.new(1, 1, 1), 0.1), Enum.Material.Sandstone, false)
			basePart(ctx.decor, "Mesa", Vector3.new(width * 0.7, height * 0.2, width * 0.55), base * CFrame.new(0, height * 0.9, 0), color:Lerp(Color3.new(0, 0, 0), 0.08), Enum.Material.Sandstone, false)
		else
			if not placeProp(ctx, "dune", Vector3.new(point.X, floorY, point.Z), 2.5 + ctx.rng:NextNumber() * 1.5) then
				return
			end
		end
	end
end

local function backdropSnow(ctx: Context)
	local floorY: number = ctx.build.floorY
	local rockColors = ctx.palette.rock or { Color3.fromRGB(150, 160, 178) }
	local snow = ctx.palette.snow and ctx.palette.snow[1] or Color3.fromRGB(244, 248, 255)
	-- Pic low-poly : cube posé sur un sommet (rotation 45° / 35,26°) en partie enterré, coiffe de neige.
	local peakRotation = CFrame.Angles(math.rad(45), 0, math.rad(35.264))
	for _, point in ringPoints(ctx, 16, 110) do
		if not charge(ctx, 2) then
			return
		end
		local size = 70 + ctx.rng:NextNumber() * 60
		local yaw = CFrame.Angles(0, ctx.rng:NextNumber() * math.pi * 2, 0)
		local diagonal = size * math.sqrt(3) / 2
		local base = CFrame.new(point.X, floorY + diagonal * 0.35, point.Z) * yaw * peakRotation
		basePart(ctx.decor, "Peak", Vector3.new(size, size, size), base, rockColors[ctx.rng:NextInteger(1, #rockColors)], Enum.Material.Slate, false).CastShadow = false
		local capSize = size * 0.42
		local capOffset = (diagonal - capSize * math.sqrt(3) / 2) -- sommets alignés
		local cap = CFrame.new(point.X, floorY + diagonal * 0.35 + capOffset + 0.6, point.Z) * yaw * peakRotation
		basePart(ctx.decor, "PeakSnow", Vector3.new(capSize, capSize, capSize), cap, snow, Enum.Material.Snow, false).CastShadow = false
	end
end

local function backdropCity(ctx: Context)
	local floorY: number = ctx.build.floorY
	local colors = ctx.palette.building or { Color3.fromRGB(200, 200, 210) }
	local roofs = ctx.palette.roof or { Color3.fromRGB(70, 74, 86) }
	for _, point in ringPoints(ctx, 24, 80) do
		if not charge(ctx, 3) then
			return
		end
		local width = 26 + ctx.rng:NextNumber() * 24
		local depth = 26 + ctx.rng:NextNumber() * 24
		local height = 40 + ctx.rng:NextNumber() * 90
		local yaw = CFrame.Angles(0, ctx.rng:NextNumber() * math.pi, 0)
		local base = CFrame.new(point.X, floorY, point.Z) * yaw
		local color = colors[ctx.rng:NextInteger(1, #colors)]
		basePart(ctx.decor, "Tower", Vector3.new(width, height, depth), base * CFrame.new(0, height / 2, 0), color, Enum.Material.SmoothPlastic, false)
		basePart(ctx.decor, "TowerWindows", Vector3.new(width + 0.3, height * 0.8, depth * 0.6), base * CFrame.new(0, height * 0.5, 0), Color3.fromRGB(150, 210, 250), Enum.Material.Glass, false).CastShadow = false
		basePart(ctx.decor, "TowerRoof", Vector3.new(width * 0.5, 4, depth * 0.5), base * CFrame.new(0, height + 2, 0), roofs[ctx.rng:NextInteger(1, #roofs)], Enum.Material.SmoothPlastic, false).CastShadow = false
	end
end

local function backdropRing(ctx: Context)
	local floorY: number = ctx.build.floorY
	for index, point in ringPoints(ctx, 22, 60) do
		local kind = if index % 3 == 0 then "birch" elseif index % 3 == 1 then "tree" else "pine"
		if not placeProp(ctx, kind, Vector3.new(point.X, floorY, point.Z), 2.4 + ctx.rng:NextNumber()) then
			return
		end
	end
end

local BACKDROPS: { [string]: (Context) -> () } = {
	sea = backdropSea,
	forest = backdropForest,
	desert = backdropDesert,
	snow = backdropSnow,
	city = backdropCity,
	ring = backdropRing,
}

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function Common.decorate(def: HoleDef, build: any, palette: Palette?, rng: Random, density: number)
	local folder: Instance = build.folder
	local biome = Biomes.get(def.biome)
	local already = tonumber(build.partCount) or 0
	local budget = math.min(DECOR.MaxParts, Course.MaxPartsPerHole - already - OBSTACLE_RESERVE)
	local ctx: Context = {
		def = def,
		build = build,
		origin = build.origin,
		biome = biome,
		palette = palette or biome.palette,
		rng = rng,
		density = math.clamp(density, 0, 3),
		budget = math.max(budget, 0),
		used = 0,
		decor = folderNamed(folder, "Decor"),
		backdrop = folderNamed(folder, "Backdrop"),
		seaTop = nil,
	}

	-- Sol ou mer (toujours construits, hors budget de décor si nécessaire).
	ctx.budget += 4
	if biome.backdrop == "sea" then
		buildFloor(ctx)
		buildSea(ctx)
		buildBeaches(ctx)
	else
		buildFloor(ctx)
	end

	if ctx.density <= 0 then
		return
	end
	-- Ordre : fond lointain (silhouette), bordure (cadre du chemin), lointains (remplissage).
	local backdrop = BACKDROPS[biome.backdrop]
	if backdrop then
		backdrop(ctx)
	end
	scatterVerge(ctx)
	scatterFar(ctx)
end

-- Exposé pour les modules de biome (mêmes règles d'exclusion du couloir).
Common.isClear = function(def: HoleDef, build: any, world: Vector3, clearance: number): boolean
	local ctx = {
		def = def,
		build = build,
		origin = build.origin,
	} :: any
	return isClear(ctx, world, clearance)
end

return Common
