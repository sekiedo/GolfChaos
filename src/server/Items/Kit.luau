--!strict
--[[
	Items.Kit — outils communs des comportements d'objets (server/Items/<Id>.luau). Aucun état global : tout ce
	qui doit être nettoyé est confié à une Trove fournie par l'appelant (ctx.roundTrove ou ctx.playerTrove).
	Ce module n'a pas de champ `Id` : ItemService ne le charge pas comme un objet.

	  Kit.service(nom) -> any?                       service voisin (nil s'il est absent)
	  Kit.character(player) -> (Model?, Humanoid?, BasePart?)   Kit.root(player) / Kit.chest(player) -> Vector3?
	  Kit.look(player) -> Vector3                    direction horizontale du personnage
	  Kit.opponents(player, opts?) -> { Player }     adversaires affectables ; opts.visibleOnly écarte les invisibles
	  Kit.nearest(player, maxDistance, opts?) -> Player?
	  Kit.raycast(origin, vector, extraIgnore?) -> RaycastResult?     décor seulement (personnages et balles ignorés)
	  Kit.lineOfSight(from, to) -> boolean
	  Kit.groundAt(position) -> Vector3              point du sol sous la position (ou la position)
	  Kit.strike(attacker, victim, spec) -> "hit" | "blocked" | "refused"   spec = { source, major, duration, knock }
	  Kit.push(attacker, victim, velocity, source) -> boolean    recul sans KO
	  Kit.knock(fromPos, toPos, speed, lift) -> Vector3
	  Kit.ballsNear(position, radius, except) -> { { player, ball } }
	  Kit.part(props) -> Part                        pièce d'effet (ancrée, sans collision) dans Workspace.ItemEffects
	  Kit.burst(position, radius, color, seconds)    sphère néon qui grossit et s'efface
	  Kit.beam(from, to, width, color, seconds) -> Part
	  Kit.ring(position, radius, color) -> Part      anneau d'avertissement posé au sol
	  Kit.projectile(ctx, spec) -> { Cancel }        projectile simulé par le serveur (voir plus bas)
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemGeometry = require(Shared.Logic.ItemGeometry)
local Log = require(Shared.Util.Log)
local Net = require(Shared.Net)

local Services = require(script.Parent.Parent.Util.Services)
local services = Services.scope("Items")

local Kit = {}

local FOLDER_NAME = "ItemEffects"
local TORSO_OFFSET = Vector3.new(0, 0.5, 0)

local effectsFolder: Folder? = nil
local projectileCounter = 0

function Kit.service(name: string): any?
	return services.get(name)
end

function Kit.folder(): Folder
	local folder = effectsFolder
	if folder and folder.Parent then
		return folder
	end
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		effectsFolder = existing
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = Workspace
	effectsFolder = created
	return created
end

--------------------------------------------------------------------------------
-- Joueurs
--------------------------------------------------------------------------------

function Kit.character(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character or not character.Parent then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

function Kit.root(player: Player): BasePart?
	local _, _, root = Kit.character(player)
	return root
end

function Kit.chest(player: Player): Vector3?
	local root = Kit.root(player)
	return if root then root.Position + TORSO_OFFSET else nil
end

function Kit.look(player: Player): Vector3
	local root = Kit.root(player)
	if not root then
		return Vector3.new(0, 0, -1)
	end
	local flat = ItemGeometry.flat(root.CFrame.LookVector)
	return if flat.Magnitude < 1e-3 then Vector3.new(0, 0, -1) else flat.Unit
end

function Kit.isInvisible(player: Player): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute("Invisible") == true
end

function Kit.opponents(player: Player, opts: { visibleOnly: boolean? }?): { Player }
	local combat = Kit.service("CombatService")
	local match = Kit.service("MatchService")
	local result: { Player } = {}
	for _, other in Players:GetPlayers() do
		if other == player or not Kit.root(other) then
			continue
		end
		if match and type(match.IsActive) == "function" and not match.IsActive(other) then
			continue
		end
		if combat and type(combat.CanAffect) == "function" and not combat.CanAffect(player, other) then
			continue
		end
		if opts and opts.visibleOnly and Kit.isInvisible(other) then
			continue
		end
		table.insert(result, other)
	end
	return result
end

function Kit.nearest(player: Player, maxDistance: number, opts: { visibleOnly: boolean? }?): Player?
	local origin = Kit.root(player)
	if not origin then
		return nil
	end
	local best: Player? = nil
	local bestDistance = maxDistance
	for _, other in Kit.opponents(player, opts) do
		local root = Kit.root(other)
		if root then
			local distance = (root.Position - origin.Position).Magnitude
			if distance <= bestDistance then
				best = other
				bestDistance = distance
			end
		end
	end
	return best
end

--------------------------------------------------------------------------------
-- Décor
--------------------------------------------------------------------------------

local function worldParams(extraIgnore: { Instance }?): RaycastParams
	local ignore: { Instance } = { Kit.folder() }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local balls = Workspace:FindFirstChild("Balls")
	if balls then
		table.insert(ignore, balls)
	end
	if extraIgnore then
		for _, instance in extraIgnore do
			table.insert(ignore, instance)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return params
end

function Kit.raycast(origin: Vector3, vector: Vector3, extraIgnore: { Instance }?): RaycastResult?
	return Workspace:Raycast(origin, vector, worldParams(extraIgnore))
end

function Kit.lineOfSight(from: Vector3, to: Vector3): boolean
	return Kit.raycast(from, to - from) == nil
end

function Kit.groundAt(position: Vector3): Vector3
	local hit = Kit.raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0))
	return if hit then hit.Position else position
end

--------------------------------------------------------------------------------
-- Frappes
--------------------------------------------------------------------------------

export type StrikeSpec = { source: string, major: boolean?, duration: number?, knock: Vector3? }

-- KO via CombatService (qui consulte le bouclier). "blocked" = absorbé ; "refused" = cible non affectable.
function Kit.strike(attacker: Player, victim: Player, spec: StrikeSpec): string
	local combat = Kit.service("CombatService")
	if not combat or type(combat.Knockout) ~= "function" then
		return "refused"
	end
	local ok, success, reason = pcall(combat.Knockout, victim, {
		attacker = attacker,
		source = spec.source,
		major = spec.major == true,
		duration = spec.duration,
		knock = spec.knock,
	})
	if not ok then
		Log.warn("Items", "KO en erreur :", success)
		return "refused"
	end
	if success then
		return "hit"
	end
	return if reason == "blocked" then "blocked" else "refused"
end

function Kit.push(attacker: Player, victim: Player, velocity: Vector3, source: string): boolean
	local combat = Kit.service("CombatService")
	if not combat or type(combat.Knockback) ~= "function" then
		return false
	end
	local ok, result = pcall(combat.Knockback, victim, velocity, { attacker = attacker, source = source })
	return ok and result == true
end

function Kit.knock(fromPos: Vector3, toPos: Vector3, speed: number, lift: number): Vector3
	return ItemGeometry.knockDirection(fromPos, toPos) * speed + Vector3.new(0, lift, 0)
end

function Kit.ballsNear(position: Vector3, radius: number, except: Player?): { { player: Player, ball: BasePart } }
	local ballService = Kit.service("BallService")
	local result: { { player: Player, ball: BasePart } } = {}
	if not ballService or type(ballService.GetBall) ~= "function" then
		return result
	end
	for _, player in Players:GetPlayers() do
		if player == except then
			continue
		end
		local ok, ball = pcall(ballService.GetBall, player)
		if ok and typeof(ball) == "Instance" and ball:IsA("BasePart") and (ball.Position - position).Magnitude <= radius then
			table.insert(result, { player = player, ball = ball })
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- Pièces d'effet (créées par le serveur, répliquées à tous)
--------------------------------------------------------------------------------

export type PartProps = {
	name: string?,
	shape: Enum.PartType?,
	size: Vector3?,
	cframe: CFrame?,
	position: Vector3?,
	color: Color3?,
	transparency: number?,
	material: Enum.Material?,
	parent: Instance?,
	lifetime: number?,
}

function Kit.part(props: PartProps): Part
	local part = Instance.new("Part")
	part.Name = props.name or "Effet"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.Shape = props.shape or Enum.PartType.Block
	part.Size = props.size or Vector3.new(1, 1, 1)
	part.Material = props.material or Enum.Material.Neon
	part.Color = props.color or Color3.new(1, 1, 1)
	part.Transparency = props.transparency or 0
	part.CFrame = props.cframe or CFrame.new(props.position or Vector3.zero)
	part.Parent = props.parent or Kit.folder()
	if props.lifetime then
		Debris:AddItem(part, props.lifetime)
	end
	return part
end

function Kit.fade(part: BasePart, seconds: number)
	local tween = TweenService:Create(part, TweenInfo.new(seconds), { Transparency = 1 })
	tween:Play()
	Debris:AddItem(part, seconds + 0.2)
end

function Kit.burst(position: Vector3, radius: number, color: Color3, seconds: number)
	local part = Kit.part({
		name = "Explosion",
		shape = Enum.PartType.Ball,
		size = Vector3.new(1, 1, 1) * 0.5,
		position = position,
		color = color,
		transparency = 0.2,
	})
	TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(1, 1, 1) * radius * 2,
		Transparency = 1,
	}):Play()
	Debris:AddItem(part, seconds + 0.2)
