--!strict
--[[
	Trous d'entraînement (biome Training, préfixe ENT). Format : docs/FORMAT_TROUS.md.
	Textes affichés : Locale/fr|en/HolesTraining.luau (clés "hole.<id>.name" / "hole.<id>.feature").

	ENT-01  Driving range : fairway très large (90 studs) sur 400 studs, repères tous les 50 studs des deux côtés,
	        trois greens-cibles (100, 200, 300) et le vrai green au bout.
	ENT-02  Trou tutoriel : par 3 court et large, une boîte d'objet sur le chemin.
	ENT-03  Atelier du putt : par 2, petit green incliné de façon douce.
	Coordonnées locales (X latéral, Y haut, Z vers le trou), studs.
]]

local Types = require(script.Parent.Parent.Parent.Types)

type HoleDef = Types.HoleDef
type PathNode = Types.PathNode
type PropDef = Types.PropDef

local V = Vector3.new

local function node(x: number, y: number, z: number, w: number?, surface: Types.Surface?, kind: any?): PathNode
	return { p = V(x, y, z), w = w, surface = surface, kind = kind }
end

local function prop(kind: string, x: number, y: number, z: number, scale: number?, yaw: number?, params: { [string]: any }?): PropDef
	return { kind = kind, position = V(x, y, z), scale = scale, yaw = yaw, params = params }
end

local holes: { HoleDef } = {}

--------------------------------------------------------------------------------
-- ENT-01 : driving range
--------------------------------------------------------------------------------
do
	local props: { PropDef } = {}
	-- Repères de distance tous les 50 studs, des deux côtés du practice (non bloquants).
	for distance = 50, 350, 50 do
		table.insert(props, prop("distanceMarker", -40, 0, distance, 1, 0, { distance = distance, solid = false }))
		table.insert(props, prop("distanceMarker", 40, 0, distance, 1, 0, { distance = distance, solid = false }))
	end
	-- Greens-cibles (disques décoratifs plats + drapeau), couleurs vives distinctes.
	table.insert(props, prop("targetGreen", 0, 0, 100, 1, 0, { radius = 9, color = Color3.fromRGB(235, 87, 87), distance = 100 }))
	table.insert(props, prop("targetGreen", -18, 0, 200, 1, 0, { radius = 11, color = Color3.fromRGB(255, 196, 61), distance = 200 }))
	table.insert(props, prop("targetGreen", 20, 0, 300, 1, 0, { radius = 13, color = Color3.fromRGB(86, 156, 255), distance = 300 }))
	-- Mobilier du départ.
	table.insert(props, prop("bench", -34, 0, -2, 1, 90))
	table.insert(props, prop("bench", 34, 0, -2, 1, -90))
	table.insert(props, prop("banner", -30, 0, 12, 1.2, 0, { solid = false }))
	table.insert(props, prop("banner", 30, 0, 12, 1.2, 0, { solid = false }))
	table.insert(props, prop("flowerbed", -24, 0, -8, 1.2))
	table.insert(props, prop("flowerbed", 24, 0, -8, 1.2))

	table.insert(holes, {
		id = "ENT-01",
		name = "Le Practice des Embruns",
		biome = "Training",
		par = 5,
		difficulty = 1,
		targetTime = 150,
		feature = "Grand practice ouvert : repères tous les 50 studs et greens-cibles pour régler ta puissance",
		seed = 1001,
		path = {
			node(0, 0, 0, 90),
			node(0, 0, 100, 90),
			node(0, 0, 200, 90),
			node(0, 0, 300, 90),
			node(0, 0, 400, 90),
		},
		cup = V(0, 0, 404),
		green = { radius = 24 },
		props = props,
		itemBoxes = { V(-30, 3, 30), V(30, 3, 30) },
		mobilityBoxes = { V(0, 3, 60) },
		decorDensity = 1.2,
	})
end

--------------------------------------------------------------------------------
-- ENT-02 : trou tutoriel
--------------------------------------------------------------------------------
table.insert(holes, {
	id = "ENT-02",
	name = "Premier Swing",
	biome = "Training",
	par = 3,
	difficulty = 1,
	targetTime = 60,
	feature = "Trou d'initiation court et indulgent : vise, charge, frappe et ramasse une boîte d'objet",
	seed = 1002,
	path = {
		node(0, 0, 0, 28),
		node(0, 0, 50, 30),
		node(-8, 0.5, 95, 30),
		node(-14, 1, 140, 28),
	},
	cup = V(-12, 1, 145),
	green = { radius = 16 },
	itemBoxes = { V(-4, 3.3, 75) },
	props = {
		prop("sign", 16, 0, 8, 1, -20, { solid = false }),
		prop("flowerbed", -18, 0, 20, 1),
		prop("bush", 18, 0, 60, 1.2),
		prop("bush", -24, 0.3, 90, 1),
		prop("flag", -30, 1, 130, 1, 0, { solid = false }),
		prop("bench", 18, 0, 40, 1, -90),
	},
	decorDensity = 1,
})

--------------------------------------------------------------------------------
-- ENT-03 : atelier du putt
--------------------------------------------------------------------------------
-- Inclinaison du green : 1,2° autour de X (côté +Z plus bas) et 0,6° autour de Z (côté +X plus haut).
-- Altitude du trou = -1 + tan(0,6°) × 4 - tan(1,2°) × 6 ≈ -1,084 (recalée exactement à la construction).
table.insert(holes, {
	id = "ENT-03",
	name = "L'Atelier du Putt",
	biome = "Training",
	par = 2,
	difficulty = 1,
	targetTime = 45,
	feature = "Petit green en légère pente pour apprendre à lire la ligne de putt",
	seed = 1003,
	path = {
		node(0, 0, 0, 20),
		node(0, -0.5, 24, 22),
		node(0, -1, 40, 22),
	},
	cup = V(4, -1.084, 46),
	green = { radius = 12, tilt = V(1.2, 0, 0.6) },
	itemBoxes = {},
	props = {
		prop("flowerbed", -14, -0.7, 30, 1),
		prop("flowerbed", 14, -0.6, 26, 1),
		prop("bench", -10, 0, -6, 1, 90),
		prop("lamp", 14, 0, 4, 1),
	},
	decorDensity = 0.8,
})

return holes
