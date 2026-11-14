--!strict
--[[
	Remotes du golf (visée, frappe, balle). Contrat entre BallService (serveur) et GolfAimController (client).
	Toutes les intentions transportent le RoundId courant (GameState.RoundId) en premier argument.
]]
return {
	-- Client -> serveur : entrer (true) / quitter (false) le mode visée. (roundId, isAiming)
	["Golf.AimState"] = { kind = "Event", dir = "ToServer", args = { "integer", "boolean" }, rate = 6, burst = 6 },
	-- Client -> serveur : démarrage de la jauge de puissance (horodaté par le serveur). (roundId)
	["Golf.SwingStart"] = { kind = "Event", dir = "ToServer", args = { "integer" }, rate = 6, burst = 4 },
	-- Client -> serveur : frappe. (roundId, direction horizontale, loft en degrés, puissance indicative 0..1, type "Drive"|"Chip"|"Putt")
	-- La puissance est RECALCULÉE par le serveur depuis l'horodatage de Golf.SwingStart (tolérance bornée).
	["Golf.Shoot"] = { kind = "Event", dir = "ToServer", args = { "integer", "Vector3", "number", "number?", "string:8?" }, rate = 4, burst = 3 },
	-- Client -> serveur : balle bloquée -> retour à la dernière position valide (pénalité configurable). (roundId)
	["Golf.ResetBall"] = { kind = "Event", dir = "ToServer", args = { "integer" }, rate = 0.5, burst = 1 },
	-- Serveur -> client (tireur) : visée annulée par le serveur. (raison : "stun" | "horn" | "too_far" | "invalid" | "unavailable" | "respawn" | "phase")
	["Golf.AimCancelled"] = { kind = "Event", dir = "ToClient" },
	-- Serveur -> client (tireur) : frappe acceptée. ({ strokes, power, shotType })
	["Golf.ShotAccepted"] = { kind = "Event", dir = "ToClient" },
	-- Serveur -> tous : une balle est entrée dans le trou. (userId, { strokes, fromDistance, holeInOne, effectId })
	["Golf.Holed"] = { kind = "Event", dir = "ToClient" },
	-- Serveur -> client concerné : balle replacée (eau, hors limites, vide, blocage). (raison, pénalité)
	["Golf.BallReset"] = { kind = "Event", dir = "ToClient" },
}
