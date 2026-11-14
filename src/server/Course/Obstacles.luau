--!strict
--[[
	Obstacles — fabrique des obstacles d'un trou (géométrie construite par code, mouvements serveur).

	  local model = Obstacles.spawn(def, parent, trove, options?)   -> Model?   (nil + avertissement unique si type inconnu)
	  Obstacles.kinds() -> { string }                                types reconnus (alias compris)
	  options = { preview: boolean?, groundRoot: Instance? }
	    preview     aperçu d'inspection : aucune animation, aucune connexion, aucun appel aux services
	    groundRoot  géométrie du trou utilisée pour recaler la base des obstacles posés au sol (défaut : parent.Parent)

	CONVENTIONS DU FORMAT (ObstacleDef, shared/Types.luau)
	  center  centre de l'obstacle en coordonnées MONDE (CourseService/HoleBuilder convertissent le repère local).
	          Obstacles posés au sol (tous sauf movingPlatform, lift, platform, swing, drawbridge) : s'il existe un
	          sol du trou entre la base (centre - hauteur/2) et le centre + 1,5 stud, la base est recalée sur ce sol.
	          On peut donc donner indifféremment le centre du volume ou le point au sol. Sinon (au-dessus d'un vide)
	          `center` est le centre du volume.
	  size    (largeur X, hauteur Y, longueur Z) dans le repère de l'obstacle ; défaut propre à chaque type.
	  yaw     cap en degrés, même convention que le format (depuis l'avant du parcours vers la droite) :
	          l'axe Z de l'obstacle (« longueur », « avant ») suit ce cap.
	  params  table propre au type (ci-dessous). Paramètres communs :
	          color (Color3 | nom de BrickColor), accent (Color3 | nom), material (nom d'Enum.Material),
	          surface (surface de golf : "Fairway" | "Rough" | "Green" | "Sand" | "Ice" | "Rock" | "Wood" |
	          "Asphalt" | "Snow" | "Mud" ; attribut "Surface" lu par BallService).
	          Mouvement : period (s, durée d'un cycle), speed (selon le type), amplitude (studs), axis
	          ("x"/"right", "y"/"up", "z"/"forward" ou Vector3 dans le repère de l'obstacle), phase (0..1,
	          décalage dans le cycle), direction (1 | -1). Le temps de référence est l'horloge serveur partagée
	          (workspace:GetServerTimeNow()) : à paramètres égaux, deux obstacles sont synchrones et reproductibles.

	TYPES ET PARAMÈTRES (défaut de size entre crochets)
	  wall          mur [16, 4, 1.5]. style "brick" | "hedge" | "wood" | "stone" | "ice" (défaut "brick").
	  hedge         alias : wall style "hedge".
	  ramp          rampe [10, 3, 14] qui MONTE vers l'avant (+Z). surface (défaut "Wood"), rails (bool, défaut true).
	  bumper        champignon rebondissant [3, 3, 3] (diamètre X, hauteur Y). bounce (multiplicateur de rebond de
	                la balle, défaut 1.35), minBounce (vitesse de sortie minimale studs/s, défaut 28), knock (recul des
	                joueurs studs/s, défaut 45). Propriétés physiques très élastiques + impulsion serveur.
	  windmill      moulin [10, 12, 8] avec tunnel à sa base (le long de Z) et pales tournant devant l'entrée.
	                period (s/tour, défaut 6), speed (degrés/s, remplace period), direction, phase, bladeLength
	                (défaut 5.5), blades (nombre, défaut 4), gap (largeur du tunnel, défaut 4.5), facing
	                ("back" défaut : pales côté départ | "forward"), knock (défaut 40).
	  movingPlatform plateforme [12, 1, 12] en va-et-vient sinusoïdal : axis (défaut "x"), amplitude (demi-course,
	                défaut 8), period (défaut 6), phase. Transporte joueurs (vitesse de surface) et balles (impulsion
	                de transport des balles posées dessus).
	  lift          alias : movingPlatform axis "y" (amplitude 5).
	  rotatingBar   barre balayeuse [20, 1, 1] (longueur X) autour d'un poteau central : height (hauteur du centre de la
	                barre, défaut 1.2), arms (1 ou 2 barres croisées, défaut 1), period (défaut 5), speed (degrés/s),
	                direction, phase, knock (défaut 42).
	  pillar        pilier [3, 8, 3] (diamètre X, hauteur Y), chapiteau et socle. shape "round" | "square".
	  arch          arche [12, 8, 3] (largeur X, hauteur Y, épaisseur Z), passage sous l'arche. thickness (pieds, défaut 2).
	  tunnel        tunnel [8, 6, 16] ouvert aux deux bouts (le long de Z). wall (épaisseur, défaut 1.5),
	                floor (bool, défaut false : la balle roule sur le sol du trou), surface du sol si floor.
	  jumpPad       trampoline [6, 1, 6]. power (vitesse verticale des joueurs, défaut 70), forward (vitesse vers +Z,
	                défaut 25), ballPower (défaut 42), ballForward (défaut 22). Joueurs : propulsion serveur
	                (MovementService.AllowDisplacement puis LinearVelocity brève) ; balles : BallService.ApplyBallImpulse.
	  conveyor      tapis roulant [8, 1, 20] vers +Z (vitesse de surface d'une Part ancrée). speed (studs/s, défaut 14,
	                négatif = vers -Z). Les balles immobiles posées dessus sont relancées (impulsion).
	  car           voiture cartoon en va-et-vient [6, 4.5, 11]. path (liste de Vector3 RELATIFS au centre, dans le
	                repère de l'obstacle ; défaut : deux points à ±distance/2 le long de axis), axis (défaut "z"),
	                distance (défaut 40), speed (studs/s, défaut 20), pause (s aux extrémités, défaut 0.8), loop (bool :
	                circuit fermé au lieu du va-et-vient), phase, model "car" | "bus" | "block", knock (défaut 60),
	                lift (défaut 28). Recul des joueurs (CombatService.Knockback), balles projetées (ApplyBallImpulse).
	  mover         même chose que car (modèle "car" par défaut, réglable).
	  platform      plateforme fixe praticable [12, 1, 12]. surface (défaut "Wood").
	  patch         zone de surface plate [12, 0.2, 12] posée sur le sol. surface (défaut "Sand"),
	                shape "cylinder" (défaut) | "box".
	  bunker        alias : patch surface "Sand".
	  swing         pont-levis [10, 1, 16] articulé sur son bord arrière (-Z) : minAngle (défaut 0), maxAngle
	                (défaut 70), period (défaut 8), phase. Les balles posées dessus sont emportées.
	  drawbridge    alias : swing.
	  stairs        escalier [10, 4, 10] montant vers +Z. steps (défaut 5), surface (défaut "Rock").

	PHYSIQUE ET RÉSEAU
	  Toutes les pièces sont ANCRÉES et possédées par le serveur. Les obstacles animés sont déplacés à chaque
	  Heartbeat (workspace:BulkMoveTo) et reçoivent AssemblyLinearVelocity / AssemblyAngularVelocity cohérentes
	  avec leur mouvement : les personnages et balles en contact sont entraînés par la physique. Les balles au
	  repos de BallService sont ancrées : les contacts avec elles sont détectés analytiquement (boîtes orientées)
	  et traités par BallService.ApplyBallImpulse ; les joueurs touchés par un élément mobile reçoivent
	  CombatService.Knockback (délai par joueur Config.Course.Animation.ContactCooldown).
	  Pièces jouables : groupe de collision "Course" ; décor non collidable : CanCollide/CanQuery/CanTouch false.
	  Tout (pièces, connexions, propulsions) appartient à la Trove passée à spawn.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Log = require(Shared.Util.Log)
local TroveModule = require(Shared.Util.Trove)
local Validate = require(Shared.Util.Validate)

type Trove = TroveModule.Trove
type ObstacleDef = Types.ObstacleDef

export type SpawnOptions = {
	preview: boolean?,
	groundRoot: Instance?,
}

type Params = { [string]: any }

-- Élément d'un groupe animé : pièce + décalage relatif au pivot du groupe.
type KinematicItem = { part: BasePart, offset: CFrame }

type Controller = {
	step: ((now: number, dt: number) -> ())?,
	hitParts: { BasePart }?,
	ballMargin: number?, -- marge de contact balle (en plus du rayon de la balle)
	ballCooldown: number?,
	onBall: ((ball: BasePart, owner: Player, part: BasePart, now: number) -> boolean)?,
	playerMargin: Vector3?,
	onPlayer: ((player: Player, root: BasePart, part: BasePart, now: number) -> boolean)?,
}

type Ctx = {
	kind: string,
	params: Params,
	size: Vector3,
	base: CFrame, -- centre de la base (au sol), orienté selon le cap
	center: CFrame, -- centre du volume
	model: Model,
	preview: boolean,
	trove: Trove,
	rng: Random,
}

type Builder = (ctx: Ctx) -> Controller?

--------------------------------------------------------------------------------
-- Réglages (défauts documentés ci-dessus ; Config.Course.Animation pour les contacts)
--------------------------------------------------------------------------------

local DEFAULT_CONTACT_INTERVAL = 0.1
local DEFAULT_CONTACT_COOLDOWN = 0.8
local DEFAULT_MAX_STEP = 0.1
local DEFAULT_BALL_RADIUS = 0.6
local DEFAULT_BALL_COOLDOWN = 0.3
local PLAYER_MARGIN = Vector3.new(1.3, 2.8, 1.3) -- demi-largeur d'un avatar autour de sa HumanoidRootPart
local GROUND_PROBE_UP = 1.5
local GROUND_PROBE_EXTRA = 1.5
local PUSH_MAX_FORCE = 1e6
local LAUNCH_DURATION = 0.18
local SNAPPED_KINDS: { [string]: boolean } = {
	movingPlatform = false,
	platform = false,
	swing = false,
}

local SURFACE_COLORS: { [string]: Color3 } = {
	Fairway = Color3.fromRGB(112, 200, 92),
	Rough = Color3.fromRGB(78, 156, 70),
	Green = Color3.fromRGB(128, 222, 104),
	Sand = Color3.fromRGB(240, 218, 150),
	Ice = Color3.fromRGB(190, 230, 255),
	Rock = Color3.fromRGB(150, 150, 160),
	Wood = Color3.fromRGB(176, 122, 74),
	Asphalt = Color3.fromRGB(70, 72, 80),
	Snow = Color3.fromRGB(245, 248, 255),
	Mud = Color3.fromRGB(110, 80, 55),
}
local SURFACE_MATERIALS: { [string]: Enum.Material } = {
	Fairway = Enum.Material.Grass,
	Rough = Enum.Material.Grass,
	Green = Enum.Material.SmoothPlastic,
	Sand = Enum.Material.Sand,
	Ice = Enum.Material.Ice,
	Rock = Enum.Material.Slate,
	Wood = Enum.Material.WoodPlanks,
	Asphalt = Enum.Material.Asphalt,
	Snow = Enum.Material.Snow,
	Mud = Enum.Material.Mud,
}

local PALETTE = {
	red = Color3.fromRGB(232, 72, 72),
	white = Color3.fromRGB(248, 246, 240),
	cream = Color3.fromRGB(246, 234, 210),
	yellow = Color3.fromRGB(255, 206, 64),
	blue = Color3.fromRGB(66, 140, 232),
	navy = Color3.fromRGB(44, 62, 104),
	purple = Color3.fromRGB(156, 98, 226),
	orange = Color3.fromRGB(255, 150, 60),
	green = Color3.fromRGB(88, 186, 84),
	hedge = Color3.fromRGB(60, 140, 62),
	wood = Color3.fromRGB(170, 112, 66),
	darkWood = Color3.fromRGB(110, 72, 44),
	stone = Color3.fromRGB(168, 168, 176),
	darkStone = Color3.fromRGB(118, 118, 128),
	metal = Color3.fromRGB(190, 196, 206),
	dark = Color3.fromRGB(40, 40, 48),
	glass = Color3.fromRGB(170, 220, 255),
	ice = Color3.fromRGB(196, 232, 255),
}
local CAR_COLORS = {
	Color3.fromRGB(232, 72, 72),
	Color3.fromRGB(66, 140, 232),
	Color3.fromRGB(255, 206, 64),
	Color3.fromRGB(88, 186, 84),
	Color3.fromRGB(156, 98, 226),
	Color3.fromRGB(255, 150, 60),
}

local Obstacles = {}

local builders: { [string]: Builder } = {}
local aliases: { [string]: { kind: string, params: Params } } = {
	hedge = { kind = "wall", params = { style = "hedge" } },
	lift = { kind = "movingPlatform", params = { axis = "y", amplitude = 5 } },
	bunker = { kind = "patch", params = { surface = "Sand" } },
	drawbridge = { kind = "swing", params = {} },
}
local warnedKinds: { [string]: boolean } = {}

--------------------------------------------------------------------------------
-- Accès paresseux (configuration, services, réseau)
--------------------------------------------------------------------------------

local configCache: { [string]: any } = {}

local function config(name: string): { [string]: any }
	local cached = configCache[name]
	if cached ~= nil then
		return cached
	end
	local result: any = {}
	local folder = Shared:FindFirstChild("Config")
	local module = folder and folder:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, loaded = pcall(require, module)
		if ok and type(loaded) == "table" then
			result = loaded
		end
	end
	configCache[name] = result
	return result
end

local function animationSetting(key: string, default: number): number
	local animation = config("Course").Animation
	local value = if type(animation) == "table" then animation[key] else nil
	return if Validate.isFiniteNumber(value) then value else default
end

local function ballRadius(): number
	local ball = config("Gameplay").Ball
	local diameter = if type(ball) == "table" then ball.Diameter else nil
	return if Validate.isFiniteNumber(diameter) then diameter / 2 else DEFAULT_BALL_RADIUS
end

local function ballTag(): string
	local ball = config("Gameplay").Ball
	local tag = if type(ball) == "table" then ball.Tag else nil
	return if type(tag) == "string" then tag else "GolfBall"
end

-- Service voisin chargé à la demande (Server.Util.Services) : aucun cycle de require au chargement.
local service = require(script.Parent.Parent.Util.Services).get

local netCache: any = nil
local function net(): any?
	if netCache == nil then
		local module = Shared:FindFirstChild("Net")
		local ok, result = pcall(function()
			return require(module :: any)
		end)
		netCache = if ok and type(result) == "table" then result else false
	end
	return if netCache then netCache else nil
end

local function playSound(name: string, position: Vector3)
	local Net = net()
	if Net and type(Net.fireAll) == "function" then
		pcall(Net.fireAll, "Effects.Sound", name, position, 1)
	end
end

local function playEffect(name: string, params: { [string]: any })
	local Net = net()
	if Net and type(Net.fireAll) == "function" then
		pcall(Net.fireAll, "Effects.Play", name, params)
	end
end

local function notifyKey(player: Player, key: string)
	local Net = net()
	if Net and type(Net.fire) == "function" then
		pcall(Net.fire, "Core.NotifyKey", player, key, {})
	end
end

local function impulseBall(owner: Player, velocity: Vector3, source: string): boolean
	local Ball = service("BallService")
	if not Ball or type(Ball.ApplyBallImpulse) ~= "function" then
		return false
	end
	local ok, result = pcall(Ball.ApplyBallImpulse, owner, velocity, source)
	return ok and result == true
end

local function knockPlayer(player: Player, velocity: Vector3, source: string): boolean
	local Combat = service("CombatService")
	if not Combat or type(Combat.Knockback) ~= "function" then
		return false
	end
	local ok, result = pcall(Combat.Knockback, player, velocity, { source = source })
	return ok and result == true
end

--------------------------------------------------------------------------------
-- Lecture des paramètres
--------------------------------------------------------------------------------

local function num(params: Params, key: string, default: number, min: number?, max: number?): number
	local value = params[key]
	if not Validate.isFiniteNumber(value) then
		return default
	end
	local result: number = value
	if min then
		result = math.max(result, min)
	end
	if max then
		result = math.min(result, max)
	end
	return result
end

local function bool(params: Params, key: string, default: boolean): boolean
	local value = params[key]
	if type(value) == "boolean" then
		return value
	end
	return default
end

local function str(params: Params, key: string, default: string): string
	local value = params[key]
	return if type(value) == "string" and value ~= "" then value else default
end

local function color(params: Params, key: string, default: Color3): Color3
	local value = params[key]
	if typeof(value) == "Color3" then
		return value
	end
	if type(value) == "string" then
		local ok, brick = pcall(BrickColor.new, value)
		if ok then
			return brick.Color
		end
	end
	return default
end

local function material(params: Params, default: Enum.Material): Enum.Material
	local value = params.material
	if typeof(value) == "EnumItem" and (value :: EnumItem).EnumType == Enum.Material then
		return value :: any
	end
	if type(value) == "string" then
		local ok, item = pcall(function()
			return (Enum.Material :: any)[value]
		end)
		if ok and typeof(item) == "EnumItem" then
			return item
		end
	end
	return default
end

local function surface(params: Params, default: string): string
	local value = params.surface
	if type(value) == "string" and SURFACE_COLORS[value] then
		return value
	end
	return default
end

-- Axe du mouvement dans le repère de l'obstacle (vecteur unitaire).
local function axisVector(value: any, default: Vector3): Vector3
	if typeof(value) == "Vector3" and Validate.isFiniteVector3(value) and value.Magnitude > 1e-3 then
		return value.Unit
	end
	if type(value) == "string" then
		local lower = string.lower(value)
		if lower == "x" or lower == "right" then
			return Vector3.xAxis
		elseif lower == "y" or lower == "up" then
			return Vector3.yAxis
		elseif lower == "z" or lower == "forward" then
			return Vector3.zAxis
		end
	end
	return default
end

-- Vitesse angulaire (rad/s) à partir de speed (degrés/s) ou de period (s/tour).
local function angularSpeed(params: Params, defaultPeriod: number): number
	local direction = if num(params, "direction", 1) < 0 then -1 else 1
	local speed = params.speed
	if Validate.isFiniteNumber(speed) then
		return math.rad(speed) * direction
	end
	local period = num(params, "period", defaultPeriod, 0.5, 600)
	return (2 * math.pi / period) * direction
end

-- Repère de l'obstacle (X droite, Y haut, Z avant) -> direction monde.
local function localToWorldDirection(frame: CFrame, v: Vector3): Vector3
	return frame.RightVector * v.X + frame.UpVector * v.Y + frame.LookVector * v.Z
end

--------------------------------------------------------------------------------
-- Construction de pièces
--------------------------------------------------------------------------------

type PartOptions = {
	shape: Enum.PartType?,
	wedge: boolean?,
	collide: boolean?,
	query: boolean?,
	transparency: number?,
	surface: string?,
	shadow: boolean?,
	physical: PhysicalProperties?,
	reflectance: number?,
}

local function newPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, partColor: Color3, partMaterial: Enum.Material?, opts: PartOptions?): BasePart
	local options: PartOptions = opts or {}
	local part: BasePart
	if options.wedge then
		part = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		if options.shape then
			block.Shape = options.shape
		end
		part = block
	end
	part.Name = name
	part.Anchored = true
	part.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	part.CFrame = cframe
	part.Color = partColor
	part.Material = partMaterial or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local collide = options.collide ~= false
	part.CanCollide = collide
	part.CanQuery = if options.query ~= nil then options.query else collide
	part.CanTouch = collide
	part.CastShadow = options.shadow ~= false
	if options.transparency then
		part.Transparency = options.transparency
	end
	if options.reflectance then
		part.Reflectance = options.reflectance
	end
	if options.surface then
		part:SetAttribute("Surface", options.surface)
	end
	if options.physical then
		part.CustomPhysicalProperties = options.physical
	end
	part.Parent = parent
	return part
end

-- Cylindre vertical (l'axe des cylindres Roblox est X).
local function verticalCylinder(parent: Instance, name: string, diameter: number, height: number, centerCFrame: CFrame, partColor: Color3, partMaterial: Enum.Material?, opts: PartOptions?): BasePart
	local options: PartOptions = table.clone(opts or {})
	options.shape = Enum.PartType.Cylinder
	return newPart(parent, name, Vector3.new(height, diameter, diameter), centerCFrame * CFrame.Angles(0, 0, math.pi / 2), partColor, partMaterial, options)
end

-- Décor non collidable (n'interfère ni avec les balles ni avec les requêtes spatiales).
local function decor(parent: Instance, name: string, size: Vector3, cframe: CFrame, partColor: Color3, partMaterial: Enum.Material?, opts: PartOptions?): BasePart
	local options: PartOptions = table.clone(opts or {})
	options.collide = false
	options.query = false
	return newPart(parent, name, size, cframe, partColor, partMaterial, options)
end

-- Chevron « > » couché au sol, pointe vers le LookVector du repère (deux barres lumineuses).
local function chevron(parent: Instance, frame: CFrame, width: number, partColor: Color3)
	local half = width / 2
	local tip = Vector3.new(0, 0, -half * 0.5)
	for _, side in { -1, 1 } do
		local tail = Vector3.new(side * half, 0, half * 0.5)
		local middle = (tip + tail) / 2
		local length = (tail - tip).Magnitude
		decor(parent, "Chevron", Vector3.new(0.35, 0.1, length + 0.3), frame * CFrame.lookAt(middle, tail), partColor, Enum.Material.Neon, { shadow = false })
	end
end

--------------------------------------------------------------------------------
-- Groupes animés et contacts
--------------------------------------------------------------------------------

type KinematicGroup = {
	items: { KinematicItem },
	parts: { BasePart },
	cframes: { CFrame },
}

local function newGroup(): KinematicGroup
	return { items = {}, parts = {}, cframes = {} }
end

local function addToGroup(group: KinematicGroup, part: BasePart, pivot: CFrame)
	table.insert(group.items, { part = part, offset = pivot:ToObjectSpace(part.CFrame) })
	table.insert(group.parts, part)
	table.insert(group.cframes, part.CFrame)
end

-- Place le groupe au pivot et donne à chaque pièce la vitesse réelle de son centre (v + ω × r).
local function moveGroup(group: KinematicGroup, pivot: CFrame, linear: Vector3, angular: Vector3)
	local cframes = group.cframes
	for index, item in group.items do
		cframes[index] = pivot * item.offset
	end
	Workspace:BulkMoveTo(group.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	local pivotPosition = pivot.Position
	for index, item in group.items do
		local part = item.part
		part.AssemblyLinearVelocity = linear + angular:Cross(cframes[index].Position - pivotPosition)
		part.AssemblyAngularVelocity = angular
	end
end

local function surfaceVelocityAt(part: BasePart, point: Vector3): Vector3
	return part.AssemblyLinearVelocity + part.AssemblyAngularVelocity:Cross(point - part.Position)
end

-- Point dans la boîte orientée d'une pièce, élargie de `margin` (par axe).
local function insideExpanded(part: BasePart, point: Vector3, margin: Vector3): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2 + margin
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

-- Caches partagés (une lecture par image pour tous les obstacles).
local ballsCache: { BasePart } = {}
local ballsCachedAt = -1
local function currentBalls(): { BasePart }
	local clock = os.clock()
	if clock - ballsCachedAt < 1 / 90 then
		return ballsCache
	end
	ballsCachedAt = clock
	local list: { BasePart } = {}
	for _, instance in CollectionService:GetTagged(ballTag()) do
		if instance:IsA("BasePart") and instance.Parent ~= nil then
			table.insert(list, instance)
		end
	end
	ballsCache = list
	return list
end

local function ballOwner(ball: BasePart): Player?
	local userId = ball:GetAttribute("OwnerUserId")
	if type(userId) ~= "number" or userId <= 0 then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

local function aliveRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Propulsion serveur d'un personnage (possédé par son client) : exemption de plausibilité puis contrainte brève
-- (la contrainte est répliquée et simulée par le client propriétaire).
local function launchCharacter(player: Player, root: BasePart, velocity: Vector3, reason: string, trove: Trove)
	local Movement = service("MovementService")
	if Movement and type(Movement.AllowDisplacement) == "function" then
		pcall(Movement.AllowDisplacement, player, 3, reason)
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "GolfChaosLaunch"
	local mover = Instance.new("LinearVelocity")
	mover.Name = "GolfChaosLaunch"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.MaxForce = PUSH_MAX_FORCE
	mover.VectorVelocity = velocity
	attachment.Parent = root
	mover.Parent = root
	local function cleanup()
		mover:Destroy()
		attachment:Destroy()
	end
	trove:Add(attachment)
	trove:Add(mover)
	task.delay(LAUNCH_DURATION, function()
		trove:Remove(attachment)
		trove:Remove(mover)
		cleanup()
	end)
end

local function runController(ctx: Ctx, controller: Controller)
	if ctx.preview then
		return
	end
	local contactInterval = animationSetting("ContactInterval", DEFAULT_CONTACT_INTERVAL)
	local contactCooldown = animationSetting("ContactCooldown", DEFAULT_CONTACT_COOLDOWN)
	local maxStep = animationSetting("MaxStep", DEFAULT_MAX_STEP)
	local radius = ballRadius()
	local ballMargin = Vector3.one * (radius + (controller.ballMargin or 0.25))
	local ballCooldown = controller.ballCooldown or DEFAULT_BALL_COOLDOWN
	local playerMargin = controller.playerMargin or PLAYER_MARGIN
	local ballTimes: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any
	local playerTimes: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
	local lastContact = 0
	local errored = false

	ctx.trove:Connect(RunService.Heartbeat, function(dt: number)
		local now = Workspace:GetServerTimeNow()
		local ok, err = pcall(function()
			local step = controller.step
			if step then
				step(now, math.min(dt, maxStep))
			end
			local hitParts = controller.hitParts
			if not hitParts or #hitParts == 0 then
				return
			end
			local onBall = controller.onBall
			if onBall then
				for _, ball in currentBalls() do
					local last = ballTimes[ball]
					if last and now - last < ballCooldown then
						continue
					end
					local stateValue = ball:GetAttribute("State")
					if stateValue == "Holed" or stateValue == "Frozen" then
						continue
					end
					for _, part in hitParts do
						if insideExpanded(part, ball.Position, ballMargin) then
							local owner = ballOwner(ball)
							if owner and onBall(ball, owner, part, now) then
								ballTimes[ball] = now
							end
							break
						end
					end
				end
			end
			local onPlayer = controller.onPlayer
			if onPlayer and now - lastContact >= contactInterval then
				lastContact = now
				for _, player in Players:GetPlayers() do
					local last = playerTimes[player]
					if last and now - last < contactCooldown then
						continue
					end
					local root = aliveRoot(player)
					if not root then
						continue
					end
					for _, part in hitParts do
						if insideExpanded(part, root.Position, playerMargin) then
							if onPlayer(player, root, part, now) then
								playerTimes[player] = now
							end
							break
						end
					end
				end
			end
		end)
		if not ok and not errored then
			errored = true -- une seule trace par obstacle (pas d'inondation du journal)
			Log.warn("Obstacles", ctx.kind, "erreur d'animation :", tostring(err))
		end
	end)
end

-- Recul d'un joueur touché par une pièce mobile (ou repoussé hors d'une pièce fixe).
local function sweepKnock(source: string, knock: number, lift: number)
	return function(player: Player, root: BasePart, part: BasePart, _now: number): boolean
		local surfaceVelocity = surfaceVelocityAt(part, root.Position)
		local horizontal = Vector3.new(surfaceVelocity.X, 0, surfaceVelocity.Z)
		local direction: Vector3
		if horizontal.Magnitude > 2 then
			direction = horizontal.Unit
		else
			local away = root.Position - part.Position
			away = Vector3.new(away.X, 0, away.Z)
			direction = if away.Magnitude > 1e-3 then away.Unit else part.CFrame.LookVector
		end
		return knockPlayer(player, direction * knock + Vector3.new(0, lift, 0), source)
	end
end

-- Balle frappée par une pièce mobile : on lui donne au moins la vitesse de la surface (×1,2) dans ce sens.
local function sweepBall(source: string, minKick: number)
	return function(ball: BasePart, owner: Player, part: BasePart, _now: number): boolean
		local position = ball.Position
		local surfaceVelocity = surfaceVelocityAt(part, position)
		local push: Vector3
		if surfaceVelocity.Magnitude > 1 then
			push = surfaceVelocity * 1.2
			if push.Magnitude < minKick then
				push = push.Unit * minKick
			end
		else
			return false -- pièce immobile : la physique suffit
		end
		local direction = push.Unit
		local current = ball.AssemblyLinearVelocity
		local along = current:Dot(direction)
		if along >= push.Magnitude then
			return false
		end
		local delta = direction * (push.Magnitude - along) + Vector3.new(0, 4, 0)
		return impulseBall(owner, delta, source)
	end
end

-- Balle posée sur une pièce mobile (plateforme, pont-levis, tapis) : relancée à la vitesse de la surface.
local function carryBall(source: string, part: BasePart, ball: BasePart, owner: Player): boolean
	if ball:GetAttribute("State") ~= "Resting" then
		return false
	end
	local localPoint = part.CFrame:PointToObjectSpace(ball.Position)
	if localPoint.Y < part.Size.Y / 2 - 0.2 then
		return false -- sur le côté, pas dessus
	end
	local velocity = surfaceVelocityAt(part, ball.Position)
	if velocity.Magnitude < 0.5 then
		return false
	end
	return impulseBall(owner, velocity, source)
end

--------------------------------------------------------------------------------
-- Types d'obstacles
--------------------------------------------------------------------------------

builders.wall = function(ctx: Ctx): Controller?
	local size, params, model = ctx.size, ctx.params, ctx.model
	local style = str(params, "style", "brick")
	local mainColor, trimColor, mat, surfaceName =
		PALETTE.white, PALETTE.red, Enum.Material.SmoothPlastic, "Rock"
	if style == "hedge" then
		mainColor, trimColor, mat, surfaceName = PALETTE.hedge, Color3.fromRGB(78, 168, 74), Enum.Material.Grass, "Rough"
	elseif style == "wood" then
		mainColor, trimColor, mat, surfaceName = PALETTE.wood, PALETTE.darkWood, Enum.Material.WoodPlanks, "Wood"
	elseif style == "stone" then
		mainColor, trimColor, mat, surfaceName = PALETTE.stone, PALETTE.darkStone, Enum.Material.Slate, "Rock"
	elseif style == "ice" then
		mainColor, trimColor, mat, surfaceName = PALETTE.ice, PALETTE.white, Enum.Material.Ice, "Ice"
	elseif style == "brick" then
		mainColor, trimColor, mat = Color3.fromRGB(214, 110, 86), PALETTE.cream, Enum.Material.Brick
	end
	mainColor = color(params, "color", mainColor)
	trimColor = color(params, "accent", trimColor)
	local body = newPart(model, "Mur", size, ctx.center, mainColor, material(params, mat), { surface = surface(params, surfaceName) })
	model.PrimaryPart = body
	if style == "hedge" then
		-- Boules de feuillage sur le dessus : silhouette cartoon.
		local count = math.max(1, math.floor(size.X / 3))
		for index = 1, count do
			local x = -size.X / 2 + (index - 0.5) * size.X / count
			decor(model, "Feuillage", Vector3.new(size.Z * 1.25, size.Z * 1.25, size.Z * 1.25), ctx.base * CFrame.new(x, size.Y, 0), trimColor, Enum.Material.Grass, { shape = Enum.PartType.Ball })
		end
	else
		newPart(model, "Chaperon", Vector3.new(size.X + 0.4, 0.4, size.Z + 0.4), ctx.base * CFrame.new(0, size.Y + 0.2, 0), trimColor, Enum.Material.SmoothPlastic, { surface = surfaceName })
	end
	return nil
end

builders.ramp = function(ctx: Ctx): Controller?
	local size, params, model = ctx.size, ctx.params, ctx.model
	local surfaceName = surface(params, "Wood")
	local mainColor = color(params, "color", SURFACE_COLORS[surfaceName] or PALETTE.wood)
	-- Une WedgePart monte vers son arrière (+Z local) : demi-tour pour qu'elle monte vers l'avant du parcours.
	local wedgeFrame = ctx.center * CFrame.Angles(0, math.pi, 0)
	local ramp = newPart(model, "Rampe", size, wedgeFrame, mainColor, material(params, SURFACE_MATERIALS[surfaceName] or Enum.Material.WoodPlanks), {
		wedge = true,
		surface = surfaceName,
	})
	model.PrimaryPart = ramp
	if bool(params, "rails", true) then
		local accent = color(params, "accent", PALETTE.red)
		local length = math.sqrt(size.Y * size.Y + size.Z * size.Z)
		local angle = math.atan2(size.Y, size.Z)
		for _, side in { -1, 1 } do
			local railFrame = ctx.base * CFrame.new(side * (size.X / 2 + 0.25), size.Y / 2 + 0.6, 0) * CFrame.Angles(angle, 0, 0)
			newPart(model, "Rail", Vector3.new(0.5, 0.5, length), railFrame, accent, Enum.Material.SmoothPlastic)
		end
	end
	return nil
end

builders.bumper = function(ctx: Ctx): Controller?
	local size, params, model = ctx.size, ctx.params, ctx.model
	local diameter = math.max(size.X, 1)
	local height = math.max(size.Y, 1)
	local bounce = num(params, "bounce", 1.35, 1, 3)
	local minBounce = num(params, "minBounce", 28, 0, 120)
	local knock = num(params, "knock", 45, 0, 150)
	local springy = PhysicalProperties.new(0.7, 0.1, 1, 1, 100)
	local stem = verticalCylinder(model, "Pied", diameter * 0.55, height * 0.6, ctx.base * CFrame.new(0, height * 0.3, 0), PALETTE.cream, Enum.Material.SmoothPlastic, {
		physical = springy,
		surface = "Rock",
	})
	local cap = verticalCylinder(model, "Chapeau", diameter, height * 0.45, ctx.base * CFrame.new(0, height * 0.78, 0), color(params, "color", PALETTE.red), Enum.Material.SmoothPlastic, {
		physical = springy,
		surface = "Rock",
	})
	decor(model, "Dome", Vector3.one * diameter, ctx.base * CFrame.new(0, height * 0.75, 0), color(params, "color", PALETTE.red), Enum.Material.SmoothPlastic, { shape = Enum.PartType.Ball })
	for index = 1, 4 do
		local angle = index * math.pi / 2
		decor(model, "Pois", Vector3.new(0.6, 0.6, 0.6), ctx.base * CFrame.Angles(0, angle, 0) * CFrame.new(0, height * 0.82, -diameter / 2), PALETTE.white, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Ball })
	end
	decor(model, "Anneau", Vector3.new(0.3, diameter * 0.75, diameter * 0.75), ctx.base * CFrame.new(0, height * 0.6, 0) * CFrame.Angles(0, 0, math.pi / 2), PALETTE.yellow, Enum.Material.Neon, { shape = Enum.PartType.Cylinder })
	model.PrimaryPart = cap
	local center = ctx.base.Position
	return {
		hitParts = { stem, cap },
		ballMargin = 0.6,
		ballCooldown = 0.25,
		onBall = function(ball: BasePart, owner: Player, _part: BasePart, _now: number): boolean
			local offset = ball.Position - center
			local normal = Vector3.new(offset.X, 0, offset.Z)
			if normal.Magnitude < 1e-3 then
				return false
			end
			normal = normal.Unit
			local velocity = ball.AssemblyLinearVelocity
			local normalSpeed = velocity:Dot(normal)
			local target = math.max(math.abs(normalSpeed) * bounce, minBounce)
			if normalSpeed >= target then
				return false
			end
			if impulseBall(owner, normal * (target - normalSpeed), "bumper") then
				playSound("ball_bounce", ball.Position)
				playEffect("HitSpark", { position = ball.Position, color = PALETTE.yellow })
				return true
			end
			return false
		end,
		onPlayer = function(player: Player, root: BasePart, _part: BasePart, _now: number): boolean
			local away = root.Position - center
			away = Vector3.new(away.X, 0, away.Z)
			local direction = if away.Magnitude > 1e-3 then away.Unit else Vector3.zAxis
			return knockPlayer(player, direction * knock + Vector3.new(0, 18, 0), "bumper")
		end,
	}
end

builders.windmill = function(ctx: Ctx): Controller?
	local size, params, model = ctx.size, ctx.params, ctx.model
	local width = math.max(size.X, 6)
	local depth = math.max(size.Z, 4)
	local bladeLength = num(params, "bladeLength", 5.5, 2, 20)
	local bladeCount = math.floor(num(params, "blades", 4, 2, 8))
	local gap = math.min(num(params, "gap", 4.5, 2, 20), width - 1.5)
	local tunnelHeight = num(params, "tunnelHeight", 3.5, 1.5, 10)
	local knock = num(params, "knock", 40, 0, 150)
	local bodyHeight = math.max(bladeLength + 2, tunnelHeight + 2.5, size.Y * 0.6)
	local roofHeight = math.max(size.Y - bodyHeight, 3)
	local bodyColor = color(params, "color", PALETTE.cream)
	local roofColor = color(params, "accent", PALETTE.red)
	local base = ctx.base

	-- Corps : deux blocs latéraux et un linteau au-dessus du tunnel.
	local sideWidth = (width - gap) / 2
	for _, side in { -1, 1 } do
		newPart(model, "Mur", Vector3.new(sideWidth, bodyHeight, depth), base * CFrame.new(side * (gap / 2 + sideWidth / 2), bodyHeight / 2, 0), bodyColor, Enum.Material.SmoothPlastic, { surface = "Wood" })
	end
	local lintel = newPart(model, "Linteau", Vector3.new(gap, bodyHeight - tunnelHeight, depth), base * CFrame.new(0, tunnelHeight + (bodyHeight - tunnelHeight) / 2, 0), bodyColor, Enum.Material.SmoothPlastic, { surface = "Wood" })
	model.PrimaryPart = lintel
	-- Bandeaux et encadrement de porte.
	decor(model, "Bandeau", Vector3.new(width + 0.3, 0.5, depth + 0.3), base * CFrame.new(0, bodyHeight - 0.25, 0), roofColor, Enum.Material.SmoothPlastic)
	for _, faceZ in { -1, 1 } do
		decor(model, "Porte", Vector3.new(gap + 0.8, 0.6, 0.3), base * CFrame.new(0, tunnelHeight + 0.3, faceZ * (depth / 2 + 0.1)), PALETTE.darkWood, Enum.Material.WoodPlanks)
	end
	-- Toit à deux pans (faîte le long de Z).
	for _, side in { -1, 1 } do
		local roofFrame = base * CFrame.new(side * width / 4, bodyHeight + roofHeight / 2, 0) * CFrame.Angles(0, -side * math.pi / 2, 0)
		newPart(model, "Toit", Vector3.new(depth + 0.8, roofHeight, width / 2 + 0.4), roofFrame, roofColor, Enum.Material.SmoothPlastic, { wedge = true })
	end
	-- Fenêtre ronde.
	local facingSign = if str(params, "facing", "back") == "forward" then -1 else 1
	decor(model, "Fenetre", Vector3.new(0.3, 1.6, 1.6), base * CFrame.new(0, bodyHeight + roofHeight * 0.35, facingSign * (depth / 2 + 0.05)) * CFrame.Angles(0, math.pi / 2, 0), PALETTE.glass, Enum.Material.Glass, { shape = Enum.PartType.Cylinder })

	-- Moyeu et pales (côté départ par défaut : face +Z du repère CFrame = vers l'arrière du parcours).
	local hubHeight = bladeLength + 0.9 -- bout de pale à 0,3 stud du sol : la balle (1,2) ne passe pas dessous
	local hubFrame = base * CFrame.new(0, hubHeight, facingSign * (depth / 2 + 0.9))
	decor(model, "Axe", Vector3.new(1.6, 1.2, 1.2), hubFrame * CFrame.new(0, 0, -facingSign * 0.6) * CFrame.Angles(0, math.pi / 2, 0), PALETTE.darkWood, Enum.Material.Wood, { shape = Enum.PartType.Cylinder })
	local group = newGroup()
	local hitParts: { BasePart } = {}
	local hub = newPart(model, "Moyeu", Vector3.new(0.8, 1.6, 1.6), hubFrame * CFrame.Angles(0, math.pi / 2, 0), PALETTE.yellow, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
	addToGroup(group, hub, hubFrame)
	for index = 1, bladeCount do
		local angle = (index - 1) * 2 * math.pi / bladeCount
		local arm = hubFrame * CFrame.Angles(0, 0, angle)
		local sail = newPart(model, "Pale", Vector3.new(1.8, bladeLength, 0.4), arm * CFrame.new(0.45, bladeLength / 2 + 0.6, 0), PALETTE.white, Enum.Material.SmoothPlastic, { surface = "Wood" })
		local spar = newPart(model, "Longeron", Vector3.new(0.4, bladeLength + 0.6, 0.5), arm * CFrame.new(-0.6, bladeLength / 2 + 0.3, 0), PALETTE.darkWood, Enum.Material.Wood, { surface = "Wood" })
		addToGroup(group, sail, hubFrame)
		addToGroup(group, spar, hubFrame)
		table.insert(hitParts, sail)
		table.insert(hitParts, spar)
	end

	local omega = angularSpeed(params, 6)
	local phase = num(params, "phase", 0) * 2 * math.pi
	local axis = hubFrame.LookVector
	local angularVelocity = axis * -omega
	local function step(now: number, _dt: number)
		local angle = (now * omega + phase) % (2 * math.pi)
		moveGroup(group, hubFrame * CFrame.Angles(0, 0, angle), Vector3.zero, angularVelocity)
	end
	step(Workspace:GetServerTimeNow(), 0)
	return {
		step = step,
		hitParts = hitParts,
		ballMargin = 0.3,
		onBall = sweepBall("windmill", 12),
		onPlayer = sweepKnock("windmill", knock, 22),
	}
end

builders.movingPlatform = function(ctx: Ctx): Controller?
	local size, params, model = ctx.size, ctx.params, ctx.model
	local surfaceName = surface(params, "Wood")
	local mainColor = color(params, "color", PALETTE.blue)
	local slab = newPart(model, "Plateforme", size, ctx.center, mainColor, material(params, Enum.Material.SmoothPlastic), { surface = surfaceName })
	model.PrimaryPart = slab
	local group = newGroup()
	addToGroup(group, slab, ctx.center)
	-- Liseré jaune et flèches de direction (décor qui suit la plateforme).
	local accent = color(params, "accent", PALETTE.yellow)
	for _, side in { -1, 1 } do
		local edge = decor(model, "Lisere", Vector3.new(size.X + 0.2, 0.25, 0.5), ctx.center * CFrame.new(0, size.Y / 2 + 0.05, side * (size.Z / 2 - 0.25)), accent, Enum.Material.SmoothPlastic)
		addToGroup(group, edge, ctx.center)
		local edge2 = decor(model, "Lisere", Vector3.new(0.5, 0.25, size.Z + 0.2), ctx.center * CFrame.new(side * (size.X / 2 - 0.25), size.Y / 2 + 0.05, 0), accent, Enum.Material.SmoothPlastic)
		addToGroup(group, edge2, ctx.center)
	end
	local axisLocal = axisVector(params.axis, Vector3.xAxis)
	local axisWorld = localToWorldDirection(ctx.center, axisLocal)
	local amplitude = num(params, "amplitude", 8, 0, 200)
	local period = num(params, "period", 6, 0.5, 600)
	local omega = 2 * math.pi / period
	local phase = num(params, "phase", 0) * 2 * math.pi
	local origin = ctx.center
	local function step(now: number, _dt: number)
		local angle = now * omega + phase
		local offset = axisWorld * (amplitude * math.sin(angle))
		local velocity = axisWorld * (amplitude * omega * math.cos(angle))
		moveGroup(group, origin + offset, velocity, Vector3.zero)
	end
	step(Workspace:GetServerTimeNow(), 0)
	return {
		step = step,
		hitParts = { slab },
		ballMargin = 0.35,
		ballCooldown = 0.25,
		onBall = function(ball: BasePart, owner: Player, part: BasePart, now: number): boolean
			if carryBall("movingPlatform", part, ball, owner) then
				return true
			end
			return sweepBall("movingPlatform", 8)(ball, owner, part, now)
		end,
	}
end

builders.rotatingBar = function(ctx: Ctx): Controller?
	local size, params, model = ctx.size, ctx.params, ctx.model
	local length = math.max(size.X, 4)
	local thickness = math.max(math.min(size.Y, size.Z), 0.6)
	local barHeight = num(params, "height", 1.2, thickness / 2, 30)
	local arms = math.floor(num(params, "arms", 1, 1, 2))
	local knock = num(params, "knock", 42, 0, 150)
	local base = ctx.base
	local postHeight = barHeight + 1.2
	verticalCylinder(model, "Poteau", 1.8, postHeight, base * CFrame.new(0, postHeight / 2, 0), PALETTE.metal, Enum.Material.Metal, { surface = "Rock" })
	verticalCylinder(model, "Socle", 3.2, 0.5, base * CFrame.new(0, 0.25, 0), PALETTE.darkStone, Enum.Material.SmoothPlastic, { surface = "Rock" })
	local pivot = base * CFrame.new(0, barHeight, 0)
	local group = newGroup()
	local hitParts: { BasePart } = {}
	local barColor = color(params, "color", PALETTE.red)
	for armIndex = 1, arms do
		local armFrame = pivot * CFrame.Angles(0, (armIndex - 1) * math.pi / 2, 0)
		local bar = newPart(model, "Barre", Vector3.new(length, thickness, thickness), armFrame, barColor, Enum.Material.SmoothPlastic, { surface = "Rock" })
		addToGroup(group, bar, pivot)
		table.insert(hitParts, bar)
		-- Bandes blanches (lisibilité du danger).
		for stripe = -2, 2 do
			if stripe ~= 0 then
				local band = decor(model, "Bande", Vector3.new(0.8, thickness + 0.08, thickness + 0.08), armFrame * CFrame.new(stripe * length / 5, 0, 0), PALETTE.white, Enum.Material.SmoothPlastic)
				addToGroup(group, band, pivot)
			end
		end
		for _, side in { -1, 1 } do
			local tip = decor(model, "Embout", Vector3.new(thickness * 1.5, thickness * 1.5, thickness * 1.5), armFrame * CFrame.new(side * length / 2, 0, 0), PALETTE.yellow, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Ball })
			addToGroup(group, tip, pivot)
		end
	end
	local cap = newPart(model, "Chapeau", Vector3.new(0.8, 2.4, 2.4), pivot * CFrame.new(0, thickness / 2 + 0.4, 0) * CFrame.Angles(0, 0, math.pi / 2), PALETTE.yellow, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
	addToGroup(group, cap, pivot)
	model.PrimaryPart = cap
	local omega = angularSpeed(params, 5)
	local phase = num(params, "phase", 0) * 2 * math.pi
	local angularVelocity = Vector3.new(0, omega, 0)
	local function step(now: number, _dt: number)
		local angle = (now * omega + phase) % (2 * math.pi)
		moveGroup(group, pivot * CFrame.Angles(0, angle, 0), Vector3.zero, angularVelocity)
	end
	step(Workspace:GetServerTimeNow(), 0)
	return {
		step = step,
		hitParts = hitParts,
		ballMargin = 0.3,
		onBall = sweepBall("rotatingBar", 14),
		onPlayer = sweepKnock("rotatingBar", knock, 24),
	}
end

builders.pillar = function(ctx: Ctx): Controller?
	local size, params, model = ctx.size, ctx.params, ctx.model
	local diameter = math.max(size.X, 0.8)
	local height = math.max(size.Y, 1)
	local mainColor = color(params, "color", PALETTE.stone)
	local accent = color(params, "accent", PALETTE.cream)
	local square = str(params, "shape", "round") == "square"
	local shaft: BasePart
	if square then
		shaft = newPart(model, "Fut", Vector3.new(diameter, height, diameter), ctx.center, mainColor, material(params, Enum.Material.SmoothPlastic), { surface = "Rock" })
		newPart(model, "Socle", Vector3.new(diameter + 0.8, 0.6, diameter + 0.8), ctx.base * CFrame.new(0, 0.3, 0), accent, Enum.Material.SmoothPlastic, { surface = "Rock" })
		newPart(model, "Chapiteau", Vector3.new(diameter + 0.8, 0.6, diameter + 0.8), ctx.base * CFrame.new(0, height - 0.3, 0), accent, Enum.Material.SmoothPlastic, { surface = "Rock" })
	else
		shaft = verticalCylinder(model, "Fut", diameter, height, ctx.center, mainColor, material(params, Enum.Material.SmoothPlastic), { surface = "Rock" })
		verticalCylinder(model, "Socle", diameter + 0.8, 0.6, ctx.base * CFrame.new(0, 0.3, 0), accent, Enum.Material.SmoothPlastic, { surface = "Rock" })
		verticalCylinder(model, "Chapiteau", diameter + 0.8, 0.6, ctx.base * CFrame.new(0, height - 0.3, 0), accent, Enum.Material.SmoothPlastic, { surface = "Rock" })
	end
	model.PrimaryPart = shaft
	return nil
end

builders.arch = function(ctx: Ctx): Controller?
	local size, params, model = ctx.size, ctx.params, ctx.model
	local width = math.max(size.X, 4)
	local height = math.max(size.Y, 3)
	local depth = math.max(size.Z, 1)
	local leg = math.min(num(params, "thickness", 2, 0.5, 10), width / 3)
	local beam = math.min(leg, height / 3)
	local mainColor = color(params, "color", Color3.fromRGB(222, 150, 96))
	local accent = color(params, "accent", PALETTE.cream)
	local mat = material(params, Enum.Material.Sandstone)
	for _, side in { -1, 1 } do
		newPart(model, "Pied", Vector3.new(leg, height - beam, depth), ctx.base * CFrame.new(side * (width / 2 - leg / 2), (height - beam) / 2, 0), mainColor, mat, { surface = "Rock" })
		-- Écoinçons arrondis sous la poutre (deux coins en biseau).
		local corner = math.min(leg * 1.2, (height - beam) / 2)
		local wedgeFrame = ctx.base * CFrame.new(side * (width / 2 - leg - corner / 2), height - beam - corner / 2, 0) * CFrame.Angles(0, side * math.pi / 2, math.pi)
		newPart(model, "Ecoincon", Vector3.new(depth, corner, corner), wedgeFrame, mainColor, mat, { wedge = true, surface = "Rock" })
	end
	local top = newPart(model, "Poutre", Vector3.new(width, beam, depth), ctx.base * CFrame.new(0, height - beam / 2, 0), mainColor, mat, { surface = "Rock" })
	newPart(model, "Corniche", Vector3.new(width + 0.6, 0.4, depth + 0.6), ctx.base * CFrame.new(0, height + 0.2, 0), accent, Enum.Material.SmoothPlastic, { surface = "Rock" })
	model.PrimaryPart = top
	return nil
end

builders.tunnel = function(ctx: Ctx): Controller?
	local size, params, model = ctx.size, ctx.params, ctx.model
	local width = math.max(size.X, 3)
	local height = math.max(size.Y, 2)
	local length = math.max(size.Z, 2)
	local wall = num(params, "wall", 1.5, 0.4, 6)
	local mainColor = color(params, "color", PALETTE.stone)
	local accent = color(params, "accent", PALETTE.yellow)
	local mat = material(params, Enum.Material.Slate)
	for _, side in { -1, 1 } do
		newPart(model, "Paroi", Vector3.new(wall, height, length), ctx.base * CFrame.new(side * (width / 2 + wall / 2), height / 2, 0), mainColor, mat, { surface = "Rock" })
	end
	local roof = newPart(model, "Voute", Vector3.new(width + wall * 2, wall, length), ctx.base * CFrame.new(0, height + wall / 2, 0), mainColor, mat, { surface = "Rock" })
	model.PrimaryPart = roof
	for _, faceZ in { -1, 1 } do
		-- Encadrement rayé jaune/noir aux deux entrées.
		local z = faceZ * (length / 2 + 0.15)
		decor(model, "Cadre", Vector3.new(width + wall * 2 + 0.4, 0.8, 0.3), ctx.base * CFrame.new(0, height + 0.4, z), accent, Enum.Material.SmoothPlastic)
		for _, side in { -1, 1 } do
			decor(model, "Montant", Vector3.new(0.8, height, 0.3), ctx.base * CFrame.new(side * (width / 2 + 0.4), height / 2, z), accent, Enum.Material.SmoothPlastic)
		end
	end
	if bool(params, "floor", false) then
		local surfaceName = surface(params, "Fairway")
		newPart(model, "Sol", Vector3.new(width, 0.4, length), ctx.base * CFrame.new(0, 0.2, 0), SURFACE_COLORS[surfaceName], SURFACE_MATERIALS[surfaceName], { surface = surfaceName })
	end
	return nil
end

builders.jumpPad = function(ctx: Ctx): Controller?
	local size, params, model = ctx.size, ctx.params, ctx.model
	local height = math.max(size.Y, 0.4)
	local power = num(params, "power", 70, 0, 250)
	local forward = num(params, "forward", 25, -150, 150)
	local ballPower = num(params, "ballPower", 42, 0, 200)
	local ballForward = num(params, "ballForward", 22, -150, 150)
	local mainColor = color(params, "color", PALETTE.purple)
	local frame = newPart(model, "Cadre", Vector3.new(size.X, height, size.Z), ctx.center, PALETTE.dark, Enum.Material.SmoothPlastic, { surface = "Rock" })
	local pad = newPart(model, "Toile", Vector3.new(size.X - 0.8, 0.2, size.Z - 0.8), ctx.base * CFrame.new(0, height + 0.1, 0), mainColor, Enum.Material.SmoothPlastic, { surface = "Rock" })
	-- Flèche lumineuse vers l'avant (indique la direction de la propulsion).
	local arrowLength = math.min(size.Z * 0.5, 3)
	chevron(model, ctx.base * CFrame.new(0, height + 0.27, 0), arrowLength, PALETTE.yellow)
	chevron(model, ctx.base * CFrame.new(0, height + 0.27, -arrowLength * 0.6), arrowLength, PALETTE.yellow)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			decor(model, "Ressort", Vector3.new(0.7, 0.7, 0.7), ctx.base * CFrame.new(x * (size.X / 2 - 0.4), height + 0.1, z * (size.Z / 2 - 0.4)), PALETTE.yellow, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Ball })
		end
	end
	model.PrimaryPart = pad
	local look = ctx.base.LookVector
	local top = ctx.base.Position.Y + height + 0.2
	local playerLaunch = look * forward + Vector3.new(0, power, 0)
	local ballLaunch = look * ballForward + Vector3.new(0, ballPower, 0)
	local trove = ctx.trove
	return {
		hitParts = { frame, pad },
		ballMargin = 0.5,
		ballCooldown = 0.8,
		playerMargin = Vector3.new(0.6, 3.2, 0.6),
		onBall = function(ball: BasePart, owner: Player, _part: BasePart, _now: number): boolean
			if ball.Position.Y < top - 0.2 then
				return false
			end
			local delta = ballLaunch - ball.AssemblyLinearVelocity
			if impulseBall(owner, delta, "jumpPad") then
				playSound("spring_boing", ball.Position)
				return true
			end
			return false
		end,
		onPlayer = function(player: Player, root: BasePart, _part: BasePart, _now: number): boolean
			local feet = root.Position.Y - 3
			if feet < top - 1 or feet > top + 1.5 then
				return false
			end
			launchCharacter(player, root, playerLaunch, "jumpPad", trove)
			playSound("spring_boing", root.Position)
			playEffect("Ring", { position = ctx.base.Position + Vector3.new(0, height + 0.3, 0), radius = math.max(size.X, size.Z) * 0.6, duration = 0.4, color = mainColor })
			notifyKey(player, "course.obstacle.jumpPad")
			return true
		end,
	}
end

builders.conveyor = function(ctx: Ctx): Controller?
	local size, params, model = ctx.size, ctx.params, ctx.model
	local speed = num(params, "speed", 14, -80, 80)
	local surfaceName = surface(params, "Asphalt")
	local belt = newPart(model, "Tapis", size, ctx.center, color(params, "color", PALETTE.dark), Enum.Material.SmoothPlastic, { surface = surfaceName })
	model.PrimaryPart = belt
	local direction = if speed >= 0 then 1 else -1
	-- Chevrons fixes indiquant le sens.
	local count = math.max(1, math.floor(size.Z / 4))
	for index = 1, count do
		local z = -size.Z / 2 + (index - 0.5) * size.Z / count
		local chevronFrame = ctx.base * CFrame.new(0, size.Y + 0.06, z) * CFrame.Angles(0, if direction > 0 then 0 else math.pi, 0)
		chevron(model, chevronFrame, math.min(size.X * 0.6, 3), PALETTE.yellow)
	end
	for _, side in { -1, 1 } do
		newPart(model, "Bord", Vector3.new(0.6, size.Y + 0.6, size.Z), ctx.base * CFrame.new(side * (size.X / 2 + 0.3), (size.Y + 0.6) / 2, 0), PALETTE.metal, Enum.Material.Metal, { surface = "Rock" })
	end
	if not ctx.preview then
		belt.AssemblyLinearVelocity = ctx.base.LookVector * speed
	end
	return {
		hitParts = { belt },
		ballMargin = 0.35,
		ballCooldown = 0.2,
		onBall = function(ball: BasePart, owner: Player, part: BasePart, _now: number): boolean
			return carryBall("conveyor", part, ball, owner)
		end,
	}
end

-- Pose (position, cap, vitesse) d'un véhicule sur son trajet, à l'instant `now`.
type PathPose = { position: Vector3, heading: Vector3, velocity: Vector3 }

local function buildPathSampler(points: { Vector3 }, speed: number, pause: number, loop: boolean, phase: number): (now: number) -> PathPose
	local route = table.clone(points)
	if loop then
		table.insert(route, points[1])
	end
	local lengths: { number } = {}
	local total = 0
	for index = 1, #route - 1 do
		local length = (route[index + 1] - route[index]).Magnitude
		lengths[index] = length
		total += length
	end
	total = math.max(total, 1e-3)
	local travel = total / speed
	local cycle = if loop then travel else 2 * (travel + pause)

	local function along(distance: number): (Vector3, Vector3)
		local remaining = distance
		for index = 1, #route - 1 do
			local length = lengths[index]
			if remaining <= length or index == #route - 1 then
				local t = if length > 1e-6 then math.clamp(remaining / length, 0, 1) else 0
				local a, b = route[index], route[index + 1]
				local dir = b - a
				return a + dir * t, if dir.Magnitude > 1e-6 then dir.Unit else Vector3.zAxis
			end
			remaining -= length
		end
		return route[#route], Vector3.zAxis
	end

	return function(now: number): PathPose
		local t = (now + phase * cycle) % cycle
		if loop then
			local position, heading = along(t * speed)
			return { position = position, heading = heading, velocity = heading * speed }
		end
		if t < travel then
			local position, heading = along(t * speed)
			return { position = position, heading = heading, velocity = heading * speed }
		end
		t -= travel
		if t < pause then
			-- Demi-tour progressif pendant la pause en bout de course.
			local position, heading = along(total)
			local alpha = t / math.max(pause, 1e-3)
			local turned = CFrame.fromAxisAngle(Vector3.yAxis, math.pi * alpha):VectorToWorldSpace(heading)
			return { position = position, heading = turned, velocity = Vector3.zero }
		end
		t -= pause
		if t < travel then
			local position, heading = along(total - t * speed)
			return { position = position, heading = -heading, velocity = -heading * speed }
		end
		t -= travel
		local position, heading = along(0)
		local alpha = t / math.max(pause, 1e-3)
		local turned = CFrame.fromAxisAngle(Vector3.yAxis, math.pi * alpha):VectorToWorldSpace(-heading)
		return { position = position, heading = turned, velocity = Vector3.zero }
	end
end

local function buildCarBody(model: Model, size: Vector3, pivot: CFrame, bodyColor: Color3, kind: string): ({ BasePart }, { BasePart })
	local parts: { BasePart } = {}
	local hits: { BasePart } = {}
	local width, height, length = size.X, size.Y, size.Z
	local function solid(name: string, partSize: Vector3, offset: CFrame, partColor: Color3, mat: Enum.Material?, opts: PartOptions?): BasePart
		local part = newPart(model, name, partSize, pivot * offset, partColor, mat, opts)
		table.insert(parts, part)
		return part
	end
	local function visual(name: string, partSize: Vector3, offset: CFrame, partColor: Color3, mat: Enum.Material?, opts: PartOptions?): BasePart
		local part = decor(model, name, partSize, pivot * offset, partColor, mat, opts)
		table.insert(parts, part)
		return part
	end
	local wheelDiameter = math.min(height * 0.4, 2)
	local clearance = wheelDiameter * 0.45
	if kind == "block" then
		local block = solid("Bloc", Vector3.new(width, height - clearance, length), CFrame.new(0, clearance + (height - clearance) / 2, 0), bodyColor, Enum.Material.SmoothPlastic, { surface = "Rock" })
		table.insert(hits, block)
	else
		local bodyHeight = if kind == "bus" then height * 0.75 else height * 0.4
		local body = solid("Carrosserie", Vector3.new(width, bodyHeight, length), CFrame.new(0, clearance + bodyHeight / 2, 0), bodyColor, Enum.Material.SmoothPlastic, { surface = "Rock" })
		table.insert(hits, body)
		local cabinHeight = height - clearance - bodyHeight
		if kind == "bus" then
			visual("Vitres", Vector3.new(width + 0.1, bodyHeight * 0.3, length * 0.8), CFrame.new(0, clearance + bodyHeight * 0.68, -length * 0.05), PALETTE.glass, Enum.Material.Glass, { transparency = 0.15 })
			solid("Toit", Vector3.new(width - 0.2, math.max(cabinHeight, 0.4), length - 0.4), CFrame.new(0, clearance + bodyHeight + math.max(cabinHeight, 0.4) / 2, 0), PALETTE.white, Enum.Material.SmoothPlastic, { surface = "Rock" })
		else
			local cabin = solid("Habitacle", Vector3.new(width * 0.84, cabinHeight, length * 0.5), CFrame.new(0, clearance + bodyHeight + cabinHeight / 2, length * 0.05), bodyColor, Enum.Material.SmoothPlastic, { surface = "Rock" })
			table.insert(hits, cabin)
			visual("Pare-brise", Vector3.new(width * 0.78, cabinHeight * 0.7, 0.2), CFrame.new(0, clearance + bodyHeight + cabinHeight * 0.45, length * 0.05 - length * 0.25 - 0.05), PALETTE.glass, Enum.Material.Glass, { transparency = 0.1 })
			visual("Lunette", Vector3.new(width * 0.78, cabinHeight * 0.6, 0.2), CFrame.new(0, clearance + bodyHeight + cabinHeight * 0.45, length * 0.05 + length * 0.25 + 0.05), PALETTE.glass, Enum.Material.Glass, { transparency = 0.1 })
			for _, side in { -1, 1 } do
				visual("Vitre", Vector3.new(0.2, cabinHeight * 0.6, length * 0.4), CFrame.new(side * width * 0.42, clearance + bodyHeight + cabinHeight * 0.45, length * 0.05), PALETTE.glass, Enum.Material.Glass, { transparency = 0.1 })
			end
		end
		-- Phares (avant = -Z du CFrame, c'est-à-dire LookVector) et feux arrière.
		for _, side in { -1, 1 } do
			visual("Phare", Vector3.new(0.9, 0.6, 0.2), CFrame.new(side * width * 0.32, clearance + bodyHeight * 0.6, -length / 2 - 0.05), Color3.fromRGB(255, 244, 180), Enum.Material.Neon)
			visual("Feu", Vector3.new(0.8, 0.5, 0.2), CFrame.new(side * width * 0.32, clearance + bodyHeight * 0.6, length / 2 + 0.05), Color3.fromRGB(255, 70, 70), Enum.Material.Neon)
		end
		visual("ParechocAvant", Vector3.new(width + 0.2, 0.5, 0.5), CFrame.new(0, clearance + 0.3, -length / 2), PALETTE.metal, Enum.Material.Metal)
		visual("ParechocArriere", Vector3.new(width + 0.2, 0.5, 0.5), CFrame.new(0, clearance + 0.3, length / 2), PALETTE.metal, Enum.Material.Metal)
	end
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			visual("Roue", Vector3.new(0.8, wheelDiameter, wheelDiameter), CFrame.new(x * (width / 2 - 0.2), wheelDiameter / 2, z * length * 0.32), PALETTE.dark, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
			visual("Jante", Vector3.new(0.85, wheelDiameter * 0.45, wheelDiameter * 0.45), CFrame.new(x * (width / 2 - 0.2), wheelDiameter / 2, z * length * 0.32), PALETTE.metal, Enum.Material.Metal, { shape = Enum.PartType.Cylinder })
		end
	end
	return parts, hits
end

builders.mover = function(ctx: Ctx): Controller?
	local size, params, model = ctx.size, ctx.params, ctx.model
	local modelKind = str(params, "model", "car")
	local bodyColor = color(params, "color", CAR_COLORS[ctx.rng:NextInteger(1, #CAR_COLORS)])
	local speed = num(params, "speed", 20, 1, 120)
	local pause = num(params, "pause", 0.8, 0, 30)
	local loop = bool(params, "loop", false)
	local phase = num(params, "phase", 0)
	local knock = num(params, "knock", 60, 0, 200)
	local lift = num(params, "lift", 28, 0, 120)

	-- Trajet : décalages relatifs au centre (repère de l'obstacle) -> monde.
	local frame = ctx.base
	local points: { Vector3 } = {}
	if type(params.path) == "table" then
		for _, point in params.path do
			if Validate.isFiniteVector3(point) then
				table.insert(points, frame.Position + localToWorldDirection(frame, point))
			end
		end
	end
	if #points < 2 then
		points = {}
		local axisWorld = localToWorldDirection(frame, axisVector(params.axis, Vector3.zAxis))
		local distance = num(params, "distance", 40, 2, 2000)
		table.insert(points, frame.Position - axisWorld * (distance / 2))
		table.insert(points, frame.Position + axisWorld * (distance / 2))
	end
	local sample = buildPathSampler(points, speed, pause, loop, phase)

	local function poseFrame(pose: PathPose): CFrame
		local heading = Vector3.new(pose.heading.X, 0, pose.heading.Z)
		if heading.Magnitude < 1e-3 then
			heading = frame.LookVector
		end
		return CFrame.lookAt(pose.position, pose.position + heading.Unit)
	end

	local startPose = sample(Workspace:GetServerTimeNow())
	local pivot = poseFrame(startPose)
	local parts, hits = buildCarBody(model, size, pivot, bodyColor, modelKind)
	model.PrimaryPart = hits[1]
	local group = newGroup()
	for _, part in parts do
		addToGroup(group, part, pivot)
	end

	-- Le trajet est matérialisé discrètement au sol (pointillés) pour l'aperçu et la lisibilité.
	for index = 1, #points - (if loop then 0 else 1) do
		local a = points[index]
		local b = points[(index % #points) + 1]
		local segment = b - a
		local length = segment.Magnitude
		if length > 2 then
			local dashes = math.floor(length / 6)
			for dash = 0, dashes - 1 do
				local position = a + segment.Unit * (dash * 6 + 1.5)
				decor(model, "Marquage", Vector3.new(0.5, 0.06, 3), CFrame.lookAt(position, position + segment) * CFrame.new(0, 0.04, -1.5), PALETTE.white, Enum.Material.SmoothPlastic, { shadow = false })
			end
		end
	end

	local function step(now: number, _dt: number)
		local pose = sample(now)
		moveGroup(group, poseFrame(pose), pose.velocity, Vector3.zero)
	end
	return {
		step = step,
		hitParts = hits,
		ballMargin = 0.4,
		ballCooldown = 0.4,
		onBall = sweepBall(ctx.kind, 18),
		onPlayer = function(player: Player, root: BasePart, part: BasePart, _now: number): boolean
			local velocity = part.AssemblyLinearVelocity
			local direction: Vector3
			if velocity.Magnitude > 1 then
				direction = Vector3.new(velocity.X, 0, velocity.Z).Unit
			else
				local away = root.Position - part.Position
				away = Vector3.new(away.X, 0, away.Z)
				direction = if away.Magnitude > 1e-3 then away.Unit else part.CFrame.LookVector
			end
			if knockPlayer(player, direction * knock + Vector3.new(0, lift, 0), ctx.kind) then
				playSound("cart_horn", part.Position)
				notifyKey(player, "course.obstacle.car")
				return true
			end
			return false
		end,
	}
end

builders.car = function(ctx: Ctx): Controller?
	return builders.mover(ctx)
end

builders.platform = function(ctx: Ctx): Controller?
	local size, params, model = ctx.size, ctx.params, ctx.model
	local surfaceName = surface(params, "Wood")
	local slab = newPart(model, "Plateforme", size, ctx.center, color(params, "color", SURFACE_COLORS[surfaceName]), material(params, SURFACE_MATERIALS[surfaceName]), { surface = surfaceName })
	model.PrimaryPart = slab
	local accent = color(params, "accent", PALETTE.darkWood)
	for _, side in { -1, 1 } do
		decor(model, "Bordure", Vector3.new(size.X + 0.3, size.Y + 0.1, 0.4), ctx.center * CFrame.new(0, 0, side * (size.Z / 2)), accent, Enum.Material.SmoothPlastic)
		decor(model, "Bordure", Vector3.new(0.4, size.Y + 0.1, size.Z + 0.3), ctx.center * CFrame.new(side * (size.X / 2), 0, 0), accent, Enum.Material.SmoothPlastic)
	end
	return nil
end

builders.patch = function(ctx: Ctx): Controller?
	local size, params, model = ctx.size, ctx.params, ctx.model
	local surfaceName = surface(params, "Sand")
	local thickness = math.max(size.Y, 0.1)
	local partColor = color(params, "color", SURFACE_COLORS[surfaceName])
	local mat = material(params, SURFACE_MATERIALS[surfaceName])
	-- Légèrement au-dessus du sol (pas de scintillement), mais assez fin pour que la balle y roule.
	local frame = ctx.base * CFrame.new(0, thickness / 2 + 0.04, 0)
	local patch: BasePart
	if str(params, "shape", "cylinder") == "box" then
		patch = newPart(model, "Zone", Vector3.new(size.X, thickness, size.Z), frame, partColor, mat, { surface = surfaceName })
	else
		-- Disque : cylindre vertical (diamètre = min(X, Z), contrainte des cylindres Roblox).
		patch = newPart(model, "Zone", Vector3.new(thickness, size.Z, size.X), frame * CFrame.Angles(0, math.pi / 2, math.pi / 2), partColor, mat, {
			shape = Enum.PartType.Cylinder,
			surface = surfaceName,
		})
	end
	model.PrimaryPart = patch
	return nil
end

builders.swing = function(ctx: Ctx): Controller?
	local size, params, model = ctx.size, ctx.params, ctx.model
	local surfaceName = surface(params, "Wood")
	local minAngle = math.rad(num(params, "minAngle", 0, -85, 85))
	local maxAngle = math.rad(num(params, "maxAngle", 70, -85, 89))
	local period = num(params, "period", 8, 1, 600)
	local phase = num(params, "phase", 0) * 2 * math.pi
	-- Charnière sur le bord arrière (-Z du parcours = +Z du CFrame).
	local hinge = ctx.center * CFrame.new(0, 0, size.Z / 2)
	local group = newGroup()
	local deck = newPart(model, "Tablier", size, ctx.center, color(params, "color", SURFACE_COLORS[surfaceName]), material(params, SURFACE_MATERIALS[surfaceName]), { surface = surfaceName })
	addToGroup(group, deck, hinge)
	model.PrimaryPart = deck
	local accent = color(params, "accent", PALETTE.darkWood)
	for _, side in { -1, 1 } do
		local rail = newPart(model, "Garde-corps", Vector3.new(0.5, 1.2, size.Z), ctx.center * CFrame.new(side * (size.X / 2 - 0.25), size.Y / 2 + 0.6, 0), accent, Enum.Material.Wood, { surface = "Wood" })
		addToGroup(group, rail, hinge)
		verticalCylinder(model, "Pivot", 1.4, 3, hinge * CFrame.new(side * (size.X / 2 + 0.8), 0.5, 0), PALETTE.darkStone, Enum.Material.Slate, { surface = "Rock" })
	end
	local omega = 2 * math.pi / period
	local right = hinge.RightVector
	local function step(now: number, _dt: number)
		local wave = now * omega + phase
		local alpha = 0.5 - 0.5 * math.cos(wave)
		local angle = minAngle + (maxAngle - minAngle) * alpha
		local rate = (maxAngle - minAngle) * 0.5 * omega * math.sin(wave)
		-- Rotation autour de l'axe droit de la charnière : angle positif = le bord avant se lève.
		moveGroup(group, hinge * CFrame.Angles(angle, 0, 0), Vector3.zero, right * rate)
	end
	step(Workspace:GetServerTimeNow(), 0)
	return {
		step = step,
		hitParts = { deck },
		ballMargin = 0.35,
		ballCooldown = 0.25,
		onBall = function(ball: BasePart, owner: Player, part: BasePart, now: number): boolean
			if carryBall("swing", part, ball, owner) then
				return true
			end
			return sweepBall("swing", 8)(ball, owner, part, now)
		end,
	}
end

builders.stairs = function(ctx: Ctx): Controller?
	local size, params, model = ctx.size, ctx.params, ctx.model
	local steps = math.floor(num(params, "steps", 5, 1, 40))
	local surfaceName = surface(params, "Rock")
	local mainColor = color(params, "color", SURFACE_COLORS[surfaceName])
	local accent = color(params, "accent", PALETTE.cream)
	local mat = material(params, SURFACE_MATERIALS[surfaceName])
	local depth = size.Z / steps
	local first: BasePart? = nil
	for index = 1, steps do
		local stepHeight = size.Y * index / steps
		-- Marche n : de -Z/2 + (n-1)·profondeur, vers l'avant (+Z du parcours = LookVector).
		local z = -size.Z / 2 + (index - 0.5) * depth
		local part = newPart(model, "Marche", Vector3.new(size.X, stepHeight, depth), ctx.base * CFrame.new(0, stepHeight / 2, -z), if index % 2 == 0 then mainColor else mainColor:Lerp(accent, 0.25), mat, { surface = surfaceName })
		first = first or part
	end
	model.PrimaryPart = first
	return nil
end

--------------------------------------------------------------------------------
-- Tailles par défaut
--------------------------------------------------------------------------------

local DEFAULT_SIZES: { [string]: Vector3 } = {
	wall = Vector3.new(16, 4, 1.5),
	ramp = Vector3.new(10, 3, 14),
	bumper = Vector3.new(3, 3, 3),
	windmill = Vector3.new(10, 12, 8),
	movingPlatform = Vector3.new(12, 1, 12),
	rotatingBar = Vector3.new(20, 1, 1),
	pillar = Vector3.new(3, 8, 3),
	arch = Vector3.new(12, 8, 3),
	tunnel = Vector3.new(8, 6, 16),
	jumpPad = Vector3.new(6, 1, 6),
	conveyor = Vector3.new(8, 1, 20),
	car = Vector3.new(6, 4.5, 11),
	mover = Vector3.new(6, 4.5, 11),
	platform = Vector3.new(12, 1, 12),
	patch = Vector3.new(12, 0.2, 12),
	swing = Vector3.new(10, 1, 16),
	stairs = Vector3.new(10, 4, 10),
}

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function Obstacles.kinds(): { string }
	local list: { string } = {}
	for kind in builders do
		table.insert(list, kind)
	end
	for alias in aliases do
		table.insert(list, alias)
	end
	table.sort(list)
	return list
end

local function resolveKind(kind: string, params: Params): (string?, Params)
	if builders[kind] then
		return kind, params
	end
	local alias = aliases[kind]
	if not alias then
		-- Alias déclarés dans Config.Course.ObstacleAliases (ex. car = "mover").
		local configured = config("Course").ObstacleAliases
		local target = if type(configured) == "table" then configured[kind] else nil
		if type(target) == "string" and builders[target] then
			return target, params
		end
		return nil, params
	end
	local merged = table.clone(alias.params)
	for key, value in params do
		merged[key] = value
	end
	return alias.kind, merged
end

local function seedFor(def: ObstacleDef): number
	local c = def.center
	return math.floor((c.X * 73.856093 + c.Y * 19.349663 + c.Z * 83.492791) % 2147483647)
end

-- Altitude du sol sous l'obstacle (géométrie du trou), ou nil.
local function probeGround(center: Vector3, halfHeight: number, groundRoot: Instance?): number?
	if not groundRoot then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { groundRoot }
	local origin = center + Vector3.new(0, GROUND_PROBE_UP, 0)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -(GROUND_PROBE_UP + halfHeight + GROUND_PROBE_EXTRA), 0), params)
	if not hit or hit.Normal.Y < 0.6 then
		return nil
	end
	-- On ne se pose pas sur un autre obstacle.
	local ancestor = hit.Instance:FindFirstAncestorWhichIsA("Model")
	if ancestor and ancestor:GetAttribute("Obstacle") ~= nil then
		return nil
	end
	return hit.Position.Y
end

local function assignCourseGroup(model: Model)
	local Collision = service("CollisionService")
	if not Collision or type(Collision.AssignPart) ~= "function" then
		return
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.CanCollide then
			pcall(Collision.AssignPart, descendant, "Course")
		end
	end
end

function Obstacles.spawn(def: ObstacleDef, parent: Instance, trove: Trove?, options: SpawnOptions?): Model?
	if type(def) ~= "table" or type(def.kind) ~= "string" or not Validate.isFiniteVector3(def.center) then
		Log.warn("Obstacles", "définition invalide ignorée")
		return nil
	end
	local opts: SpawnOptions = options or {}
	local rawParams: Params = if type(def.params) == "table" then def.params :: Params else {}
	local kind, params = resolveKind(def.kind, rawParams)
	if not kind then
		if not warnedKinds[def.kind] then
			warnedKinds[def.kind] = true
			Log.warn("Obstacles", "type d'obstacle inconnu ignoré :", def.kind)
		end
		return nil
	end
	local builder = builders[kind]
	local size = DEFAULT_SIZES[kind] or Vector3.new(4, 4, 4)
	if Validate.isFiniteVector3(def.size) then
		local given = def.size :: Vector3
		size = Vector3.new(math.clamp(math.abs(given.X), 0.2, 400), math.clamp(math.abs(given.Y), 0.05, 400), math.clamp(math.abs(given.Z), 0.2, 400))
	end
	local rotation = CFrame.Angles(0, -math.rad(if Validate.isFiniteNumber(def.yaw) then def.yaw :: number else 0), 0)
	local center = def.center
	local halfHeight = size.Y / 2
	local baseY = center.Y - halfHeight
	if SNAPPED_KINDS[kind] ~= false then
		local groundRoot = opts.groundRoot or parent.Parent or parent
		local ground = probeGround(center, halfHeight, groundRoot)
		if ground then
			baseY = ground
		end
	end
	local base = CFrame.new(center.X, baseY, center.Z) * rotation
	local model = Instance.new("Model")
	model.Name = "Obstacle_" .. def.kind
	model:SetAttribute("Obstacle", def.kind)
	model:SetAttribute("ObstacleBase", kind)
	local ctx: Ctx = {
		kind = def.kind,
		params = params,
		size = size,
		base = base,
		center = base * CFrame.new(0, halfHeight, 0),
		model = model,
		preview = opts.preview == true,
		trove = trove or TroveModule.new(),
		rng = Random.new(seedFor(def)),
	}
	local ok, controller = pcall(builder, ctx)
	if not ok then
		model:Destroy()
		Log.warn("Obstacles", "construction de", def.kind, "en échec :", tostring(controller))
		return nil
	end
	model.Parent = parent
	if trove then
		trove:Add(model)
	end
	if not ctx.preview then
		assignCourseGroup(model)
		if controller then
			runController(ctx, controller)
		end
	end
	return model
end

return Obstacles
