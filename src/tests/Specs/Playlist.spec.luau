--!strict
-- Playlists (Logic.Playlist + Config.Match.Playlists) : tailles, ordre du catalogue, biomes, mélange
-- reproductible, sélection personnalisée, replis (docs/REGLES_SCORE.md §12). Données de trous synthétiques :
-- le test ne dépend pas du contenu réel de Data/Holes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Playlist = require(Shared.Logic.Playlist)
local ConfigMatch = require(Shared.Config.Match)

local function hole(id: string, biome: string): any
	return { id = id, biome = biome }
end

-- 13 trous de parcours (Côte 5, Forêt 5, Désert 3) + 3 trous d'entraînement, volontairement dans le désordre.
local CATALOG = {
	hole("FOR-03", "Forest"),
	hole("COT-02", "Coast"),
	hole("ENT-01", "Training"),
	hole("DES-01", "Desert"),
	hole("COT-01", "Coast"),
	hole("FOR-01", "Forest"),
	hole("COT-05", "Coast"),
	hole("FOR-02", "Forest"),
	hole("ENT-02", "Training"),
	hole("COT-03", "Coast"),
	hole("DES-03", "Desert"),
	hole("FOR-05", "Forest"),
	hole("COT-04", "Coast"),
	hole("DES-02", "Desert"),
	hole("FOR-04", "Forest"),
	hole("ENT-03", "Training"),
}

local TRAINING_ONLY = { hole("ENT-01", "Training"), hole("ENT-02", "Training"), hole("ENT-03", "Training") }

local function settings(overrides: { [string]: any }?): any
	local base: { [string]: any } = table.clone(ConfigMatch.DefaultSettings) :: any
	base.shuffle = false
	if overrides then
		for key, value in overrides do
			base[key] = value
		end
	end
	return base
end

local function hasTraining(ids: { string }): boolean
	for _, id in ids do
		if string.sub(id, 1, 3) == "ENT" then
			return true
		end
	end
	return false
end

local function sorted(list: { string }): { string }
	local copy = table.clone(list)
	table.sort(copy)
	return copy
end

