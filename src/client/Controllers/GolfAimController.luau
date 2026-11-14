--!strict
--[[
	GolfAimController — visée et frappe du golf côté client (priorité 30), adapté du prototype
	(legacy/prototype-etape1/AimController.lua) aux remotes Golf.* et aux contrôleurs partagés.

	Machine à états : Idle -> Aiming -> Charging -> Following -> Idle
	  Idle       avatar libre. Près de SA balle immobile (Gameplay.Shot.AimEnterDistance) : invite et action
	             « Viser » (E / LT / bouton tactile). Entrée automatique après chaque coup si Gameplay.Aim.AutoEnter
	             (jamais à l'entraînement).
	  Aiming     caméra orbitale autour de la balle (pilote CameraController « GolfAim ») ; clic droit + glisser /
	             A D ← → / sticks / glisser tactile : orienter ; molette, R F, ↑ ↓, croix ↑ ↓ : angle ; T, croix ← → :
	             type de coup ; Espace / clic / A / RT : lancer la jauge ; clic droit (bref), Q, B : quitter.
	             Aperçu de trajectoire (BallMath.predictTrajectory + vent) : perles locales + repère d'atterrissage.
	  Charging   jauge 0 -> 1 -> 0 (Gameplay.Shot.PowerPeriod, vitesse de jeu si GaugeFollowsGameSpeed) ;
	             second appui : Golf.Shoot(roundId, direction, loft, puissance, type) ; annuler : retour à la visée.
	  Following  la caméra suit la balle jusqu'à son arrêt (ou jusqu'à ce que le joueur bouge / annule).
	  Balle bloquée : maintenir G / Y (ou le bouton tactile « Replacer ») -> Golf.ResetBall(roundId).

	RoundId : GameState.RoundId, ou 0 pour une balle d'entraînement (attribut de balle Practice, attribut
	joueur Practice, ou phase Lobby/Preparing). Le serveur (BallService) revalide tout et répond par
	Golf.AimCancelled / Golf.ShotAccepted / Golf.BallReset. Aucun attribut répliqué n'est posé ici.

	API : GetState() -> "Idle" | "Aiming" | "Charging" | "Following"   IsAiming() -> boolean
	      Cancel(raison?)   GetBall() -> BasePart?   IsPractice() -> boolean
	      StateChanged : Signal(nouvelEtat, ancienEtat)
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Trove = require(Shared.Util.Trove)
local Log = require(Shared.Util.Log)
local GameState = require(Shared.Util.GameState)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local Gameplay = require(Shared.Config.Gameplay)
local BallMath = require(Shared.Logic.BallMath)

local InputController = require(script.Parent.InputController)
local CameraController = require(script.Parent.CameraController)

export type AimState = "Idle" | "Aiming" | "Charging" | "Following"

local GolfAimController = {}
GolfAimController.Priority = 30
GolfAimController.StateChanged = Signal.new()

local SHOT = Gameplay.Shot
local AIM = Gameplay.Aim
local BALL = Gameplay.Ball
local SHOT_TYPES = Gameplay.ShotTypes

-- Réglages de présentation (aucun effet sur le jeu : le serveur décide).
local CAMERA_DRIVER = "GolfAim"
local FOLLOW_DRIVER = "GolfFollow"
local CAMERA_PRIORITY = 50
local FOLLOW_PRIORITY = 45
local KEY_YAW_SPEED = math.rad(110) -- degrés/s au clavier
local RESET_HOLD_TIME = 1 -- s de maintien de G / Y avant Golf.ResetBall
local RESET_COOLDOWN = 2.5
local REENTER_BLOCK = 0.6 -- s sans réentrée après une annulation serveur
local TAP_MAX_TIME = 0.35 -- clic droit bref = annuler
local TAP_MAX_MOVE = 8 -- pixels
local FOLLOW_HARD_LIMIT = 15 -- s : retour forcé au joueur
local FOLLOW_REST_DELAY = 0.6
local FOLLOW_HOLED_DELAY = 1.4
local MAX_SWING_MARGIN = 0.5 -- s avant Shot.MaxSwingTime : la jauge revient d'elle-même à la visée
local BEAD_COUNT = 44
local BEAD_MIN_SPACING = 1.6
local SWEET_SPOT_INTERVAL = 0.2
local PUTT_SUGGEST_DISTANCE = 30

local localPlayer = Players.LocalPlayer

type BindingKeys = { Enum.KeyCode | Enum.UserInputType }

local state = {
	mode = "Idle" :: AimState,
	initialized = false,
	started = false,
	gameState = nil :: Folder?,
	ball = nil :: BasePart?,
	ballTrove = nil :: Trove.Trove?,
	panel = nil :: any,
	-- visée
	yaw = 0,
	pitch = math.rad(AIM.DefaultPitchDeg),
	loft = 0,
	shotType = "Drive",
	chargeStart = 0,
	power = 0,
	cameraCFrame = nil :: CFrame?,
	rmbDown = false,
	rmbStart = 0,
	rmbMoved = 0,
	touchInput = nil :: InputObject?,
	keyYaw = 0, -- -1, 0, 1 (A/D, ←/→)
	aimRoundId = 0,
	blockUntil = 0,
	autoArmed = false,
	-- suivi
	followStart = 0,
	followSawMoving = false,
	followEndAt = 0,
	-- réinitialisation de balle
	resetHoldStart = 0,
	resetHolding = false,
	resetSentAt = 0,
	-- caches
	settingsJson = "",
	gameSpeed = nil :: number?,
	sweetAt = 0,
	lastPrompt = nil :: string?,
	lastTouchAim = false,
	lastTouchReset = false,
	humanoidAutoRotate = nil :: boolean?,
}

local runtimeTrove = Trove.new()
local aimTrove = Trove.new() -- liaisons et connexions de la visée (nettoyées en sortie)

local previewFolder: Folder? = nil
local beads: { BasePart } = {}
local landingMarker: Model? = nil
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.RespectCanCollide = true
raycastParams.IgnoreWater = false

--------------------------------------------------------------------------------
-- Lectures d'état
--------------------------------------------------------------------------------

local function readGame(name: string): any
	local folder = state.gameState
	if folder then
		return folder:GetAttribute(name)
	end
	return nil
end

local function phase(): string
	local value = readGame("Phase")
	return if type(value) == "string" then value else "Lobby"
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isPracticeBall(): boolean
	local ball = state.ball
	if ball then
		local attribute = ball:GetAttribute("Practice")
		if type(attribute) == "boolean" then
			return attribute
		end
	end
	if localPlayer:GetAttribute("Practice") == true then
		return true
	end
	return table.find(BALL.PracticePhases, phase()) ~= nil
end

local function currentRoundId(): number
	if isPracticeBall() then
		return 0
	end
	local value = readGame("RoundId")
	return if isFiniteNumber(value) then math.floor(value) else 0
end

local function cupPosition(): Vector3?
	if isPracticeBall() then
		return nil
	end
	local value = readGame("CupPosition")
	if typeof(value) == "Vector3" then
		return value
	end
	return nil
end

local function currentWind(): Vector3
	if isPracticeBall() and not BALL.PracticeWind then
		return Vector3.zero
	end
	local value = readGame("Wind")
	if typeof(value) == "Vector3" and value.Magnitude == value.Magnitude then
		return value
	end
	return Vector3.zero
end

local function refreshGameSpeed()
	local json = readGame("SettingsJson")
	if type(json) ~= "string" or json == state.settingsJson then
		return
	end
	state.settingsJson = json
	state.gameSpeed = nil
	local ok, decoded = pcall(function(): any
		return HttpService:JSONDecode(json)
	end)
	if ok and type(decoded) == "table" and isFiniteNumber(decoded.gameSpeed) then
		state.gameSpeed = decoded.gameSpeed
	end
end

-- Période de la jauge : même règle que le serveur (BallService.gaugePeriod).
local function gaugePeriod(): number
	if not SHOT.GaugeFollowsGameSpeed then
		return SHOT.PowerPeriod
	end
	refreshGameSpeed()
	return BallMath.powerPeriod(SHOT.PowerPeriod, BallMath.effectiveGameSpeed(phase(), state.gameSpeed))
end

local function getCharacterParts(): (BasePart?, Humanoid?)
	local character = localPlayer.Character
	if not character then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return (if root and root:IsA("BasePart") then root else nil), humanoid
end

local function shotDef(shotType: string): any
	return SHOT_TYPES[shotType] or SHOT_TYPES[SHOT.DefaultType]
end

local function aimDirection(): Vector3
	return CFrame.Angles(0, state.yaw, 0).LookVector
end

local function phaseAllowsShot(): boolean
	return isPracticeBall() or phase() == "Playing"
end

local function puttAllowed(): boolean
	local ball = state.ball
	if not ball then
		return false
	end
	local surface = ball:GetAttribute("Surface")
	local cup = cupPosition()
	local distance = if cup then BallMath.flatDistance(ball.Position, cup) else nil
	return BallMath.puttAllowed(if type(surface) == "string" then surface else nil, distance, SHOT.PuttSurfaces, SHOT.PuttMaxCupDistance)
end

local function guidedAllowed(): boolean
	return Gameplay.Guided.Enabled and (not isPracticeBall() or Gameplay.Guided.AllowPractice)
end

-- Types proposés au joueur, dans l'ordre de Shot.TypeOrder.
local function availableShotTypes(): { string }
	local list = {}
	for _, shotType in SHOT.TypeOrder do
		local name = shotType :: string
		if SHOT_TYPES[name] == nil then
			continue
		end
		if name == "Putt" and not puttAllowed() then
			continue
		end
		if name == "Guided" and not guidedAllowed() then
			continue
		end
		table.insert(list, name)
	end
	if #list == 0 then
		table.insert(list, SHOT.DefaultType)
	end
	return list
end

-- Raison locale empêchant de viser (nil = possible). Le serveur revérifie tout.
local function localAimRefusal(): string?
	local ball = state.ball
	if not ball or not ball.Parent then
		return "unavailable"
	end
	local ballState = ball:GetAttribute("State")
	if ballState ~= "Resting" then
		return if ballState == "Moving" then "ball_moving" elseif ballState == "Frozen" then "ball_frozen" else "finished"
	end
	if not phaseAllowsShot() then
		return "phase"
	end
	if localPlayer:GetAttribute("KnockedOut") == true then
		return "stun"
	end
	if localPlayer:GetAttribute("InVehicle") == true then
		return "vehicle"
	end
	if localPlayer:GetAttribute("Spectating") == true then
		return "unavailable"
	end
	if not isPracticeBall() and localPlayer:GetAttribute("HoleFinished") == true then
		return "finished"
	end
	local root, humanoid = getCharacterParts()
	if not root or not humanoid or humanoid.Health <= 0 then
		return "unavailable"
	end
	if (root.Position - ball.Position).Magnitude > SHOT.AimEnterDistance then
		return "too_far"
	end
	local character = localPlayer.Character
	if character then
		for _, attribute in SHOT.AimBlockingCharacterAttributes do
			if character:GetAttribute(attribute) == true then
				return "status"
			end
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Panneau (UI/AimPanel), chargé paresseusement
--------------------------------------------------------------------------------

local function getPanel(): any
	if state.panel then
		return state.panel
	end
	local client = script.Parent.Parent
	local ui = client:FindFirstChild("UI")
	local module = if ui then ui:FindFirstChild("AimPanel") else nil
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(function(): any
		return (require(module) :: any).new()
	end)
	if not ok then
		Log.warn("Aim", "AimPanel indisponible :", result)
		return nil
	end
	state.panel = result
	runtimeTrove:Add(function()
		pcall(function()
			result:Destroy()
		end)
	end)
	return result
end

local function panelCall(method: string, ...: any)
	local panel = getPanel()
	if panel and type(panel[method]) == "function" then
		local ok, err = pcall(panel[method], panel, ...)
		if not ok then
			Log.debug("Aim", "AimPanel." .. method, err)
		end
	end
end

local function showMessage(text: string, kind: string?)
	panelCall("ShowMessage", text, kind)
end

local function localizedOr(key: string, fallbackKey: string, vars: { [string]: any }?): string
	if Locale.has(key) or Locale.has(key, "fr") then
		return Locale.t(key, vars)
	end
	return Locale.t(fallbackKey, vars)
end

local function keyLabel(action: string): string
	local ok, label = pcall(InputController.GetKeyLabel, action)
	if ok and type(label) == "string" and label ~= "" then
		return label
	end
	return "?"
end

local function refreshHint()
	local device = InputController.GetDevice()
	local text: string
	if state.mode == "Charging" then
		if device == "Touch" then
			text = Locale.t("aim.hint.chargeTouch")
		else
			text = Locale.t("aim.hint.charge", { swing = keyLabel("GolfSwing"), cancel = keyLabel("GolfCancel") })
		end
	elseif device == "Touch" then
		text = Locale.t("aim.hint.aimTouch")
	elseif device == "Gamepad" then
		text = Locale.t("aim.hint.aimGamepad", {
			loft = Locale.t("aim.hint.pair", { a = keyLabel("GolfLoftUp"), b = keyLabel("GolfLoftDown") }),
			shot = keyLabel("GolfShotType"),
			swing = keyLabel("GolfSwing"),
			cancel = keyLabel("GolfCancel"),
		})
	else
		text = Locale.t("aim.hint.aimKbm", {
			rotate = Locale.t("aim.hint.rotateKbm", { left = keyLabel("GolfYawLeft"), right = keyLabel("GolfYawRight") }),
			loft = Locale.t("aim.hint.loftKbm", { up = keyLabel("GolfLoftUp"), down = keyLabel("GolfLoftDown") }),
			shot = keyLabel("GolfShotType"),
			swing = keyLabel("GolfSwing"),
			cancel = keyLabel("GolfCancel"),
		})
	end
	panelCall("SetHint", text)
end

--------------------------------------------------------------------------------
-- Aperçu de trajectoire (perles locales, aucune physique)
--------------------------------------------------------------------------------

local function ensurePreview(): Folder
	local existing = previewFolder
	if existing and existing.Parent then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "GolfAimPreview"
	for index = 1, BEAD_COUNT do
		local bead = Instance.new("Part")
		bead.Name = "Perle" .. index
		bead.Shape = Enum.PartType.Ball
		bead.Material = Enum.Material.Neon
		bead.Anchored = true
		bead.CanCollide = false
		bead.CanQuery = false
		bead.CanTouch = false
		bead.CastShadow = false
		bead.Transparency = 1
		local t = (index - 1) / (BEAD_COUNT - 1)
		local size = 0.5 - 0.18 * t
		bead.Size = Vector3.new(size, size, size)
		bead.Color = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 201, 60), t)
		bead.Parent = folder
		beads[index] = bead
	end
	local marker = Instance.new("Model")
	marker.Name = "Atterrissage"
	local disc = Instance.new("Part")
	disc.Name = "Disque"
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.Neon
	disc.Color = Color3.fromRGB(255, 201, 60)
	disc.Size = Vector3.new(0.12, 3.4, 3.4)
	disc.Transparency = 0.35
	local ring = Instance.new("Part")
	ring.Name = "Centre"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.new(1, 1, 1)
	ring.Size = Vector3.new(0.16, 1, 1)
	ring.Transparency = 0.1
	for _, part in { disc, ring } do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = marker
	end
	marker.PrimaryPart = disc
	marker.Parent = folder
	landingMarker = marker
	folder.Parent = Workspace.CurrentCamera or Workspace
	previewFolder = folder
	return folder
