--!strict
--[[
	Corne Tonitruante (horn) — après une annonce de 0,4 s, les adversaires à moins de 45 studs :
	  - chargent leur frappe  -> frappe prématurée (BallService.ForceShot) ;
	  - visent sans charger   -> visée annulée et bloquée 1,5 s ;
	  - ont un objet sensible au klaxon sélectionné -> 35 % de chance de l'utiliser involontairement.
	La Bulle Magnétique ignore la corne (aucun effet, charge non consommée). Les alliés ne sont pas affectés.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Kit = require(script.Parent.Kit)

local DEF = Items.ById.horn
local P = DEF.params

local Horn = { Id = "horn" }

function Horn.Use(ctx: any, player: Player, _payload: any): (boolean, string?)
	local root = Kit.root(player)
	if not root then
		return false, "item.fb.state"
	end
	Kit.burst(root.Position + Vector3.new(0, 2, 0), 6, DEF.color, DEF.windup)
	ctx.after(ctx.playerTrove(player), DEF.windup, function()
		local origin = Kit.root(player)
		if not origin then
			return
		end
		Kit.burst(origin.Position + Vector3.new(0, 2, 0), DEF.range * 0.4, DEF.color, 0.5)
		local ball = Kit.service("BallService")
		for _, victim in Kit.opponents(player) do
			local victimRoot = Kit.root(victim)
			if not victimRoot or (victimRoot.Position - origin.Position).Magnitude > DEF.range then
				continue
			end
			if ctx.shieldCharges(victim) > 0 then
				continue -- la bulle ignore la corne
			end
			if ball and type(ball.IsCharging) == "function" and ball.IsCharging(victim) then
				if type(ball.ForceShot) == "function" and ball.ForceShot(victim, "horn") then
					ctx.record(player, "hornForcedShots", 1)
				end
			elseif ball and type(ball.IsAiming) == "function" and ball.IsAiming(victim) then
				if type(ball.CancelAim) == "function" then
					ball.CancelAim(victim, "horn", P.AimBlockSeconds)
				end
			elseif ctx.rng:NextNumber() < P.AccidentalUseChance then
				ctx.forceUse(victim, "horn")
			end
		end
	end)
	return true, nil
end

return Horn
