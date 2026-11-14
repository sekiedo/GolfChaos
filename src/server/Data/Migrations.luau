--!strict
--[[
	Migrations — amène un profil lu dans le DataStore à Schema.CURRENT_VERSION, puis l'assainit. SERVEUR uniquement.
	Module PUR : aucun effet au require, aucune requête, jamais de yield (utilisable dans une transformation
	UpdateAsync).

	  Migrations.upgrade(raw, now?) -> (Profile?, { string }, string?)
	      raw = nil                 -> profil neuf (Schema.defaultProfile), aucune réparation
	      raw = table version <= N  -> étapes Migrations.Steps[version] appliquées dans l'ordre sur une COPIE,
	                                   puis Schema.sanitize ; la liste décrit migrations et réparations
	      raw d'une version FUTURE  -> (nil, {}, "future_version") : un serveur ancien ne doit jamais réécrire
	                                   un profil produit par un code plus récent (perte de données)
	      raw non-table             -> (nil, {}, "invalid") : valeur inattendue, à ne pas écraser sans examen

	Ajouter une version : incrémenter Schema.CURRENT_VERSION et écrire Migrations.Steps[ancienneVersion] =
	function(data) ... end, qui transforme `data` (déjà copié) de `ancienneVersion` vers `ancienneVersion + 1`.
]]

local Schema = require(script.Parent.Schema)

export type Profile = Schema.Profile
export type Step = (data: { [any]: any }) -> ()

local Migrations = {}

-- Étapes indexées par la version de DÉPART. La version 0 désigne un profil sans champ `version`.
Migrations.Steps = {
	[0] = function(_data: { [any]: any })
		-- Profil d'avant le champ `version` : même forme que la version 1, rien à transformer.
	end,
} :: { [number]: Step }

local function deepCopy(value: any, seen: { [any]: any }): any
	if type(value) ~= "table" then
		return value
	end
	if seen[value] ~= nil then
		return seen[value]
	end
	local copy = {}
	seen[value] = copy
	for key, item in value do
		copy[deepCopy(key, seen)] = deepCopy(item, seen)
	end
	return copy
end

local function versionOf(raw: { [any]: any }): number
	local version = raw.version
	if type(version) == "number" and version == version and version >= 0 and version % 1 == 0 then
		return version
	end
	return 0
end

function Migrations.upgrade(raw: any, now: number?): (Profile?, { string }, string?)
	if raw == nil then
		return Schema.defaultProfile(now), {}, nil
	end
	if type(raw) ~= "table" then
		return nil, {}, "invalid"
	end
	local version = versionOf(raw)
	if version > Schema.CURRENT_VERSION then
		return nil, {}, "future_version"
	end

	local data = deepCopy(raw, {})
	local notes: { string } = {}
	while version < Schema.CURRENT_VERSION do
		local step = Migrations.Steps[version]
		if step then
			step(data)
		end
		version += 1
		data.version = version
		table.insert(notes, string.format("migration %d -> %d", version - 1, version))
	end

	local profile, repairs = Schema.sanitize(data, now)
	for _, repair in repairs do
		table.insert(notes, repair)
	end
	return profile, notes, nil
end

return Migrations