return function(t)
	t.describe("Noms de playlists", function()
		t.it("analyse les noms simples et les biomes", function()
			local kind, biome = Playlist.parse("Biome:Coast")
			t.expect(kind).toBe("Biome")
			t.expect(biome).toBe("Coast")
			t.expect((Playlist.parse("Quick3"))).toBe("Quick3")
			t.expect((Playlist.parse("Mixed"))).toBe("Mixed")
			t.expect((Playlist.parse("Custom"))).toBe("Custom")
			t.expect((Playlist.parse("Biome:Mars"))).toBeNil()
			t.expect((Playlist.parse("quick3"))).toBeNil()
			t.expect((Playlist.parse(nil))).toBeNil()
			t.expect(Playlist.isValidName("Full18")).toBe(true)
			t.expect(Playlist.isValidName("Biome:")).toBe(false)
		end)

		t.it("calcule la taille demandée", function()
			t.expect(Playlist.requestedCount(settings({ playlist = "Quick3" }))).toBe(3)
			t.expect(Playlist.requestedCount(settings({ playlist = "Front9" }))).toBe(9)
			t.expect(Playlist.requestedCount(settings({ playlist = "Full18" }))).toBe(18)
			t.expect(Playlist.requestedCount(settings({ playlist = "Mixed", holeCount = 7 }))).toBe(7)
			t.expect(Playlist.requestedCount(settings({ playlist = "Mixed", holeCount = 99 }))).toBe(18)
			t.expect(Playlist.requestedCount(settings({ playlist = "Custom", customHoleIds = { "A", "B", "C", "D" } }))).toBe(4)
		end)
	end)

	t.describe("Playlists fixes", function()
		t.it("Quick3 prend les 3 premiers trous du parcours (ordre du catalogue)", function()
			local result = Playlist.build(settings({ playlist = "Quick3" }), CATALOG, 1)
			t.expect(result.holeIds).toEqual({ "COT-01", "COT-02", "COT-03" })
			t.expect(result.kind).toBe("Quick3")
			t.expect(result.fallback).toBeNil()
		end)

		t.it("Front9 enchaîne les biomes dans l'ordre du parcours", function()
			local result = Playlist.build(settings({ playlist = "Front9" }), CATALOG, 1)
			t.expect(result.holeIds).toEqual({
				"COT-01",
				"COT-02",
				"COT-03",
				"COT-04",
				"COT-05",
				"FOR-01",
				"FOR-02",
				"FOR-03",
				"FOR-04",
			})
		end)

		t.it("Full18 se replie sur tous les trous disponibles", function()
			local result = Playlist.build(settings({ playlist = "Full18" }), CATALOG, 1)
			t.expect(#result.holeIds).toBe(13)
			t.expect(result.requested).toBe(18)
			t.expect(result.fallback).toBe("fewerHoles")
		end)

		t.it("respecte le filtre de biomes", function()
			local result = Playlist.build(settings({ playlist = "Quick3", biomes = { "Desert" } }), CATALOG, 1)
			t.expect(result.holeIds).toEqual({ "DES-01", "DES-02", "DES-03" })
		end)

		t.it("n'inclut jamais de trou d'entraînement", function()
			for _, name in { "Quick3", "Front9", "Full18", "Mixed" } do
				local result = Playlist.build(settings({ playlist = name, holeCount = 18 }), CATALOG, 7)
				t.expect(hasTraining(result.holeIds)).toBe(false)
			end
		end)
	end)

	t.describe("Biome et mélange", function()
		t.it("Biome:<Biome> prend holeCount trous du biome", function()
			local result = Playlist.build(settings({ playlist = "Biome:Forest", holeCount = 2 }), CATALOG, 1)
			t.expect(result.holeIds).toEqual({ "FOR-01", "FOR-02" })
			t.expect(result.kind).toBe("Biome")
			t.expect(result.biome).toBe("Forest")
		end)

		t.it("un biome sans trou se replie sur le parcours", function()
			local result = Playlist.build(settings({ playlist = "Biome:Snow", holeCount = 2 }), CATALOG, 1)
			t.expect(result.fallback).toBe("biomeEmpty")
			t.expect(result.holeIds).toEqual({ "COT-01", "COT-02" })
		end)

		t.it("Mixed alterne les biomes demandés", function()
			local result = Playlist.build(
				settings({ playlist = "Mixed", holeCount = 4, biomes = { "Coast", "Forest" } }),
				CATALOG,
				1
			)
			t.expect(result.holeIds).toEqual({ "COT-01", "FOR-01", "COT-02", "FOR-02" })
		end)

		t.it("le mélange est reproductible avec la même graine", function()
			local a = Playlist.build(settings({ playlist = "Front9", shuffle = true }), CATALOG, 42)
			local b = Playlist.build(settings({ playlist = "Front9", shuffle = true }), CATALOG, 42)
			t.expect(a.holeIds).toEqual(b.holeIds)
			t.expect(#a.holeIds).toBe(9)
			t.expect(a.seed).toBe(42)
		end)

		t.it("le mélange ne garde que des trous uniques du pool", function()
			local result = Playlist.build(settings({ playlist = "Full18", shuffle = true }), CATALOG, 5)
			local seen: { [string]: boolean } = {}
			for _, id in result.holeIds do
				t.expect(seen[id]).toBeNil()
				seen[id] = true
			end
			t.expect(#result.holeIds).toBe(13)
		end)
	end)

	t.describe("Sélection personnalisée", function()
		t.it("garde l'ordre de l'hôte et ignore inconnus et doublons", function()
			local result = Playlist.build(
				settings({ playlist = "Custom", customHoleIds = { "FOR-02", "COT-01", "FOR-02", "XXX" } }),
				CATALOG,
				1
			)
			t.expect(result.holeIds).toEqual({ "FOR-02", "COT-01" })
			t.expect(result.kind).toBe("Custom")
			t.expect(sorted(result.invalidIds)).toEqual({ "FOR-02", "XXX" })
		end)

		t.it("une sélection vide se replie sur une partie rapide", function()
			local result = Playlist.build(settings({ playlist = "Custom", customHoleIds = {} }), CATALOG, 1)
			t.expect(result.fallback).toBe("customInvalid")
			t.expect(result.kind).toBe("Quick3")
			t.expect(result.holeIds).toEqual({ "COT-01", "COT-02", "COT-03" })
		end)

		t.it("borne une liste envoyée par un client", function()
			local known: { [string]: boolean } = {}
			local huge: { string } = {}
			for index = 1, 100 do
				local id = string.format("H-%03d", index)
				known[id] = true
				table.insert(huge, id)
			end
			local clean = Playlist.sanitizeCustom(huge, known, 18)
			t.expect(#clean).toBe(18)
			local tooLong = Playlist.sanitizeCustom({ string.rep("x", 200) }, { [string.rep("x", 200)] = true }, 18)
			t.expect(#tooLong).toBe(0)
			local notTable = Playlist.sanitizeCustom("COT-01", known, 18)
			t.expect(#notTable).toBe(0)
		end)
	end)

	t.describe("Replis", function()
		t.it("un nom inconnu devient Quick3", function()
			local result = Playlist.build(settings({ playlist = "Nope" }), CATALOG, 1)
			t.expect(result.fallback).toBe("invalidPlaylist")
			t.expect(result.kind).toBe("Quick3")
			t.expect(#result.holeIds).toBe(3)
		end)

		t.it("sans trou de parcours, utilise les trous d'entraînement", function()
			local result = Playlist.build(settings({ playlist = "Quick3" }), TRAINING_ONLY, 1)
			t.expect(result.fallback).toBe("trainingOnly")
			t.expect(result.holeIds).toEqual({ "ENT-01", "ENT-02", "ENT-03" })
		end)

		t.it("sans aucun trou, renvoie une liste vide sans erreur", function()
			local result = Playlist.build(settings({ playlist = "Front9" }), {}, 1)
			t.expect(result.fallback).toBe("noHoles")
			t.expect(#result.holeIds).toBe(0)
		end)

		t.it("ignore les entrées invalides et les doublons des données", function()
			local holes = Playlist.dedupeHoles({
				hole("COT-01", "Coast"),
				hole("COT-01", "Forest"),
				{ id = 5, biome = "Coast" },
				"pas une table",
				{ id = "", biome = "Coast" },
				hole("FOR-01", "Forest"),
			} :: any)
			t.expect(#holes).toBe(2)
			t.expect(holes[1].biome).toBe("Coast")
		end)
	end)
end
