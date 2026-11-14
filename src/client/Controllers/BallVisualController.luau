--!strict
--[[
	BallVisualController — rendu client des balles de golf (priorité 36).

	Pour chaque Part de Workspace.Balls (attributs OwnerUserId, State, Skin) :
	  - une sphère VISUELLE locale (diamètre du Part) suit la balle serveur par interpolation exponentielle
	    à chaque image (Gameplay.Aim.VisualSmoothing, recalage au-delà de VisualSnapDistance) et roule
	    visuellement dans le sens du déplacement ;
	  - habillage par le skin du propriétaire : Shared.Cosmetics, emplacement "Ball", decorate(visuel, variante)
	    (attribut Skin = "id" ou "id:variante", ou attribut SkinVariant) ; la balle blanche par défaut sinon ;
	  - le Part serveur reste la collision de référence : masqué LOCALEMENT (LocalTransparencyModifier) et sa
	    traînée serveur est coupée localement (aucune propriété répliquée n'est modifiée côté serveur) ;
	  - traînée pendant le mouvement (désactivée si EffectsController.IsReduced()) ;
	  - balles des autres : étiquette nom + couleur du propriétaire (glyphe d'équipe en mode Équipes) ;
	  - sa propre balle : contour visible à travers le décor, flèche hors écran + distance, pulsation et
	    étiquette « Prête ! » quand elle s'arrête ;
	  - balle gelée (State = "Frozen") : coque de glace.
	Tout est nettoyé à la disparition de la balle (Trove par balle).

	API : GetVisual(ball) -> BasePart?   GetOwnBall() -> BasePart?
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trove = require(Shared.Util.Trove)
local Log = require(Shared.Util.Log)
local GameState = require(Shared.Util.GameState)
local Locale = require(Shared.Locale)
local Gameplay = require(Shared.Config.Gameplay)

local ClientRoot = script.Parent.Parent
local Theme = require(ClientRoot.UI.Theme)

local BallVisualController = {}
BallVisualController.Priority = 36

local AIM = Gameplay.Aim
local BALL = Gameplay.Ball

local TAG_MAX_DISTANCE = 260
local OWN_TAG_MIN_DISTANCE = 22 -- en deçà, l'étiquette de sa propre balle est masquée
local INDICATOR_MIN_DISTANCE = 14
local INDICATOR_MARGIN = 56
local READY_TAG_TIME = 1.6
local ROLL_MAX_STEP = math.rad(90)
local OWN_COLOR = Color3.fromRGB(255, 214, 64)

local localPlayer = Players.LocalPlayer

type Entry = {
	ball: BasePart,
	visual: BasePart,
	trove: Trove.Trove,
	skinTrove: Trove.Trove,
	trail: Trail,
	tag: BillboardGui?,
	tagLabel: TextLabel?,
	highlight: Highlight?,
	ice: BasePart?,
	position: Vector3,
	rotation: CFrame,
	own: boolean,
	ownerUserId: number,
	lastState: string,
	readyUntil: number,
	skin: string,
}

local entries: { [BasePart]: Entry } = {}
local runtimeTrove = Trove.new()
local visualsFolder: Folder? = nil
local gameStateFolder: Folder? = nil

local indicator = {
	gui = nil :: ScreenGui?,
	root = nil :: Frame?,
	arrow = nil :: TextLabel?,
	label = nil :: TextLabel?,
}

--------------------------------------------------------------------------------
-- Modules facultatifs
--------------------------------------------------------------------------------

local cosmeticsModule: any = nil
local cosmeticsLooked = false

local function getCosmetics(): any
	if not cosmeticsLooked then
		cosmeticsLooked = true
		local module = Shared:FindFirstChild("Cosmetics")
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				cosmeticsModule = result
			else
				Log.warn("BallVisual", "Cosmetics indisponible :", result)
			end
		end
	end
	return cosmeticsModule
end

local effectsModule: any = nil
local effectsLooked = false

local function getEffects(): any
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
	return effectsModule
end

local function isReduced(): boolean
	local effects = getEffects()
	if effects and type(effects.IsReduced) == "function" then
		local ok, value = pcall(effects.IsReduced)
		if ok then
			return value == true
		end
	end
	return Theme.isReducedMotion()
end

local function playEffect(name: string, params: { [string]: any })
	local effects = getEffects()
	if effects and type(effects.Play) == "function" then
		pcall(effects.Play, name, params)
	end
end

--------------------------------------------------------------------------------
-- Aides
--------------------------------------------------------------------------------

local function teamsMode(): boolean
	local folder = gameStateFolder
	return folder ~= nil and folder:GetAttribute("Mode") == "Teams"
end

-- Couleur stable d'un joueur sans équipe (teinte dérivée de l'identifiant).
local function ownerColor(userId: number): Color3
	local hue = ((userId * 0.61803398875) % 1)
	return Color3.fromHSV(hue, 0.55, 1)
end

local function parseSkin(ball: BasePart): (string, number?)
	local raw = ball:GetAttribute("Skin")
	local id = if type(raw) == "string" then raw else ""
	local variant: number? = nil
	local separator = string.find(id, ":", 1, true)
	if separator then
		variant = tonumber(string.sub(id, separator + 1))
		id = string.sub(id, 1, separator - 1)
	end
	local attribute = ball:GetAttribute("SkinVariant")
	if type(attribute) == "number" then
		variant = attribute
	end
	return id, variant
end

local function makeLocalPart(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Habillage par défaut : balle blanche brillante.
local function applyDefaultLook(visual: BasePart)
	visual.Material = Enum.Material.SmoothPlastic
	visual.Color = BALL.Color
	visual.Reflectance = 0.05
	visual.Transparency = 0
end

local function applySkin(entry: Entry)
	local id, variant = parseSkin(entry.ball)
	local key = id .. ":" .. tostring(variant)
	if key == entry.skin then
		return
	end
	entry.skin = key
	entry.skinTrove:Clean()
	applyDefaultLook(entry.visual)
	if id == "" then
		return
	end
	local cosmetics = getCosmetics()
	if not cosmetics or type(cosmetics.get) ~= "function" then
		return
	end
	local okGet, def = pcall(cosmetics.get, id)
	if not okGet or type(def) ~= "table" or def.slot ~= "Ball" or type(def.decorate) ~= "function" then
		return
	end
	local okDecorate, decoration = pcall(def.decorate, entry.visual, variant)
	if not okDecorate then
		Log.warn("BallVisual", "skin de balle en erreur :", id, decoration)
		applyDefaultLook(entry.visual)
		return
	end
	if typeof(decoration) == "Instance" then
		-- Équité : un décor n'interagit jamais avec le jeu.
		for _, item in { decoration, table.unpack(decoration:GetDescendants()) } do
			if item:IsA("BasePart") then
				item.CanCollide = false
				item.CanQuery = false
				item.CanTouch = false
				item.Massless = true
			end
		end
		entry.skinTrove:Add(decoration)
	end
end

local function buildTag(entry: Entry)
	local ownerId = entry.ownerUserId
	local owner = Players:GetPlayerByUserId(ownerId)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "EtiquetteBalle"
	billboard.Adornee = entry.visual
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = TAG_MAX_DISTANCE
	billboard.Size = UDim2.fromOffset(180, 30)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, entry.ball.Size.Y * 0.5 + 1.6, 0)
	billboard.ResetOnSpawn = false

	local pill = Instance.new("Frame")
	pill.Name = "Pastille"
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.new(0, 0, 0, 24)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundColor3 = Theme.Colors.Night
	pill.BackgroundTransparency = 0.2
	pill.BorderSizePixel = 0
	pill.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = pill
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = pill

	local label = Instance.new("TextLabel")
	label.Name = "Nom"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0, 0, 1, 0)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.FontFace = Theme.font("Heavy")
	label.TextSize = 15
	label.TextColor3 = Theme.Colors.Paper
	label.Parent = pill
	local textStroke = Instance.new("UIStroke")
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textStroke.Color = Theme.Colors.Ink
	textStroke.Thickness = 1.5
	textStroke.Parent = label

	local function refresh()
		if entry.own then
			label.Text = Locale.t("aim.ball.yours")
			stroke.Color = OWN_COLOR
			label.TextColor3 = OWN_COLOR
			return
		end
		local name = if owner then owner.DisplayName else Locale.t("aim.ballTag.unknown")
		local team = if owner then owner:GetAttribute("Team") else nil
		local style = if teamsMode() then Theme.team(team) else nil
		if style then
			label.Text = Locale.t("aim.ballTag.teamName", { glyph = style.glyph, name = name })
			stroke.Color = style.color
			label.TextColor3 = style.text
		else
			label.Text = Locale.t("aim.ballTag.name", { name = name })
			local color = ownerColor(ownerId)
			stroke.Color = color
			label.TextColor3 = Theme.ensureContrast(color, Theme.Colors.Night, 4.5)
		end
	end
	refresh()
	if owner then
		entry.trove:Connect(owner:GetAttributeChangedSignal("Team"), refresh)
	end
	local folder = gameStateFolder
	if folder then
		entry.trove:Connect(folder:GetAttributeChangedSignal("Mode"), refresh)
	end
	billboard.Parent = entry.visual
	entry.tag = billboard
	entry.tagLabel = label
end

local function ensureIce(entry: Entry, frozen: boolean)
	if frozen and not entry.ice then
		local ice = makeLocalPart("Glace", entry.ball.Size * 1.35)
		ice.Material = Enum.Material.Ice
		ice.Color = Color3.fromRGB(170, 225, 255)
		ice.Transparency = 0.35
		ice.CastShadow = false
		ice.Parent = entry.visual
		entry.ice = ice
	elseif not frozen and entry.ice then
		entry.ice:Destroy()
		entry.ice = nil
	end
end

local function pulse(entry: Entry)
	local ground = entry.position - Vector3.new(0, entry.ball.Size.Y * 0.5, 0)
	playEffect("Ring", { position = ground, radius = 2.6, duration = 1.1, color = OWN_COLOR })
	entry.readyUntil = os.clock() + READY_TAG_TIME
	if not isReduced() then
		local base = entry.ball.Size
		local visual = entry.visual
		visual.Size = base * 1.35
		TweenService:Create(visual, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = base }):Play()
	end
end

local function onStateChanged(entry: Entry)
	local value = entry.ball:GetAttribute("State")
	local newState = if type(value) == "string" then value else "Resting"
	local previous = entry.lastState
	entry.lastState = newState
	entry.trail.Enabled = newState == "Moving" and not isReduced()
	ensureIce(entry, newState == "Frozen")
	if entry.own and newState == "Resting" and previous == "Moving" then
		pulse(entry)
	end
end

--------------------------------------------------------------------------------
-- Suivi des balles
--------------------------------------------------------------------------------

local function removeBall(ball: BasePart)
	local entry = entries[ball]
	if not entry then
		return
	end
	entries[ball] = nil
	entry.trove:Clean()
end

local function addBall(ball: BasePart)
	if entries[ball] then
		return
	end
	local ownerValue = ball:GetAttribute("OwnerUserId")
	local ownerUserId = if type(ownerValue) == "number" then ownerValue else 0
	local trove = Trove.new()
	local visual = makeLocalPart("BalleVisuelle_" .. ownerUserId, ball.Size)
	applyDefaultLook(visual)
	visual.CFrame = ball.CFrame
	trove:Add(visual)

	-- Traînée locale (deux attachements haut/bas).
	local radius = ball.Size.Y * 0.5
	local top = Instance.new("Attachment")
	top.Name = "TraineeHaut"
	top.Position = Vector3.new(0, radius * 0.6, 0)
	top.Parent = visual
	local bottom = Instance.new("Attachment")
	bottom.Name = "TraineeBas"
	bottom.Position = Vector3.new(0, -radius * 0.6, 0)
	bottom.Parent = visual
	local trail = Instance.new("Trail")
	trail.Name = "Trainee"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = BALL.TrailLifetime
	trail.FaceCamera = true
	trail.LightEmission = 0.6
	trail.MinLength = 0.05
	local own = ownerUserId == localPlayer.UserId
	local trailColor = if own then OWN_COLOR else ownerColor(ownerUserId)
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), trailColor)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Enabled = false
	trail.Parent = visual

	local entry: Entry = {
		ball = ball,
		visual = visual,
		trove = trove,
		skinTrove = trove:Extend(),
		trail = trail,
		tag = nil,
		tagLabel = nil,
		highlight = nil,
		ice = nil,
		position = ball.Position,
		rotation = CFrame.identity,
		own = own,
		ownerUserId = ownerUserId,
		lastState = "",
		readyUntil = 0,
		skin = "\0",
	}
	entries[ball] = entry

	-- Le Part serveur reste la référence mais n'est plus dessiné localement.
	ball.LocalTransparencyModifier = 1
	local function hideServerVisuals()
		for _, descendant in ball:GetDescendants() do
			if descendant:IsA("Trail") or descendant:IsA("ParticleEmitter") then
				descendant.Enabled = false
			elseif descendant:IsA("BasePart") then
				descendant.LocalTransparencyModifier = 1
			end
		end
	end
	hideServerVisuals()
	trove:Connect(ball.DescendantAdded, function()
		task.defer(hideServerVisuals)
	end)
	trove:Connect(ball:GetPropertyChangedSignal("LocalTransparencyModifier"), function()
		if ball.LocalTransparencyModifier ~= 1 then
			ball.LocalTransparencyModifier = 1
		end
	end)
	trove:Add(function()
		if ball.Parent then
			ball.LocalTransparencyModifier = 0
		end
	end)

	if own then
		local highlight = Instance.new("Highlight")
		highlight.Name = "ContourBalle"
		highlight.Adornee = visual
		highlight.FillTransparency = 1
		highlight.OutlineColor = OWN_COLOR
		highlight.OutlineTransparency = 0.15
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = visual
		entry.highlight = highlight
	end
	buildTag(entry)

	trove:Connect(ball:GetAttributeChangedSignal("State"), function()
		onStateChanged(entry)
	end)
	trove:Connect(ball:GetAttributeChangedSignal("Skin"), function()
		applySkin(entry)
	end)
	trove:Connect(ball:GetAttributeChangedSignal("SkinVariant"), function()
		applySkin(entry)
	end)
	trove:Connect(ball:GetPropertyChangedSignal("Size"), function()
		visual.Size = ball.Size
	end)
	-- Propriétaire connu après coup (réplication différée) : on reconstruit l'entrée.
	trove:Connect(ball:GetAttributeChangedSignal("OwnerUserId"), function()
		local value = ball:GetAttribute("OwnerUserId")
		if type(value) == "number" and value ~= entry.ownerUserId then
			task.defer(function()
				removeBall(ball)
				if ball.Parent then
					addBall(ball)
				end
			end)
		end
	end)
	applySkin(entry)
	onStateChanged(entry)
	visual.Parent = visualsFolder or Workspace