end

local function hidePreview()
	for _, bead in beads do
		bead.Transparency = 1
	end
	local marker = landingMarker
	if marker then
		for _, part in marker:GetChildren() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 1
			end
		end
	end
end

local function updateRaycastFilter()
	local filter: { Instance } = {}
	local balls = Workspace:FindFirstChild(BALL.FolderName)
	if balls then
		table.insert(filter, balls)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	if previewFolder then
		table.insert(filter, previewFolder)
	end
	local camera = Workspace.CurrentCamera
	if camera then
		table.insert(filter, camera)
	end
	raycastParams.FilterDescendantsInstances = filter
end

-- Distance de roulement d'un putt (modèle de BallMath.rollStep : dv/dt = -drag v - résistance).
local function rollDistance(speed: number, drag: number, resistance: number): number
	if speed <= 0 then
		return 0
	end
	if drag <= 1e-4 then
		return if resistance > 0 then speed * speed / (2 * resistance) else speed * 10
	end
	local k = resistance / drag
	if k <= 1e-4 then
		return speed / drag
	end
	local stopTime = math.log((speed + k) / k) / drag
	return (speed + k) * (1 - math.exp(-drag * stopTime)) / drag - k * stopTime
end

local function surfaceDef(): any
	local ball = state.ball
	local name = if ball then ball:GetAttribute("Surface") else nil
	return Gameplay.Surfaces[if type(name) == "string" then name else "Green"] or Gameplay.Surfaces.Green
