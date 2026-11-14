--!strict
--[[
	Effets de base partagés (registre EffectsController). Purement visuels et locaux, construits par code
	avec les textures de particules intégrées au moteur (aucun asset uploadé).

	  Splash { position }                       éclaboussure (eau)
	  SandPuff { position }                     nuage de sable
	  HitSpark { position, color? }             étincelles d'impact
	  Explosion { position, radius? }           explosion cartoon + onde de choc
	  Ring { position, radius, duration, color?, pulse? }   anneau d'annonce au sol (télégraphie lisible)
	  Beam { from, to, duration?, color?, width? }          rayon (laser, rail)
	  KOStars { position, duration? }           étoiles au-dessus d'un joueur KO
	  Confetti { position }                     célébration par défaut à l'entrée dans le trou
	  FloatingText { position, text, color? }   texte flottant court ("KO !", "+1")
	  ScreenFlash { color?, duration? }         flash plein écran ; en mode sans flash : vignette sombre + icône
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local EXPLOSION_CORE = "rbxasset://textures/particles/explosion01_core_main.dds"
local SHOCKWAVE = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local SQUARE = "rbxasset://textures/particles/SquareParticle.png"

local function seq(...: Color3): ColorSequence
	local colors = { ... }
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local points = {}
	for index, color in colors do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(points)
end

local function groundDisc(api: any, position: Vector3, radius: number, color: Color3, transparency: number): Part
	local disc = Instance.new("Part")
	disc.Name = "Anneau"
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.Neon
	disc.Color = color
	disc.Transparency = transparency
	disc.Size = Vector3.new(0.15, radius * 2, radius * 2)
	disc.CFrame = CFrame.new(position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
	disc.Parent = api.folder()
	return disc
end

local Core = {}

Core.Splash = function(params, api)
	local position = params.position
	if typeof(position) ~= "Vector3" then
		return
	end
	local anchor = api.anchorAt(position)
	api.emit(anchor, {
		texture = SPARKLES,
		color = seq(Color3.fromRGB(200, 240, 255), Color3.fromRGB(80, 170, 255)),
		size = NumberSequence.new(0.8, 0.1),
		speed = NumberRange.new(10, 22),
		spread = Vector2.new(35, 35),
		acceleration = Vector3.new(0, -60, 0),
		lifetime = NumberRange.new(0.5, 0.9),
	}, 40)
	api.debris(anchor, 2)
	api.sound("splash_water", { position = position })
end

Core.SandPuff = function(params, api)
	local position = params.position
	if typeof(position) ~= "Vector3" then
		return
	end
	local anchor = api.anchorAt(position)
	api.emit(anchor, {
		texture = SMOKE,
		color = seq(Color3.fromRGB(235, 210, 150)),
		size = NumberSequence.new(1.2, 2.6),
		transparency = NumberSequence.new(0.3, 1),
		speed = NumberRange.new(3, 7),
		spread = Vector2.new(70, 70),
		lifetime = NumberRange.new(0.6, 1.1),
		drag = 3,
	}, 14)
	api.debris(anchor, 2)
end

Core.HitSpark = function(params, api)
	local position = params.position
	if typeof(position) ~= "Vector3" then
		return
	end
	local color = if typeof(params.color) == "Color3" then params.color else Color3.fromRGB(255, 230, 120)
	local anchor = api.anchorAt(position)
	api.emit(anchor, {
		texture = SPARKLES,
		color = seq(color),
		size = NumberSequence.new(0.7, 0),
		speed = NumberRange.new(14, 26),
		lifetime = NumberRange.new(0.25, 0.45),
		lightEmission = 0.8,
	}, 18)
	api.debris(anchor, 1.5)
end

Core.Explosion = function(params, api)
	local position = params.position
	if typeof(position) ~= "Vector3" then
		return
	end
	local radius = if type(params.radius) == "number" then params.radius else 8
	local anchor = api.anchorAt(position)
	api.emit(anchor, {
		texture = EXPLOSION_CORE,
		color = seq(Color3.fromRGB(255, 240, 160), Color3.fromRGB(255, 120, 40)),
		size = NumberSequence.new(radius * 0.5, radius * 0.9),
		transparency = NumberSequence.new(0, 1),
		speed = NumberRange.new(2, 6),
		lifetime = NumberRange.new(0.35, 0.6),
		lightEmission = 0.7,
	}, 10)
	api.emit(anchor, {
		texture = SMOKE,
		color = seq(Color3.fromRGB(90, 90, 100)),
		size = NumberSequence.new(radius * 0.4, radius * 0.8),
		transparency = NumberSequence.new(0.2, 1),
		speed = NumberRange.new(4, 10),
		lifetime = NumberRange.new(0.8, 1.4),
		drag = 2,
	}, 12)
	api.emit(anchor, {
		texture = SHOCKWAVE,
		color = seq(Color3.fromRGB(255, 255, 255)),
		size = NumberSequence.new(1, radius * 2.2),
		transparency = NumberSequence.new(0.2, 1),
		speed = NumberRange.new(0, 0),
		lifetime = NumberRange.new(0.35, 0.35),
		spread = Vector2.new(0, 0),
	}, 1)
	api.debris(anchor, 3)
end

Core.Ring = function(params, api)
	local position = params.position
	if typeof(position) ~= "Vector3" then
		return
	end
	local radius = if type(params.radius) == "number" then params.radius else 6
	local duration = if type(params.duration) == "number" then params.duration else 1
	local color = if typeof(params.color) == "Color3" then params.color else Color3.fromRGB(255, 70, 70)
	local disc = groundDisc(api, position, radius, color, 0.55)
	local inner = groundDisc(api, position, radius * 0.08, Color3.new(1, 1, 1), 0.3)
	if params.pulse ~= false and not api.isReduced() then
		TweenService:Create(disc, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.8 }):Play()
	end
	api.debris(disc, duration)
	api.debris(inner, duration)
end

Core.Beam = function(params, api)
	local from, to = params.from, params.to
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	local duration = if type(params.duration) == "number" then params.duration else 0.35
	local color = if typeof(params.color) == "Color3" then params.color else Color3.fromRGB(120, 255, 240)
	local width = if type(params.width) == "number" then params.width else 1.2
	local a0, a1 = api.anchorAt(from), api.anchorAt(to)
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = width
	beam.Width1 = width
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(0.05)
	beam.Segments = 1
	beam.Parent = a0
	TweenService:Create(beam, TweenInfo.new(duration), { Width0 = 0, Width1 = 0 }):Play()
	api.debris(a0, duration + 0.1)
	api.debris(a1, duration + 0.1)
end

Core.KOStars = function(params, api)
	local position = params.position
	if typeof(position) ~= "Vector3" then
		return
	end
	local duration = if type(params.duration) == "number" then params.duration else 2
	local anchor = api.anchorAt(position + Vector3.new(0, 3, 0))
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLES
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 230, 80))
	emitter.Size = NumberSequence.new(0.5)
	emitter.Lifetime = NumberRange.new(0.6)
	emitter.Speed = NumberRange.new(2)
	emitter.SpreadAngle = Vector2.new(0, 180)
	emitter.Rate = if api.isReduced() then 4 else 12
	emitter.LightEmission = 0.6
	emitter.Parent = anchor
	api.debris(anchor, duration)
