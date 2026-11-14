--!strict
-- Intégration : catalogue de cosmétiques complet, construisible, et sans effet physique (équité).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Locale = require(ReplicatedStorage.Shared.Locale)

-- Effectifs minimaux exigés (hors objets gratuits par défaut, sauf pour Head qui n'en a pas).
local REQUIRED = { Head = 25, Face = 15, Outfit = 20, Shoes = 10, Club = 15, Ball = 10, HoleEffect = 5, Emote = 8 }

local function checkSafe(root: Instance, id: string)
	local list = root:GetDescendants()
	table.insert(list, root)
	for _, item in list do
		if item:IsA("BasePart") then
			if not item.Massless or item.CanCollide or item.CanQuery or item.CanTouch or item.Anchored then
				error(string.format("%s : pièce %s non conforme (Massless=%s CanCollide=%s CanQuery=%s CanTouch=%s Anchored=%s)",
					id, item:GetFullName(), tostring(item.Massless), tostring(item.CanCollide), tostring(item.CanQuery),
					tostring(item.CanTouch), tostring(item.Anchored)))
			end
		elseif item:IsA("Script") or item:IsA("LocalScript") then
			error(id .. " : un cosmétique ne doit contenir aucun script")
		end
	end
end

return function(t)
	t.describe("Catalogue de cosmétiques", function()
		t.it("est structurellement valide", function()
			local errors = Cosmetics.validate()
			if #errors > 0 then
				error(table.concat(errors, " ; "))
			end
		end)

		t.it("atteint les effectifs exigés par emplacement (hors objets par défaut)", function()
			local problems = {}
			for slot, required in REQUIRED do
				local count = 0
				for _, def in Cosmetics.bySlot(slot :: any) do
					if def.unlock.kind ~= "Default" or slot == "Emote" then
						count += 1
					end
				end
				if count < required then
					table.insert(problems, string.format("%s : %d/%d", slot, count, required))
				end
			end
			if #problems > 0 then
				error("effectifs insuffisants : " .. table.concat(problems, ", "))
			end
		end)

		t.it("a un nom traduit (fr et en) pour chaque cosmétique", function()
			local missing = {}
			for _, def in Cosmetics.all() do
				if not Locale.has(def.nameKey, "fr") or not Locale.has(def.nameKey, "en") then
					table.insert(missing, def.id)
				end
			end
			if #missing > 0 then
				error(string.format("%d nom(s) manquant(s) : %s", #missing, table.concat(missing, ", ", 1, math.min(#missing, 10))))
			end
		end)

		t.it("a une description et des noms de variantes traduits (fr et en)", function()
			local missing = {}
			local function check(key: any)
				if type(key) == "string" and (not Locale.has(key, "fr") or not Locale.has(key, "en")) then
					table.insert(missing, key)
				end
			end
			for _, def in Cosmetics.all() do
				check((def :: any).descKey)
				for _, variant in (def :: any).variants or {} do
					check(variant.nameKey)
				end
			end
			if #missing > 0 then
				error(string.format("%d texte(s) manquant(s) : %s", #missing, table.concat(missing, ", ", 1, math.min(#missing, 10))))
			end
		end)

		t.it("construit chaque modèle sans erreur et sans effet physique", function()
			local holder = Instance.new("Folder")
			local failures = {}
			for _, def in Cosmetics.all() do
				local ok, err = pcall(function()
					local variantCount = if def.variants then #def.variants else 1
					for variant = 1, math.max(1, variantCount) do
						if def.build then
							local model = def.build(variant)
							assert(typeof(model) == "Instance", "build doit retourner une Instance")
							if def.slot == "Head" or def.slot == "Face" then
								assert(model:IsA("Accessory"), "Head/Face doit retourner un Accessory")
								assert(model:FindFirstChild("Handle"), "Accessory sans Handle")
							elseif def.slot == "Outfit" or def.slot == "Shoes" then
								assert(model:IsA("Folder"), def.slot .. " doit retourner un Folder")
								for _, child in model:GetChildren() do
									assert(child:IsA("Accessory"), def.slot .. " : enfant non Accessory " .. child.Name)
								end
							elseif def.slot == "Club" then
								assert(model:IsA("Model"), "Club doit retourner un Model")
								local handle = model:FindFirstChild("Handle")
								assert(handle and handle:FindFirstChild("Grip"), "Club sans Handle.Grip")
							end
							model.Parent = holder
							checkSafe(model, def.id)
						elseif def.decorate then
							local visual = Instance.new("Part")
							visual.Shape = Enum.PartType.Ball
							visual.Size = Vector3.new(1.2, 1.2, 1.2)
							visual.Anchored = false
							visual.CanCollide = false
							visual.Parent = holder
							local decoration = def.decorate(visual, variant)
							if decoration then
								checkSafe(decoration, def.id)
							end
						end
					end
				end)
				if not ok then
					table.insert(failures, def.id .. " : " .. tostring(err))
				end
			end
			holder:Destroy()
			if #failures > 0 then
				error(string.format("%d échec(s) : %s", #failures, table.concat(failures, " | ", 1, math.min(#failures, 8))))
			end
		end)

		t.it("garde la même longueur de club pour tous les skins (même portée)", function()
			local lengths = {}
			for _, def in Cosmetics.bySlot("Club") do
				if def.build then
					local model = def.build(1) :: Model
					local _, size = model:GetBoundingBox()
					table.insert(lengths, { id = def.id, length = math.max(size.X, size.Y, size.Z) })
					model:Destroy()
				end
			end
			for _, entry in lengths do
				if entry.length > 4.6 or entry.length < 2.6 then
					error(string.format("%s : longueur %.2f hors de [2.6, 4.6]", entry.id, entry.length))
				end
			end
		end)
	end)
end
