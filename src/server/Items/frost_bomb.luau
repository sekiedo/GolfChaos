--!strict
--[[
	Bombe Givrante (frost_bomb) — lancée en cloche (35°, 55 studs/s), explose au contact du décor ou d'un adversaire :
	rayon 9 ; chaque adversaire touché est gelé 3 s (immobile, visée annulée) sauf si sa bulle absorbe ; les balles
	dans le rayon sont gelées 3 s. Tombée sur l'eau, elle crée une plateforme de glace de 8 s. Alliés non affectés.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Config.Items)
local ItemGeometry = require(ReplicatedStorage.Shared.Logic.ItemGeometry)
local Kit = require(script.Parent.Kit)

local DEF = Items.ById.frost_bomb
local P = DEF.params
local ICE_COLOR = Color3.fromRGB(200, 240, 255)

local FrostBomb = { Id = "frost_bomb" }

local function freeze(ctx: any, victim: Player)
	local character = Kit.character(victim)
	local movement = Kit.service("MovementService")
	if not character or not movement then
		return
	end
	local ball = Kit.service("BallService")
	if ball and type(ball.CancelAim) == "function" then
		ball.CancelAim(victim, "frozen", P.FreezeSeconds)
	end
	movement.Lock(victim, "Frozen")
	character:SetAttribute("Frozen", true)
	ctx.addEffect(victim, "frozen", P.FreezeSeconds, function()
		movement.Unlock(victim, "Frozen")
		if character.Parent then
			character:SetAttribute("Frozen", nil)
		end
	end)
end

local function overWater(at: Vector3): Vector3?
	local params = RaycastParams.new()
	params.IgnoreWater = false
	local result = Workspace:Raycast(at + Vector3.new(0, 3, 0), Vector3.new(0, -10, 0), params)
	if result and result.Material == Enum.Material.Water then
		return result.Position
	end
	return nil
end

function FrostBomb.Use(ctx: any, player: Player, payload: any): (boolean, string?)
	local origin = Kit.chest(player)
	if not origin then
		return false, "item.fb.state"
	end
	local aim: Vector3 = payload.aim
	local flat = ItemGeometry.flat(aim)
	if flat.Magnitude < 1e-3 then
		flat = Kit.look(player)
	end
	local loft = math.rad(P.ThrowLoftDegrees)
	local velocity = flat.Unit * math.cos(loft) * P.ThrowSpeed + Vector3.new(0, math.sin(loft) * P.ThrowSpeed, 0)

	Kit.projectile(ctx, {
		kind = "bomb",
		owner = player,
		origin = origin + flat.Unit * 2,
		velocity = velocity,
		gravity = Workspace.Gravity,
		life = 4,
		hitRadius = 2.2,
		size = 1.6,
		color = DEF.color,
		onEnd = function(reason: string, at: Vector3, _victim: Player?)
			if reason == "cancel" then
				return
			end
			Kit.burst(at, P.Radius, DEF.color, 0.5)
			for _, victim in Kit.opponents(player) do
				local chest = Kit.chest(victim)
				if chest and (chest - at).Magnitude <= P.Radius then
					if not ctx.consumeShield(victim) then
						freeze(ctx, victim)
					end
				end
			end
			local ball = Kit.service("BallService")
			if ball and type(ball.FreezeBall) == "function" then
				for _, entry in Kit.ballsNear(at, P.Radius, nil) do
					ball.FreezeBall(entry.player, P.FreezeSeconds)
				end
			end
			local waterPoint = overWater(at)
			if waterPoint then
				local platform = Kit.part({
					name = "PlateformeDeGlace",
					shape = Enum.PartType.Cylinder,
					size = Vector3.new(1, P.PlatformRadius * 2, P.PlatformRadius * 2),
					cframe = CFrame.new(waterPoint + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
					color = ICE_COLOR,
					material = Enum.Material.Ice,
					transparency = 0.1,
				})
				platform.CanCollide = true
				platform.CanQuery = true
				ctx.roundTrove:Add(platform)
				ctx.after(ctx.roundTrove, P.PlatformSeconds, function()
					Kit.fade(platform, 0.5)
				end)
			end
		end,
	})
	return true, nil
end

return FrostBomb
