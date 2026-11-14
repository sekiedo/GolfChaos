--!strict
--[[
	Locale : tous les textes affichés passent par ici (interface française, traduction anglaise possible).

	  local Locale = require(ReplicatedStorage.Shared.Locale)
	  Locale.t("hud.strokes", { n = 3 })      --> "Coups : 3"   (variables {n} remplacées)
	  Locale.setLanguage("en")                 --> bascule (fr par défaut)
	  Locale.getLanguage()  /  Locale.has(key)  /  Locale.missingKeys()

	Les chaînes vivent dans Locale/fr/*.luau et Locale/en/*.luau : un fichier par domaine
	(Core, Hud, Items, Shop...), chacun retournant { ["domaine.cle"] = "texte" }.
	Une clé absente en anglais retombe sur le français ; absente partout, la clé elle-même est
	affichée (et listée par missingKeys() pour les tests).
]]

local Locale = {}

local tables: { [string]: { [string]: string } } = {}
local language = "fr"
local missing: { [string]: boolean } = {}
local changedCallbacks: { (string) -> () } = {}

local function loadLanguage(code: string)
	local folder = script:FindFirstChild(code)
	local merged: { [string]: string } = {}
	if folder then
		for _, module in folder:GetChildren() do
			if module:IsA("ModuleScript") then
				local ok, entries = pcall(require, module)
				if ok and type(entries) == "table" then
					for key, text in entries :: { [string]: string } do
						if merged[key] ~= nil then
							warn(string.format("[Locale] clé dupliquée %s (%s/%s)", key, code, module.Name))
						end
						merged[key] = text
					end
				else
					warn(string.format("[Locale] fichier illisible %s/%s : %s", code, module.Name, tostring(entries)))
				end
			end
		end
	end
	tables[code] = merged
end

loadLanguage("fr")
loadLanguage("en")

local function interpolate(text: string, vars: { [string]: any }?): string
	if not vars then
		return text
	end
	return (string.gsub(text, "{(%w+)}", function(name)
		local value = vars[name]
		if value == nil then
			return "{" .. name .. "}"
		end
		return tostring(value)
	end))
end

function Locale.t(key: string, vars: { [string]: any }?): string
	local text = tables[language] and tables[language][key]
	if text == nil and language ~= "fr" then
		text = tables.fr[key]
	end
	if text == nil then
		missing[key] = true
		return key
	end
	return interpolate(text, vars)
end

function Locale.has(key: string, code: string?): boolean
	local dict = tables[code or language]
	return dict ~= nil and dict[key] ~= nil
end

function Locale.setLanguage(code: string)
	if tables[code] and code ~= language then
		language = code
		for _, callback in changedCallbacks do
			task.spawn(callback, code)
		end
	end
end

function Locale.getLanguage(): string
	return language
end

function Locale.getLanguages(): { string }
	local list = {}
	for code in tables do
		table.insert(list, code)
	end
	table.sort(list)
	return list
end

function Locale.onLanguageChanged(callback: (string) -> ())
	table.insert(changedCallbacks, callback)
end

function Locale.missingKeys(): { string }
	local list = {}
	for key in missing do
		table.insert(list, key)
	end
	table.sort(list)
	return list
end

-- Clés présentes en français mais absentes en anglais (suivi de la traduction).
function Locale.untranslatedKeys(code: string?): { string }
	local target = tables[code or "en"] or {}
	local list = {}
	for key in tables.fr do
		if target[key] == nil then
			table.insert(list, key)
		end
	end
	table.sort(list)
	return list
end

return Locale
