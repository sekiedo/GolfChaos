--!strict
--[[
	Remotes du salon (LobbyService). Les réglages sont validés clé par clé côté serveur (type, bornes,
	hôte uniquement, phase Lobby/Preparing uniquement).
]]
return {
	-- Client -> serveur : modifier un réglage de partie (hôte). (clé, valeur) — clés : voir Types.MatchSettings
	["Lobby.SetSetting"] = { kind = "Event", dir = "ToServer", args = { "string:24", "any" }, rate = 8, burst = 8 },
	-- Client -> serveur : playlist personnalisée (hôte). (liste d'ids de trous, 1..18 éléments)
	["Lobby.SetCustomPlaylist"] = { kind = "Event", dir = "ToServer", args = { "table" }, rate = 1, burst = 2 },
	-- Client -> serveur : se déclarer prêt / pas prêt.
	["Lobby.SetReady"] = { kind = "Event", dir = "ToServer", args = { "boolean" }, rate = 2, burst = 3 },
	-- Client -> serveur : ouvrir la préparation (Lobby -> Preparing) ou lancer la partie (Preparing -> Loading) (hôte).
	["Lobby.Advance"] = { kind = "Event", dir = "ToServer", args = {}, rate = 0.5, burst = 2 },
	-- Client -> serveur : revenir à l'accueil depuis la préparation (hôte).
	["Lobby.Cancel"] = { kind = "Event", dir = "ToServer", args = {}, rate = 0.5, burst = 2 },
	-- Client -> serveur : choisir son équipe ("Red" | "Blue" | "Auto").
	["Lobby.SetTeam"] = { kind = "Event", dir = "ToServer", args = { "string:8" }, rate = 1, burst = 3 },
	-- Client -> serveur : équilibrer les équipes automatiquement (hôte).
	["Lobby.BalanceTeams"] = { kind = "Event", dir = "ToServer", args = {}, rate = 0.5, burst = 1 },
	-- Client -> serveur : créer une partie privée entre amis (serveur réservé ; expérience publiée uniquement).
	["Lobby.CreatePrivate"] = { kind = "Event", dir = "ToServer", args = {}, rate = 0.1, burst = 1 },
	-- Client -> serveur : demander une session d'entraînement (Driving Range / tutoriel). (type : "Range" | "Tutorial")
	["Lobby.RequestTraining"] = { kind = "Event", dir = "ToServer", args = { "string:12" }, rate = 0.5, burst = 2 },
	-- Serveur -> tous : instantané du salon. ({ hostUserId, settings, players = { { userId, name, ready, team, spectator } }, canStart })
	["Lobby.State"] = { kind = "Event", dir = "ToClient" },
}
