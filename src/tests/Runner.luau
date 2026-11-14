--!strict
--[[
	Mini-framework de tests unitaires exécuté DANS Roblox Studio (mode Édition ou serveur de test).

	  require(game.ServerStorage.Tests.Runner).run()             -- tous les fichiers Specs/*.spec
	  require(game.ServerStorage.Tests.Runner).run("Scoring")    -- seulement les specs dont le nom contient "Scoring"

	Un fichier Specs/Nom.spec.luau retourne une fonction recevant `t` :
	    return function(t)
	        t.describe("Barème", function()
	            t.it("donne 12 points au premier", function()
	                t.expect(Scoring.arrivalPoints(1, 8)).toBe(12)
	            end)
	        end)
	    end

	Matchers : toBe, notToBe, toEqual (profond), toBeCloseTo(v, eps?), toBeTruthy, toBeFalsy, toBeNil,
	           notToBeNil, toBeGreaterThan, toBeLessThan, toBeGreaterThanOrEqual, toBeLessThanOrEqual,
	           toContain (tableau ou sous-chaîne), toThrow (expect(fn).toThrow()), toHaveLength(n).
	run() retourne { passed, failed, total, failures = { { name, message } }, summary }.
	Chaque spec est chargée depuis un CLONE du ModuleScript : relancer les tests après modification
	ne réutilise jamais un résultat de require mis en cache.
]]

local Runner = {}

type Failure = { name: string, message: string }

local function deepEqual(a: any, b: any, seen: { [any]: any }?): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	local visited = seen or {}
	if visited[a] == b then
		return true
	end
	visited[a] = b
	for key, value in a do
		if not deepEqual(value, b[key], visited) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function show(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) == "table" then
		local parts = {}
		local count = 0
		for key, item in value do
			count += 1
			if count > 8 then
				table.insert(parts, "…")
				break
			end
			table.insert(parts, tostring(key) .. "=" .. tostring(item))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end

local function makeExpect()
	return function(actual: any)
		local m = {}
		local function fail(message: string)
			error(message, 3)
		end
		function m.toBe(expected: any)
			if actual ~= expected then
				fail(string.format("attendu %s, obtenu %s", show(expected), show(actual)))
			end
		end
		function m.notToBe(expected: any)
			if actual == expected then
				fail(string.format("ne devait pas valoir %s", show(expected)))
			end
		end
		function m.toEqual(expected: any)
			if not deepEqual(actual, expected) then
				fail(string.format("attendu %s, obtenu %s (comparaison profonde)", show(expected), show(actual)))
			end
		end
		function m.toBeCloseTo(expected: number, epsilon: number?)
			local eps = epsilon or 1e-6
			if type(actual) ~= "number" or math.abs(actual - expected) > eps then
				fail(string.format("attendu %s ± %s, obtenu %s", show(expected), show(eps), show(actual)))
			end
		end
		function m.toBeTruthy()
			if not actual then
				fail("attendu une valeur vraie, obtenu " .. show(actual))
			end
		end
		function m.toBeFalsy()
			if actual then
				fail("attendu une valeur fausse, obtenu " .. show(actual))
			end
		end
		function m.toBeNil()
			if actual ~= nil then
				fail("attendu nil, obtenu " .. show(actual))
			end
		end
		function m.notToBeNil()
			if actual == nil then
				fail("attendu une valeur non nil")
			end
		end
		function m.toBeGreaterThan(expected: number)
			if not (type(actual) == "number" and actual > expected) then
				fail(string.format("attendu > %s, obtenu %s", show(expected), show(actual)))
			end
		end
		function m.toBeLessThan(expected: number)
			if not (type(actual) == "number" and actual < expected) then
				fail(string.format("attendu < %s, obtenu %s", show(expected), show(actual)))
			end
		end
		function m.toBeGreaterThanOrEqual(expected: number)
			if not (type(actual) == "number" and actual >= expected) then
				fail(string.format("attendu >= %s, obtenu %s", show(expected), show(actual)))
			end
		end
		function m.toBeLessThanOrEqual(expected: number)
			if not (type(actual) == "number" and actual <= expected) then
				fail(string.format("attendu <= %s, obtenu %s", show(expected), show(actual)))
			end
		end
		function m.toContain(expected: any)
			if type(actual) == "string" then
				if not string.find(actual, tostring(expected), 1, true) then
					fail(string.format("%s ne contient pas %s", show(actual), show(expected)))
				end
			elseif type(actual) == "table" then
				if not table.find(actual, expected) then
					fail(string.format("le tableau ne contient pas %s", show(expected)))
				end
			else
				fail("toContain attend une chaîne ou un tableau")
			end
		end
		function m.toHaveLength(expected: number)
			local length = if type(actual) == "string" or type(actual) == "table" then #actual else -1
			if length ~= expected then
				fail(string.format("longueur attendue %d, obtenue %d", expected, length))
			end
		end
		function m.toThrow(pattern: string?)
			if type(actual) ~= "function" then
				fail("toThrow attend une fonction")
			end
			local ok, err = pcall(actual)
			if ok then
				fail("la fonction n'a pas levé d'erreur")
			elseif pattern and not string.find(tostring(err), pattern, 1, true) then
				fail(string.format("erreur %s ne contient pas %s", show(tostring(err)), show(pattern)))
			end
		end
		return m
	end
end

local function collectSpecs(folder: Instance, filter: string?): { ModuleScript }
	local specs = {}
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("ModuleScript") and string.match(descendant.Name, "%.spec$") then
			if not filter or string.find(descendant.Name, filter, 1, true) then
				table.insert(specs, descendant)
			end
		end
	end
	table.sort(specs, function(a, b)
		return a.Name < b.Name
	end)
	return specs
end

function Runner.run(filter: string?, options: { verbose: boolean? }?)
	local verbose = options == nil or options.verbose ~= false
	local specsFolder = script.Parent:FindFirstChild("Specs")
	local passed, failed = 0, 0
	local failures: { Failure } = {}
	local lines: { string } = {}

	if not specsFolder then
		return { passed = 0, failed = 0, total = 0, failures = failures, summary = "Aucun dossier Specs" }
	end

	for _, specModule in collectSpecs(specsFolder, filter) do
		local clone = specModule:Clone()
		clone.Parent = specModule.Parent
		local okLoad, specFn = pcall(require, clone)
		clone:Destroy()
		if not okLoad or type(specFn) ~= "function" then
			failed += 1
			local message = "chargement impossible : " .. tostring(specFn)
			table.insert(failures, { name = specModule.Name, message = message })
			table.insert(lines, "✘ " .. specModule.Name .. " — " .. message)
			continue
		end

		local stack: { string } = {}
		local t = {}
		t.expect = makeExpect()
		function t.describe(name: string, body: () -> ())
			table.insert(stack, name)
			local ok, err = pcall(body)
			if not ok then
				failed += 1
				local fullName = specModule.Name .. " › " .. table.concat(stack, " › ")
				table.insert(failures, { name = fullName, message = "erreur dans describe : " .. tostring(err) })
				table.insert(lines, "✘ " .. fullName .. " — " .. tostring(err))
			end
			table.remove(stack)
		end
		function t.it(name: string, body: () -> ())
			local fullName = specModule.Name .. " › " .. table.concat(stack, " › ") .. " › " .. name
			local ok, err = pcall(body)
			if ok then
				passed += 1
				if verbose then
					table.insert(lines, "✔ " .. fullName)
				end
			else
				failed += 1
				table.insert(failures, { name = fullName, message = tostring(err) })
				table.insert(lines, "✘ " .. fullName .. " — " .. tostring(err))
			end
		end

		local okRun, errRun = pcall(specFn, t)
		if not okRun then
			failed += 1
			table.insert(failures, { name = specModule.Name, message = tostring(errRun) })
			table.insert(lines, "✘ " .. specModule.Name .. " — " .. tostring(errRun))
		end
	end

	local total = passed + failed
	local summary = string.format("TESTS : %d réussis, %d échoués, %d au total", passed, failed, total)
	table.insert(lines, summary)
	print(table.concat(lines, "\n"))
	return { passed = passed, failed = failed, total = total, failures = failures, summary = summary }
end

return Runner