end

--------------------------------------------------------------------------------
-- Indicateur hors écran de sa propre balle
--------------------------------------------------------------------------------

local function buildIndicator()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("BallIndicator")
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "BallIndicator"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 3

	local root = Instance.new("Frame")
	root.Name = "Repere"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Size = UDim2.fromOffset(46, 46)
	root.BackgroundColor3 = OWN_COLOR
	root.BorderSizePixel = 0
	root.Visible = false
	root.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = root
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Ink
	stroke.Thickness = 3
	stroke.Parent = root

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Fleche"
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.FontFace = Theme.font("Display")
	arrow.TextSize = 26
	arrow.Text = "▲"
	arrow.TextColor3 = Theme.Colors.Ink
	arrow.Parent = root

	local label = Instance.new("TextLabel")
	label.Name = "Distance"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 1, 4)
	label.Size = UDim2.fromOffset(160, 20)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.font("Heavy")
	label.TextSize = 15
	label.TextColor3 = Theme.Colors.Paper
	label.Parent = root
	local labelStroke = Instance.new("UIStroke")
	labelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	labelStroke.Color = Theme.Colors.Ink
	labelStroke.Thickness = 2
	labelStroke.Parent = label

	local scale = Instance.new("UIScale")
	scale.Scale = Theme.getScale()
	scale.Parent = gui
	runtimeTrove:Connect(Theme.Changed, function(what: any)
		if what == "layout" then
			scale.Scale = Theme.getScale()
		end
	end)

	gui.Parent = playerGui
	runtimeTrove:Add(gui)
	indicator.gui = gui
	indicator.root = root
	indicator.arrow = arrow
	indicator.label = label
