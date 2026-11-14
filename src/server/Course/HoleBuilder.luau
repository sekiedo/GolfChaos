--!strict
--[[
	Course/HoleBuilder : construit la géométrie d'un trou à partir d'un Types.HoleDef (format docs/FORMAT_TROUS.md).

	  local result = HoleBuilder.build(def, Course.HoleOrigin, workspace, { preview = false })

	Toutes les positions renvoyées sont en coordonnées MONDE = origin + local (aucun miroir).
	Construit dans un Folder non parenté puis parenté une seule fois (si `parent` est fourni).

	Contenu du dossier (sous-dossiers) :
	  Ground    ruban du chemin (bandes de tonte, bordures, rebords biseautés, jointures arrondies, fondations,
	            bordures basses quand le chemin est en hauteur)      → groupe de collision "Course"
	  Bridges   tabliers, poutres, poteaux, garde-corps / cordes, piles   → "Course"
	  Tunnels   murs et toits des tunnels                             → "Course"
	  Tee       tertre de départ, rebord, fondation (repères décoratifs)  → "Course"
	  Green     green (Surface "Green"), avant-green, rebord, fondation → "Course"
	  Cup       anneau, disque sombre, mât et drapeau (NON collidables)  → "Props"
	  Hazards   volumes de danger (CanCollide false, CanQuery true, tag "GolfHazard", attribut Hazard) et fonds
	            collidables de l'eau et de la lave                    → "Course"
	  PropsSolid / PropsDecor   accessoires explicites du trou (bloquants / décoratifs) → "Course" / "Props"
	  Backdrop  fond collidable de Biomes/Common (sol de fond, plage)  → "Course"
	  Decor     décor de fond non bloquant (Biomes/Common et Biomes/<Biome>) → "Props"
	Les OBSTACLES ne sont pas construits ici (Obstacles.luau, appelé par CourseService) : `result.obstacles`
	contient leurs définitions avec des centres en coordonnées monde.

	Surfaces : attribut "Surface" sur chaque pièce praticable = Config/Course.SurfaceAttribute[surface] (identité :
	les dix surfaces du format existent dans Config/Gameplay.Surfaces, que lit BallService).
	La capture de la balle reste dans BallService.SetCup (cupPosition / cupRadius renvoyés ici).
	Collisions : CollisionService.AssignModel (chargé paresseusement) hors aperçu ; en aperçu (mode Édition) les
	groupes ne sont pas touchés pour ne pas modifier la place.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Course = require(Shared.Config.Course)
local Biomes = require(Shared.Config.Biomes)
local HoleValidator = require(Shared.Logic.HoleValidator)
local Log = require(Shared.Util.Log)
local Props = require(script.Parent.Props)

type HoleDef = Types.HoleDef
type PathNode = Types.PathNode
type BiomeDef = Biomes.BiomeDef
type SurfaceStyle = Biomes.SurfaceStyle

export type BuildOptions = {
	preview: boolean?, -- aperçu en mode Édition : pas de groupes de collision
	decor: boolean?, -- false : pas de décor de fond (défaut true)
}

export type BuildResult = {
	folder: Folder,
	origin: Vector3,
	cupPosition: Vector3,
	cupRadius: number,
	teeCFrame: CFrame, -- sur le dessus du tertre, regard vers le premier segment
	checkpoints: { CFrame },
	itemBoxes: { Vector3 },
	mobilityBoxes: { Vector3 },
	carts: { CFrame },
	killY: number,
	floorY: number, -- sol de fond (sous killY)
	lowestY: number, -- nœud le plus bas (monde)
	bounds: { min: Vector3, max: Vector3 },
	pathLength: number,
	greenCenter: Vector3, -- centre du dessus du green
	greenRadius: number,
	obstacles: { Types.ObstacleDef },
	partCount: number,
}

local HoleBuilder = {}

local PATH = Course.Path
local GREEN = Course.Green
local TEE = Course.Tee
local BRIDGE = Course.Bridge
local TUNNEL = Course.Tunnel
local HAZARDS = Course.Hazards
local HALF_PI = math.pi / 2
local UP = Vector3.yAxis

local HAZARD_TAG = "GolfHazard"
do
	local ok, Gameplay = pcall(require, Shared.Config.Gameplay)
	if ok and type(Gameplay) == "table" and type((Gameplay :: any).Hazards) == "table" then
		HAZARD_TAG = (Gameplay :: any).Hazards.Tag or HAZARD_TAG
	end
end

-- Dossiers et groupe de collision associé.
local FOLDERS: { { name: string, group: string } } = {
	{ name = "Ground", group = "Course" },
	{ name = "Bridges", group = "Course" },
	{ name = "Tunnels", group = "Course" },
	{ name = "Tee", group = "Course" },
	{ name = "Green", group = "Course" },
	{ name = "Cup", group = "Props" },
	{ name = "Hazards", group = "Course" },
	{ name = "PropsSolid", group = "Course" },
	{ name = "PropsDecor", group = "Props" },
	{ name = "Backdrop", group = "Course" },
	{ name = "Decor", group = "Props" },
}

type State = {
	def: HoleDef,
	origin: Vector3,
	biome: BiomeDef,
	folders: { [string]: Folder },
	nodes: { PathNode },
	lowestLocal: number,
	floorWorld: number,
}

--------------------------------------------------------------------------------
-- Outils géométriques
--------------------------------------------------------------------------------

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatUnit(v: Vector3): Vector3
	local f = flat(v)
	if f.Magnitude < 1e-6 then
		return Vector3.zAxis
	end
	return f.Unit
end

-- Vecteur latéral horizontal (+X quand on avance vers +Z).
local function sideOf(dir: Vector3): Vector3
	local f = flatUnit(dir)
	return Vector3.new(f.Z, 0, -f.X)
end

local function slopeTan(a: Vector3, b: Vector3): number
	local run = flat(b - a).Magnitude
	if run < 1e-6 then
		return 0
	end
	return math.abs(b.Y - a.Y) / run
end

local function surfaceName(surface: string): string
	return Course.SurfaceAttribute[surface] or surface
end

--------------------------------------------------------------------------------
-- Création de pièces
--------------------------------------------------------------------------------

local function applyStyle(part: BasePart, color: Color3, material: Enum.Material)
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Color = color
	part.Material = material
end

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, surface: string?): Part
	local part = Instance.new("Part")
	part.Name = name
	applyStyle(part, color, material)
	part.Size = size
	part.CFrame = cf
	if surface then
		part:SetAttribute("Surface", surfaceName(surface))
	end
	part.Parent = parent
	return part
end

local function newCylinder(parent: Instance, name: string, height: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material, surface: string?): Part
	-- `cf` : centre et orientation (axe Y de cf = axe du cylindre).
	local part = newPart(parent, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, HALF_PI), color, material, surface)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function newWedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, surface: string?): WedgePart
	local part = Instance.new("WedgePart")
	part.Name = name
	applyStyle(part, color, material)
	part.Size = size
	part.CFrame = cf
	if surface then
		part:SetAttribute("Surface", surfaceName(surface))
	end
	part.Parent = parent
	return part
