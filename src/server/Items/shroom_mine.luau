--!strict
--[[
	Champignon Piégé (shroom_mine) — posé aux pieds ; armement 1,5 s (clignotement lent) ; un adversaire à moins de
	6 studs déclenche un avertissement de 0,6 s (clignotement rapide) puis l'explosion : frappe majeure à moins de 6
	studs, recul jusqu'à 8. Une balle rapide qui le touche le fait exploser. 2 champignons actifs par joueur, 60 s de vie.
	Un coup de poing à moins de 4 studs le désamorce sans explosion. Les alliés et le poseur ne le déclenchent jamais
	(Kit.opponents). Nettoyé en fin de trou et à la déconnexion du poseur.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Kit = require(script.Parent.Kit)

local DEF = Items.ById.shroom_mine
local P = DEF.params
local BALL_TOUCH_RADIUS = 3
local CHECK_INTERVAL = 0.1

local ShroomMine = { Id = "shroom_mine" }

function ShroomMine.Use(ctx: any, player: Player, _payload: any): (boolean, string?)
	if ctx.mines(player, 0) >= Items.MaxActiveMinesPerPlayer then
		return false, "item.fb.mineLimit"
	end
	local root = Kit.root(player)
	if not root then
		return false, "item.fb.state"
	end
	local position = Kit.groundAt(root.Position)
	local trove = ctx.roundTrove:Extend()
	ctx.playerTrove(player):Add(trove)
	ctx.mines(player, 1)
	local released = false
	trove:Add(function()
		if not released then
			released = true
			ctx.mines(player, -1)
		end
	end)

	local mine = Kit.part({
		name = "Champignon",
		shape = Enum.PartType.Ball,
		size = Vector3.new(2.4, 1.8, 2.4),
		position = position + Vector3.new(0, 0.7, 0),
		color = DEF.color,
		material = Enum.Material.SmoothPlastic,
	})
	trove:Add(mine)

	local armed = false
	local triggered = false
	local exploded = false

	local function explode()
		if exploded then
			return
		end
		exploded = true
		local at = mine.Position
		Kit.burst(at, P.ExplosionRadius, DEF.color, 0.5)
		for _, victim in Kit.opponents(player) do
			local chest = Kit.chest(victim)
			if chest then
				local distance = (chest - at).Magnitude
				if distance <= P.KnockoutRadius then
					Kit.strike(player, victim, { source = "shroom_mine", major = true, duration = 2.2, knock = Kit.knock(at, chest, 70, 28) })
				elseif distance <= P.ExplosionRadius then
					Kit.push(player, victim, Kit.knock(at, chest, 40, 12), "shroom_mine")
				end
			end
		end
		local ball = Kit.service("BallService")
		if ball and type(ball.ApplyBallImpulse) == "function" then
			for _, entry in Kit.ballsNear(at, P.ExplosionRadius, nil) do
				ball.ApplyBallImpulse(entry.player, Kit.knock(at, entry.ball.Position, 45, 18), "shroom_mine")
			end
		end
		trove:Clean()
	end

	ctx.after(trove, DEF.windup, function()
		armed = true
	end)
	ctx.after(trove, DEF.duration, function()
		trove:Clean() -- 60 s de vie
	end)

	-- Surveillance : clignotement, déclenchement par un adversaire ou par une balle rapide.
	trove:Add(task.spawn(function()
		local blink = false
		while not exploded do
			task.wait(CHECK_INTERVAL)
			if not mine.Parent then
				return
			end
			blink = not blink
			mine.Transparency = if (armed and not triggered) then (if blink then 0.35 else 0) elseif triggered then (if blink then 0.6 else 0) else 0.5
			if armed and not triggered then
				local at = mine.Position
				for _, victim in Kit.opponents(player) do
					local victimRoot = Kit.root(victim)
					if victimRoot and (victimRoot.Position - at).Magnitude <= P.TriggerRadius then
						triggered = true
						ctx.warn(victim, "shroom_mine", player)
						ctx.after(trove, P.WarningSeconds, explode)
						break
					end
				end
				if not triggered then
					for _, entry in Kit.ballsNear(at, BALL_TOUCH_RADIUS, nil) do
						if entry.ball.AssemblyLinearVelocity.Magnitude >= P.BallTriggerSpeed then
							triggered = true
							explode()
							break
						end
					end
				end
			end
		end
	end))

	-- Désamorçage par un coup de poing.
	local combat = Kit.service("CombatService")
	if combat and combat.Punched and type(combat.Punched.Connect) == "function" then
		trove:Add(combat.Punched:Connect(function(_puncher: any, punchPosition: any)
			if not exploded and typeof(punchPosition) == "Vector3" and (punchPosition - mine.Position).Magnitude <= P.DisarmPunchRange then
				exploded = true
				Kit.burst(mine.Position, 2, Color3.new(1, 1, 1), 0.3)
				trove:Clean()
			end
		end))
	end
	return true, nil
end

return ShroomMine