end

local function updateIndicator(entry: Entry?)
	local root = indicator.root
	if not root then
		return
	end
	local camera = Workspace.CurrentCamera
	local character = localPlayer.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not entry or not camera or not hrp or not hrp:IsA("BasePart") or entry.lastState == "Holed" then
		root.Visible = false
		return
	end
	local position = entry.position
	local distance = (position - hrp.Position).Magnitude
	if distance < INDICATOR_MIN_DISTANCE then
		root.Visible = false
		return
	end
	local viewport = camera.ViewportSize
	local point, onScreen = camera:WorldToViewportPoint(position)
	local inside = onScreen
		and point.Z > 0
		and point.X > INDICATOR_MARGIN
		and point.X < viewport.X - INDICATOR_MARGIN
		and point.Y > INDICATOR_MARGIN
		and point.Y < viewport.Y - INDICATOR_MARGIN
	local label = indicator.label :: TextLabel
	local arrow = indicator.arrow :: TextLabel
	if inside then
		-- Balle visible : l'étiquette 3D suffit.
		root.Visible = false
		return
	end
	local center = viewport / 2
	local direction = Vector2.new(point.X, point.Y) - center
	if point.Z < 0 then
		direction = -direction
	end
	if direction.Magnitude < 1 then
		direction = Vector2.new(0, 1)
	end
	local halfX = math.max(center.X - INDICATOR_MARGIN, 10)
	local halfY = math.max(center.Y - INDICATOR_MARGIN, 10)
	local factor = math.min(halfX / math.max(math.abs(direction.X), 1e-3), halfY / math.max(math.abs(direction.Y), 1e-3))
	local placed = center + direction * factor
	root.Position = UDim2.fromOffset(placed.X, placed.Y)
	arrow.Rotation = math.deg(math.atan2(direction.X, -direction.Y))
	label.Text = Locale.t("aim.ball.offscreen", { n = math.floor(distance + 0.5) })
	-- Libellé du côté intérieur de l'écran.
	label.Position = if placed.Y > center.Y then UDim2.new(0.5, 0, 0, -24) else UDim2.new(0.5, 0, 1, 4)
	root.Visible = true
