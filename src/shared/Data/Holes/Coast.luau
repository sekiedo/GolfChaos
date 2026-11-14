--!strict
--[[
	Trous de la Côte (biome Coast, préfixe COT) : îles, plages, ponts, falaises, passages au-dessus de l'eau.
	Plan : docs/PLAN_PARCOURS.md ; format et règles : docs/FORMAT_TROUS.md ; textes : Locale/fr|en/HolesCoast.luau.

	COT-01..COT-06 sont les trous de RÉFÉRENCE (exemples complets pour les auteurs de biomes).
	Pour ajouter COT-07..COT-18 : copier un bloc `table.insert(holes, {...})`, garder les helpers ci-dessous,
	ajouter les clés "hole.COT-NN.name/feature" dans les deux fichiers Locale, puis lancer
	require(game.ServerStorage.Tests.Runner).run("Holes") dans Studio.

	Rappels (détails dans FORMAT_TROUS) :
	- Repère local : X latéral (+X = GAUCHE du joueur qui regarde vers le trou), Y haut, Z vers le trou ; studs.
	- Un nœud décrit le segment qui COMMENCE à lui (surface, kind, largeur) ; le dernier nœud = centre du green.
	- La mer de la Côte est posée automatiquement 5 studs sous le nœud le plus bas (danger "water").
	- Obstacles : `center` = centre géométrique (y = sol + size.Y / 2) ; `size` = (épaisseur X, hauteur Y,
	  longueur Z) dans le repère tourné de `yaw`.
	- Boîtes d'objets : position = sol + 3 (centre de la boîte). Voiturettes : CFrame au sol + 2.
]]

local Types = require(script.Parent.Parent.Parent.Types)

type HoleDef = Types.HoleDef
type PathNode = Types.PathNode
type PropDef = Types.PropDef
type ObstacleDef = Types.ObstacleDef

local V = Vector3.new

-- Nœud de chemin : position, largeur, surface et nature du segment qui commence ici.
local function node(x: number, y: number, z: number, w: number?, surface: Types.Surface?, kind: any?): PathNode
	return { p = V(x, y, z), w = w, surface = surface, kind = kind }
end

local function prop(kind: string, x: number, y: number, z: number, scale: number?, yaw: number?, params: { [string]: any }?): PropDef
	return { kind = kind, position = V(x, y, z), scale = scale, yaw = yaw, params = params }
end

local function obstacle(kind: string, center: Vector3, size: Vector3?, yaw: number?, params: { [string]: any }?): ObstacleDef
	return { kind = kind, center = center, size = size, yaw = yaw, params = params }
end

local holes: { HoleDef } = {}

--------------------------------------------------------------------------------
-- COT-01 : Le Ponton des Mouettes (par 3, difficulté 1)
-- Départ sur un ponton de bois, traversée d'un lagon peu profond (eau turquoise au-dessus de la mer), green de
-- plage. Le chemin à pied suit le ponton puis une passerelle ; la balle doit survoler le lagon.
--------------------------------------------------------------------------------
table.insert(holes, {
	id = "COT-01",
	name = "Le Ponton des Mouettes",
	biome = "Coast",
	par = 3,
	difficulty = 1,
	targetTime = 70,
	feature = "Départ sur un ponton, courte traversée d'un lagon peu profond vers un green de plage",
	seed = 2101,
	path = {
		node(0, 2, 0, 14, "Wood", "bridge"), -- ponton du départ
		node(0, 2, 40, 10, "Wood", "bridge"), -- passerelle au-dessus du lagon
		node(-6, 2, 100, 26, "Sand"), -- plage
		node(-10, 2.5, 130, 28), -- fairway de plage
		node(-12, 3, 160), -- centre du green
	},
	cup = V(-10, 3, 166),
	green = { radius = 16 },
	hazards = {
		-- Lagon peu profond : plus clair que la mer, son fond descend sous le niveau de la mer.
		{ kind = "water", shape = "box", center = V(0, -1.7, 70), size = V(80, 4, 52) },
	},
	props = {
		prop("buoy", 14, 0.3, 58, 1),
		prop("buoy", -16, 0.3, 80, 1),
		prop("palm", -24, 2, 112, 1.1),
		prop("umbrella", 6, 2, 118, 1, 20),
		prop("palm", 8, 2.5, 138, 1),
		prop("crate", -26, 2.1, 104, 0.8, 15, { solid = false }),
	},
	itemBoxes = { V(-8, 5.2, 115) },
	decorDensity = 1.1,
})

