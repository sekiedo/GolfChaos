--!strict
--[[
	Config.Match — déroulement de la partie, salon, apparitions et playlists (docs/REGLES_SCORE.md §2 et §9,
	docs/ARCHITECTURE.md §7).

	DONNÉES UNIQUEMENT : la machine à états vit dans shared/Logic/MatchStateMachine.luau, les playlists dans
	shared/Logic/Playlist.luau ; les services server/Services/{MatchService, LobbyService, SpawnService}.luau
	appliquent ces valeurs. Lisible par le client (chronomètres, menus du salon) : aucun secret.

	Unités : secondes, studs (sauf mention contraire).
]]

local Types = require(script.Parent.Parent.Types)

-- Règle de validation d'un réglage d'hôte (LobbyService.ApplySetting).
export type SettingRule = {
	kind: "enum" | "boolean" | "integer" | "number" | "playlist" | "biomeList" | "holeList",
	values: { string }?, -- valeurs permises (enum, biomeList)
	min: number?, -- borne basse (integer, number) ou longueur minimale (holeList)
	max: number?, -- borne haute (integer, number) ou longueur maximale (biomeList, holeList)
	step: number?, -- pas d'arrondi (number)
	viaSetSetting: boolean?, -- false : modifiable seulement par un remote dédié (Lobby.SetCustomPlaylist)
}

local Match = {}

--------------------------------------------------------------------------------
-- Participants
--------------------------------------------------------------------------------
Match.MinParticipants = 1 -- une partie démarre avec au moins un participant
Match.MaxParticipants = 8 -- cible principale de la demande
Match.MaxParticipantsExperimental = 16 -- MatchSettings.experimental16 (mode expérimental, stabilité non mesurée)

