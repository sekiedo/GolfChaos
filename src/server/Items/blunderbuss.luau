--!strict
--[[
	Tromblon Rebond (blunderbuss) — cône de 30° sur 25 studs : KO à moins de 12 studs, recul dégressif ; les balles
	des adversaires dans le cône sont poussées. Recul du tireur : poussée arrière ; si le tir vise le sol (inclinaison
	sous −35°) propulsion verticale (« saut au tromblon », exemption de plausibilité 1,5 s). Le plongeon évite le
	coup, un allié n'est pas affecté (Kit.opponents), la bulle absorbe. Sensible au klaxon. 2 charges, 1,2 s entre tirs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Config.Items)
local ItemGeometry = require(ReplicatedStorage.Shared.Logic.ItemGeometry)
local Kit = require(script.Parent.Kit)

local DEF = Items.ById.blunderbuss
local P = DEF.params

local Blunderbuss = { Id = "blunderbuss" }

function Blunderbuss.Use(_ctx: any, player: Player, payload: any): (boolean, string?)
	local root = Kit.root(player)
	local origin = Kit.chest(player)
	if not root or not origin then
		return false, "item.fb.state"
	end
	local aim: Vector3 = payload.aim
	local half = P.ConeDegrees / 2
	local combat = Kit.service("CombatService")
	local ball = Kit.service("BallService")

	for _, victim in Kit.opponents(player) do
		local chest = Kit.chest(victim)
		if not chest or not ItemGeometry.inCone(origin, aim, chest, half, DEF.range) then
			continue
		end
		if combat and type(combat.IsDodging) == "function" and combat.IsDodging(victim) then
			continue
		end
		if not Kit.lineOfSight(origin, chest) then
			continue
		end
		local distance = (chest - origin).Magnitude
		local speed = P.KnockbackMax * ItemGeometry.falloff(distance, P.KnockoutRange, DEF.range) + 25
		local knock = Kit.knock(origin, chest, math.min(speed, P.KnockbackMax), 12)
		if distance <= P.KnockoutRange then
			Kit.strike(player, victim, { source = "blunderbuss", duration = 1.8, knock = knock })
		else
			Kit.push(player, victim, knock * 0.6, "blunderbuss")
		end
	end

	if ball and type(ball.ApplyBallImpulse) == "function" then
		for _, entry in Kit.ballsNear(origin, DEF.range, player) do
			if ItemGeometry.inCone(origin, aim, entry.ball.Position, half, DEF.range) then
				ball.ApplyBallImpulse(entry.player, aim * P.BallImpulse + Vector3.new(0, 12, 0), "blunderbuss")
			end
		end
	end

	-- Recul du tireur.
	local movement = Kit.service("MovementService")
	if movement and type(movement.AllowDisplacement) == "function" then
		movement.AllowDisplacement(player, P.ExemptionSeconds, "blunderbuss")
	end
	local flatAim = ItemGeometry.flat(aim)
	local recoil = if flatAim.Magnitude > 1e-3 then -flatAim.Unit * P.RecoilSpeed else Vector3.zero
	if aim.Y < math.sin(math.rad(P.GroundAimPitchDegrees)) then
		recoil += Vector3.new(0, P.VerticalRecoilSpeed, 0)
	end
	if recoil.Magnitude > 0 then
		Kit.push(player, player, recoil, "blunderbuss_recoil")
	end

	Kit.burst(origin + aim * 4, 5, DEF.color, 0.3)
	return true, nil
end

return Blunderbuss
