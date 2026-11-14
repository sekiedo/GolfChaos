--[[
	StarterPlayer/StarterPlayerScripts/Controllers/AimController  (ModuleScript)
	----------------------------------------------------------------------------
	Mode visée côté client : détection de proximité, caméra orbitale autour de la balle,
	flèche directionnelle 3D (Beams), jauge de puissance oscillante, envoi des intentions au serveur.

	Machine à états :  Idle -> Aiming -> Charging -> Following -> Idle

	  Idle      avatar libre. Dès qu'on est à portée de SA balle immobile : Aiming (auto) ou touche E.
	  Aiming    caméra orbitale, flèche. Clic droit + glisser / glisser tactile / stick droit : orienter.
	            Molette, R/F, croix directionnelle : angle de frappe. Espace / clic / bouton : lance la jauge.
	  Charging  la jauge oscille. Un 2e appui frappe. Q : retour à la visée.
	  Following caméra qui suit la balle jusqu'à son arrêt (ou dès que le joueur bouge).

	Rien ici n'est autoritaire : le serveur revalide tout (BallService).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local player = Players.LocalPlayer

local AimController = {}

local REASON_TEXT = {
	horn = "La corne de brume t'a déconcentré !",
	unavailable = "Tu ne peux pas frapper pour le moment.",
	stun = "Tu es étourdi !",
}

local ACTION_SWING = "GolfSwing"
local ACTION_CANCEL = "GolfCancel"
local ACTION_LOFT_UP = "GolfLoftUp"
local ACTION_LOFT_DOWN = "GolfLoftDown"

local mode = "Idle"
local ballsFolder, ball, highlight, ui, arrow
local ballPollTimer = 0
local yaw = 0
local pitch = math.rad(Config.Aim.DefaultPitchDeg)
local loft = Config.Shot.DefaultLoft
local chargeStart = 0
local followStart = 0
local followSawMoving = false
local aimBlockedUntil = 0
local suppressUntilLeave = false
local canAimNow = false
local rightMouseDown = false
local cameraCFrame = CFrame.new()

local cameraParams = RaycastParams.new()
cameraParams.FilterType = Enum.RaycastFilterType.Exclude
cameraParams.RespectCanCollide = true

local function now()
	return workspace:GetServerTimeNow()
end

local function getCharacterParts()
	local character = player.Character
	if not character then
		return nil, nil
	end
	return character:FindFirstChild("HumanoidRootPart"), character:FindFirstChildOfClass("Humanoid")
end

--------------------------------------------------------------------------------
-- Flèche 3D : deux Beams (tige + pointe triangulaire) portés par une Part invisible locale
--------------------------------------------------------------------------------

local function createArrow()
	local part = Instance.new("Part")
	part.Name = "GolfAimArrow"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Parent = workspace.CurrentCamera

	local a0 = Instance.new("Attachment")
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Parent = part
	local a2 = Instance.new("Attachment")
	a2.Parent = part

	local function makeBeam(from, to, width0, width1)
		local beam = Instance.new("Beam")
		beam.Attachment0 = from
		beam.Attachment1 = to
		beam.Width0 = width0
		beam.Width1 = width1
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Segments = 1
		beam.Transparency = NumberSequence.new(0.1)
		beam.Enabled = false
		beam.Parent = part
		return beam
	end
	local shaft = makeBeam(a0, a1, 0.55, 0.55)
	local head = makeBeam(a1, a2, 2.0, 0)

	local api = {}

	function api.SetVisible(visible)
		shaft.Enabled = visible
		head.Enabled = visible
	end

	function api.Update(origin, direction, power)
		local length = Config.Aim.ArrowMinLength + (Config.Aim.ArrowMaxLength - Config.Aim.ArrowMinLength) * power
		part.CFrame = CFrame.new(origin + Vector3.new(0, -Config.Ball.Diameter / 2 + 0.2, 0))
		a0.Position = Vector3.zero
		a1.Position = direction * length
		a2.Position = direction * (length + Config.Aim.ArrowHeadLength)
		local color = ColorSequence.new(Color3.fromHSV(0.33 * (1 - power), 0.85, 1))
		shaft.Color = color
		head.Color = color
	end

	function api.Destroy()
		part:Destroy()
	end

	return api
end

--------------------------------------------------------------------------------
-- Balle du joueur local
--------------------------------------------------------------------------------

local function refreshBall(dt)
	if ball and ball.Parent then
		return
	end
	if ball then
		ball = nil
		if highlight then
			highlight:Destroy()
			highlight = nil
		end
	end

	ballPollTimer -= dt
	if ballPollTimer > 0 then
		return
	end
	ballPollTimer = 0.5

	for _, candidate in ballsFolder:GetChildren() do
		if candidate:GetAttribute("OwnerUserId") == player.UserId then
			ball = candidate
			-- Contour visible à travers les murs : on retrouve toujours sa balle.
			highlight = Instance.new("Highlight")
			highlight.Adornee = ball
			highlight.FillTransparency = 1
			highlight.OutlineColor = Color3.fromRGB(255, 220, 0)
			highlight.OutlineTransparency = 0.2
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.Parent = ball
			break
		end
	end
end

--------------------------------------------------------------------------------
-- Caméra
--------------------------------------------------------------------------------

local function restoreCamera()
	local camera = workspace.CurrentCamera
	local _, humanoid = getCharacterParts()
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

local function clipCamera(focus, desiredPosition)
	local filter = { ballsFolder }
	if player.Character then
		table.insert(filter, player.Character)
	end
	cameraParams.FilterDescendantsInstances = filter

	local offset = desiredPosition - focus
	local result = workspace:Raycast(focus, offset, cameraParams)
	if result then
		return result.Position + result.Normal * 0.5
	end
	return desiredPosition
end

local function updateAimCamera(dt)
	local camera = workspace.CurrentCamera
	local focus = ball.Position + Vector3.new(0, Config.Aim.FocusHeight, 0)
	local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(-pitch, 0, 0)
	local desired = focus + rotation * Vector3.new(0, 0, Config.Aim.CameraDistance)
	local target = CFrame.lookAt(clipCamera(focus, desired), focus)

	cameraCFrame = cameraCFrame:Lerp(target, 1 - math.exp(-Config.Aim.CameraSmoothing * dt))
	camera.CFrame = cameraCFrame
	camera.Focus = CFrame.new(focus)
end

local function updateFollowCamera(dt)
	local camera = workspace.CurrentCamera
	local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(-math.rad(Config.Aim.FollowPitchDeg), 0, 0)
	local desired = ball.Position + rotation * Vector3.new(0, 0, Config.Aim.FollowDistance)
	local target = CFrame.lookAt(clipCamera(ball.Position, desired), ball.Position)

	cameraCFrame = cameraCFrame:Lerp(target, 1 - math.exp(-Config.Aim.FollowSmoothing * dt))
	camera.CFrame = cameraCFrame
	camera.Focus = CFrame.new(ball.Position)
end

--------------------------------------------------------------------------------
-- Entrées (actions liées uniquement pendant la visée pour ne pas gêner le reste du jeu)
--------------------------------------------------------------------------------

local function changeLoft(delta)
	loft = math.clamp(loft + delta, Config.Shot.MinLoft, Config.Shot.MaxLoft)
	ui:SetLoft(loft)
end

local function rotate(deltaX, deltaY, sensitivity)
	yaw -= deltaX * sensitivity
	pitch = math.clamp(pitch + deltaY * sensitivity, math.rad(Config.Aim.MinPitchDeg), math.rad(Config.Aim.MaxPitchDeg))
end

local function releaseMouse()
	rightMouseDown = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

local function unbindAimActions()
	ContextActionService:UnbindAction(ACTION_SWING)
	ContextActionService:UnbindAction(ACTION_CANCEL)
	ContextActionService:UnbindAction(ACTION_LOFT_UP)
	ContextActionService:UnbindAction(ACTION_LOFT_DOWN)
end

local function exitAim(notifyServer, blockSeconds)
	if mode ~= "Aiming" and mode ~= "Charging" then
		return
	end
	mode = "Idle"
	unbindAimActions()
	releaseMouse()
	arrow.SetVisible(false)
	ui:SetVisible(false)
	ui:SetCharging(false)
	restoreCamera()

	local _, humanoid = getCharacterParts()
	if humanoid then
		humanoid.AutoRotate = true
	end
	if notifyServer then
		Net.Get("AimState"):FireServer(false)
	end
	aimBlockedUntil = now() + (blockSeconds or 0)
end

local function beginFollow()
	mode = "Following"
	followStart = now()
	followSawMoving = false
	unbindAimActions()
	releaseMouse()
	arrow.SetVisible(false)
	ui:SetVisible(false)
	ui:SetCharging(false)

	local _, humanoid = getCharacterParts()
	if humanoid then
		humanoid.AutoRotate = true
	end
end

local function exitFollow()
	if mode ~= "Following" then
		return
	end
	mode = "Idle"
	restoreCamera()
end

local function handleSwing()
	if mode == "Aiming" then
		mode = "Charging"
		chargeStart = now()
		ui:SetCharging(true)
		Net.Get("SwingStart"):FireServer()
	elseif mode == "Charging" then
		local power = Config.PowerAtTime(now() - chargeStart)
		local direction = CFrame.Angles(0, yaw, 0).LookVector
		Net.Get("Shoot"):FireServer(direction, loft, power)
		-- Retour visuel immédiat (masque la latence) : le serveur reste maître du résultat.
		beginFollow()
	end
end

local function handleCancel()
	if mode == "Charging" then
		mode = "Aiming"
		ui:SetCharging(false)
		Net.Get("SwingStart"):FireServer() -- invalide l'ancien chrono côté serveur
	elseif mode == "Aiming" then
		suppressUntilLeave = true
		exitAim(true)
	end
end

local function bindAimActions()
	local high = Enum.ContextActionPriority.High.Value

	ContextActionService:BindActionAtPriority(ACTION_SWING, function(_, state)
		if state == Enum.UserInputState.Begin then
			handleSwing()
		end
		return Enum.ContextActionResult.Sink
	end, false, high, Enum.KeyCode.Space, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonA)

	ContextActionService:BindActionAtPriority(ACTION_CANCEL, function(_, state)
		if state == Enum.UserInputState.Begin then
			handleCancel()
		end
		return Enum.ContextActionResult.Sink
	end, false, high, Enum.KeyCode.Q, Enum.KeyCode.ButtonB)

	ContextActionService:BindActionAtPriority(ACTION_LOFT_UP, function(_, state)
		if state == Enum.UserInputState.Begin then
			changeLoft(Config.Shot.LoftStep)
		end
		return Enum.ContextActionResult.Sink
	end, false, high, Enum.KeyCode.R, Enum.KeyCode.DPadUp)

	ContextActionService:BindActionAtPriority(ACTION_LOFT_DOWN, function(_, state)
		if state == Enum.UserInputState.Begin then
			changeLoft(-Config.Shot.LoftStep)
		end
		return Enum.ContextActionResult.Sink
	end, false, high, Enum.KeyCode.F, Enum.KeyCode.DPadDown)
end

local function stepGamepad(dt)
	if not UserInputService.GamepadEnabled then
		return
	end
	for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local stick = input.Position
			if stick.Magnitude > 0.2 then
				yaw -= stick.X * Config.Aim.StickSpeed * dt
				pitch = math.clamp(
					pitch - stick.Y * Config.Aim.StickSpeed * 0.5 * dt,
					math.rad(Config.Aim.MinPitchDeg),
					math.rad(Config.Aim.MaxPitchDeg)
				)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Entrée / sortie du mode visée
--------------------------------------------------------------------------------

local function enterAim(root, humanoid)
	if mode ~= "Idle" then
		return
	end
	mode = "Aiming"
	suppressUntilLeave = false

	-- Cap initial : vers le trou si le GameManager (étape 2) publie Workspace:SetAttribute("HolePosition", Vector3)
	local toward
	local holePosition = workspace:GetAttribute("HolePosition")
	if typeof(holePosition) == "Vector3" then
		toward = holePosition - ball.Position
	else
		toward = root.CFrame.LookVector
	end
	toward = Vector3.new(toward.X, 0, toward.Z)
	if toward.Magnitude < 0.1 then
		toward = Vector3.new(0, 0, -1)
	end
	toward = toward.Unit
	yaw = math.atan2(-toward.X, -toward.Z)
	pitch = math.rad(Config.Aim.DefaultPitchDeg)
	loft = Config.Shot.DefaultLoft

	local camera = workspace.CurrentCamera
	cameraCFrame = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	humanoid.AutoRotate = false

	bindAimActions()
	ui:SetPrompt(nil)
	ui:SetLoft(loft)
	ui:SetCharging(false)
	ui:SetVisible(true)
	arrow.SetVisible(true)

	Net.Get("AimState"):FireServer(true)
end

--------------------------------------------------------------------------------
-- Boucle de rendu
--------------------------------------------------------------------------------

local function onRender(dt)
	refreshBall(dt)

	local root, humanoid = getCharacterParts()
	if not (ball and ball.Parent and root and humanoid and humanoid.Health > 0) then
		canAimNow = false
		if mode == "Aiming" or mode == "Charging" then
			exitAim(true)
		elseif mode == "Following" then
			exitFollow()
		end
		return
	end

	local state = ball:GetAttribute("State")
	local stunned = player:GetAttribute("Stunned") == true
	local distance = (root.Position - ball.Position).Magnitude
	if highlight then
		highlight.Enabled = state ~= "Holed"
	end

	if mode == "Idle" then
		canAimNow = state == "Resting" and not stunned and distance <= Config.Shot.AimEnterDistance and now() >= aimBlockedUntil
		if distance > Config.Shot.AimExitDistance then
			suppressUntilLeave = false
		end

		if canAimNow and not suppressUntilLeave then
			if Config.Aim.AutoEnter then
				enterAim(root, humanoid)
			else
				ui:SetPrompt("Appuie sur E pour viser")
			end
		else
			ui:SetPrompt(nil)
		end
	elseif mode == "Aiming" or mode == "Charging" then
		if stunned or state ~= "Resting" or distance > Config.Shot.AimExitDistance then
			exitAim(true, 1)
			return
		end
		stepGamepad(dt)

		local direction = CFrame.Angles(0, yaw, 0).LookVector
		local power = Config.Aim.IdleArrowPower
		if mode == "Charging" then
			power = Config.PowerAtTime(now() - chargeStart)
			ui:SetPower(power)
		end

		-- L'avatar se tourne vers la cible (purement visuel).
		local rootPosition = root.Position
		root.CFrame = root.CFrame:Lerp(CFrame.lookAt(rootPosition, rootPosition + direction), 1 - math.exp(-10 * dt))

		updateAimCamera(dt)
		arrow.Update(ball.Position, direction, power)
	elseif mode == "Following" then
		local elapsed = now() - followStart
		if state == "Moving" then
			followSawMoving = true
		end
		local playerWantsControl = humanoid.MoveDirection.Magnitude > 0.1 and elapsed > 0.4
		local ballDone = (followSawMoving and state ~= "Moving") or (not followSawMoving and elapsed > Config.Aim.FollowStartTimeout)
		if stunned or playerWantsControl or ballDone or elapsed > Config.Aim.FollowMaxTime then
			exitFollow()
			return
		end
		updateFollowCamera(dt)
	end
end

--------------------------------------------------------------------------------
-- Initialisation
--------------------------------------------------------------------------------

function AimController.Init()
	local screenGui = player:WaitForChild("PlayerGui"):WaitForChild("AimGui")
	local PowerMeter = require(screenGui:WaitForChild("PowerMeter"))
	ui = PowerMeter.new(screenGui)
	ballsFolder = workspace:WaitForChild("Balls")
	arrow = createArrow()

	ui.SwingActivated.Event:Connect(handleSwing)
	ui.CancelActivated.Event:Connect(handleCancel)

	-- Annulation décidée par le serveur (étourdissement, corne de brume, tir refusé...)
	Net.Get("AimCancelled").OnClientEvent:Connect(function(reason)
		if mode == "Aiming" or mode == "Charging" then
			exitAim(false, if reason == "horn" then 3 else 1)
		elseif mode == "Following" then
			exitFollow()
		end
		local text = REASON_TEXT[reason]
		if text then
			ui:ShowToast(text, "warn")
		end
	end)

	Net.Get("Notify").OnClientEvent:Connect(function(text, kind)
		if typeof(text) == "string" then
			ui:ShowToast(text, if typeof(kind) == "string" then kind else "info")
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 and (mode == "Aiming" or mode == "Charging") then
			rightMouseDown = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		elseif input.KeyCode == Enum.KeyCode.E and mode == "Idle" and canAimNow then
			local root, humanoid = getCharacterParts()
			if root and humanoid then
				enterAim(root, humanoid)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and rightMouseDown then
			releaseMouse()
		end
	end)

	UserInputService.InputChanged:Connect(function(input, processed)
		if mode ~= "Aiming" and mode ~= "Charging" then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			if rightMouseDown then
				rotate(input.Delta.X, input.Delta.Y, Config.Aim.MouseSensitivity)
			end
		elseif input.UserInputType == Enum.UserInputType.Touch then
			if not processed then
				rotate(input.Delta.X, input.Delta.Y, Config.Aim.TouchSensitivity)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			if not processed then
				changeLoft(input.Position.Z * Config.Shot.LoftStep)
			end
		end
	end)

	-- Priorité Camera + 1 : on s'exécute après le script de caméra par défaut.
	RunService:BindToRenderStep("GolfAim", Enum.RenderPriority.Camera.Value + 1, onRender)
end

return AimController
