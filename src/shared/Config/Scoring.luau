--!strict
--[[
	Config.Scoring — barème et règles chiffrées du score (spécification : docs/REGLES_SCORE.md).

	DONNÉES UNIQUEMENT : les calculs vivent dans shared/Logic/Scoring.luau (fonctions pures, testées par
	tests/Specs/Scoring.spec.luau) et sont appliqués par server/Services/MatchService.luau.
	Lisible par le client (affichage du barème, des bonus) : aucun secret, le serveur reste seul juge.

	Unités : points, coups, studs, secondes.
]]

-- Catégories de performance par rapport au par (identifiants de bonus, aussi utilisés comme clés de texte).
export type ParCategory = "holeInOne" | "albatross" | "eagle" | "birdie" | "par"

local Scoring = {}

--------------------------------------------------------------------------------
-- Barème d'arrivée (mode Chacun pour soi ; affiché aussi en mode Équipes)
--------------------------------------------------------------------------------
-- Points selon le rang d'arrivée : index = rang (1 = premier arrivé).
Scoring.ArrivalPoints = { 12, 9, 7, 5, 4, 3, 2, 1 }
-- Rangs au-delà du tableau (9e à 16e, architecture 16 joueurs) : tout joueur qui termine marque au moins 1 point.
Scoring.ArrivalPointsBeyond = 1
-- Trou non terminé (TimeOut, Forfeit, AFK, Disconnected).
Scoring.DnfPoints = 0

--------------------------------------------------------------------------------
-- Bonus de performance golfique (par rapport au par) — une seule catégorie : la meilleure atteinte
--------------------------------------------------------------------------------
-- Ordre d'évaluation (du meilleur au moins bon) ; le premier atteint s'applique.
Scoring.ParCategoryOrder = { "holeInOne", "albatross", "eagle", "birdie", "par" } :: { ParCategory }
Scoring.ParBonus = {
	holeInOne = 6, -- 1 coup
	albatross = 5, -- par − 3 ou mieux (hors trou en un)
	eagle = 4, -- par − 2
	birdie = 2, -- par − 1
	par = 1, -- par
	-- bogey ou pire : aucun bonus
} :: { [string]: number }

--------------------------------------------------------------------------------
-- Coup rentré de loin (distance horizontale du coup final, mesurée par le serveur)
--------------------------------------------------------------------------------
Scoring.LongShot = {
	Enabled = true,
	MinDistance = 40, -- studs ; même seuil que le défi « Tir de sniper » (Config/Achievements)
	Points = 2,
	CountPutts = false, -- un putt rentré de loin ne compte pas
	Id = "longShot",
}

--------------------------------------------------------------------------------
-- Bonus de vitesse (optionnel)
--------------------------------------------------------------------------------
Scoring.Speed = {
	Enabled = true,
	MaxFraction = 0.5, -- terminer en au plus 50 % de la durée de référence (targetTime × timeScale)
	Points = 1,
	Id = "speed",
}

-- Plafond de la somme des bonus d'un trou (catégorie + loin + vitesse) : 2/3 d'une victoire.
Scoring.BonusCap = 8

--------------------------------------------------------------------------------
-- Chronomètre du trou : limite = clamp(targetTime × timeScale × Factor, Min, Max)
--------------------------------------------------------------------------------
Scoring.HoleTime = {
	Factor = 2,
	DefaultTargetTime = 90, -- durée cible utilisée si le trou n'en fournit pas de valide (s)
	Min = 45,
	Max = 600,
}

-- Prolongation déclenchée par la première arrivée : temps restant ramené dans [Min ; Max] (× timeScale).
Scoring.Overtime = {
	Enabled = true,
	Min = 20,
	Max = 45,
	ScaleWithTimeScale = true,
}

--------------------------------------------------------------------------------
-- Plafond de coups par trou (abandon automatique) : clamp(par + ParOffset, Min, Max)
--------------------------------------------------------------------------------
Scoring.StrokeCap = {
	ParOffset = 7,
	Min = 10,
	Max = 14,
}

--------------------------------------------------------------------------------
-- Mode Équipes
--------------------------------------------------------------------------------
Scoring.Team = {
	PointPerHole = 1, -- point marqué par l'équipe gagnante d'un trou (ratio d'arrivées)
}

return Scoring