end

local function decorOnly(part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

-- Triangle épais : la face SUPÉRIEURE passe par p1, p2, p3 (monde), l'épaisseur part vers le bas.
-- Deux WedgePart (méthode classique de découpe selon la hauteur issue du sommet opposé au plus grand côté).
local function triangle(parent: Instance, name: string, p1: Vector3, p2: Vector3, p3: Vector3, thickness: number, color: Color3, material: Enum.Material, surface: string?)
	local a, b, c = p1, p2, p3
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local normal = ac:Cross(ab)
	if normal.Magnitude < 1e-3 or bc.Magnitude < 1e-3 then
		return
	end
	local right = normal.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	if height < 0.02 then
		return
	end
	local normalUp = if right.Y >= 0 then right else -right
	local shift = -normalUp * (thickness / 2)
	local depth1 = math.abs(ab:Dot(back))
	local depth2 = math.abs(ac:Dot(back))
	if depth1 > 0.02 then
		newWedge(parent, name, Vector3.new(thickness, height, depth1), CFrame.fromMatrix((a + b) / 2 + shift, right, up, back), color, material, surface)
	end
	if depth2 > 0.02 then
		newWedge(parent, name, Vector3.new(thickness, height, depth2), CFrame.fromMatrix((a + c) / 2 + shift, -right, up, -back), color, material, surface)
	end
end

-- Repère d'un segment de ruban (sans dévers) : X latéral horizontal, Y normal au ruban, Z le long du segment.
local function ribbonFrame(a: Vector3, b: Vector3, centerTop: Vector3): (CFrame, Vector3)
	local look = (b - a).Unit
	local side = sideOf(b - a)
	local up = look:Cross(side)
	if up.Y < 0 then
		up = -up
	end
	return CFrame.fromMatrix(centerTop, side, up, look), up
end

-- Ruban (quadrilatère) de a à b, demi-largeurs ra / rb, dessus abaissé de `drop`, épaisseur vers le bas.
-- Bandes de tonte si `alt` est fourni (largeur constante uniquement).
local function quad(parent: Instance, name: string, a: Vector3, b: Vector3, ra: number, rb: number, drop: number, thickness: number, color: Color3, material: Enum.Material, surface: string?, alt: Color3?)
	local length = (b - a).Magnitude
	if length < 0.05 then
		return
	end
	local lowered = Vector3.new(0, -drop, 0)
	local a2, b2 = a + lowered, b + lowered
	local side = sideOf(b - a)
	local rMin = math.min(ra, rb)
	local look = (b2 - a2).Unit
	local _, up = ribbonFrame(a2, b2, a2)
	local function boxBetween(t0: number, t1: number, partColor: Color3)
		local p0 = a2 + (b2 - a2) * t0
		local p1 = a2 + (b2 - a2) * t1
		local mid = (p0 + p1) / 2 - up * (thickness / 2)
		local cf = CFrame.fromMatrix(mid, side, up, look)
		newPart(parent, name, Vector3.new(rMin * 2, thickness, (p1 - p0).Magnitude + 0.04), cf, partColor, material, surface)
	end
	if alt and PATH.StripedFairway and math.abs(ra - rb) < 0.05 then
		local count = math.max(1, math.floor(length / PATH.StripeLength + 0.5))
		for index = 1, count do
			boxBetween((index - 1) / count, index / count, if index % 2 == 0 then alt else color)
		end
	else
		boxBetween(0, 1, color)
	end
	if math.abs(ra - rb) >= 0.05 then
		for _, sign in { 1, -1 } do
			local s = side * sign
			if ra > rb then
				triangle(parent, name, a2 + s * rb, a2 + s * ra, b2 + s * rb, thickness, color, material, surface)
			else
				triangle(parent, name, a2 + s * ra, b2 + s * rb, b2 + s * ra, thickness, color, material, surface)
			end
		end
	end
end

-- Poutre de section width × height dont l'arête inférieure centrale va de p1 à p2.
local function beam(parent: Instance, name: string, p1: Vector3, p2: Vector3, width: number, height: number, color: Color3, material: Enum.Material, surface: string?): Part?
	local length = (p2 - p1).Magnitude
	if length < 0.05 then
		return nil
	end
	local look = (p2 - p1).Unit
	local side = sideOf(p2 - p1)
	local up = look:Cross(side)
	if up.Y < 0 then
		up = -up
	end
	local center = (p1 + p2) / 2 + up * (height / 2)
	return newPart(parent, name, Vector3.new(width, height, length), CFrame.fromMatrix(center, side, up, look), color, material, surface)
end

--------------------------------------------------------------------------------
-- Fondations (falaises sous le ruban)
--------------------------------------------------------------------------------

-- Prisme vertical sous un segment : dessus = ligne (a, b) abaissée de `topDrop`, jusqu'à floorY.
local function foundation(state: State, a: Vector3, b: Vector3, ra: number, rb: number, topDrop: number)
	if not Course.Foundation.Enabled then
		return
	end
	local parent = state.folders.Ground
	local style = state.biome.cliff
	local lowTop = math.min(a.Y, b.Y) - topDrop
	local depth = lowTop - state.floorWorld
	if depth < 0.5 then
		return
	end
	local fa = Vector3.new(a.X, lowTop, a.Z)
	local fb = Vector3.new(b.X, lowTop, b.Z)
	local run = (fb - fa).Magnitude
	if run < 0.05 then
		return
	end
	local look = (fb - fa).Unit
	local side = sideOf(fb - fa)
	local rMin = math.min(ra, rb)
	local center = (fa + fb) / 2 - UP * (depth / 2)
	newPart(parent, "Cliff", Vector3.new(rMin * 2, depth, run + 0.1), CFrame.fromMatrix(center, side, UP, look), style.color, style.material)
	if math.abs(ra - rb) >= 0.05 then
		for _, sign in { 1, -1 } do
			local s = side * sign
			if ra > rb then
				triangle(parent, "Cliff", fa + s * rb, fa + s * ra, fb + s * rb, depth, style.color, style.material)
			else
				triangle(parent, "Cliff", fa + s * ra, fb + s * rb, fb + s * ra, depth, style.color, style.material)
			end
		end
	end
	-- Remplissage de la pente entre le dessus du prisme et le dessous du rebord.
	local rise = math.abs(b.Y - a.Y)
	if rise > 0.1 then
		local high, low = if a.Y > b.Y then fa else fb, if a.Y > b.Y then fb else fa
		local mid = (fa + fb) / 2 + UP * (rise / 2)
		local cf = CFrame.lookAt(mid, mid + (low - high))
		newWedge(parent, "CliffSlope", Vector3.new(rMin * 2, rise, run), cf, style.color, style.material)
	end
end

--------------------------------------------------------------------------------
-- Segments
--------------------------------------------------------------------------------

local function isGroundKind(kind: string): boolean
	return kind == "ground" or kind == "ice" or kind == "tunnel"
end

-- Couches d'un segment au sol : fairway (+ tonte), bordure, rebord biseauté, fondation, bordures basses.
local function buildGroundSegment(state: State, index: number, a: Vector3, b: Vector3, ra: number, rb: number, surface: string)
	local biome = state.biome
	local parent = state.folders.Ground
	local style = Biomes.surfaceStyle(biome, surface)
	local border = Biomes.surfaceStyle(biome, biome.borderSurface)
	local rough = PATH.RoughWidth
	local thick = PATH.RibbonThickness
	local alt = if surface == "Fairway" then style.alt else nil
	quad(parent, "Fairway", a, b, ra, rb, 0, thick, style.color, style.material, surface, alt)
	quad(parent, "Border", a, b, ra + rough, rb + rough, PATH.RoughDrop, thick, border.color, border.material, biome.borderSurface)
	local lipA, lipB = ra + rough + PATH.EdgeLipOverhang, rb + rough + PATH.EdgeLipOverhang
	quad(parent, "Edge", a, b, lipA, lipB, PATH.EdgeLip, PATH.EdgeLipThickness, biome.edge.color, biome.edge.material, biome.borderSurface)
	foundation(state, a, b, lipA - 0.3, lipB - 0.3, PATH.EdgeLip + PATH.EdgeLipThickness - 0.05)
	-- Bordures basses quand le segment est nettement au-dessus du point le plus bas du parcours.
	local elevation = math.min(a.Y, b.Y) - (state.origin.Y + state.lowestLocal)
	if elevation >= PATH.CurbMinElevation then
		local side = sideOf(b - a)
		for _, sign in { 1, -1 } do
			local offsetA = side * sign * (ra + rough - PATH.CurbWidth / 2)
			local offsetB = side * sign * (rb + rough - PATH.CurbWidth / 2)
			local drop = Vector3.new(0, -PATH.RoughDrop, 0)
			beam(parent, "Curb", a + offsetA + drop, b + offsetB + drop, PATH.CurbWidth, PATH.CurbHeight, biome.edge.color, biome.edge.material, "Rock")
		end
	end
	local _ = index
end

local function buildBridgeSegment(state: State, a: Vector3, b: Vector3, width: number, surface: string)
	local biome = state.biome
	local parent = state.folders.Bridges
	local deck = biome.bridge.deck
	local style = if surface == "Wood" then deck else Biomes.surfaceStyle(biome, surface)
	local dir = (b - a).Unit
	-- Le tablier mord de 0,6 stud dans le sol à chaque extrémité.
	local a2, b2 = a - dir * 0.6, b + dir * 0.6
	local r = width / 2
	quad(parent, "Deck", a2, b2, r, r, 0, BRIDGE.DeckThickness, style.color, style.material, surface)
	local side = sideOf(b - a)
	local length = (b2 - a2).Magnitude
	local _, up = ribbonFrame(a2, b2, a2)
	-- Poutres latérales sous le tablier.
	for _, sign in { 1, -1 } do
		local offset = side * sign * (r - 0.4) - up * (BRIDGE.DeckThickness + BRIDGE.BeamHeight)
		beam(parent, "Beam", a2 + offset, b2 + offset, 0.8, BRIDGE.BeamHeight, biome.bridge.post, Enum.Material.Wood)
	end
	-- Poteaux et garde-corps (cordes pour le style « rope »).
	local posts = math.max(1, math.ceil(length / BRIDGE.PostSpacing))
	for _, sign in { 1, -1 } do
		local edge = side * sign * (r - BRIDGE.RailThickness / 2)
		for step = 0, posts do
			local base = a2 + (b2 - a2) * (step / posts) + edge
			newPart(parent, "Post", Vector3.new(BRIDGE.RailThickness * 1.3, BRIDGE.RailHeight + 0.3, BRIDGE.RailThickness * 1.3), CFrame.new(base + UP * ((BRIDGE.RailHeight + 0.3) / 2)), biome.bridge.post, Enum.Material.Wood)
		end
		if biome.bridge.rope then
			for _, height in { BRIDGE.RailHeight, BRIDGE.RailHeight * 0.55 } do
				local p1 = a2 + edge + UP * height
				local p2 = b2 + edge + UP * height
				local rope = newCylinder(parent, "Rope", (p2 - p1).Magnitude, 0.35, CFrame.lookAt((p1 + p2) / 2, p2) * CFrame.Angles(HALF_PI, 0, 0), biome.bridge.rail, Enum.Material.Fabric)
				rope.CastShadow = false
			end
			-- Filet invisible sous les cordes : les balles et les joueurs ne passent pas entre les cordes.
			local net = beam(parent, "RailGuard", a2 + edge, b2 + edge, BRIDGE.RailThickness, BRIDGE.RailHeight, biome.bridge.rail, Enum.Material.SmoothPlastic)
			if net then
				net.Transparency = 1
				net.CastShadow = false
			end
		else
			beam(parent, "Rail", a2 + edge + UP * (BRIDGE.RailHeight - 0.4), b2 + edge + UP * (BRIDGE.RailHeight - 0.4), BRIDGE.RailThickness, 0.4, biome.bridge.rail, Enum.Material.SmoothPlastic)
			local guard = beam(parent, "RailGuard", a2 + edge, b2 + edge, BRIDGE.RailThickness * 0.6, BRIDGE.RailHeight - 0.4, biome.bridge.rail, Enum.Material.SmoothPlastic)
			if guard then
				guard.Transparency = 1
				guard.CastShadow = false
			end
		end
	end
	-- Piles jusqu'au sol de fond (dans la mer pour la Côte).
	local pillars = math.floor(length / BRIDGE.PillarSpacing)
	for step = 1, pillars do
		local top = a2 + (b2 - a2) * (step / (pillars + 1)) - up * BRIDGE.DeckThickness
		local depth = top.Y - state.floorWorld
		if depth > 1 then
			for _, sign in { 1, -1 } do
				local base = top + side * sign * (r * 0.6)
				newCylinder(parent, "Pillar", depth, math.max(1.2, width * BRIDGE.PillarWidthRatio * 0.4), CFrame.new(base - UP * (depth / 2)), biome.bridge.post, Enum.Material.Wood)
			end
		end
	end
end

local function buildTunnelShell(state: State, a: Vector3, b: Vector3, width: number)
	local biome = state.biome
	local parent = state.folders.Tunnels
	local style = biome.tunnel
	local r = width / 2
	local wall = TUNNEL.WallThickness
	local side = sideOf(b - a)
	local _, up = ribbonFrame(a, b, a)
	for _, sign in { 1, -1 } do
		local offset = side * sign * (r + wall / 2)
		beam(parent, "TunnelWall", a + offset - up * 0.5, b + offset - up * 0.5, wall, TUNNEL.Height + 0.5, style.color, style.material, "Rock")
		-- Chanfrein intérieur (voûte low-poly).
		-- Coin d'angle droit en haut contre le mur : Y local vers le bas, Z local vers le mur, X le long du tunnel.
		local outward = side * sign
		local yAxis = -up
		local zAxis = outward
		local xAxis = yAxis:Cross(zAxis)
		local center = (a + b) / 2 + outward * (r - 1.2) + up * (TUNNEL.Height - 1.2)
		newWedge(parent, "TunnelArch", Vector3.new((b - a).Magnitude, 2.4, 2.4), CFrame.fromMatrix(center, xAxis, yAxis, zAxis), style.color, style.material, "Rock")
	end
	beam(parent, "TunnelRoof", a + up * TUNNEL.Height, b + up * TUNNEL.Height, width + wall * 2, TUNNEL.RoofThickness, style.color, style.material, "Rock")
	-- Bandeau de façade aux deux entrées (lisibilité de la grotte).
	for _, point in { a, b } do
		local face = CFrame.fromMatrix(point + up * (TUNNEL.Height + TUNNEL.RoofThickness / 2), side, up, (b - a).Unit)
		newPart(parent, "TunnelPortal", Vector3.new(width + wall * 2 + 1.2, TUNNEL.RoofThickness + 1, 1.2), face, biome.edge.color, style.material)
	end
end

-- Jointure arrondie d'un nœud intérieur : éventail de triangles horizontaux du côté extérieur du virage.
local function buildJoint(state: State, index: number)
	local nodes = state.nodes
	local origin = state.origin
	local p = origin + nodes[index].p
	local prev = origin + nodes[index - 1].p
	local nextP = origin + nodes[index + 1].p
	local d1, d2 = flatUnit(p - prev), flatUnit(nextP - p)
	local cross = d1:Cross(d2).Y
	local dot = math.clamp(d1:Dot(d2), -1, 1)
	local turn = math.acos(dot)
	local r = HoleValidator.nodeWidth(nodes[index]) / 2
	local maxTan = math.max(slopeTan(prev, p), slopeTan(p, nextP))
	local biome = state.biome
	local parent = state.folders.Ground
	local surface = HoleValidator.nodeSurface(nodes[index])
	local style = Biomes.surfaceStyle(biome, surface)
	local border = Biomes.surfaceStyle(biome, biome.borderSurface)
	local rough = PATH.RoughWidth
	local rTotal = r + rough + PATH.EdgeLipOverhang

	if turn > math.rad(2) then
		local outer = if cross > 0 then -1 else 1
		local s1, s2 = sideOf(d1) * outer, sideOf(d2) * outer
		local a1 = math.atan2(s1.X, s1.Z)
		local a2 = math.atan2(s2.X, s2.Z)
		local delta = a2 - a1
		while delta > math.pi do
			delta -= 2 * math.pi
		end
		while delta < -math.pi do
			delta += 2 * math.pi
		end
		local steps = math.max(1, math.ceil(math.abs(math.deg(delta)) / PATH.JointSectorDeg))
		local layers = {
			{ radius = r, drop = 0, thick = PATH.RibbonThickness, color = style.color, material = style.material, surface = surface },
			{ radius = r + rough, drop = PATH.RoughDrop, thick = PATH.RibbonThickness, color = border.color, material = border.material, surface = biome.borderSurface },
			{ radius = rTotal, drop = PATH.EdgeLip, thick = PATH.EdgeLipThickness, color = biome.edge.color, material = biome.edge.material, surface = biome.borderSurface },
		}
		for _, layer in layers do
			local center = p - UP * layer.drop
			local thickness = layer.thick + layer.radius * maxTan + 0.3
			for step = 0, steps - 1 do
				local t0 = a1 + delta * (step / steps)
				local t1 = a1 + delta * ((step + 1) / steps)
				local q0 = center + Vector3.new(math.sin(t0), 0, math.cos(t0)) * layer.radius
				local q1 = center + Vector3.new(math.sin(t1), 0, math.cos(t1)) * layer.radius
				triangle(parent, "Joint", center, q0, q1, thickness, layer.color, layer.material, layer.surface)
			end
		end
	end
	-- Pile ronde sous le nœud (ferme les fondations dans les virages).
	if Course.Foundation.Enabled then
		local top = p.Y - PATH.EdgeLip - PATH.EdgeLipThickness - rTotal * maxTan
		local depth = top - state.floorWorld
		if depth > 0.5 then
			newCylinder(parent, "CliffJoint", depth, (rTotal - 0.3) * 2, CFrame.new(Vector3.new(p.X, top - depth / 2, p.Z)), biome.cliff.color, biome.cliff.material)
		end
	end
end

--------------------------------------------------------------------------------
-- Départ, green, trou
--------------------------------------------------------------------------------

local function teeFrame(def: HoleDef): (Vector3, Vector3)
	local position = if def.tee then def.tee.position else def.path[1].p
	local dir: Vector3
	if def.tee and def.tee.yaw then
		local yaw = math.rad(def.tee.yaw)
		dir = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
	else
		dir = flatUnit(def.path[2].p - def.path[1].p)
	end
	return position, dir
end

local function buildTee(state: State): CFrame
	local def = state.def
	local biome = state.biome
	local parent = state.folders.Tee
	local localPos, dir = teeFrame(def)
	local position = state.origin + localPos
	local top = position + UP * TEE.BoxRaise
	local frame = CFrame.lookAt(top, top + dir)
	local onBridge = HoleValidator.nodeKind(def.path[1]) == "bridge"
	local style = if onBridge then biome.bridge.deck else biome.tee
	local surface = if onBridge then "Wood" else "Fairway"
	local size = Vector3.new(TEE.BoxWidth, TEE.BoxThickness, TEE.BoxDepth)
	newPart(parent, "TeeBox", size, frame * CFrame.new(0, -TEE.BoxThickness / 2, 0), style.color, style.material, surface)
	-- Rebord et fondation propres au tertre (il déborde souvent du ruban).
	local lipSize = Vector3.new(TEE.BoxWidth + 1.2, PATH.EdgeLipThickness, TEE.BoxDepth + 1.2)
	newPart(parent, "TeeEdge", lipSize, frame * CFrame.new(0, -TEE.BoxRaise - PATH.EdgeLip - PATH.EdgeLipThickness / 2, 0), biome.edge.color, biome.edge.material, "Rock")
	local cliffTop = top.Y - TEE.BoxRaise - PATH.EdgeLip - PATH.EdgeLipThickness
	local depth = cliffTop - state.floorWorld
	if depth > 0.5 then
		if onBridge then
			-- Ponton : quatre pilotis au lieu d'une falaise.
			for _, corner in { Vector2.new(1, 1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.new(-1, -1) } do
				local offset = frame * CFrame.new(corner.X * (TEE.BoxWidth / 2 - 1.5), 0, corner.Y * (TEE.BoxDepth / 2 - 1.5))
				local base = Vector3.new(offset.Position.X, cliffTop - depth / 2, offset.Position.Z)
				newCylinder(parent, "TeePile", depth, 1.6, CFrame.new(base), biome.bridge.post, Enum.Material.Wood)
			end
		elseif Course.Foundation.Enabled then
			local cliffFrame = CFrame.lookAt(Vector3.new(top.X, cliffTop - depth / 2, top.Z), Vector3.new(top.X, cliffTop - depth / 2, top.Z) + dir)
			newPart(parent, "TeeCliff", Vector3.new(TEE.BoxWidth + 0.6, depth, TEE.BoxDepth + 0.6), cliffFrame, biome.cliff.color, biome.cliff.material)
		end
	end
	-- Repères colorés aux coins avant (décoratifs, non collidables).
	local markers = biome.teeMarkers
	for index, sign in { -1, 1 } do
		local color = markers[((index - 1) % #markers) + 1]
		local marker = newPart(parent, "TeeMarker", Vector3.one * TEE.MarkerSize, frame * CFrame.new(sign * (TEE.BoxWidth / 2 - 2), TEE.MarkerSize / 2, -(TEE.BoxDepth / 2 - 1.5)) * CFrame.Angles(0, math.rad(45), 0), color, Enum.Material.SmoothPlastic)
		decorOnly(marker)
	end
	return frame
end

local function buildGreen(state: State): (Vector3, number, Vector3)
	local def = state.def
	local biome = state.biome
	local parent = state.folders.Green
	local radius = HoleValidator.greenRadius(def)
	local centerLocal = def.path[#def.path].p
	local center = state.origin + centerLocal
	local normal = HoleValidator.greenNormal(def)
	-- Rotation de l'inclinaison (mêmes angles que HoleValidator.greenNormal).
	local tilt = def.green and def.green.tilt
	local tiltRotation = if tilt then CFrame.Angles(math.rad(tilt.X), 0, math.rad(tilt.Z)) else CFrame.new()
	local base = CFrame.new(center) * tiltRotation
	local greenStyle = Biomes.surfaceStyle(biome, "Green")
	local fairway = Biomes.surfaceStyle(biome, "Fairway")
	newCylinder(parent, "Green", GREEN.Thickness, radius * 2, base * CFrame.new(0, GREEN.Raise - GREEN.Thickness / 2, 0), greenStyle.color, greenStyle.material, "Green")
	local fringeRadius = radius + GREEN.FringeWidth
	newCylinder(parent, "Fringe", GREEN.Thickness + 0.3, fringeRadius * 2, base * CFrame.new(0, GREEN.Raise * 0.5 - (GREEN.Thickness + 0.3) / 2, 0), fairway.alt or fairway.color, fairway.material, "Fairway")
	local lipRadius = fringeRadius + PATH.EdgeLipOverhang + 0.4
	newCylinder(parent, "GreenEdge", PATH.EdgeLipThickness, lipRadius * 2, base * CFrame.new(0, -PATH.EdgeLip - PATH.EdgeLipThickness / 2, 0), biome.edge.color, biome.edge.material, biome.borderSurface)
	if Course.Foundation.Enabled then
		local top = center.Y - PATH.EdgeLip - PATH.EdgeLipThickness - lipRadius * math.tan(math.acos(math.clamp(normal.Y, -1, 1)))
		local depth = top - state.floorWorld
		if depth > 0.5 then
			newCylinder(parent, "GreenCliff", depth, (lipRadius - 0.3) * 2, CFrame.new(Vector3.new(center.X, top - depth / 2, center.Z)), biome.cliff.color, biome.cliff.material)
		end
	end
	-- Trou : recalé sur la surface du green.
	local cupLocal = def.cup
	local surfaceY = HoleValidator.greenSurfaceY(def, cupLocal) + GREEN.Raise / normal.Y
	local cupWorld = state.origin + Vector3.new(cupLocal.X, surfaceY, cupLocal.Z)
	local cupFrame = CFrame.new(cupWorld) * tiltRotation
	local cupRadius = Course.CupRadius
	local cupParent = state.folders.Cup
	local ring = newCylinder(cupParent, "CupRing", 0.04, (cupRadius + Course.Cup.RingWidth) * 2, cupFrame * CFrame.new(0, Course.Cup.RingRaise, 0), Color3.fromRGB(250, 250, 250), Enum.Material.SmoothPlastic)
	decorOnly(ring)
	local hole = newCylinder(cupParent, "CupHole", 0.04, cupRadius * 2, cupFrame * CFrame.new(0, Course.Cup.HoleRaise, 0), Color3.fromRGB(24, 26, 30), Enum.Material.SmoothPlastic)
	decorOnly(hole)
	local flag = Course.Flag
	local pole = newCylinder(cupParent, "FlagPole", flag.PoleHeight, flag.PoleDiameter, CFrame.new(cupWorld + UP * (flag.PoleHeight / 2)), biome.flag.pole, Enum.Material.SmoothPlastic)
	decorOnly(pole)
	local cloth = newPart(cupParent, "Flag", flag.ClothSize, CFrame.new(cupWorld + Vector3.new(flag.ClothSize.X / 2, flag.PoleHeight - flag.ClothSize.Y / 2 - 0.2, 0)), biome.flag.cloth, Enum.Material.Fabric)
	decorOnly(cloth)
	local cap = newPart(cupParent, "FlagCap", Vector3.one * 0.55, CFrame.new(cupWorld + UP * (flag.PoleHeight + 0.2)), Color3.fromRGB(255, 220, 80), Enum.Material.Neon)
	cap.Shape = Enum.PartType.Ball
	decorOnly(cap)
	local greenTop = center + UP * GREEN.Raise
	return cupWorld, cupRadius, greenTop
end

--------------------------------------------------------------------------------
-- Dangers
--------------------------------------------------------------------------------

local function buildHazard(state: State, hazard: Types.HazardDef, index: number)
	local biome = state.biome
	local parent = state.folders.Hazards
	local center = state.origin + hazard.center
	local frame = CFrame.new(center) * CFrame.Angles(0, math.rad(hazard.yaw or 0), 0)
	local isCylinder = (hazard.shape or "box") == "cylinder"
	local size = hazard.size
	local volume: Part
	if isCylinder then
		volume = newCylinder(parent, "Hazard_" .. hazard.kind, size.Y, size.X, frame, biome.water.color, Enum.Material.SmoothPlastic)
	else
		volume = newPart(parent, "Hazard_" .. hazard.kind, size, frame, biome.water.color, Enum.Material.SmoothPlastic)
	end
	volume.CanCollide = false
	volume.CanQuery = true -- requis par les requêtes spatiales de BallService
	volume.CanTouch = true
	volume.CastShadow = false
	volume:SetAttribute("Hazard", hazard.kind)
	volume:SetAttribute("HazardIndex", index)
	CollectionService:AddTag(volume, HAZARD_TAG)
	if hazard.kind == "water" then
		volume.Color = biome.water.color
		volume.Transparency = biome.water.transparency
		volume.Reflectance = 0.05
	elseif hazard.kind == "lava" then
		volume.Color = biome.lava.color
		volume.Material = Enum.Material.Neon
		volume.Transparency = biome.lava.transparency
	else
		volume.Transparency = 1
	end
	-- Fond collidable (eau, lave) : la balle s'arrête DANS le volume, BallService applique la pénalité.
	if hazard.kind == "water" or hazard.kind == "lava" then
		local bedColor = if hazard.kind == "water" then biome.water.bed else Color3.fromRGB(70, 30, 20)
		local bedThickness = math.min(HAZARDS.BedThickness, size.Y * 0.4)
		local bedFrame = frame * CFrame.new(0, -size.Y / 2 + bedThickness / 2, 0)
		local bed: Part
		if isCylinder then
			bed = newCylinder(parent, "HazardBed", bedThickness, size.X - 0.1, bedFrame, bedColor, Enum.Material.SmoothPlastic)
		else
			bed = newPart(parent, "HazardBed", Vector3.new(size.X - 0.1, bedThickness, size.Z - 0.1), bedFrame, bedColor, Enum.Material.SmoothPlastic)
		end
		bed:SetAttribute("Surface", surfaceName("Sand"))
		bed.CastShadow = false
	end
end

--------------------------------------------------------------------------------
-- Checkpoints et boîtes
--------------------------------------------------------------------------------

local function segmentKindAt(nodes: { PathNode }, segIndex: number): string
	return HoleValidator.nodeKind(nodes[math.clamp(segIndex, 1, #nodes)])
end

local function buildCheckpoints(state: State, teeFrame_: CFrame, pathLength: number): { CFrame }
	local def = state.def
	local origin = state.origin
	local spawnHeight = Course.Checkpoint.SpawnHeight
	local list: { CFrame } = {}
	if def.checkpoints then
		for _, position in def.checkpoints do
			local _, segIndex = HoleValidator.distanceToPath(def.path, position)
			local a, b = def.path[segIndex].p, def.path[math.min(segIndex + 1, #def.path)].p
			local world = origin + position + UP * spawnHeight
			table.insert(list, CFrame.lookAt(world, world + flatUnit(b - a)))
		end
		return list
	end
	table.insert(list, teeFrame_ + UP * spawnHeight)
	local stop = pathLength - (HoleValidator.greenRadius(def) + Course.Checkpoint.GreenClearance)
	local distance = Course.Checkpoint.Spacing
	while distance < stop do
		local position, dir, segIndex = HoleValidator.pointAtDistance(def.path, distance)
		if segmentKindAt(def.path, segIndex) ~= "gap" then
			local world = origin + position + UP * spawnHeight
			table.insert(list, CFrame.lookAt(world, world + dir))
		end
		distance += Course.Checkpoint.Spacing
	end
	return list
end

local function generatedItemBoxes(state: State, pathLength: number): { Vector3 }
	local def = state.def
	local fractions = Course.Boxes.DefaultFractions[def.par] or {}
	local list: { Vector3 } = {}
	for index, fraction in fractions do
		local position, dir, segIndex = HoleValidator.pointAtDistance(def.path, pathLength * fraction)
		local kind = segmentKindAt(def.path, segIndex)
		if kind ~= "gap" then
			local lateral = 0
			if kind ~= "bridge" then
				local halfWidth = HoleValidator.nodeWidth(def.path[segIndex]) / 2
				lateral = math.min(Course.Boxes.DefaultLateralOffset, math.max(halfWidth - 3, 0)) * (if index % 2 == 0 then -1 else 1)
			end
			local world = state.origin + position + sideOf(dir) * lateral + UP * Course.Boxes.Height
			table.insert(list, world)
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- Accessoires explicites, décor, collisions
--------------------------------------------------------------------------------

local function buildProps(state: State, rng: Random)
	local def = state.def
	if def.props == nil then
		return
	end
	for _, prop in def.props do
		local params = prop.params or {}
		local cf = CFrame.new(state.origin + prop.position) * CFrame.Angles(0, math.rad(prop.yaw or 0), 0)
		local model = Props.make(prop.kind, cf, prop.scale, rng, state.biome.palette, params)
		if model == nil then
			Log.warn("HoleBuilder", def.id, "accessoire inconnu :", prop.kind)
			continue
		end
		local solid = if params.solid ~= nil then params.solid == true else Course.SolidProps[prop.kind] == true
		if solid then
			Props.setSolid(model, true)
			model.Parent = state.folders.PropsSolid
		else
			model.Parent = state.folders.PropsDecor
		end
	end
end

local collisionModule: any = nil
local collisionLookupDone = false

local function getCollisionService(): any
	if collisionLookupDone then
		return collisionModule
	end
	collisionLookupDone = true
	local services = script.Parent.Parent:FindFirstChild("Services")
	local module = services and services:FindFirstChild("CollisionService")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" and type((result :: any).AssignModel) == "function" then
			collisionModule = result
		else
			Log.warn("HoleBuilder", "CollisionService indisponible :", result)
		end
	end
	return collisionModule
end

local function assignCollisionGroups(state: State)
	local service = getCollisionService()
	if service == nil then
		return
	end
	for _, entry in FOLDERS do
		local folder = state.folders[entry.name]
		if folder then
			local ok, err = pcall(service.AssignModel, folder, entry.group, false)
			if not ok then
				Log.warn("HoleBuilder", "groupe de collision", entry.group, ":", err)
			end
		end
	end
end

local function runDecorators(state: State, result: BuildResult, rng: Random)
	local def = state.def
	local density = math.clamp((def.decorDensity or 1) * state.biome.decorDensity, 0, 3)
	local biomesFolder = script.Parent:FindFirstChild("Biomes")
	if biomesFolder == nil then
		return
	end
	local function run(moduleName: string)
		local module = biomesFolder:FindFirstChild(moduleName)
		if module == nil or not module:IsA("ModuleScript") then
			return
		end
		local ok, decorator = pcall(require, module)
		if not ok or type(decorator) ~= "table" or type((decorator :: any).decorate) ~= "function" then
			if not ok then
				Log.warn("HoleBuilder", "module de décor en erreur :", moduleName, decorator)
			end
			return
		end
		local success, err = pcall((decorator :: any).decorate, def, result, state.biome.palette, rng, density)
		if not success then
			Log.warn("HoleBuilder", def.id, "décor", moduleName, "en erreur :", err)
		end
	end
	run("Common")
	run(def.biome)
end

local function countParts(folder: Instance): number
	local count = 0
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function HoleBuilder.build(def: HoleDef, origin: Vector3, parent: Instance?, options: BuildOptions?): BuildResult
	assert(type(def) == "table" and type(def.path) == "table" and #def.path >= 2, "HoleBuilder.build : définition sans chemin valide")
	local opts: BuildOptions = options or {}
	local validation = HoleValidator.validate(def)
	if not validation.ok then
		for _, message in validation.errors do
			Log.warn("HoleBuilder", def.id, "validation :", message)
		end
	end

	local biome = Biomes.get(def.biome)
	local nodes = def.path
	local lowestLocal = math.huge
	for _, node in nodes do
		lowestLocal = math.min(lowestLocal, node.p.Y)
	end
	if def.obstacles then
		for _, obstacle in def.obstacles do
			if Course.WalkableObstacleKinds[obstacle.kind] then
				local half = if obstacle.size then obstacle.size.Y / 2 else 0
				lowestLocal = math.min(lowestLocal, obstacle.center.Y - half)
			end
		end
	end
	local killLocal = lowestLocal - Course.KillMargin
	local floorLocal = killLocal - Course.GroundBelowKill

	local folder = Instance.new("Folder")
	folder.Name = "Hole_" .. def.id
	local folders: { [string]: Folder } = {}
	for _, entry in FOLDERS do
		local sub = Instance.new("Folder")
		sub.Name = entry.name
		sub.Parent = folder
		folders[entry.name] = sub
	end

	local state: State = {
		def = def,
		origin = origin,
		biome = biome,
		folders = folders,
		nodes = nodes,
		lowestLocal = lowestLocal,
		floorWorld = origin.Y + floorLocal,
	}

	-- Segments du chemin ------------------------------------------------------
	local count = #nodes
	local greenRadius = HoleValidator.greenRadius(def)
	for index = 1, count - 1 do
		local node, nextNode = nodes[index], nodes[index + 1]
		local kind = HoleValidator.nodeKind(node)
		local a = origin + node.p
		local b = origin + nextNode.p
		local wa = HoleValidator.nodeWidth(node)
		local wb = if kind == "bridge" or kind == "tunnel" then wa else HoleValidator.nodeWidth(nextNode)
		if kind == "gap" then
			continue
		elseif kind == "bridge" then
			local surface = node.surface or "Wood"
			buildBridgeSegment(state, a, b, wa, surface)
		else
			local surface = HoleValidator.nodeSurface(node)
			-- Le premier segment recule sous le tertre ; le dernier ne déborde jamais au-dessus du green.
			if index == 1 then
				-- Rallonge plate sous l'arrière du tertre (même largeur que le départ du segment).
				local behind = a - flatUnit(b - a) * (TEE.BoxDepth / 2 + 2)
				buildGroundSegment(state, 0, behind, a, wa / 2, wa / 2, surface)
			end
			if index == count - 1 and a.Y > b.Y + 0.05 then
				local length = flat(b - a).Magnitude
				local entry = greenRadius + GREEN.FringeWidth - 1
				if length > entry + 1 then
					local t = (length - entry) / length
					local e = a:Lerp(b, t)
					buildGroundSegment(state, index, a, e, wa / 2, (wa + (wb - wa) * t) / 2, surface)
					-- Tablier plat sous l'avant-green (jamais au-dessus du green).
					local apronEnd = Vector3.new(b.X, b.Y - 0.05, b.Z)
					local apronStart = Vector3.new(e.X, b.Y - 0.05, e.Z)
					buildGroundSegment(state, index, apronStart, apronEnd, (wa + (wb - wa) * t) / 2, wb / 2, surface)
				else
					buildGroundSegment(state, index, a, b, wa / 2, wb / 2, surface)
				end
			else
				buildGroundSegment(state, index, a, b, wa / 2, wb / 2, surface)
			end
			if kind == "tunnel" then
				buildTunnelShell(state, origin + node.p, b, wa)
			end
		end
	end
	for index = 2, count - 1 do
		if isGroundKind(HoleValidator.nodeKind(nodes[index - 1])) and isGroundKind(HoleValidator.nodeKind(nodes[index])) then
			buildJoint(state, index)
		end
	end

	-- Départ, green, dangers -------------------------------------------------
	local teeCFrame = buildTee(state)
	local cupPosition, cupRadius, greenCenter = buildGreen(state)
	if def.hazards then
		for index, hazard in def.hazards do
			buildHazard(state, hazard, index)
		end
	end

	-- Données de jeu ------------------------------------------------------------
	local pathLength = HoleValidator.pathLength(nodes)
	local checkpoints = buildCheckpoints(state, teeCFrame, pathLength)
	local itemBoxes: { Vector3 } = {}
	if def.itemBoxes then
		for _, position in def.itemBoxes do
			table.insert(itemBoxes, origin + position)
		end
	else
		itemBoxes = generatedItemBoxes(state, pathLength)
	end
	local mobilityBoxes: { Vector3 } = {}
	for _, position in def.mobilityBoxes or {} do
		table.insert(mobilityBoxes, origin + position)
	end
	local carts: { CFrame } = {}
	for _, cf in def.carts or {} do
		table.insert(carts, CFrame.new(origin) * cf)
	end
	local obstacles: { Types.ObstacleDef } = {}
	for _, obstacle in def.obstacles or {} do
		table.insert(obstacles, {
			kind = obstacle.kind,
			center = origin + obstacle.center,
			size = obstacle.size,
			yaw = obstacle.yaw,
			params = obstacle.params,
		})
	end

	-- Bornes (monde).
	local bounds: { min: Vector3, max: Vector3 }
	if def.bounds then
		bounds = { min = origin + def.bounds.min, max = origin + def.bounds.max }
	else
		local minV = Vector3.new(math.huge, math.huge, math.huge)
		local maxV = -minV
		local function include(point: Vector3, radius: number)
			minV = minV:Min(point - Vector3.new(radius, 0, radius))
			maxV = maxV:Max(point + Vector3.new(radius, 0, radius))
		end
		for _, node in nodes do
			include(node.p, HoleValidator.nodeWidth(node) / 2 + PATH.RoughWidth)
		end
		include(nodes[count].p, greenRadius + GREEN.FringeWidth)
		include(teeFrame(def), TEE.BoxWidth / 2)
		local margin = Course.Bounds.Margin
		bounds = {
			min = origin + Vector3.new(minV.X - margin, minV.Y - Course.Bounds.Floor, minV.Z - margin),
			max = origin + Vector3.new(maxV.X + margin, maxV.Y + Course.Bounds.Ceiling, maxV.Z + margin),
		}
	end

	local result: BuildResult = {
		folder = folder,
		origin = origin,
		cupPosition = cupPosition,
		cupRadius = cupRadius,
		teeCFrame = teeCFrame,
		checkpoints = checkpoints,
		itemBoxes = itemBoxes,
		mobilityBoxes = mobilityBoxes,
		carts = carts,
		killY = origin.Y + killLocal,
		floorY = origin.Y + floorLocal,
		lowestY = origin.Y + lowestLocal,
		bounds = bounds,
		pathLength = pathLength,
		greenCenter = greenCenter,
		greenRadius = greenRadius,
		obstacles = obstacles,
		partCount = 0,
	}

	-- Accessoires et décor (déterministes : même graine = même trou) ------------
	local rng = Random.new(def.seed)
	buildProps(state, rng)
	result.partCount = countParts(folder)
	if opts.decor ~= false then
		runDecorators(state, result, Random.new(def.seed + 7919))
	end

	if not opts.preview then
		assignCollisionGroups(state)
	end

	result.partCount = countParts(folder)
	if result.partCount > Course.MaxPartsPerHole then
		Log.warn("HoleBuilder", def.id, "budget de pièces dépassé :", result.partCount, ">", Course.MaxPartsPerHole)
	end
	folder:SetAttribute("HoleId", def.id)
	folder:SetAttribute("Biome", def.biome)
	folder:SetAttribute("KillY", result.killY)
	folder:SetAttribute("PartCount", result.partCount)
	folder:SetAttribute("Preview", opts.preview == true)

	if parent then
		folder.Parent = parent
	end
	return result
end

-- Nombre de pièces d'un dossier construit (outils).
HoleBuilder.countParts = countParts

return HoleBuilder
