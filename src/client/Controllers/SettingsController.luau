--!strict
--[[
	SettingsController — préférences du joueur local (contrat docs/ARCHITECTURE.md §9).

	  SettingsController.Get(clé) -> valeur              (valeur par défaut tant que rien n'est chargé)
	  SettingsController.Set(clé, valeur) -> boolean     valide, applique tout de suite, enregistre (différé)
	  SettingsController.Reset()                         remet les valeurs par défaut
	  SettingsController.GetAll() -> { [clé]: valeur }   copie
	  SettingsController.GetSpec(clé) -> Spec?           bornes / valeurs permises (pour l'écran Réglages)
	  SettingsController.IsSynced(clé) -> boolean        clé enregistrée dans le profil (Schema.SettingKeys)
	  SettingsController.Changed : Signal(clé, valeur, ancienne)
	  SettingsController.Loaded  : Signal()              premier Data.Sync reçu

	Clés synchronisées avec le profil (doivent rester identiques à server/Data/Schema.SettingKeys) :
	  masterVolume, musicVolume, sfxVolume, sensitivity, cameraShake (0..1), vibration, reducedEffects, noFlash,
	  language ("fr" | "en"), quality ("Auto" | "Low" | "Medium" | "High").
	Clés locales (session uniquement, absentes du schéma serveur) : uiVolume, invertY, textSize.

	Application immédiate : langue (Locale.setLanguage) ; volumes, qualité, effets réduits et sans flash sont lus
	par EffectsController / CameraController / Theme via Get et Changed. Les valeurs reçues par Data.Sync ne sont
	pas renvoyées au serveur ; les changements locaux partent par Data.SaveSettings (regroupés, 1,5 s après le
	dernier changement, au plus 1 message/s).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Log = require(Shared.Util.Log)
local Locale = require(Shared.Locale)

export type Spec = {
	kind: "number" | "boolean" | "enum",
	default: any,
	min: number?,
	max: number?,
	step: number?,
	values: { string }?,
	synced: boolean,
}

local SettingsController = {}
SettingsController.Priority = 5

SettingsController.Changed = Signal.new()
SettingsController.Loaded = Signal.new()

-- Bornes alignées sur server/Data/Schema.luau (le serveur revalide de toute façon chaque clé).
local SPECS: { [string]: Spec } = {
	masterVolume = { kind = "number", default = 1, min = 0, max = 1, step = 0.05, synced = true },
	musicVolume = { kind = "number", default = 0.8, min = 0, max = 1, step = 0.05, synced = true },
	sfxVolume = { kind = "number", default = 1, min = 0, max = 1, step = 0.05, synced = true },
	sensitivity = { kind = "number", default = 1, min = 0.1, max = 4, step = 0.05, synced = true },
	cameraShake = { kind = "number", default = 1, min = 0, max = 1, step = 0.1, synced = true },
	vibration = { kind = "boolean", default = true, synced = true },
	reducedEffects = { kind = "boolean", default = false, synced = true },
	noFlash = { kind = "boolean", default = false, synced = true },
	language = { kind = "enum", default = "fr", values = { "fr", "en" }, synced = true },
	quality = { kind = "enum", default = "Auto", values = { "Auto", "Low", "Medium", "High" }, synced = true },
	-- Locales (à ajouter au schéma serveur pour les conserver entre les sessions).
	uiVolume = { kind = "number", default = 1, min = 0, max = 1, step = 0.05, synced = false },
	invertY = { kind = "boolean", default = false, synced = false },
	textSize = { kind = "enum", default = "Normal", values = { "Normal", "Large", "Larger" }, synced = false },
}

local SAVE_DELAY = 1.5
local SAVE_MIN_INTERVAL = 1.05
local SYNC_RETRY_DELAY = 6

local values: { [string]: any } = {}
local pending: { [string]: any } = {}
local saveToken = 0
local lastSaveAt = -math.huge
local loaded = false

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Valeur normalisée selon la spécification, ou nil si inacceptable.
local function normalize(spec: Spec, value: any): any
	if spec.kind == "number" then
		if type(value) == "boolean" then
			value = if value then spec.max else spec.min
		end
		if not isFinite(value) then
			return nil
		end
		local minimum = spec.min or -math.huge
		local maximum = spec.max or math.huge
		local result = math.clamp(value, minimum, maximum)
		local step = spec.step
		if step and step > 0 then
			result = minimum + math.floor((result - minimum) / step + 0.5) * step
			result = math.clamp(math.floor(result * 10000 + 0.5) / 10000, minimum, maximum)
		end
		return result
	elseif spec.kind == "boolean" then
		return if type(value) == "boolean" then value else nil
	else
		if type(value) ~= "string" then
			return nil
		end
		local allowed = spec.values or {}
		if table.find(allowed, value) then
			return value
		end
		-- Langue : accepte "fr-FR", "en_us"...
		local short = string.lower(string.sub(value, 1, 2))
		if table.find(allowed, short) then
			return short
		end
		return nil
	end
end

local function apply(key: string, value: any)
	if key == "language" and type(value) == "string" then
		Locale.setLanguage(value)
	end
end

local function flush()
	if next(pending) == nil then
		return
	end
	local patch = pending
	pending = {}
	lastSaveAt = os.clock()
	local ok, err = pcall(Net.send, "Data.SaveSettings", patch)
	if not ok then
		Log.warn("Settings", "enregistrement impossible :", err)
		-- On réessaie au prochain changement (les valeurs restent appliquées localement).
		for key, value in patch do
			if pending[key] == nil then
				pending[key] = value
			end
		end
	end
end

local function scheduleSave()
	saveToken += 1
	local token = saveToken
	task.delay(SAVE_DELAY, function()
		if token ~= saveToken then
			return
		end
		local wait = SAVE_MIN_INTERVAL - (os.clock() - lastSaveAt)
		if wait > 0 then
			task.wait(wait)
			if token ~= saveToken then
				return
			end
		end
		flush()
	end)
end

-- Écrit une valeur déjà normalisée ; save = false pour les valeurs venues du serveur.
local function write(key: string, value: any, save: boolean)
	local old = values[key]
	if old == value then
		return
	end
	values[key] = value
	apply(key, value)
	local spec = SPECS[key]
	if save and spec and spec.synced then
		pending[key] = value
		scheduleSave()
	end
	SettingsController.Changed:Fire(key, value, old)
end

function SettingsController.Get(key: string): any
	local value = values[key]
	if value ~= nil then
		return value
	end
	local spec = SPECS[key]
	return if spec then spec.default else nil
end

function SettingsController.Set(key: string, value: any): boolean
	local spec = SPECS[key]
	if not spec then
		Log.warn("Settings", "réglage inconnu :", key)
		return false
	end
	local normalized = normalize(spec, value)
	if normalized == nil then
		return false
	end
	write(key, normalized, true)
	return true
end

function SettingsController.Reset()
	for key, spec in SPECS do
		write(key, spec.default, true)
	end
end

function SettingsController.GetAll(): { [string]: any }
	local copy = {}
	for key, spec in SPECS do
		local value = values[key]
		copy[key] = if value ~= nil then value else spec.default
	end
	return copy
end

function SettingsController.GetSpec(key: string): Spec?
	return SPECS[key]
end

function SettingsController.IsSynced(key: string): boolean
	local spec = SPECS[key]
	return spec ~= nil and spec.synced
end

function SettingsController.IsLoaded(): boolean
	return loaded
end

-- Applique les préférences d'un instantané Data.Sync (sans les renvoyer au serveur).
local function applySnapshot(settings: any)
	if type(settings) ~= "table" then
		return
	end
	for key, spec in SPECS do
		if spec.synced and pending[key] == nil then
			local normalized = normalize(spec, (settings :: any)[key])
			if normalized ~= nil then
				write(key, normalized, false)
			end
		end
	end
end

function SettingsController.Init()
	for key, spec in SPECS do
		values[key] = spec.default
	end
	apply("language", values.language)
end

function SettingsController.Start()
	local ok, err = pcall(function()
		Net.listen("Data.Sync", function(snapshot: any)
			if type(snapshot) ~= "table" then
				return
			end
			if snapshot.settings ~= nil then
				applySnapshot(snapshot.settings)
				if not loaded then
					loaded = true
					SettingsController.Loaded:Fire()
				end
			end
		end)
	end)
	if not ok then
		Log.warn("Settings", "Data.Sync indisponible :", err)
		return
	end
	-- Instantané demandé si le serveur ne l'a pas envoyé de lui-même (arrivée tardive de l'interface).
	task.delay(SYNC_RETRY_DELAY, function()
		if not loaded then
			pcall(Net.send, "Data.RequestSync")
		end
	end)
end

return SettingsController
