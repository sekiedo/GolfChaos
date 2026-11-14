--!strict
-- Registre des objets et tirage avec rattrapage (Config.Items, Config.ItemBoxes, Logic.ItemOdds).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local ItemOdds = require(Shared.Logic.ItemOdds)
local Locale = require(Shared.Locale)

local EXPECTED_IDS = {
	"horn", "espresso", "cork_pistol", "blunderbuss", "magnet_shield", "caddie_kart", "shroom_mine", "orbital_beam",
	"confetti_rocket", "kangaroo_boots", "rocket_club", "frost_bomb", "ninja_smoke", "paparazzi_flash",
	"grumpy_cloud", "rail_slinger", "mega_burger",
}

return function(t)
	t.describe("Registre des objets", function()
		t.it("contient exactement les 17 objets attendus, avec un ordre unique", function()
			t.expect(#Items.List).toBe(17)
			local orders = {}
			for _, id in EXPECTED_IDS do
				local def = Items.get(id)
				t.expect(def).notToBeNil()
				local order = (def :: any).order
				t.expect(orders[order]).toBeNil()
				orders[order] = true
			end
		end)

		t.it("renseigne tous les champs exigés pour chaque objet", function()
			for _, def in Items.List do
				local prefix = def.id .. " : "
				assert(type(def.rarity) == "string", prefix .. "rareté")
				assert(def.weightLeader >= 0 and def.weightLast >= 0, prefix .. "poids")
				assert(def.weightLeader + def.weightLast > 0, prefix .. "poids nuls")
				assert(type(def.range) == "number" and def.range >= 0, prefix .. "portée")
				assert(type(def.duration) == "number" and def.duration >= 0, prefix .. "durée")
				assert(type(def.charges) == "number" and def.charges >= 1, prefix .. "charges")
				assert(type(def.cooldown) == "number" and def.cooldown >= 0, prefix .. "délai")
				assert(type(def.targets) == "table" and #def.targets >= 1, prefix .. "catégories de cible")
				assert(type(def.shield) == "string", prefix .. "réaction au bouclier")
				assert(def.allyEffect == "None" or def.allyEffect == "Self", prefix .. "effet sur alliés")
				assert(type(def.cleanup) == "table", prefix .. "nettoyage")
				assert(type(def.counterKey) == "string", prefix .. "contre-jeu")
			end
		end)

		t.it("a des textes français et anglais pour chaque objet", function()
			for _, def in Items.List do
				for _, key in { def.nameKey, def.descKey, def.counterKey } do
					assert(Locale.has(key, "fr"), "fr manquant : " .. key)
					assert(Locale.has(key, "en"), "en manquant : " .. key)
				end
			end
		end)

		t.it("a une capacité d'inventaire initiale dans les bornes", function()
			t.expect(Items.InventoryCapacity).toBeGreaterThanOrEqual(Items.MinCapacity)
			t.expect(Items.InventoryCapacity).toBeLessThanOrEqual(Items.MaxCapacity)
		end)
	end)

	t.describe("Tirage avec rattrapage", function()
		t.it("calcule la position normalisée", function()
			t.expect(ItemOdds.normalizedPosition(1, 8)).toBe(0)
			t.expect(ItemOdds.normalizedPosition(8, 8)).toBe(1)
			t.expect(ItemOdds.normalizedPosition(1, 1)).toBe(0.5)
		end)

		t.it("donne des probabilités qui somment à 1", function()
			for _, position in { 0, 0.5, 1 } do
				local sum = 0
				for _, p in ItemOdds.probabilities(Items.List, position, 1, "Random") do
					sum += p
				end
				t.expect(sum).toBeCloseTo(1, 1e-9)
			end
		end)

		t.it("favorise les attaques majeures pour les derniers et les réduit pour le meneur", function()
			local leader = ItemOdds.probabilities(Items.List, 0, 1, "Random")
			local last = ItemOdds.probabilities(Items.List, 1, 1, "Random")
			for _, id in { "orbital_beam", "rail_slinger", "mega_burger", "grumpy_cloud" } do
				t.expect(last[id]).toBeGreaterThan(leader[id])
			end
		end)

		t.it("n'applique aucun rattrapage quand la force est nulle", function()
			local a = ItemOdds.probabilities(Items.List, 0, 0, "Random")
			local b = ItemOdds.probabilities(Items.List, 1, 0, "Random")
			for id, p in a do
				t.expect(b[id]).toBeCloseTo(p, 1e-9)
			end
		end)

		t.it("ne sort que des objets de mobilité d'une boîte de mobilité", function()
			local probs = ItemOdds.probabilities(Items.List, 0.5, 1, "Mobility")
			local count = 0
			for id in probs do
				count += 1
				t.expect((Items.get(id) :: any).mobilityBox).toBe(true)
			end
			t.expect(count).toBe(4)
		end)

		t.it("est reproductible avec une graine et suit la distribution attendue", function()
			local rngA, rngB = Random.new(1234), Random.new(1234)
			for _ = 1, 50 do
				t.expect(ItemOdds.roll(Items.List, rngA, 0.3, 1, "Random")).toBe(ItemOdds.roll(Items.List, rngB, 0.3, 1, "Random"))
			end
			local rng = Random.new(42)
			local counts: { [string]: number } = {}
			local samples = 20000
			for _ = 1, samples do
				local id = ItemOdds.roll(Items.List, rng, 1, 1, "Random") :: string
				counts[id] = (counts[id] or 0) + 1
			end
			for id, p in ItemOdds.probabilities(Items.List, 1, 1, "Random") do
				local observed = (counts[id] or 0) / samples
				t.expect(math.abs(observed - p)).toBeLessThan(0.015)
			end
		end)

		t.it("respecte la liste d'exclusion", function()
			local rng = Random.new(7)
			for _ = 1, 200 do
				local id = ItemOdds.roll(Items.List, rng, 0.5, 1, "Random", { horn = true, espresso = true })
				t.expect(id).notToBe("horn")
				t.expect(id).notToBe("espresso")
			end
		end)
	end)
end
