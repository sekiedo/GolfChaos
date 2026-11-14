--!strict
--[[
	Remotes de la boutique et de la personnalisation (CosmeticService). Prix, possession, conditions de déblocage
	et débit des pièces sont décidés par le serveur (transaction idempotente par identifiant d'opération).
	Aucun achat en Robux dans cette livraison.
]]
return {
	-- Client -> serveur : acheter un cosmétique avec des pièces. (cosmeticId)
	["Shop.Buy"] = { kind = "Event", dir = "ToServer", args = { "string:48" }, rate = 2, burst = 3 },
	-- Client -> serveur : équiper (ou retirer si nil) un cosmétique possédé dans un emplacement. (emplacement, cosmeticId?)
	["Shop.Equip"] = { kind = "Event", dir = "ToServer", args = { "string:16", "string:48?" }, rate = 4, burst = 4 },
	-- Client -> serveur : choisir la variante de couleur d'un cosmétique possédé. (cosmeticId, indice)
	["Shop.SetVariant"] = { kind = "Event", dir = "ToServer", args = { "string:48", "integer" }, rate = 4, burst = 4 },
	-- Client -> serveur : enregistrer la tenue actuelle dans un ensemble (1..3).
	["Shop.SaveLoadout"] = { kind = "Event", dir = "ToServer", args = { "integer" }, rate = 1, burst = 2 },
	-- Client -> serveur : porter un ensemble enregistré (1..3).
	["Shop.UseLoadout"] = { kind = "Event", dir = "ToServer", args = { "integer" }, rate = 1, burst = 2 },
	-- Serveur -> client : résultat d'une action. (action, ok, cléLocale?, données?)
	["Shop.Result"] = { kind = "Event", dir = "ToClient" },
}
