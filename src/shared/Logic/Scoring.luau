--!strict
--[[
	Logic.Scoring — calcul PUR du score (spécification : docs/REGLES_SCORE.md ; valeurs : Config/Scoring.luau).
	Aucune dépendance moteur, aucun effet de bord : testé par tests/Specs/Scoring.spec.luau et appliqué par
	MatchService. Chaque fonction accepte une configuration facultative (défaut : Config.Scoring) pour les tests.

	Barème et bonus
	  Scoring.arrivalPoints(rank?, config?)                         -> points du rang d'arrivée (0 si non arrivé)
	  Scoring.parCategory(strokes, par)                             -> "holeInOne" | "albatross" | "eagle" | "birdie" | "par" | nil
	  Scoring.isLongShot(fromDistance?, wasPutt?, config?)          -> boolean
	  Scoring.isSpeedBonus(finishTime?, referenceTime?, config?)    -> boolean
	  Scoring.computeBonuses(input, config?)                        -> { category, ids, raw, total (plafonné) }
	  Scoring.scoreHole(input, config?)                             -> { arrival, bonus, points }
	Arrivées et classements
	  Scoring.nextFinishRank(previousCount, lastFrame?, lastRank?, frame) -> rang (même image = rang partagé)
	  Scoring.competitionRanks(items, better)                       -> rangs « 1, 1, 3 » alignés sur items
	  Scoring.matchStandings(entries)                               -> lignes triées avec rang (départages §5.8)
	Chronomètre, prolongation, plafond de coups
	  Scoring.referenceTime(targetTime?, timeScale?, config?)       -> targetTime × timeScale
	  Scoring.holeTimeLimit(targetTime?, timeScale?, config?)       -> clamp(référence × Facteur, Min, Max)
	  Scoring.overtimeWindow(timeScale?, config?)                   -> (min, max) du temps restant
	  Scoring.deadlineAfterFinish(now, deadline, timeScale?, alreadyTriggered, config?) -> (échéance, déclenchée)
	  Scoring.strokeCap(par, config?)                               -> clamp(par + 7, 10, 14)
	  Scoring.standingStrokes(status, strokes, cap)                 -> coups retenus au départage
	Équipes
	  Scoring.teamHolePoint(red, blue)                              -> ("Red" | "Blue" | nil, motif)
	  Scoring.teamMatchResult(redScore, blueScore)                  -> "Red" | "Blue" | "Draw"
	  Scoring.teamResultFor(team?, winner)                          -> "Win" | "Lose" | "Draw" | nil
	  Scoring.assignTeams(choices)                                  -> { Team } (choix respectés, Auto équilibrés)
	  Scoring.balanceTeams(count)                                   -> { Team } (Rouge, Bleu, Rouge…)
	Solo
	  Scoring.soloSummary(holes)                                    -> { strokes, par, toPar, time, holesFinished, holes }
	  Scoring.isBetterSoloRecord(candidate, previous?)              -> boolean (moins de coups, puis temps)
	  Scoring.signed(n)                                             -> "+2" | "0" | "-1"
]]

local ConfigScoring = require(script.Parent.Parent.Config.Scoring)
local Types = require(script.Parent.Parent.Types)

export type ScoringConfig = typeof(ConfigScoring)
export type ParCategory = ConfigScoring.ParCategory
export type HoleStatus = "Finished" | "TimeOut" | "Forfeit" | "Disconnected" | "AFK"
export type TeamChoice = "Red" | "Blue" | "Auto"

export type BonusInput = {
	strokes: number,
	par: number,
	fromDistance: number?, -- distance horizontale du coup final au trou (studs)
	wasPutt: boolean?,
	finishTime: number?, -- secondes depuis le début du trou
	referenceTime: number?, -- targetTime × timeScale
}

export type BonusResult = {
	category: ParCategory?,
	ids: { string }, -- identifiants des bonus obtenus (catégorie, "longShot", "speed")
	raw: number, -- somme avant plafond
	total: number, -- somme plafonnée (BonusCap)
}

