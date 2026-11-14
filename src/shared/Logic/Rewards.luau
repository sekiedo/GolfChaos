--!strict
--[[
	Logic.Rewards — calcul pur des pièces de fin de partie (testé ; aucune dépendance moteur).

	  Rewards.computeMatch(input, economy) -> { eligible, reason?, total, breakdown = { [poste] = pièces } }

	input = {
		mode = "FreeForAll" | "Teams" | "Solo" | "Training",
		rank = number?,            -- rang final (Chacun pour soi)
		participants = number,     -- nombre de participants classés
		holeCount = number,        -- nombre de trous de la partie
		activeHoles = number,      -- trous avec au moins un coup accepté
		holesFinished = number,    -- balles rentrées
		parOrBetter = number,      -- trous au par ou mieux
		holeInOnes = number, eagles = number, birdies = number,
		teamResult = ("Win" | "Lose" | "Draw")?,
	}
	Le montant n'est jamais négatif, toujours entier, et plafonné par economy.MatchCap.
]]

local Rewards = {}

export type MatchInput = {
	mode: string,
	rank: number?,
	participants: number,
	holeCount: number,
	activeHoles: number,
	holesFinished: number,
	parOrBetter: number,
	holeInOnes: number,
	eagles: number,
	birdies: number,
	teamResult: string?,
}

export type MatchReward = {
	eligible: boolean,
	reason: string?,
	total: number,
	breakdown: { [string]: number },
}

local function int(value: number?): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return math.max(0, math.floor(value))
end

function Rewards.computeMatch(input: MatchInput, economy: any): MatchReward
	local breakdown: { [string]: number } = {}
	if input.mode == "Training" then
		return { eligible = false, reason = "training", total = 0, breakdown = breakdown }
	end
	local holeCount = int(input.holeCount)
	local required = math.min(economy.MinActiveHoles, holeCount)
	if holeCount <= 0 or int(input.activeHoles) < math.max(1, required) then
		return { eligible = false, reason = "inactive", total = 0, breakdown = breakdown }
	end

	breakdown.base = economy.Base
	breakdown.holes = economy.PerHoleFinished * math.min(int(input.holesFinished), holeCount)

	if input.mode == "FreeForAll" then
		local rank = int(input.rank)
		if rank >= 1 and int(input.participants) >= 2 then
			breakdown.placement = economy.Placement[rank] or economy.Placement.Others
		end
	elseif input.mode == "Teams" then
		local result = input.teamResult
		if result == "Win" then
			breakdown.team = economy.Team.Win
		elseif result == "Draw" then
			breakdown.team = economy.Team.Draw
		elseif result == "Lose" then
			breakdown.team = economy.Team.Lose
		end
	elseif input.mode == "Solo" then
		breakdown.solo = economy.Solo.Base + economy.Solo.PerParOrBetter * math.min(int(input.parOrBetter), holeCount)
	end

	local performance = economy.Performance.HoleInOne * int(input.holeInOnes)
		+ economy.Performance.Eagle * int(input.eagles)
		+ economy.Performance.Birdie * int(input.birdies)
	if performance > 0 then
		breakdown.performance = math.min(performance, economy.PerformanceCap)
	end

	local total = 0
	for _, amount in breakdown do
		total += amount
	end
	if total > economy.MatchCap then
		breakdown.cap = economy.MatchCap - total
		total = economy.MatchCap
	end
	return { eligible = true, reason = nil, total = int(total), breakdown = breakdown }
end

return Rewards
