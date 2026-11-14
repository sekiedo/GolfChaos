--!strict
--[[
	Catalog/Emotes : émotes (emplacement "Emote") — 13 émotes, une par animation de Animations/Library/Emotes.luau.

	Contrat (Cosmetics/init.luau) : emote = identifiant d'une animation procédurale ; il est IDENTIQUE à
	l'identifiant du cosmétique (emote_wave -> animation "emote_wave"), ce que vérifie Cosmetics.spec.
	Aucun modèle à construire : l'émote est purement visuelle, jouée par AnimationController sur chaque client à
	partir des attributs de personnage posés par EmoteService.

	Obtention : 2 gratuites par défaut, 9 à l'achat (monnaie gagnée en jeu), 2 débloquées par l'activité.
	Aucune n'est vendue en Robux et aucune ne donne d'avantage de jeu.
]]

type Unlock = { kind: string, value: any? }

type EmoteDef = {
	id: string,
	slot: "Emote",
	nameKey: string,
	descKey: string,
	rarity: "Common" | "Rare" | "Epic" | "Legendary",
	price: number,
	unlock: Unlock,
	tags: { string },
	emote: string,
}

local function emote(id: string, rarity: "Common" | "Rare" | "Epic" | "Legendary", price: number, unlock: Unlock, tags: { string }): EmoteDef
	return {
		id = id,
		slot = "Emote",
		nameKey = "cos." .. id,
		descKey = "cos." .. id .. ".desc",
		rarity = rarity,
		price = price,
		unlock = unlock,
		tags = tags,
		emote = id,
	}
end

local DEFAULT = { kind = "Default" }
local PRICE = { kind = "Price" }

return {
	-- Gratuites -------------------------------------------------------------------------------
	emote("emote_wave", "Common", 0, DEFAULT, { "greeting" }),
	emote("emote_golf_clap", "Common", 0, DEFAULT, { "reaction" }),

	-- À l'achat -------------------------------------------------------------------------------
	emote("emote_fist_pump", "Common", 150, PRICE, { "celebration" }),
	emote("emote_facepalm", "Common", 150, PRICE, { "reaction" }),
	emote("emote_sprinkler", "Common", 200, PRICE, { "dance" }),
	emote("emote_duck_waddle", "Rare", 400, PRICE, { "dance" }),
	emote("emote_noodle", "Rare", 450, PRICE, { "dance" }),
	emote("emote_royal_bow", "Rare", 500, PRICE, { "greeting" }),
	emote("emote_caddie_bot", "Rare", 600, PRICE, { "dance" }),
	emote("emote_flamingo", "Epic", 900, PRICE, { "dance" }),
	emote("emote_birdie_solo", "Epic", 1000, PRICE, { "dance", "music" }),

	-- Débloquées par l'activité (prix 0 : la condition remplace l'achat) ---------------------------
	emote("emote_bunker_tantrum", "Rare", 0, { kind = "MatchesPlayed", value = 10 }, { "reaction" }),
	emote("emote_champion_flex", "Legendary", 0, { kind = "Wins", value = 5 }, { "celebration" }),
}
