--!strict
-- Tests du localisateur de services serveur (Server.Util.Services).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Services = require((ServerScriptService :: any).Server.Util.Services)

return function(t: any)
	-- Dossier factice : des ModuleScripts vides, le chargeur injecté décide de ce que chacun « retourne ».
	local function fixture(results: { [string]: any }): any
		local folder = Instance.new("Folder")
		local loads: { [string]: number } = {}
		for name in results do
			local module = Instance.new("ModuleScript")
			module.Name = name
			module.Parent = folder
		end
		local decoy = Instance.new("Folder")
		decoy.Name = "PasUnModule"
		decoy.Parent = folder
		local time = 0
		local locator = Services.new({
			folder = folder,
			retryTime = 5,
			clock = function()
				return time
			end,
			loader = function(module: ModuleScript)
				loads[module.Name] = (loads[module.Name] or 0) + 1
				local result = results[module.Name]
				if result == "ERREUR" then
					error("module cassé")
				end
				return result
			end,
		})
		return {
			locator = locator,
			loads = loads,
			results = results,
			advance = function(seconds: number)
				time += seconds
			end,
			destroy = function()
				folder:Destroy()
			end,
		}
	end

	t.describe("Services.get", function()
		t.it("retourne la table du service et ne le charge qu'une fois", function()
			local service = { Priority = 1 }
			local f = fixture({ Alpha = service })
			t.expect(f.locator.get("Alpha")).toBe(service)
			t.expect(f.locator.get("Alpha")).toBe(service)
			t.expect(f.loads.Alpha).toBe(1)
			f.destroy()
		end)
		t.it("retourne nil pour un service absent, cassé, non-table ou qui n'est pas un ModuleScript", function()
			local f = fixture({ Casse = "ERREUR", Nombre = 42 })
			t.expect(f.locator.get("Inconnu")).toBeNil()
			t.expect(f.locator.get("Casse")).toBeNil()
			t.expect(f.locator.get("Nombre")).toBeNil()
			t.expect(f.locator.get("PasUnModule")).toBeNil()
			f.destroy()
		end)
		t.it("mémorise un échec puis réessaie après le délai", function()
			local f = fixture({ Tardif = "ERREUR" })
			t.expect(f.locator.get("Tardif")).toBeNil()
			f.advance(2)
			t.expect(f.locator.get("Tardif")).toBeNil()
			t.expect(f.loads.Tardif).toBe(1)
			f.results.Tardif = { ok = true }
			f.advance(4)
			t.expect(f.locator.get("Tardif")).notToBeNil()
			t.expect(f.loads.Tardif).toBe(2)
			f.destroy()
		end)
		t.it("reset vide le cache", function()
			local f = fixture({ Alpha = {} })
			f.locator.get("Alpha")
			f.locator.reset()
			f.locator.get("Alpha")
			t.expect(f.loads.Alpha).toBe(2)
			f.destroy()
		end)
	end)

	t.describe("Services.scope", function()
		t.it("call transmet les arguments et le résultat", function()
			local f = fixture({
				Alpha = {
					Add = function(a: number, b: number)
						return a + b
					end,
				},
			})
			local ok, result = f.locator.scope("Test").call("Alpha", "Add", 2, 3)
			t.expect(ok).toBe(true)
			t.expect(result).toBe(5)
			f.destroy()
		end)
		t.it("call retourne (false, nil) si le service, la méthode manque ou si l'appel échoue", function()
			local f = fixture({
				Alpha = {
					Boom = function()
						error("boum")
					end,
					PasUneFonction = 3,
				},
			})
			local services = f.locator.scope("Test")
			local ok1, r1 = services.call("Inconnu", "Add")
			local ok2, r2 = services.call("Alpha", "Absente")
			local ok3, r3 = services.call("Alpha", "PasUneFonction")
			local ok4, r4 = services.call("Alpha", "Boom")
			t.expect(ok1).toBe(false)
			t.expect(ok2).toBe(false)
			t.expect(ok3).toBe(false)
			t.expect(ok4).toBe(false)
			t.expect(r1).toBeNil()
			t.expect(r2).toBeNil()
			t.expect(r3).toBeNil()
			t.expect(r4).toBeNil()
			f.destroy()
		end)
		t.it("connect s'abonne à un signal et isole une erreur du gestionnaire", function()
			local changed = Signal.new()
			local f = fixture({ Alpha = { Changed = changed } })
			local services = f.locator.scope("Test")
			local received = nil
			t.expect(services.connect("Alpha", "Changed", function(value)
				received = value
			end)).toBe(true)
			t.expect(services.connect("Alpha", "Changed", function()
				error("gestionnaire cassé")
			end)).toBe(true)
			changed:Fire(7)
			t.expect(received).toBe(7)
			f.destroy()
		end)
		t.it("connect retourne false si le service ou le signal manque", function()
			local f = fixture({ Alpha = { PasUnSignal = 1 } })
			local services = f.locator.scope("Test")
			t.expect(services.connect("Inconnu", "Changed", function() end)).toBe(false)
			t.expect(services.connect("Alpha", "Absent", function() end)).toBe(false)
			t.expect(services.connect("Alpha", "PasUnSignal", function() end)).toBe(false)
			f.destroy()
		end)
	end)
end
