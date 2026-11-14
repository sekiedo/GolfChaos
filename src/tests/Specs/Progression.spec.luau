--!strict
-- Progression : défis (Config.Achievements) et récompenses de fin de partie (Logic.Rewards + Config.Economy).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Achievements = require(Shared.Config.Achievements)
local Economy = require(Shared.Config.Economy)
local Rewards = require(Shared.Logic.Rewards)
local Locale = require(Shared.Locale)

local REFERENCED_BY_COSMETICS = {
	"ach_hole_in_one", "ach_eagle", "ach_win_match", "ach_win_10", "ach_ko_25", "ach_items_50", "ach_cart_5km",
	"ach_all_biomes", "ach_tutorial",
}
local REQUIRED_CATEGORIES = { "Golf", "Precision", "Exploration", "Items", "Survival", "Team", "Vehicles" }

local function input(overrides: { [string]: any }): any
	local base = {
		mode = "FreeForAll", rank = 1, participants = 4, holeCount = 9, activeHoles = 9, holesFinished = 9,
		parOrBetter = 5, holeInOnes = 0, eagles = 0, birdies = 2, teamResult = nil,
	}
	for key, value in overrides do
		base[key] = value
	end
	return base
end

return function(t)
	t.describe("Défis", function()
		t.it("en propose au moins 30, aux ids uniques", function()
			t.expect(#Achievements.List).toBeGreaterThanOrEqual(30)
			local seen = {}
			for _, def in Achievements.List do
				t.expect(seen[def.id]).toBeNil()
				seen[def.id] = true
			end
		end)

		t.it("couvre toutes les catégories exigées", function()
			for _, category in REQUIRED_CATEGORIES do
				local found = false
				for _, def in Achievements.List do
					if def.category == category then
						found = true
					end
				end
				if not found then
					error("catégorie absente : " .. category)
				end
			end
		end)

		t.it("contient les défis référencés par les cosmétiques", function()
			for _, id in REFERENCED_BY_COSMETICS do
				t.expect(Achievements.get(id)).notToBeNil()
			end
		end)

		t.it("a des définitions complètes, des récompenses positives et des textes fr/en", function()
			for _, def in Achievements.List do
				assert(def.target >= 1, def.id .. " : cible")
				assert(def.reward > 0 and math.floor(def.reward) == def.reward, def.id .. " : récompense")
				if def.kind == "Event" then
					assert(type(def.event) == "string", def.id .. " : événement")
				else
					assert(type(def.stat) == "string", def.id .. " : statistique")
				end
				assert(def.badgeId == nil, def.id .. " : aucun BadgeId ne doit être inventé")
				for _, key in { def.nameKey, def.descKey } do
					assert(Locale.has(key, "fr") and Locale.has(key, "en"), "texte manquant : " .. key)
				end
			end
		end)

		t.it("calcule la progression des trois types", function()
			local birdies = Achievements.get("ach_birdie_25") :: any
			t.expect(Achievements.progress(birdies, { birdies = 7 }, nil, nil)).toBe(7)
			t.expect(Achievements.progress(birdies, { birdies = 99 }, nil, nil)).toBe(25)
			local biomes = Achievements.get("ach_all_biomes") :: any
			t.expect(Achievements.progress(biomes, nil, { biomesFinished = { Coast = true, Snow = true } }, nil)).toBe(2)
			local tutorial = Achievements.get("ach_tutorial") :: any
			t.expect(Achievements.progress(tutorial, nil, nil, { tutorialDone = true })).toBe(1)
			t.expect(Achievements.progress(tutorial, nil, nil, nil)).toBe(0)
		end)
	end)

	t.describe("Récompenses de fin de partie", function()
		t.it("ne donne rien en entraînement", function()
			local reward = Rewards.computeMatch(input({ mode = "Training" }), Economy)
			t.expect(reward.eligible).toBeFalsy()
			t.expect(reward.total).toBe(0)
		end)

		t.it("ne donne rien à un joueur inactif (AFK)", function()
			local reward = Rewards.computeMatch(input({ activeHoles = 1, holesFinished = 0 }), Economy)
			t.expect(reward.eligible).toBeFalsy()
			t.expect(reward.total).toBe(0)
		end)

		t.it("accepte une partie courte si tous ses trous ont été joués", function()
			local reward = Rewards.computeMatch(input({ holeCount = 1, activeHoles = 1, holesFinished = 1 }), Economy)
			t.expect(reward.eligible).toBeTruthy()
		end)

		t.it("récompense le classement en Chacun pour soi", function()
			local first = Rewards.computeMatch(input({ rank = 1 }), Economy)
			local fourth = Rewards.computeMatch(input({ rank = 4 }), Economy)
			t.expect(first.total).toBeGreaterThan(fourth.total)
			t.expect(first.breakdown.placement).toBe(Economy.Placement[1])
			t.expect(fourth.breakdown.placement).toBe(Economy.Placement.Others)
		end)

		t.it("récompense l'équipe gagnante plus que la perdante", function()
			local win = Rewards.computeMatch(input({ mode = "Teams", rank = nil, teamResult = "Win" }), Economy)
			local lose = Rewards.computeMatch(input({ mode = "Teams", rank = nil, teamResult = "Lose" }), Economy)
			t.expect(win.total).toBeGreaterThan(lose.total)
		end)

		t.it("plafonne les bonus de performance et le total", function()
			local reward = Rewards.computeMatch(input({ holeCount = 18, activeHoles = 18, holesFinished = 18, holeInOnes = 10, eagles = 10, birdies = 10 }), Economy)
			t.expect(reward.breakdown.performance).toBe(Economy.PerformanceCap)
			t.expect(reward.total).toBeLessThanOrEqual(Economy.MatchCap)
		end)

		t.it("retourne toujours un entier positif ou nul, même avec des entrées invalides", function()
			local reward = Rewards.computeMatch(input({ holesFinished = 0 / 0, birdies = -5, eagles = math.huge }), Economy)
			t.expect(reward.total).toBeGreaterThanOrEqual(0)
			t.expect(math.floor(reward.total)).toBe(reward.total)
		end)
	end)
end
