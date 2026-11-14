--!strict
--[[
	Schema — format versionné du profil persistant d'un joueur (docs/SPEC_DEMANDE.md §8). SERVEUR uniquement.
	Module PUR : aucun effet au require, aucune requête, aucune instance créée.

	  Schema.CURRENT_VERSION                       version écrite par ce code (Migrations y amène les anciennes)
	  Schema.defaultProfile(now?) -> Profile       profil neuf (Config.Economy.StartingCoins pièces)
	  Schema.sanitize(data, now?) -> (Profile, { string })
	        Répare les champs manquants ou invalides SANS jeter les données valides (statistiques inconnues,
	        ensembles, champs inconnus sérialisables conservés) et renvoie la liste des réparations (vide = rien
	        à corriger). Ne modifie jamais `data` : le résultat est une copie neuve, bornée et sérialisable pour
	        DataStore. Idempotent : sanitize(sanitize(x)) ne répare plus rien. À appeler APRÈS les migrations
	        (Migrations.upgrade le fait).
	  Schema.validateSetting(key, value) -> (boolean, valeurNormalisée)   préférence venant du client (stricte)
	  Schema.applySettings(settings, patch) -> (clésModifiées, clésRejetées)   message Data.SaveSettings
	  Schema.hasOp(profile, opId) / Schema.recordOp(profile, opId, at?)   idempotence des transactions
	  Schema.incrementStat(profile, key, amount?) / Schema.addToSet(profile, setName, entry)
	  Schema.recordSolo(profile, holeId, strokes, time) / Schema.isBetterSolo(a, b)
	  Schema.clientView(profile) -> table          instantané pour Data.Sync (sans processedOps ni champs inconnus)
	  Schema.defaultEquipped() / Schema.emptyLoadout() / Schema.defaultSettings() / Schema.isId(value, maxBytes?)

	Contenu d'un profil (version 1) :
	  coins          pièces, entier 0..Economy.MaxCoins
	  owned          { [cosmeticId] = true } — les cosmétiques « par défaut » (unlock Default) n'y figurent pas
	  equipped       { Head, Face, Outfit, Shoes, Club, Ball, HoleEffect = id ou "", Emotes = { id } (8 au plus) }
	                 "" = cosmétique par défaut de l'emplacement (Cosmetics.defaultFor(slot))
	  variants       { [cosmeticId] = indice de variante de couleur (1..64) }
	  loadouts       ensembles enregistrés (3 proposés) : { name, savedAt (0 = emplacement vide), equipped, variants }
	                 le nom est un texte saisi par le joueur : le FILTRER (TextService) avant de l'afficher à d'autres
	  achievements   { [achievementId] = { done, at? } }
	  stats          compteurs { [nom] = nombre fini } : TOUTE clé est acceptée ; Schema.KnownStats pré-remplies à 0
	  sets           ensembles { [nomEnsemble] = { [élément] = true } } (biomesFinished, holesFinished_Coast, itemsUsedSet...)
	  events         { [nomÉvénement] = true } (défis de type Event : tutorialDone, noPenaltyNine...)
	  bestSolo       { [holeId] = { strokes, time } } — record personnel du mode Solo (moins de coups, puis temps) ;
	                 une valeur écrite par erreur dans stats.bestSolo est déplacée ici par sanitize
	  settings       préférences : masterVolume, musicVolume, sfxVolume (0..1), sensitivity (0.1..4), cameraShake (0..1),
	                 vibration, reducedEffects, noFlash (booléens), language ("fr", "en"...), quality ("Auto"|"Low"|"Medium"|"High")
	  processedOps   liste bornée { id, at } des opérations déjà appliquées (récompenses, achats) ; jamais envoyée au client
	  tutorialDone, createdAt, updatedAt (secondes Unix, os.time())

	Les identifiants ne sont PAS confrontés aux catalogues (Cosmetics, Config.Achievements) : un id retiré d'un
	catalogue reste conservé et sera simplement ignoré par le service concerné (aucune perte s'il revient).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Config.Economy)

export type Slot = "Head" | "Face" | "Outfit" | "Shoes" | "Club" | "Ball" | "HoleEffect"

export type Equipped = {
	Head: string,
	Face: string,
	Outfit: string,
	Shoes: string,
	Club: string,
	Ball: string,
	HoleEffect: string,
	Emotes: { string },
}

export type Loadout = {
	name: string,
	savedAt: number,
	equipped: Equipped,
	variants: { [string]: number },
}

export type AchievementRecord = { done: boolean, at: number? }

export type SoloRecord = { strokes: number, time: number }

export type Settings = {
	masterVolume: number,
	musicVolume: number,
	sfxVolume: number,
	sensitivity: number,
	cameraShake: number,
	vibration: boolean,
	reducedEffects: boolean,
	noFlash: boolean,
	language: string,
	quality: string,
}

export type ProcessedOp = { id: string, at: number }

export type Profile = {
	version: number,
	coins: number,
	owned: { [string]: boolean },
	equipped: Equipped,
	variants: { [string]: number },
	loadouts: { Loadout },
	achievements: { [string]: AchievementRecord },
	stats: { [string]: number },
	sets: { [string]: { [string]: boolean } },
	events: { [string]: boolean },
	bestSolo: { [string]: SoloRecord },
	settings: Settings,
	processedOps: { ProcessedOp },
	tutorialDone: boolean,
	createdAt: number,
	updatedAt: number,
}

local Schema = {}

Schema.CURRENT_VERSION = 1

Schema.Limits = table.freeze({
	MaxIdLength = 64, -- octets : cosmétiques, défis, trous, objets, statistiques, ensembles, événements
	MaxOpIdLength = 100, -- octets : identifiants d'opération (ex. MatchId .. ":" .. UserId)
	Loadouts = 3, -- ensembles proposés (Shop.SaveLoadout / Shop.UseLoadout 1..3)
	MaxStoredLoadouts = 10, -- ensembles conservés si le nombre proposé baisse un jour (aucune perte)
	MaxLoadoutNameLength = 32, -- caractères
	MaxLoadoutNameBytes = 128,
	MaxLoadoutVariants = 64,
	MaxEquippedEmotes = 8,
	MaxVariantIndex = 64,
	MaxOwned = 2000,
	MaxVariants = 2000,
	MaxAchievements = 512,
	MaxStats = 512,
	MaxStatValue = 1e15,
	MaxSets = 64,
	MaxSetEntries = 1024,
	MaxEvents = 256,
	MaxBestSolo = 256,
	MaxSoloStrokes = 999,
	MaxSoloTime = 86400, -- secondes
	MaxProcessedOps = 200, -- les plus anciennes sont oubliées au-delà (≈ 150 parties récentes)
	MaxExtraFields = 32, -- champs inconnus conservés (écrits par un autre service ou une autre version)
	MaxExtraDepth = 8,
	MaxSettingsPatch = 16, -- clés par message Data.SaveSettings
	MaxRepairs = 100, -- longueur maximale de la liste de réparations renvoyée par sanitize
})
local LIMITS = Schema.Limits

Schema.Slots = table.freeze({ "Head", "Face", "Outfit", "Shoes", "Club", "Ball", "HoleEffect" } :: { Slot })

-- Compteurs pré-remplis à 0 (toute autre clé numérique reste acceptée et conservée).
Schema.KnownStats = table.freeze({
	"holesPlayed",
	"holesFinished",
	"holesInOne",
	"birdies",
	"eagles",
	"parOrBetter",
	"shots",
	"kos",
	"timesKOed",
	"itemsUsed",
	"cartDistance",
	"cartKOs",
	"matchesPlayed",
	"matchesWon",
	"teamWins",
	"longShots",
	"onePutts",
	"chipIns",
	"shieldBlocks",
	"hornForcedShots",
	"dodges",
} :: { string })

--------------------------------------------------------------------------------
-- Préférences (bornes et valeurs par défaut : source unique pour sanitize et Data.SaveSettings)
--------------------------------------------------------------------------------

type NumberSpec = {
	kind: "number",
	default: number,
	min: number,
	max: number,
	acceptBoolean: boolean?, -- true -> max, false -> min (interrupteur côté interface)
	acceptPercent: boolean?, -- 1 < v <= 100 lu comme un pourcentage
}
type BooleanSpec = { kind: "boolean", default: boolean }
type EnumSpec = { kind: "enum", default: string, values: { string } }
type LanguageSpec = { kind: "language", default: string }
type SettingSpec = NumberSpec | BooleanSpec | EnumSpec | LanguageSpec

local SETTINGS: { [string]: SettingSpec } = {
	masterVolume = { kind = "number", default = 1, min = 0, max = 1 },
	musicVolume = { kind = "number", default = 0.8, min = 0, max = 1 },
	sfxVolume = { kind = "number", default = 1, min = 0, max = 1 },
	sensitivity = { kind = "number", default = 1, min = 0.1, max = 4 },
	cameraShake = { kind = "number", default = 1, min = 0, max = 1, acceptBoolean = true, acceptPercent = true },
	vibration = { kind = "boolean", default = true },
	reducedEffects = { kind = "boolean", default = false },
	noFlash = { kind = "boolean", default = false },
	language = { kind = "language", default = "fr" },
	quality = { kind = "enum", default = "Auto", values = { "Auto", "Low", "Medium", "High" } },
}

Schema.SettingKeys = table.freeze({
	"masterVolume",
	"musicVolume",
	"sfxVolume",
	"sensitivity",
	"cameraShake",
	"vibration",
	"reducedEffects",
	"noFlash",
	"language",
	"quality",
} :: { string })

local CURRENT_VERSION = Schema.CURRENT_VERSION
local SLOTS = Schema.Slots
local KNOWN_STATS = Schema.KnownStats
local FALLBACK_LANGUAGES = { "fr", "en" }

local KNOWN_FIELDS: { [string]: boolean } = {
	version = true,
	coins = true,
	owned = true,
	equipped = true,
	variants = true,
	loadouts = true,
	achievements = true,
	stats = true,
	sets = true,
	events = true,
	bestSolo = true,
	settings = true,
	processedOps = true,
	tutorialDone = true,
	createdAt = true,
	updatedAt = true,
}

--------------------------------------------------------------------------------
-- Outils
--------------------------------------------------------------------------------

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Nombre fini, ou texte numérique court (réparation d'une valeur mal typée) ; nil sinon.
local function toFiniteNumber(value: any): number?
	if isFinite(value) then
		return value
	elseif type(value) == "string" and #value <= 32 then
		local parsed = tonumber(value)
		if isFinite(parsed) then
			return parsed
		end
	end
	return nil
end

-- Texte non vide, borné, UTF-8 valide, sans caractère de contrôle.
local function isCleanString(value: any, maxBytes: number): boolean
	if type(value) ~= "string" then
		return false
	end
	local length = #value
	return length > 0 and length <= maxBytes and utf8.len(value) ~= nil and string.find(value, "%c") == nil
end

-- Identifiant utilisable comme clé : texte propre, ou nombre fini converti en texte ; nil sinon.
local function toId(value: any, maxBytes: number?): string?
	local limit = maxBytes or LIMITS.MaxIdLength
	if type(value) == "string" then
		return if isCleanString(value, limit) then value else nil
	elseif isFinite(value) then
		local text = if value == math.floor(value) and math.abs(value) < 2 ^ 53
			then string.format("%d", value)
			else tostring(value)
		return if #text <= limit then text else nil
	end
	return nil
end

local function addRepair(repairs: { string }, path: string, reason: string)
	local count = #repairs
	if count < LIMITS.MaxRepairs then
		table.insert(repairs, path .. " : " .. reason)
	elseif count == LIMITS.MaxRepairs then
		table.insert(repairs, "… (réparations suivantes non listées)")
	end
end

local function count(map: { [any]: any }): number
	local total = 0
	for _ in map do
		total += 1
	end
	return total
end

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value :: any do
		copy[deepCopy(key)] = deepCopy(child)
	end
	return copy :: any
end

local function economyNumber(value: any, fallback: number): number
	return if isFinite(value) and value >= 0 then math.floor(value) else fallback
end

local function maxCoins(): number
	return economyNumber(Economy.MaxCoins, 10_000_000)
end

local function startingCoins(): number
	return math.min(economyNumber(Economy.StartingCoins, 0), maxCoins())
end

-- Valeurs d'une liste dans l'ordre des indices (trous tolérés), puis clés texte d'une forme « ensemble »
-- ({ id = true }) triées. Le booléen indique une forme non canonique (ensemble, valeurs non textuelles).
local function listEntries(value: { [any]: any }): ({ any }, boolean)
	local indices: { number } = {}
	local names: { string } = {}
	local normalized = false
	for key, entry in value do
		if type(key) == "number" then
			table.insert(indices, key)
			if type(entry) ~= "string" then
				normalized = true
			end
		else
			normalized = true
			if type(key) == "string" and entry ~= false then
				table.insert(names, key)
			end
		end
	end
	table.sort(indices)
	table.sort(names)
	local result: { any } = {}
	for _, index in indices do
		table.insert(result, value[index])
	end
	for _, name in names do
		table.insert(result, name)
	end
	return result, normalized
end

-- Langues acceptées : celles chargées par Locale (require paresseux), sinon fr/en.
local languageCache: { [string]: boolean }? = nil

local function supportedLanguages(): { [string]: boolean }
	local cached = languageCache
	if cached then
		return cached
	end
	local set: { [string]: boolean } = {}
	local ok, list = pcall(function()
		local Locale = require(Shared.Locale) :: any
		return Locale.getLanguages()
	end)
	if ok and type(list) == "table" then
		for _, code in list do
			if type(code) == "string" and code ~= "" then
				set[string.lower(code)] = true
			end
		end
	end
	if next(set) == nil then
		for _, code in FALLBACK_LANGUAGES do
			set[code] = true
		end
	end
	languageCache = set
	return set
end

-- Normalise une préférence. `lenient` (données stockées) accepte aussi un texte numérique.
local function coerceSetting(spec: SettingSpec, value: any, lenient: boolean): (boolean, any)
	if spec.kind == "number" then
		local number: number? = nil
		if type(value) == "boolean" then
			if spec.acceptBoolean then
				number = if value then spec.max else spec.min
			end
		elseif isFinite(value) then
			number = value
		elseif lenient then
			number = toFiniteNumber(value)
		end
		if number == nil then
			return false, nil
		end
		local resolved: number = number
		if spec.acceptPercent and resolved > spec.max and resolved <= 100 then
			resolved = resolved / 100 * spec.max
		end
		return true, math.clamp(resolved, spec.min, spec.max)
	elseif spec.kind == "boolean" then
		if type(value) == "boolean" then
			return true, value
		end
		return false, nil
	elseif spec.kind == "enum" then
		if type(value) == "string" and #value <= 32 then
			local lowered = string.lower(value)
			for _, option in spec.values do
				if string.lower(option) == lowered then
					return true, option
				end
			end
		end
		return false, nil
	else
		if type(value) == "string" and #value <= 16 then
			local code = string.lower(value)
			if supportedLanguages()[code] then
				return true, code
			end
		end
		return false, nil
	end
end

--------------------------------------------------------------------------------
-- Valeurs par défaut
--------------------------------------------------------------------------------

function Schema.defaultEquipped(): Equipped
	return {
		Head = "",
		Face = "",
		Outfit = "",
		Shoes = "",
		Club = "",
		Ball = "",
		HoleEffect = "",
		Emotes = {},
	}
end

function Schema.emptyLoadout(): Loadout
	return { name = "", savedAt = 0, equipped = Schema.defaultEquipped(), variants = {} }
end

function Schema.defaultSettings(): Settings
	local settings: { [string]: any } = {}
	for key, spec in SETTINGS do
		settings[key] = spec.default
	end
	return (settings :: any) :: Settings
end

local function defaultStats(): { [string]: number }
	local stats: { [string]: number } = {}
	for _, key in KNOWN_STATS do
		stats[key] = 0
	end
	return stats
end

function Schema.defaultProfile(now: number?): Profile
	local clock = if isFinite(now) then now :: number else os.time()
	local loadouts: { Loadout } = {}
	for index = 1, LIMITS.Loadouts do
		loadouts[index] = Schema.emptyLoadout()
	end
	return {
		version = CURRENT_VERSION,
		coins = startingCoins(),
		owned = {},
		equipped = Schema.defaultEquipped(),
		variants = {},
		loadouts = loadouts,
		achievements = {},
		stats = defaultStats(),
		sets = {},
		events = {},
		bestSolo = {},
		settings = Schema.defaultSettings(),
		processedOps = {},
		tutorialDone = false,
		createdAt = clock,
		updatedAt = clock,
	}
end

--------------------------------------------------------------------------------
-- Réparation champ par champ
--------------------------------------------------------------------------------

local function sanitizeCoins(value: any, repairs: { string }): number
	if value == nil then
		addRepair(repairs, "coins", "manquant")
		return startingCoins()
	end
	local number = toFiniteNumber(value)
	if number == nil then
		addRepair(repairs, "coins", "invalide")
		return 0
	end
	local whole = math.floor(number)
	local fixed = math.clamp(whole, 0, maxCoins())
	if fixed ~= value then
		addRepair(repairs, "coins", if fixed ~= whole then "borné" else "normalisé")
	end
	return fixed
end

-- Ensemble d'identifiants { [id] = true } ; accepte aussi la forme liste { "id1", "id2" }.
local function sanitizeIdSet(value: any, path: string, max: number, repairs: { string }): { [string]: boolean }
	local result: { [string]: boolean } = {}
	if value == nil then
		addRepair(repairs, path, "manquant")
		return result
	end
	if type(value) ~= "table" then
		addRepair(repairs, path, "invalide")
		return result
	end
	local total, dropped, normalized = 0, 0, false
	for key, entry in value do
		local id: string?
		if type(key) == "number" then
			id = toId(entry) -- forme liste
			normalized = true
		elseif entry == false then
			normalized = true -- « absent » explicite : retiré sans perte
			continue
		else
			id = toId(key) -- forme ensemble (une valeur vraie non booléenne est acceptée)
			if entry ~= true or type(key) ~= "string" then
				normalized = true
			end
		end
		if id == nil then
			dropped += 1
		elseif not result[id] then
			if total < max then
				result[id] = true
				total += 1
			else
				dropped += 1
			end
		end
	end
	if dropped > 0 then
		addRepair(repairs, path, "retirés " .. dropped)
	end
	if normalized then
		addRepair(repairs, path, "normalisé")
	end
	return result
end

-- Liste ordonnée d'identifiants distincts, bornée.
local function sanitizeIdList(value: any, path: string, max: number, repairs: { string }): { string }
	local result: { string } = {}
	if value == nil then
		return result
	end
	if type(value) ~= "table" then
		addRepair(repairs, path, "invalide")
		return result
	end
	local entries, normalized = listEntries(value)
	local seen: { [string]: boolean } = {}
	local dropped = 0
	for _, entry in entries do
		local id = toId(entry)
		if id == nil or seen[id] then
			dropped += 1
		else
			seen[id] = true
			if #result < max then
				table.insert(result, id)
			else
				dropped += 1
			end
		end
	end
	if dropped > 0 then
		addRepair(repairs, path, "retirés " .. dropped)
	end
	if normalized then
		addRepair(repairs, path, "normalisé")
	end
	return result
end

local function sanitizeEquipped(value: any, path: string, repairs: { string }): Equipped
	local result = Schema.defaultEquipped()
	if value == nil then
		addRepair(repairs, path, "manquant")
		return result
	end
	if type(value) ~= "table" then
		addRepair(repairs, path, "invalide")
		return result
	end
	local writable = result :: any
	for _, slot in SLOTS do
		local entry = value[slot]
		if entry == nil or entry == "" then
			continue -- vide : cosmétique par défaut de l'emplacement
		end
		local id = if type(entry) == "string" then toId(entry) else nil
		if id then
			writable[slot] = id
		else
			addRepair(repairs, path .. "." .. slot, "invalide")
		end
	end
	result.Emotes = sanitizeIdList(value.Emotes, path .. ".Emotes", LIMITS.MaxEquippedEmotes, repairs)
	for key in value do
		if key ~= "Emotes" and not (type(key) == "string" and table.find(SLOTS, key :: any) ~= nil) then
			addRepair(repairs, path .. "." .. tostring(key), "inconnu")
		end
	end
	return result
end

local function sanitizeVariants(value: any, path: string, max: number, repairs: { string }): { [string]: number }
	local result: { [string]: number } = {}
	if value == nil then
		addRepair(repairs, path, "manquant")
		return result
	end
	if type(value) ~= "table" then
		addRepair(repairs, path, "invalide")
		return result
	end
	local total, dropped, normalized = 0, 0, false
	for key, entry in value do
		local id = if type(key) == "string" then toId(key) else nil
		local index = toFiniteNumber(entry)
		if id == nil or index == nil then
			dropped += 1
			continue
		end
		local whole = math.floor(index)
		if whole < 1 or whole > LIMITS.MaxVariantIndex or total >= max then
			dropped += 1
		else
			result[id] = whole
			total += 1
			if whole ~= entry then
				normalized = true
			end
		end
	end
	if dropped > 0 then
		addRepair(repairs, path, "retirés " .. dropped)
	end
	if normalized then
		addRepair(repairs, path, "normalisé")
	end
	return result
end

local function sanitizeLoadoutName(value: any): (string, boolean)
	if value == nil or value == "" then
		return "", true
	end
	if type(value) == "string" and #value <= LIMITS.MaxLoadoutNameBytes and string.find(value, "%c") == nil then
		local characters = utf8.len(value)
		if characters ~= nil and characters <= LIMITS.MaxLoadoutNameLength then
			return value, true
		end
	end
	return "", false
end

local function sanitizeLoadout(value: any, index: number, repairs: { string }): Loadout
	if value == nil or value == false then
		return Schema.emptyLoadout() -- emplacement vide
	end
	local path = "loadouts[" .. index .. "]"
	if type(value) ~= "table" then
		addRepair(repairs, path, "invalide")
		return Schema.emptyLoadout()
	end
	local name, nameValid = sanitizeLoadoutName(value.name)
	if not nameValid then
		addRepair(repairs, path .. ".name", "invalide")
	end
	local savedAt = 0
	if value.savedAt ~= nil then
		local number = toFiniteNumber(value.savedAt)
		if number ~= nil and number >= 0 then
			savedAt = number
			if number ~= value.savedAt then
				addRepair(repairs, path .. ".savedAt", "normalisé")
			end
		else
			addRepair(repairs, path .. ".savedAt", "invalide")
		end
	end
	return {
		name = name,
		savedAt = savedAt,
		equipped = sanitizeEquipped(value.equipped, path .. ".equipped", repairs),
		variants = sanitizeVariants(value.variants, path .. ".variants", LIMITS.MaxLoadoutVariants, repairs),
	}
end

local function sanitizeLoadouts(value: any, repairs: { string }): { Loadout }
	local source: { [any]: any } = {}
	if value == nil then
		addRepair(repairs, "loadouts", "manquant")
	elseif type(value) ~= "table" then
		addRepair(repairs, "loadouts", "invalide")
	else
		source = value
	end
	local last, dropped = 0, 0
	for key in source do
		local index = if type(key) == "number" then key elseif type(key) == "string" then tonumber(key) else nil
		if index ~= nil and index >= 1 and index == math.floor(index) and index <= LIMITS.MaxStoredLoadouts then
			if index > last then
				last = index
			end
		else
			dropped += 1
		end
	end
	if dropped > 0 then
		addRepair(repairs, "loadouts", "retirés " .. dropped)
	end
	local result: { Loadout } = {}
	for index = 1, math.max(last, LIMITS.Loadouts) do
		local entry = source[index]
		if entry == nil then
			entry = source[tostring(index)]
		end
		result[index] = sanitizeLoadout(entry, index, repairs)
	end
	return result
end

local function sanitizeAchievements(value: any, repairs: { string }): { [string]: AchievementRecord }
	local result: { [string]: AchievementRecord } = {}
	if value == nil then
		addRepair(repairs, "achievements", "manquant")
		return result
	end
	if type(value) ~= "table" then
		addRepair(repairs, "achievements", "invalide")
		return result
	end
	local total, dropped, normalized = 0, 0, false
	for key, entry in value do
		local id: string? = nil
		local record: AchievementRecord? = nil
		if type(key) == "number" then
			id = toId(entry) -- ancienne forme liste des défis réussis
			record = { done = true }
			normalized = true
		else
			id = toId(key)
			if entry == true then
				record = { done = true }
				normalized = true
			elseif isFinite(entry) then
				record = { done = true, at = if entry >= 0 then entry else nil }
				normalized = true
			elseif type(entry) == "table" then
				local at = toFiniteNumber(entry.at)
				if at ~= nil and at < 0 then
					at = nil
				end
				if entry.at ~= nil and at ~= entry.at then
					normalized = true
				end
				local done = entry.done
				if type(done) ~= "boolean" then
					done = at ~= nil -- un horodatage seul signifie « réussi »
					normalized = true
				end
				record = { done = done, at = at }
			end
		end
		if id == nil or record == nil then
			dropped += 1
			continue
		end
		local existing = result[id]
		if existing == nil then
			if total < LIMITS.MaxAchievements then
				result[id] = record
				total += 1
			else
				dropped += 1
			end
		elseif record.done and not existing.done then
			result[id] = record -- doublon : la version réussie l'emporte
		end
	end
	if dropped > 0 then
		addRepair(repairs, "achievements", "retirés " .. dropped)
	end
	if normalized then
		addRepair(repairs, "achievements", "normalisé")
	end
	return result
end

-- Retourne aussi un éventuel stats.bestSolo (table écrite au mauvais endroit) pour le déplacer.
local function sanitizeStats(value: any, repairs: { string }): ({ [string]: number }, any)
	local result = defaultStats()
	if value == nil then
		addRepair(repairs, "stats", "manquant")
		return result, nil
	end
	if type(value) ~= "table" then
		addRepair(repairs, "stats", "invalide")
		return result, nil
	end
	local total = count(result)
	local legacyBestSolo: any = nil
	local dropped, normalized = 0, false
	for key, entry in value do
		local name = toId(key)
		if name == "bestSolo" and type(entry) == "table" then
			legacyBestSolo = entry
			addRepair(repairs, "stats.bestSolo", "déplacé vers bestSolo")
			continue
		end
		local number = toFiniteNumber(entry)
		if name == nil or number == nil then
			dropped += 1
			continue
		end
		if result[name] == nil then
			if total >= LIMITS.MaxStats then
				dropped += 1
				continue
			end
			total += 1
		end
		local clamped = math.clamp(number, -LIMITS.MaxStatValue, LIMITS.MaxStatValue)
		result[name] = clamped
		if clamped ~= entry or type(key) ~= "string" then
			normalized = true
		end
	end
	if dropped > 0 then
		addRepair(repairs, "stats", "retirés " .. dropped)
	end
	if normalized then
		addRepair(repairs, "stats", "normalisé")
	end
	return result, legacyBestSolo
end

local function sanitizeSets(value: any, repairs: { string }): { [string]: { [string]: boolean } }
	local result: { [string]: { [string]: boolean } } = {}
	if value == nil then
		addRepair(repairs, "sets", "manquant")
		return result
	end
	if type(value) ~= "table" then
		addRepair(repairs, "sets", "invalide")
		return result
	end
	local total, dropped = 0, 0
	for key, entries in value do
		local name = toId(key)
		if name == nil or type(entries) ~= "table" or result[name] ~= nil or total >= LIMITS.MaxSets then
			dropped += 1
			continue
		end
		result[name] = sanitizeIdSet(entries, "sets." .. name, LIMITS.MaxSetEntries, repairs)
		total += 1
		if type(key) ~= "string" then
			addRepair(repairs, "sets." .. name, "normalisé")
		end
	end
	if dropped > 0 then
		addRepair(repairs, "sets", "retirés " .. dropped)
	end
	return result
end

local function sanitizeSoloRecord(entry: any): SoloRecord?
	if type(entry) ~= "table" then
		return nil
	end
	local strokes = toFiniteNumber(entry.strokes)
	local duration = toFiniteNumber(entry.time)
	if strokes == nil or duration == nil or strokes < 1 or duration < 0 then
		return nil
	end
	return {
		strokes = math.clamp(math.floor(strokes), 1, LIMITS.MaxSoloStrokes),
		time = math.clamp(duration, 0, LIMITS.MaxSoloTime),
	}
end

-- Meilleur record : moins de coups, puis temps plus court (docs/REGLES_SCORE.md §7).
function Schema.isBetterSolo(candidate: SoloRecord, current: SoloRecord?): boolean
	if current == nil then
		return true
	end
	if candidate.strokes ~= current.strokes then
		return candidate.strokes < current.strokes
	end
	return candidate.time < current.time
end

local function sanitizeBestSolo(value: any, legacy: any, repairs: { string }): { [string]: SoloRecord }
	local result: { [string]: SoloRecord } = {}
	local total = 0
	local function absorb(source: { [any]: any }, path: string)
		local dropped, normalized = 0, false
		for key, entry in source do
			local id = toId(key)
			local record = if id ~= nil then sanitizeSoloRecord(entry) else nil
			if id == nil or record == nil then
				dropped += 1
				continue
			end
			if record.strokes ~= entry.strokes or record.time ~= entry.time or type(key) ~= "string" then
				normalized = true
			end
			local existing = result[id]
			if existing == nil then
				if total < LIMITS.MaxBestSolo then
					result[id] = record
					total += 1
				else
					dropped += 1
				end
			elseif Schema.isBetterSolo(record, existing) then
				result[id] = record
			end
		end
		if dropped > 0 then
			addRepair(repairs, path, "retirés " .. dropped)
		end
		if normalized then
			addRepair(repairs, path, "normalisé")
		end
	end
	if value == nil then
		addRepair(repairs, "bestSolo", "manquant")
	elseif type(value) ~= "table" then
		addRepair(repairs, "bestSolo", "invalide")
	else
		absorb(value, "bestSolo")
	end
	if type(legacy) == "table" then
		absorb(legacy, "stats.bestSolo")
	end
	return result
end

local function sanitizeSettings(value: any, repairs: { string }): Settings
	local result = Schema.defaultSettings()
	if value == nil then
		addRepair(repairs, "settings", "manquant")
		return result
	end
	if type(value) ~= "table" then
		addRepair(repairs, "settings", "invalide")
		return result
	end
	local writable = result :: any
	for key, raw in value do
		local spec = if type(key) == "string" then SETTINGS[key] else nil
		if spec == nil then
			addRepair(repairs, "settings." .. tostring(key), "inconnu")
			continue
		end
		local ok, coerced = coerceSetting(spec, raw, true)
		if ok then
			writable[key] = coerced
			if coerced ~= raw then
				addRepair(repairs, "settings." .. key, "normalisé")
			end
		else
			addRepair(repairs, "settings." .. key, "invalide")
		end
	end
	return result
end

local function sanitizeProcessedOps(value: any, repairs: { string }): { ProcessedOp }
	local result: { ProcessedOp } = {}
	if value == nil then
		addRepair(repairs, "processedOps", "manquant")
		return result
	end
	if type(value) ~= "table" then
		addRepair(repairs, "processedOps", "invalide")
		return result
	end
	local positions: { [string]: number } = {}
	local dropped, normalized = 0, false
	local function push(id: any, at: any)
		if not isCleanString(id, LIMITS.MaxOpIdLength) then
			dropped += 1
			return
		end
		local opId: string = id
		local stamp = toFiniteNumber(at)
		if stamp == nil or stamp < 0 then
			stamp = 0
			normalized = true
		elseif stamp ~= at then
			normalized = true
		end
		local time: number = stamp :: number
		local position = positions[opId]
		if position ~= nil then
			local existing = result[position]
			if time > existing.at then
				existing.at = time
			end
			normalized = true -- doublon fusionné
		else
			table.insert(result, { id = opId, at = time })
			positions[opId] = #result
		end
	end
	-- Forme canonique : liste { { id, at } } dans l'ordre d'application ; tolère { "id" } et { [id] = at }.
	local indices: { number } = {}
	local named: { { id: string, at: number } } = {}
	for key, entry in value do
		if type(key) == "number" then
			table.insert(indices, key)
		elseif type(key) == "string" then
			table.insert(named, { id = key, at = toFiniteNumber(entry) or 0 })
			normalized = true
		else
			dropped += 1
		end
	end
	table.sort(indices)
	for _, index in indices do
		local entry = value[index]
		if type(entry) == "table" then
			push(entry.id, entry.at)
		elseif type(entry) == "string" then
			push(entry, 0)
			normalized = true
		else
			dropped += 1
		end
	end
	table.sort(named, function(a, b)
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.id < b.id
	end)
	for _, entry in named do
		push(entry.id, entry.at)
	end
	if dropped > 0 then
		addRepair(repairs, "processedOps", "retirés " .. dropped)
	end
	if normalized then
		addRepair(repairs, "processedOps", "normalisé")
	end
	local excess = #result - LIMITS.MaxProcessedOps
	if excess > 0 then
		-- liste bornée : on oublie les plus anciennes (début de liste)
		result = table.move(result, excess + 1, #result, 1, {})
		addRepair(repairs, "processedOps", "tronqué " .. excess)
	end
	return result
end

local function sanitizeBoolean(value: any, path: string, default: boolean, repairs: { string }): boolean
	if type(value) == "boolean" then
		return value
	end
	if value == nil then
		addRepair(repairs, path, "manquant")
		return default
	end
	addRepair(repairs, path, "invalide")
	return value == 1 or value == "true"
end

local function sanitizeTime(value: any, path: string, fallback: number, repairs: { string }): number
	local number = toFiniteNumber(value)
	if number ~= nil and number >= 0 then
		if number ~= value then
			addRepair(repairs, path, "normalisé")
		end
		return number
	end
	addRepair(repairs, path, if value == nil then "manquant" else "invalide")
	return fallback
end

-- Copie d'une valeur sérialisable en JSON (types simples, tables sans cycle, tableaux contigus ou
-- dictionnaires à clés texte, profondeur bornée) ; (false, nil) si la valeur ne l'est pas.
local function jsonSafeCopy(value: any, depth: number, seen: { [any]: boolean }): (boolean, any)
	local kind = type(value)
	if kind == "boolean" then
		return true, value
	elseif kind == "number" then
		return isFinite(value), value
	elseif kind == "string" then
		return utf8.len(value) ~= nil, value
	elseif kind ~= "table" or depth > LIMITS.MaxExtraDepth or seen[value] then
		return false, nil
	end
	seen[value] = true
	local copy: { [any]: any } = {}
	local hasText, numeric = false, 0
	local valid = true
	for key, child in value do
		if type(key) == "string" and utf8.len(key) ~= nil then
			hasText = true
		elseif type(key) == "number" and key >= 1 and key == math.floor(key) then
			numeric += 1
		else
			valid = false
			break
		end
		local ok, childCopy = jsonSafeCopy(child, depth + 1, seen)
		if not ok then
			valid = false
			break
		end
		copy[key] = childCopy
	end
	seen[value] = nil
	if not valid or (hasText and numeric > 0) then
		return false, nil
	end
	for index = 1, numeric do
		if copy[index] == nil then
			return false, nil -- tableau à trous : non sérialisable tel quel
		end
	end
	return true, copy
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function Schema.isId(value: any, maxBytes: number?): boolean
	return type(value) == "string" and isCleanString(value, maxBytes or LIMITS.MaxIdLength)
end

function Schema.sanitize(data: any, now: number?): (Profile, { string })
	local repairs: { string } = {}
	local clock = if isFinite(now) then now :: number else os.time()
	local source: { [any]: any } = {}
	if type(data) == "table" then
		source = data
		if data.version ~= CURRENT_VERSION then
			addRepair(repairs, "version", "corrigée")
		end
	else
		addRepair(repairs, "profil", if data == nil then "manquant" else "invalide")
	end

	local stats, legacyBestSolo = sanitizeStats(source.stats, repairs)
	local createdAt = sanitizeTime(source.createdAt, "createdAt", clock, repairs)
	local profile: Profile = {
		version = CURRENT_VERSION,
		coins = sanitizeCoins(source.coins, repairs),
		owned = sanitizeIdSet(source.owned, "owned", LIMITS.MaxOwned, repairs),
		equipped = sanitizeEquipped(source.equipped, "equipped", repairs),
		variants = sanitizeVariants(source.variants, "variants", LIMITS.MaxVariants, repairs),
		loadouts = sanitizeLoadouts(source.loadouts, repairs),
		achievements = sanitizeAchievements(source.achievements, repairs),
		stats = stats,
		sets = sanitizeSets(source.sets, repairs),
		events = sanitizeIdSet(source.events, "events", LIMITS.MaxEvents, repairs),
		bestSolo = sanitizeBestSolo(source.bestSolo, legacyBestSolo, repairs),
		settings = sanitizeSettings(source.settings, repairs),
		processedOps = sanitizeProcessedOps(source.processedOps, repairs),
		tutorialDone = sanitizeBoolean(source.tutorialDone, "tutorialDone", false, repairs),
		createdAt = createdAt,
		updatedAt = sanitizeTime(source.updatedAt, "updatedAt", createdAt, repairs),
	}

	-- Champs inconnus : conservés s'ils sont sérialisables (données d'un autre service ou d'une autre version).
	local extras = 0
	local writable = profile :: any
	for key, value in source do
		if type(key) == "string" and KNOWN_FIELDS[key] then
			continue
		end
		if extras < LIMITS.MaxExtraFields and Schema.isId(key) then
			local ok, copy = jsonSafeCopy(value, 1, {})
			if ok then
				writable[key] = copy
				extras += 1
				continue
			end
		end
		addRepair(repairs, "champ " .. tostring(key), "retiré")
	end

	return profile, repairs
end

-- Préférence envoyée par le client : clé connue et valeur du bon type (bornée). (false, nil) sinon.
function Schema.validateSetting(key: any, value: any): (boolean, any)
	if type(key) ~= "string" then
		return false, nil
	end
	local spec = SETTINGS[key]
	if spec == nil then
		return false, nil
	end
	return coerceSetting(spec, value, false)
end

-- Applique un patch { clé = valeur } (Data.SaveSettings) ; retourne les clés modifiées (triées) et rejetées.
function Schema.applySettings(settings: Settings, patch: any): ({ string }, { string })
	local changed: { string } = {}
	local rejected: { string } = {}
	if type(patch) ~= "table" then
		table.insert(rejected, "*")
		return changed, rejected
	end
	local writable = settings :: any
	local seen = 0
	for key, value in patch do
		seen += 1
		if seen > LIMITS.MaxSettingsPatch then
			table.insert(rejected, "*trop de clés")
			break
		end
		local ok, normalized = Schema.validateSetting(key, value)
		if ok then
			if writable[key] ~= normalized then
				writable[key] = normalized
				table.insert(changed, key)
			end
		else
			table.insert(rejected, if type(key) == "string" then string.sub(key, 1, 32) else typeof(key))
		end
	end
	table.sort(changed)
	return changed, rejected
end

function Schema.hasOp(profile: Profile, opId: string): boolean
	for _, op in profile.processedOps do
		if op.id == opId then
			return true
		end
	end
	return false
end

-- Mémorise une opération appliquée. false si l'identifiant est invalide ou déjà connu (rien n'est fait).
function Schema.recordOp(profile: Profile, opId: string, at: number?): boolean
	if not isCleanString(opId, LIMITS.MaxOpIdLength) or Schema.hasOp(profile, opId) then
		return false
	end
	table.insert(profile.processedOps, { id = opId, at = if isFinite(at) and (at :: number) >= 0 then at :: number else os.time() })
	local ops = profile.processedOps
	while #ops > LIMITS.MaxProcessedOps do
		table.remove(ops, 1)
	end
	return true
end

-- Ajoute `amount` (1 par défaut) à un compteur ; retourne la nouvelle valeur, ou nil si refusé (clé ou montant
-- invalide, trop de compteurs).
function Schema.incrementStat(profile: Profile, key: string, amount: number?): number?
	local name = toId(key)
	local delta = if amount == nil then 1 else amount
	if name == nil or not isFinite(delta) then
		return nil
	end
	local stats = profile.stats
	local current = stats[name]
	if current == nil then
		if count(stats) >= LIMITS.MaxStats then
			return nil
		end
		current = 0
	end
	local value = math.clamp((current :: number) + delta, -LIMITS.MaxStatValue, LIMITS.MaxStatValue)
	stats[name] = value
	return value
end

-- Ajoute un élément à un ensemble (créé au besoin) ; true seulement s'il est nouveau.
function Schema.addToSet(profile: Profile, setName: string, entry: string): boolean
	local name = toId(setName)
	local id = toId(entry)
	if name == nil or id == nil then
		return false
	end
	local sets = profile.sets
	local set = sets[name]
	if set == nil then
		if count(sets) >= LIMITS.MaxSets then
			return false
		end
		set = {}
		sets[name] = set
	end
	local target = set :: { [string]: boolean }
	if target[id] or count(target) >= LIMITS.MaxSetEntries then
		return false
	end
	target[id] = true
	return true
end

-- Enregistre un trou terminé en Solo ; true si c'est un nouveau record personnel.
function Schema.recordSolo(profile: Profile, holeId: string, strokes: number, time: number): boolean
	local id = toId(holeId)
	local record = sanitizeSoloRecord({ strokes = strokes, time = time })
	if id == nil or record == nil then
		return false
	end
	local current = profile.bestSolo[id]
	if current == nil and count(profile.bestSolo) >= LIMITS.MaxBestSolo then
		return false
	end
	if not Schema.isBetterSolo(record, current) then
		return false
	end
	profile.bestSolo[id] = record
	return true
end

-- Instantané destiné au client propriétaire (Data.Sync ajoute status et persistent).
function Schema.clientView(profile: Profile): { [string]: any }
	return {
		version = profile.version,
		coins = profile.coins,
		owned = deepCopy(profile.owned),
		equipped = deepCopy(profile.equipped),
		variants = deepCopy(profile.variants),
		loadouts = deepCopy(profile.loadouts),
		achievements = deepCopy(profile.achievements),
		stats = deepCopy(profile.stats),
		sets = deepCopy(profile.sets),
		events = deepCopy(profile.events),
		bestSolo = deepCopy(profile.bestSolo),
		settings = deepCopy(profile.settings),
		tutorialDone = profile.tutorialDone,
		createdAt = profile.createdAt,
	}
end

return Schema
