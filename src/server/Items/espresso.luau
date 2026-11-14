--!strict
--[[
	Expresso Turbo (espresso) — vitesse ×1,45 et saut ×1,15 pendant 8 s. Réutiliser rafraîchit la durée sans cumul
	(même clé de modificateur dans MovementService). Retiré à la réapparition, en fin de trou, à la déconnexion
	(ItemService.ClearEffects). Le gel l'emporte : MovementService verrouille alors tout déplacement.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Kit = require(script.Parent.Kit)

local DEF = Items.ById.espresso
local P = DEF.params

local Espresso = { Id = "espresso" }

function Espresso.Use(ctx: any, player: Player, _payload: any): (boolean, string?)
	local movement = Kit.service("MovementService")
	if not movement or type(movement.SetModifier) ~= "function" then
		return false, "item.fb.unavailable"
	end
	movement.SetModifier(player, "espresso", P.SpeedMultiplier, P.JumpMultiplier, DEF.duration)
	ctx.addEffect(player, "espresso", DEF.duration, function()
		movement.ClearModifier(player, "espresso")
	end)
	return true, nil
end

return Espresso
