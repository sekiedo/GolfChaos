--!strict
-- Boutique et personnalisation (français). Clés préfixées "shop.".
-- Les clés shop.err.* sont renvoyées par CosmeticService (remote Shop.Result) : une par raison de refus.
return {
	["shop.err.profile"] = "Profil indisponible : réessaie dans un instant",
	["shop.err.unknown"] = "Cet objet n'existe pas",
	["shop.err.owned"] = "Tu possèdes déjà cet objet",
	["shop.err.notOwned"] = "Tu ne possèdes pas cet objet",
	["shop.err.coins"] = "Pas assez de pièces",
	["shop.err.locked"] = "Objet verrouillé : remplis sa condition pour le débloquer",
	["shop.err.slot"] = "Emplacement inconnu",
	["shop.err.variant"] = "Cette couleur n'existe pas pour cet objet",
	["shop.err.emotesFull"] = "Toutes tes cases d'émotes sont prises : retires-en une d'abord",
	["shop.err.loadout"] = "Cet ensemble n'existe pas",
	["shop.err.emptyLoadout"] = "Cet ensemble est vide : enregistre d'abord une tenue",
}