end

--------------------------------------------------------------------------------
-- Boucle de rendu
--------------------------------------------------------------------------------

local function onRenderStep(dt: number)
	local alpha = 1 - math.exp(-AIM.VisualSmoothing * dt)
	local camera = Workspace.CurrentCamera
	local character = localPlayer.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local ownEntry: Entry? = nil
	local now = os.clock()
	for ball, entry in entries do
		if not ball.Parent then
			continue
		end
		local target = ball.Position
		local previous = entry.position
		local offset = target - previous
		local position: Vector3
		if offset.Magnitude > AIM.VisualSnapDistance then
			position = target
		else
			position = previous:Lerp(target, alpha)
		end
		-- Roulement visuel : rotation autour de l'axe perpendiculaire au déplacement.
		local moved = position - previous
		local horizontal = Vector3.new(moved.X, 0, moved.Z)
		local radius = math.max(ball.Size.Y * 0.5, 0.05)
		if horizontal.Magnitude > 1e-3 and horizontal.Magnitude < AIM.VisualSnapDistance then
			local axis = Vector3.yAxis:Cross(horizontal.Unit)
			local angle = math.min(horizontal.Magnitude / radius, ROLL_MAX_STEP)
			entry.rotation = CFrame.fromAxisAngle(axis, angle) * entry.rotation
		end
		entry.position = position
		entry.visual.CFrame = CFrame.new(position) * entry.rotation
		if entry.ice then
			entry.ice.CFrame = CFrame.new(position)
		end
		-- Étiquette de sa propre balle : seulement de loin, ou « Prête ! » juste après l'arrêt.
		if entry.own then
			ownEntry = entry
			local tag = entry.tag
			local label = entry.tagLabel
			if tag and label then
				local far = hrp ~= nil and hrp:IsA("BasePart") and (hrp.Position - position).Magnitude > OWN_TAG_MIN_DISTANCE
				local ready = now < entry.readyUntil
				tag.Enabled = (far or ready) and entry.lastState ~= "Holed"
				label.Text = if ready then Locale.t("aim.ball.ready") else Locale.t("aim.ball.yours")
			end
		elseif entry.tag and camera then
			entry.tag.Enabled = entry.lastState ~= "Holed"
		end
	end
	updateIndicator(ownEntry)
