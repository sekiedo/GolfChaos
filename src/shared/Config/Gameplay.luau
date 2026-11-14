--!strict
--[[
	Config/Gameplay : réglages du golf (balle, frappes, trou, vent, dangers), du combat cartoon (KO, frappe
	de proximité, plongeon, tir de balle guidé) et des déplacements (vitesse, contrôle de plausibilité).

	DONNÉES UNIQUEMENT : les règles qui exploitent ces valeurs vivent dans shared/Logic/BallMath.luau et
	server/Services/{BallService, CombatService, MovementService, CollisionService, NetworkValidation}.luau.
	Ce module est lu par le serveur (autorité) ET par le client (aperçu de trajectoire, jauge, HUD) :
	il ne contient aucun secret et le serveur revalide tout ce que le client envoie.

	Unités : studs, secondes, studs/s, studs/s², degrés (sauf mention contraire).
	Gravité du monde : Workspace.Gravity (196,2 dans default.project.json). La balle n'en subit qu'une fraction
	(Ball.GravityScale) grâce à une VectorForce de compensation : g_balle = Workspace.Gravity × GravityScale.

	Équité : un skin de balle ou d'avatar ne modifie AUCUNE de ces valeurs (même Part de collision pour tous,
	portées et impacts calculés sur le HumanoidRootPart et sur la Part serveur de la balle).
]]

-- Types de frappe acceptés par Golf.Shoot (5e argument, "string:8?") ; nil = Shot.DefaultType.
export type ShotType = "Drive" | "Chip" | "Putt" | "Guided"
export type HazardKind = "water" | "oob" | "lava" | "void"
-- Surfaces reconnues : celles de Types.Surface (données des trous) + "Grass" (surface par défaut héritée).
export type SurfaceName =
	"Grass"
	| "Fairway"
	| "Green"
	| "Rough"
	| "Sand"
	| "Ice"
	| "Rock"
	| "Wood"
	| "Asphalt"
	| "Snow"
	| "Mud"