export type ScoreInput = {
	status: HoleStatus,
	rank: number?,
	strokes: number,
	par: number,
	fromDistance: number?,
	wasPutt: boolean?,
	finishTime: number?,
	referenceTime: number?,
	withArrival: boolean?, -- false : pas de barème d'arrivée (Solo, Entraînement)
	withBonuses: boolean?, -- false : aucun bonus (Entraînement)
}

export type HoleScore = {
	arrival: number,
	bonus: BonusResult,
	points: number,
}

export type StandingInput = {
	userId: number,
	name: string,
	team: Types.Team?,
	points: number,
	holeWins: number,
	totalStrokes: number,
	birdiesOrBetter: number,
}

export type StandingRow = {
	userId: number,
	name: string,
	team: Types.Team?,
	points: number,
	holeWins: number,
	totalStrokes: number,
	birdiesOrBetter: number,
	rank: number,
}

export type TeamHoleStats = {
	size: number, -- membres de l'équipe participant au trou au départ (déconnectés compris)
	finishers: number, -- membres ayant rentré leur balle
	finisherStrokes: number, -- somme des coups des membres arrivés
}

export type SoloHole = {
	finished: boolean,
	strokes: number,
	par: number,
	time: number?, -- temps d'arrivée (trou terminé)
	timeLimit: number, -- durée limite du trou (retenue si non terminé)
	cap: number, -- plafond de coups du trou
}

export type SoloSummary = {
	strokes: number,
	par: number,
	toPar: number,
	time: number,
	holesFinished: number,
	holes: number,
}

export type SoloRecord = { strokes: number, time: number }

local Scoring = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function resolve(config: ScoringConfig?): ScoringConfig
	return config or ConfigScoring
end

local function nonNegativeInteger(value: any): number
	if not isFinite(value) then
		return 0
	end
	return math.max(0, math.floor(value))
end

local function emptyBonus(): BonusResult
	return { category = nil, ids = {}, raw = 0, total = 0 }
end

Scoring.emptyBonus = emptyBonus

--------------------------------------------------------------------------------
-- Barème d'arrivée et bonus
--------------------------------------------------------------------------------

function Scoring.arrivalPoints(rank: number?, config: ScoringConfig?): number
	local c = resolve(config)
	if rank == nil or not isFinite(rank) or rank < 1 then
		return c.DnfPoints
	end
	local value = c.ArrivalPoints[math.floor(rank)]
	if value ~= nil then
		return value
	end
	return c.ArrivalPointsBeyond
end

-- Meilleure catégorie atteinte par rapport au par (nil : bogey ou pire, ou données invalides).
function Scoring.parCategory(strokes: number, par: number): ParCategory?
	if not isFinite(strokes) or not isFinite(par) or strokes < 1 then
		return nil
	end
	local count = math.floor(strokes)
	if count == 1 then
		return "holeInOne"
	end
	local diff = count - math.floor(par)
	if diff <= -3 then
		return "albatross"
	elseif diff == -2 then
		return "eagle"
	elseif diff == -1 then
		return "birdie"
	elseif diff == 0 then
		return "par"
	end
	return nil
end

-- Vrai pour une catégorie « birdie ou mieux » (trou en un compris).
function Scoring.isBirdieOrBetter(category: ParCategory?): boolean
	return category == "holeInOne" or category == "albatross" or category == "eagle" or category == "birdie"
end

function Scoring.isParOrBetter(category: ParCategory?): boolean
	return category ~= nil
end

function Scoring.isLongShot(fromDistance: number?, wasPutt: boolean?, config: ScoringConfig?): boolean
	local rule = resolve(config).LongShot
	if not rule.Enabled or fromDistance == nil or not isFinite(fromDistance) then
		return false
	end
	if wasPutt == true and not rule.CountPutts then
		return false
	end
	return fromDistance >= rule.MinDistance
end

