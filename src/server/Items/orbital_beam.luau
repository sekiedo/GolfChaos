--!strict
--[[
	Rayon Satellite (orbital_beam) — cible : l'adversaire le mieux placé (distance restante au trou la plus faible),
	hors alliés, terminés, protégés et invisibles. Sans cible valide, l'objet n'est pas consommé. Déroulé : cercle rouge
	de rayon 7 qui suit la cible 2 s, se fige 1,2 s, puis frappe majeure sur tout adversaire dans le cercle (les balles
	présentes sont projetées). Contre-jeu : sortir du cercle, bouclier (détruit + KO sans fort recul), invisibilité.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Config.Items)
local ItemGeometry = require(ReplicatedStorage.Shared.Logic.ItemGeometry)
local Kit = require(script.Parent.Kit)

local DEF = Items.ById.orbital_beam
local P = DEF.params
local FOLLOW_STEP = 0.05
local SKY_HEIGHT = 120

local OrbitalBeam = { Id = "orbital_beam" }

local function bestPlaced(player: Player): Player?
	local ball = Kit.service("BallService")
	if not ball or type(ball.GetCup) ~= "function" or type(ball.GetBall) ~= "function" then
		return Kit.nearest(player, math.huge, { visibleOnly = true })
	end
	local cup = ball.GetCup()
	local candidates: { { id: any, remaining: number } } = {}
	for _, other in Kit.opponents(player, { visibleOnly = true }) do
		local ok, ballPart = pcall(ball.GetBall, other)
		local where = if ok and typeof(ballPart) == "Instance" and ballPart:IsA("BasePart") then ballPart.Position else Kit.chest(other)
		if where and typeof(cup) == "Vector3" then
			table.insert(candidates, { id = other, remaining = (where - cup).Magnitude })
		elseif where then
			table.insert(candidates, { id = other, remaining = 0 })
		end
	end
	return ItemGeometry.bestPlaced(candidates, player)
end

function OrbitalBeam.Use(ctx: any, player: Player, _payload: any): (boolean, string?)
	local target = bestPlaced(player)
	local targetRoot = if target then Kit.root(target) else nil
	if not target or not targetRoot then
		return false, "item.fb.noTarget"
	end
	ctx.warn(target, "orbital_beam", player)
	local center = Kit.groundAt(targetRoot.Position)
	local ring = Kit.ring(center, P.Radius, DEF.color)
	local trove = ctx.roundTrove:Extend()
	trove:Add(ring)
	ctx.playerTrove(player):Add(trove)

	trove:Add(task.spawn(function()
		-- Phase 1 : le cercle suit la cible.
		local elapsed = 0
		while elapsed < P.FollowSeconds do
			task.wait(FOLLOW_STEP)
			elapsed += FOLLOW_STEP
			local root = if target then Kit.root(target) else nil
			if root then
				center = Kit.groundAt(root.Position)
				ring.CFrame = CFrame.new(center + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
			end
		end
		-- Phase 2 : le cercle se fige (charge visible).
		ring.Color = Color3.new(1, 1, 1)
		ring.Transparency = 0.2
		task.wait(P.LockSeconds)
		-- Frappe.
		Kit.beam(center + Vector3.new(0, SKY_HEIGHT, 0), center, 4, DEF.color, 0.5)
		Kit.burst(center, P.Radius, DEF.color, 0.6)
		local ball = Kit.service("BallService")
		for _, victim in Kit.opponents(player) do
			local chest = Kit.chest(victim)
			if chest and (ItemGeometry.flat(chest - center)).Magnitude <= P.Radius then
				Kit.strike(player, victim, { source = "orbital_beam", major = true, duration = 3, knock = Kit.knock(center, chest, 85, 30) })
			end
		end
		if ball and type(ball.ApplyBallImpulse) == "function" then
			for _, entry in Kit.ballsNear(center, P.Radius, nil) do
				ball.ApplyBallImpulse(entry.player, Kit.knock(center, entry.ball.Position, P.BallImpulse, 30), "orbital_beam")
			end
		end
		trove:Clean()
	end))
	return true, nil
end

return OrbitalBeam