export type ShotTypeDef = {
	MinLoft: number, -- angle de frappe minimal (degrés au-dessus de l'horizontale)
	MaxLoft: number,
	DefaultLoft: number,
	MinSpeed: number, -- vitesse de lancement à 0 % de puissance (avant PowerScale)
	MaxSpeed: number, -- vitesse de lancement à 100 % de puissance (avant PowerScale)
	PowerScale: number, -- multiplicateur appliqué à la vitesse finale (Chip : 0,6)
	PowerCurve: number, -- exposant puissance -> vitesse (1 = linéaire ; > 1 = plus de précision aux faibles puissances)
}

export type SurfaceDef = {
	Drag: number, -- freinage de roulement proportionnel à la vitesse (1/s)
	RollResistance: number, -- freinage de roulement constant (studs/s²) : immobilise la balle sur les pentes douces
	Friction: number, -- PhysicalProperties de la balle sur cette surface (poids 100 : la balle impose ses valeurs)
	Elasticity: number, -- rebond (aussi utilisé pour la réflexion de l'anti-traversée)
}

local Gameplay = {}

--------------------------------------------------------------------------------
-- Groupes de collision (noms exacts ; matrice documentée dans CollisionService)
--------------------------------------------------------------------------------
Gameplay.CollisionGroups = {
	Balls = "Balls",
	Characters = "Characters",
	Vehicles = "Vehicles",
	Projectiles = "Projectiles",
	Ghosts = "Ghosts", -- joueurs ayant terminé le trou (intangibles)
	Course = "Course", -- géométrie jouable du parcours (sol, murs, obstacles)
	Props = "Props", -- décor non bloquant
}

Gameplay.Collision = {
	BallBallDefault = false, -- interactions physiques entre balles hors partie (accueil)
	-- Pendant une partie, suit MatchSettings.ballCollisions (GameState.SettingsJson) ; SetBallCollisions
	-- impose une valeur jusqu'au prochain changement de réglages ou de phase.
	SyncBallCollisionsWithSettings = true,
	CharactersCollide = true, -- les avatars se bousculent entre eux (comportement Roblox par défaut)
	AutoGhostOnHoleFinished = true, -- un joueur dont l'attribut HoleFinished passe à true devient fantôme
}

--------------------------------------------------------------------------------
-- Balle
--------------------------------------------------------------------------------
Gameplay.Ball = {
	Diameter = 1.2,
	Density = 0.7, -- constante pour toutes les surfaces : masse identique pour tous (aucun skin ne la change)
	Color = Color3.fromRGB(255, 255, 255), -- Part de référence neutre ; le client affiche le skin par-dessus
	GravityScale = 0.5, -- fraction de Workspace.Gravity subie par la balle (trajectoires plus longues, arcade)
	MaxSpeed = 160, -- plafond (studs/s) : limite le déplacement entre deux pas et donc les risques de traversée
	RestSpeed = 1.2, -- sous cette vitesse la balle est candidate à l'arrêt...
	RestTime = 0.6, -- ...pendant cette durée (s)
	RestSlopeMargin = 1.25, -- arrêt permis si g_balle × sin(pente) <= RollResistance × marge
	MaxMoveTime = 30, -- arrêt forcé de sécurité (s)
	GroundRayExtra = 0.6, -- marge du rayon vers le sol sous la balle
	DragMaxVerticalSpeed = 8, -- pas de freinage de roulement pendant un grand rebond
	AirDrag = 0.04, -- traînée de l'air en vol (1/s) ; utilisée aussi par l'aperçu de trajectoire client
	LiftOff = 0.1, -- décollage vertical appliqué au moment de la frappe (studs)
	KillHeight = -60, -- altitude « vide » par défaut si CourseService ne fournit pas de killY
	TerrainWater = true, -- l'eau du Terrain est un danger "water"
	HazardCheckInterval = 0.1, -- période des contrôles coûteux (eau du Terrain, hors-limites CourseService)
	RestingSupportInterval = 0.25, -- période de vérification du sol sous une balle immobile (plateforme disparue...)
	SupportProbeExtra = 0.35, -- profondeur sondée sous une balle immobile (au-delà du rayon)
	ResetMinDelay = 1, -- délai mini après une frappe avant d'accepter Golf.ResetBall d'une balle en mouvement (s)
	ResetMinDistance = 0.5, -- Golf.ResetBall refusé si la balle est déjà à sa dernière position valide
	ServerTrail = true, -- traînée sur la Part serveur pendant le vol (le client peut la masquer localement)
	TrailLifetime = 0.45,
	FolderName = "Balls", -- Workspace.Balls
	Tag = "GolfBall", -- tag CollectionService posé sur chaque balle
	SimFolderName = "SimBalls", -- Workspace.SimBalls : balles sans propriétaire des outils de validation
	PracticeBallsCanHitPlayers = false, -- balles d'entraînement (accueil) : pas de KO
	PracticeWind = false, -- le vent du trou ne s'applique pas aux balles d'entraînement
	-- Phases où une balle créée sans précision devient une balle d'entraînement (coups non comptés en partie).
	PracticePhases = { "Lobby", "Preparing" } :: { string },
	ErrorLogLimit = 3, -- erreurs de simulation journalisées par balle (évite d'inonder la console)
}

--------------------------------------------------------------------------------
-- Anti-traversée (balayage Spherecast entre deux pas serveur)
--------------------------------------------------------------------------------
Gameplay.AntiTunneling = {
	Enabled = true,
	CastRadiusScale = 0.8, -- rayon balayé = rayon de la balle × 0,8 (pas de faux contact avec le sol de roulement)
	MinSweepDistance = 0.05, -- en dessous, aucun balayage
	MaxSweepDistance = 1000, -- borne de l'API Spherecast (1024)
	-- Confirmation : le CENTRE de la balle doit avoir franchi une surface (rayon fin le long du même segment).
	-- Un relief franchi par-dessus (bordure, crête) ne déclenche donc jamais de correction.
	ConfirmWithCenterRay = true,
	SkinDistance = 0.05, -- marge de replacement devant la surface touchée
	TangentialKeep = 0.9, -- fraction de la vitesse tangentielle conservée après correction
}

--------------------------------------------------------------------------------
-- Balle bloquée (vibre ou reste coincée sans se déplacer)
--------------------------------------------------------------------------------
Gameplay.Stuck = {
	MinDisplacement = 0.35, -- déplacement (studs) sous lequel la balle est considérée immobile
	Time = 3, -- durée sans déplacement notable avant immobilisation forcée (s)
}

--------------------------------------------------------------------------------
-- Trou (capture balayée segment–cercle côté serveur)
--------------------------------------------------------------------------------
Gameplay.Cup = {
	Radius = 1.7, -- rayon du trou (studs) ; BallService.SetCup peut le préciser par trou
	MinRadius = 0.5,
	MaxRadius = 6,
	CaptureTolerance = 0.1, -- marge ajoutée au rayon de capture
	CaptureSpeed = 34, -- vitesse HORIZONTALE max (studs/s) pour tomber quand la balle passe au centre
	EdgeSpeedFactor = 0.5, -- au bord du trou, la vitesse max de capture est réduite de 50 % (balles rapides : ressortie)
	VerticalAbove = 1.25, -- centre de la balle au plus 1,25 au-dessus du niveau du trou (une balle en vol passe au-dessus)
	VerticalBelow = 1.5, -- tolérance sous le niveau du trou
	GimmeRadius = 2.3, -- balle presque arrêtée en équilibre sur le bord (centre à moins de 2,3 studs) : elle tombe
	GimmeDelay = 0.4, -- délai avant la chute d'une balle en équilibre (s), sans coup supplémentaire
	SinkDepth = 1.2, -- animation : profondeur atteinte dans le trou
	SinkTime = 0.3, -- animation : durée (s)
	LipOutDeflectDeg = 14, -- balle trop rapide qui passe sur le trou : légère déviation...
	LipOutSpeedKeep = 0.85, -- ...et perte de vitesse
	LipOutCooldown = 0.3, -- une seule déviation par passage (s)
	RequirePlayingPhase = true, -- capture uniquement pendant la phase "Playing" (les résultats sont figés après)
}

--------------------------------------------------------------------------------
-- Dangers et pénalités
--------------------------------------------------------------------------------
Gameplay.Hazards = {
	Tag = "GolfHazard", -- tag CollectionService des volumes dangereux (Parts) ; attribut Hazard = HazardKind
	DefaultKind = "water" :: HazardKind, -- attribut Hazard absent ou inconnu
	OobRequiresGround = true, -- hors limites : seulement quand la balle touche le sol (survoler est permis)
	UseCourseBounds = true, -- consulte aussi CourseService.IsOutOfBounds(position) (s'il existe)
	-- Coups ajoutés par motif (Golf.ResetBall = "stuck" : règle « coup et distance »).
	Penalties = {
		water = 1,
		oob = 1,
		lava = 1,
		void = 1,
		stuck = 1,
	} :: { [string]: number },
	MaxPenalty = 10, -- borne des pénalités demandées par les autres services
	-- Balle mise en mouvement par un tiers (objet, plateforme disparue) puis tombée dans un danger : pas de pénalité.
	WaiveForExternalImpulse = true,
}

--------------------------------------------------------------------------------
-- Vent (accélération horizontale en vol, studs/s²)
--------------------------------------------------------------------------------
Gameplay.Wind = {
	MaxAcceleration = 40, -- borne de sécurité de BallService.SetWind
	PublishToGameState = true, -- SetWind recopie la valeur dans GameState.Wind (HUD et aperçu client)
	-- Intensités indicatives des réglages d'hôte (MatchSettings.wind) pour MatchService.
	Strengths = {
		Off = 0,
		Light = 5,
		Strong = 12,
	} :: { [string]: number },
	RandomMin = 0,
	RandomMax = 14,
}

--------------------------------------------------------------------------------
-- Frappes
--------------------------------------------------------------------------------
Gameplay.Shot = {
	DefaultType = "Drive" :: ShotType,
	TypeOrder = { "Drive", "Chip", "Putt", "Guided" } :: { ShotType }, -- ordre de sélection côté client
	PowerPeriod = 1.6, -- durée d'un aller-retour complet de la jauge 0 -> 1 -> 0 (s)
	PowerTolerance = 0.2, -- écart max accepté entre la puissance client et la puissance recalculée par le serveur
	PowerReportDeviation = 0.45, -- écart client/serveur au-delà duquel la frappe est signalée à NetworkValidation
	GaugeFollowsGameSpeed = false, -- true : période / MatchSettings.gameSpeed (le client doit appliquer la même règle)
	MinSwingTime = 0.12, -- délai mini entre « début de jauge » et « frappe » (s)
	MaxSwingTime = 12, -- délai maxi (s)
	Cooldown = 0.4, -- délai mini entre deux frappes (s)
	LoftStep = 3, -- degrés par cran de molette (client)
	AimEnterDistance = 9, -- distance joueur–balle pour entrer en mode visée
	AimExitDistance = 14, -- au-delà, la visée est annulée
	DistanceTolerance = 4, -- tolérance serveur (latence)
	AimWatchInterval = 0.25, -- période de surveillance des joueurs en visée (distance, phase, état) (s)
	SwingAnimTime = 0.6, -- durée de l'attribut AnimState = "Swing" après une frappe (s)
	PuttSurfaces = { "Green" } :: { string }, -- surfaces où le putt est toujours permis...
	PuttMaxCupDistance = 30, -- ...sinon seulement à moins de 30 studs (horizontaux) du trou
	-- Frappe forcée (Klaxon, BallService.ForceShot) :
	--   joueur qui charge   -> frappe immédiate à la puissance serveur courante ;
	--   joueur qui vise     -> "weak" : frappe faible et imprécise ; "none" : refus (l'objet annule alors la visée).
	ForcedShotWhenAiming = "weak",
	ForcedWeakPowerMin = 0.08,
	ForcedWeakPowerMax = 0.3,
	ForcedWeakSpreadDeg = 30,
	ForcedShotType = "Drive" :: ShotType, -- type de la frappe forcée loin du trou...
	ForcedShotTypeNearCup = "Putt" :: ShotType, -- ...et quand le putt est permis
	-- Attributs de PERSONNAGE qui interdisent de viser, et effets d'ItemService (HasEffect) équivalents.
	AimBlockingCharacterAttributes = { "Frozen", "Giant", "Dazzled" } :: { string },
	AimBlockingEffects = { "frozen", "dazzled", "giant" } :: { string },
	-- Frappe amplifiée (Club Propulseur, BallService.SetShotBoost) : bornes de sécurité.
	ShotBoostMaxMultiplier = 2,
	ShotBoostMaxDuration = 30,
}

Gameplay.ShotTypes = {
	-- Longue frappe, angle réglable (prototype : 25 -> 150 studs/s, loft 8–60).
	Drive = {
		MinLoft = 8,
		MaxLoft = 60,
		DefaultLoft = 28,
		MinSpeed = 25,
		MaxSpeed = 150,
		PowerScale = 1,
		PowerCurve = 1,
	} :: ShotTypeDef,
	-- Coup lobé : haut et court (puissance × 0,6).
	Chip = {
		MinLoft = 48,
		MaxLoft = 60,
		DefaultLoft = 52,
		MinSpeed = 25,
		MaxSpeed = 150,
		PowerScale = 0.6,
		PowerCurve = 1,
	} :: ShotTypeDef,
	-- Putt : roulé précis (courbe 1,5 = résolution fine pour les petits putts), plafonné à 60 studs/s.
	Putt = {
		MinLoft = 0,
		MaxLoft = 3,
		DefaultLoft = 0,
		MinSpeed = 2,
		MaxSpeed = 60,
		PowerScale = 1,
		PowerCurve = 1.5,
	} :: ShotTypeDef,
	-- Tir de balle guidé vers un adversaire verrouillé (règles : Gameplay.Guided).
	Guided = {
		MinLoft = 2,
		MaxLoft = 20,
		DefaultLoft = 8,
		MinSpeed = 70,
		MaxSpeed = 130,
		PowerScale = 1,
		PowerCurve = 1,
	} :: ShotTypeDef,
} :: { [string]: ShotTypeDef }

--------------------------------------------------------------------------------
-- Tir de balle guidé (verrouillage et esquive)
--------------------------------------------------------------------------------
--[[
	Règles de verrouillage (vérifiées par le SERVEUR au moment de la frappe, depuis les positions serveur ;
	sélection pure : BallMath.pickLockTarget, partagée avec l'aperçu client) :
	  - cible = adversaire (jamais un allié en mode Équipes, jamais soi) dans le cône horizontal de demi-angle
	    LockConeDeg (+ ServerConeSlackDeg côté serveur) autour de la direction visée, entre LockMinDistance et
	    LockRange studs de la balle, à moins de MaxVerticalOffset studs d'altitude ;
	  - en ligne de vue depuis la balle (le décor bloque, les avatars non) ;
	  - ni invisible (attribut Invisible), ni protégé (réapparition), ni KO, ni en plongeon (Dodging),
	    ni ayant terminé le trou, ni spectateur (CombatService.CanAffect) ;
	  - parmi les cibles valides : score = angle (rad) × AngleWeight + distance / LockRange, le plus petit gagne.
	Sans cible valide, la frappe est refusée (Golf.AimCancelled "no_target") : aucun coup n'est compté.
	Pendant le vol : le verrou est vérifié toutes les LosCheckInterval s ; il est ROMPU si la ligne de vue est
	perdue plus de LosGraceTime s, si la cible devient invisible/protégée/KO, plonge (esquive) ou termine.
	Une balle dont le verrou est rompu continue en trajectoire balistique. Le virage est limité à
	MaxTurnRateDeg degrés/s (BallMath.homingStep) ; le guidage cesse au premier contact avec le sol ou après
	MaxHomingTime s. L'attribut de balle GuidedTargetUserId (0 = aucun) annonce la cible à tous les clients.
]]
Gameplay.Guided = {
	Enabled = true,
	AllowPractice = false, -- pas de tir guidé avec une balle d'entraînement (elle ne peut toucher personne)
	LockRange = 90,
	LockMinDistance = 4,
	LockConeDeg = 25, -- demi-angle du cône de verrouillage (aperçu client)
	ServerConeSlackDeg = 8, -- tolérance serveur ajoutée (latence entre l'aperçu client et la frappe)
	MaxVerticalOffset = 40, -- écart d'altitude max entre la balle et la cible
	AngleWeight = 2, -- score de sélection = angle (rad) × AngleWeight + distance / LockRange
	MaxTurnRateDeg = 120, -- virage maximal de la balle guidée (degrés/s)
	MaxHomingTime = 2.5, -- durée maximale du guidage (s)
	LosCheckInterval = 0.1, -- période de vérification du verrou en vol (s)
	LosGraceTime = 0, -- ligne de vue perdue plus longtemps que cela -> verrou rompu (0 = immédiat)
	StopHomingOnGround = true, -- le guidage cesse au premier rebond
	AimHeight = 0.8, -- point visé au-dessus du HumanoidRootPart (torse)
	Cooldown = 6, -- délai entre deux tirs guidés d'un même joueur (s)
	EndsProtection = true, -- tirer sur un adversaire met fin à sa propre protection de réapparition
}

--------------------------------------------------------------------------------
-- Visée / caméra (client) — repris du prototype
--------------------------------------------------------------------------------
Gameplay.Aim = {
	AutoEnter = true, -- true : mode visée dès qu'on s'approche ; false : appuyer sur l'action « Viser »
	CameraDistance = 16,
	FocusHeight = 1.5,
	DefaultPitchDeg = 28,
	MinPitchDeg = 8,
	MaxPitchDeg = 70,
	CameraSmoothing = 14,
	MouseSensitivity = 0.0035,
	TouchSensitivity = 0.006,
	StickSpeed = 2.4,
	IdleArrowPower = 0.5, -- longueur de la flèche tant que la jauge ne tourne pas
	ArrowMinLength = 6,
	ArrowMaxLength = 30,
	ArrowHeadLength = 4,
	FollowDistance = 20, -- caméra qui suit la balle après la frappe
	FollowPitchDeg = 24,
	FollowSmoothing = 6,
	FollowMaxTime = 5,
	FollowStartTimeout = 1.5,
	-- Aperçu de trajectoire (BallMath.predictTrajectory, mêmes paramètres que le serveur).
	PreviewStep = 1 / 30,
	PreviewMaxTime = 4,
	PreviewMaxPoints = 120,
	-- Affichage lissé de la balle (client) vers la position serveur faisant autorité.
	VisualSmoothing = 18, -- 1/s (lissage exponentiel)
	VisualSnapDistance = 12, -- au-delà de cet écart, l'affichage se recale instantanément
}

--------------------------------------------------------------------------------
-- Surfaces
--------------------------------------------------------------------------------
-- Drag/RollResistance : freinage au sol. Friction/Elasticity : PhysicalProperties de la balle.
-- Une Part (ou son modèle parent) peut imposer sa surface avec l'attribut string "Surface" (ex. "Green", "Sand").
Gameplay.DefaultSurface = "Grass" :: SurfaceName

Gameplay.Surfaces = {
	Grass = { Drag = 0.9, RollResistance = 5, Friction = 0.4, Elasticity = 0.45 },
	Fairway = { Drag = 0.8, RollResistance = 4.5, Friction = 0.4, Elasticity = 0.45 },
	Green = { Drag = 0.45, RollResistance = 2.6, Friction = 0.3, Elasticity = 0.35 },
	Rough = { Drag = 2.6, RollResistance = 10, Friction = 0.8, Elasticity = 0.2 },
	Sand = { Drag = 5.5, RollResistance = 24, Friction = 1.0, Elasticity = 0.05 },
	Ice = { Drag = 0.05, RollResistance = 0.4, Friction = 0.02, Elasticity = 0.4 },
	Rock = { Drag = 0.7, RollResistance = 4, Friction = 0.5, Elasticity = 0.6 },
	Wood = { Drag = 0.6, RollResistance = 3.5, Friction = 0.45, Elasticity = 0.55 },
	Asphalt = { Drag = 0.75, RollResistance = 4, Friction = 0.6, Elasticity = 0.55 },
	Snow = { Drag = 3.5, RollResistance = 14, Friction = 0.7, Elasticity = 0.1 },
	Mud = { Drag = 6.5, RollResistance = 28, Friction = 1.0, Elasticity = 0.02 },
} :: { [string]: SurfaceDef }

-- Surface déduite du matériau (Terrain inclus) quand la Part n'a pas d'attribut "Surface".
Gameplay.MaterialSurface = {
	[Enum.Material.Grass] = "Grass",
	[Enum.Material.LeafyGrass] = "Rough",
	[Enum.Material.Mud] = "Mud",
	[Enum.Material.Ground] = "Rough",
	[Enum.Material.Snow] = "Snow",
	[Enum.Material.Sand] = "Sand",
	[Enum.Material.Salt] = "Sand",
	[Enum.Material.Ice] = "Ice",
	[Enum.Material.Glacier] = "Ice",
	[Enum.Material.Rock] = "Rock",
	[Enum.Material.Slate] = "Rock",
	[Enum.Material.Basalt] = "Rock",
	[Enum.Material.Granite] = "Rock",
	[Enum.Material.Marble] = "Rock",
	[Enum.Material.Limestone] = "Rock",
	[Enum.Material.Sandstone] = "Rock",
	[Enum.Material.CrackedLava] = "Rock",
	[Enum.Material.Concrete] = "Rock",
	[Enum.Material.Brick] = "Rock",
	[Enum.Material.Cobblestone] = "Rock",
	[Enum.Material.Asphalt] = "Asphalt",
	[Enum.Material.Pavement] = "Asphalt",
	[Enum.Material.Wood] = "Wood",
	[Enum.Material.WoodPlanks] = "Wood",
} :: { [Enum.Material]: string }

--------------------------------------------------------------------------------
-- KO (ex-« étourdissement » du prototype) et anti-KO répété
--------------------------------------------------------------------------------
Gameplay.KO = {
	DefaultDuration = 2, -- durée d'un KO sans durée précisée (s)
	MinDuration = 0.5,
	MaxDuration = 6,
	RecoverImmunity = 1.5, -- immunité après chaque relève (s)
	SameAttackerCooldown = 8, -- même attaquant -> même victime : délai avant un nouveau KO (s)
	DiminishingWindow = 20, -- fenêtre de comptage des KO successifs d'une même victime (s)
	-- Multiplicateur de durée selon le rang du KO dans la fenêtre (1er, 2e, 3e, 4e et suivants).
	DiminishingMultipliers = { 1, 1, 0.75, 0.5 } :: { number },
	MaxKnockSpeed = 140, -- borne de la vitesse de recul (studs/s)
	ShieldBrokenKnockScale = 0.15, -- bouclier brisé par une frappe majeure : KO sans fort recul
	GiantImmuneToMinor = true, -- personnage géant (attribut Giant) : immunisé contre les frappes mineures
	StandUpLift = 2.5, -- l'avatar est redressé légèrement au-dessus du sol à la relève
	PostRecoverExemption = 1, -- exemption de plausibilité après la relève (s)
	RagdollUpperAngle = 70,
	RagdollNeckAngle = 40,
	RagdollTwistAngle = 30,
	SpawnProtection = 3, -- protection après chaque apparition (s)
	ProtectOnSpawn = true, -- accordée automatiquement à chaque nouveau personnage
	AttackEndsProtection = true, -- attaquer met fin à sa propre protection
	AllowedPhases = { "Lobby", "Preparing", "Playing" } :: { string }, -- phases où le combat est actif
}

-- Impacts de balle sur les joueurs (repris du prototype).
Gameplay.BallHit = {
	MinSpeed = 38, -- vitesse mini de la balle pour mettre KO
	HitRadiusExtra = 1.4, -- rayon de détection = rayon de la balle + 1,4
	HitCooldown = 1, -- par balle et par victime (s)
	Knockback = 45,
	KnockUp = 28,
	BallSlowdown = 0.65, -- la balle garde 65 % de sa vitesse après un impact
	Duration = 2,
	DodgeAvoids = true, -- un joueur en plongeon (Dodging) n'est pas touché
}

-- Frappe de proximité (Combat.Punch).
Gameplay.Punch = {
	Range = 7, -- portée depuis le HumanoidRootPart de l'attaquant
	ConeDeg = 50, -- demi-angle du cône horizontal
	MaxHeightDelta = 5,
	Cooldown = 0.8,
	Duration = 1.2, -- KO court
	Knockback = 38,
	KnockUp = 22,
	AnimTime = 0.35, -- AnimState = "Punch"
	FacingToleranceDeg = 120, -- direction envoyée trop éloignée de l'orientation de l'avatar -> orientation serveur
	ScoreAngleWeight = 2, -- choix de la cible : angle (rad) × poids + distance / portée
}

-- Plongeon / esquive (Combat.Dive).
Gameplay.Dive = {
	Speed = 52, -- vitesse horizontale imposée pendant la poussée
	Lift = 14, -- composante verticale
	PushTime = 0.22, -- durée de la poussée (LinearVelocity répliquée, simulée par le client propriétaire)
	DodgeWindow = 0.35, -- attribut Dodging = true : les projectiles et balles guidées ratent (= Config.Items.DodgeWindow)
	Cooldown = 2.5,
	AnimTime = 0.7, -- AnimState = "Dive"
	ExemptionTime = 1.2, -- exemption de plausibilité accordée (s)
}

-- Recul sans KO (CombatService.Knockback).
Gameplay.Knockback = {
	PushTime = 0.2,
	MaxForce = 100000, -- force max de la LinearVelocity de poussée
	ExemptionTime = 1.5,
}

--------------------------------------------------------------------------------
-- Déplacements et plausibilité
--------------------------------------------------------------------------------
Gameplay.Movement = {
	WalkSpeed = 16,
	JumpPower = 50,
	MinSpeedMultiplier = 0,
	MaxSpeedMultiplier = 3,
	MaxJumpMultiplier = 3,
	ApplyGameSpeed = true, -- MatchSettings.gameSpeed multiplie la vitesse de marche pendant une partie
	-- Verrous retirés automatiquement quand le personnage disparaît (aucun état ne survit à une réapparition).
	-- Les autres verrous (phase de partie...) appartiennent au joueur et restent posés.
	LocksClearedOnRespawn = { "Aim", "KO", "Frozen", "Dazzled", "Stun" } :: { string },
	ClearModifiersOnRespawn = true,
	Plausibility = {
		Enabled = true,
		SampleInterval = 0.5, -- période d'échantillonnage des HumanoidRootPart (s)
		Tolerance = 1.6, -- multiplicateur de la vitesse max autorisée
		Allowance = 8, -- studs supplémentaires par échantillon (latence, pentes, bousculades)
		RiseAllowance = 4, -- montée supplémentaire tolérée par échantillon (studs)
		SlopeFactor = 1.2, -- montée tolérée par stud de déplacement horizontal (rampes, escaliers)
		FlagrantRatio = 4, -- déplacement > 4 × l'autorisé : correction immédiate (téléportation flagrante)
		ViolationsBeforeCorrection = 3, -- infractions (dans la fenêtre) avant de replacer le joueur
		ViolationWindow = 10, -- fenêtre de comptage (s)
		RespawnGrace = 2.5, -- exemption après apparition (s)
		TeleportGrace = 1.5, -- exemption après une téléportation serveur (s)
		FloorProbeDepth = 8, -- détection d'un sol mobile (voiturette, plateforme, tapis) sous le joueur
		MinDt = 0.1,
		MaxDt = 3,
	},
}

--------------------------------------------------------------------------------
-- Statistiques de validation réseau
--------------------------------------------------------------------------------
Gameplay.NetworkValidation = {
	WarnThreshold = 10, -- avertissement au journal au 10e rapport d'un même motif pour un joueur...
	WarnEvery = 50, -- ...puis tous les 50 rapports
	MaxSamples = 5, -- détails conservés par motif
	MaxSampleLength = 160,
	MaxDeparted = 64, -- joueurs partis conservés dans le rapport
}

--------------------------------------------------------------------------------
-- Retours visuels décidés par le serveur (remote Effects.Play, registre client/Effects/*).
-- Purement cosmétiques ; "" = aucun effet. Aucun son n'est déclenché par ces services.
--------------------------------------------------------------------------------
Gameplay.Feedback = {
	Enabled = true,
	HazardEffects = {
		water = "Splash",
		lava = "Explosion",
		oob = "",
		void = "",
		stuck = "",
	} :: { [string]: string },
	LavaEffectRadius = 3,
	BallHitEffect = "HitSpark", -- balle qui met un joueur KO
	PunchHitEffect = "HitSpark", -- frappe de proximité réussie
	KOEffect = "KOStars", -- étoiles au-dessus d'un joueur KO (durée = durée du KO)
}

return Gameplay