function Scoring.isSpeedBonus(finishTime: number?, referenceTime: number?, config: ScoringConfig?): boolean
	local rule = resolve(config).Speed
	if not rule.Enabled then
		return false
	end
	if finishTime == nil or referenceTime == nil or not isFinite(finishTime) or not isFinite(referenceTime) then
		return false
	end
	if referenceTime <= 0 or finishTime < 0 then
		return false
	end
	return finishTime <= referenceTime * rule.MaxFraction
end

-- Bonus cumulables (catégorie + loin + vitesse), plafonnés à BonusCap.
function Scoring.computeBonuses(input: BonusInput, config: ScoringConfig?): BonusResult
	local c = resolve(config)
	local ids: { string } = {}
	local raw = 0
	local category = Scoring.parCategory(input.strokes, input.par)
	if category ~= nil then
		local value = c.ParBonus[category] or 0
		if value > 0 then
			table.insert(ids, category)
			raw += value
		end
	end
	if Scoring.isLongShot(input.fromDistance, input.wasPutt, c) and c.LongShot.Points > 0 then
		table.insert(ids, c.LongShot.Id)
		raw += c.LongShot.Points
	end
	if Scoring.isSpeedBonus(input.finishTime, input.referenceTime, c) and c.Speed.Points > 0 then
		table.insert(ids, c.Speed.Id)
		raw += c.Speed.Points
	end
	local total = math.clamp(raw, 0, math.max(0, c.BonusCap))
	return { category = category, ids = ids, raw = raw, total = total }
end

-- Points d'un trou : barème(rang) + bonus plafonnés ; 0 si le trou n'est pas terminé.
function Scoring.scoreHole(input: ScoreInput, config: ScoringConfig?): HoleScore
	local c = resolve(config)
	if input.status ~= "Finished" then
		return { arrival = c.DnfPoints, bonus = emptyBonus(), points = c.DnfPoints }
	end
	local arrival = if input.withArrival == false then 0 else Scoring.arrivalPoints(input.rank, c)
	local bonus: BonusResult
	if input.withBonuses == false then
		bonus = emptyBonus()
	else
		bonus = Scoring.computeBonuses({
			strokes = input.strokes,
			par = input.par,
			fromDistance = input.fromDistance,
			wasPutt = input.wasPutt,
			finishTime = input.finishTime,
			referenceTime = input.referenceTime,
		}, c)
	end
	return { arrival = arrival, bonus = bonus, points = arrival + bonus.total }
end

--------------------------------------------------------------------------------
-- Arrivées simultanées et classements
--------------------------------------------------------------------------------

-- Rang d'une nouvelle arrivée. Une arrivée traitée pendant la même image serveur que la précédente partage son
-- rang (le meilleur) ; sinon rang = nombre d'arrivées précédentes + 1 (classement 1, 1, 3).
function Scoring.nextFinishRank(previousCount: number, lastFrame: number?, lastRank: number?, frame: number): number
	local count = nonNegativeInteger(previousCount)
	if count > 0 and lastFrame ~= nil and lastRank ~= nil and frame == lastFrame then
		return lastRank
	end
	return count + 1
end

