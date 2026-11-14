--!strict
--[[
	Logic.Playlist — construction PURE de la liste des trous d'une partie (aucune dépendance moteur hormis
	Random, aucun effet de bord ; testé par tests/Specs/Playlist.spec.luau).

	  Playlist.build(settings, holes, seed?) -> PlaylistResult
	      settings : Types.MatchSettings (playlist, holeCount, customHoleIds, biomes, shuffle)
	      holes    : liste de HoleDef (seuls `id` et `biome` sont lus) — Data/Holes.all()
	      seed     : graine du mélange (même graine + mêmes données = même playlist) ; défaut 0

	Playlists (Config/Match.Playlists) :
	  "Quick3" / "Front9" / "Full18"  les 3 / 9 / 18 premiers trous du parcours (ordre du catalogue : biomes dans
	                                  l'ordre CourseBiomes, puis identifiant), limités aux biomes de settings.biomes
	                                  s'il est renseigné ; mélangés si settings.shuffle.
	  "Biome:<Biome>"                 settings.holeCount trous du biome, dans l'ordre (ou mélangés).
	  "Mixed"                         settings.holeCount trous des biomes de settings.biomes (tous les biomes du
	                                  parcours si vide) : alternance biome par biome, ou mélange si settings.shuffle.
	  "Custom"                        settings.customHoleIds : ids inconnus ignorés, doublons retirés, 18 au plus ;
	                                  ordre de l'hôte (ou mélangé si settings.shuffle).

	Repli (jamais d'erreur, jamais de boucle) : moins de trous que demandé -> tous les trous disponibles
	(fallback "fewerHoles") ; filtre de biome vide -> parcours complet ("biomeEmpty") ; aucun trou de parcours ->
	trous d'entraînement ("trainingOnly") ; playlist personnalisée vide ou invalide -> "Quick3" ("customInvalid") ;
	nom de playlist inconnu -> "Quick3" ("invalidPlaylist") ; aucun trou du tout -> liste vide ("noHoles").
	Les doublons d'identifiants dans les données sont ignorés (le premier l'emporte).
]]

local Types = require(script.Parent.Parent.Types)
local ConfigMatch = require(script.Parent.Parent.Config.Match)

export type PlaylistKind = "Quick3" | "Front9" | "Full18" | "Biome" | "Mixed" | "Custom"

