--!strict
-- Textes du parcours et de l'accueil (français). Clés préfixées "course." : panneaux de l'accueil, invites,
-- green et driving range d'entraînement, podium, messages des obstacles et du chargement des trous.
-- Utilisées par server/Services/CourseService.luau, server/Course/LobbyBuilder.luau et server/Course/Obstacles.luau.
-- Les libellés posés sur les panneaux portent l'attribut "LocaleKey" (un contrôleur client peut les retraduire).
return {
	-- Panneaux de l'accueil
	["course.sign.welcome"] = "Golf Chaos",
	["course.sign.welcomeSub"] = "Bienvenue au club !",
	["course.sign.play"] = "Jouer",
	["course.sign.playSub"] = "Rejoindre ou créer une partie",
	["course.sign.shop"] = "Boutique",
	["course.sign.shopSub"] = "Tenues, clubs et balles",
	["course.sign.customize"] = "Personnaliser",
	["course.sign.customizeSub"] = "Compose ton style",
	["course.sign.challenges"] = "Défis",
	["course.sign.challengesSub"] = "Relève-les tous",
	["course.sign.training"] = "Entraînement",
	["course.sign.trainingSub"] = "Driving range et tutoriel",
	["course.sign.practice"] = "Green d'entraînement",
	["course.sign.practiceSub"] = "Prends une balle et travaille ton putt",
	["course.sign.range"] = "Driving range",
	["course.sign.rangeSub"] = "Teste la puissance de tes drives",
	["course.sign.podium"] = "Podium",
	["course.sign.podiumSub"] = "Les champions de la dernière partie",

	-- Podium
	["course.podium.first"] = "1er",
	["course.podium.second"] = "2e",
	["course.podium.third"] = "3e",

	-- Driving range
	["course.range.marker"] = "{n} studs",

	-- Invites (ProximityPrompt)
	["course.prompt.takeBall"] = "Prendre une balle",
	["course.prompt.open"] = "Ouvrir",

	-- Entraînement
	["course.practice.ready"] = "Balle prête : vise et frappe !",
	["course.practice.holed"] = "Dans le trou ! Belle frappe.",
	["course.practice.unavailable"] = "L'entraînement est fermé pendant une partie.",
	["course.practice.busy"] = "Attends un instant avant de reprendre une balle.",

	-- Accueil
	["course.lobby.rescued"] = "Oups ! Retour sur la place.",

	-- Trous
	["course.hole.loadFailed"] = "Le trou {id} n'a pas pu être chargé.",

	-- Obstacles : messages
	["course.obstacle.car"] = "Attention, voiture !",
	["course.obstacle.jumpPad"] = "Hop !",

	-- Obstacles : noms (catalogue, documentation du format)
	["course.obstacle.name.wall"] = "Mur",
	["course.obstacle.name.ramp"] = "Rampe",
	["course.obstacle.name.bumper"] = "Champignon rebondissant",
	["course.obstacle.name.windmill"] = "Moulin",
	["course.obstacle.name.movingPlatform"] = "Plateforme mobile",
	["course.obstacle.name.rotatingBar"] = "Barre tournante",
	["course.obstacle.name.pillar"] = "Pilier",
	["course.obstacle.name.arch"] = "Arche",
	["course.obstacle.name.tunnel"] = "Tunnel",
	["course.obstacle.name.jumpPad"] = "Trampoline",
	["course.obstacle.name.conveyor"] = "Tapis roulant",
	["course.obstacle.name.car"] = "Voiture",
	["course.obstacle.name.mover"] = "Véhicule",
	["course.obstacle.name.platform"] = "Plateforme",
	["course.obstacle.name.patch"] = "Zone de surface",
	["course.obstacle.name.swing"] = "Pont-levis",
	["course.obstacle.name.stairs"] = "Escalier",
}
