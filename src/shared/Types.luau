--!strict
--[[
	Types partagés transverses (contrats entre services, contrôleurs et données).
	Les types propres à un domaine vivent à côté de sa configuration (ex. Config/Items.luau exporte ItemDef).
	Toute modification ici doit rester rétrocompatible : de nombreux modules en dépendent.
]]

local Types = {}

--------------------------------------------------------------------------------
-- Partie
--------------------------------------------------------------------------------

-- Machine à états de la partie (voir docs/ARCHITECTURE.md §Machine à états et shared/Logic/MatchStateMachine).
export type Phase =
	"Lobby" -- accueil : hub jouable, entraînement, boutique
	| "Preparing" -- préparation du salon : l'hôte configure, les joueurs se déclarent prêts
	| "Loading" -- chargement du trou : construction, placement des joueurs et des balles
	| "HoleIntro" -- présentation du trou (survol caméra, nom, par)
	| "Countdown" -- compte à rebours 3-2-1
	| "Playing" -- partie en cours sur le trou
	| "HoleEnd" -- fin du trou : plus aucune action ne modifie les résultats
	| "HoleResults" -- tableau des résultats du trou
	| "Podium" -- fin de partie : podium et récompenses

export type Mode = "FreeForAll" | "Teams" | "Solo" | "Training"
export type Team = "Red" | "Blue"
export type Biome = "Coast" | "Forest" | "Desert" | "Snow" | "City" | "Training"

-- Réglages choisis par l'hôte (validés serveur, figés pendant un trou).
export type MatchSettings = {
	mode: Mode,
	playlist: string, -- "Quick3" | "Front9" | "Full18" | "Biome:<Biome>" | "Mixed" | "Custom"
	holeCount: number, -- 1..18 (playlist personnalisée : longueur de customHoleIds)
	customHoleIds: { string }?,
	biomes: { Biome }?, -- filtre pour "Mixed"
	shuffle: boolean,
	timeScale: number, -- multiplicateur de durée des trous (0.5..2)
	wind: "Off" | "Light" | "Strong" | "Random",
	gameSpeed: number, -- vitesse de jeu (0.75..1.5) : vitesse de déplacement, jauge
	itemsEnabled: boolean,
	itemFrequency: "Low" | "Normal" | "High",
	ballCollisions: boolean, -- interactions entre balles
	friendlyFire: boolean, -- toujours false en mode Équipes (règle), réglable ailleurs
	lateJoin: boolean, -- arrivées tardives autorisées au trou suivant
	experimental16: boolean, -- autorise jusqu'à 16 participants (expérimental)
}

-- Résultat d'un joueur sur un trou.
export type HoleResult = {
	userId: number,
	name: string,
	team: Team?,
	finished: boolean,
	finishOrder: number?, -- 1 = premier arrivé ; nil si non terminé
	finishTime: number?, -- secondes depuis le début du trou
	strokes: number, -- coups + pénalités
	par: number,
	points: number, -- points de la manche (mode Chacun pour soi)
	bonuses: { string }, -- identifiants des bonus obtenus (ex. "birdie", "longShot")
	status: "Finished" | "TimeOut" | "Forfeit" | "Disconnected" | "AFK",
}

--------------------------------------------------------------------------------
-- Trous (format de données : voir docs/FORMAT_TROUS.md)
--------------------------------------------------------------------------------

export type Surface = "Fairway" | "Rough" | "Green" | "Sand" | "Ice" | "Rock" | "Wood" | "Asphalt" | "Snow" | "Mud"

-- Nœud de la ligne centrale du parcours (du départ vers le trou).
export type PathNode = {
	p: Vector3, -- position au sol : x, y = altitude du sol, z
	w: number?, -- largeur praticable (studs), défaut 24
	surface: Surface?, -- surface du segment qui COMMENCE à ce nœud, défaut "Fairway"
	kind: ("ground" | "bridge" | "gap" | "ice" | "tunnel")?, -- nature du segment qui commence ici
}

export type HazardDef = {
	kind: "water" | "oob" | "lava" | "void",
	shape: ("box" | "cylinder")?,
	center: Vector3,
	size: Vector3, -- box : dimensions ; cylinder : (diamètre, hauteur, diamètre)
	yaw: number?, -- degrés
}

export type ObstacleDef = {
	kind: string, -- "wall" | "ramp" | "bumper" | "windmill" | "movingPlatform" | "rotatingBar" | "pillar" | "arch" | "tunnel" | "jumpPad" | "conveyor" | "car" ...
	center: Vector3,
	size: Vector3?,
	yaw: number?,
	params: { [string]: any }?, -- paramètres propres au type (vitesse, amplitude, période, couleur...)
}

export type PropDef = {
	kind: string, -- "tree" | "palm" | "rock" | "cactus" | "pine" | "snowman" | "building" | "lamp" | "bench" | ...
	position: Vector3,
	scale: number?,
	yaw: number?,
	params: { [string]: any }?,
}

export type HoleDef = {
	id: string, -- identifiant stable, ex. "COT-01" (Côte), "FOR-07", "DES-12", "NEI-18", "VIL-09", "ENT-01"
	name: string, -- nom original affiché
	biome: Biome,
	par: number, -- 2..6
	difficulty: number, -- 1 (facile) .. 5 (expert)
	targetTime: number, -- durée cible en secondes pour un joueur moyen
	feature: string, -- particularité du trou (une phrase, affichée au catalogue et à l'intro)
	seed: number, -- graine du décor procédural (décor reproductible)
	path: { PathNode }, -- au moins 2 nœuds ; le premier = zone de départ, le dernier = green
	tee: { position: Vector3, yaw: number? }?, -- défaut : path[1]
	cup: Vector3, -- centre du trou (sur le green)
	green: { radius: number, tilt: Vector3? }?, -- défaut : rayon 14
	hazards: { HazardDef }?,
	obstacles: { ObstacleDef }?,
	props: { PropDef }?,
	checkpoints: { Vector3 }?, -- défaut : générés le long de path
	itemBoxes: { Vector3 }?,
	mobilityBoxes: { Vector3 }?,
	carts: { CFrame }?, -- voiturettes posées sur le parcours
	bounds: { min: Vector3, max: Vector3 }?, -- défaut : boîte englobante de path + marge
	shortcuts: { { description: string, requires: string? } }?, -- raccourcis risqués (documentation + validation)
	decorDensity: number?, -- 0..2, défaut 1
	windBias: Vector3?, -- vent dominant propre au trou (optionnel)
}

-- Données de trou chargé, renvoyées par CourseService.LoadHole.
export type HoleRuntime = {
	def: HoleDef,
	folder: Folder,
	origin: Vector3, -- décalage monde appliqué aux coordonnées locales du HoleDef
	cupPosition: Vector3, -- monde
	cupRadius: number,
	teeCFrame: CFrame, -- monde
	checkpoints: { CFrame }, -- monde, ordonnés du départ vers le trou
	itemBoxes: { Vector3 },
	killY: number, -- altitude sous laquelle tout est hors limites
	bounds: { min: Vector3, max: Vector3 }, -- monde
	pathLength: number, -- longueur de la ligne centrale (studs)
}

return Types