export type PlaylistResult = {
	holeIds: { string },
	kind: PlaylistKind,
	biome: Types.Biome?, -- playlist "Biome:<Biome>"
	requested: number, -- nombre de trous demandés
	available: number, -- trous candidats après filtrage (avant la coupe à `requested`)
	fallback: string?, -- motif du repli éventuel (voir l'en-tête)
	invalidIds: { string }, -- ids personnalisés ignorés (inconnus, doublons, en trop)
	seed: number,
}

type HoleLike = { id: string, biome: string }

local PLAYLISTS = ConfigMatch.Playlists

local Playlist = {}

local BIOME_SET: { [string]: boolean } = {}
local ALL_BIOMES: { string } = {}
for _, biome in PLAYLISTS.Biomes do
	BIOME_SET[biome] = true
	table.insert(ALL_BIOMES, biome)
end

local COURSE_INDEX: { [string]: number } = {}
local COURSE_BIOMES: { string } = {}
for index, biome in PLAYLISTS.CourseBiomes do
	COURSE_INDEX[biome] = index
	table.insert(COURSE_BIOMES, biome)
end

local function clampCount(value: any): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return PLAYLISTS.MinHoles
	end
	return math.clamp(math.floor(value), PLAYLISTS.MinHoles, PLAYLISTS.MaxHoles)
end

-- Décompose un nom de playlist : ("Quick3" | ... | "Biome", biome?) ou nil si le nom est invalide.
function Playlist.parse(name: any): (PlaylistKind?, Types.Biome?)
	if type(name) ~= "string" then
		return nil, nil
	end
	if PLAYLISTS.FixedSizes[name] ~= nil then
		return name :: PlaylistKind, nil
	end
	if name == "Mixed" then
		return "Mixed", nil
	elseif name == "Custom" then
		return "Custom", nil
	end
	local biome = string.match(name, "^Biome:(%a+)$")
	if biome ~= nil and BIOME_SET[biome] then
		return "Biome", biome :: Types.Biome
	end
	return nil, nil
end

function Playlist.isValidName(name: any): boolean
	local kind = Playlist.parse(name)
	return kind ~= nil
end

function Playlist.isBiome(value: any): boolean
	return type(value) == "string" and BIOME_SET[value] == true
end

-- Taille demandée par une playlist (fixe, ou settings.holeCount / longueur de la liste personnalisée).
function Playlist.requestedCount(settings: Types.MatchSettings): number
	local kind = Playlist.parse(settings.playlist)
	if kind ~= nil then
		local fixed = PLAYLISTS.FixedSizes[kind]
		if fixed ~= nil then
			return fixed
		end
		if kind == "Custom" then
			local ids = settings.customHoleIds
			return if type(ids) == "table" then math.clamp(#ids, 0, PLAYLISTS.MaxHoles) else 0
		end
	end
	return clampCount(settings.holeCount)
end

-- Entrées valides et uniques (id texte non vide, biome texte), dans l'ordre d'origine.
function Playlist.dedupeHoles(holes: { any }): { HoleLike }
	local result: { HoleLike } = {}
	local seen: { [string]: boolean } = {}
	if type(holes) ~= "table" then
		return result
	end
	for _, hole in holes do
		if type(hole) ~= "table" then
			continue
		end
		local id, biome = hole.id, hole.biome
		if type(id) ~= "string" or id == "" or type(biome) ~= "string" or seen[id] then
			continue
		end
		seen[id] = true
		table.insert(result, { id = id, biome = biome })
	end
	return result
end

-- Index des trous par identifiant (après dédoublonnage).
function Playlist.indexById(holes: { any }): { [string]: boolean }
	local index: { [string]: boolean } = {}
	for _, hole in Playlist.dedupeHoles(holes) do
		index[hole.id] = true
	end
	return index
end

-- Ordre du catalogue : biomes du parcours dans l'ordre CourseBiomes (les autres ensuite, par nom), puis id.
function Playlist.sortCourse(holes: { HoleLike }): { HoleLike }
	local sorted = table.clone(holes)
	table.sort(sorted, function(a: HoleLike, b: HoleLike): boolean
		local indexA = COURSE_INDEX[a.biome] or math.huge
		local indexB = COURSE_INDEX[b.biome] or math.huge
		if indexA ~= indexB then
			return indexA < indexB
		end
		if a.biome ~= b.biome then
			return a.biome < b.biome
		end
		return a.id < b.id
	end)
	return sorted
end

-- Mélange de Fisher-Yates en place, reproductible avec un Random à graine fixe. Retourne la liste.
function Playlist.shuffle<T>(list: { T }, rng: Random): { T }
	for index = #list, 2, -1 do
		local other = rng:NextInteger(1, index)
		list[index], list[other] = list[other], list[index]
	end
	return list
end

-- Liste personnalisée envoyée par un client : seuls les ids connus, uniques, en texte court, sont gardés
-- (au plus `maxCount`). Retourne (ids valides dans l'ordre, ids rejetés pour information).
function Playlist.sanitizeCustom(ids: any, known: { [string]: boolean }, maxCount: number?): ({ string }, { string })
	local clean: { string } = {}
	local rejected: { string } = {}
	if type(ids) ~= "table" then
		return clean, rejected
	end
	local limit = math.clamp(math.floor(maxCount or PLAYLISTS.MaxHoles), 0, PLAYLISTS.MaxHoles)
	local maxLength = ConfigMatch.Lobby.HoleIdMaxLength
	local seen: { [string]: boolean } = {}
	-- Parcours borné : un client ne peut pas imposer une liste immense.
	local scanLimit = math.max(limit, 1) * 3
	for index = 1, scanLimit do
		local value = (ids :: { any })[index]
		if value == nil then
			break
		end
		if type(value) ~= "string" or #value == 0 or #value > maxLength then
			table.insert(rejected, if type(value) == "string" then string.sub(value, 1, maxLength) else "?")
		elseif seen[value] or not known[value] or #clean >= limit then
			table.insert(rejected, value)
		else
			seen[value] = true
			table.insert(clean, value)
		end
	end
	return clean, rejected
end

local function filterByBiomes(holes: { HoleLike }, biomes: { [string]: boolean }): { HoleLike }
	local result: { HoleLike } = {}
	for _, hole in holes do
		if biomes[hole.biome] then
			table.insert(result, hole)
		end
	end
	return result
end

-- Biomes demandés (valides, uniques, dans l'ordre donné) ; liste vide si aucun.
local function requestedBiomes(value: any): { string }
	local result: { string } = {}
	if type(value) ~= "table" then
		return result
	end
	local seen: { [string]: boolean } = {}
	for index = 1, #ALL_BIOMES do
		local biome = (value :: { any })[index]
		if biome == nil then
			break
		end
		if Playlist.isBiome(biome) and not seen[biome] then
			seen[biome] = true
			table.insert(result, biome)
		end
	end
	return result
end

local function toSet(list: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, value in list do
		set[value] = true
	end
	return set
end

-- Alternance biome par biome (ordre `biomeOrder`), chaque biome dans l'ordre du catalogue.
local function interleave(holes: { HoleLike }, biomeOrder: { string }): { HoleLike }
	local groups: { { HoleLike } } = {}
	local groupIndex: { [string]: number } = {}
	for _, biome in biomeOrder do
		if groupIndex[biome] == nil then
			table.insert(groups, {})
			groupIndex[biome] = #groups
		end
	end
	for _, hole in Playlist.sortCourse(holes) do
		local index = groupIndex[hole.biome]
		if index ~= nil then
			table.insert(groups[index], hole)
		end
	end
	local result: { HoleLike } = {}
	local round = 1
	local added = true
	while added do
		added = false
		for _, group in groups do
			local hole = group[round]
			if hole ~= nil then
				table.insert(result, hole)
				added = true
			end
		end
		round += 1
	end
	return result
end

local function ids(holes: { HoleLike }, count: number): { string }
	local result: { string } = {}
	for index = 1, math.min(count, #holes) do
		table.insert(result, holes[index].id)
	end
	return result
end

function Playlist.build(settings: Types.MatchSettings, holes: { any }, seed: number?): PlaylistResult
	local seedValue = if type(seed) == "number" and seed == seed and math.abs(seed) < 2 ^ 52 then math.floor(seed) else 0
	local rng = Random.new(seedValue)
	local catalog = Playlist.dedupeHoles(holes)
	local trainingBiome: string = PLAYLISTS.TrainingBiome
	local courseSet = toSet(COURSE_BIOMES)
	local courseHoles = Playlist.sortCourse(filterByBiomes(catalog, courseSet))
	local trainingHoles = Playlist.sortCourse(filterByBiomes(catalog, { [trainingBiome] = true }))
	local shuffle = settings.shuffle == true

	local fallback: string? = nil
	local invalidIds: { string } = {}
	local kind, biome = Playlist.parse(settings.playlist)
	if kind == nil then
		kind = "Quick3"
		fallback = "invalidPlaylist"
	end

	-- Repli commun : parcours complet, sinon trous d'entraînement.
	local function fallbackPool(reason: string): { HoleLike }
		if #courseHoles > 0 then
			fallback = fallback or reason
			return table.clone(courseHoles)
		end
		if #trainingHoles > 0 then
			fallback = fallback or "trainingOnly"
			return table.clone(trainingHoles)
		end
		fallback = "noHoles"
		return {}
	end

	local requested: number
	local ordered: { HoleLike }

	if kind == "Custom" then
		local known: { [string]: boolean } = {}
		for _, hole in catalog do
			known[hole.id] = true
		end
		local clean, rejected = Playlist.sanitizeCustom(settings.customHoleIds, known, PLAYLISTS.MaxHoles)
		invalidIds = rejected
		if #clean == 0 then
			-- Liste vide ou entièrement invalide : partie rapide plutôt qu'un blocage.
			fallback = fallback or "customInvalid"
			kind = "Quick3"
			requested = PLAYLISTS.FixedSizes.Quick3
			ordered = if #courseHoles > 0 then table.clone(courseHoles) else fallbackPool("customInvalid")
		else
			requested = #clean
			local byId: { [string]: HoleLike } = {}
			for _, hole in catalog do
				byId[hole.id] = hole
			end
			ordered = {}
			for _, id in clean do
				table.insert(ordered, byId[id])
			end
		end
	elseif kind == "Biome" then
		requested = clampCount(settings.holeCount)
		local biomeName: string = biome or ""
		ordered = Playlist.sortCourse(filterByBiomes(catalog, { [biomeName] = true }))
		if #ordered == 0 then
			ordered = fallbackPool("biomeEmpty")
		end
	elseif kind == "Mixed" then
		requested = clampCount(settings.holeCount)
		local wanted = requestedBiomes(settings.biomes)
		if #wanted == 0 then
			wanted = table.clone(COURSE_BIOMES)
		end
		local pool = filterByBiomes(catalog, toSet(wanted))
		if #pool == 0 then
			ordered = fallbackPool("biomeEmpty")
		elseif shuffle then
			ordered = Playlist.sortCourse(pool)
		else
			ordered = interleave(pool, wanted)
		end
	else
		requested = PLAYLISTS.FixedSizes[kind] or PLAYLISTS.FixedSizes.Quick3
		local wanted = requestedBiomes(settings.biomes)
		if #wanted > 0 then
			ordered = Playlist.sortCourse(filterByBiomes(catalog, toSet(wanted)))
			if #ordered == 0 then
				ordered = fallbackPool("biomeEmpty")
			end
		else
			ordered = if #courseHoles > 0 then table.clone(courseHoles) else fallbackPool("trainingOnly")
		end
	end

	if shuffle then
		Playlist.shuffle(ordered, rng)
	end

	local holeIds = ids(ordered, requested)
	if #holeIds == 0 then
		fallback = "noHoles"
	elseif #holeIds < requested and fallback == nil then
		fallback = "fewerHoles"
	end

	return {
		holeIds = holeIds,
		kind = kind :: PlaylistKind,
		biome = if kind == "Biome" then biome else nil,
		requested = requested,
		available = #ordered,
		fallback = fallback,
		invalidIds = invalidIds,
		seed = seedValue,
	}
end

return Playlist