end

Core.Confetti = function(params, api)
	local position = params.position
	if typeof(position) ~= "Vector3" then
		return
	end
	local anchor = api.anchorAt(position + Vector3.new(0, 1, 0))
	api.emit(anchor, {
		texture = SQUARE,
		color = seq(Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 220, 60), Color3.fromRGB(80, 200, 255), Color3.fromRGB(120, 230, 120)),
		size = NumberSequence.new(0.35, 0.25),
		transparency = NumberSequence.new(0, 0.6),
		speed = NumberRange.new(18, 30),
		spread = Vector2.new(30, 30),
		acceleration = Vector3.new(0, -40, 0),
		lifetime = NumberRange.new(1.2, 2),
		rotSpeed = NumberRange.new(-300, 300),
		drag = 1.5,
	}, 60)
	api.debris(anchor, 3)
end

Core.FloatingText = function(params, api)
	local position = params.position
	if typeof(position) ~= "Vector3" or type(params.text) ~= "string" then
		return
	end
	local anchor = api.anchorAt(position + Vector3.new(0, 3, 0))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 60)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = params.text
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
	label.TextColor3 = if typeof(params.color) == "Color3" then params.color else Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	gui.Parent = anchor
	if not api.isReduced() then
		TweenService:Create(anchor, TweenInfo.new(1.2), { WorldPosition = anchor.WorldPosition + Vector3.new(0, 3, 0) }):Play()
	end
	TweenService:Create(label, TweenInfo.new(1.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	api.debris(anchor, 1.3)
end

Core.ScreenFlash = function(params, api)
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local duration = if type(params.duration) == "number" then params.duration else 1
	local gui = Instance.new("ScreenGui")
	gui.Name = "EffetEcran"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.ResetOnSpawn = false
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BorderSizePixel = 0
	frame.Parent = gui
	if api.isNoFlash() then
		-- Accessibilité : aucune lumière vive ; vignette sombre + icône, même durée (la pénalité de jeu est serveur).
		frame.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
		frame.BackgroundTransparency = 0.35
		local icon = Instance.new("TextLabel")
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.4)
		icon.Size = UDim2.fromOffset(320, 80)
		icon.TextScaled = true
		icon.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
		icon.TextColor3 = Color3.fromRGB(255, 220, 120)
		icon.Text = if type(params.label) == "string" then params.label else "✶"
		icon.Parent = frame
	else
		frame.BackgroundColor3 = if typeof(params.color) == "Color3" then params.color else Color3.new(1, 1, 1)
		frame.BackgroundTransparency = 0
	end
	gui.Parent = playerGui
	local fadeStart = math.max(0, duration - 0.6)
	task.delay(fadeStart, function()
		if frame.Parent then
			TweenService:Create(frame, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		end
	end)
	api.debris(gui, duration + 0.1)
end

return Core
