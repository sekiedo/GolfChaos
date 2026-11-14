--!strict
--[[
	Remotes de progression (AchievementService, RewardService). Tout est décidé et versé par le serveur.
]]
return {
	-- Serveur -> client : défi réussi. (achievementId, pièces versées)
	["Progress.AchievementCompleted"] = { kind = "Event", dir = "ToClient" },
	-- Serveur -> client : récompense de fin de partie. ({ total, breakdown, eligible, reason? })
	["Progress.MatchReward"] = { kind = "Event", dir = "ToClient" },
}
