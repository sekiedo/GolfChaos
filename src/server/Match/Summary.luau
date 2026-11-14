--!strict
--[[
	Match.Summary — résumé de fin de partie et ordre du podium (extraits de MatchService, sans changement de comportement).

	  Summary.build(m, rows) -> (summary, payload)   summary garde les joueurs (serveur), payload est sérialisable (réseau)
	  Summary.podiumOrder(m, standings, winner, isPresent) -> { Player }   trois premiers d'abord ; équipe gagnante en tête
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Scoring = require(Shared.Logic.Scoring)

local MatchTypes = require(script.Parent.Types)

type MatchState = MatchTypes.MatchState

local Summary = {}

function Summary.build(m: MatchState, rows: { Scoring.StandingRow }): ({ [string]: any }, { [string]: any })
	local winner: string? = nil
	if m.mode == "Teams" then
		winner = Scoring.teamMatchResult(m.teamScores.Red, m.teamScores.Blue)
	end
	local standings = {}
	local playersInfo = {}
	local netPlayers = {}
	for _, row in rows do
		local record = m.records[row.userId]
		table.insert(standings, {
			userId = row.userId,
			name = row.name,
			team = row.team,
			points = row.points,
			strokes = row.totalStrokes,
			holeWins = row.holeWins,
			rank = row.rank,
		})
		if record then
			local teamResult = if winner ~= nil
				then Scoring.teamResultFor(record.team, winner :: any)
				else nil
			local soloSummary = Scoring.soloSummary(record.soloHoles)
			local info = {
				userId = record.userId,
				name = record.name,
				team = record.team,
				mode = m.mode,
				rank = row.rank,
				participants = #rows,
				holeCount = m.holesPlayed,
				activeHoles = record.activeHoles,
				holesFinished = record.holesFinished,
				parOrBetter = record.parOrBetter,
				holeInOnes = record.holeInOnes,
				eagles = record.eagles,
				birdies = record.birdies,
				teamResult = teamResult,
				solo = {
					strokes = soloSummary.strokes,
					par = soloSummary.par,
					toPar = soloSummary.toPar,
					toParText = Scoring.signed(soloSummary.toPar),
					time = soloSummary.time,
					holesFinished = soloSummary.holesFinished,
				},
			}
			table.insert(netPlayers, info)
			local withPlayer = table.clone(info) :: { [string]: any }
			withPlayer.player = record.player
			table.insert(playersInfo, withPlayer)
		end
	end
	local base = {
		matchId = m.id,
		mode = m.mode,
		standings = standings,
		teamScores = { Red = m.teamScores.Red, Blue = m.teamScores.Blue },
		winner = winner,
		winnerUserId = if m.mode ~= "Teams" and rows[1] then rows[1].userId else 0,
		holeCount = m.holesPlayed,
		completed = true,
	}
	local summary = table.clone(base) :: { [string]: any }
	summary.players = playersInfo
	local payload = table.clone(base) :: { [string]: any }
	payload.players = netPlayers
	return summary, payload
end

-- Places du podium : les trois premiers (en mode Équipes, l'équipe gagnante d'abord).
function Summary.podiumOrder(m: MatchState, standings: { { [string]: any } }, winner: string?, isPresent: (Player?) -> boolean): { Player }
	local ordered: { { [string]: any } } = {}
	if m.mode == "Teams" and (winner == "Red" or winner == "Blue") then
		for _, row in standings do
			if row.team == winner then
				table.insert(ordered, row)
			end
		end
		for _, row in standings do
			if row.team ~= winner then
				table.insert(ordered, row)
			end
		end
	else
		ordered = standings
	end
	local result: { Player } = {}
	for _, row in ordered do
		local record = m.records[row.userId]
		local player = record and record.player
		if player and isPresent(player) then
			table.insert(result, player)
		end
	end
	return result
end

return Summary