end

function Kit.beam(from: Vector3, to: Vector3, width: number, color: Color3, seconds: number): Part
	local length = math.max(0.1, (to - from).Magnitude)
	local part = Kit.part({
		name = "Rayon",
		size = Vector3.new(width, width, length),
		cframe = CFrame.lookAt(from:Lerp(to, 0.5), to),
		color = color,
		transparency = 0.1,
	})
	Kit.fade(part, seconds)
	return part
end

function Kit.ring(position: Vector3, radius: number, color: Color3): Part
	return Kit.part({
		name = "Anneau",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.3, radius * 2, radius * 2),
		cframe = CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color = color,
		transparency = 0.45,
	})
end

--------------------------------------------------------------------------------
-- Projectiles simulés par le serveur
--------------------------------------------------------------------------------

--[[
	spec = {
	  kind          "rocket" | "bomb" (type annoncé aux clients par Items.Projectile)
	  owner         Player
	  origin        Vector3 ; velocity Vector3
	  gravity       studs/s² (0 = vol droit)
	  life          secondes de vol maximum
	  hitRadius     rayon de contact avec les adversaires (0 = ignore les joueurs)
	  size, color   aspect
	  steer         (position, velocity, dt) -> Vector3 nouvelle vitesse (guidage), facultatif
	  onEnd         (reason: "hit" | "world" | "expire" | "cancel", position: Vector3, victim: Player?) -> ()
	}
	La simulation s'arrête d'elle-même ; `ctx.roundTrove` la détruit aussi en fin de manche.
]]
export type ProjectileSpec = {
	kind: string,
	owner: Player,
	origin: Vector3,
	velocity: Vector3,
	gravity: number?,
	life: number,
	hitRadius: number?,
	size: number?,
	color: Color3?,
	steer: ((position: Vector3, velocity: Vector3, dt: number) -> Vector3)?,
	onEnd: (reason: string, position: Vector3, victim: Player?) -> (),
}