--------------------------------------------------------------------------------
-- Durées des phases (s). Chaque phase a une durée maximale : rien ne peut bloquer la progression.
--------------------------------------------------------------------------------
Match.Durations = {
	PreparingMax = 240, -- sécurité : préparation trop longue -> retour à l'accueil
	AllReadyDelay = 3, -- départ automatique quand tous les participants sont prêts (annulé si quelqu'un se désiste)
	LoadingMin = 1.5, -- durée minimale du chargement (les clients reçoivent le trou et les placements)
	LoadingMax = 25, -- sécurité : chargement bloqué -> trou suivant, ou partie interrompue
	PlacementTimeout = 8, -- attente maximale du placement de tous les personnages (apparitions comprises)
	HoleIntro = 5, -- présentation du trou (nom, par, particularité)
	Countdown = 3, -- compte à rebours 3-2-1 (joueurs immobilisés, frappes refusées)
	PlayingMax = 900, -- sécurité absolue, quelle que soit la durée limite du trou
	HoleEnd = 3, -- résultats figés
	HoleResults = 8, -- tableau des résultats du trou
	Podium = 12, -- classement final et récompenses
	DeadlineCheckInterval = 0.2, -- période de vérification de l'échéance du trou (prolongation comprise)
	HoledBallRemoveDelay = 1.2, -- balle rentrée retirée après ce délai (animation de chute dans le trou)
}

-- Musiques et sons d'ambiance déclenchés par MatchService (noms de Config/Sounds ; "" = aucun).
Match.Audio = {
	MusicLobby = "music_lobby",
	MusicMatch = "music_match",
	MusicOvertime = "music_tension",
	MusicPodium = "music_podium",
	CountdownBeep = "countdown_beep",
	CountdownGo = "countdown_go",
	Finish = "crowd_cheer",
	HoleInOne = "hole_in_one_fanfare",
	Birdie = "birdie_sting",
	TimeUp = "crowd_aww",
}

-- Podium de fin de partie : emplacements de CourseService.GetLobby().kiosks (rang 1, 2, 3).
Match.Podium = {
	Slots = { "podium1", "podium2", "podium3" },
	Effect = "Confetti", -- effet du registre client (client/Effects/Core.luau)
	EffectRepeat = 3, -- nombre de salves de confettis pendant la phase
	EffectInterval = 2.5,
}

--------------------------------------------------------------------------------
-- Inactivité (AFK) pendant la phase Playing
--------------------------------------------------------------------------------
Match.Afk = {
	Enabled = true,
	Seconds = 60, -- sans frappe acceptée ni déplacement significatif -> statut AFK, trou perdu
	RepeatSeconds = 25, -- délai réduit pour un joueur encore marqué AFK au début du trou suivant
	MinMove = 4, -- déplacement horizontal significatif (studs) depuis la dernière activité
	HeartbeatMinMove = 0.25, -- Match.Heartbeat compte seulement avec au moins ce petit déplacement...
	HeartbeatMinTurnDeg = 8, -- ...ou cette rotation de l'avatar depuis le battement précédent
	SampleInterval = 1, -- période d'échantillonnage serveur
	IgnoreWhileKnockedOut = true, -- un joueur KO n'accumule pas d'inactivité
	WarningBefore = 10, -- avertissement envoyé au joueur ce nombre de secondes avant d'être déclaré AFK
}

--------------------------------------------------------------------------------
-- Arrivées tardives (le réglage d'hôte MatchSettings.lateJoin décide ; voici la politique appliquée)
--------------------------------------------------------------------------------
Match.LateJoin = {
	-- lateJoin = true : spectateur jusqu'au trou suivant, puis participant (dans la limite des places).
	-- lateJoin = false ou partie pleine : spectateur jusqu'à la partie suivante. Jamais au milieu d'un trou.
	AllowInSolo = false, -- le mode Solo n'a qu'un participant
	AllowInTraining = true,
	-- Trous manqués : comptés au plafond de coups pour le départage (docs/REGLES_SCORE.md §4.2).
}

--------------------------------------------------------------------------------
-- Apparitions (SpawnService) et placements de départ (MatchService)
--------------------------------------------------------------------------------
Match.Spawn = {
	ProtectionSeconds = 3, -- protection accordée après chaque (ré)apparition (CombatService.GrantProtection)
	FallProtectionSeconds = 2, -- protection après un replacement suite à une chute
	RespawnDelay = 2, -- réapparition après une mort accidentelle (bouton Réinitialiser, bug de physique)
	LoadRetries = 3, -- tentatives de Player:LoadCharacter() avant abandon (journalisé)
	LoadRetryDelay = 1,
	LobbyKillY = -60, -- altitude sous laquelle un personnage de l'accueil est replacé (si l'accueil n'en fournit pas)
	KillCheckInterval = 0.25, -- période de surveillance des chutes
	SafeSampleInterval = 0.5, -- mémorisation de la dernière position sûre (au sol, au-dessus de la limite)
	CharacterLift = 3.2, -- hauteur du pivot du personnage au-dessus du sol (R15 standard)
	GroundProbeUp = 6, -- recherche du sol : départ du rayon au-dessus du point visé...
	GroundProbeDown = 40, -- ...et longueur vers le bas
	BallForward = 4, -- au départ, balle posée devant le joueur (studs)
	BallLift = 0.7, -- centre de la balle au-dessus du sol (rayon 0,6 + marge)
	StartSpacing = 6, -- écart latéral quand CourseService fournit moins de départs que de participants
	LobbyWaitTimeout = 15, -- attente de l'accueil construit par CourseService avant la plateforme de secours
	FallbackPlatformSize = Vector3.new(80, 2, 80), -- plateforme de secours (CourseService absent)
	FallbackPlatformPosition = Vector3.new(0, 0, 0),
	PadJitter = 2.5, -- décalage aléatoire maximal autour d'un plot d'apparition de l'accueil (évite l'empilement)
	FallRespawnCooldown = 1, -- délai minimal entre deux replacements pour chute d'un même joueur
}

--------------------------------------------------------------------------------
-- Équipes (mode Équipes rouge/bleue)
--------------------------------------------------------------------------------
Match.Teams = {
	Order = { "Red", "Blue" } :: { Types.Team },
	Red = { NameKey = "match.team.Red", BrickColor = "Bright red" },
	Blue = { NameKey = "match.team.Blue", BrickColor = "Bright blue" },
}

--------------------------------------------------------------------------------
-- Salon
--------------------------------------------------------------------------------
Match.Lobby = {
	AutoStartWhenAllReady = true, -- départ automatique quand tous les participants sont prêts (Durations.AllReadyDelay)
	MinCustomHoles = 1,
	MaxCustomHoles = 18,
	HoleIdMaxLength = 24,
	TeamChoices = { "Red", "Blue", "Auto" },
	StateDebounce = 0.15, -- regroupement des instantanés Lobby.State (s)
}

-- Parties privées entre amis (serveur réservé ; expérience publiée uniquement).
Match.Private = {
	AllowInStudio = false, -- true : tenter la téléportation en Test / Team Test d'une place publiée
	MaxPlayers = 50, -- limite de TeleportService:TeleportAsync par appel
	IncludeFriends = true, -- emmène les amis du demandeur présents sur le serveur
	Retries = 2, -- nouvelles tentatives en cas d'échec de téléportation
	RetryDelay = 1,
	FloodedRetryDelay = 15, -- Enum.TeleportResult.Flooded : attendre avant de réessayer
}

-- Entraînement à l'accueil (Driving Range, tutoriel) : aucune incidence sur le score ni sur les pièces.
Match.Training = {
	Kinds = { "Range", "Tutorial" },
	BallForward = 6, -- balle d'entraînement posée devant le joueur si la zone n'indique pas de position
	Cooldown = 2, -- délai entre deux demandes d'un même joueur
	AreaRadius = 140, -- s'éloigner de plus de cette distance (horizontale) du départ met fin à la session
	CheckInterval = 1, -- période de vérification de la zone d'entraînement
}

--------------------------------------------------------------------------------
-- Playlists (shared/Logic/Playlist.luau)
--------------------------------------------------------------------------------
Match.Playlists = {
	-- Playlists de taille fixe : les N premiers trous du « parcours » (biomes filtrés, ordre du catalogue).
	FixedSizes = { Quick3 = 3, Front9 = 9, Full18 = 18 } :: { [string]: number },
	-- Noms simples acceptés ; "Biome:<Biome>" s'ajoute pour chaque biome de Biomes.
	Names = { "Quick3", "Front9", "Full18", "Mixed", "Custom" },
	-- Ordre du parcours (pool des playlists fixes et de "Mixed") ; Training n'y figure pas.
	CourseBiomes = { "Coast", "Forest", "Desert", "Snow", "City" } :: { Types.Biome },
	-- Tous les biomes reconnus (playlist "Biome:<Biome>", filtre biomes).
	Biomes = { "Coast", "Forest", "Desert", "Snow", "City", "Training" } :: { Types.Biome },
	TrainingBiome = "Training" :: Types.Biome,
	MinHoles = 1,
	MaxHoles = 18,
}

--------------------------------------------------------------------------------
-- Réglages de partie (Types.MatchSettings) : valeurs par défaut et règles de validation
--------------------------------------------------------------------------------
Match.DefaultSettings = {
	mode = "FreeForAll",
	playlist = "Quick3",
	holeCount = 3,
	customHoleIds = nil,
	biomes = nil,
	shuffle = false,
	timeScale = 1,
	wind = "Light",
	gameSpeed = 1,
	itemsEnabled = true,
	itemFrequency = "Normal",
	ballCollisions = false,
	friendlyFire = false,
	lateJoin = true,
	experimental16 = false,
} :: Types.MatchSettings

-- Ordre d'affichage des réglages dans le salon.
Match.SettingKeys = {
	"mode",
	"playlist",
	"holeCount",
	"customHoleIds",
	"biomes",
	"shuffle",
	"timeScale",
	"wind",
	"gameSpeed",
	"itemsEnabled",
	"itemFrequency",
	"ballCollisions",
	"friendlyFire",
	"lateJoin",
	"experimental16",
}

Match.SettingRules = {
	mode = { kind = "enum", values = { "FreeForAll", "Teams", "Solo", "Training" } },
	playlist = { kind = "playlist" },
	holeCount = { kind = "integer", min = 1, max = 18 },
	customHoleIds = { kind = "holeList", min = 1, max = 18, viaSetSetting = false },
	biomes = { kind = "biomeList", values = { "Coast", "Forest", "Desert", "Snow", "City", "Training" }, max = 6 },
	shuffle = { kind = "boolean" },
	timeScale = { kind = "number", min = 0.5, max = 2, step = 0.05 },
	wind = { kind = "enum", values = { "Off", "Light", "Strong", "Random" } },
	gameSpeed = { kind = "number", min = 0.75, max = 1.5, step = 0.05 },
	itemsEnabled = { kind = "boolean" },
	itemFrequency = { kind = "enum", values = { "Low", "Normal", "High" } },
	ballCollisions = { kind = "boolean" },
	friendlyFire = { kind = "boolean" },
	lateJoin = { kind = "boolean" },
	experimental16 = { kind = "boolean" },
} :: { [string]: SettingRule }

return Match
