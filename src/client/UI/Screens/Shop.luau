--!strict
--[[
	Shop — écran Boutique : tous les cosmétiques par emplacement, achat avec les pièces gagnées en jeu
	(aucun achat en Robux). Présentation partagée avec Personnaliser : voir CosmeticBrowser.
	Show(args) : args = nom d'emplacement ("Head", "Club"...) pour ouvrir directement sur un onglet.
]]

local CosmeticBrowser = require(script.Parent.CosmeticBrowser)

local Shop = {}

function Shop.new(ctx: any): any
	return CosmeticBrowser.new(ctx, "shop", "Shop")
end

return Shop
