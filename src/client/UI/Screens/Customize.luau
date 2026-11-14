--!strict
--[[
	Customize — écran Personnaliser : équiper les cosmétiques possédés, choisir leur couleur, gérer les 3
	ensembles enregistrés. Présentation partagée avec Boutique : voir CosmeticBrowser.
	Show(args) : args = nom d'emplacement ("Head", "Emote"...) pour ouvrir directement sur un onglet.
]]

local CosmeticBrowser = require(script.Parent.CosmeticBrowser)

local Customize = {}

function Customize.new(ctx: any): any
	return CosmeticBrowser.new(ctx, "customize", "Customize")
end

return Customize
