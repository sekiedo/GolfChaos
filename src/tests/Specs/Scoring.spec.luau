--!strict
-- Score (Logic.Scoring + Config.Scoring) : barème, bonus, plafond, égalités, départages, prolongation, plafond de
-- coups, équipes (déséquilibrées comprises), solo. Chaque cas reprend un exemple de docs/REGLES_SCORE.md.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Scoring = require(Shared.Logic.Scoring)
local ConfigScoring = require(Shared.Config.Scoring)

local function finished(rank: number, strokes: number, par: number, extra: { [string]: any }?): any
	local input: { [string]: any } = {
		status = "Finished",
		rank = rank,
		strokes = strokes,
		par = par,
		fromDistance = 10,
		wasPutt = false,
		finishTime = 100,
		referenceTime = 90,
	}
	if extra then
		for key, value in extra do
			input[key] = value
		end
	end
	return input
end

local function standing(userId: number, name: string, points: number, wins: number, strokes: number, birdies: number): any
	return {
		userId = userId,
		name = name,
		points = points,
		holeWins = wins,
		totalStrokes = strokes,
		birdiesOrBetter = birdies,
	}
end

local function rankOf(rows: { any }, userId: number): number?
	for _, row in rows do
		if row.userId == userId then
			return row.rank
		end
	end
	return nil
end

