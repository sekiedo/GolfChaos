--!strict
--[[
	Remotes du combat cartoon (frappe de proximité, plongeon, annonces de KO). Serveur : CombatService.
]]
return {
	-- Client -> serveur : frappe de proximité (coup de poing/club) dans la direction regardée. (roundId, direction)
	["Combat.Punch"] = { kind = "Event", dir = "ToServer", args = { "integer", "Vector3" }, rate = 3, burst = 2 },
	-- Client -> serveur : plongeon / esquive dans une direction. (roundId, direction)
	["Combat.Dive"] = { kind = "Event", dir = "ToServer", args = { "integer", "Vector3" }, rate = 2, burst = 1 },
	-- Serveur -> tous : annonce de KO. (victimUserId, attackerUserId (0 si aucun), source : "ball" | "punch" | itemId...)
	["Combat.KO"] = { kind = "Event", dir = "ToClient" },
	-- Serveur -> client : retour visuel d'une action de combat refusée ou réussie. (action, ok, raison?)
	["Combat.Feedback"] = { kind = "Event", dir = "ToClient" },
}
