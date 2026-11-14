--!strict
-- Menus et écrans de phase : menu principal, salon de l'hôte, bannière, chargement, présentation, départ.
-- Domaine « menu ». Les libellés de réglages et de modes réutilisent lobby.* et match.*.
return {
	-- Menu principal (accueil)
	["menu.title"] = "Golf Chaos",
	["menu.subtitle"] = "Le golf où tout peut arriver",
	["menu.play"] = "Jouer",
	["menu.play.lobby"] = "Salon de la partie",
	["menu.play.inMatch"] = "Partie en cours",
	["menu.training"] = "Entraînement",
	["menu.shop"] = "Boutique",
	["menu.customize"] = "Personnaliser",
	["menu.challenges"] = "Défis",
	["menu.settings"] = "Réglages",
	["menu.spectator"] = "Regarder la prochaine partie",
	["menu.resume"] = "Reprendre",
	["menu.coins"] = "{coins} pièces",
	["menu.button"] = "Menu",
	["menu.hint.keyboard"] = "M : menu   ·   Échap : retour",
	["menu.hint.gamepad"] = "Start : menu   ·   B : retour",
	["menu.training.title"] = "Entraînement",
	["menu.training.pick"] = "Choisis ton entraînement",

	-- Salon (préparation)
	["menu.host.sectionGame"] = "Partie",
	["menu.host.sectionRules"] = "Règles",
	["menu.host.sectionPlayers"] = "Joueurs",
	["menu.host.readOnly"] = "Seul l'hôte peut modifier les réglages",
	["menu.host.youTag"] = "TOI",
	["menu.host.hostTag"] = "HÔTE",
	["menu.host.waitingReady"] = "En attente des joueurs prêts…",
	["menu.host.canStart"] = "Tout est prêt : tu peux lancer !",
	["menu.host.syncing"] = "Synchronisation du salon…",
	["menu.host.customPlaylist"] = "Sélection : {count} trou(s)",
	["menu.host.biomesAll"] = "Tous les biomes",
	["menu.host.teamLocked"] = "Équipes en mode Équipes uniquement",
	["menu.host.reopen"] = "Salon",

	-- Bannière de phase
	["menu.banner.lobby"] = "Accueil",
	["menu.banner.preparing"] = "Préparation de la partie",
	["menu.banner.timer"] = "{time}",
	["menu.banner.host"] = "Hôte : {name}",
	["menu.banner.noHost"] = "Aucun hôte",

	-- Chargement
	["menu.loading.title"] = "Chargement…",
	["menu.loading.tip"] = "Astuce",
	["menu.tip.1"] = "Maintiens la frappe plus longtemps pour une balle plus puissante : relâche au bon moment !",
	["menu.tip.2"] = "Le vent pousse ta balle en vol : regarde la flèche avant de frapper.",
	["menu.tip.3"] = "Les premiers arrivés au trou marquent le plus de points.",
	["menu.tip.4"] = "Un coup de poing bien placé fait perdre du temps à un adversaire… mais il peut répliquer !",
	["menu.tip.5"] = "Les boîtes d'objets donnent plus souvent de bons objets aux joueurs en retard.",
	["menu.tip.6"] = "Une voiturette te rapproche de ta balle, mais attention aux virages !",
	["menu.tip.7"] = "Tomber à l'eau coûte un coup de pénalité : vise le fairway.",
	["menu.tip.8"] = "Sur le green, frappe doucement : la balle roule loin.",
	["menu.tip.9"] = "Un trou en un rapporte un gros bonus de points.",
	["menu.tip.10"] = "En mode Équipes, aide tes alliés : chaque arrivée compte pour l'équipe.",
	["menu.tip.11"] = "Le sable freine la balle, la glace la fait glisser.",
	["menu.tip.12"] = "Les réglages d'accessibilité (effets réduits, sans flash) sont dans le menu Réglages.",

	-- Présentation du trou
	["menu.intro.biome"] = "Biome : {biome}",
	["menu.intro.mode"] = "{mode}",
	["menu.intro.difficulty"] = "Difficulté",

	-- Compte à rebours
	["menu.countdown.3"] = "3",
	["menu.countdown.2"] = "2",
	["menu.countdown.1"] = "1",
}
