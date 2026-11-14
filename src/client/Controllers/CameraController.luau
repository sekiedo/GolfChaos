--!strict
--[[
	CameraController — caméra du joueur local : 3e personne par défaut, prises de contrôle scriptées,
	secousses, suivi (spectateur) et survol d'introduction des trous.

	API :
	  CameraController.Shake(intensite, duree)            -- secousse ; respecte le réglage « cameraShake »
	                                                     -- (false / 0 = aucune ; nombre 0..1 = atténuation)
	  CameraController.Follow(cible?)                     -- suivre un Player / Model / Humanoid / BasePart ;
	                                                     -- nil = revenir à son propre personnage
	  CameraController.GetFollowTarget() -> any?
	  CameraController.PlayFlyover(points, duree, options?) -> boolean
	        points  : { CFrame | Vector3 } (au moins 1) ; Vector3 = position, regard vers options.lookAt
	                  ou vers le point suivant
	        options : { lookAt: Vector3?, skippable: boolean? (défaut true), keepAfterPhase: boolean?,
	                    onComplete: ((completed: boolean) -> ())? }
	  CameraController.CancelFlyover()   CameraController.IsFlyoverPlaying() -> boolean
	  CameraController.Restore()                          -- annule survol + suivi + secousses, caméra par défaut
	  CameraController.PushDriver(nom, priorite, update)  -- prise de contrôle scriptée (visée, suivi de balle) :
	        update(dt, cframeCourante) -> (CFrame?, focus: Vector3?) ; le pilote de plus haute priorité gagne
	  CameraController.PopDriver(nom)    CameraController.HasDriver(nom) -> boolean
	  CameraController.ClipPosition(focus, souhaitee, exclus?) -> Vector3   -- évite de traverser les murs
	  Signaux : FlyoverFinished(completed: boolean), FollowTargetLost(cible)

	Fonctionnement :
	  - Hors pilote, la caméra Roblox par défaut (PlayerModule) reste maître : confortable et familière.
	  - Les effets (secousse, transition douce au retour) sont appliqués APRÈS la caméra par défaut puis
	    retirés AVANT sa mise à jour suivante : son état interne n'est jamais pollué (pas de dérive).
	  - Survol d'intro : lancé automatiquement à la phase HoleIntro si personne d'autre ne l'a fait
	    (départ = personnage local, arrivée = GameState.CupPosition) ; annulé à la fin de la phase.
	  - Aucun effet de bord au require.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Signal = require(Shared.Util.Signal)
local Trove = require(Shared.Util.Trove)
local Log = require(Shared.Util.Log)
local GameState = require(Shared.Util.GameState)
local Locale = require(Shared.Locale)

local InputController = require(script.Parent.InputController)

export type DriverUpdate = (dt: number, current: CFrame) -> (CFrame?, Vector3?)
export type FlyoverOptions = {
	lookAt: Vector3?,
	skippable: boolean?,
	keepAfterPhase: boolean?,
	onComplete: ((completed: boolean) -> ())?,
}

type Driver = { name: string, priority: number, update: DriverUpdate, order: number }
type ShakeEntry = { intensity: number, duration: number, startedAt: number, seed: number }
type Flyover = {
	positions: { Vector3 },
	rotations: { CFrame },
	cumulative: { number }, -- longueur cumulée jusqu'à chaque point (pour une vitesse régulière)
	totalLength: number,
	duration: number,
	startedAt: number,
	options: FlyoverOptions,
	trove: Trove.Trove,
}

local CameraController = {}
CameraController.Priority = 20

CameraController.FlyoverFinished = Signal.new()
CameraController.FollowTargetLost = Signal.new()

-- Réglages locaux (valeurs de présentation, sans effet sur le gameplay).
local DEFAULT_FIELD_OF_VIEW = 70
local RETURN_TRANSITION_TIME = 0.35 -- s : retour doux vers la caméra par défaut après un pilote
local SHAKE_MAX_ANGLE_DEG = 2.4 -- amplitude angulaire à intensité 1
local SHAKE_FREQUENCY = 18 -- vitesse du bruit de secousse
local SHAKE_MAX_INTENSITY = 3
local SHAKE_MAX_DURATION = 5
local SHAKE_MAX_ACTIVE = 8
local CLIP_RADIUS = 0.6
local CLIP_MARGIN = 0.3
local FLYOVER_DRIVER = "__Flyover"
local FLYOVER_PRIORITY = 100
local SKIP_ACTION = "CameraSkipFlyover"
local INTRO_AUTOSTART_DELAY = 0.25 -- s : laisse l'interface d'intro lancer son propre survol d'abord
local INTRO_MIN_DURATION = 2
local INTRO_MAX_DURATION = 7
local RENDER_PRE = "GolfChaosCameraPre"
local RENDER_MAIN = "GolfChaosCameraMain"

local localPlayer = Players.LocalPlayer

local drivers: { Driver } = {}
local shakes: { ShakeEntry } = {}
local runtimeTrove: Trove.Trove = Trove.new()
local clipParams = RaycastParams.new()

local cam = {
	initialized = false,
	scripted = false, -- true tant qu'un pilote impose CameraType.Scriptable
	driverOrder = 0,
	baseCFrame = nil :: CFrame?, -- CFrame avant effets (dernière image)
	appliedCFrame = nil :: CFrame?, -- CFrame réellement posée après effets
	transitionFrom = nil :: CFrame?,
	transitionStartedAt = 0,
	transitionDuration = 0,
	followTarget = nil :: any,
	followTrove = nil :: Trove.Trove?,
	flyover = nil :: Flyover?,
	introToken = 0,
	settingsModule = nil :: any,
	settingsLooked = false,
}

--------------------------------------------------------------------------------
-- Utilitaires
--------------------------------------------------------------------------------

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function getSetting(key: string): any
	if not cam.settingsLooked then
		cam.settingsLooked = true
		local module = script.Parent:FindFirstChild("SettingsController")
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				cam.settingsModule = result
			end
		end
	end
	local settings = cam.settingsModule
	if settings and type(settings.Get) == "function" then
		local ok, value = pcall(settings.Get, key)
		if ok then
			return value
		end
	end
	return nil
end

local function getOwnHumanoid(): Humanoid?
	local character = localPlayer.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function getOwnRoot(): BasePart?
	local character = localPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function smoothstep(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

--------------------------------------------------------------------------------
-- Sujet de la caméra (soi ou cible suivie)
--------------------------------------------------------------------------------

local function subjectFor(target: any): Instance?
	if typeof(target) ~= "Instance" then
		return nil
	end
	local instance = target :: Instance
	if instance:IsA("Player") then
		local character = instance.Character
		if not character then
			return nil
		end
		return character:FindFirstChildOfClass("Humanoid") or character:FindFirstChild("HumanoidRootPart")
	elseif instance:IsA("Humanoid") then
		return instance
	elseif instance:IsA("Model") then
		return instance:FindFirstChildOfClass("Humanoid") or instance.PrimaryPart
	elseif instance:IsA("BasePart") then
		return instance
	end
	return nil
end

local function applyDefaultCamera()
	local camera = Workspace.CurrentCamera
	if not camera or #drivers > 0 then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Custom then
		camera.CameraType = Enum.CameraType.Custom
	end
	local subject = subjectFor(cam.followTarget) or getOwnHumanoid()
	if subject and camera.CameraSubject ~= subject then
		camera.CameraSubject = subject :: any
	end
end

--------------------------------------------------------------------------------
-- Pilotes (prises de contrôle scriptées)
--------------------------------------------------------------------------------

local function topDriver(): Driver?
	local best: Driver? = nil
	for _, driver in drivers do
		if best == nil or driver.priority > best.priority or (driver.priority == best.priority and driver.order > best.order) then
			best = driver
		end
	end
	return best
end

function CameraController.PushDriver(name: string, priority: number, update: DriverUpdate)
	assert(type(name) == "string" and name ~= "", "CameraController.PushDriver : nom invalide")
	assert(type(update) == "function", "CameraController.PushDriver : update manquant")
	for index, driver in drivers do
		if driver.name == name then
			table.remove(drivers, index)
			break
		end
	end
	cam.driverOrder += 1
	table.insert(drivers, { name = name, priority = priority, update = update, order = cam.driverOrder })
end

function CameraController.PopDriver(name: string)
	for index, driver in drivers do
		if driver.name == name then
			table.remove(drivers, index)
			return
		end
	end
end

function CameraController.HasDriver(name: string): boolean
	for _, driver in drivers do
		if driver.name == name then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Anti-traversée des murs
--------------------------------------------------------------------------------

function CameraController.ClipPosition(focus: Vector3, desired: Vector3, exclude: { Instance }?): Vector3
	local offset = desired - focus
	local distance = offset.Magnitude
	if distance < 0.05 then
		return desired
	end
	local filter: { Instance } = {}
	if exclude then
		for _, instance in exclude do
			table.insert(filter, instance)
		end
	end
	local character = localPlayer.Character
	if character then
		table.insert(filter, character)
	end
	local balls = Workspace:FindFirstChild("Balls")
	if balls then
		table.insert(filter, balls)
	end
	clipParams.FilterDescendantsInstances = filter
	local okCast, result = pcall(function(): RaycastResult?
		return Workspace:Spherecast(focus, CLIP_RADIUS, offset, clipParams)
	end)
	if not okCast then
		result = Workspace:Raycast(focus, offset, clipParams)
	end
	if result then
		local allowed = math.max(result.Distance - CLIP_MARGIN, 0.5)
		return focus + offset.Unit * math.min(allowed, distance)
	end
	return desired
end

--------------------------------------------------------------------------------
-- Secousses
--------------------------------------------------------------------------------

local function shakeScale(): number
	local setting = getSetting("cameraShake")
	local scale = 1
	if setting == false then
		return 0
	elseif type(setting) == "number" and isFiniteNumber(setting) then
		-- Accepte 0..1 ou un pourcentage 0..100.
		scale = if setting > 1 then setting / 100 else setting
		scale = math.clamp(scale, 0, 1)
	end
	if getSetting("reducedEffects") == true then
		scale *= 0.5
	end
	return scale
end

function CameraController.Shake(intensity: number, duration: number)
	if not isFiniteNumber(intensity) or not isFiniteNumber(duration) then
		return
	end
	local scale = shakeScale()
	if scale <= 0 then
		return
	end
	local amount = math.clamp(intensity, 0, SHAKE_MAX_INTENSITY) * scale
	local length = math.clamp(duration, 0, SHAKE_MAX_DURATION)
	if amount <= 0 or length <= 0 then
		return
	end
	if #shakes >= SHAKE_MAX_ACTIVE then
		table.remove(shakes, 1)
	end
	table.insert(shakes, { intensity = amount, duration = length, startedAt = os.clock(), seed = math.random() * 1000 })
end

local function shakeOffset(now: number): CFrame?
	if #shakes == 0 then
		return nil
	end
	local pitch, yaw, roll = 0, 0, 0
	local index = 1
	while index <= #shakes do
		local entry = shakes[index]
		local progress = (now - entry.startedAt) / entry.duration
		if progress >= 1 then
			table.remove(shakes, index)
		else
			local fade = (1 - progress) * (1 - progress)
			local amplitude = entry.intensity * fade * 2 -- math.noise rend environ [-0.5, 0.5]
			local t = now * SHAKE_FREQUENCY
			pitch += math.noise(entry.seed, t, 0.5) * amplitude
			yaw += math.noise(t, entry.seed, 1.5) * amplitude
			roll += math.noise(0.5, t, entry.seed) * amplitude * 0.5
			index += 1
		end
	end
	if pitch == 0 and yaw == 0 and roll == 0 then
		return nil
	end
	local maxAngle = math.rad(SHAKE_MAX_ANGLE_DEG)
	return CFrame.Angles(pitch * maxAngle, yaw * maxAngle, roll * maxAngle)
end

--------------------------------------------------------------------------------
-- Suivi (spectateur)
--------------------------------------------------------------------------------

local function loseFollowTarget(target: any)
	if cam.followTarget ~= target then
		return
	end
	CameraController.Follow(nil)
	CameraController.FollowTargetLost:Fire(target)
end

function CameraController.Follow(target: any)
	if cam.followTrove then
		cam.followTrove:Clean()
		cam.followTrove = nil
	end
	if target ~= nil and typeof(target) ~= "Instance" then
		Log.warn("Camera", "Follow : cible invalide", typeof(target))
		target = nil
	end
	cam.followTarget = target
	if target ~= nil then
		local trove = Trove.new()
		cam.followTrove = trove
		local instance = target :: Instance
		if instance:IsA("Player") then
			trove:Connect(instance.CharacterAdded, function()
				task.defer(applyDefaultCamera)
			end)
			trove:Connect(instance.CharacterRemoving, function()
				task.defer(applyDefaultCamera)
			end)
		end
		trove:Connect(instance.AncestryChanged, function(_child: Instance, parent: Instance?)
			if parent == nil then
				task.defer(loseFollowTarget, target)
			end
		end)
	end
	applyDefaultCamera()
end

function CameraController.GetFollowTarget(): any
	return cam.followTarget
end

--------------------------------------------------------------------------------
-- Survol (intro des trous)
--------------------------------------------------------------------------------

local function catmullRom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2 = t * t
	local t3 = t2 * t
	return ((p1 * 2) + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end

local function sampleFlyover(flyover: Flyover, u: number): CFrame
	local positions = flyover.positions
	local count = #positions
	if count == 1 or flyover.totalLength <= 1e-3 then
		return CFrame.new(positions[1]) * flyover.rotations[1]
	end
	local target = math.clamp(u, 0, 1) * flyover.totalLength
	local segment = count - 1
	for index = 1, count - 1 do
		if flyover.cumulative[index + 1] >= target then
			segment = index
			break
		end
	end
	local startLength = flyover.cumulative[segment]
	local segmentLength = flyover.cumulative[segment + 1] - startLength
	local t = if segmentLength > 1e-4 then (target - startLength) / segmentLength else 1
	local p0 = positions[math.max(segment - 1, 1)]
	local p1 = positions[segment]
	local p2 = positions[segment + 1]
	local p3 = positions[math.min(segment + 2, count)]
	local position = catmullRom(p0, p1, p2, p3, t)
	local rotation = flyover.rotations[segment]:Lerp(flyover.rotations[segment + 1], smoothstep(t))
	return CFrame.new(position) * rotation
end

local function finishFlyover(completed: boolean)
	local flyover = cam.flyover
	if not flyover then
		return
	end
	cam.flyover = nil
	CameraController.PopDriver(FLYOVER_DRIVER)
	flyover.trove:Clean()
	local onComplete = flyover.options.onComplete
	if onComplete then
		task.spawn(onComplete, completed)
	end
	CameraController.FlyoverFinished:Fire(completed)
end

function CameraController.CancelFlyover()
	finishFlyover(false)
end

function CameraController.IsFlyoverPlaying(): boolean
	return cam.flyover ~= nil
end

function CameraController.PlayFlyover(points: { any }, duration: number, options: FlyoverOptions?): boolean
	if type(points) ~= "table" or #points == 0 then
		Log.warn("Camera", "PlayFlyover : aucun point")
		return false
	end
	if not isFiniteNumber(duration) or duration <= 0 then
		Log.warn("Camera", "PlayFlyover : durée invalide", duration)
		return false
	end
	local opts: FlyoverOptions = options or {}
	local lookAt = opts.lookAt

	local positions: { Vector3 } = {}
	for _, point in points do
		if typeof(point) == "CFrame" then
			table.insert(positions, (point :: CFrame).Position)
		elseif typeof(point) == "Vector3" then
			table.insert(positions, point :: Vector3)
		end
	end
	if #positions == 0 then
		Log.warn("Camera", "PlayFlyover : points invalides")
		return false
	end

	local rotations: { CFrame } = {}
	local validIndex = 0
	for _, point in points do
		if typeof(point) == "CFrame" then
			validIndex += 1
			table.insert(rotations, (point :: CFrame).Rotation)
		elseif typeof(point) == "Vector3" then
			validIndex += 1
			local position = point :: Vector3
			local focus: Vector3
			if lookAt then
				focus = lookAt
			elseif positions[validIndex + 1] then
				focus = positions[validIndex + 1]
			elseif validIndex > 1 then
				focus = position + (position - positions[validIndex - 1])
			else
				focus = position + Vector3.new(0, 0, -1)
			end
			if (focus - position).Magnitude < 1e-3 then
				focus = position + Vector3.new(0, 0, -1)
			end
			table.insert(rotations, CFrame.lookAt(position, focus).Rotation)
		end
	end

	local cumulative: { number } = { 0 }
	for index = 2, #positions do
		cumulative[index] = cumulative[index - 1] + (positions[index] - positions[index - 1]).Magnitude
	end

	-- Un nouveau survol remplace le précédent.
	finishFlyover(false)

	local flyover: Flyover = {
		positions = positions,
		rotations = rotations,
		cumulative = cumulative,
		totalLength = cumulative[#positions],
		duration = math.clamp(duration, 0.1, 60),
		startedAt = os.clock(),
		options = opts,
		trove = Trove.new(),
	}
	cam.flyover = flyover

	CameraController.PushDriver(FLYOVER_DRIVER, FLYOVER_PRIORITY, function(_dt: number, _current: CFrame): (CFrame?, Vector3?)
		if cam.flyover ~= flyover then
			return nil, nil
		end
		local progress = (os.clock() - flyover.startedAt) / flyover.duration
		if progress >= 1 then
			local final = sampleFlyover(flyover, 1)
			task.defer(function()
				if cam.flyover == flyover then
					finishFlyover(true)
				end
			end)
			return final, final.Position + final.LookVector * 10
		end
		local cframe = sampleFlyover(flyover, smoothstep(progress))
		return cframe, cframe.Position + cframe.LookVector * 10
	end)

	if opts.skippable ~= false then
		InputController.BindAtPriority(SKIP_ACTION, InputController.Priorities.Modal, function(inputState: Enum.UserInputState): boolean?
			if inputState == Enum.UserInputState.Begin and cam.flyover == flyover then
				CameraController.CancelFlyover()
			end
			return nil
		end, Enum.KeyCode.Space, Enum.KeyCode.Return, Enum.KeyCode.ButtonA)
		InputController.SetTouchButton(SKIP_ACTION, {
			text = Locale.t("controls.action.skip"),
			slot = "TopRight",
			indicator = true,
		})
		flyover.trove:Add(function()
			InputController.Unbind(SKIP_ACTION)
			InputController.SetTouchButton(SKIP_ACTION, nil)
		end)
	end

	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		flyover.trove:Connect(humanoid.Died, function()
			if cam.flyover == flyover then
				finishFlyover(false)
			end
		end)
	end
	return true
end

-- Survol par défaut : du green vers le départ, pour finir derrière le joueur en regardant le trou.
local function playDefaultIntro(gameStateFolder: Folder)
	local cup = gameStateFolder:GetAttribute("CupPosition")
	local root = getOwnRoot()
	if typeof(cup) ~= "Vector3" or not root then
		return
	end
	local cupPosition = cup :: Vector3
	local tee = root.Position
	local flat = Vector3.new(tee.X - cupPosition.X, 0, tee.Z - cupPosition.Z)
	local distance = flat.Magnitude
	if distance < 12 then
		return
	end
	local away = flat.Unit -- du trou vers le départ
	local side = Vector3.new(-away.Z, 0, away.X)
	local height = math.clamp(distance * 0.35, 25, 90)
	local middle = cupPosition:Lerp(tee, 0.5)

	local start = cupPosition - away * 25 + Vector3.new(0, height * 0.6, 0) + side * 8
	local over = middle + Vector3.new(0, height, 0) + side * math.clamp(distance * 0.15, 10, 40)
	local behind = CameraController.ClipPosition(tee + Vector3.new(0, 3, 0), tee + away * 22 + Vector3.new(0, 10, 0))

	local endsAt = gameStateFolder:GetAttribute("PhaseEndsAt")
	local duration = INTRO_MAX_DURATION
	if isFiniteNumber(endsAt) and (endsAt :: number) > 0 then
		duration = math.clamp((endsAt :: number) - Workspace:GetServerTimeNow() - 0.3, INTRO_MIN_DURATION, INTRO_MAX_DURATION)
	end
	CameraController.PlayFlyover({
		CFrame.lookAt(start, cupPosition),
		CFrame.lookAt(over, middle:Lerp(cupPosition, 0.4)),
		CFrame.lookAt(behind, tee:Lerp(cupPosition, 0.25)),
	}, duration, { skippable = true })
end

local function onPhaseChanged(gameStateFolder: Folder, phase: any)
	cam.introToken += 1
	local token = cam.introToken
	if phase == "HoleIntro" then
		task.delay(INTRO_AUTOSTART_DELAY, function()
			if cam.introToken ~= token or cam.flyover ~= nil then
				return
			end
			if gameStateFolder:GetAttribute("Phase") ~= "HoleIntro" then
				return
			end
			playDefaultIntro(gameStateFolder)
		end)
	else
		local flyover = cam.flyover
		if flyover and not flyover.options.keepAfterPhase then
			CameraController.CancelFlyover()
		end
	end
end

--------------------------------------------------------------------------------
-- Retour à la caméra par défaut
--------------------------------------------------------------------------------

function CameraController.Restore()
	CameraController.CancelFlyover()
	CameraController.Follow(nil)
	table.clear(shakes)
	local camera = Workspace.CurrentCamera
	if camera and #drivers == 0 then
		camera.FieldOfView = DEFAULT_FIELD_OF_VIEW
		local humanoid = getOwnHumanoid()
		if humanoid then
			humanoid.CameraOffset = Vector3.zero
		end
		applyDefaultCamera()
	end
end

--------------------------------------------------------------------------------
-- Boucle de rendu
--------------------------------------------------------------------------------

-- Avant la caméra par défaut : retire les effets posés à l'image précédente.
local function preCameraStep()
	local camera = Workspace.CurrentCamera
	local applied = cam.appliedCFrame
	local base = cam.baseCFrame
	cam.appliedCFrame = nil
	if camera and applied and base and camera.CFrame == applied then
		camera.CFrame = base
	end
end

-- Après la caméra par défaut : pilote éventuel, puis transition et secousse.
local function mainCameraStep(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local driver = topDriver()
	if driver then
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		cam.scripted = true
		cam.transitionFrom = nil
		local ok, cframe, focus = pcall(driver.update, dt, camera.CFrame)
		if not ok then
			Log.error("Camera", "pilote " .. driver.name .. " :", cframe)
			CameraController.PopDriver(driver.name)
		elseif typeof(cframe) == "CFrame" then
			camera.CFrame = cframe
			if typeof(focus) == "Vector3" then
				camera.Focus = CFrame.new(focus)
			end
		end
	elseif cam.scripted then
		-- Plus aucun pilote : la caméra par défaut reprend la main, avec une transition douce.
		cam.scripted = false
		cam.transitionFrom = camera.CFrame
		cam.transitionStartedAt = os.clock()
		cam.transitionDuration = RETURN_TRANSITION_TIME
		applyDefaultCamera()
	end

	local base = camera.CFrame
	local final = base
	local from = cam.transitionFrom
	if from and not driver then
		local progress = (os.clock() - cam.transitionStartedAt) / math.max(cam.transitionDuration, 1e-3)
		if progress >= 1 then
			cam.transitionFrom = nil
		else
			final = from:Lerp(base, smoothstep(progress))
		end
	end
	local offset = shakeOffset(os.clock())
	if offset then
		final = final * offset
	end
	cam.baseCFrame = base
	if final ~= base then
		camera.CFrame = final
		cam.appliedCFrame = final
	end
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function CameraController.Init()
	if cam.initialized then
		return
	end
	cam.initialized = true
	clipParams.FilterType = Enum.RaycastFilterType.Exclude
	clipParams.RespectCanCollide = true
	clipParams.IgnoreWater = true

	RunService:BindToRenderStep(RENDER_PRE, Enum.RenderPriority.Camera.Value - 1, preCameraStep)
	RunService:BindToRenderStep(RENDER_MAIN, Enum.RenderPriority.Camera.Value + 1, mainCameraStep)
	runtimeTrove:Add(function()
		RunService:UnbindFromRenderStep(RENDER_PRE)
		RunService:UnbindFromRenderStep(RENDER_MAIN)
	end)

	-- Règle de visibilité : un objet « caméra » (caméra drone de suivi / spectateur) ne doit jamais être visible par le
	-- joueur qu'il suit. Masqué localement (LocalTransparencyModifier = 1, émetteurs coupés) ; les autres joueurs le voient.
	local function isCameraProp(instance: Instance): boolean
		if not (instance:IsA("BasePart") or instance:IsA("Model")) then
			return false
		end
		local name = string.lower(instance.Name)
		return instance:GetAttribute("CameraProp") == true
			or string.find(name, "spectatorcamera", 1, true) ~= nil
			or string.find(name, "dronecamera", 1, true) ~= nil
			or string.find(name, "followcamera", 1, true) ~= nil
			or string.find(name, "camerarig", 1, true) ~= nil
	end
	local function hideFromSelf(instance: Instance)
		local watched = instance:GetAttribute("WatchedUserId")
		if watched ~= nil and watched ~= localPlayer.UserId then
			return -- suit quelqu'un d'autre : visible pour nous
		end
		local targets: { Instance } = { instance }
		for _, descendant in instance:GetDescendants() do
			table.insert(targets, descendant)
		end
		for _, item in targets do
			if item:IsA("BasePart") then
				item.LocalTransparencyModifier = 1
				runtimeTrove:Connect(item:GetPropertyChangedSignal("LocalTransparencyModifier"), function()
					if item.LocalTransparencyModifier ~= 1 then
						item.LocalTransparencyModifier = 1
					end
				end)
			elseif item:IsA("Decal") then
				item.Transparency = 1
			elseif item:IsA("ParticleEmitter") or item:IsA("Trail") or item:IsA("Beam") then
				(item :: any).Enabled = false
			end
		end
	end
	local function scanOwnCameraProps(root: Instance)
		for _, descendant in root:GetDescendants() do
			if isCameraProp(descendant) then
				hideFromSelf(descendant)
			end
		end
		runtimeTrove:Connect(root.DescendantAdded, function(descendant: Instance)
			if isCameraProp(descendant) then
				task.defer(hideFromSelf, descendant)
			end
		end)
	end
	scanOwnCameraProps(Workspace)

	local function onCharacterAdded(character: Model)
		-- Le moteur remet CameraSubject sur le nouvel humanoïde : on réapplique le suivi éventuel.
		task.defer(function()
			if localPlayer.Character ~= character then
				return
			end
			local camera = Workspace.CurrentCamera
			if camera then
				camera.FieldOfView = DEFAULT_FIELD_OF_VIEW
			end
			applyDefaultCamera()
		end)
	end
	runtimeTrove:Connect(localPlayer.CharacterAdded, onCharacterAdded)
	local currentCharacter = localPlayer.Character
	if currentCharacter then
		onCharacterAdded(currentCharacter)
	end
end

function CameraController.Start()
	local ok, folder = pcall(GameState.get)
	if not ok or typeof(folder) ~= "Instance" then
		Log.warn("Camera", "GameState indisponible : pas de survol d'intro automatique")
		return
	end
	local gameStateFolder = folder :: Folder
	runtimeTrove:Connect(gameStateFolder:GetAttributeChangedSignal("Phase"), function()
		onPhaseChanged(gameStateFolder, gameStateFolder:GetAttribute("Phase"))
	end)
	if gameStateFolder:GetAttribute("Phase") == "HoleIntro" then
		onPhaseChanged(gameStateFolder, "HoleIntro")
	end
end

return CameraController