-- Classement « compétition » : `better(a, b)` est vrai si a est strictement meilleur que b. Deux éléments dont
-- aucun n'est meilleur que l'autre partagent le meilleur rang ; le suivant saute (1, 1, 3).
-- Retourne les rangs dans l'ordre de `items` (ordre d'origine conservé entre ex æquo).
function Scoring.competitionRanks<T>(items: { T }, better: (T, T) -> boolean): { number }
	local order: { number } = {}
	for index = 1, #items do
		order[index] = index
	end
	table.sort(order, function(a: number, b: number): boolean
		local itemA, itemB = items[a], items[b]
		if better(itemA, itemB) then
			return true
		end
		if better(itemB, itemA) then
			return false
		end
		return a < b
	end)
	local ranks: { number } = table.create(#items, 0)
	for position, index in order do
		if position > 1 then
			local previous = order[position - 1]
			if not better(items[previous], items[index]) then
				ranks[index] = ranks[previous]
				continue
			end
		end
		ranks[index] = position
	end
	return ranks
end

-- a est-il strictement meilleur que b au classement de la partie (sans les critères d'affichage) ?
function Scoring.isBetterStanding(a: StandingInput, b: StandingInput): boolean
	if a.points ~= b.points then
		return a.points > b.points
	end
	if a.holeWins ~= b.holeWins then
		return a.holeWins > b.holeWins
	end
	if a.totalStrokes ~= b.totalStrokes then
		return a.totalStrokes < b.totalStrokes
	end
	if a.birdiesOrBetter ~= b.birdiesOrBetter then
		return a.birdiesOrBetter > b.birdiesOrBetter
	end
	return false
end

-- Classement final : points, trous gagnés, coups retenus, birdies ou mieux, puis rang partagé.
-- Ordre d'affichage entre ex æquo : nom puis UserId (sans effet sur le rang).
function Scoring.matchStandings(entries: { StandingInput }): { StandingRow }
	local rows: { StandingRow } = {}
	for _, entry in entries do
		table.insert(rows, {
			userId = entry.userId,
			name = entry.name,
			team = entry.team,
			points = entry.points,
			holeWins = entry.holeWins,
			totalStrokes = entry.totalStrokes,
			birdiesOrBetter = entry.birdiesOrBetter,
			rank = 0,
		})
	end
	table.sort(rows, function(a: StandingRow, b: StandingRow): boolean
		if Scoring.isBetterStanding(a, b) then
			return true
		end
		if Scoring.isBetterStanding(b, a) then
			return false
		end
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.userId < b.userId
	end)
	for index, row in rows do
		if index > 1 and not Scoring.isBetterStanding(rows[index - 1], row) then
			row.rank = rows[index - 1].rank
		else
			row.rank = index
		end
	end
	return rows
end

--------------------------------------------------------------------------------
-- Chronomètre, prolongation, plafond de coups
--------------------------------------------------------------------------------

local function validScale(timeScale: number?): number
	if timeScale ~= nil and isFinite(timeScale) and timeScale > 0 then
		return timeScale
	end
	return 1
end

-- Durée de référence d'un trou (bonus de vitesse) : targetTime × timeScale.
function Scoring.referenceTime(targetTime: number?, timeScale: number?, config: ScoringConfig?): number
	local c = resolve(config)
	local target = if targetTime ~= nil and isFinite(targetTime) and targetTime > 0
		then targetTime
		else c.HoleTime.DefaultTargetTime
	return target * validScale(timeScale)
end

-- Durée limite d'un trou : clamp(targetTime × timeScale × Facteur, Min, Max).
function Scoring.holeTimeLimit(targetTime: number?, timeScale: number?, config: ScoringConfig?): number
	local c = resolve(config)
	local limit = Scoring.referenceTime(targetTime, timeScale, c) * c.HoleTime.Factor
	return math.clamp(limit, c.HoleTime.Min, c.HoleTime.Max)
end

-- Fenêtre du temps restant après la première arrivée.
function Scoring.overtimeWindow(timeScale: number?, config: ScoringConfig?): (number, number)
	local c = resolve(config)
	local scale = if c.Overtime.ScaleWithTimeScale then validScale(timeScale) else 1
	local minimum = c.Overtime.Min * scale
	local maximum = math.max(minimum, c.Overtime.Max * scale)
	return minimum, maximum
end

-- Échéance du trou après une arrivée. La première arrivée ramène le temps restant dans la fenêtre de prolongation
-- (réduction ou extension) ; les suivantes ne changent rien. Retourne (échéance, prolongation déclenchée maintenant).
function Scoring.deadlineAfterFinish(
	now: number,
	deadline: number,
	timeScale: number?,
	alreadyTriggered: boolean,
	config: ScoringConfig?
): (number, boolean)
	local c = resolve(config)
	if alreadyTriggered or not c.Overtime.Enabled or not isFinite(now) or not isFinite(deadline) then
		return deadline, false
	end
	local minimum, maximum = Scoring.overtimeWindow(timeScale, c)
	local remaining = math.clamp(deadline - now, minimum, maximum)
	return now + remaining, true
end

-- Plafond de coups d'un trou (au-delà : frappe refusée ; balle immobile au plafond : abandon automatique).
function Scoring.strokeCap(par: number, config: ScoringConfig?): number
	local rule = resolve(config).StrokeCap
	if not isFinite(par) then
		return rule.Max
	end
	return math.clamp(math.floor(par) + rule.ParOffset, rule.Min, rule.Max)
end

-- Coups retenus au départage : coups réels pour un trou terminé, sinon max(coups, plafond).
function Scoring.standingStrokes(status: HoleStatus, strokes: number, cap: number): number
	local count = nonNegativeInteger(strokes)
	if status == "Finished" then
		return math.max(1, count)
	end
	return math.max(count, nonNegativeInteger(cap))
end

--------------------------------------------------------------------------------
-- Équipes
--------------------------------------------------------------------------------

local function sanitizeTeam(stats: TeamHoleStats): (number, number, number)
	local size = nonNegativeInteger(stats.size)
	local finishers = math.min(nonNegativeInteger(stats.finishers), size)
	local strokes = nonNegativeInteger(stats.finisherStrokes)
	return size, finishers, strokes
end

-- Point d'équipe d'un trou : ratio d'arrivées (arrivées / taille), puis arrivées absolues, puis moyenne de coups
-- des arrivants la plus basse ; sinon aucun point. Comparaisons exactes par produits croisés (aucun arrondi).
-- Retourne (équipe gagnante ou nil, motif "ratio" | "finishers" | "strokes" | "tie").
function Scoring.teamHolePoint(red: TeamHoleStats, blue: TeamHoleStats): (Types.Team?, string)
	local redSize, redFinishers, redStrokes = sanitizeTeam(red)
	local blueSize, blueFinishers, blueStrokes = sanitizeTeam(blue)

	-- Ratio : une équipe sans membre a un ratio nul.
	local redNum, redDen = if redSize > 0 then redFinishers else 0, if redSize > 0 then redSize else 1
	local blueNum, blueDen = if blueSize > 0 then blueFinishers else 0, if blueSize > 0 then blueSize else 1
	local left, right = redNum * blueDen, blueNum * redDen
	if left > right then
		return "Red", "ratio"
	elseif right > left then
		return "Blue", "ratio"
	end

	if redFinishers > blueFinishers then
		return "Red", "finishers"
	elseif blueFinishers > redFinishers then
		return "Blue", "finishers"
	end

	if redFinishers > 0 and blueFinishers > 0 then
		-- Moyenne redStrokes/redFinishers contre blueStrokes/blueFinishers.
		local redAverage, blueAverage = redStrokes * blueFinishers, blueStrokes * redFinishers
		if redAverage < blueAverage then
			return "Red", "strokes"
		elseif blueAverage < redAverage then
			return "Blue", "strokes"
		end
	end
	return nil, "tie"
end

function Scoring.teamMatchResult(redScore: number, blueScore: number): "Red" | "Blue" | "Draw"
	local red = if isFinite(redScore) then redScore else 0
	local blue = if isFinite(blueScore) then blueScore else 0
	if red > blue then
		return "Red"
	elseif blue > red then
		return "Blue"
	end
	return "Draw"
end

-- Résultat d'équipe d'un joueur pour les récompenses ; nil sans équipe.
function Scoring.teamResultFor(team: Types.Team?, winner: "Red" | "Blue" | "Draw"): ("Win" | "Lose" | "Draw")?
	if team == nil then
		return nil
	end
	if winner == "Draw" then
		return "Draw"
	end
	return if team == winner then "Win" else "Lose"
end

-- Composition des équipes au lancement. `choices` est dans l'ordre d'arrivée sur le serveur ; toute valeur autre
-- que "Red"/"Blue" vaut "Auto". Choix explicites respectés ; chaque Auto rejoint l'équipe la moins nombreuse
-- (Rouge en cas d'égalité) ; avec au moins 2 joueurs, aucune équipe vide : le dernier arrivé de l'équipe pleine
-- change d'équipe, en priorité un joueur Auto.
function Scoring.assignTeams(choices: { string }): { Types.Team }
	local result: { Types.Team } = table.create(#choices, "Red" :: Types.Team)
	local assigned: { boolean } = table.create(#choices, false)
	local redCount, blueCount = 0, 0
	for index, choice in choices do
		if choice == "Red" then
			result[index] = "Red"
			assigned[index] = true
			redCount += 1
		elseif choice == "Blue" then
			result[index] = "Blue"
			assigned[index] = true
			blueCount += 1
		end
	end
	for index = 1, #choices do
		if not assigned[index] then
			if redCount <= blueCount then
				result[index] = "Red"
				redCount += 1
			else
				result[index] = "Blue"
				blueCount += 1
			end
			assigned[index] = true
		end
	end
	if #choices >= 2 and (redCount == 0 or blueCount == 0) then
		local emptyTeam: Types.Team = if redCount == 0 then "Red" else "Blue"
		local fullTeam: Types.Team = if emptyTeam == "Red" then "Blue" else "Red"
		local moveIndex: number? = nil
		for index = #choices, 1, -1 do
			local choice = choices[index]
			if result[index] == fullTeam and choice ~= "Red" and choice ~= "Blue" then
				moveIndex = index
				break
			end
		end
		if moveIndex == nil then
			for index = #choices, 1, -1 do
				if result[index] == fullTeam then
					moveIndex = index
					break
				end
			end
		end
		if moveIndex ~= nil then
			result[moveIndex] = emptyTeam
		end
	end
	return result
end

-- Équilibrage déterministe : Rouge, Bleu, Rouge… dans l'ordre donné.
function Scoring.balanceTeams(count: number): { Types.Team }
	local result: { Types.Team } = {}
	for index = 1, nonNegativeInteger(count) do
		result[index] = if index % 2 == 1 then "Red" else "Blue"
	end
	return result
end

--------------------------------------------------------------------------------
-- Solo
--------------------------------------------------------------------------------

-- Score solo : coups totaux (trou non terminé = max(coups, plafond)), par total, écart au par, temps total
-- (trou non terminé = durée limite).
function Scoring.soloSummary(holes: { SoloHole }): SoloSummary
	local strokes, par, time, finished = 0, 0, 0, 0
	for _, hole in holes do
		if hole.finished then
			strokes += math.max(1, nonNegativeInteger(hole.strokes))
			time += if hole.time ~= nil and isFinite(hole.time) and hole.time >= 0 then hole.time else hole.timeLimit
			finished += 1
		else
			strokes += math.max(nonNegativeInteger(hole.strokes), nonNegativeInteger(hole.cap))
			time += if isFinite(hole.timeLimit) then math.max(0, hole.timeLimit) else 0
		end
		par += nonNegativeInteger(hole.par)
	end
	return {
		strokes = strokes,
		par = par,
		toPar = strokes - par,
		time = time,
		holesFinished = finished,
		holes = #holes,
	}
end

-- Record personnel : moins de coups, puis temps plus court. Un record précédent absent ou invalide est battu.
function Scoring.isBetterSoloRecord(candidate: SoloRecord, previous: SoloRecord?): boolean
	if not isFinite(candidate.strokes) or not isFinite(candidate.time) then
		return false
	end
	if previous == nil or not isFinite(previous.strokes) or not isFinite(previous.time) then
		return true
	end
	if candidate.strokes ~= previous.strokes then
		return candidate.strokes < previous.strokes
	end
	return candidate.time < previous.time
end

-- Écart signé pour l'affichage (« +2 », « 0 », « -1 ») ; aucun mot, donc pas de traduction nécessaire.
function Scoring.signed(value: number): string
	if not isFinite(value) then
		return "0"
	end
	local rounded = math.floor(value + 0.5)
	if rounded > 0 then
		return "+" .. tostring(rounded)
	end
	return tostring(rounded)
end

return Scoring
