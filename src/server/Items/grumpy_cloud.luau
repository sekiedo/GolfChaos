--!strict
--[[
	Nuage Grincheux (grumpy_cloud) — un nuage dérive à 12 studs/s vers l'adversaire visible le plus proche pendant 8 s ;
	toutes les 2 s il marque le sol sous lui (cercle d'avertissement 1 s) puis y fait tomber la foudre : rayon 5,
	KO mineur de 2 s. Les balles dans le rayon sont poussées. Bouclier : absorbe ; plongeon ou sortie du cercle : évite.
	Le nuage et ses cercles sont détruits en fin de trou (roundTrove).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Config.Items)
local ItemGeometry = require(ReplicatedStorage.Shared.Logic.ItemGeometry)
local Kit = require(script.Parent.Kit)

local DEF = Items.ById.grumpy_cloud
local P = DEF.params
local STEP = 0.05
local SEARCH_RANGE = 200

local GrumpyCloud = { Id = "grumpy_cloud" }

function GrumpyCloud.Use(ctx: any, player: Player, _payload: any): (boolean, string?)
	local root = Kit.root(player)
	if not root then
		return false, "item.fb.state"
	end
	local trove = ctx.roundTrove:Extend()
	ctx.playerTrove(player):Add(trove)
	local position = root.Position + Vector3.new(0, P.Height, 0)
	local cloud = Kit.part({
		name = "NuageGrincheux",
		shape = Enum.PartType.Ball,
		size = Vector3.new(10, 4, 10),
		position = position,
		color = DEF.color,
		material = Enum.Material.SmoothPlastic,
		transparency = 0.25,
	})
	trove:Add(cloud)

	local function strike(center: Vector3)
		Kit.beam(center + Vector3.new(0, P.Height, 0), center, 3, Color3.fromRGB(255, 255, 160), 0.35)
		Kit.burst(center, P.StrikeRadius, Color3.fromRGB(255, 255, 160), 0.4)
		for _, victim in Kit.opponents(player) do
			local chest = Kit.chest(victim)
			if chest and ItemGeometry.flat(chest - center).Magnitude <= P.StrikeRadius then
				Kit.strike(player, victim, { source = "grumpy_cloud", duration = P.KnockoutDuration, knock = Kit.knock(center, chest, 35, 14) })
			end
		end
		local ball = Kit.service("BallService")
		if ball and type(ball.ApplyBallImpulse) == "function" then
			for _, entry in Kit.ballsNear(center, P.StrikeRadius, nil) do
				ball.ApplyBallImpulse(entry.player, Kit.knock(center, entry.ball.Position, 25, 10), "grumpy_cloud")
			end
		end
	end

	trove:Add(task.spawn(function()
		local elapsed = 0
		local sinceStrike = 0
		while elapsed < DEF.duration and cloud.Parent do
			task.wait(STEP)
			elapsed += STEP
			sinceStrike += STEP
			local target = Kit.nearest(player, SEARCH_RANGE, { visibleOnly = true })
			local targetRoot = if target then Kit.root(target) else nil
			if targetRoot then
				local goal = targetRoot.Position + Vector3.new(0, P.Height, 0)
				local delta = ItemGeometry.flat(goal - position)
				if delta.Magnitude > 0.5 then
					position += delta.Unit * math.min(P.DriftSpeed * STEP, delta.Magnitude)
				end
			end
			cloud.Position = position
			if sinceStrike >= P.StrikeInterval then
				sinceStrike = 0
				local center = Kit.groundAt(Vector3.new(position.X, position.Y, position.Z))
				local ring = Kit.ring(center, P.StrikeRadius, DEF.color)
				trove:Add(ring)
				ctx.after(trove, P.StrikeWarning, function()
					ring:Destroy()
					strike(center)
				end)
			end
		end
		trove:Clean()
	end))
	return true, nil
end

return GrumpyCloud
