--!strict
--[[
	Validate : contrôles de types et de bornes pour toute donnée venant d'un client
	(ou d'une sauvegarde). Un exploiteur peut envoyer nil, NaN, ±inf, des Vector3 géants,
	des tables cycliques, des chaînes énormes : on vérifie AVANT toute utilisation.

	checkArgs(spec, ...) vérifie une liste d'arguments selon une spécification :
	  "string"      chaîne, longueur <= 200            "string:32"  longueur <= 32
	  "number"      nombre fini                         "integer"    entier fini
	  "boolean"     booléen                             "Vector3"    Vector3 aux composantes finies
	  "Vector2"     Vector2 fini                        "CFrame"     CFrame fini
	  "table"       table (non vide ou vide)            "any"        aucune vérification
	  suffixe "?"   argument facultatif (nil accepté), ex. "number?"
]]

local Validate = {}

local DEFAULT_MAX_STRING = 200

function Validate.isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Validate.isInteger(value: any): boolean
	return Validate.isFiniteNumber(value) and math.floor(value) == value
end

function Validate.isFiniteVector3(value: any): boolean
	return typeof(value) == "Vector3"
		and Validate.isFiniteNumber(value.X)
		and Validate.isFiniteNumber(value.Y)
		and Validate.isFiniteNumber(value.Z)
end

function Validate.isFiniteVector2(value: any): boolean
	return typeof(value) == "Vector2" and Validate.isFiniteNumber(value.X) and Validate.isFiniteNumber(value.Y)
end

function Validate.isFiniteCFrame(value: any): boolean
	if typeof(value) ~= "CFrame" then
		return false
	end
	for _, component in { value:GetComponents() } do
		if not Validate.isFiniteNumber(component) then
			return false
		end
	end
	return true
end

function Validate.isString(value: any, maxLength: number?): boolean
	return type(value) == "string" and #value <= (maxLength or DEFAULT_MAX_STRING)
end

-- Retourne un nombre fini borné, ou `default` si la valeur est invalide.
function Validate.clampNumber(value: any, min: number, max: number, default: number): number
	if not Validate.isFiniteNumber(value) then
		return default
	end
	return math.clamp(value, min, max)
end

-- `allowed` : tableau de valeurs ou dictionnaire { [valeur] = true }.
function Validate.isOneOf(value: any, allowed: { [any]: any }): boolean
	if allowed[value] == true then
		return true
	end
	return table.find(allowed :: { any }, value) ~= nil
end

-- Direction horizontale unitaire, ou nil si le vecteur est invalide ou presque nul.
function Validate.flatUnit(value: any, minMagnitude: number?): Vector3?
	if not Validate.isFiniteVector3(value) then
		return nil
	end
	local flat = Vector3.new(value.X, 0, value.Z)
	if flat.Magnitude < (minMagnitude or 0.05) then
		return nil
	end
	return flat.Unit
end

-- Direction 3D unitaire, ou nil.
function Validate.unit(value: any, minMagnitude: number?): Vector3?
	if not Validate.isFiniteVector3(value) then
		return nil
	end
	if value.Magnitude < (minMagnitude or 0.05) then
		return nil
	end
	return value.Unit
end

local function checkOne(kind: string, value: any): boolean
	local base, parameter = string.match(kind, "^(%a+%d?):?(%d*)$")
	if not base then
		return false
	end
	if base == "any" then
		return true
	elseif base == "string" then
		local limit = if parameter ~= "" then tonumber(parameter) else nil
		return Validate.isString(value, limit)
	elseif base == "number" then
		return Validate.isFiniteNumber(value)
	elseif base == "integer" then
		return Validate.isInteger(value)
	elseif base == "boolean" then
		return type(value) == "boolean"
	elseif base == "Vector3" then
		return Validate.isFiniteVector3(value)
	elseif base == "Vector2" then
		return Validate.isFiniteVector2(value)
	elseif base == "CFrame" then
		return Validate.isFiniteCFrame(value)
	elseif base == "table" then
		return type(value) == "table"
	end
	return false
end

-- Vérifie les arguments selon `spec`. Retourne (true) ou (false, message).
function Validate.checkArgs(spec: { string }, ...: any): (boolean, string?)
	local count = select("#", ...)
	if count > #spec then
		return false, string.format("trop d'arguments (%d > %d)", count, #spec)
	end
	for index, rawKind in spec do
		local value = (select(index, ...))
		local optional = string.sub(rawKind, -1) == "?"
		local kind = if optional then string.sub(rawKind, 1, -2) else rawKind
		if value == nil then
			if not optional then
				return false, string.format("argument %d manquant (%s)", index, kind)
			end
		elseif not checkOne(kind, value) then
			return false, string.format("argument %d invalide (attendu %s, reçu %s)", index, kind, typeof(value))
		end
	end
	return true, nil
end

return Validate
