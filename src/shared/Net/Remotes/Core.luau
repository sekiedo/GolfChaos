--!strict
-- Remotes transverses (notifications, santé). Voir Net/init.luau pour le format.
return {
	-- Serveur -> client : message court affiché en toast. (texte, type "info" | "warn" | "hit" | "success")
	["Core.Notify"] = { kind = "Event", dir = "ToClient" },
	-- Serveur -> client : clé de traduction + variables (préféré à Core.Notify pour les textes du jeu).
	["Core.NotifyKey"] = { kind = "Event", dir = "ToClient" },
	-- Client -> serveur : le client signale qu'il a fini de charger son interface (pour les arrivées tardives).
	["Core.ClientReady"] = { kind = "Event", dir = "ToServer", args = {}, rate = 1, burst = 2 },
}
