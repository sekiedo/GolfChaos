--!strict
-- Données des trous (Data/Holes) et validateur pur (Logic/HoleValidator) : chaque trou agrégé passe la validation,
-- identifiants uniques, biomes Training et Coast présents, textes localisés, cohérence avec Props.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Holes = require(Shared.Data.Holes)
local HoleValidator = require(Shared.Logic.HoleValidator)
local Course = require(Shared.Config.Course)
local Locale = require(Shared.Locale)

local V = Vector3.new

-- Trou minimal valide servant de base aux tests négatifs.
local function baseHole(): any
	return {
		id = "TST-01",
		name = "Test",
		biome = "Coast",
		par = 3,
		difficulty = 1,
		targetTime = 60,
		feature = "test",
		seed = 1,
		path = {
			{ p = V(0, 0, 0) },
			{ p = V(0, 0, 80) },
			{ p = V(0, 0, 150) },
		},
		cup = V(0, 0, 154),
	}
end

local function withId(def: any, id: string): any
	def.id = id
	return def
end

local function hasError(result: HoleValidator.Result, pattern: string): boolean
	for _, message in result.errors do
		if string.find(message, pattern, 1, true) then
			return true
		end
	end
	return false
end

return function(t)
	t.describe("Agrégateur Data/Holes", function()
		t.it("charge les biomes Training et Coast", function()
			t.expect(#Holes.byBiome("Training") >= 3).toBe(true)
			t.expect(#Holes.byBiome("Coast") >= 6).toBe(true)
			t.expect(Holes.get("ENT-01")).notToBeNil()
			t.expect(Holes.get("ENT-02")).notToBeNil()
			t.expect(Holes.get("ENT-03")).notToBeNil()
			for index = 1, 6 do
				t.expect(Holes.get(string.format("COT-%02d", index))).notToBeNil()
			end
			t.expect(Holes.get("XXX-99")).toBeNil()
		end)

		t.it("ids() et count() suivent all(), dans un ordre stable (biome puis id)", function()
			local all = Holes.all()
			local ids = Holes.ids()
			t.expect(#ids).toBe(#all)
			t.expect(Holes.count()).toBe(#all)
			local biomeRank: { [string]: number } = {}
			for rank, biome in Course.BiomeOrder do
				biomeRank[biome] = rank
			end
			for index = 2, #all do
				local a, b = all[index - 1], all[index]
				local ra, rb = biomeRank[a.biome] or 99, biomeRank[b.biome] or 99
				t.expect(ra < rb or (ra == rb and a.id < b.id)).toBe(true)
			end
		end)
	end)

	t.describe("Validation de tous les trous", function()
		t.it("aucun trou n'a d'erreur de validation", function()
			local summary = HoleValidator.validateAll(Holes.all())
			local errors = {}
			for _, message in summary.messages do
				if string.find(message, "ERREUR", 1, true) then
					table.insert(errors, message)
				end
			end
			if #errors > 0 then
				error(table.concat(errors, "\n"))
			end
			t.expect(summary.ok).toBe(true)
		end)

		t.it("les identifiants sont uniques", function()
			local summary = HoleValidator.validateAll(Holes.all())
			t.expect(#summary.duplicates).toBe(0)
			local seen: { [string]: boolean } = {}
			for _, def in Holes.all() do
				t.expect(seen[def.id]).toBeNil()
				seen[def.id] = true
			end
		end)

		t.it("chaque trou Training et Coast a son nom et sa particularité en français et en anglais", function()
			local missing = {}
			for _, biome in { "Training", "Coast" } do
				for _, def in Holes.byBiome(biome) do
					for _, suffix in { "name", "feature" } do
						local key = string.format("hole.%s.%s", def.id, suffix)
						if not Locale.has(key, "fr") or not Locale.has(key, "en") then
							table.insert(missing, key)
						end
					end
				end
			end
			if #missing > 0 then
				error("clés manquantes : " .. table.concat(missing, ", "))
			end
		end)

		t.it("la longueur des trous de référence respecte la plage de leur par", function()
			for _, def in Holes.byBiome("Coast") do
				local range = Course.Validation.ParLength[def.par]
				local length = HoleValidator.validate(def).metrics.pathLength
				t.expect(length >= range[1] and length <= range[2]).toBe(true)
			end
		end)
	end)

	t.describe("HoleValidator (règles)", function()
		t.it("accepte le trou minimal", function()
			local result = HoleValidator.validate(withId(baseHole(), "COT-99"))
			if not result.ok then
				error(table.concat(result.errors, "\n"))
			end
			t.expect(result.metrics.nodeCount).toBe(3)
			t.expect(result.metrics.pathLength).toBeCloseTo(150, 0.01)
		end)

		t.it("refuse un préfixe d'identifiant inconnu ou incohérent avec le biome", function()
			t.expect(hasError(HoleValidator.validate(withId(baseHole(), "ZZZ-01")), "préfixe inconnu")).toBe(true)
			t.expect(hasError(HoleValidator.validate(withId(baseHole(), "FOR-01")), "impose le biome")).toBe(true)
			t.expect(hasError(HoleValidator.validate(withId(baseHole(), "COT-1")), "format attendu")).toBe(true)
		end)

		t.it("refuse une pente supérieure à 30°", function()
			local def = withId(baseHole(), "COT-98")
			def.path[2].p = V(0, 60, 80)
			t.expect(hasError(HoleValidator.validate(def), "pente")).toBe(true)
		end)

		t.it("refuse un trou (gap) de plus de 6 studs et accepte 5 studs", function()
			local def = withId(baseHole(), "COT-97")
			def.path = {
				{ p = V(0, 0, 0) },
				{ p = V(0, 0, 60), kind = "gap" },
				{ p = V(0, 0, 70) },
				{ p = V(0, 0, 150) },
			}
			local result = HoleValidator.validate(def)
			t.expect(hasError(result, "trou de")).toBe(true)
			t.expect(result.metrics.maxGap).toBeCloseTo(10, 0.01)
			def.path[3].p = V(0, 0, 65)
			t.expect(hasError(HoleValidator.validate(def), "trou de")).toBe(false)
		end)

		t.it("refuse un trou hors du green et un green trop incliné", function()
			local def = withId(baseHole(), "COT-96")
			def.cup = V(0, 0, 170)
			t.expect(hasError(HoleValidator.validate(def), "centre du green")).toBe(true)
			def.cup = V(0, 0, 154)
			def.green = { radius = 14, tilt = V(5, 0, 0) }
			t.expect(hasError(HoleValidator.validate(def), "incliné")).toBe(true)
		end)

		t.it("refuse un type d'obstacle ou d'accessoire inconnu", function()
			local def = withId(baseHole(), "COT-95")
			def.obstacles = { { kind = "dragon", center = V(0, 1, 50) } }
			def.props = { { kind = "volcano", position = V(10, 0, 50) } }
			local result = HoleValidator.validate(def)
			t.expect(hasError(result, "type inconnu \"dragon\"")).toBe(true)
			t.expect(hasError(result, "props[1]")).toBe(true)
		end)

		t.it("refuse un danger qui recouvre le départ ou le trou", function()
			local def = withId(baseHole(), "COT-94")
			def.hazards = { { kind = "water", center = V(0, 0, 0), size = V(10, 2, 10) } }
			t.expect(hasError(HoleValidator.validate(def), "recouvre le départ")).toBe(true)
			def.hazards = { { kind = "lava", shape = "cylinder", center = V(0, 0, 154), size = V(6, 2, 6) } }
			t.expect(hasError(HoleValidator.validate(def), "recouvre le trou")).toBe(true)
		end)

		t.it("refuse des bornes qui ne contiennent pas le chemin et un pont trop étroit", function()
			local def = withId(baseHole(), "COT-93")
			def.bounds = { min = V(-50, -50, -10), max = V(50, 50, 100) }
			t.expect(hasError(HoleValidator.validate(def), "bounds ne contiennent pas")).toBe(true)
			def.bounds = nil
			def.path[2].kind = "bridge"
			def.path[2].w = 4
			t.expect(hasError(HoleValidator.validate(def), "bridge trop étroit")).toBe(true)
		end)

		t.it("signale les doublons dans validateAll", function()
			local summary = HoleValidator.validateAll({ withId(baseHole(), "COT-92"), withId(baseHole(), "COT-92") })
			t.expect(#summary.duplicates).toBe(1)
			t.expect(summary.ok).toBe(false)
		end)

		t.it("pointAtDistance et distanceToPath sont cohérents", function()
			local def = baseHole()
			local point, dir = HoleValidator.pointAtDistance(def.path, 100)
			t.expect(point.Z).toBeCloseTo(100, 0.001)
			t.expect(dir.Z).toBeCloseTo(1, 0.001)
			local distance, segment, _, along = HoleValidator.distanceToPath(def.path, V(5, 0, 120))
			t.expect(distance).toBeCloseTo(5, 0.001)
			t.expect(segment).toBe(2)
			t.expect(along).toBeCloseTo(120, 0.001)
		end)
	end)

	t.describe("Cohérence avec les accessoires (serveur)", function()
		t.it("Config/Course.PropKinds correspond exactement à Props.kinds()", function()
			local server = ServerScriptService:FindFirstChild("Server")
			local courseFolder = server and server:FindFirstChild("Course")
			local module = courseFolder and courseFolder:FindFirstChild("Props")
			if module == nil or not module:IsA("ModuleScript") then
				return -- module serveur absent (exécution hors place construite) : test sans objet
			end
			local Props = require(module) :: any
			local kinds = Props.kinds()
			local expected: { [string]: boolean } = {}
			for _, kind in Course.PropKinds do
				expected[kind] = true
			end
			t.expect(#kinds).toBe(#Course.PropKinds)
			for _, kind in kinds do
				t.expect(expected[kind]).toBe(true)
			end
			t.expect(#kinds >= 20).toBe(true)
		end)
	end)
end
