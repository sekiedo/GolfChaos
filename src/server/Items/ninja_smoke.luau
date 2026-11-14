--!strict
--[[
	Nuage Ninja (ninja_smoke) — nuage de fumée de rayon 10 pendant 6 s ; l'utilisateur devient invisible 5 s
	(attribut Invisible lu par BallService/CombatService : plus ciblable par les objets à verrouillage). L'invisibilité
	prend fin à l'attaque, à l'utilisation d'un autre objet (ItemService.breakInvisible), à un tir de balle
	ou à l'expiration. Transparence : 0,92 (la modulation alliés 0,5 est portée par le client via l'attribut).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Kit = require(script.Parent.Kit)

local DEF = Items.ById.ninja_smoke
local P = DEF.params

local NinjaSmoke = { Id = "ninja_smoke" }

local function setTransparency(character: Model, value: number, saved: { [Instance]: number }?)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			if saved then
				saved[descendant] = descendant.Transparency
			end
			descendant.Transparency = value
		elseif descendant:IsA("Decal") then
			if saved then
				saved[descendant] = descendant.Transparency
			end
			descendant.Transparency = value
		end
	end
end

function NinjaSmoke.Use(ctx: any, player: Player, _payload: any): (boolean, string?)
	local character, _, root = Kit.character(player)
	if not character or not root then
		return false, "item.fb.state"
	end
	-- Nuage au sol.
	local cloud = Kit.part({
		name = "NuageNinja",
		shape = Enum.PartType.Ball,
		size = Vector3.new(1, 1, 1) * P.CloudRadius * 2,
		position = Kit.groundAt(root.Position) + Vector3.new(0, P.CloudRadius * 0.4, 0),
		color = DEF.color,
		material = Enum.Material.SmoothPlastic,
		transparency = 0.55,
	})
	ctx.roundTrove:Add(cloud)
	ctx.after(ctx.roundTrove, P.CloudSeconds, function()
		Kit.fade(cloud, 0.6)
	end)

	-- Invisibilité : on mémorise les transparences pour les restaurer fidèlement.
	ctx.clearEffect(player, "invisible")
	local saved: { [Instance]: number } = {}
	setTransparency(character, P.OthersTransparency, saved)
	character:SetAttribute("Invisible", true)
	ctx.addEffect(player, "invisible", P.InvisibleSeconds, function()
		for instance, transparency in saved do
			if instance.Parent then
				(instance :: any).Transparency = transparency
			end
		end
		if character.Parent then
			character:SetAttribute("Invisible", nil)
		end
	end)
	return true, nil
end

return NinjaSmoke
