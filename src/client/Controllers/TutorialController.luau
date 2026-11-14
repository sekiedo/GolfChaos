--!strict
--[[
	TutorialController — tutoriel rapide par points lumineux blancs dans le décor 3D (priorité 90).

	  - Aucune flèche, aucun trait de guidage : orbes blancs (Neon + PointLight + anneau pulsant) à hauteur
	    du regard, avec étiquette « TUTO » + 1 phrase (BillboardGui).
	  - Accueil : avancer, Boutique, Personnaliser, Jouer. Golf : viser, objets.
	  - Validation automatique (proximité ou action) : son cristallin, l'orbe s'efface, le suivant s'active.
	    Bouton discret « Passer le tuto ». Fin ou saut -> Tutorial.Complete (profil serveur).
	  - Ne démarre que si profile.tutorialDone est faux.

	API : IsActive() -> boolean   Skip()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameState = require(Shared.Util.GameState)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)

local TutorialController = {}
TutorialController.Priority = 90

local localPlayer = Players.LocalPlayer
local PING = "rbxasset://sounds/electronicpingshort.wav"
local ORB_COLOR = Color3.fromRGB(255, 252, 244)
local EYE_HEIGHT = 5

type Step = {
	text: string,
	reach: number,
	scope: string,
	target: () -> Vector3?,
	done: (() -> boolean)?,
}

local steps: { Step } = {}
local index = 0
local active = false
local connection: RBXScriptConnection? = nil
local orb: Part? = nil
local ring: Part? = nil
local bornAt = 0
local startPosition: Vector3? = nil
local skipGui: ScreenGui? = nil
local usedItem = false
local wasHolding = false

local function controller(name: string): any?
	local module = script.Parent:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
	end
	return nil
end

local function phaseName(): string
	local ok, folder = pcall(GameState.get)
	if ok and typeof(folder) == "Instance" then
		local value = (folder :: Folder):GetAttribute("Phase")
		if type(value) == "string" then
			return value
		end
	end
	return "Lobby"
end

local function rootPart(): BasePart?
	local character = localPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function standPosition(kiosk: string): Vector3?
	local lobby = Workspace:FindFirstChild("Lobby")
	local stands = lobby and lobby:FindFirstChild("Stands")
	local stand = stands and stands:FindFirstChild("Stand_" .. kiosk)
	if stand and stand:IsA("Model") then
		return stand:GetPivot().Position
	end
	return nil
end

local function ballPosition(): Vector3?
	local aim = controller("GolfAimController")
	local ball = aim and aim.GetBall()
	return if ball then ball.Position else nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local function buildSteps()
	steps = {
		{
			text = "tutorial.step.move",
			reach = 6,
			scope = "lobby",
			target = function()
				local root = rootPart()
				if not startPosition and root then
					local look = root.CFrame.LookVector
					local flat = Vector3.new(look.X, 0, look.Z)
					startPosition = root.Position + (if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis) * 14
				end
				return startPosition
			end,
		},
		{ text = "tutorial.step.shop", reach = 11, scope = "lobby", target = function() return standPosition("shop") end },
		{ text = "tutorial.step.customize", reach = 11, scope = "lobby", target = function() return standPosition("customize") end },
		{ text = "tutorial.step.play", reach = 11, scope = "lobby", target = function() return standPosition("play") end },
		{
			text = "tutorial.step.aim",
			reach = 0,
			scope = "golf",
			target = ballPosition,
			done = function()
				local aim = controller("GolfAimController")
				local state = aim and aim.GetState()
				return state == "Aiming" or state == "Charging" or state == "Following"
			end,
		},
		{
			text = "tutorial.step.items",
			reach = 0,
			scope = "golf",
			target = function()
				local root = rootPart()
				return ballPosition() or (if root then root.Position else nil)
			end,
			done = function()
				return usedItem
			end,
		},
	}
end

local function clearOrb()
	if orb then
		orb:Destroy()
		orb = nil
	end
	if ring then
		ring:Destroy()
		ring = nil
	end
end

local function chime()
	local sound = Instance.new("Sound")
	sound.SoundId = PING
	sound.Volume = 0.5
	sound.PlaybackSpeed = 1.5
	sound.Parent = Workspace
	sound:Play()
	task.delay(2, function()
		sound:Destroy()
	end)
end

local function finish()
	if not active then
		return
	end
	active = false
	clearOrb()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if skipGui then
		skipGui:Destroy()
		skipGui = nil
	end
	pcall(Net.send, "Tutorial.Complete")
end

local function glowPart(name: string, shape: Enum.PartType, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = ORB_COLOR
	p.Parent = Workspace
	return p
end

local function spawnOrb(current: Step)
	clearOrb()
	local p = glowPart("TutoPoint", Enum.PartType.Ball, Vector3.one * 1.6)
	local light = Instance.new("PointLight")
	light.Color = ORB_COLOR
	light.Range = 14
	light.Brightness = 1.6
	light.Parent = p
	local halo = glowPart("TutoAnneau", Enum.PartType.Cylinder, Vector3.new(0.12, 2.4, 2.4))
	halo.Transparency = 0.5

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(280, 92)
	billboard.StudsOffset = Vector3.new(0, 3.4, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 140
	billboard.Parent = p
	local card = Instance.new("Frame")
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Color3.fromRGB(24, 28, 40)
	card.BackgroundTransparency = 0.15
	card.BorderSizePixel = 0
	card.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = card
	local badge = Instance.new("TextLabel")
	badge.Size = UDim2.fromOffset(70, 20)
	badge.Position = UDim2.fromOffset(12, 10)
	badge.BackgroundColor3 = ORB_COLOR
	badge.TextColor3 = Color3.fromRGB(24, 28, 40)
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 12
	badge.Text = Locale.t("tutorial.badge")
	badge.Parent = card
	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(1, 0)
	badgeCorner.Parent = badge
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -24, 1, -38)
	label.Position = UDim2.fromOffset(12, 34)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 16
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = Locale.t(current.text)
	label.Parent = card
	orb = p
	ring = halo
	bornAt = os.clock()
end

local function buildSkipButton()
	local screen = Instance.new("ScreenGui")
	screen.Name = "TutorialSkip"
	screen.ResetOnSpawn = false
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(132, 28)
	button.AnchorPoint = Vector2.new(0, 1)
	button.Position = UDim2.new(0, 16, 1, -16)
	button.BackgroundColor3 = Color3.fromRGB(24, 28, 40)
	button.BackgroundTransparency = 0.45
	button.TextColor3 = Color3.fromRGB(235, 238, 245)
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 13
	button.Text = Locale.t("tutorial.skip")
	button.Parent = screen
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	button.Activated:Connect(finish)
	screen.Parent = localPlayer:WaitForChild("PlayerGui")
	skipGui = screen
end

local function tick()
	if not active then
		return
	end
	local inventory = controller("InventoryController")
	local holding = inventory ~= nil and inventory.IsHolding() == true
	if wasHolding and not holding then
		usedItem = true
	end
	wasHolding = holding

	local current = steps[index]
	if not current then
		return
	end
	local inLobby = phaseName() == "Lobby"
	local aim = controller("GolfAimController")
	local practicing = aim ~= nil and aim.IsPractice() == true
	local inGolf = not inLobby or practicing
	if current.scope == "lobby" and inGolf then
		clearOrb()
		index += 1 -- étape d'accueil devenue sans objet
		return
	end
	if current.scope == "golf" and not inGolf then
		clearOrb()
		return
	end
	local target = current.target()
	if not target then
		clearOrb()
		return
	end
	if not orb or not ring then
		spawnOrb(current)
	end
	local t = os.clock() - bornAt
	local position = target + Vector3.new(0, EYE_HEIGHT + math.sin(t * 2.4) * 0.35, 0)
	if orb and ring then
		orb.Position = position
		orb.Size = Vector3.one * (1.5 + math.sin(t * 4) * 0.12)
		local pulse = (t * 0.9) % 1
		ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
		ring.Size = Vector3.new(0.12, 2.2 + pulse * 4.5, 2.2 + pulse * 4.5)
		ring.Transparency = 0.4 + pulse * 0.6
	end
	local root = rootPart()
	local completed = false
	if current.done then
		completed = current.done()
	elseif root then
		completed = flatDistance(root.Position, target) <= current.reach
	end
	if completed then
		chime()
		clearOrb()
		index += 1
		if index > #steps then
			finish()
		end
	end
end

function TutorialController.IsActive(): boolean
	return active
end

function TutorialController.Skip()
	finish()
end

function TutorialController.Init() end

function TutorialController.Start()
	local profile = controller("ProfileController")
	local deadline = os.clock() + 15
	local snapshot: { [string]: any } = if profile then profile.Get() else {}
	while profile and next(snapshot) == nil and os.clock() < deadline do
		task.wait(0.5)
		snapshot = profile.Get()
	end
	if snapshot.tutorialDone == true then
		return
	end
	buildSteps()
	index = 1
	active = true
	buildSkipButton()
	connection = RunService.Heartbeat:Connect(tick)
end

return TutorialController
