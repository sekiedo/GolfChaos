--!strict
--[[
	Config/Course : réglages de construction et de validation des parcours (CourseService, HoleBuilder,
	LobbyBuilder, Obstacles, Props, Biomes/Common, Logic/HoleValidator).

	DONNÉES UNIQUEMENT : la géométrie est produite par server/Course/*, les règles de validation par
	shared/Logic/HoleValidator.luau. Guide d'écriture des trous : docs/FORMAT_TROUS.md.

	Unités : studs, secondes, degrés (sauf mention contraire).
	Repère LOCAL d'un trou : X latéral, Y vers le haut, Z vers l'avant (du départ vers le trou), origine au
	départ. AUCUN miroir : monde = origine + local (contrat commun HoleBuilder / CourseService / Obstacles).
	Attention : Roblox est un repère direct ; un joueur placé au départ et regardant vers +Z voit +X sur sa
	GAUCHE (voir docs/FORMAT_TROUS.md §2).
	Un cap (`yaw`) se mesure en degrés : direction = (sin yaw, 0, cos yaw) ; 0 = +Z, 90 = +X.
]]

local Course = {}

-- Décalages monde (raccourcis de premier niveau utilisés par CourseService ; identiques à Course.World).
Course.LobbyOrigin = Vector3.new(0, 0, 0)
Course.HoleOrigin = Vector3.new(0, 0, 5000)

--------------------------------------------------------------------------------
-- Monde
--------------------------------------------------------------------------------
Course.World = {
	LobbyOrigin = Course.LobbyOrigin, -- centre de la place de l'accueil (dessus du sol)
	RangeOrigin = Vector3.new(0, 0, -118), -- départ du Driving Range (ENT-01), derrière la porte d'entraînement
	TutorialOrigin = Vector3.new(-240, 0, -118), -- départ du trou tutoriel (ENT-02)
	HoleOrigin = Course.HoleOrigin, -- trous de partie : très loin de l'accueil, un seul chargé à la fois
	PreviewOrigin = Vector3.new(3000, 0, 0), -- BuildPreview sans origine précisée
	FolderName = "Course", -- Workspace.Course (trou chargé)
	LobbyFolderName = "Lobby", -- Workspace.Lobby (accueil + entraînement)
	PreviewFolderName = "CoursePreviews", -- Workspace.CoursePreviews (inspection en mode Édition)
}

Course.Training = {
	RangeId = "ENT-01",
	TutorialId = "ENT-02",
	PuttingId = "ENT-03",
}

-- Préfixe d'identifiant -> biome (format "PPP-NN", ex. "COT-07").
Course.IdPrefixes = {
	COT = "Coast",
	FOR = "Forest",
	DES = "Desert",
	NEI = "Snow",
	VIL = "City",
	ENT = "Training",
} :: { [string]: string }

-- Ordre d'affichage / d'agrégation des biomes (Data/Holes).
Course.BiomeOrder = { "Coast", "Forest", "Desert", "Snow", "City", "Training" } :: { string }

--------------------------------------------------------------------------------
-- Énumérations du format (Types.luau) et catalogues de types d'éléments
--------------------------------------------------------------------------------
Course.Biomes = { "Coast", "Forest", "Desert", "Snow", "City", "Training" } :: { string }
Course.Surfaces = { "Fairway", "Rough", "Green", "Sand", "Ice", "Rock", "Wood", "Asphalt", "Snow", "Mud" } :: { string }
Course.SegmentKinds = { "ground", "bridge", "gap", "ice", "tunnel" } :: { string }
Course.HazardKinds = { "water", "oob", "lava", "void" } :: { string }

-- Attribut "Surface" posé sur les pièces : nom compris par BallService (clés de Config/Gameplay.Surfaces).
-- Les dix surfaces du format existent toutes dans Gameplay.Surfaces : la correspondance est l'identité.
-- (Gameplay.DefaultSurface = "Grass" ne sert qu'aux pièces sans attribut.)
Course.SurfaceAttribute = {
	Fairway = "Fairway",
	Rough = "Rough",
	Green = "Green",
	Sand = "Sand",
	Ice = "Ice",
	Rock = "Rock",
	Wood = "Wood",
	Asphalt = "Asphalt",
	Snow = "Snow",
	Mud = "Mud",
} :: { [string]: string }

-- Obstacles (construits par server/Course/Obstacles.luau, jamais par HoleBuilder). Liste fermée reconnue par
-- Logic/HoleValidator ; paramètres documentés dans docs/FORMAT_TROUS.md §8.
Course.ObstacleKinds = {
	"wall",
	"ramp",
	"bumper",
	"windmill",
	"movingPlatform",
	"rotatingBar",
	"pillar",
	"arch",
	"tunnel",
	"jumpPad",
	"conveyor",
	"car",
} :: { string }

-- Alias (aucun pour l'instant : un alias doit d'abord être géré par Obstacles.luau).
Course.ObstacleAliases = {} :: { [string]: string }

-- Obstacles animés côté serveur.
Course.AnimatedObstacleKinds = {
	windmill = true,
	movingPlatform = true,
	rotatingBar = true,
	car = true,
} :: { [string]: boolean }

-- Obstacles dont le dessus est praticable (comptent dans les bornes et l'altitude de la zone mortelle).
Course.WalkableObstacleKinds = {
	ramp = true,
	movingPlatform = true,
	tunnel = true,
	jumpPad = true,
	conveyor = true,
} :: { [string]: boolean }

-- Accessoires (server/Course/Props.luau). DOIT rester identique à Props.kinds() (vérifié par Holes.spec).
Course.PropKinds = {
	"tree",
	"pine",
	"palm",
	"birch",
	"bush",
	"rock",
	"boulder",
	"cactus",
	"duneGrass",
	"snowman",
	"iceCrystal",
	"building",
	"house",
	"hut",
	"lamp",
	"bench",
	"fence",
	"banner",
	"buoy",
	"umbrella",
	"lighthouse",
	"crate",
	"barrel",
	"cone",
	"sign",
	"mushroom",
	"flowerbed",
	"reeds",
	"flag",
	"boat",
	"dune",
	"distanceMarker",
	"targetGreen",
} :: { string }

-- Accessoires bloquants quand ils sont posés explicitement sur le trou (`props` du HoleDef ; params.solid
-- force true/false). Le décor de fond généré n'est JAMAIS bloquant (groupe de collision "Props").
Course.SolidProps = {
	tree = true,
	pine = true,
	palm = true,
	birch = true,
	rock = true,
	boulder = true,
	cactus = true,
	snowman = true,
	iceCrystal = true,
	house = true,
	hut = true,
	building = true,
	lamp = true,
	fence = true,
	lighthouse = true,
	crate = true,
	barrel = true,
	boat = true,
	buoy = true,
	mushroom = true,
} :: { [string]: boolean }

-- Accessoires que le Méga Burger peut briser (attribut "Breakable", docs/MATRICE_INTERACTIONS.md).
Course.BreakableProps = {
	bush = true,
	flowerbed = true,
	mushroom = true,
	snowman = true,
	iceCrystal = true,
	lamp = true,
	bench = true,
	fence = true,
	sign = true,
	umbrella = true,
	crate = true,
	barrel = true,
	cone = true,
	flag = true,
	banner = true,
	reeds = true,
	duneGrass = true,
} :: { [string]: boolean }

--------------------------------------------------------------------------------
-- Chemin principal (ruban de fairway)
--------------------------------------------------------------------------------
Course.Path = {
	DefaultWidth = 24, -- largeur praticable d'un nœud sans `w`
	BridgeDefaultWidth = 10, -- largeur d'un segment "bridge"/"tunnel" dont le nœud n'a pas de `w`
	MinWidth = 10, -- largeur minimale d'un segment au sol du chemin principal (erreur en dessous)
	MinBridgeWidth = 6, -- largeur minimale d'un pont ou d'un tunnel (erreur en dessous)
	NarrowWidth = 14, -- avertissement : segment au sol plus étroit
	MaxWidth = 120, -- largeur maximale d'un nœud
	MaxNodes = 64,
	MinSegmentLength = 1, -- deux nœuds plus proches sont refusés
	MaxSlopeDeg = 30, -- pente maximale du chemin principal (marche)
	MaxGap = 6, -- longueur horizontale maximale d'un segment "gap" (saut sans objet)
	MaxGapRise = 2.5, -- montée maximale au-dessus d'un "gap"
	RibbonThickness = 1.2, -- épaisseur du ruban de fairway
	RoughWidth = 6, -- bordure de rough de chaque côté du ruban (au sol uniquement)
	RoughDrop = 0.06, -- le rough est un peu plus bas que le fairway (pas de scintillement)
	TurnSlopeWarnTurnDeg = 25, -- avertissement : virage marqué...
	TurnSlopeWarnSlopeDeg = 12, -- ...sur un nœud bordé d'une pente plus forte que ceci
	StripedFairway = true, -- alternance de teinte des bandes de tonte
	StripeLength = 18, -- longueur d'une bande de tonte (studs)
	JointSectorDeg = 30, -- secteur maximal d'un triangle de jointure (virages arrondis)
	EdgeLip = 0.45, -- le rebord biseauté est 0,45 stud sous le dessus du ruban...
	EdgeLipOverhang = 0.6, -- ... et déborde de 0,6 stud de chaque côté
	EdgeLipThickness = 1.6,
	CurbMinElevation = 14, -- bordure basse sur un segment au sol à plus de 14 studs au-dessus du nœud le plus bas
	CurbHeight = 0.9,
	CurbWidth = 0.8,
	GreenApproachMaxSlopeDeg = 4, -- avertissement : dernier segment trop pentu à l'entrée du green
}

-- Fondation en terre/roche sous le chemin, jusqu'au sol de fond (le parcours forme des plateaux).
Course.Foundation = {
	Enabled = true,
	MinDepth = 6,
}

-- Zone mortelle et sol de fond.
Course.KillMargin = 30 -- killY = altitude la plus basse du parcours (nœuds, obstacles praticables) - 30
Course.KillDepth = Course.KillMargin -- alias explicite
Course.GroundBelowKill = 4 -- le sol de fond (décor) est 4 studs sous killY : tout ce qui tombe le franchit
Course.SeaBelowPath = 5 -- biome à mer : niveau de la mer 5 studs sous le nœud le plus bas
Course.SeaDepth = 6

-- Bornes par défaut (boîte englobante de l'aire praticable + marge).
Course.Bounds = {
	Margin = 40,
	Ceiling = 160, -- hauteur au-dessus du point le plus haut (les balles hautes ne sont jamais hors limites)
	Floor = 40, -- profondeur sous le point le plus bas
}

--------------------------------------------------------------------------------
-- Départ, green, trou, drapeau
--------------------------------------------------------------------------------
Course.Tee = {
	MaxPlayers = 16,
	BoxWidth = 54, -- assez large pour 16 balles espacées de 3,2 studs
	BoxDepth = 14,
	BoxThickness = 1,
	BoxRaise = 0.2, -- le tertre dépasse légèrement du fairway
	BallSpacing = 3.2, -- espacement minimal entre deux balles (exigence : >= 3)
	BallLineOffset = 2, -- ligne des balles légèrement en avant du centre du tertre
	RowSpacing = 4, -- au-delà de MaxPlayers : rangée supplémentaire derrière
	PlayerOffset = Vector3.new(0, 3, 3.5), -- position du joueur relative à un emplacement de départ (derrière la balle)
	MaxOffsetFromFirstNode = 12, -- `tee.position` doit rester près du premier nœud
	MaxRiseFromFirstNode = 2,
	MarkerSize = 1.4, -- repères colorés aux coins avant du tertre
}

Course.Green = {
	DefaultRadius = 14,
	MinRadius = 8,
	MaxRadius = 30,
	FringeWidth = 3, -- avant-green (surface Fairway)
	Raise = 0.06, -- le green dépasse légèrement du ruban
	Thickness = 1,
	MaxTiltDeg = 1.5, -- au-delà, une balle peut ne jamais s'arrêter (avertissement)
	MaxTiltErrorDeg = 3, -- au-delà : erreur
	CupEdgeMargin = 1.5, -- le trou reste à 1,5 stud du bord du green
}

Course.CupRadius = 1.7 -- DOIT être égal à Config/Gameplay.Cup.Radius (capture serveur)
Course.Cup = {
	RingWidth = 0.25, -- anneau blanc autour du trou (visuel)
	RingRaise = 0.02,
	HoleRaise = 0.03, -- disque sombre (visuel, non collidable)
	SnapWarn = 0.6, -- écart d'altitude cup.Y / surface du green : avertissement
	SnapError = 3, -- ... erreur
}

Course.Flag = {
	PoleHeight = 9,
	PoleDiameter = 0.3,
	ClothSize = Vector3.new(3.2, 1.9, 0.12),
}

--------------------------------------------------------------------------------
-- Checkpoints, boîtes, voiturettes
--------------------------------------------------------------------------------
Course.Checkpoint = {
	Spacing = 55, -- espacement des checkpoints générés (longueur de chemin)
	MaxSpacing = 95, -- avertissement au-delà (checkpoints fournis)
	GreenClearance = 6, -- le dernier checkpoint généré est avant le green (rayon + 6)
	SpawnHeight = 3, -- hauteur du CFrame de réapparition au-dessus du sol
	MaxDistanceFromPath = 6, -- un checkpoint fourni reste sur l'aire praticable (+ 6 studs)
	BehindTolerance = 8, -- GetCheckpointFor : on ne réapparaît jamais plus loin que sa progression + 8
}

Course.Boxes = {
	MinItemBoxesFromPar = 4, -- au moins une boîte d'objet à partir du par 4
	MaxDistanceFromPath = 14, -- avertissement : boîte loin du chemin (plateforme de raccourci ?)
	MaxDistanceError = 60, -- erreur : boîte perdue loin de tout chemin
	Height = 3, -- position d'une boîte = sol + 3 (centre de la boîte)
	-- Boîtes générées quand `itemBoxes` est absent : fractions de la longueur du chemin.
	DefaultFractions = {
		[2] = {},
		[3] = { 0.5 },
		[4] = { 0.35, 0.7 },
		[5] = { 0.3, 0.55, 0.78 },
		[6] = { 0.25, 0.45, 0.65, 0.82 },
	} :: { [number]: { number } },
	DefaultLateralOffset = 5, -- décalage latéral alterné des boîtes générées
}

--------------------------------------------------------------------------------
-- Ponts, tunnels, dangers
--------------------------------------------------------------------------------
Course.Bridge = {
	DeckThickness = 1,
	RailHeight = 2.2,
	RailThickness = 0.5,
	PostSpacing = 12,
	PillarSpacing = 30,
	PillarWidthRatio = 0.4,
	BeamHeight = 1.2, -- poutres latérales sous le tablier
}

Course.Tunnel = {
	Height = 12,
	WallThickness = 2,
	RoofThickness = 2,
}

Course.Hazards = {
	BedThickness = 1, -- fond collidable sous l'eau et la lave (la balle s'arrête DANS le volume)
	OobStakeHeight = 4, -- piquets blancs aux coins d'une zone hors limites
	OobStakeDiameter = 0.5,
	MinSize = 2, -- dimension minimale d'un volume (erreur en dessous)
}

--------------------------------------------------------------------------------
-- Obstacles animés
--------------------------------------------------------------------------------
Course.Animation = {
	ContactInterval = 0.1, -- période des requêtes spatiales de contact (recul des joueurs)
	ContactCooldown = 0.8, -- même obstacle -> même joueur
	MaxStep = 0.1, -- pas maximal intégré par image (s)
}

--------------------------------------------------------------------------------
-- Décor de fond (Biomes/Common et modules de biome)
--------------------------------------------------------------------------------
Course.Decor = {
	MaxParts = 650, -- budget de pièces du décor de fond par trou (plafonné aussi par MaxPartsPerHole)
	GroundMargin = 160, -- le sol de fond déborde des bornes de cette marge
	VergeSpacing = 16, -- pas entre deux emplacements de décor de bordure
	VergeChance = 0.45, -- probabilité d'un décor à chaque emplacement (× densités)
	VergeDistance = { 4, 16 }, -- distance au bord extérieur du chemin (studs)
	FarProps = 26, -- accessoires lointains (× densité)
	FarDistance = { 30, 110 },
	CorridorClearance = 3, -- marge autour du couloir de jeu, du green, du départ et des dangers
	MaxAttemptsFactor = 4,
	BackdropRingRadius = 260, -- rayon de l'anneau de décor lointain (montagnes, immeubles...)
}

Course.MaxPartsPerHole = 1500 -- budget de pièces par trou, décor compris (avertissement au-delà)
Course.PartBudget = Course.MaxPartsPerHole -- alias explicite

--------------------------------------------------------------------------------
-- Accueil
--------------------------------------------------------------------------------
Course.Lobby = {
	PlazaRadius = 72,
	PlazaThickness = 2,
	KillDepth = 45, -- killY de l'accueil = origine.Y - 45
	SpawnPadCount = 8,
	SpawnRingRadius = 22,
	SpawnHeight = 3,
	HedgeHeight = 4,
	BarrierHeight = 24, -- mur invisible derrière la haie
	GateWidth = 18, -- ouverture vers le Driving Range
	WalkwayWidth = 16,
	PromptDistance = 12,
	ZoneSize = Vector3.new(14, 8, 14),
	Bounds = { Margin = 40, Ceiling = 200 },
}

--------------------------------------------------------------------------------
-- Validation (Logic/HoleValidator)
--------------------------------------------------------------------------------
Course.Validation = {
	ParMin = 2,
	ParMax = 6,
	DifficultyMin = 1,
	DifficultyMax = 5,
	-- Longueur du chemin (studs) par par. Physique : un drive porte ~150-220 studs roulement compris.
	ParLength = {
		[2] = { 30, 120 },
		[3] = { 120, 220 },
		[4] = { 230, 380 },
		[5] = { 380, 560 },
		[6] = { 560, 760 },
	} :: { [number]: { number } },
	-- Le Driving Range (ENT-01) n'est pas un vrai trou : longueur non contrôlée.
	LengthExempt = { ["ENT-01"] = true } :: { [string]: boolean },
	-- Durée estimée d'un joueur moyen = longueur × WanderFactor / WalkSpeed + (par + ExtraShots) × SecondsPerShot.
	WalkSpeed = 16, -- identique à Config/Gameplay.Movement.WalkSpeed
	WanderFactor = 1.15,
	SecondsPerShot = 9,
	ExtraShots = 1,
	TargetTimeWarnLow = 0.6, -- targetTime / estimation hors [0,6 ; 2,2] : avertissement
	TargetTimeWarnHigh = 2.2,
	MinTargetTime = 20,
	MaxTargetTime = 900,
	DecorDensityMax = 2,
	PropScaleMin = 0.2,
	PropScaleMax = 6,
	WindBiasWarn = 14,
	MaxShortcuts = 6,
	IdPattern = "^(%u%u%u)%-(%d%d)$",
}

return Course
