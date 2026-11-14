--!strict
--[[
	VehicleService — Kart-Caddie (objet caddie_kart ; docs/ARCHITECTURE.md §6, priorité 45).

	  VehicleService.SpawnKart(owner, cframe) -> boolean   crée un kart (8 places) ; faux si impossible
	  VehicleService.EjectPlayer(player) -> boolean        fait descendre le joueur de son siège (appelé par CombatService au KO)
	  VehicleService.Damage(player, points)                usure du kart occupé par ce joueur
	  VehicleService.ClearAll()                            détruit tous les karts (fin de trou, MatchService)
	  VehicleService.GetCartOf(player) -> Model?

	Conception : le serveur reste propriétaire physique du châssis (aucune propriété réseau donnée au conducteur),
	donc la vitesse, les collisions et les KO sont autoritatifs. Le conducteur (VehicleSeat) ne transmet que
	Throttle/Steer ; le serveur pilote un LinearVelocity (plan horizontal, la gravité reste libre) et un
	AngularVelocity (lacet). Vitesse plafonnée à Params.MaxSpeed.
	  - Monter : ProximityPrompt sur le châssis, déclenché côté serveur (place libre la plus proche, conducteur d'abord) ;
	    descendre : saut standard.
	  - Écrasement : au-dessus de RamMinSpeed, un adversaire du conducteur touché par l'avant est mis KO (mineur) ;
	    au-dessus de MajorRamSpeed : frappe majeure et 1 point d'usure. Structure : 3 points ; à 0 le kart explose.
	  - Durée de vie : 45 s. Un seul kart par joueur (le précédent disparaît).
	  - Coincé (accélérateur plein, vitesse ~0 pendant StuckEjectSeconds) : tous les passagers sont éjectés.
	Statistiques : cartDistance (studs parcourus par le conducteur), cartKOs (via AchievementService.KnockedOut, source "caddie_kart").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local ItemGeometry = require(Shared.Logic.ItemGeometry)
local Log = require(Shared.Util.Log)
local Net = require(Shared.Net)
local Trove = require(Shared.Util.Trove)

local Services = require(script.Parent.Parent.Util.Services)
local services = Services.scope("Vehicle")

local VehicleService = {}
VehicleService.Priority = 45

local DEF = Items.ById.caddie_kart
local P = DEF.params
local FOLDER_NAME = "Karts"
local ACCELERATION = 38 -- studs/s²
local BRAKE = 70
local REVERSE_MAX = 18
local TURN_RATE = 1.9 -- rad/s à pleine vitesse de braquage
local RAM_RADIUS = 5.5
local RAM_REHIT_SECONDS = 1.2
local STATE_INTERVAL = 0.5
local KART_SIZE = Vector3.new(7, 1.2, 12)
local SEAT_LAYOUT = { -- décalages locaux (x, z) : conducteur puis 7 passagers
	Vector3.new(-1.6, 1.2, -2.5),
	Vector3.new(1.6, 1.2, -2.5),
	Vector3.new(-1.6, 1.2, 0.5),
	Vector3.new(1.6, 1.2, 0.5),
	Vector3.new(-1.6, 1.2, 3.5),
	Vector3.new(1.6, 1.2, 3.5),
	Vector3.new(0, 1.2, 5.2),
}

type Cart = {
	id: number,
	owner: Player,
	model: Model,
	chassis: Part,
	driverSeat: any,
	seats: { any },
	trove: any,
	expiresAt: number,
	structure: number,
	speed: number,
	lastRam: { [Player]: number },
	stuckFor: number,
	lastResetAt: number,
	flush: number,
}

local carts: { [number]: Cart } = {}
local cartOfPlayer: { [Player]: Cart } = {}
local cartCounter = 0
local foldered: Folder? = nil

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function folder(): Folder
	if foldered and foldered.Parent then
		return foldered
	end
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		foldered = existing
	else
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = Workspace
		foldered = created
	end
	return foldered :: Folder
end

local function occupantPlayer(seat: any): Player?
	local occupant = seat.Occupant
	if not occupant then
		return nil
	end
	return Players:GetPlayerFromCharacter(occupant.Parent)
end

local function seatIndexOf(cart: Cart, seat: any): number
	if seat == cart.driverSeat then
		return 1
	end
	local index = table.find(cart.seats, seat)
	return if index then index + 1 else 0
end

local function pushState(cart: Cart, player: Player, seat: any?)
	local payload: any = nil
	if seat then
		payload = {
			cartId = cart.id,
			seatIndex = seatIndexOf(cart, seat),
			isDriver = seat == cart.driverSeat,
			structure = cart.structure,
			expiresAt = cart.expiresAt,
		}
	end
	pcall(Net.fire, "Vehicles.State", player, payload)
end

local function allSeats(cart: Cart): { any }
	local list: { any } = { cart.driverSeat }
	for _, seat in cart.seats do
		table.insert(list, seat)
	end
	return list
end

local function ejectAll(cart: Cart)
	for _, seat in allSeats(cart) do
		local occupant = seat.Occupant
		if occupant then
			local rider = Players:GetPlayerFromCharacter(occupant.Parent)
			if rider then
				rider:SetAttribute("InVehicle", nil)
				cartOfPlayer[rider] = nil
			end
			occupant.Sit = false
		end
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
end

local function destroyCart(cart: Cart, explode: boolean)
	if carts[cart.id] ~= cart then
		return
	end
	carts[cart.id] = nil
	if cartOfPlayer[cart.owner] == cart then
		cartOfPlayer[cart.owner] = nil
	end
	ejectAll(cart)
	if explode and cart.chassis.Parent then
		local part = Instance.new("Part")
		part.Name = "ExplosionKart"
		part.Shape = Enum.PartType.Ball
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Material = Enum.Material.Neon
		part.Color = DEF.color
		part.Size = Vector3.new(4, 4, 4)
		part.Position = cart.chassis.Position
		part.Parent = folder()
		task.delay(0.4, part.Destroy, part)
	end
	cart.trove:Clean()
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function makeSeat(class: "Seat" | "VehicleSeat", name: string, chassis: Part, offset: Vector3): any
	local seat: any = Instance.new(class)
	seat.Name = name
	seat.Size = Vector3.new(2.4, 0.6, 2.4)
	seat.Color = Color3.fromRGB(40, 40, 50)
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat.CFrame = chassis.CFrame * CFrame.new(offset)
	seat.CustomPhysicalProperties = PhysicalProperties.new(0.2, 0, 0, 1, 1)
	seat.Parent = chassis.Parent
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = chassis
	weld.Part1 = seat
	weld.Parent = seat
	return seat
end

local function build(owner: Player, cframe: CFrame): Cart
	cartCounter += 1
	local model = Instance.new("Model")
	model.Name = "CaddieKart_" .. cartCounter
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = KART_SIZE
	chassis.Color = DEF.color
	chassis.Material = Enum.Material.SmoothPlastic
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.CFrame = cframe
	chassis.CustomPhysicalProperties = PhysicalProperties.new(1.2, 0.05, 0, 1, 1)
	chassis.Parent = model
	model.PrimaryPart = chassis

	local driverSeat = makeSeat("VehicleSeat", "SiegeConducteur", chassis, SEAT_LAYOUT[1])
	driverSeat.MaxSpeed = 0 -- la vitesse est pilotée par le serveur, pas par le moteur de VehicleSeat
	driverSeat.Torque = 0
	driverSeat.TurnSpeed = 0
	local seats: { any } = {}
	for index = 2, math.min(P.Seats, #SEAT_LAYOUT + 1) do
		table.insert(seats, makeSeat("Seat", "Siege" .. index, chassis, SEAT_LAYOUT[index]))
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "Pilotage"
	attachment.Parent = chassis
	local linear = Instance.new("LinearVelocity")
	linear.Name = "Avance"
	linear.Attachment0 = attachment
	linear.RelativeTo = Enum.ActuatorRelativeTo.World
	linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	linear.PrimaryTangentAxis = Vector3.xAxis
	linear.SecondaryTangentAxis = Vector3.zAxis
	linear.PlaneVelocity = Vector2.zero
	linear.MaxForce = 60000
	linear.Parent = chassis
	local angular = Instance.new("AngularVelocity")
	angular.Name = "Lacet"
	angular.Attachment0 = attachment
	angular.RelativeTo = Enum.ActuatorRelativeTo.World
	angular.AngularVelocity = Vector3.zero
	angular.MaxTorque = 150000
	angular.Parent = chassis

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Monter"
	prompt.ActionText = "Monter"
	prompt.ObjectText = "Kart-Caddie"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = chassis

	model:SetAttribute("CartId", cartCounter)
	model:SetAttribute("OwnerUserId", owner.UserId)
	model.Parent = folder()
	local collision = services.get("CollisionService")
	if collision and type(collision.AssignModel) == "function" then
		pcall(collision.AssignModel, model, "Vehicles", true)
	end
	chassis:SetNetworkOwner(nil)

	local cart: Cart = {
		id = cartCounter,
		owner = owner,
		model = model,
		chassis = chassis,
		driverSeat = driverSeat,
		seats = seats,
		trove = Trove.new(),
		expiresAt = now() + DEF.duration,
		structure = P.StructurePoints,
		speed = 0,
		lastRam = {},
		stuckFor = 0,
		lastResetAt = -math.huge,
		flush = 0,
	}
	cart.trove:Add(model)
	model:SetAttribute("Structure", cart.structure)
	return cart
end

--------------------------------------------------------------------------------
-- Boucle de conduite et collisions
--------------------------------------------------------------------------------

local function driverOf(cart: Cart): Player?
	return occupantPlayer(cart.driverSeat)
end

local function updateCart(cart: Cart, dt: number)
	local chassis = cart.chassis
	if not chassis.Parent then
		destroyCart(cart, false)
		return
	end
	if now() >= cart.expiresAt then
		destroyCart(cart, true)
		return
	end
	local driver = driverOf(cart)
	local throttle = if driver then cart.driverSeat.ThrottleFloat else 0
	local steer = if driver then cart.driverSeat.SteerFloat else 0
	local forward = ItemGeometry.flat(chassis.CFrame.LookVector)
	if forward.Magnitude < 1e-3 then
		return
	end
	forward = forward.Unit
	-- Le modèle regarde vers -Z du châssis : avant = LookVector ; accélérateur +1 = avancer.
	if throttle > 0.05 then
		cart.speed = math.min(cart.speed + ACCELERATION * throttle * dt, P.MaxSpeed)
	elseif throttle < -0.05 then
		if cart.speed > 0 then
			cart.speed = math.max(cart.speed - BRAKE * dt, -REVERSE_MAX)
		else
			cart.speed = math.max(cart.speed + ACCELERATION * 0.6 * throttle * dt, -REVERSE_MAX)
		end
	else
		local drag = ACCELERATION * 0.5 * dt
		cart.speed = if math.abs(cart.speed) <= drag then 0 else cart.speed - math.sign(cart.speed) * drag
	end
	local planar = forward * cart.speed
	local linear = chassis:FindFirstChild("Avance") :: LinearVelocity?
	local angular = chassis:FindFirstChild("Lacet") :: AngularVelocity?
	if linear then
		linear.PlaneVelocity = Vector2.new(planar.X, planar.Z)
	end
	if angular then
		local authority = math.clamp(math.abs(cart.speed) / 10, 0, 1) * (if cart.speed >= 0 then 1 else -1)
		angular.AngularVelocity = Vector3.new(0, -steer * TURN_RATE * authority, 0)
	end

	-- Statistique de distance (conducteur).
	if driver and cart.speed > 0 then
		cart.flush += cart.speed * dt
		if cart.flush >= 10 then
			local whole = math.floor(cart.flush)
			cart.flush -= whole
			local achievements = services.get("AchievementService")
			if achievements and type(achievements.Increment) == "function" then
				pcall(achievements.Increment, driver, "cartDistance", whole)
			end
		end
	end

	-- Coincé : accélérateur à fond mais presque immobile.
	local real = ItemGeometry.flat(chassis.AssemblyLinearVelocity).Magnitude
	if driver and throttle > 0.5 and real < 2 then
		cart.stuckFor += dt
		if cart.stuckFor >= P.StuckEjectSeconds then
			cart.stuckFor = 0
			cart.speed = 0
			ejectAll(cart)
		end
	else
		cart.stuckFor = 0
	end
	-- Vitesse interne recalée sur la vitesse réelle (collision frontale contre le décor).
	if cart.speed > 0 and real < cart.speed * 0.4 then
		cart.speed = real
	end

	-- Écrasement.
	if driver and real >= P.RamMinSpeed and cart.speed > 0 then
		local front = chassis.Position + forward * (KART_SIZE.Z / 2)
		local combat = services.get("CombatService")
		for _, victim in Players:GetPlayers() do
			if victim == driver or cartOfPlayer[victim] == cart then
				continue
			end
			local character = victim.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root or (root.Position - front).Magnitude > RAM_RADIUS then
				continue
			end
			local seated = false
			for _, seat in allSeats(cart) do
				if occupantPlayer(seat) == victim then
					seated = true
				end
			end
			if seated or (cart.lastRam[victim] and now() - cart.lastRam[victim] < RAM_REHIT_SECONDS) then
				continue
			end
			if combat and type(combat.CanAffect) == "function" then
				local okAffect, can = pcall(combat.CanAffect, driver, victim)
				if okAffect and can == false then
					continue
				end
			end
			if combat and type(combat.IsDodging) == "function" and combat.IsDodging(victim) then
				continue
			end
			local major = real >= P.MajorRamSpeed
			local ok, success = pcall(combat.Knockout, victim, {
				attacker = driver,
				source = "caddie_kart",
				major = major,
				duration = if major then 2.6 else 1.8,
				knock = forward * math.min(real * 1.4, 90) + Vector3.new(0, 20, 0),
			})
			if ok and success then
				cart.lastRam[victim] = now()
				if major then
					VehicleService.Damage(driver, 1)
				end
			end
		end
	end
end

local function connectSeat(cart: Cart, seat: any)
	cart.trove:Add(seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local player = occupantPlayer(seat)
		if player then
			cartOfPlayer[player] = cart
			player:SetAttribute("InVehicle", true)
			pushState(cart, player, seat)
		end
		-- Joueur descendu : on retrouve qui n'est plus assis ici.
		for owner, owned in cartOfPlayer do
			if owned == cart then
				local stillSeated = false
				for _, other in allSeats(cart) do
					if occupantPlayer(other) == owner then
						stillSeated = true
					end
				end
				if not stillSeated then
					cartOfPlayer[owner] = nil
					owner:SetAttribute("InVehicle", nil)
					pushState(cart, owner, nil)
				end
			end
		end
	end))
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

function VehicleService.SpawnKart(owner: Player, cframe: CFrame): boolean
	local previous = cartOfPlayer[owner]
	for _, cart in carts do
		if cart.owner == owner then
			destroyCart(cart, false)
		end
	end
	if previous and carts[previous.id] then
		destroyCart(previous, false)
	end
	local ok, built = pcall(build, owner, cframe)
	if not ok then
		Log.warn("Vehicle", "construction du kart impossible :", built)
		return false
	end
	local cart = built :: Cart
	carts[cart.id] = cart
	for _, seat in allSeats(cart) do
		connectSeat(cart, seat)
	end
	local prompt = cart.chassis:FindFirstChild("Monter") :: ProximityPrompt
	cart.trove:Add(prompt.Triggered:Connect(function(player: Player)
		VehicleService.Board(player, cart)
	end))
	return true
end

function VehicleService.Board(player: Player, cart: Cart): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or humanoid.SeatPart then
		return false
	end
	local match = services.get("MatchService")
	if match and type(match.GetPhase) == "function" and match.GetPhase() ~= "Playing" then
		return false
	end
	-- Pas de monte pendant un KO ou une visée de golf.
	if character and (character:GetAttribute("KnockedOut") == true or character:GetAttribute("Aiming") == true) then
		return false
	end
	for _, seat in allSeats(cart) do
		if not seat.Occupant then
			seat:Sit(humanoid)
			return true
		end
	end
	return false
end

function VehicleService.EjectPlayer(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or not humanoid.SeatPart then
		return false
	end
	local seat = humanoid.SeatPart
	player:SetAttribute("InVehicle", nil)
	cartOfPlayer[player] = nil
	humanoid.Sit = false
	local weld = seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	return true
end

function VehicleService.GetCartOf(player: Player): Model?
	local cart = cartOfPlayer[player]
	return if cart then cart.model else nil
end

function VehicleService.Damage(player: Player, points: number)
	local cart = cartOfPlayer[player]
	if not cart then
		return
	end
	cart.structure -= points
	cart.model:SetAttribute("Structure", math.max(cart.structure, 0))
	for _, seat in allSeats(cart) do
		local rider = occupantPlayer(seat)
		if rider then
			pushState(cart, rider, seat)
		end
	end
	if cart.structure <= 0 then
		destroyCart(cart, true)
	end
end

function VehicleService.ClearAll()
	for _, cart in table.clone(carts) do
		destroyCart(cart, false)
	end
	table.clear(cartOfPlayer)
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

local function currentRound(): number
	local match = services.get("MatchService")
	return if match and type(match.GetRoundId) == "function" then match.GetRoundId() else 0
end

function VehicleService.Init()
	Net.on("Vehicles.Reset", function(player: Player, roundId: number)
		local cart = cartOfPlayer[player]
		if not cart or driverOf(cart) ~= player or roundId ~= currentRound() then
			return
		end
		if now() - cart.lastResetAt < P.ResetCooldown then
			return
		end
		cart.lastResetAt = now()
		local position = cart.chassis.Position + Vector3.new(0, 4, 0)
		local flat = ItemGeometry.flat(cart.chassis.CFrame.LookVector)
		if flat.Magnitude < 1e-3 then
			flat = Vector3.new(0, 0, -1)
		end
		cart.model:PivotTo(CFrame.lookAt(position, position + flat.Unit))
		cart.chassis.AssemblyLinearVelocity = Vector3.zero
		cart.chassis.AssemblyAngularVelocity = Vector3.zero
		cart.speed = 0
	end)
	Net.on("Vehicles.Horn", function(player: Player)
		local cart = cartOfPlayer[player]
		if cart and driverOf(cart) == player then
			cart.model:SetAttribute("HornAt", now()) -- le client joue le son local à partir de l'attribut
		end
	end)
end

function VehicleService.Start()
	RunService.Heartbeat:Connect(function(dt: number)
		for _, cart in table.clone(carts) do
			local ok, err = pcall(updateCart, cart, dt)
			if not ok then
				Log.warn("Vehicle", "kart en erreur :", err)
				destroyCart(cart, false)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(STATE_INTERVAL)
			for _, cart in carts do
				for _, seat in allSeats(cart) do
					local rider = occupantPlayer(seat)
					if rider then
						pushState(cart, rider, seat)
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		for _, cart in table.clone(carts) do
			if cart.owner == player then
				destroyCart(cart, false)
			end
		end
		cartOfPlayer[player] = nil
	end)
end

return VehicleService
