--!strict
-- Sauvegarde : Migrations, MemoryAdapter et ProfileStore (verrou de session). Aucun accès au DataStore réel.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local dataFolder = (ServerScriptService :: any).Server.Data
local Schema = require(dataFolder.Schema)
local Migrations = require(dataFolder.Migrations)
local MemoryAdapter = require(dataFolder.Adapters.MemoryAdapter)
local ProfileStore = require(dataFolder.ProfileStore)
local ProfileOps = require(dataFolder.ProfileOps)

return function(t: any)
	-- Deux « serveurs » (sessions A et B) partageant le même magasin en mémoire et la même horloge.
	local function world(failWith: ((string, string) -> string?)?): any
		local time = 1_000_000
		local service = MemoryAdapter.newService({ failWith = failWith })
		local function session(id: string)
			return ProfileStore.new({
				adapter = MemoryAdapter.new({ service = service, maxAttempts = 1 }),
				sessionId = id,
				jobId = "job-" .. id,
				lockExpiry = 300,
				now = function()
					return time
				end,
			})
		end
		return {
			a = session("A"),
			b = session("B"),
			advance = function(seconds: number)
				time += seconds
			end,
		}
	end

	t.describe("Migrations.upgrade", function()
		t.it("crée un profil neuf quand la clé n'existe pas", function()
			local profile, notes, err = Migrations.upgrade(nil, 100)
			t.expect(err).toBeNil()
			t.expect(#notes).toBe(0)
			t.expect(profile.version).toBe(Schema.CURRENT_VERSION)
			t.expect(profile.coins).toBe(Economy.StartingCoins)
		end)
		t.it("migre un profil sans version sans perdre ses données ni modifier l'original", function()
			local raw = { coins = 777, owned = { head_test = true } }
			local profile, notes, err = Migrations.upgrade(raw, 100)
			t.expect(err).toBeNil()
			t.expect(profile.version).toBe(Schema.CURRENT_VERSION)
			t.expect(profile.coins).toBe(777)
			t.expect(profile.owned.head_test).toBe(true)
			t.expect(#notes).toBeGreaterThan(0)
			t.expect((raw :: any).version).toBeNil()
		end)
		t.it("refuse une version future et une valeur qui n'est pas une table", function()
			local future, _, futureErr = Migrations.upgrade({ version = Schema.CURRENT_VERSION + 1, coins = 5 }, 100)
			t.expect(future).toBeNil()
			t.expect(futureErr).toBe("future_version")
			local invalid, _, invalidErr = Migrations.upgrade("abc", 100)
			t.expect(invalid).toBeNil()
			t.expect(invalidErr).toBe("invalid")
		end)
	end)

	t.describe("Schema.sanitize", function()
		t.it("garde les statistiques arbitraires, les ensembles et les événements des défis", function()
			local profile = Schema.defaultProfile(100)
			local raw: any = profile
			raw.stats.cartMeters = 1234.5
			raw.stats.statInventee = 7
			raw.sets.biomesFinished = { Coast = true, Forest = true }
			raw.events.tutorialDone = true
			local clean, repairs = Schema.sanitize(raw, 200)
			t.expect(#repairs).toBe(0)
			t.expect(clean.stats.cartMeters).toBe(1234.5)
			t.expect(clean.stats.statInventee).toBe(7)
			t.expect(clean.sets.biomesFinished.Forest).toBe(true)
			t.expect(clean.events.tutorialDone).toBe(true)
		end)
		t.it("est idempotent et répare un profil abîmé sans jeter ce qui est valide", function()
			local clean, repairs = Schema.sanitize({ version = 1, coins = -50, owned = { ok_item = true, [5] = true }, stats = { wins = 3 } }, 100)
			t.expect(#repairs).toBeGreaterThan(0)
			t.expect(clean.coins).toBeGreaterThanOrEqual(0)
			t.expect(clean.owned.ok_item).toBe(true)
			t.expect(clean.stats.wins).toBe(3)
			local _, again = Schema.sanitize(clean, 100)
			t.expect(#again).toBe(0)
		end)
	end)

	t.describe("ProfileOps", function()
		t.it("update travaille sur une copie et borne les pièces", function()
			local profile = Schema.defaultProfile(100)
			local ok, updated = ProfileOps.update(profile, function(data)
				data.coins = Economy.MaxCoins + 500.7
				data.owned.head_test = true
			end)
			t.expect(ok).toBe(true)
			t.expect(updated.coins).toBe(Economy.MaxCoins)
			t.expect(updated.owned.head_test).toBe(true)
			t.expect(profile.coins).toBe(Economy.StartingCoins)
			t.expect(profile.owned.head_test).toBeNil()
		end)
		t.it("update annule tout si la fonction renvoie false ou lève une erreur", function()
			local profile = Schema.defaultProfile(100)
			local okFalse, draftFalse, reason = ProfileOps.update(profile, function(data)
				data.coins = 1
				return false, "nope"
			end)
			t.expect(okFalse).toBe(false)
			t.expect(draftFalse).toBeNil()
			t.expect(reason).toBe("nope")
			local okError, draftError, errorReason = ProfileOps.update(profile, function(data)
				data.coins = 2
				error("boum")
			end)
			t.expect(okError).toBe(false)
			t.expect(draftError).toBeNil()
			t.expect(errorReason).toBe("error")
			t.expect(profile.coins).toBe(Economy.StartingCoins)
		end)
		t.it("transact applique une opération une seule fois", function()
			local profile = Schema.defaultProfile(100)
			local function pay(data: any): (boolean, string?)
				data.coins += 100
				return true, nil
			end
			local ok, paid = ProfileOps.transact(profile, "match:abc:1", pay)
			t.expect(ok).toBe(true)
			t.expect(paid.coins).toBe(Economy.StartingCoins + 100)
			t.expect(Schema.hasOp(paid, "match:abc:1")).toBe(true)
			t.expect(Schema.hasOp(profile, "match:abc:1")).toBe(false)
			local again, draft, reason = ProfileOps.transact(paid, "match:abc:1", pay)
			t.expect(again).toBe(false)
			t.expect(draft).toBeNil()
			t.expect(reason).toBe("duplicate")
		end)
		t.it("transact ne mémorise pas une opération refusée : elle peut réussir plus tard", function()
			local profile = Schema.defaultProfile(100)
			local reached = false
			local function claim(data: any): (boolean, string?)
				if not reached then
					return false, "not_reached"
				end
				data.coins += 50
				return true, nil
			end
			local first, _, reason = ProfileOps.transact(profile, "ach:test", claim)
			t.expect(first).toBe(false)
			t.expect(reason).toBe("not_reached")
			t.expect(Schema.hasOp(profile, "ach:test")).toBe(false)
			reached = true
			local second, claimed = ProfileOps.transact(profile, "ach:test", claim)
			t.expect(second).toBe(true)
			t.expect(claimed.coins).toBe(Economy.StartingCoins + 50)
		end)
		t.it("transact refuse un identifiant invalide et isole une erreur", function()
			local profile = Schema.defaultProfile(100)
			local function noop()
				return true
			end
			t.expect((ProfileOps.transact(profile, "", noop))).toBe(false)
			t.expect((ProfileOps.transact(profile, string.rep("x", Schema.Limits.MaxOpIdLength + 1), noop))).toBe(false)
			local ok, _, reason = ProfileOps.transact(profile, "op:1", function()
				error("boum")
			end)
			t.expect(ok).toBe(false)
			t.expect(reason).toBe("error")
		end)
	end)

	t.describe("MemoryAdapter", function()
		t.it("se déclare non persistant", function()
			local adapter = MemoryAdapter.new()
			t.expect(adapter.kind).toBe("Memory")
			t.expect(adapter.persistent).toBe(false)
		end)
		t.it("écrit, relit et isole les valeurs par copie", function()
			local adapter = MemoryAdapter.new()
			local value = { coins = 10, list = { 1, 2 } }
			local written = adapter:Update("k", function()
				return value, { 42 }, { tag = "x" }
			end)
			t.expect(written.ok).toBe(true)
			value.coins = 999
			local read = adapter:Get("k")
			t.expect(read.ok).toBe(true)
			t.expect(read.value.coins).toBe(10)
			t.expect(read.keyInfo.metadata.tag).toBe("x")
			t.expect(read.keyInfo.userIds[1]).toBe(42)
			read.value.coins = 5
			t.expect(adapter:Get("k").value.coins).toBe(10)
		end)
		t.it("une transformation qui renvoie nil n'écrit rien", function()
			local adapter = MemoryAdapter.new()
			local result = adapter:Update("k", function()
				return nil
			end)
			t.expect(result.ok).toBe(true)
			t.expect(result.aborted).toBe(true)
			t.expect(adapter:Get("k").value).toBeNil()
		end)
	end)

	t.describe("ProfileStore", function()
		t.it("charge un profil neuf, l'enregistre et le retrouve après libération", function()
			local w = world()
			local first = w.a:Load(1)
			t.expect(first.status).toBe("Loaded")
			t.expect(first.isNew).toBe(true)
			first.profile.coins = 1234
			local ok = w.a:Save(1, first.profile, { release = true })
			t.expect(ok).toBe(true)
			local second = w.b:Load(1)
			t.expect(second.status).toBe("Loaded")
			t.expect(second.isNew).toBe(false)
			t.expect(second.profile.coins).toBe(1234)
		end)
		t.it("refuse le chargement tant qu'un autre serveur tient le verrou", function()
			local w = world()
			t.expect(w.a:Load(1).status).toBe("Loaded")
			local blocked = w.b:Load(1)
			t.expect(blocked.status).toBe("Locked")
			t.expect(blocked.profile).toBeNil()
			-- La session propriétaire peut recharger son propre profil.
			t.expect(w.a:Load(1).status).toBe("Loaded")
		end)
		t.it("reprend un verrou expiré, et l'ancien propriétaire ne peut plus écrire", function()
			local w = world()
			local mine = w.a:Load(1)
			w.advance(301)
			local taken = w.b:Load(1)
			t.expect(taken.status).toBe("Loaded")
			mine.profile.coins = 999999
			local ok, reason = w.a:Save(1, mine.profile)
			t.expect(ok).toBe(false)
			t.expect(reason).toBe("lock_lost")
			taken.profile.coins = 42
			t.expect((w.b:Save(1, taken.profile, { release = true }))).toBe(true)
			w.advance(1)
			t.expect(w.a:Load(1).profile.coins).toBe(42)
		end)
		t.it("un enregistrement renouvelle le verrou", function()
			local w = world()
			local mine = w.a:Load(1)
			w.advance(200)
			t.expect((w.a:Save(1, mine.profile))).toBe(true)
			w.advance(200)
			t.expect(w.b:Load(1).status).toBe("Locked")
		end)
		t.it("Release rend le verrou sans modifier les données", function()
			local w = world()
			local mine = w.a:Load(1)
			mine.profile.coins = 555
			t.expect((w.a:Save(1, mine.profile))).toBe(true)
			t.expect(w.a:Release(1)).toBe(true)
			local other = w.b:Load(1)
			t.expect(other.status).toBe("Loaded")
			t.expect(other.profile.coins).toBe(555)
		end)
		t.it("un chargement en échec n'écrit rien et ne remplace jamais un profil existant", function()
			local failing = false
			local w = world(function(operation: string)
				return if failing and operation == "Update" then "502: API Services rejected request" else nil
			end)
			local mine = w.a:Load(1)
			mine.profile.coins = 4321
			t.expect((w.a:Save(1, mine.profile, { release = true }))).toBe(true)
			failing = true
			local failed = w.b:Load(1)
			t.expect(failed.status).toBe("Failed")
			t.expect(failed.profile).toBeNil()
			failing = false
			t.expect(w.b:Load(1).profile.coins).toBe(4321)
		end)
		t.it("refuse un profil d'une version future sans le modifier", function()
			local w = world()
			local service = MemoryAdapter.newService()
			local adapter = MemoryAdapter.new({ service = service })
			adapter:Update("Player_7", function()
				return { version = Schema.CURRENT_VERSION + 5, coins = 77 }, { 7 }, {}
			end)
			local futureStore = ProfileStore.new({ adapter = adapter, sessionId = "F" })
			local result = futureStore:Load(7)
			t.expect(result.status).toBe("Failed")
			t.expect(result.error).toBe("future_version")
			t.expect(adapter:Get("Player_7").value.coins).toBe(77)
			t.expect(w).notToBeNil()
		end)
	end)
end