return function(t)
	t.describe("Barème d'arrivée (§5.1)", function()
		t.it("donne 12, 9, 7, 5, 4, 3, 2, 1 aux huit premiers", function()
			local expected = { 12, 9, 7, 5, 4, 3, 2, 1 }
			for rank, points in expected do
				t.expect(Scoring.arrivalPoints(rank)).toBe(points)
			end
		end)

		t.it("donne 1 point du 9e au 16e et 0 à un non-arrivant", function()
			for rank = 9, 16 do
				t.expect(Scoring.arrivalPoints(rank)).toBe(1)
			end
			t.expect(Scoring.arrivalPoints(nil)).toBe(0)
			t.expect(Scoring.arrivalPoints(0)).toBe(0)
			t.expect(Scoring.arrivalPoints(0 / 0)).toBe(0)
		end)
	end)

	t.describe("Bonus golfiques (§5.3–5.6)", function()
		t.it("reconnaît chaque catégorie par rapport au par", function()
			t.expect(Scoring.parCategory(1, 3)).toBe("holeInOne")
			t.expect(Scoring.parCategory(1, 2)).toBe("holeInOne")
			t.expect(Scoring.parCategory(2, 5)).toBe("albatross")
			t.expect(Scoring.parCategory(2, 6)).toBe("albatross")
			t.expect(Scoring.parCategory(2, 4)).toBe("eagle")
			t.expect(Scoring.parCategory(3, 4)).toBe("birdie")
			t.expect(Scoring.parCategory(4, 4)).toBe("par")
			t.expect(Scoring.parCategory(5, 4)).toBeNil()
			t.expect(Scoring.parCategory(0, 4)).toBeNil()
		end)

		t.it("donne les valeurs de la configuration", function()
			t.expect(ConfigScoring.ParBonus.holeInOne).toBe(6)
			t.expect(ConfigScoring.ParBonus.albatross).toBe(5)
			t.expect(ConfigScoring.ParBonus.eagle).toBe(4)
			t.expect(ConfigScoring.ParBonus.birdie).toBe(2)
			t.expect(ConfigScoring.ParBonus.par).toBe(1)
			t.expect(ConfigScoring.BonusCap).toBe(8)
		end)

		t.it("compte le coup rentré de loin dès 40 studs, putts exclus", function()
			t.expect(Scoring.isLongShot(40, false)).toBe(true)
			t.expect(Scoring.isLongShot(39.9, false)).toBe(false)
			t.expect(Scoring.isLongShot(80, true)).toBe(false)
			t.expect(Scoring.isLongShot(nil, false)).toBe(false)
		end)

		t.it("accorde le bonus de vitesse sous 50 % de la référence", function()
			t.expect(Scoring.isSpeedBonus(45, 90)).toBe(true)
			t.expect(Scoring.isSpeedBonus(45.5, 90)).toBe(false)
			t.expect(Scoring.isSpeedBonus(nil, 90)).toBe(false)
			t.expect(Scoring.isSpeedBonus(10, 0)).toBe(false)
		end)

		t.it("plafonne la somme des bonus à 8", function()
			local bonus = Scoring.computeBonuses({
				strokes = 1,
				par = 3,
				fromDistance = 120,
				wasPutt = false,
				finishTime = 20,
				referenceTime = 60,
			})
			t.expect(bonus.raw).toBe(9)
			t.expect(bonus.total).toBe(8)
			t.expect(bonus.ids).toContain("holeInOne")
			t.expect(bonus.ids).toContain("longShot")
			t.expect(bonus.ids).toContain("speed")
		end)
	end)

	t.describe("Points du trou (§5.7, tableau d'exemples)", function()
		t.it("1er avec birdie : 14", function()
			local score = Scoring.scoreHole(finished(1, 3, 4, { fromDistance = 12, finishTime = 50, referenceTime = 90 }))
			t.expect(score.arrival).toBe(12)
			t.expect(score.points).toBe(14)
		end)

		t.it("2e au par : 10", function()
			t.expect(Scoring.scoreHole(finished(2, 4, 4)).points).toBe(10)
		end)

		t.it("1er avec trou en un de loin et rapide : 20 (bonus plafonné)", function()
			local score = Scoring.scoreHole(finished(1, 1, 3, { fromDistance = 120, finishTime = 20, referenceTime = 60 }))
			t.expect(score.bonus.total).toBe(8)
			t.expect(score.points).toBe(20)
		end)

		t.it("3e avec bogey : 7", function()
			t.expect(Scoring.scoreHole(finished(3, 5, 4)).points).toBe(7)
		end)

		t.it("4e avec eagle rentré au chip de 45 studs : 11", function()
			local score = Scoring.scoreHole(finished(4, 3, 5, { fromDistance = 45, finishTime = 100, referenceTime = 130 }))
			t.expect(score.points).toBe(11)
		end)

		t.it("trou non terminé : 0 point et aucun bonus, quel que soit le statut", function()
			for _, status in { "TimeOut", "Forfeit", "AFK", "Disconnected" } do
				local score = Scoring.scoreHole(finished(1, 1, 3, { status = status }))
				t.expect(score.points).toBe(0)
				t.expect(#score.bonus.ids).toBe(0)
			end
		end)

		t.it("sans barème d'arrivée (solo), seuls les bonus comptent", function()
			local score = Scoring.scoreHole(finished(1, 3, 4, { withArrival = false }))
			t.expect(score.arrival).toBe(0)
			t.expect(score.points).toBe(2)
		end)
	end)

	t.describe("Arrivées simultanées et classements (§5.2, §5.8)", function()
		t.it("partage le rang des arrivées de la même image (1, 1, 3)", function()
			local first = Scoring.nextFinishRank(0, nil, nil, 10)
			local second = Scoring.nextFinishRank(1, 10, first, 10)
			local third = Scoring.nextFinishRank(2, 10, second, 11)
			t.expect(first).toBe(1)
			t.expect(second).toBe(1)
			t.expect(third).toBe(3)
		end)

		t.it("calcule un classement compétition 1, 1, 3", function()
			local ranks = Scoring.competitionRanks({ 10, 7, 10, 3 }, function(a: number, b: number): boolean
				return a > b
			end)
			t.expect(ranks).toEqual({ 1, 3, 1, 4 })
		end)

		t.it("départage par points, trous gagnés, coups, puis birdies", function()
			local rows = Scoring.matchStandings({
				standing(1, "A", 30, 1, 20, 0),
				standing(2, "B", 32, 0, 30, 0),
				standing(3, "C", 30, 2, 25, 0),
				standing(4, "D", 30, 1, 18, 0),
				standing(5, "E", 30, 1, 18, 2),
			})
			t.expect(rankOf(rows, 2)).toBe(1) -- plus de points
			t.expect(rankOf(rows, 3)).toBe(2) -- plus de trous gagnés
			t.expect(rankOf(rows, 5)).toBe(3) -- moins de coups, puis plus de birdies
			t.expect(rankOf(rows, 4)).toBe(4)
			t.expect(rankOf(rows, 1)).toBe(5)
		end)

		t.it("donne un rang partagé en cas d'égalité parfaite, affichage par nom", function()
			local rows = Scoring.matchStandings({
				standing(7, "Zoé", 20, 1, 15, 1),
				standing(8, "Alix", 20, 1, 15, 1),
				standing(9, "Max", 10, 0, 20, 0),
			})
			t.expect(rows[1].name).toBe("Alix")
			t.expect(rows[1].rank).toBe(1)
			t.expect(rows[2].rank).toBe(1)
			t.expect(rows[3].rank).toBe(3)
		end)
	end)

	t.describe("Chronomètre et prolongation (§3)", function()
		t.it("calcule la durée limite des exemples", function()
			t.expect(Scoring.holeTimeLimit(60, 1)).toBe(120)
			t.expect(Scoring.holeTimeLimit(90, 1)).toBe(180)
			t.expect(Scoring.holeTimeLimit(130, 1)).toBe(260)
			t.expect(Scoring.holeTimeLimit(nil, 1)).toBe(180)
			t.expect(Scoring.holeTimeLimit(60, 0.5)).toBe(60)
		end)

		t.it("borne la durée limite entre 45 et 600 s", function()
			t.expect(Scoring.holeTimeLimit(10, 1)).toBe(45)
			t.expect(Scoring.holeTimeLimit(400, 1)).toBe(600)
		end)

		t.it("calcule la durée de référence sans le facteur", function()
			t.expect(Scoring.referenceTime(90, 1)).toBe(90)
			t.expect(Scoring.referenceTime(60, 2)).toBe(120)
			t.expect(Scoring.referenceTime(-5, 1)).toBe(90)
		end)

		t.it("réduit le temps restant à 45 s après la première arrivée", function()
			local deadline, triggered = Scoring.deadlineAfterFinish(70, 180, 1, false)
			t.expect(deadline).toBe(115)
			t.expect(triggered).toBe(true)
		end)

		t.it("prolonge à 20 s s'il restait moins", function()
			local deadline, triggered = Scoring.deadlineAfterFinish(170, 180, 1, false)
			t.expect(deadline).toBe(190)
			t.expect(triggered).toBe(true)
		end)

		t.it("ne se déclenche qu'une fois", function()
			local deadline, triggered = Scoring.deadlineAfterFinish(100, 115, 1, true)
			t.expect(deadline).toBe(115)
			t.expect(triggered).toBe(false)
		end)

		t.it("suit l'échelle de temps de l'hôte", function()
			local minimum, maximum = Scoring.overtimeWindow(2)
			t.expect(minimum).toBe(40)
			t.expect(maximum).toBe(90)
			local deadline = Scoring.deadlineAfterFinish(0, 600, 2, false)
			t.expect(deadline).toBe(90)
		end)
	end)

	t.describe("Plafond de coups et coups retenus (§4)", function()
		t.it("vaut par + 7 borné entre 10 et 14", function()
			t.expect(Scoring.strokeCap(2)).toBe(10)
			t.expect(Scoring.strokeCap(3)).toBe(10)
			t.expect(Scoring.strokeCap(4)).toBe(11)
			t.expect(Scoring.strokeCap(5)).toBe(12)
			t.expect(Scoring.strokeCap(6)).toBe(13)
			t.expect(Scoring.strokeCap(0 / 0)).toBe(14)
		end)

		t.it("retient max(coups, plafond) pour un non-arrivant", function()
			t.expect(Scoring.standingStrokes("Finished", 4, 11)).toBe(4)
			t.expect(Scoring.standingStrokes("Finished", 0, 11)).toBe(1)
			t.expect(Scoring.standingStrokes("TimeOut", 5, 11)).toBe(11)
			t.expect(Scoring.standingStrokes("Forfeit", 13, 11)).toBe(13)
			t.expect(Scoring.standingStrokes("Disconnected", 0, 10)).toBe(10)
			t.expect(Scoring.standingStrokes("AFK", 2, 12)).toBe(12)
		end)
	end)

	t.describe("Équipes (§6)", function()
		t.it("donne le point au meilleur ratio d'arrivées", function()
			local winner, reason = Scoring.teamHolePoint(
				{ size = 4, finishers = 3, finisherStrokes = 12 },
				{ size = 4, finishers = 2, finisherStrokes = 6 }
			)
			t.expect(winner).toBe("Red")
			t.expect(reason).toBe("ratio")
		end)

		t.it("traite les équipes déséquilibrées par le ratio (2/3 contre 3/5)", function()
			local winner = Scoring.teamHolePoint(
				{ size = 3, finishers = 2, finisherStrokes = 8 },
				{ size = 5, finishers = 3, finisherStrokes = 9 }
			)
			t.expect(winner).toBe("Red")
		end)

		t.it("départage les ratios égaux par les arrivées absolues", function()
			local winner, reason = Scoring.teamHolePoint(
				{ size = 4, finishers = 2, finisherStrokes = 10 },
				{ size = 2, finishers = 1, finisherStrokes = 3 }
			)
			t.expect(winner).toBe("Red")
			t.expect(reason).toBe("finishers")
		end)

		t.it("départage ensuite par la moyenne de coups des arrivants", function()
			local winner, reason = Scoring.teamHolePoint(
				{ size = 4, finishers = 2, finisherStrokes = 7 },
				{ size = 4, finishers = 2, finisherStrokes = 8 }
			)
			t.expect(winner).toBe("Red")
			t.expect(reason).toBe("strokes")
		end)

		t.it("ne donne aucun point en cas d'égalité complète ou sans arrivée", function()
			local winner = Scoring.teamHolePoint(
				{ size = 2, finishers = 1, finisherStrokes = 4 },
				{ size = 2, finishers = 1, finisherStrokes = 4 }
			)
			t.expect(winner).toBeNil()
			local none = Scoring.teamHolePoint(
				{ size = 3, finishers = 0, finisherStrokes = 0 },
				{ size = 2, finishers = 0, finisherStrokes = 0 }
			)
			t.expect(none).toBeNil()
		end)

		t.it("donne la victoire au plus grand total, sinon match nul", function()
			t.expect(Scoring.teamMatchResult(3, 1)).toBe("Red")
			t.expect(Scoring.teamMatchResult(1, 2)).toBe("Blue")
			t.expect(Scoring.teamMatchResult(2, 2)).toBe("Draw")
			t.expect(Scoring.teamResultFor("Red", "Red")).toBe("Win")
			t.expect(Scoring.teamResultFor("Blue", "Red")).toBe("Lose")
			t.expect(Scoring.teamResultFor("Blue", "Draw")).toBe("Draw")
			t.expect(Scoring.teamResultFor(nil, "Red")).toBeNil()
		end)

		t.it("respecte les choix et place les Auto dans l'équipe la moins nombreuse", function()
			t.expect(Scoring.assignTeams({ "Auto", "Auto", "Auto" })).toEqual({ "Red", "Blue", "Red" })
			t.expect(Scoring.assignTeams({ "Red", "Auto", "Auto" })).toEqual({ "Red", "Blue", "Red" })
			t.expect(Scoring.assignTeams({ "Blue", "Blue", "Auto" })).toEqual({ "Blue", "Blue", "Red" })
		end)

		t.it("ne laisse jamais une équipe vide avec au moins deux joueurs", function()
			t.expect(Scoring.assignTeams({ "Red", "Red" })).toEqual({ "Red", "Blue" })
			t.expect(Scoring.assignTeams({ "Blue", "Blue", "Blue" })).toEqual({ "Blue", "Blue", "Red" })
			t.expect(Scoring.assignTeams({ "Red" })).toEqual({ "Red" })
		end)

		t.it("équilibre Rouge, Bleu, Rouge… dans l'ordre d'arrivée", function()
			t.expect(Scoring.balanceTeams(5)).toEqual({ "Red", "Blue", "Red", "Blue", "Red" })
			t.expect(Scoring.balanceTeams(0)).toEqual({})
		end)
	end)

	t.describe("Solo (§7)", function()
		t.it("compte les trous non terminés au plafond et à la durée limite", function()
			local summary = Scoring.soloSummary({
				{ finished = true, strokes = 3, par = 4, time = 50, timeLimit = 180, cap = 11 },
				{ finished = false, strokes = 5, par = 3, time = nil, timeLimit = 120, cap = 10 },
			})
			t.expect(summary.strokes).toBe(13)
			t.expect(summary.par).toBe(7)
			t.expect(summary.toPar).toBe(6)
			t.expect(summary.time).toBe(170)
			t.expect(summary.holesFinished).toBe(1)
			t.expect(summary.holes).toBe(2)
		end)

		t.it("garde le meilleur record : moins de coups, puis temps plus court", function()
			t.expect(Scoring.isBetterSoloRecord({ strokes = 3, time = 50 }, nil)).toBe(true)
			t.expect(Scoring.isBetterSoloRecord({ strokes = 3, time = 50 }, { strokes = 4, time = 10 })).toBe(true)
			t.expect(Scoring.isBetterSoloRecord({ strokes = 3, time = 50 }, { strokes = 3, time = 40 })).toBe(false)
			t.expect(Scoring.isBetterSoloRecord({ strokes = 3, time = 30 }, { strokes = 3, time = 40 })).toBe(true)
			t.expect(Scoring.isBetterSoloRecord({ strokes = 0 / 0, time = 30 }, nil)).toBe(false)
		end)

		t.it("affiche l'écart au par avec son signe", function()
			t.expect(Scoring.signed(2)).toBe("+2")
			t.expect(Scoring.signed(0)).toBe("0")
			t.expect(Scoring.signed(-1)).toBe("-1")
		end)
	end)
end
