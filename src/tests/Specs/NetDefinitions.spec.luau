--!strict
-- Intégration : toutes les définitions de remotes sont cohérentes (type, sens, spécification d'arguments, débit).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

local VALID_KINDS = { Event = true, Unreliable = true, Function = true }
local VALID_DIRS = { ToServer = true, ToClient = true, Both = true }
local VALID_BASES = {
	any = true,
	string = true,
	number = true,
	integer = true,
	boolean = true,
	Vector3 = true,
	Vector2 = true,
	CFrame = true,
	table = true,
}

local function validArgKind(raw: string): boolean
	local kind = if string.sub(raw, -1) == "?" then string.sub(raw, 1, -2) else raw
	local base, parameter = string.match(kind, "^(%a+%d?):?(%d*)$")
	if not base or not VALID_BASES[base] then
		return false
	end
	if parameter ~= "" and base ~= "string" then
		return false
	end
	return true
end

return function(t)
	local defs = Net.getDefinitions()

	t.describe("Définitions réseau", function()
		t.it("contiennent au moins les domaines de base", function()
			for _, name in { "Core.Notify", "Golf.Shoot", "Combat.Punch", "Match.Podium", "Lobby.SetSetting", "Data.Sync" } do
				t.expect(defs[name]).notToBeNil()
			end
		end)

		t.it("ont un type et un sens valides", function()
			for name, def in defs do
				if not VALID_KINDS[def.kind] then
					error(name .. " : kind invalide " .. tostring(def.kind))
				end
				if not VALID_DIRS[def.dir] then
					error(name .. " : dir invalide " .. tostring(def.dir))
				end
			end
		end)

		t.it("déclarent une spécification d'arguments valide pour tout remote client -> serveur", function()
			for name, def in defs do
				if def.dir ~= "ToClient" then
					if type(def.args) ~= "table" then
						error(name .. " : args manquant")
					end
					for index, raw in def.args :: { string } do
						if type(raw) ~= "string" or not validArgKind(raw) then
							error(string.format("%s : argument %d invalide (%s)", name, index, tostring(raw)))
						end
					end
				end
			end
		end)

		t.it("n'invoquent jamais le client (RemoteFunction serveur -> client interdite)", function()
			for name, def in defs do
				if def.kind == "Function" and def.dir ~= "ToServer" then
					error(name .. " : une Function doit être ToServer")
				end
			end
		end)

		t.it("limitent le débit avec des valeurs positives", function()
			for name, def in defs do
				if def.rate ~= nil and not (type(def.rate) == "number" and def.rate > 0) then
					error(name .. " : rate invalide")
				end
				if def.burst ~= nil and not (type(def.burst) == "number" and def.burst >= 1) then
					error(name .. " : burst invalide")
				end
			end
		end)

		t.it("suivent la convention de nommage Domaine.Action", function()
			for name in defs do
				if not string.match(name, "^%u%a+%.%u%w+$") then
					error("nom non conforme : " .. name)
				end
			end
		end)
	end)
end