--------------------------------------------------------------------------------
-- COT-02 : Anse aux Galets (par 4, difficulté 1)
-- Dogleg à droite (vers -X) le long d'une plage de galets ; une mare de marée occupe l'intérieur du virage
-- (raccourci risqué). Un muret de pierre retient les balles à l'extérieur du virage.
--------------------------------------------------------------------------------
table.insert(holes, {
	id = "COT-02",
	name = "Anse aux Galets",
	biome = "Coast",
	par = 4,
	difficulty = 1,
	targetTime = 90,
	feature = "Dogleg à droite le long d'une plage de galets, mare de marée dans le virage",
	seed = 2102,
	path = {
		node(0, 4, 0, 26),
		node(0, 4, 70, 28),
		node(0, 5, 140, 50), -- virage élargi : la mare mord l'intérieur
		node(-50, 6, 190, 30),
		node(-110, 6, 215, 26),
		node(-150, 6, 220), -- centre du green
	},
	cup = V(-155, 6, 223),
	green = { radius = 16 },
	hazards = {
		-- Mare de marée posée sur le fairway (0,7 stud d'eau au-dessus de l'herbe).
		{ kind = "water", shape = "cylinder", center = V(-22, 5.4, 150), size = V(24, 1.2, 24) },
	},
	obstacles = {
		-- Muret de galets à l'extérieur du virage (épaisseur 1,5, hauteur 2,5, longueur 30).
		obstacle("wall", V(24, 6.55, 150), V(1.5, 2.5, 30), -22.5, { color = Color3.fromRGB(176, 168, 150), material = "Cobblestone" }),
	},
	props = {
		prop("rock", 18, 4, 40, 0.6),
		prop("rock", -17, 4.4, 100, 0.8),
		prop("rock", 16, 4.2, 112, 0.5),
		prop("umbrella", -60, 6, 213, 1, -30),
		prop("palm", -120, 6, 232, 1.1),
		prop("crate", -84, 6, 186, 0.9),
		prop("barrel", -88, 6, 183, 0.9),
	},
	itemBoxes = { V(0, 7.4, 100), V(-80, 9, 205) },
	shortcuts = {
		{ description = "Couper le virage au-dessus de la mare de marée" },
	},
	decorDensity = 1,
})

--------------------------------------------------------------------------------
-- COT-03 : L'Île du Phare (par 3, difficulté 2)
-- Départ sur la côte, green sur une île au pied du phare ; à pied, on traverse un pont de cordes.
--------------------------------------------------------------------------------
table.insert(holes, {
	id = "COT-03",
	name = "L'Île du Phare",
	biome = "Coast",
	par = 3,
	difficulty = 2,
	targetTime = 65,
	feature = "Green sur une île au pied du phare, accès à pied par un pont de cordes",
	seed = 2103,
	path = {
		node(0, 10, 0, 24),
		node(0, 10, 40, 24),
		node(0, 9, 70, 8, "Wood", "bridge"), -- pont de cordes
		node(0, 9, 130, 44), -- l'île
		node(8, 9.5, 160), -- centre du green
	},
	cup = V(4, 9.5, 166),
	green = { radius = 16 },
	props = {
		prop("lighthouse", -17, 9.2, 140, 0.9),
		prop("palm", 21, 9.2, 138, 1),
		prop("rock", 16, 10, 24, 0.7),
		prop("rock", -14, 10, 32, 0.5),
		prop("buoy", 20, 4, 95, 1),
		prop("buoy", -18, 4, 105, 1),
		prop("flowerbed", -10, 9.3, 150, 0.8),
	},
	itemBoxes = { V(0, 13, 25) },
	windBias = V(2, 0, 0),
	decorDensity = 1,
})

--------------------------------------------------------------------------------
-- COT-04 : Falaise des Cormorans (par 4, difficulté 2)
-- Départ au sommet d'une falaise (y = 40) ; le drive plonge vers le fairway du bas (y = 8). À pied : une rampe
-- de 25° longe la falaise, avec des paliers plats aux virages. Raccourci : sauter la falaise avec les bottes.
--------------------------------------------------------------------------------
table.insert(holes, {
	id = "COT-04",
	name = "Falaise des Cormorans",
	biome = "Coast",
	par = 4,
	difficulty = 2,
	targetTime = 95,
	feature = "Départ en haut de falaise et drive plongeant ; descente à pied par la rampe",
	seed = 2104,
	path = {
		node(0, 40, 0, 26), -- plateau du départ
		node(0, 40, 26, 26), -- belvédère
		node(12, 40, 36, 16), -- palier (virage à plat)
		node(22, 40, 38, 14, "Rock"), -- haut de la rampe
		node(90, 8, 48, 14), -- bas de la rampe (25°)
		node(100, 8, 54, 18), -- palier du bas
		node(96, 8, 90, 28),
		node(80, 8.5, 160, 30),
		node(66, 9, 215), -- centre du green
	},
	cup = V(62, 9, 220),
	green = { radius = 16 },
	props = {
		prop("bench", -12, 40, 22, 1, 90),
		prop("sign", 15, 40, 8, 1, -30, { solid = false }),
		prop("rock", 113, 8, 75, 0.8),
		prop("rock", 64, 8.6, 150, 0.6),
		prop("palm", 101, 8.4, 160, 1),
		prop("flowerbed", 52, 9, 205, 1),
	},
	itemBoxes = { V(100, 11, 70), V(86, 11.4, 140) },
	mobilityBoxes = { V(10, 43, 16) },
	shortcuts = {
		{ description = "Sauter du haut de la falaise directement sur le fairway du bas", requires = "kangaroo_boots" },
	},
	decorDensity = 1,
})

