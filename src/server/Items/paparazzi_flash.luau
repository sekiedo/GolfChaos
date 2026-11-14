--!strict
--[[
	Flash Paparazzi (paparazzi_flash) — cône de 50° sur 30 studs, ligne de vue exigée. Un adversaire touché doit
	regarder vers le photographe (produit scalaire ≥ 0,2) pour être ébloui : 2,5 s d'attribut Dazzled (écran blanc
	côté client, respecte l'option « sans flash »), vitesse ×0,6, visée annulée. La bulle absorbe l'effet.
	Se retourner à temps (ne pas regarder l'éclair) est le contre-jeu.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Config.Items)
local ItemGeometry = require(ReplicatedStorage.Shared.Logic.ItemGeometry)
local Kit = require(script.Parent.Kit)

local DEF = Items.ById.paparazzi_flash
local P = DEF.params

local PaparazziFlash = { Id = "paparazzi_flash" }

function PaparazziFlash.Use(ctx: any, player: Player, payload: any): (boolean, string?)
	local origin = Kit.chest(player)
	if not origin then
		return false, "item.fb.state"
	end
	local aim: Vector3 = payload.aim
	local movement = Kit.service("MovementService")
	local ball = Kit.service("BallService")

	Kit.burst(origin + aim * 3, 6, DEF.color, 0.25)
	for _, victim in Kit.opponents(player) do
		local chest = Kit.chest(victim)
		local victimRoot = Kit.root(victim)
		if not chest or not victimRoot then
			continue
		end
		if not ItemGeometry.inCone(origin, aim, chest, P.ConeDegrees / 2, DEF.range) or not Kit.lineOfSight(origin, chest) then
			continue
		end
		if not ItemGeometry.facing(chest, origin, victimRoot.CFrame.LookVector, P.FacingDotMin) then
			continue -- tourne le dos à l'éclair
		end
		if ctx.consumeShield(victim) then
			continue
		end
		local character = Kit.character(victim)
		if not character then
			continue
		end
		if ball and type(ball.CancelAim) == "function" then
			ball.CancelAim(victim, "dazzled", P.DazzleSeconds)
		end
		if movement and type(movement.SetModifier) == "function" then
			movement.SetModifier(victim, "dazzled", P.SpeedMultiplier, nil, P.DazzleSeconds)
		end
		character:SetAttribute("Dazzled", true)
		ctx.addEffect(victim, "dazzled", P.DazzleSeconds, function()
			if movement and type(movement.ClearModifier) == "function" then
				movement.ClearModifier(victim, "dazzled")
			end
			if character.Parent then
				character:SetAttribute("Dazzled", nil)
			end
		end)
	end
	return true, nil
end

return PaparazziFlash
