--!strict
--[[
	ProfileOps — modifications ATOMIQUES d'un profil en mémoire. SERVEUR uniquement. Module PUR (aucun effet au
	require, aucune requête, aucun yield) : utilisé par PlayerDataService et testable seul.

	Les deux fonctions travaillent sur une COPIE du profil : le profil d'origine n'est jamais modifié, l'appelant
	remplace son profil par la copie renvoyée seulement en cas de succès (tout ou rien).

	  ProfileOps.update(profile, fn(data) -> ...any) -> (boolean, Profile?, string?, string?)
	      (true, copieModifiée)            fn s'est exécutée sans renvoyer false
	      (false, nil, raison?)            fn a renvoyé false (raison = son 2e résultat s'il est textuel)
	      (false, nil, "error", message)   fn a levé une erreur
	  ProfileOps.transact(profile, opId, fn(data) -> (boolean, string?)) -> (boolean, Profile?, string?, string?)
	      (true, copieModifiée)            fn a renvoyé true ; opId est mémorisé dans la copie (Schema.recordOp)
	      (false, nil, "duplicate")        opId déjà appliqué : rien n'est rejoué
	      (false, nil, "invalid_op")       identifiant vide, trop long ou non textuel
	      (false, nil, raison)             refus métier de fn ("refused" par défaut) : opId N'EST PAS mémorisé,
	                                       l'opération pourra donc réussir plus tard (défi pas encore atteint)
	      (false, nil, "error", message)   fn a levé une erreur
	  ProfileOps.clampCoins(value) -> entier dans 0..Economy.MaxCoins
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Schema = require(script.Parent.Schema)

type Profile = Schema.Profile

local ProfileOps = {}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = deepCopy(item)
	end
	return copy
end

function ProfileOps.clampCoins(value: any): number
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, Economy.MaxCoins)
end

local function finish(draft: any): Profile
	draft.coins = ProfileOps.clampCoins(draft.coins)
	return draft
end

function ProfileOps.update(profile: Profile, fn: (data: any) -> ...any): (boolean, Profile?, string?, string?)
	local draft = deepCopy(profile)
	local ok, result, reason = pcall(fn, draft)
	if not ok then
		return false, nil, "error", tostring(result)
	end
	if result == false then
		return false, nil, if type(reason) == "string" then reason else nil, nil
	end
	return true, finish(draft), nil, nil
end

function ProfileOps.transact(profile: Profile, opId: string, fn: (data: any) -> (boolean, string?)): (boolean, Profile?, string?, string?)
	if type(opId) ~= "string" or opId == "" or #opId > Schema.Limits.MaxOpIdLength then
		return false, nil, "invalid_op", nil
	end
	if Schema.hasOp(profile, opId) then
		return false, nil, "duplicate", nil
	end
	local draft = deepCopy(profile)
	local ok, result, reason = pcall(fn, draft)
	if not ok then
		return false, nil, "error", tostring(result)
	end
	if result ~= true then
		return false, nil, if type(reason) == "string" then reason else "refused", nil
	end
	if not Schema.recordOp(draft, opId) then
		return false, nil, "invalid_op", nil
	end
	return true, finish(draft), nil, nil
end

return ProfileOps