--------------------------------------------------------------------------------
-- COT-05 : Le Chapelet d'Îlots (par 5, difficulté 2)
-- Quatre îlots reliés par trois ponts, une boîte d'objet par îlot, des butoirs sur les îlots 2 et 3.
-- Raccourci : traverser l'eau en ligne droite en la gelant (Boule Givrante).
--------------------------------------------------------------------------------
table.insert(holes, {
	id = "COT-05",
	name = "Le Chapelet d'Îlots",
	biome = "Coast",
	par = 5,
	difficulty = 2,
	targetTime = 125,
	feature = "Quatre îlots reliés par des ponts, une boîte d'objet sur chaque îlot",
	seed = 2105,
	path = {
		node(0, 6, 0, 30), -- îlot 1
		node(0, 6, 45, 40),
		node(5, 6, 75, 10, "Wood", "bridge"), -- pont 1
		node(25, 6, 115, 36), -- îlot 2
		node(35, 7, 150, 40),
		node(40, 7, 170, 10, "Wood", "bridge"), -- pont 2
		node(30, 7, 215, 36), -- îlot 3
		node(20, 8, 250, 40),
		node(15, 8, 270, 10, "Wood", "bridge"), -- pont 3
		node(0, 8, 315, 36), -- îlot 4
		node(-10, 8.5, 360, 36),
		node(-15, 9, 410), -- centre du green
	},
	cup = V(-12, 9, 416),
	green = { radius = 18 },
	obstacles = {
		obstacle("bumper", V(40, 7.7, 140), V(4, 2, 4), 0, { color = Color3.fromRGB(255, 120, 90), strength = 60 }),
		obstacle("bumper", V(14, 8.7, 238), V(4, 2, 4), 0, { color = Color3.fromRGB(255, 120, 90), strength = 60 }),
	},
	props = {
		prop("palm", 21, 6, 30, 1),
		prop("palm", 54, 6.9, 148, 1.1),
		prop("palm", 2, 7.6, 242, 1),
		prop("palm", -25, 8.2, 330, 1.2),
		prop("umbrella", 12, 8.3, 345, 1, 40),
		prop("buoy", -10, 1, 95, 1),
		prop("buoy", 55, 1, 190, 1),
		prop("buoy", -20, 1, 290, 1),
	},
	itemBoxes = { V(0, 9, 25), V(28, 9.5, 130), V(25, 10.5, 232), V(-5, 11.3, 338) },
	carts = { CFrame.new(-10, 8, 18) },
	shortcuts = {
		{ description = "Traverser l'eau en ligne droite entre les îlots en gelant la surface", requires = "frost_bomb" },
	},
	decorDensity = 1,
})

--------------------------------------------------------------------------------
-- COT-06 : Crique des Contrebandiers (par 4, difficulté 2)
-- Le fairway traverse une grotte marine (segment "tunnel" de 70 studs). Stalagmites à la sortie, butin des
-- contrebandiers à l'entrée. Raccourci : jouer par-dessus le toit de la grotte.
--------------------------------------------------------------------------------
table.insert(holes, {
	id = "COT-06",
	name = "Crique des Contrebandiers",
	biome = "Coast",
	par = 4,
	difficulty = 2,
	targetTime = 90,
	feature = "Fairway qui traverse une grotte marine",
	seed = 2106,
	path = {
		node(0, 8, 0, 26),
		node(0, 8, 60, 26),
		node(-10, 8, 110, 24),
		node(-15, 8, 130, 18, "Rock", "tunnel"), -- grotte marine
		node(-20, 8, 200, 26),
		node(-10, 8.5, 250, 28),
		node(5, 9, 300), -- centre du green
	},
	cup = V(2, 9, 305),
	green = { radius = 16 },
	obstacles = {
		obstacle("pillar", V(-10, 11.7, 216), V(3.5, 7, 3.5), 0, { color = Color3.fromRGB(120, 110, 100), material = "Slate" }),
		obstacle("pillar", V(-25, 11.8, 232), V(3.5, 7, 3.5), 0, { color = Color3.fromRGB(120, 110, 100), material = "Slate" }),
	},
	props = {
		prop("crate", 2, 8, 116, 1),
		prop("crate", 3.5, 9.6, 116.5, 0.7, 25),
		prop("barrel", 4, 8, 108, 1),
		prop("lamp", -1, 8, 126, 0.9),
		prop("boat", 30, 3, 160, 1.2, 15),
		prop("rock", 16, 8, 50, 0.7),
	},
	itemBoxes = { V(0, 11, 40), V(-14, 11.3, 230) },
	shortcuts = {
		{ description = "Faire passer la balle par-dessus le toit de la grotte" },
	},
	decorDensity = 1,
})

-- COT-07 .. COT-18 : à ajouter ici (voir docs/PLAN_PARCOURS.md et docs/FORMAT_TROUS.md).

return holes
