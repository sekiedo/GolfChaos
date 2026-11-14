--!strict
--[[
	Config.Achievements — défis et succès INTERNES (fonctionnent sans BadgeId Roblox ; le champ badgeId permet
	de raccorder plus tard un vrai badge de plateforme, après publication).

	kind :
	  "Stat"  progression = profil.stats[stat] (compteur cumulé), atteint quand >= target
	  "Set"   progression = nombre d'éléments distincts dans profil.sets[stat] (ex. biomes terminés)
	  "Event" atteint quand AchievementService reçoit l'événement `event` (progression 0/1)
	Récompense versée une seule fois (opId = "ach:" .. id). Les ids référencés par les cosmétiques
	(ach_hole_in_one, ach_eagle, ach_win_match, ach_win_10, ach_ko_25, ach_items_50, ach_cart_5km,
	ach_all_biomes, ach_tutorial) ne doivent jamais changer.
]]

export type Category = "Golf" | "Precision" | "Exploration" | "Items" | "Survival" | "Team" | "Vehicles" | "Victory"
export type AchievementDef = {
	id: string,
	category: Category,
	nameKey: string,
	descKey: string,
	kind: "Stat" | "Set" | "Event",
	stat: string?,
	event: string?,
	target: number,
	reward: number,
	badgeId: number?, -- à renseigner après publication (jamais inventé)
}

local function stat(id: string, category: Category, statKey: string, target: number, reward: number): AchievementDef
	return { id = id, category = category, nameKey = "ach." .. id .. ".name", descKey = "ach." .. id .. ".desc", kind = "Stat", stat = statKey, target = target, reward = reward }
end

local function set(id: string, category: Category, setKey: string, target: number, reward: number): AchievementDef
	return { id = id, category = category, nameKey = "ach." .. id .. ".name", descKey = "ach." .. id .. ".desc", kind = "Set", stat = setKey, target = target, reward = reward }
end

local function event(id: string, category: Category, eventName: string, reward: number): AchievementDef
	return { id = id, category = category, nameKey = "ach." .. id .. ".name", descKey = "ach." .. id .. ".desc", kind = "Event", event = eventName, target = 1, reward = reward }
end

local list: { AchievementDef } = {
	-- Golf
	stat("ach_first_hole", "Golf", "holesFinished", 1, 50),
	stat("ach_par_10", "Golf", "parOrBetter", 10, 150),
	stat("ach_birdie", "Golf", "birdies", 1, 100),
	stat("ach_birdie_25", "Golf", "birdies", 25, 400),
	stat("ach_eagle", "Golf", "eagles", 1, 300),
	stat("ach_hole_in_one", "Golf", "holesInOne", 1, 600),
	stat("ach_holes_100", "Golf", "holesFinished", 100, 500),
	-- Précision
	stat("ach_long_shot", "Precision", "longShots", 1, 250),
	stat("ach_putt_master", "Precision", "onePutts", 20, 300),
	event("ach_no_penalty_9", "Precision", "noPenaltyNine", 300),
	stat("ach_chip_in", "Precision", "chipIns", 1, 200),
	-- Exploration
	set("ach_all_biomes", "Exploration", "biomesFinished", 5, 400),
	set("ach_coast_18", "Exploration", "holesFinished_Coast", 18, 500),
	set("ach_forest_18", "Exploration", "holesFinished_Forest", 18, 500),
	set("ach_desert_18", "Exploration", "holesFinished_Desert", 18, 500),
	set("ach_snow_18", "Exploration", "holesFinished_Snow", 18, 500),
	set("ach_city_9", "Exploration", "holesFinished_City", 9, 400),
	event("ach_tutorial", "Exploration", "tutorialDone", 100),
	-- Objets
	stat("ach_items_10", "Items", "itemsUsed", 10, 100),
	stat("ach_items_50", "Items", "itemsUsed", 50, 300),
	set("ach_all_items", "Items", "itemsUsedSet", 17, 600),
	stat("ach_shield_block", "Items", "shieldBlocks", 10, 250),
	stat("ach_horn_premature", "Items", "hornForcedShots", 5, 200),
	-- Survie
	stat("ach_ko_10", "Survival", "kos", 10, 150),
	stat("ach_ko_25", "Survival", "kos", 25, 350),
	stat("ach_dodge_10", "Survival", "dodges", 10, 250),
	event("ach_untouchable", "Survival", "untouchableMatch", 300),
	event("ach_comeback", "Survival", "comebackHole", 300),
	-- Équipe
	stat("ach_team_win", "Team", "teamWins", 1, 200),
	stat("ach_team_win_10", "Team", "teamWins", 10, 600),
	event("ach_team_all_finish", "Team", "teamAllFinished", 200),
	-- Véhicules
	stat("ach_cart_first", "Vehicles", "cartDistance", 100, 100),
	stat("ach_cart_5km", "Vehicles", "cartDistance", 5000, 400),
	stat("ach_cart_ram", "Vehicles", "cartKOs", 5, 250),
	event("ach_cart_full", "Vehicles", "cartFourPassengers", 300),
	-- Victoires
	stat("ach_win_match", "Victory", "matchesWon", 1, 300),
	stat("ach_win_10", "Victory", "matchesWon", 10, 1000),
	stat("ach_matches_25", "Victory", "matchesPlayed", 25, 300),
}

local byId: { [string]: AchievementDef } = {}
for _, def in list do
	byId[def.id] = def
end

local Achievements = {}
Achievements.List = list
Achievements.ById = byId
Achievements.LongShotDistance = 40 -- « Tir de sniper » : balle rentrée d'au moins 40 studs (hors putt)

function Achievements.get(id: string): AchievementDef?
	return byId[id]
end

-- Progression d'un défi à partir des statistiques et ensembles du profil (pur, utilisé client et serveur).
function Achievements.progress(def: AchievementDef, stats: { [string]: number }?, sets: { [string]: { [string]: boolean } }?, events: { [string]: boolean }?): number
	if def.kind == "Stat" then
		local value = stats and def.stat and stats[def.stat] or 0
		return math.min(value, def.target)
	elseif def.kind == "Set" then
		local count = 0
		local entries = sets and def.stat and sets[def.stat]
		if entries then
			for _, present in entries do
				if present then
					count += 1
				end
			end
		end
		return math.min(count, def.target)
	end
	return if events and def.event and events[def.event] then 1 else 0
end

return Achievements
