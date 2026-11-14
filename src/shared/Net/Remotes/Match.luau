--!strict
--[[
	Remotes de la partie (MatchService). L'état continu passe par les attributs de ReplicatedStorage.GameState
	et des joueurs (docs/ARCHITECTURE.md §6) ; ces remotes ne portent que des événements ponctuels.
]]
return {
	-- Serveur -> tous : un joueur a terminé le trou. ({ userId, name, finishOrder, strokes, par, points, bonuses })
	["Match.PlayerFinished"] = { kind = "Event", dir = "ToClient" },
	-- Serveur -> tous : résultats du trou. ({ holeId, holeName, par, results = { HoleResult }, teamScores = { Red, Blue }, teamWinner })
	["Match.HoleResults"] = { kind = "Event", dir = "ToClient" },
	-- Serveur -> tous : fin de partie. ({ matchId, mode, standings = { { userId, name, team, points, strokes, rank } }, teamScores, winner })
	["Match.Podium"] = { kind = "Event", dir = "ToClient" },
	-- Serveur -> tous ou un joueur : annonce localisée. (cléLocale, variables?)
	["Match.Announce"] = { kind = "Event", dir = "ToClient" },
	-- Client -> serveur : abandonner le trou courant (reste spectateur du trou). (roundId)
	["Match.Forfeit"] = { kind = "Event", dir = "ToServer", args = { "integer" }, rate = 0.5, burst = 1 },
	-- Client -> serveur : préférer être spectateur à la prochaine partie (true) ou participant (false).
	["Match.SetSpectator"] = { kind = "Event", dir = "ToServer", args = { "boolean" }, rate = 1, burst = 2 },
	-- Client -> serveur : signaler une activité (anti-AFK) quand le joueur bouge la caméra/l'avatar. (roundId)
	["Match.Heartbeat"] = { kind = "Event", dir = "ToServer", args = { "integer" }, rate = 0.5, burst = 2 },
}
