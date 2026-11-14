--!strict
--[[
	Pistolet à Bouchon (cork_pistol) — 2 tirs instantanés (rayon serveur, portée 80, arrêt sur le décor). Une touche
	provoque un KO court (1,8 s) et un léger recul. Le plongeon fait rater, un allié est traversé, la Bulle Magnétique
	dévie le bouchon (−1 charge, gérée par CombatService via ItemService). Sensible au klaxon.
	Les charges (2) et le délai entre tirs (0,8 s) sont gérés par ItemService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Config.Items)
local ItemGeometry = require(ReplicatedStorage.Shared.Logic.ItemGeometry)
local Kit = require(script.Parent.Kit)

local DEF = Items.ById.cork_pistol
local P = DEF.params
local VICTIM_RADIUS = 2.2

local CorkPistol = { Id = "cork_pistol" }

function CorkPistol.Use(_ctx: any, player: Player, payload: any): (boolean, string?)
	local origin = Kit.chest(player)
	if not origin then
		return false, "item.fb.state"
	end
	local aim: Vector3 = payload.aim
	-- Distance au décor sur la ligne de tir.
	local wall = Kit.raycast(origin, aim * DEF.range)
	local reach = if wall then (wall.Position - origin).Magnitude else DEF.range
	local combat = Kit.service("CombatService")

	local centers: { Vector3 } = {}
	local owners: { Player } = {}
	for _, victim in Kit.opponents(player, { visibleOnly = false }) do
		local chest = Kit.chest(victim)
		if chest then
			table.insert(centers, chest)
			table.insert(owners, victim)
		end
	end
	local endPoint = origin + aim * reach
	for _, hit in ItemGeometry.sortAlongRay(origin, aim, centers, VICTIM_RADIUS, reach) do
		local victim = owners[hit.index]
		if combat and type(combat.IsDodging) == "function" and combat.IsDodging(victim) then
			continue -- plongeon : le bouchon passe
		end
		local result = Kit.strike(player, victim, {
			source = "cork_pistol",
			duration = P.KnockoutDuration,
			knock = aim * P.Knockback + Vector3.new(0, 8, 0),
		})
		if result ~= "refused" then
			endPoint = origin + aim * hit.t
			break
		end
	end
	Kit.beam(origin + aim * 1.5, endPoint, 0.25, DEF.color, 0.18)
	return true, nil
end

return CorkPistol