end

--------------------------------------------------------------------------------
-- API et cycle de vie
--------------------------------------------------------------------------------

function BallVisualController.GetVisual(ball: BasePart): BasePart?
	local entry = entries[ball]
	return if entry then entry.visual else nil
end

function BallVisualController.GetOwnBall(): BasePart?
	for ball, entry in entries do
		if entry.own then
			return ball
		end
	end
	return nil
end

function BallVisualController.Init()
	local folder = Instance.new("Folder")
	folder.Name = "GolfBallVisuals"
	visualsFolder = folder
	runtimeTrove:Add(folder)
	runtimeTrove:Add(function()
		for ball in table.clone(entries) do
			removeBall(ball)
		end
	end)
end

function BallVisualController.Start()
	local okState, stateFolder = pcall(GameState.get)
	if okState and typeof(stateFolder) == "Instance" then
		gameStateFolder = stateFolder :: Folder
	end
	if visualsFolder then
		visualsFolder.Parent = Workspace
	end
	buildIndicator()
	RunService:BindToRenderStep("GolfChaosBallVisuals", Enum.RenderPriority.Camera.Value + 5, onRenderStep)
	runtimeTrove:Add(function()
		RunService:UnbindFromRenderStep("GolfChaosBallVisuals")
	end)

	local balls = Workspace:FindFirstChild(BALL.FolderName) or Workspace:WaitForChild(BALL.FolderName, 120)
	if not balls then
		Log.warn("BallVisual", "dossier Workspace." .. BALL.FolderName .. " introuvable")
		return
	end
	local function consider(child: Instance)
		if child:IsA("BasePart") then
			-- Attributs arrivés avec l'instance (ou juste après en mode différé).
			task.defer(function()
				if child.Parent == balls then
					addBall(child)
				end
			end)
		end
	end
	runtimeTrove:Connect(balls.ChildAdded, consider)
	runtimeTrove:Connect(balls.ChildRemoved, function(child: Instance)
		if child:IsA("BasePart") then
			removeBall(child)
		end
	end)
	for _, child in balls:GetChildren() do
		consider(child)
	end
end

return BallVisualController
