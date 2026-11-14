--!strict
--[[
	Bulle Magnétique (magnet_shield) — 12 s de protection : absorbe 3 frappes mineures ; une frappe majeure la détruit
	et provoque un KO sans fort recul. L'absorption elle-même est faite par le gestionnaire de bouclier d'ItemService
	(CombatService.SetShieldHandler) ; ce module pose l'état, la bulle visible et l'attribut Shielded.
	Retirée à la fin de la durée, à la rupture, à la réapparition, en fin de trou et à la déconnexion.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Kit = require(script.Parent.Kit)

local DEF = Items.ById.magnet_shield
local P = DEF.params

local MagnetShield = { Id = "magnet_shield" }

function MagnetShield.Use(ctx: any, player: Player, _payload: any): (boolean, string?)
	local character, _, root = Kit.character(player)
	if not character or not root then
		return false, "item.fb.state"
	end
	-- Réutilisation : on repart d'une bulle neuve (3 charges, 12 s).
	ctx.clearEffect(player, "shield")
	local bubble = Kit.part({
		name = "BulleMagnetique",
		shape = Enum.PartType.Ball,
		size = Vector3.new(1, 1, 1) * P.Radius * 2,
		color = DEF.color,
		transparency = 0.7,
		material = Enum.Material.ForceField,
		cframe = root.CFrame,
	})
	bubble.Anchored = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = bubble
	weld.Part1 = root
	weld.Parent = bubble
	character:SetAttribute("Shielded", true)
	ctx.setShield(player, P.MinorHitsAbsorbed)
	ctx.addEffect(player, "shield", DEF.duration, function()
		ctx.setShield(player, 0)
		bubble:Destroy()
		if character.Parent then
			character:SetAttribute("Shielded", nil)
		end
	end)
	return true, nil
end

return MagnetShield
