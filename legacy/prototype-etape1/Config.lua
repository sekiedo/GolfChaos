--[[
	ReplicatedStorage/Shared/Config  (ModuleScript)
	-----------------------------------------------
	Toutes les constantes d'équilibrage. Lisible par le client ET le serveur :
	on n'y met jamais de secret, et le serveur reste la seule autorité.
]]

local Config = {}

Config.Debug = {
	-- Étape 1 uniquement : crée une balle devant chaque joueur pour tester sans GameManager.
	AutoSpawnBall = true,
}

Config.CollisionGroups = {
	Ball = "Balls",
	Character = "Characters",
}

-- Avatar ---------------------------------------------------------------------
Config.WalkSpeed = 16
Config.JumpPower = 50

-- Balle ----------------------------------------------------------------------
Config.Ball = {
	Diameter = 1.2,
	Density = 0.7, -- constante pour toutes les surfaces => masse constante
	Color = Color3.fromRGB(255, 255, 255),
	GravityScale = 0.5, -- 0.5 = la balle subit la moitié de la gravité (trajectoires plus longues, plus "arcade")
	MaxSpeed = 160, -- plafond anti-tunneling (studs/s)
	RestSpeed = 1.2, -- sous cette vitesse la balle est candidate à l'arrêt...
	RestTime = 0.6, -- ...pendant cette durée (s)
	MaxMoveTime = 30, -- arrêt forcé de sécurité (s)
	GroundRayExtra = 0.6, -- marge du raycast vers le sol sous la balle
	DragMaxVerticalSpeed = 8, -- la friction de roulement ne s'applique pas pendant un grand rebond
	KillHeight = -60, -- sous cette altitude : balle hors limites
	HazardPenalty = 1, -- coups ajoutés quand la balle tombe à l'eau / hors limites
	TerrainWater = true, -- détecte l'eau du Terrain
	HazardTag = "GolfHazard", -- tag CollectionService pour les zones d'eau / hors limites en Parts
}

-- Tir ------------------------------------------------------------------------
Config.Shot = {
	MinSpeed = 25, -- vitesse de lancement à 0 % de puissance
	MaxSpeed = 150, -- vitesse de lancement à 100 %
	DefaultLoft = 28, -- angle de frappe par défaut (degrés)
	MinLoft = 8,
	MaxLoft = 60,
	LoftStep = 3, -- degrés par cran de molette
	PowerPeriod = 1.6, -- durée d'un aller-retour complet de la jauge 0 -> 1 -> 0 (s)
	PowerTolerance = 0.2, -- écart max accepté entre la puissance client et la puissance recalculée serveur
	MinSwingTime = 0.12, -- délai mini entre "début de jauge" et "frappe"
	MaxSwingTime = 12, -- délai maxi
	Cooldown = 0.4,
	AimEnterDistance = 9, -- distance joueur-balle pour entrer en mode visée
	AimExitDistance = 14, -- distance au-delà de laquelle on sort du mode visée
	DistanceTolerance = 4, -- tolérance serveur (latence)
}

-- Visée / caméra (client) ----------------------------------------------------
Config.Aim = {
	AutoEnter = true, -- true : mode visée dès qu'on s'approche ; false : appuyer sur E
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
}

-- Étourdissement -------------------------------------------------------------
Config.Stun = {
	Duration = 2,
	Immunity = 1.5, -- immunité après un étourdissement (évite l'enchaînement infini)
	BallMinSpeed = 38, -- vitesse mini de la balle pour étourdir
	HitRadiusExtra = 1.4,
	HitCooldown = 1, -- par balle et par victime
	BallKnockback = 45,
	BallKnockUp = 28,
	BallSlowdown = 0.65, -- la balle garde 65 % de sa vitesse après un impact
}

-- Surfaces -------------------------------------------------------------------
-- Drag = freinage de roulement (1/s). Friction/Elasticity = PhysicalProperties de la balle.
Config.DefaultSurface = "Grass"
Config.Surfaces = {
	Grass = { Drag = 0.9, Friction = 0.4, Elasticity = 0.45 },
	Green = { Drag = 0.45, Friction = 0.3, Elasticity = 0.35 },
	Rough = { Drag = 2.6, Friction = 0.8, Elasticity = 0.2 },
	Sand = { Drag = 5.5, Friction = 1.0, Elasticity = 0.05 },
	Ice = { Drag = 0.05, Friction = 0.02, Elasticity = 0.4 },
	Rock = { Drag = 0.7, Friction = 0.5, Elasticity = 0.6 },
}

-- Déduction de la surface depuis le matériau (Terrain inclus).
-- Une Part peut forcer sa surface avec l'attribut string "Surface" (ex: "Green", "Sand").
Config.MaterialSurface = {
	[Enum.Material.Grass] = "Grass",
	[Enum.Material.LeafyGrass] = "Rough",
	[Enum.Material.Mud] = "Rough",
	[Enum.Material.Ground] = "Rough",
	[Enum.Material.Snow] = "Rough",
	[Enum.Material.Sand] = "Sand",
	[Enum.Material.Ice] = "Ice",
	[Enum.Material.Glacier] = "Ice",
	[Enum.Material.Rock] = "Rock",
	[Enum.Material.Slate] = "Rock",
	[Enum.Material.Concrete] = "Rock",
	[Enum.Material.Asphalt] = "Rock",
	[Enum.Material.Pavement] = "Rock",
	[Enum.Material.Cobblestone] = "Rock",
}

-- Jauge de puissance : onde triangulaire 0 -> 1 -> 0.
-- Partagée par le client (affichage) et le serveur (calcul autoritaire).
function Config.PowerAtTime(elapsed)
	local phase = (elapsed / Config.Shot.PowerPeriod) % 1
	if phase < 0.5 then
		return phase * 2
	end
	return (1 - phase) * 2
end

return Config
