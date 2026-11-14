--!strict
-- Cosmetics.Status : état affiché par la Boutique / Personnaliser (pur) + textes des écrans de collection.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Cosmetics)
local Status = require(Shared.Cosmetics.Status)
local Locale = require(Shared.Locale)
local Achievements = require(Shared.Config.Achievements)

local function snap(overrides: { [string]: any }?): any
	local base = { coins = 0, owned = {}, equipped = {}, variants = {}, achievements = {}, stats = {} }
	for key, value in overrides or {} do
		base[key] = value
	end
	return base
end

local function firstPriced(slot: string): any
	for _, def in Cosmetics.bySlot(slot :: any) do
		if def.unlock.kind == "Price" and def.price > 0 then
			return def
		end
	end
	error("aucun cosmétique payant pour " .. slot)
end

return function(t)
	t.describe("Cosmetics.Status", function()
		t.it("un objet par défaut est possédé et équipé quand l'emplacement est vide", function()
			local def = Cosmetics.defaultFor("Ball")
			t.expect(def ~= nil).toBe(true)
			t.expect(Status.of(def, snap())).toBe("equipped")
		end)

		t.it("un objet payant : achetable avec assez de pièces, sinon « poor »", function()
			local def = firstPriced("Head")
			t.expect(Status.of(def, snap({ coins = 0 }))).toBe("poor")
			t.expect(Status.of(def, snap({ coins = def.price }))).toBe("buyable")
		end)

		t.it("possédé puis équipé", function()
			local def = firstPriced("Club")
			t.expect(Status.of(def, snap({ owned = { [def.id] = true } }))).toBe("owned")
			t.expect(Status.of(def, snap({ owned = { [def.id] = true }, equipped = { Club = def.id } }))).toBe("equipped")
		end)

		t.it("une émote est équipée si elle figure dans la liste", function()
			local emote = Cosmetics.bySlot("Emote")[1]
			t.expect(Status.isEquipped(emote, snap({ equipped = { Emotes = { emote.id } } }))).toBe(true)
			t.expect(Status.isEquipped(emote, snap({ equipped = { Emotes = {} } }))).toBe(false)
		end)

		t.it("un objet à condition reste verrouillé puis se débloque avec les statistiques", function()
			local locked
			for _, def in Cosmetics.all() do
				if def.unlock.kind == "Wins" then
					locked = def
					break
				end
			end
			t.expect(locked ~= nil).toBe(true)
			t.expect(Status.of(locked, snap({ coins = 99999 }))).toBe("locked")
			local info = Status.unlock(locked, snap({ stats = { matchesWon = locked.unlock.value } }))
			t.expect(info.unlocked).toBe(true)
			t.expect(Status.of(locked, snap({ coins = 99999, stats = { matchesWon = locked.unlock.value } })) ~= "locked").toBe(true)
		end)

		t.it("la variante choisie est bornée au nombre de variantes", function()
			local def
			for _, candidate in Cosmetics.all() do
				if candidate.variants and #candidate.variants > 1 then
					def = candidate
					break
				end
			end
			t.expect(def ~= nil).toBe(true)
			t.expect(Status.variantOf(def, snap())).toBe(1)
			t.expect(Status.variantOf(def, snap({ variants = { [def.id] = 2 } }))).toBe(2)
			t.expect(Status.variantOf(def, snap({ variants = { [def.id] = 999 } }))).toBe(1)
		end)
	end)

	t.describe("Textes des écrans de collection", function()
		local KEYS = {
			"shop.title", "shop.buy", "shop.equip", "shop.unequip", "shop.price", "shop.coins", "shop.empty",
			"shop.state.equipped", "shop.state.owned", "shop.state.poor", "shop.state.lockedShort",
			"shop.unlock.free", "shop.unlock.achievement", "shop.unlock.wins", "shop.unlock.holesInOne", "shop.unlock.matches",
			"shop.result.buy", "shop.result.equip", "shop.result.variant", "shop.result.saveLoadout", "shop.result.useLoadout",
			"customize.title", "customize.empty", "customize.colorN", "customize.useLoadout", "customize.saveLoadout",
			"customize.emotesCount", "challenges.title", "challenges.summary", "challenges.reward", "challenges.progress",
			"emotes.title", "emotes.hint", "emotes.empty", "emotes.stop", "emotes.customize", "menu.emotes",
		}
		t.it("existent en français et en anglais", function()
			for _, key in KEYS do
				t.expect(Locale.has(key, "fr")).toBe(true)
				t.expect(Locale.has(key, "en")).toBe(true)
			end
		end)

		t.it("couvrent chaque emplacement, rareté et catégorie de défi", function()
			for _, slot in { "Head", "Face", "Outfit", "Shoes", "Club", "Ball", "HoleEffect", "Emote" } do
				t.expect(Locale.has("shop.tab." .. slot, "fr")).toBe(true)
			end
			for _, rarity in Status.RARITY_ORDER do
				t.expect(Locale.has("shop.rarity." .. rarity, "fr")).toBe(true)
			end
			for _, def in Achievements.List do
				t.expect(Locale.has("challenges.cat." .. def.category, "fr")).toBe(true)
			end
		end)
	end)
end
