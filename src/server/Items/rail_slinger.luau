--!strict
--[[
	Lance-Rail (rail_slinger) — maintenir « Utiliser » 1 s pour charger (laser de visée côté client), relâcher pour
	tirer : rayon instantané de 140 studs (arrêté par le décor), jusqu'à 3 adversaires touchés dans l'ordre,
	frappe majeure avec recul ×1 / ×0,7 / ×0,5. Une bulle qui absorbe le tir arrête le rayon. Le plongeon évite.
	Relâcher avant la fin de la charge annule sans consommer l'objet.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Config.Items)
local ItemGeometry = require(ReplicatedStorage.Shared.Logic.ItemGeometry)
local Kit = require(script.Parent.Kit)

local DEF = Items.ById.rail_slinger
local P = DEF.params

local RailSlinger = { Id = "rail_slinger" }

function RailSlinger.UseStart(_ctx: any, _player: Player, _hold: any): boolean
	return true
end

function RailSlinger.Use(_ctx: any, player: Player, payload: any): (boolean, string?)
	if (payload.held or 0) < DEF.windup then
		return false, nil -- charge incomplète : rien n'est consommé
	end
	local origin = Kit.chest(player)
	if not origin then
		return false, "item.fb.state"
	end
	local aim: Vector3 = payload.aim
	local wall = Kit.raycast(origin, aim * DEF.range)
	local length = if wall then (wall.Position - origin).Magnitude else DEF.range
	local combat = Kit.service("CombatService")

	local candidates: { Player } = {}
	local points: { Vector3 } = {}
	for _, victim in Kit.opponents(player) do
		local chest = Kit.chest(victim)
		if chest then
			table.insert(candidates, victim)
			table.insert(points, chest)
		end
	end
	local order = ItemGeometry.sortAlongRay(origin, aim, points, P.BeamRadius, length)
	local hits = 0
	local stoppedAt = length
	for _, entry in order do
		if hits >= P.MaxTargets then
			break
		end
		local victim = candidates[entry.index]
		if combat and type(combat.IsDodging) == "function" and combat.IsDodging(victim) then
			continue
		end
		local scale = P.KnockbackScale[hits + 1] or P.KnockbackScale[#P.KnockbackScale]
		local result = Kit.strike(player, victim, {
			source = "rail_slinger",
			major = true,
			duration = 2.5,
			knock = Kit.knock(origin, points[entry.index], 90 * scale, 22 * scale),
		})
		if result == "blocked" then
			stoppedAt = entry.t
			break
		elseif result == "hit" then
			hits += 1
		end
	end
	Kit.beam(origin + aim * 1.5, origin + aim * stoppedAt, P.BeamRadius * 2, DEF.color, 0.4)
	return true, nil
end

return RailSlinger