end

local function previewPoints(origin: Vector3, power: number): ({ Vector3 }, Vector3?, Vector3?)
	local def = shotDef(state.shotType)
	local direction = aimDirection()
	if state.shotType == "Putt" then
		-- Roulé : ligne au sol, recalée par rayons vers le bas.
		local surface = surfaceDef()
		local speed = BallMath.launchSpeed(power, def)
		local distance = math.clamp(rollDistance(speed, surface.Drag, surface.RollResistance), 0.5, 140)
		local points = {}
		local steps = 24
		local finalPoint = origin
		local finalNormal = Vector3.yAxis
		for index = 0, steps do
			local flatPoint = origin + direction * (distance * index / steps)
			local hit = Workspace:Raycast(flatPoint + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), raycastParams)
			local point = if hit then hit.Position + Vector3.new(0, BALL.Diameter / 2, 0) else flatPoint
			table.insert(points, point)
			finalPoint = point
			finalNormal = if hit then hit.Normal else Vector3.yAxis
		end
		return points, finalPoint - Vector3.new(0, BALL.Diameter / 2, 0), finalNormal
	end
	local velocity = BallMath.launchVelocity(direction, state.loft, power, def)
	local gravity = BallMath.effectiveGravity(Workspace.Gravity, BALL.GravityScale)
	local landingNormal: Vector3? = nil
	local points, hit = BallMath.predictTrajectory(origin + Vector3.new(0, BALL.LiftOff, 0), velocity, {
		gravity = gravity,
		wind = currentWind(),
		drag = BALL.AirDrag,
		step = AIM.PreviewStep,
		maxTime = AIM.PreviewMaxTime,
		maxPoints = AIM.PreviewMaxPoints,
		collide = function(from: Vector3, to: Vector3): Vector3?
			local result = Workspace:Raycast(from, to - from, raycastParams)
			if result then
				landingNormal = result.Normal
				return result.Position
			end
			return nil
		end,
	})
	if hit then
		return points, points[#points], landingNormal or Vector3.yAxis
	end
	return points, nil, nil
end

-- Effets réduits (EffectsController s'il est disponible).
local effectsModule: any = nil
local effectsLooked = false
local function isReducedEffects(): boolean
	if not effectsLooked then
		effectsLooked = true
		local module = script.Parent:FindFirstChild("EffectsController")
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				effectsModule = result
			end
		end
	end
	if effectsModule and type(effectsModule.IsReduced) == "function" then
		local ok, reduced = pcall(effectsModule.IsReduced)
		return ok and reduced == true
	end
	return false
end

-- Place les perles régulièrement le long de la polyligne.
local function drawPreview(points: { Vector3 }, landing: Vector3?, normal: Vector3?)
	ensurePreview()
	local cumulative = { 0 }
	local total = 0
	for index = 2, #points do
		total += (points[index] - points[index - 1]).Magnitude
		cumulative[index] = total
	end
	local spacing = math.max(BEAD_MIN_SPACING, total / BEAD_COUNT)
	local segment = 2
	for index, bead in beads do
		local distance = (index - 0.5) * spacing
		if distance > total or #points < 2 then
			bead.Transparency = 1
			continue
		end
		while segment < #points and cumulative[segment] < distance do
			segment += 1
		end
		local a, b = points[segment - 1], points[segment]
		local span = cumulative[segment] - cumulative[segment - 1]
		local alpha = if span > 1e-4 then (distance - cumulative[segment - 1]) / span else 0
		bead.CFrame = CFrame.new(a:Lerp(b, math.clamp(alpha, 0, 1)))
		bead.Transparency = 0.05 + 0.5 * (distance / math.max(total, 1))
	end
	local marker = landingMarker
	if marker then
		local visible = landing ~= nil
		for _, part in marker:GetChildren() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = if visible then 0 else 1
			end
		end
		if landing then
			local up = if normal and normal.Magnitude > 0.5 then normal.Unit else Vector3.yAxis
			-- Le cylindre a son axe le long de X : on aligne X sur la normale.
			local right = if math.abs(up:Dot(Vector3.zAxis)) < 0.95 then up:Cross(Vector3.zAxis).Unit else up:Cross(Vector3.xAxis).Unit
			local back = up:Cross(right).Unit
			local base = CFrame.fromMatrix(landing + up * 0.08, up, right, back)
			local pulse = 1
			if not isReducedEffects() then
				pulse = 1 + 0.12 * math.sin(os.clock() * 6)
			end
			local disc = marker:FindFirstChild("Disque") :: BasePart?
			local center = marker:FindFirstChild("Centre") :: BasePart?
			if disc then
				disc.Size = Vector3.new(0.12, 3.4 * pulse, 3.4 * pulse)
				disc.CFrame = base
			end
			if center then
				center.CFrame = base * CFrame.new(0.03, 0, 0)
			end
		end
	end
end

-- Puissance conseillée pour atteindre le trou (recherche dichotomique ; nil si inconnue).
local function computeSweetSpot(): number?
	local ball = state.ball
	local cup = cupPosition()
	if not ball or not cup or state.shotType == "Guided" then
		return nil
	end
	local origin = ball.Position
	local target = BallMath.flatDistance(origin, cup)
	if target < 0.5 then
		return nil
	end
	local def = shotDef(state.shotType)
	local function reach(power: number): number
		if state.shotType == "Putt" then
			local surface = surfaceDef()
			return rollDistance(BallMath.launchSpeed(power, def), surface.Drag, surface.RollResistance)
		end
		local velocity = BallMath.launchVelocity(aimDirection(), state.loft, power, def)
		local points = BallMath.predictTrajectory(origin, velocity, {
			gravity = BallMath.effectiveGravity(Workspace.Gravity, BALL.GravityScale),
			wind = currentWind(),
			drag = BALL.AirDrag,
			step = 1 / 15,
			maxTime = 8,
			maxPoints = 200,
			floorY = cup.Y,
		})
		return BallMath.flatDistance(origin, points[#points])
	end
	if reach(1) < target then
		return 1
	end
	local low, high = 0, 1
	for _ = 1, 14 do
		local mid = (low + high) / 2
		if reach(mid) < target then
			low = mid
		else
			high = mid
		end
	end
	return (low + high) / 2
end

--------------------------------------------------------------------------------
-- Personnage (convention d'adresse du golfeur, voir BallMath.addressLook)
--------------------------------------------------------------------------------

local function faceAddress()
	local root, humanoid = getCharacterParts()
	if not root or not humanoid then
		return
	end
	if state.humanoidAutoRotate == nil then
		state.humanoidAutoRotate = humanoid.AutoRotate
	end
	humanoid.AutoRotate = false
	local look = BallMath.addressLook(aimDirection())
	if look then
		local position = root.Position
		local current = root.CFrame.LookVector
		if current:Dot(look) < 0.9995 then
			root.CFrame = CFrame.lookAt(position, position + look)
		end
	end
end

local function restoreCharacter()
	local _, humanoid = getCharacterParts()
	if humanoid then
		humanoid.AutoRotate = if state.humanoidAutoRotate == nil then true else state.humanoidAutoRotate :: boolean
	end
	state.humanoidAutoRotate = nil
end

--------------------------------------------------------------------------------
-- Caméra
--------------------------------------------------------------------------------

local function smoothAlpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

-- Position affichée de la balle : sphère lissée de BallVisualController si disponible (caméra sans à-coups).
local visualModule: any = nil
local visualLooked = false
local function displayedBallPosition(ball: BasePart): Vector3
	if not visualLooked then
		visualLooked = true
		local module = script.Parent:FindFirstChild("BallVisualController")
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				visualModule = result
			end
		end
	end
	if visualModule and type(visualModule.GetVisual) == "function" then
		local ok, visual = pcall(visualModule.GetVisual, ball)
		if ok and typeof(visual) == "Instance" and visual:IsA("BasePart") then
			return visual.Position
		end
	end
	return ball.Position
end

local function aimCameraUpdate(dt: number, current: CFrame): (CFrame?, Vector3?)
	local ball = state.ball
	if not ball or not ball.Parent then
		return nil, nil
	end
	local focus = displayedBallPosition(ball) + Vector3.new(0, AIM.FocusHeight, 0)
	local rotation = CFrame.Angles(0, state.yaw, 0) * CFrame.Angles(-state.pitch, 0, 0)
	local desired = focus + rotation * Vector3.new(0, 0, AIM.CameraDistance)
	local clipped = CameraController.ClipPosition(focus, desired)
	local target = CFrame.lookAt(clipped, focus)
	local from = state.cameraCFrame or current
	local result = from:Lerp(target, smoothAlpha(AIM.CameraSmoothing, dt))
	state.cameraCFrame = result
	return result, focus
end

local function followCameraUpdate(dt: number, current: CFrame): (CFrame?, Vector3?)
	local ball = state.ball
	if not ball or not ball.Parent then
		return nil, nil
	end
	local focus = displayedBallPosition(ball)
	local rotation = CFrame.Angles(0, state.yaw, 0) * CFrame.Angles(-math.rad(AIM.FollowPitchDeg), 0, 0)
	local desired = focus + rotation * Vector3.new(0, 0, AIM.FollowDistance)
	local clipped = CameraController.ClipPosition(focus, desired)
	local target = CFrame.lookAt(clipped, focus)
	local from = state.cameraCFrame or current
	local result = from:Lerp(target, smoothAlpha(AIM.FollowSmoothing, dt))
	state.cameraCFrame = result
	return result, focus
end

--------------------------------------------------------------------------------
-- Transitions
--------------------------------------------------------------------------------

local function setMode(mode: AimState)
	local previous = state.mode
	if previous == mode then
		return
	end
	state.mode = mode
	GolfAimController.StateChanged:Fire(mode, previous)
end

local function releaseMouse()
	if state.rmbDown then
		state.rmbDown = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	state.touchInput = nil
	state.keyYaw = 0
end

local function clampLoft()
	local def = shotDef(state.shotType)
	state.loft = math.clamp(state.loft, def.MinLoft, def.MaxLoft)
	panelCall("SetLoft", state.loft)
end

local function setShotType(shotType: string, announce: boolean)
	local def = shotDef(shotType)
	state.shotType = if SHOT_TYPES[shotType] then shotType else SHOT.DefaultType
	state.loft = def.DefaultLoft
	clampLoft()
	panelCall("SetShotType", state.shotType)
	state.sweetAt = 0
	if announce then
		local suggestion = nil
		if state.shotType == "Putt" then
			suggestion = Locale.t("aim.shot.suggested")
		end
		panelCall("SetSuggestion", suggestion)
	end
end

-- Quitte la visée/charge (sans passer par le suivi). notify : prévenir le serveur.
local function exitAim(notify: boolean, blockSeconds: number?)
	if state.mode ~= "Aiming" and state.mode ~= "Charging" then
		return
	end
	aimTrove:Clean()
	releaseMouse()
	hidePreview()
	panelCall("SetCharging", false)
	panelCall("SetVisible", false)
	panelCall("SetSuggestion", nil)
	panelCall("SetSweetSpot", nil)
	CameraController.PopDriver(CAMERA_DRIVER)
	restoreCharacter()
	if notify then
		Net.send("Golf.AimState", state.aimRoundId, false)
	end
	state.blockUntil = os.clock() + (blockSeconds or 0)
	setMode("Idle")
end

local function exitFollow()
	if state.mode ~= "Following" then
		return
	end
	aimTrove:Clean()
	CameraController.PopDriver(FOLLOW_DRIVER)
	state.cameraCFrame = nil
	setMode("Idle")
end

local function beginFollow()
	aimTrove:Clean()
	releaseMouse()
	hidePreview()
	panelCall("SetCharging", false)
	panelCall("SetVisible", false)
	panelCall("SetSuggestion", nil)
	CameraController.PopDriver(CAMERA_DRIVER)
	restoreCharacter()
	state.followStart = os.clock()
	state.followSawMoving = false
	state.followEndAt = 0
	setMode("Following")
	CameraController.PushDriver(FOLLOW_DRIVER, FOLLOW_PRIORITY, followCameraUpdate)
	-- Pendant le suivi, annuler rend la main au joueur.
	InputController.BindAtPriority("GolfFollowSkip", InputController.Priorities.Aim, function(inputState: Enum.UserInputState): boolean?
		if inputState == Enum.UserInputState.Begin then
			exitFollow()
		end
		return true
	end, Enum.KeyCode.Q, Enum.KeyCode.ButtonB, Enum.UserInputType.MouseButton2)
	aimTrove:Add(function()
		InputController.Unbind("GolfFollowSkip")
	end)
end

local function startCharging()
	if state.mode ~= "Aiming" then
		return
	end
	local reason = localAimRefusal()
	if reason ~= nil then
		showMessage(localizedOr("aim.cancel." .. reason, "aim.cancel.default"), "warn")
		exitAim(true, REENTER_BLOCK)
		return
	end
	state.chargeStart = os.clock()
	state.power = 0
	Net.send("Golf.SwingStart", state.aimRoundId)
	setMode("Charging")
	panelCall("SetCharging", true)
	refreshHint()
end

local function cancelCharging()
	if state.mode ~= "Charging" then
		return
	end
	setMode("Aiming")
	panelCall("SetCharging", false)
	refreshHint()
end

local function shoot()
	if state.mode ~= "Charging" then
		return
	end
	local elapsed = os.clock() - state.chargeStart
	if elapsed < SHOT.MinSwingTime then
		return -- trop tôt : le serveur refuserait (Shot.MinSwingTime)
	end
	local power = BallMath.powerAtTime(elapsed, gaugePeriod())
	local direction = aimDirection()
	local loft = BallMath.clampLoft(state.loft, shotDef(state.shotType))
	Net.send("Golf.Shoot", state.aimRoundId, direction, loft, power, state.shotType)
	beginFollow()
end

local function onSwingInput()
	if state.mode == "Aiming" then
		startCharging()
	elseif state.mode == "Charging" then
		shoot()
	end
end

local function onCancelInput()
	if state.mode == "Charging" then
		cancelCharging()
	elseif state.mode == "Aiming" then
		state.autoArmed = false
		exitAim(true, 0.3)
	elseif state.mode == "Following" then
		exitFollow()
	end
end

local function changeLoft(direction: number)
	if state.mode ~= "Aiming" and state.mode ~= "Charging" then
		return
	end
	state.loft += direction * SHOT.LoftStep
	clampLoft()
	state.sweetAt = 0
end

local function cycleShotType(step: number)
	if state.mode ~= "Aiming" then
		return
	end
	local list = availableShotTypes()
	local index = table.find(list, state.shotType) or 0
	index = ((index - 1 + step) % #list) + 1
	setShotType(list[index], false)
	panelCall("SetSuggestion", nil)
end

local function bindAimActions()
	local priority = InputController.Priorities.Aim
	local function pressOnly(fn: () -> ()): (Enum.UserInputState) -> boolean?
		return function(inputState: Enum.UserInputState): boolean?
			if inputState == Enum.UserInputState.Begin then
				fn()
			end
			return true
		end
	end
	InputController.BindAtPriority("GolfSwing", priority, pressOnly(onSwingInput), Enum.KeyCode.Space, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonR2)
	InputController.BindAtPriority("GolfCancel", priority, pressOnly(onCancelInput), Enum.KeyCode.Q, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	InputController.BindAtPriority("GolfLoftUp", priority, pressOnly(function()
		changeLoft(1)
	end), Enum.KeyCode.R, Enum.KeyCode.Up, Enum.KeyCode.DPadUp)
	InputController.BindAtPriority("GolfLoftDown", priority, pressOnly(function()
		changeLoft(-1)
	end), Enum.KeyCode.F, Enum.KeyCode.Down, Enum.KeyCode.DPadDown)
	InputController.BindAtPriority("GolfShotType", priority, pressOnly(function()
		cycleShotType(1)
	end), Enum.KeyCode.T, Enum.KeyCode.DPadRight)
	InputController.BindAtPriority("GolfShotTypePrev", priority, pressOnly(function()
		cycleShotType(-1)
	end), Enum.KeyCode.DPadLeft)
	InputController.BindAtPriority("GolfLoftWheel", priority, function(inputState: Enum.UserInputState, input: InputObject?): boolean?
		if inputState == Enum.UserInputState.Change and input then
			local z = input.Position.Z
			if z > 0 then
				changeLoft(1)
			elseif z < 0 then
				changeLoft(-1)
			end
		end
		return true
	end, Enum.UserInputType.MouseWheel)
	local function yawKey(direction: number): (Enum.UserInputState) -> boolean?
		return function(inputState: Enum.UserInputState): boolean?
			if inputState == Enum.UserInputState.Begin then
				state.keyYaw = direction
			elseif state.keyYaw == direction then
				state.keyYaw = 0
			end
			return true
		end
	end
	InputController.BindAtPriority("GolfYawLeft", priority, yawKey(-1), Enum.KeyCode.A, Enum.KeyCode.Left)
	InputController.BindAtPriority("GolfYawRight", priority, yawKey(1), Enum.KeyCode.D, Enum.KeyCode.Right)
	-- Consomme W/S/saut pendant la visée (le personnage ne bouge pas).
	InputController.BindAtPriority("GolfAimSink", priority, function(): boolean?
		return true
	end, Enum.KeyCode.W, Enum.KeyCode.S, Enum.KeyCode.ButtonL3)
	-- Clic droit : glisser = orienter ; clic bref = annuler.
	InputController.BindAtPriority("GolfOrbit", priority, function(inputState: Enum.UserInputState): boolean?
		if inputState == Enum.UserInputState.Begin then
			state.rmbDown = true
			state.rmbStart = os.clock()
			state.rmbMoved = 0
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			local wasTap = state.rmbDown and os.clock() - state.rmbStart <= TAP_MAX_TIME and state.rmbMoved <= TAP_MAX_MOVE
			releaseMouse()
			if wasTap and inputState == Enum.UserInputState.End then
				onCancelInput()
			end
		end
		return true
	end, Enum.UserInputType.MouseButton2)

	for _, action in { "GolfSwing", "GolfCancel", "GolfLoftUp", "GolfLoftDown", "GolfShotType", "GolfShotTypePrev", "GolfLoftWheel", "GolfYawLeft", "GolfYawRight", "GolfAimSink", "GolfOrbit" } do
		aimTrove:Add(function()
			InputController.Unbind(action)
		end)
	end

	-- Glisser tactile (hors interface) : orienter la visée.
	aimTrove:Connect(UserInputService.InputBegan, function(input: InputObject, processed: boolean)
		if processed or input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if state.touchInput == nil then
			state.touchInput = input
		end
	end)
	aimTrove:Connect(UserInputService.InputChanged, function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch and input == state.touchInput then
			local delta = input.Delta
			state.yaw -= delta.X * AIM.TouchSensitivity
			state.pitch = math.clamp(state.pitch + delta.Y * AIM.TouchSensitivity, math.rad(AIM.MinPitchDeg), math.rad(AIM.MaxPitchDeg))
		end
	end)
	aimTrove:Connect(UserInputService.InputEnded, function(input: InputObject)
		if input == state.touchInput then
			state.touchInput = nil
		end
	end)

	-- Boutons du panneau (tactile surtout).
	local panel = getPanel()
	if panel then
		aimTrove:Add(panel.SwingActivated:Connect(onSwingInput))
		aimTrove:Add(panel.CancelActivated:Connect(onCancelInput))
		aimTrove:Add(panel.ShotTypeActivated:Connect(function()
			cycleShotType(1)
		end))
		aimTrove:Add(panel.LoftChanged:Connect(function(delta: any)
			changeLoft(if type(delta) == "number" and delta < 0 then -1 else 1)
		end))
	end
	aimTrove:Connect(InputController.DeviceChanged, refreshHint)
end

local function enterAim()
	if state.mode ~= "Idle" then
		return
	end
	if os.clock() < state.blockUntil then
		return
	end
	local refusal = localAimRefusal()
	if refusal then
		return
	end
	local ball = state.ball :: BasePart
	state.aimRoundId = currentRoundId()
	state.autoArmed = false
	-- Direction initiale : vers le trou s'il est connu, sinon selon la caméra actuelle.
	local cup = cupPosition()
	local initial: Vector3? = nil
	if cup then
		local toCup = Vector3.new(cup.X - ball.Position.X, 0, cup.Z - ball.Position.Z)
		if toCup.Magnitude > 0.5 then
			initial = toCup.Unit
		end
	end
	if not initial then
		local camera = Workspace.CurrentCamera
		if camera then
			local look = camera.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude > 1e-3 then
				initial = flat.Unit
			end
		end
	end
	local direction = initial or Vector3.new(0, 0, -1)
	state.yaw = math.atan2(-direction.X, -direction.Z)
	state.pitch = math.rad(AIM.DefaultPitchDeg)
	local camera = Workspace.CurrentCamera
	state.cameraCFrame = if camera then camera.CFrame else nil

	Net.send("Golf.AimState", state.aimRoundId, true)
	setMode("Aiming")
	setShotType(if puttAllowed() then "Putt" else SHOT.DefaultType, true)
	CameraController.PushDriver(CAMERA_DRIVER, CAMERA_PRIORITY, aimCameraUpdate)
	bindAimActions()
	ensurePreview()
	panelCall("SetVisible", true)
	panelCall("SetCharging", false)
	panelCall("SetWind", currentWind())
	refreshHint()
end

--------------------------------------------------------------------------------
-- Boucle de rendu
--------------------------------------------------------------------------------

local function updateRotation(dt: number)
	-- Souris (clic droit maintenu).
	if state.rmbDown then
		local delta = UserInputService:GetMouseDelta()
		state.rmbMoved += math.abs(delta.X) + math.abs(delta.Y)
		state.yaw -= delta.X * AIM.MouseSensitivity
		state.pitch = math.clamp(state.pitch + delta.Y * AIM.MouseSensitivity, math.rad(AIM.MinPitchDeg), math.rad(AIM.MaxPitchDeg))
	end
	-- Clavier.
	if state.keyYaw ~= 0 then
		state.yaw -= state.keyYaw * KEY_YAW_SPEED * dt
	end
	-- Manette : sticks droit (orientation + inclinaison) et gauche (orientation).
	local ok, gamepadStates = pcall(function(): { InputObject }
		return UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
	end)
	if ok then
		for _, input in gamepadStates do
			if input.KeyCode == Enum.KeyCode.Thumbstick2 or input.KeyCode == Enum.KeyCode.Thumbstick1 then
				local position = input.Position
				local x = if math.abs(position.X) > 0.15 then position.X else 0
				state.yaw -= x * AIM.StickSpeed * dt
				if input.KeyCode == Enum.KeyCode.Thumbstick2 then
					local y = if math.abs(position.Y) > 0.15 then position.Y else 0
					state.pitch = math.clamp(state.pitch - y * AIM.StickSpeed * 0.6 * dt, math.rad(AIM.MinPitchDeg), math.rad(AIM.MaxPitchDeg))
				end
			end
		end
	end
end

local function updateAiming(dt: number)
	local ball = state.ball
	if not ball or not ball.Parent then
		exitAim(true)
		return
	end
	-- Abandon local évident (la surveillance serveur confirme de son côté).
	local root = getCharacterParts()
	if root and (root.Position - ball.Position).Magnitude > SHOT.AimExitDistance then
		showMessage(Locale.t("aim.cancel.too_far"), "warn")
		exitAim(true, REENTER_BLOCK)
		return
	end
	if ball:GetAttribute("State") ~= "Resting" and state.mode == "Aiming" then
		exitAim(true, REENTER_BLOCK)
		return
	end
	updateRotation(dt)
	faceAddress()

	local power = AIM.IdleArrowPower
	if state.mode == "Charging" then
		local elapsed = os.clock() - state.chargeStart
		if elapsed > SHOT.MaxSwingTime - MAX_SWING_MARGIN then
			cancelCharging()
		else
			power = BallMath.powerAtTime(elapsed, gaugePeriod())
			state.power = power
			panelCall("SetPower", power)
		end
	end

	updateRaycastFilter()
	local points, landing, normal = previewPoints(ball.Position, power)
	drawPreview(points, landing, normal)

	local cup = cupPosition()
	panelCall("SetDistance", if cup then BallMath.flatDistance(ball.Position, cup) else nil)
	panelCall("SetWind", currentWind())
	local now = os.clock()
	if now >= state.sweetAt then
		state.sweetAt = now + SWEET_SPOT_INTERVAL
		panelCall("SetSweetSpot", computeSweetSpot())
	end
end

local function updateFollowing()
	local ball = state.ball
	local now = os.clock()
	if not ball or not ball.Parent then
		exitFollow()
		return
	end
	local ballState = ball:GetAttribute("State")
	if ballState == "Moving" then
		state.followSawMoving = true
	end
	if state.followEndAt > 0 then
		if now >= state.followEndAt then
			exitFollow()
		end
		return
	end
	if ballState == "Holed" then
		state.followEndAt = now + FOLLOW_HOLED_DELAY
	elseif state.followSawMoving and (ballState == "Resting" or ballState == "Frozen") then
		state.followEndAt = now + FOLLOW_REST_DELAY
		state.autoArmed = true
	elseif not state.followSawMoving and now - state.followStart > AIM.FollowStartTimeout then
		exitFollow() -- frappe refusée ou perdue : retour immédiat
	elseif now - state.followStart > math.max(AIM.FollowMaxTime, FOLLOW_HARD_LIMIT) then
		exitFollow()
	else
		-- Le joueur bouge : il reprend la main.
		local _, humanoid = getCharacterParts()
		if humanoid and humanoid.MoveDirection.Magnitude > 0.2 and now - state.followStart > 0.4 then
			exitFollow()
		end
	end
end

local function sendReset()
	local now = os.clock()
	if now - state.resetSentAt < RESET_COOLDOWN then
		return
	end
	state.resetSentAt = now
	Net.send("Golf.ResetBall", currentRoundId())
end

local function updatePrompt()
	local text: string? = nil
	local device = InputController.GetDevice()
	local canAim = state.mode == "Idle" and os.clock() >= state.blockUntil and localAimRefusal() == nil
	if state.resetHolding then
		text = Locale.t("aim.prompt.resetHolding")
	elseif state.mode == "Following" then
		text = Locale.t("aim.prompt.following", { key = keyLabel("GolfFollowSkip") })
	elseif canAim then
		if device == "Touch" then
			text = Locale.t("aim.prompt.enterTouch", { button = Locale.t("controls.action.aim") })
		else
			text = Locale.t("aim.prompt.enter", { key = keyLabel("GolfAim") })
		end
	end
	if text ~= state.lastPrompt then
		state.lastPrompt = text
		panelCall("SetPrompt", text)
	end
	if canAim ~= state.lastTouchAim then
		state.lastTouchAim = canAim
		InputController.SetTouchButtonVisible("GolfAim", canAim)
	end
	local ball = state.ball
	local showReset = ball ~= nil and ball.Parent ~= nil and ball:GetAttribute("State") ~= "Holed" and phaseAllowsShot() and state.mode ~= "Charging"
	if showReset ~= state.lastTouchReset then
		state.lastTouchReset = showReset
		InputController.SetTouchButtonVisible("GolfResetBall", showReset)
	end
	-- Entrée automatique après un coup (jamais à l'entraînement).
	if canAim and AIM.AutoEnter and state.autoArmed and not isPracticeBall() then
		enterAim()
	end
end

local function onRenderStep(dt: number)
	local mode = state.mode
	if mode == "Aiming" or mode == "Charging" then
		updateAiming(dt)
	elseif mode == "Following" then
		updateFollowing()
	end
	if state.resetHolding and os.clock() - state.resetHoldStart >= RESET_HOLD_TIME then
		state.resetHolding = false
		sendReset()
	end
	updatePrompt()
end

--------------------------------------------------------------------------------
-- Balle du joueur local
--------------------------------------------------------------------------------

local function setBall(ball: BasePart?)
	if state.ball == ball then
		return
	end
	if state.ballTrove then
		state.ballTrove:Clean()
		state.ballTrove = nil
	end
	if state.mode == "Aiming" or state.mode == "Charging" then
		exitAim(true)
	elseif state.mode == "Following" then
		exitFollow()
	end
	state.ball = ball
	if ball then
		local trove = Trove.new()
		state.ballTrove = trove
		state.autoArmed = true
		trove:Connect(ball:GetAttributeChangedSignal("State"), function()
			local value = ball:GetAttribute("State")
			if value == "Resting" and state.mode == "Idle" then
				state.autoArmed = true
			end
		end)
	end
end

local function isOwnBall(instance: Instance): boolean
	return instance:IsA("BasePart") and instance:GetAttribute("OwnerUserId") == localPlayer.UserId
end

local function scanBalls(folder: Instance)
	for _, child in folder:GetChildren() do
		if isOwnBall(child) then
			setBall(child :: BasePart)
			return
		end
	end
	setBall(nil)
end

local function watchBallsFolder(folder: Instance)
	runtimeTrove:Connect(folder.ChildAdded, function(child: Instance)
		if child:IsA("BasePart") then
			-- L'attribut OwnerUserId peut arriver juste après l'instance (signaux différés).
			task.defer(function()
				if isOwnBall(child) and child.Parent == folder then
					setBall(child)
				end
			end)
		end
	end)
	runtimeTrove:Connect(folder.ChildRemoved, function(child: Instance)
		if child == state.ball then
			scanBalls(folder)
		end
	end)
	scanBalls(folder)
end

--------------------------------------------------------------------------------
-- Événements serveur
--------------------------------------------------------------------------------

local function onAimCancelled(reason: any)
	local key = if type(reason) == "string" then "aim.cancel." .. reason else "aim.cancel.default"
	local text = localizedOr(key, "aim.cancel.default")
	if state.mode == "Aiming" or state.mode == "Charging" then
		exitAim(false, REENTER_BLOCK)
		showMessage(text, "warn")
	elseif state.mode == "Following" and not state.followSawMoving then
		exitFollow()
		state.blockUntil = os.clock() + REENTER_BLOCK
		showMessage(text, "warn")
	end
end

local function onShotAccepted(info: any)
	local forced = type(info) == "table" and info.forced == true
	if state.mode == "Aiming" or state.mode == "Charging" then
		beginFollow() -- frappe forcée (Corne) pendant la visée
	end
	if forced then
		showMessage(Locale.t("aim.shot.forced"), "warn")
	end
end

local function onBallReset(reason: any, penalty: any)
	local key = if type(reason) == "string" then "aim.reset." .. reason else "aim.reset.generic"
	local text = localizedOr(key, "aim.reset.generic")
	if isFiniteNumber(penalty) and penalty > 0 then
		text = Locale.t(if penalty > 1 then "aim.reset.penaltyMany" else "aim.reset.penalty", { text = text, n = penalty })
	end
	if state.mode == "Aiming" or state.mode == "Charging" then
		exitAim(true, REENTER_BLOCK)
	elseif state.mode == "Following" then
		exitFollow()
	end
	state.autoArmed = true
	showMessage(text, "info")
end

local function onPhaseOrRoundChanged()
	if state.mode == "Aiming" or state.mode == "Charging" then
		if not phaseAllowsShot() or currentRoundId() ~= state.aimRoundId then
			exitAim(true)
		end
	elseif state.mode == "Following" and not phaseAllowsShot() then
		exitFollow()
	end
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

function GolfAimController.GetState(): AimState
	return state.mode
end

function GolfAimController.IsAiming(): boolean
	return state.mode == "Aiming" or state.mode == "Charging"
end

function GolfAimController.GetBall(): BasePart?
	return state.ball
end

function GolfAimController.IsPractice(): boolean
	return isPracticeBall()
end

function GolfAimController.Cancel(reason: string?)
	if state.mode == "Aiming" or state.mode == "Charging" then
		exitAim(true, REENTER_BLOCK)
		if type(reason) == "string" and reason ~= "" then
			showMessage(localizedOr("aim.cancel." .. reason, "aim.cancel.default"), "warn")
		end
	elseif state.mode == "Following" then
		exitFollow()
	end
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function GolfAimController.Init()
	if state.initialized then
		return
	end
	state.initialized = true

	-- Action « Viser » (toujours liée : passe la main si la visée est impossible).
	InputController.Bind("GolfAim", function(inputState: Enum.UserInputState): boolean?
		if inputState ~= Enum.UserInputState.Begin then
			return false
		end
		if state.mode == "Idle" and localAimRefusal() == nil and os.clock() >= state.blockUntil then
			enterAim()
			return true
		end
		return false
	end, Enum.KeyCode.E, Enum.KeyCode.ButtonL2)
	InputController.SetTouchButton("GolfAim", {
		text = Locale.t("controls.action.aim"),
		slot = "ActionC",
		color = Color3.fromRGB(91, 209, 91),
		visible = false,
	})

	-- Balle bloquée : maintenir G / Y.
	InputController.Bind("GolfResetBall", function(inputState: Enum.UserInputState): boolean?
		local ball = state.ball
		if inputState == Enum.UserInputState.Begin then
			if not ball or ball:GetAttribute("State") == "Holed" or not phaseAllowsShot() or state.mode == "Charging" then
				return false
			end
			state.resetHolding = true
			state.resetHoldStart = os.clock()
			return true
		end
		local wasHolding = state.resetHolding
		state.resetHolding = false
		return wasHolding
	end, Enum.KeyCode.G, Enum.KeyCode.ButtonY)
	InputController.SetTouchButton("GolfResetBall", {
		text = Locale.t("controls.action.resetBall"),
		slot = "ActionD",
		visible = false,
	})
	runtimeTrove:Add(function()
		InputController.Unbind("GolfAim")
		InputController.Unbind("GolfResetBall")
		InputController.SetTouchButton("GolfAim", nil)
		InputController.SetTouchButton("GolfResetBall", nil)
	end)

	runtimeTrove:Add(Net.listen("Golf.AimCancelled", onAimCancelled))
	runtimeTrove:Add(Net.listen("Golf.ShotAccepted", onShotAccepted))
	runtimeTrove:Add(Net.listen("Golf.BallReset", onBallReset))

	runtimeTrove:Connect(localPlayer.CharacterAdded, function()
		if state.mode == "Aiming" or state.mode == "Charging" then
			exitAim(true)
		end
		state.humanoidAutoRotate = nil
	end)
	runtimeTrove:Connect(localPlayer:GetAttributeChangedSignal("KnockedOut"), function()
		if localPlayer:GetAttribute("KnockedOut") == true and GolfAimController.IsAiming() then
			exitAim(true, REENTER_BLOCK)
		end
	end)
	runtimeTrove:Add(aimTrove)
	runtimeTrove:Add(function()
		CameraController.PopDriver(CAMERA_DRIVER)
		CameraController.PopDriver(FOLLOW_DRIVER)
		if previewFolder then
			previewFolder:Destroy()
			previewFolder = nil
		end
		table.clear(beads)
		landingMarker = nil
	end)
end

function GolfAimController.Start()
	if state.started then
		return
	end
	state.started = true
	local ok, folder = pcall(GameState.get)
	if ok and typeof(folder) == "Instance" then
		local gameState = folder :: Folder
		state.gameState = gameState
		runtimeTrove:Connect(gameState:GetAttributeChangedSignal("Phase"), onPhaseOrRoundChanged)
		runtimeTrove:Connect(gameState:GetAttributeChangedSignal("RoundId"), onPhaseOrRoundChanged)
	else
		Log.warn("Aim", "GameState indisponible : visée limitée à l'entraînement")
	end
	runtimeTrove:Connect(localPlayer:GetAttributeChangedSignal("Practice"), onPhaseOrRoundChanged)

	getPanel()
	RunService:BindToRenderStep("GolfChaosAim", Enum.RenderPriority.Input.Value + 1, onRenderStep)
	runtimeTrove:Add(function()
		RunService:UnbindFromRenderStep("GolfChaosAim")
	end)

	local balls = Workspace:FindFirstChild(BALL.FolderName) or Workspace:WaitForChild(BALL.FolderName, 120)
	if balls then
		watchBallsFolder(balls)
	else
		Log.warn("Aim", "dossier Workspace." .. BALL.FolderName .. " introuvable")
	end
end

return GolfAimController
