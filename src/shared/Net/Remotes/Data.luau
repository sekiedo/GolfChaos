--!strict
--[[
	Remotes des données joueur (PlayerDataService). Le client ne modifie jamais directement son profil :
	il envoie des intentions validées (préférences) ; monnaie, achats et récompenses sont serveur.
]]
return {
	-- Serveur -> client (propriétaire) : instantané (partiel) du profil.
	-- ({ status, persistent, coins, owned, equipped, loadouts, achievements, stats, settings, version })
	["Data.Sync"] = { kind = "Event", dir = "ToClient" },
	-- Client -> serveur : enregistrer les préférences (table clé -> valeur, validée par clé côté serveur).
	["Data.SaveSettings"] = { kind = "Event", dir = "ToServer", args = { "table" }, rate = 1, burst = 3 },
	-- Client -> serveur : demander un nouvel instantané (après reconnexion de l'interface).
	["Data.RequestSync"] = { kind = "Event", dir = "ToServer", args = {}, rate = 0.2, burst = 2 },
}
