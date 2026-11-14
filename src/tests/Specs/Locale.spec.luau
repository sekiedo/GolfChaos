--!strict
-- Intégration : les textes sont centralisés et traduits (français complet, anglais aligné).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locale = require(ReplicatedStorage.Shared.Locale)

return function(t)
	t.describe("Locale", function()
		t.it("retourne le texte français par défaut et interpole les variables", function()
			t.expect(Locale.getLanguage()).toBe("fr")
			t.expect(Locale.t("core.seconds", { n = 5 })).toBe("5 s")
		end)

		t.it("retombe sur la clé pour un texte inconnu (et le signale)", function()
			local key = "test.cle.inexistante.xyz"
			t.expect(Locale.t(key)).toBe(key)
			t.expect(Locale.missingKeys()).toContain(key)
		end)

		t.it("traduit chaque raison de refus de la boutique (CosmeticService)", function()
			local reasons = {
				"profile", "unknown", "owned", "notOwned", "coins", "locked", "slot", "variant", "emotesFull", "loadout",
				"emptyLoadout",
			}
			for _, reason in reasons do
				local key = "shop.err." .. reason
				t.expect(Locale.has(key, "fr")).toBe(true)
				t.expect(Locale.has(key, "en")).toBe(true)
			end
		end)

		t.it("a une traduction anglaise pour chaque clé française", function()
			local untranslated = Locale.untranslatedKeys("en")
			if #untranslated > 0 then
				local sample = {}
				for index = 1, math.min(10, #untranslated) do
					sample[index] = untranslated[index]
				end
				error(string.format("%d clé(s) sans anglais, ex. : %s", #untranslated, table.concat(sample, ", ")))
			end
		end)

		t.it("garde les mêmes variables dans les deux langues", function()
			local problems = {}
			-- Comparaison des noms de variables {x} entre fr et en pour chaque clé commune.
			local frFolder = ReplicatedStorage.Shared.Locale:FindFirstChild("fr")
			local enFolder = ReplicatedStorage.Shared.Locale:FindFirstChild("en")
			if not frFolder or not enFolder then
				return
			end
			local function collect(folder: Instance): { [string]: string }
				local merged = {}
				for _, module in folder:GetChildren() do
					if module:IsA("ModuleScript") then
						local ok, entries = pcall(require, module)
						if ok and type(entries) == "table" then
							for key, text in entries :: { [string]: string } do
								merged[key] = text
							end
						end
					end
				end
				return merged
			end
			local function vars(text: string): { [string]: boolean }
				local set = {}
				for name in string.gmatch(text, "{(%w+)}") do
					set[name] = true
				end
				return set
			end
			local fr, en = collect(frFolder), collect(enFolder)
			for key, frText in fr do
				local enText = en[key]
				if type(frText) == "string" and type(enText) == "string" then
					local a, b = vars(frText), vars(enText)
					for name in a do
						if not b[name] then
							table.insert(problems, key .. " ({" .. name .. "} absent en anglais)")
						end
					end
				end
			end
			if #problems > 0 then
				error(table.concat(problems, " ; "))
			end
		end)
	end)
end
