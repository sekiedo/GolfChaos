--!strict
--[[
	Lance-Fusées Confettis (confetti_rocket) — maintenir « Utiliser » : une cible adverse visible dans un cône de 20°,
	à moins de 150 studs et en ligne de vue est verrouillée après 0,6 s ; relâcher pour tirer (sans verrou : tir droit).
	Vol à 70 studs/s, virage max 90°/s, 4 s de vie ; explosion au contact : KO à moins de 5 studs, recul jusqu'à 8.
	Contre-jeu : plongeon ou Nuage Ninja (verrou rompu, la fusée file droit), bouclier (frappe absorbée), couverture.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Config.Items)
local ItemGeometry = require(ReplicatedStorage.Shared.Logic.ItemGeometry)
local Kit = require(script.Parent.Kit)

local DEF = Items.ById.confetti_rocket
local P = DEF.params
local HIT_RADIUS = 2.6

local ConfettiRocket = { Id = "confetti_rocket" }

local function validLock(target: Player?): boolean
	if not target or not Kit.root(target) or Kit.isInvisible(target) then
		return false
	end
	local combat = Kit.service("CombatService")
	if combat and type(combat.IsDodging) == "function" and combat.IsDodging(target) then
		return false
	end
	return true
end

function ConfettiRocket.UseStart(ctx: any, player: Player, hold: any): boolean
	ctx.after(ctx.playerTrove(player), P.LockSeconds, function()
		if hold.data.cancelled then
			return
		end
		local origin = Kit.chest(player)
		local root = Kit.root(player)
		if not origin or not root then
			return
		end
		local aim = hold.data.aim or root.CFrame.LookVector
		local best: Player? = nil
		local bestDot = -1
		for _, victim in Kit.opponents(player, { visibleOnly = true }) do
			local chest = Kit.chest(victim)
			if chest and ItemGeometry.inCone(origin, aim, chest, P.LockConeDegrees, DEF.range) and Kit.lineOfSight(origin, chest) then
				local dot = (chest - origin).Unit:Dot(aim.Unit)
				if dot > bestDot then
					best = victim
					bestDot = dot
				end
			end
		end
		if best then
			hold.data.target = best
			ctx.lockState(player, best.UserId)
		end
	end)
	return true
end

function ConfettiRocket.UseCancel(ctx: any, player: Player, hold: any)
	hold.data.cancelled = true
	ctx.lockState(player, 0)
end

function ConfettiRocket.Use(ctx: any, player: Player, payload: any): (boolean, string?)
	local origin = Kit.chest(player)
	if not origin then
		return false, "item.fb.state"
	end
	local aim: Vector3 = payload.aim
	local locked: Player? = payload.hold.target
	ctx.lockState(player, 0)
	local maxTurn = math.rad(P.TurnRateDegrees)
	local start = origin + aim * 2.5

	local function explode(at: Vector3, direct: Player?)
		Kit.burst(at, P.ExplosionRadius, DEF.color, 0.5)
		local combat = Kit.service("CombatService")
		for _, victim in Kit.opponents(player) do
			local chest = Kit.chest(victim)
			if not chest then
				continue
			end
			if combat and type(combat.IsDodging) == "function" and combat.IsDodging(victim) and victim ~= direct then
				continue
			end
			local distance = (chest - at).Magnitude
			if distance <= P.KnockoutRadius or victim == direct then
				Kit.strike(player, victim, { source = "confetti_rocket", duration = 1.8, knock = Kit.knock(at, chest, 55, 20) })
			elseif distance <= P.ExplosionRadius then
				Kit.push(player, victim, Kit.knock(at, chest, 30, 10), "confetti_rocket")
			end
		end
	end

	Kit.projectile(ctx, {
		kind = "rocket",
		owner = player,
		origin = start,
		velocity = aim * P.Speed,
		life = DEF.duration,
		hitRadius = HIT_RADIUS,
		size = 1.4,
		color = DEF.color,
		steer = function(position: Vector3, velocity: Vector3, dt: number): Vector3
			if locked and not validLock(locked) then
				locked = nil -- verrou rompu : la fusée file droit
			end
			local chest = if locked then Kit.chest(locked :: Player) else nil
			if not chest then
				return velocity
			end
			local direction = velocity.Unit
			local desired = (chest - position)
			if desired.Magnitude < 1e-3 then
				return velocity
			end
			desired = desired.Unit
			local angle = math.acos(math.clamp(direction:Dot(desired), -1, 1))
			local step = maxTurn * dt
			if angle <= step or angle < 1e-4 then
				return desired * P.Speed
			end
			local t = step / angle
			return (direction * (1 - t) + desired * t).Unit * P.Speed
		end,
		onEnd = function(reason: string, at: Vector3, victim: Player?)
			if reason ~= "cancel" then
				explode(at, victim)
			end
		end,
	})
	return true, nil
end

return ConfettiRocket
