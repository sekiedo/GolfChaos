--!strict
--[[
	Bottes Kangourou (kangaroo_boots) — 3 bonds géants (saut ×2,6) dans les 15 s ; contrôle aérien normal ;
	exemption de plausibilité pendant l'effet. Fin après le 3e bond ou au bout de 15 s ; retiré à la réapparition,
	en fin de trou et à la déconnexion.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Kit = require(script.Parent.Kit)

local DEF = Items.ById.kangaroo_boots
local P = DEF.params
local LAST_BOUND_GRACE = 0.6

local KangarooBoots = { Id = "kangaroo_boots" }

function KangarooBoots.Use(ctx: any, player: Player, _payload: any): (boolean, string?)
	local movement = Kit.service("MovementService")
	local _, humanoid = Kit.character(player)
	if not movement or type(movement.SetModifier) ~= "function" or not humanoid then
		return false, "item.fb.unavailable"
	end
	movement.SetModifier(player, "kangaroo", 1, P.JumpMultiplier, DEF.duration)
	if type(movement.AllowDisplacement) == "function" then
		movement.AllowDisplacement(player, DEF.duration, "kangaroo")
	end
	local bounds = 0
	local connection = humanoid.StateChanged:Connect(function(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
		if new ~= Enum.HumanoidStateType.Jumping then
			return
		end
		bounds += 1
		if bounds >= P.Bounds then
			ctx.after(ctx.playerTrove(player), LAST_BOUND_GRACE, function()
				ctx.clearEffect(player, "kangaroo")
			end)
		end
	end)
	ctx.addEffect(player, "kangaroo", DEF.duration, function()
		connection:Disconnect()
		movement.ClearModifier(player, "kangaroo")
	end)
	return true, nil
end

return KangarooBoots
