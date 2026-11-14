--!strict
--[[
	Remotes des objets (ItemService). Le client n'envoie que des intentions ; le serveur valide phase, RoundId,
	participant actif, état (KO, gel, éblouissement, trou terminé), objet présent dans la case, délais, cible et
	ligne de vue, puis décide de l'effet. Voir docs/REGISTRE_OBJETS.md et docs/ARCHITECTURE.md §10.
]]
return {
	-- Client -> serveur : sélectionner une case d'inventaire (1..capacité).
	["Items.Select"] = { kind = "Event", dir = "ToServer", args = { "integer" }, rate = 8, burst = 6 },
	-- Client -> serveur : utiliser l'objet d'une case. (roundId, case, direction de visée, userId de la cible suggérée ou nil)
	-- La cible suggérée n'est qu'une indication : le serveur la revalide (ou choisit lui-même selon la règle de l'objet).
	["Items.Use"] = { kind = "Event", dir = "ToServer", args = { "integer", "integer", "Vector3", "integer?" }, rate = 4, burst = 3 },
	-- Client -> serveur : début d'utilisation maintenue (verrouillage de fusée, charge du rail). (roundId, case)
	["Items.UseStart"] = { kind = "Event", dir = "ToServer", args = { "integer", "integer" }, rate = 4, burst = 3 },
	-- Client -> serveur : annulation d'une utilisation maintenue. (roundId, case)
	["Items.UseCancel"] = { kind = "Event", dir = "ToServer", args = { "integer", "integer" }, rate = 4, burst = 3 },
	-- Serveur -> client (propriétaire) : objet obtenu. (itemId, case)
	["Items.Gained"] = { kind = "Event", dir = "ToClient" },
	-- Serveur -> client : retour d'utilisation (refus ou information). (cléLocale, variables?)
	["Items.Feedback"] = { kind = "Event", dir = "ToClient" },
	-- Serveur -> tous : un projectile simulé par le serveur apparaît. (id, type, origine, vitesse Vector3, paramètres)
	["Items.Projectile"] = { kind = "Event", dir = "ToClient" },
	-- Serveur -> tous : correction de trajectoire d'un projectile guidé (perte acceptable). (id, position, vitesse)
	["Items.ProjectileUpdate"] = { kind = "Unreliable", dir = "ToClient" },
	-- Serveur -> tous : fin d'un projectile. (id, position, raison "hit" | "expire" | "deflect" | "dodge")
	["Items.ProjectileEnd"] = { kind = "Event", dir = "ToClient" },
	-- Serveur -> client : état du verrouillage pour le tireur. (userId de la cible verrouillée, 0 si aucun)
	["Items.LockState"] = { kind = "Event", dir = "ToClient" },
	-- Serveur -> client : avertissement à une cible (cercle orbital, viseur laser, nuage). (itemId, attackerUserId)
	["Items.Warning"] = { kind = "Event", dir = "ToClient" },
}
