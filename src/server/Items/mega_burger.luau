--!strict
--[[
	Méga-Burger (mega_burger) — 8 s en géant : taille ×2,2, vitesse ×0,85, attribut Giant (visée bloquée, immunité aux
	frappes mineures via le gestionnaire de bouclier d'ItemService). Au contact (6 studs) un adversaire est mis KO
	2 s avec un fort recul (90) ; les balles proches sont projetées ; les décors cassables à portée sont détruits.
	Fin : retour à la taille d'origine, retiré à la réapparition, en fin de trou et à la déconnexion.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Kit = require(script.Parent.Kit)

local DEF = Items.ById.mega_burger
local P = DEF.params
local CONTACT_RADIUS = 6
local BREAK_RADIUS = 8
local STEP = 0.1
local REHIT_SECONDS = 1.5

local MegaBurger = { Id = "mega_burger" }

local function breakProps(at: Vector3)
	for _, part in Workspace:GetPartBoundsInRadius(at, BREAK_RADIUS) do
		local model = part:FindFirstAncestorWhichIsA("Model")
		if model and model:GetAttribute("Breakable") == true then
			Kit.burst(model:GetPivot().Position, 3, DEF.color, 0.3)
			model:Destroy()
		end
	end
end

function MegaBurger.Use(ctx: any, player: Player, _payload: any): (boolean, string?)
	local character, _, root = Kit.character(player)
	local movement = Kit.service("MovementService")
	if not character or not root or not movement then
		return false, "item.fb.state"
	end
	ctx.clearEffect(player, "giant")
	local previousScale = character:GetScale()
	character:ScaleTo(previousScale * P.Scale)
	character:SetAttribute("Giant", true)
	movement.SetModifier(player, "giant", P.SpeedMultiplier, nil, DEF.duration)

	local running = true
	local lastHit: { [Player]: number } = {}
	ctx.addEffect(player, "giant", DEF.duration, function()
		running = false
		movement.ClearModifier(player, "giant")
		if character.Parent then
			character:ScaleTo(previousScale)
			character:SetAttribute("Giant", nil)
		end
	end)

	task.spawn(function()
		while running and character.Parent do
			task.wait(STEP)
			local current = Kit.root(player)
			if not current then
				break
			end
			local at = current.Position
			local time = os.clock()
			for _, victim in Kit.opponents(player) do
				local victimRoot = Kit.root(victim)
				if victimRoot and (victimRoot.Position - at).Magnitude <= CONTACT_RADIUS and time - (lastHit[victim] or 0) >= REHIT_SECONDS then
					lastHit[victim] = time
					Kit.strike(player, victim, {
						source = "mega_burger",
						major = true,
						duration = P.ContactKnockout,
						knock = Kit.knock(at, victimRoot.Position, P.ContactKnockback, 30),
					})
				end
			end
			local ball = Kit.service("BallService")
			if ball and type(ball.ApplyBallImpulse) == "function" then
				for _, entry in Kit.ballsNear(at, CONTACT_RADIUS, player) do
					ball.ApplyBallImpulse(entry.player, Kit.knock(at, entry.ball.Position, P.BallImpulse, 20), "mega_burger")
				end
			end
			breakProps(at)
		end
	end)
	return true, nil
end

return MegaBurger
