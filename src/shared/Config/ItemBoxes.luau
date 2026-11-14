--!strict
--[[
	Config.ItemBoxes — boîtes d'objets aléatoires et boîtes de mobilité (docs/REGISTRE_OBJETS.md, « Règles communes »).
	Le tirage est fait par le serveur (Logic/ItemOdds) ; ces valeurs ne sont qu'indicatives côté client.
]]

local ItemBoxes = {}

ItemBoxes.PickupRadius = 4 -- ramassage par proximité testée côté serveur (studs)
ItemBoxes.CheckInterval = 0.1 -- fréquence du test de proximité (s)

-- Réapparition d'une boîte après ramassage (s), selon le réglage d'hôte itemFrequency.
ItemBoxes.Respawn = { Low = 16, Normal = 10, High = 6 }

-- Rattrapage : 0 = tirage identique pour tous ; 1 = interpolation complète meneur -> dernier.
ItemBoxes.CatchUpStrength = 1

-- Joueur seul ou rang inconnu : position normalisée utilisée pour le tirage (0 = meneur, 1 = dernier).
ItemBoxes.DefaultNormalizedPosition = 0.5

ItemBoxes.Kinds = {
	Random = { pool = "All", color = Color3.fromRGB(255, 200, 60), glyph = "?" },
	Mobility = { pool = "Mobility", color = Color3.fromRGB(80, 220, 160), glyph = "»" },
}

-- Aspect (construit par code) : cube tournant et flottant.
ItemBoxes.Visual = { Size = 3, SpinSpeed = 1.6, BobAmplitude = 0.4, BobSpeed = 2.2 }

return ItemBoxes
