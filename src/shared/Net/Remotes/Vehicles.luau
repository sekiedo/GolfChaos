--!strict
--[[
	Remotes des Kart-Caddies (VehicleService). Monter se fait par ProximityPrompt (déclenché côté serveur) ;
	descendre par le saut standard du siège. Conduite : siège VehicleSeat, propriété réseau au conducteur,
	vitesse plafonnée et vérifiée par le serveur.
]]
return {
	-- Client -> serveur : remettre son kart à l'endroit (conducteur, délai de recharge). (roundId)
	["Vehicles.Reset"] = { kind = "Event", dir = "ToServer", args = { "integer" }, rate = 0.3, burst = 1 },
	-- Client -> serveur : klaxon du kart (cosmétique, son pour tous).
	["Vehicles.Horn"] = { kind = "Event", dir = "ToServer", args = {}, rate = 1, burst = 2 },
	-- Serveur -> client : état du véhicule occupé. ({ cartId, seatIndex, isDriver, structure, expiresAt } ou nil en descendant)
	["Vehicles.State"] = { kind = "Event", dir = "ToClient" },
}