function Kit.projectile(ctx: any, spec: ProjectileSpec): { Cancel: () -> () }
	projectileCounter += 1
	local id = projectileCounter
	local size = spec.size or 1.2
	local part = Kit.part({
		name = "Projectile_" .. id,
		shape = Enum.PartType.Ball,
		size = Vector3.new(size, size, size),
		position = spec.origin,
		color = spec.color or Color3.new(1, 1, 1),
	})
	pcall(Net.fireAll, "Items.Projectile", id, spec.kind, spec.origin, spec.velocity, { owner = spec.owner.UserId })

	local position = spec.origin
	local velocity = spec.velocity
	local age = 0
	local finished = false
	local connection: RBXScriptConnection? = nil

	local function finish(reason: string, at: Vector3, victim: Player?)
		if finished then
			return
		end
		finished = true
		if connection then
			connection:Disconnect()
		end
		part:Destroy()
		pcall(Net.fireAll, "Items.ProjectileEnd", id, at, reason)
		local ok, err = pcall(spec.onEnd, reason, at, victim)
		if not ok then
			Log.warn("Items", "fin de projectile en erreur :", err)
		end
	end

	connection = RunService.Heartbeat:Connect(function(dt: number)
		if finished then
			return
		end
		age += dt
		if spec.steer then
			velocity = spec.steer(position, velocity, dt)
		elseif spec.gravity and spec.gravity ~= 0 then
			velocity += Vector3.new(0, -spec.gravity * dt, 0)
		end
		local step = velocity * dt
		local length = step.Magnitude
		if length > 1e-4 then
			-- Adversaire touché sur ce segment ?
			local radius = spec.hitRadius or 0
			if radius > 0 then
				local direction = step.Unit
				local bestT = length + 1
				local bestVictim: Player? = nil
				for _, victim in Kit.opponents(spec.owner) do
					local chest = Kit.chest(victim)
					if chest then
						local t = ItemGeometry.rayHitsSphere(position, direction, chest, radius, length)
						if t and t < bestT then
							bestT = t
							bestVictim = victim
						end
					end
				end
				if bestVictim then
					finish("hit", position + direction * bestT, bestVictim)
					return
				end
			end
			local hit = Kit.raycast(position, step)
			if hit then
				finish("world", hit.Position, nil)
				return
			end
		end
		position += step
		part.Position = position
		if age >= spec.life then
			finish("expire", position, nil)
		end
	end)
	local trove = ctx.roundTrove
	if trove then
		trove:Add(function()
			finish("cancel", position, nil)
		end)
	end

	return {
		Cancel = function()
			finish("cancel", position, nil)
		end,
	}
end

return Kit
