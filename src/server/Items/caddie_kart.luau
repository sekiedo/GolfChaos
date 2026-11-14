--!strict
--[[
	Kart-Caddie (caddie_kart) — fait apparaître un kart devant l'utilisateur (8 places, 45 s). Si l'emplacement n'est
	pas libre, ou si VehicleService est absent, l'objet n'est pas consommé. Toute la logique du kart (sièges, vitesse,
	collisions avec les adversaires, usure, nettoyage) est dans VehicleService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Kit = require(script.Parent.Kit)

local DEF = Items.ById.caddie_kart
local P = DEF.params

local CaddieKart = { Id = "caddie_kart" }

function CaddieKart.Use(_ctx: any, player: Player, _payload: any): (boolean, string?)
	local vehicles = Kit.service("VehicleService")
	if not vehicles or type(vehicles.SpawnKart) ~= "function" then
		return false, "item.fb.unavailable"
	end
	local root = Kit.root(player)
	if not root then
		return false, "item.fb.state"
	end
	local look = Kit.look(player)
	local origin = root.Position + Vector3.new(0, 1, 0)
	-- Emplacement libre : rien devant (décor) sur la distance d'apparition + la longueur du kart.
	if Kit.raycast(origin, look * (P.SpawnDistance + 5)) then
		return false, "item.fb.noRoom"
	end
	local position = Kit.groundAt(root.Position + look * P.SpawnDistance) + Vector3.new(0, 2, 0)
	local ok, spawned = pcall(vehicles.SpawnKart, player, CFrame.lookAt(position, position + look))
	if not ok or spawned ~= true then
		return false, "item.fb.noRoom"
	end
	return true, nil
end

return CaddieKart
