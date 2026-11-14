--!strict
--[[
	Club-Fusée (rocket_club) — l'effet dépend de la situation :
	  1. en visée / charge de coup : le prochain tir est ×1,6 plus puissant (BallService.SetShotBoost, 10 s) ;
	  2. sinon, un adversaire dans le cône de 60° à moins de 7 studs : frappe majeure ;
	  3. sinon, élan vers l'avant à 80 studs/s pendant 0,4 s (exemption de plausibilité).
	Le plongeon évite la frappe ; la bulle est détruite par la frappe majeure (CombatService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Config.Items)
local ItemGeometry = require(ReplicatedStorage.Shared.Logic.ItemGeometry)
local Kit = require(script.Parent.Kit)

local DEF = Items.ById.rocket_club
local P = DEF.params

local RocketClub = { Id = "rocket_club" }

function RocketClub.Use(_ctx: any, player: Player, payload: any): (boolean, string?)
	local origin = Kit.chest(player)
	if not origin then
		return false, "item.fb.state"
	end
	local aim: Vector3 = payload.aim
	local ball = Kit.service("BallService")

	-- 1. Boost de tir.
	if ball and type(ball.IsAiming) == "function" and type(ball.SetShotBoost) == "function" then
		local aiming = ball.IsAiming(player) or (type(ball.IsCharging) == "function" and ball.IsCharging(player))
		if aiming and ball.SetShotBoost(player, P.ShotPowerMultiplier, DEF.duration) then
			Kit.burst(origin, 3, DEF.color, 0.4)
			return true, nil
		end
	end

	-- 2. Frappe au corps à corps.
	local combat = Kit.service("CombatService")
	local struck = false
	for _, victim in Kit.opponents(player) do
		local chest = Kit.chest(victim)
		if not chest or not ItemGeometry.inCone(origin, aim, chest, P.MeleeConeDegrees / 2, DEF.range) then
			continue
		end
		if combat and type(combat.IsDodging) == "function" and combat.IsDodging(victim) then
			continue
		end
		if Kit.strike(player, victim, { source = "rocket_club", major = true, duration = 2.5, knock = Kit.knock(origin, chest, 85, 25) }) ~= "refused" then
			struck = true
		end
	end
	if struck then
		Kit.burst(origin + aim * 3, 4, DEF.color, 0.3)
		return true, nil
	end

	-- 3. Élan.
	local movement = Kit.service("MovementService")
	if movement and type(movement.AllowDisplacement) == "function" then
		movement.AllowDisplacement(player, P.DashSeconds + 0.4, "rocket_club")
	end
	local flat = ItemGeometry.flat(aim)
	if flat.Magnitude < 1e-3 then
		return false, "item.fb.state"
	end
	Kit.push(player, player, flat.Unit * P.DashSpeed + Vector3.new(0, 4, 0), "rocket_club_dash")
	Kit.burst(origin - flat.Unit * 2, 3, DEF.color, 0.3)
	return true, nil
end

return RocketClub
