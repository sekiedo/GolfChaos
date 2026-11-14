--!strict
--[[
	Config.Economy — monnaie du jeu (pièces) gagnée uniquement en jouant. Aucune boutique Robux, aucun pay-to-win.
	Calcul pur et testé dans Logic/Rewards.luau ; versement serveur idempotent (opId = MatchId..":"..UserId).

	Anti-farm :
	  - l'Entraînement (Driving Range, essais d'objets/véhicules) ne rapporte RIEN ;
	  - le tutoriel rapporte une seule fois (récompense du défi ach_tutorial) ;
	  - une partie ne rapporte que si le joueur a été actif sur au moins MinActiveHoles trous
	    (au moins un coup accepté sur le trou) — un joueur AFK ne gagne rien ;
	  - chaque partie est plafonnée (MatchCap) ; les bonus de performance aussi (PerformanceCap).
]]

local Economy = {}

Economy.StartingCoins = 250
Economy.MaxCoins = 10_000_000 -- borne de sécurité du solde

Economy.MinActiveHoles = 3 -- nombre minimal de trous joués activement (ou tous les trous si la partie en compte moins)
Economy.MatchCap = 400 -- plafond de pièces par partie (hors défis)
Economy.PerformanceCap = 100 -- plafond des bonus de performance par partie

Economy.Base = 40 -- participation à une partie complète (éligible)
Economy.PerHoleFinished = 8 -- par trou terminé (balle rentrée)

-- Bonus de classement (Chacun pour soi), indexé par rang ; au-delà : Others.
Economy.Placement = { [1] = 60, [2] = 40, [3] = 25, Others = 10 }
-- Mode Équipes : gagnants / perdants / égalité.
Economy.Team = { Win = 50, Lose = 15, Draw = 30 }
-- Mode Solo : base fixe + bonus par trou au par ou mieux.
Economy.Solo = { Base = 30, PerParOrBetter = 5 }

-- Bonus de performance golfique (cumulables, plafonnés par PerformanceCap).
Economy.Performance = { HoleInOne = 50, Eagle = 25, Birdie = 10 }

-- Prix de référence de la boutique par rareté (les cosmétiques portent leur propre prix).
Economy.PriceByRarity = { Common = 200, Rare = 500, Epic = 1000, Legendary = 2000 }

return Economy
