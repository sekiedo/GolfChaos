--!strict
--[[
	Data/Holes : agrégateur des trous (un module par biome, chacun retourne un tableau de Types.HoleDef).

	  local Holes = require(ReplicatedStorage.Shared.Data.Holes)
	  Holes.all()            -- tous les trous, ordre stable : biome (Config/Course.BiomeOrder) puis id
	  Holes.get("COT-03")    -- un trou ou nil
	  Holes.byBiome("Coast") -- trous d'un biome (ordre par id)
	  Holes.ids()            -- identifiants dans l'ordre de all()
	  Holes.count()          -- nombre total de trous

	Chargement paresseux au premier appel (aucun effet de bord au require). Un module de biome absent ou en
	erreur est remplacé par une liste vide et signalé UNE fois dans le journal ; un doublon d'identifiant garde
	la première définition et est signalé (HoleValidator.validateAll le compte aussi comme erreur).
	Les listes renvoyées sont des copies superficielles : les définitions elles-mêmes sont partagées et ne doivent
	jamais être modifiées par l'appelant.
]]

local Types = require(script.Parent.Parent.Types)
local Course = require(script.Parent.Parent.Config.Course)
local Log = require(script.Parent.Parent.Util.Log)

type HoleDef = Types.HoleDef

local Holes = {}

local MODULES = Course.BiomeOrder -- un ModuleScript par biome, même nom

local loaded = false
local ordered: { HoleDef } = {}
local byId: { [string]: HoleDef } = {}
local byBiomeList: { [string]: { HoleDef } } = {}
local loadErrors: { [string]: string } = {}

local function loadModule(name: string): { HoleDef }
	local module = script:FindFirstChild(name)
	if module == nil or not module:IsA("ModuleScript") then
		loadErrors[name] = "module absent"
		Log.warn("Holes", "module de trous absent :", name)
		return {}
	end
	local ok, result = pcall(require, module)
	if not ok then
		loadErrors[name] = tostring(result)
		Log.warn("Holes", "module de trous en erreur :", name, result)
		return {}
	end
	if type(result) ~= "table" then
		loadErrors[name] = "ne retourne pas de tableau"
		Log.warn("Holes", "module de trous invalide (tableau attendu) :", name)
		return {}
	end
	local list: { HoleDef } = {}
	for _, def in result :: { any } do
		if type(def) == "table" and type(def.id) == "string" then
			table.insert(list, def :: HoleDef)
		else
			Log.warn("Holes", "entrée ignorée dans", name, "(id manquant)")
		end
	end
	return list
end

local function ensureLoaded()
	if loaded then
		return
	end
	loaded = true
	for _, biome in MODULES do
		local list = loadModule(biome)
		table.sort(list, function(a: HoleDef, b: HoleDef)
			return a.id < b.id
		end)
		local kept: { HoleDef } = {}
		for _, def in list do
			if byId[def.id] ~= nil then
				Log.warn("Holes", "identifiant dupliqué ignoré :", def.id)
				continue
			end
			byId[def.id] = def
			table.insert(kept, def)
			table.insert(ordered, def)
		end
		byBiomeList[biome] = kept
	end
end

function Holes.all(): { HoleDef }
	ensureLoaded()
	return table.clone(ordered)
end

function Holes.get(id: string): HoleDef?
	ensureLoaded()
	return byId[id]
end

function Holes.byBiome(biome: string): { HoleDef }
	ensureLoaded()
	local list = byBiomeList[biome]
	return if list then table.clone(list) else {}
end

function Holes.ids(): { string }
	ensureLoaded()
	local ids = table.create(#ordered)
	for index, def in ordered do
		ids[index] = def.id
	end
	return ids
end

function Holes.count(): number
	ensureLoaded()
	return #ordered
end

-- Modules de biome en erreur ou absents ({ [biome] = raison }), pour les outils et les tests.
function Holes.loadErrors(): { [string]: string }
	ensureLoaded()
	return table.clone(loadErrors)
end

return Holes
