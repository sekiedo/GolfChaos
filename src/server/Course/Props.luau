--!strict
--[[
	Course/Props : accessoires cartoon low-poly construits par code (aucun mesh, aucun AssetId).

	  local model = Props.make("palm", CFrame.new(pos), 1.2, Random.new(seed), palette)
	  Props.kinds()                    -- liste des types (identique à Config/Course.PropKinds)
	  Props.setSolid(model, true)      -- rend bloquantes les pièces « cœur » (tronc, corps, socle)
	  Props.partCount(model)

	Conventions :
	- `cf` = point au SOL du pied de l'accessoire (le modèle pousse vers +Y de `cf`) ; `scale` multiplie tout.
	- Toutes les pièces sont ancrées, sans Union, NON bloquantes par défaut (CanCollide, CanQuery, CanTouch
	  false) : c'est du décor. Les pièces « cœur » (attribut PropCore = true : tronc, corps, socle) deviennent
	  bloquantes via Props.setSolid ; HoleBuilder le fait pour les accessoires posés explicitement sur le trou dont
	  le type est dans Config/Course.SolidProps (ou params.solid = true). Le décor de fond n'est jamais bloquant.
	- CastShadow coupé sur les petites pièces (diagonale < 10 studs) pour les performances.
	- Attributs du modèle : PropKind (string), Breakable (bool, Config/Course.BreakableProps).
	- `palette` = Config/Biomes.<biome>.palette ({ foliage = { Color3 }, trunk = ..., rock = ..., ... }) ;
	  `rng` rend les variations (teintes, orientations) reproductibles (même graine = même décor).
	- `params` (facultatif, 6e argument) : options propres au type (distance, radius, color, textKey, light...).
	Textes inscrits sur le décor : Locale (clés "hole.marker.*" de Locale/*/HolesTraining.luau).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Course = require(Shared.Config.Course)
local Locale = require(Shared.Locale)

export type Palette = { [string]: { Color3 } }

type Ctx = {
	model: Model,
	cf: CFrame,
	s: number,
	rng: Random,
	pal: Palette,
	params: { [string]: any },
}

local Props = {}

local SMOOTH = Enum.Material.SmoothPlastic
local HALF_PI = math.pi / 2

local DEFAULTS: Palette = {
	foliage = { Color3.fromRGB(76, 176, 76), Color3.fromRGB(96, 196, 84) },
	trunk = { Color3.fromRGB(140, 98, 60) },
	rock = { Color3.fromRGB(170, 166, 160), Color3.fromRGB(150, 146, 140) },
	flower = { Color3.fromRGB(255, 120, 150), Color3.fromRGB(255, 210, 80), Color3.fromRGB(255, 255, 255) },
	accent = { Color3.fromRGB(255, 82, 82), Color3.fromRGB(255, 255, 255), Color3.fromRGB(56, 170, 255) },
	sand = { Color3.fromRGB(240, 214, 150) },
	snow = { Color3.fromRGB(244, 248, 255) },
	ice = { Color3.fromRGB(170, 220, 255) },
	cactus = { Color3.fromRGB(84, 160, 84) },
	building = { Color3.fromRGB(240, 220, 180), Color3.fromRGB(200, 200, 210) },
	roof = { Color3.fromRGB(70, 74, 86) },
	metal = { Color3.fromRGB(90, 96, 110) },
}

local WHITE = Color3.fromRGB(250, 250, 250)
local DARK = Color3.fromRGB(40, 40, 46)

--------------------------------------------------------------------------------
-- Outils de construction
--------------------------------------------------------------------------------

local function pick(ctx: Ctx, key: string): Color3
	local list = ctx.pal[key]
	if list == nil or #list == 0 then
		list = DEFAULTS[key] or DEFAULTS.accent
	end
	return list[ctx.rng:NextInteger(1, #list)]
end

-- Variation de teinte légère (±amount sur la luminosité) pour casser la répétition.
local function vary(ctx: Ctx, color: Color3, amount: number?): Color3
	local h, s, v = color:ToHSV()
	local delta = (ctx.rng:NextNumber() * 2 - 1) * (amount or 0.06)
	return Color3.fromHSV(h, s, math.clamp(v + delta, 0, 1))
end

local function scaled(ctx: Ctx, offset: CFrame): CFrame
	return CFrame.new(offset.Position * ctx.s) * offset.Rotation
end

local function finish(ctx: Ctx, part: BasePart, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, core: boolean?)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = material or SMOOTH
	part.Color = color
	part.Size = size * ctx.s
	part.CFrame = ctx.cf * scaled(ctx, offset)
	part.CastShadow = part.Size.Magnitude >= 10
	if core then
		part:SetAttribute("PropCore", true)
	end
	part.Parent = ctx.model
end

local function box(ctx: Ctx, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, core: boolean?): Part
	local part = Instance.new("Part")
	finish(ctx, part, size, offset, color, material, core)
	return part
end

local function wedge(ctx: Ctx, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, core: boolean?): WedgePart
	local part = Instance.new("WedgePart")
	finish(ctx, part, size, offset, color, material, core)
	return part
end

-- Cylindre vertical : hauteur h, diamètre d, centre à `offset`.
local function cyl(ctx: Ctx, h: number, d: number, offset: CFrame, color: Color3, material: Enum.Material?, core: boolean?): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	finish(ctx, part, Vector3.new(h, d, d), offset * CFrame.Angles(0, 0, HALF_PI), color, material, core)
	return part
end

local function ball(ctx: Ctx, d: number, offset: CFrame, color: Color3, material: Enum.Material?, core: boolean?): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	finish(ctx, part, Vector3.new(d, d, d), offset, color, material, core)
	return part
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- Rotation aléatoire (facettes low-poly).
local function tumble(ctx: Ctx): CFrame
	local r = ctx.rng
	return CFrame.Angles(r:NextNumber() * math.pi, r:NextNumber() * math.pi, r:NextNumber() * math.pi)
end

-- Panneau de texte (SurfaceGui) sur une face d'une pièce ; le texte vient de Locale.
local function label(part: BasePart, face: Enum.NormalId, text: string, textColor: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	gui.Parent = part
	local text_ = Instance.new("TextLabel")
	text_.BackgroundTransparency = 1
	text_.Size = UDim2.fromScale(1, 1)
	text_.Text = text
	text_.TextScaled = true
	text_.TextColor3 = textColor
	text_.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	text_.Parent = gui
end

--------------------------------------------------------------------------------
-- Végétation
--------------------------------------------------------------------------------

local function tree(ctx: Ctx)
	local trunkH = 7 + ctx.rng:NextNumber() * 2
	cyl(ctx, trunkH, 1.6, at(0, trunkH / 2, 0), vary(ctx, pick(ctx, "trunk")), SMOOTH, true)
	local color = pick(ctx, "foliage")
	for index = 1, 3 do
		local size = 6.5 - index * 0.8 + ctx.rng:NextNumber()
		local angle = index * 2.1
		local offset = at(math.cos(angle) * 1.4, trunkH + index * 1.6, math.sin(angle) * 1.4)
		box(ctx, Vector3.new(size, size, size), offset * tumble(ctx), vary(ctx, color, 0.08))
	end
end

local function pine(ctx: Ctx)
	cyl(ctx, 4, 1.4, at(0, 2, 0), vary(ctx, pick(ctx, "trunk")), SMOOTH, true)
	local color = pick(ctx, "foliage")
	local tiers = { { 8, 3, 4.5 }, { 6, 2.6, 7.5 }, { 4, 2.2, 10.2 }, { 2, 2, 12.4 } }
	for index, tier in tiers do
		local yaw = CFrame.Angles(0, math.rad(45 * index + ctx.rng:NextNumber() * 20), 0)
		box(ctx, Vector3.new(tier[1], tier[2], tier[1]), at(0, tier[3], 0) * yaw, vary(ctx, color, 0.05), SMOOTH, index == 1)
	end
	if ctx.params.snowy or ctx.pal.snow ~= nil then
		box(ctx, Vector3.new(2.2, 0.8, 2.2), at(0, 13.6, 0) * CFrame.Angles(0, math.rad(45), 0), pick(ctx, "snow"))
	end
end

local function palm(ctx: Ctx)
	local trunk = vary(ctx, pick(ctx, "trunk"))
	local lean = 0.12 + ctx.rng:NextNumber() * 0.12
	local pos = Vector3.zero
	local segments = 5
	for index = 1, segments do
		local tilt = CFrame.Angles(0, 0, -lean * index)
		local step = (tilt * CFrame.new(0, 2.6, 0)).Position
		local center = pos + step / 2
		local shade = if index % 2 == 0 then trunk else vary(ctx, trunk, 0.1)
		cyl(ctx, 2.8, 1.3 - index * 0.08, CFrame.new(center) * tilt, shade, SMOOTH, true)
		pos += step
	end
	local top = CFrame.new(pos)
	local leaf = pick(ctx, "foliage")
	for index = 1, 6 do
		local yaw = math.rad(index * 60 + ctx.rng:NextNumber() * 15)
		local frond = top * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0.2, 2.6) * CFrame.Angles(math.rad(22), 0, 0)
		box(ctx, Vector3.new(1.5, 0.3, 5.6), frond, vary(ctx, leaf, 0.08))
	end
	ball(ctx, 0.9, top * at(0.5, -0.5, 0.3), Color3.fromRGB(120, 84, 50))
	ball(ctx, 0.9, top * at(-0.4, -0.6, -0.4), Color3.fromRGB(110, 76, 46))
end

local function birch(ctx: Ctx)
	local h = 10
	cyl(ctx, h, 1.1, at(0, h / 2, 0), Color3.fromRGB(240, 238, 230), SMOOTH, true)
	for index = 1, 3 do
		box(ctx, Vector3.new(0.4, 0.25, 0.2), at(0.45, 2 + index * 2.2, 0) * CFrame.Angles(0, index, 0), DARK)
	end
	local color = Color3.fromRGB(170, 210, 80):Lerp(pick(ctx, "foliage"), 0.4)
	box(ctx, Vector3.new(5, 6, 5), at(0, h + 1.5, 0) * tumble(ctx), vary(ctx, color))
	box(ctx, Vector3.new(3.6, 4.4, 3.6), at(0.8, h + 4, 0.4) * tumble(ctx), vary(ctx, color))
end

local function bush(ctx: Ctx)
	local color = pick(ctx, "foliage")
	box(ctx, Vector3.new(3.4, 3, 3.4), at(0, 1.2, 0) * tumble(ctx), vary(ctx, color), SMOOTH, true)
	box(ctx, Vector3.new(2.6, 2.4, 2.6), at(1.4, 1, 0.6) * tumble(ctx), vary(ctx, color))
	if ctx.rng:NextNumber() < 0.5 then
		ball(ctx, 0.7, at(0.4, 2.6, -0.6), pick(ctx, "flower"))
	end
end

local function cactus(ctx: Ctx)
	local color = vary(ctx, pick(ctx, "cactus"))
	local h = 7 + ctx.rng:NextNumber() * 2
	cyl(ctx, h, 1.8, at(0, h / 2, 0), color, SMOOTH, true)
	ball(ctx, 1.8, at(0, h, 0), color)
	local armH = h * 0.45
	cyl(ctx, 1, 1.2, at(1.3, armH, 0) * CFrame.Angles(0, 0, HALF_PI), color)
	cyl(ctx, 2.4, 1.2, at(1.9, armH + 1.2, 0), color)
	ball(ctx, 1.2, at(1.9, armH + 2.4, 0), color)
	if ctx.rng:NextNumber() < 0.6 then
		cyl(ctx, 1, 1.1, at(-1.3, armH + 1.2, 0) * CFrame.Angles(0, 0, HALF_PI), color)
		cyl(ctx, 1.8, 1.1, at(-1.8, armH + 2.1, 0), color)
		ball(ctx, 1.1, at(-1.8, armH + 3, 0), color)
	end
	if ctx.rng:NextNumber() < 0.5 then
		ball(ctx, 0.8, at(0, h + 0.9, 0), pick(ctx, "flower"))
	end
end

local function duneGrass(ctx: Ctx)
	local color = Color3.fromRGB(196, 186, 110)
	for index = 1, 4 do
		local yaw = math.rad(index * 90 + ctx.rng:NextNumber() * 40)
		local tilt = math.rad(12 + ctx.rng:NextNumber() * 18)
		box(ctx, Vector3.new(0.3, 2.6, 0.3), CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, 0) * at(0, 1.3, 0), vary(ctx, color, 0.1))
	end
end

local function reeds(ctx: Ctx)
	for index = 1, 5 do
		local x = (ctx.rng:NextNumber() - 0.5) * 2
		local z = (ctx.rng:NextNumber() - 0.5) * 2
		local h = 3 + ctx.rng:NextNumber() * 1.5
		cyl(ctx, h, 0.2, at(x, h / 2, z) * CFrame.Angles(0, 0, (ctx.rng:NextNumber() - 0.5) * 0.3), Color3.fromRGB(110, 150, 70))
		if index % 2 == 1 then
			cyl(ctx, 0.8, 0.4, at(x, h, z), Color3.fromRGB(120, 80, 50))
		end
	end
end

local function mushroom(ctx: Ctx)
	cyl(ctx, 3, 1.4, at(0, 1.5, 0), Color3.fromRGB(245, 236, 214), SMOOTH, true)
	local cap = Color3.fromRGB(235, 70, 70):Lerp(pick(ctx, "accent"), 0.2)
	cyl(ctx, 1.2, 5, at(0, 3.4, 0), cap, SMOOTH, true)
	cyl(ctx, 0.9, 3.4, at(0, 4.3, 0), cap)
	for index = 1, 3 do
		local angle = index * 2.09
		ball(ctx, 0.7, at(math.cos(angle) * 1.5, 4.6, math.sin(angle) * 1.5), WHITE)
	end
end

local function flowerbed(ctx: Ctx)
	box(ctx, Vector3.new(5, 0.6, 3), at(0, 0.3, 0), Color3.fromRGB(110, 78, 52))
	box(ctx, Vector3.new(4.4, 0.4, 2.4), at(0, 0.7, 0), vary(ctx, pick(ctx, "foliage")))
	for index = 1, 4 do
		local x = -1.6 + (index - 1) * 1.07
		ball(ctx, 0.8, at(x, 1.2, (ctx.rng:NextNumber() - 0.5) * 1.2), pick(ctx, "flower"))
	end
end

--------------------------------------------------------------------------------
-- Minéral, neige
--------------------------------------------------------------------------------

local function rock(ctx: Ctx)
	local color = pick(ctx, "rock")
	box(ctx, Vector3.new(3.2, 2.6, 2.8), at(0, 0.8, 0) * tumble(ctx), vary(ctx, color), SMOOTH, true)
	if ctx.rng:NextNumber() < 0.6 then
		box(ctx, Vector3.new(1.8, 1.5, 1.6), at(1.6, 0.4, 0.8) * tumble(ctx), vary(ctx, color))
	end
end

local function boulder(ctx: Ctx)
	local color = pick(ctx, "rock")
	box(ctx, Vector3.new(7, 6, 6.5), at(0, 2, 0) * tumble(ctx), vary(ctx, color), SMOOTH, true)
	box(ctx, Vector3.new(4.5, 4, 4.2), at(2.6, 1.4, 1.8) * tumble(ctx), vary(ctx, color))
	box(ctx, Vector3.new(3, 2.6, 2.8), at(-2.4, 0.8, -1.6) * tumble(ctx), vary(ctx, color))
end

local function dune(ctx: Ctx)
	local color = pick(ctx, "sand")
	ball(ctx, 26, at(0, -8, 0), vary(ctx, color, 0.04), Enum.Material.Sand, true)
	ball(ctx, 16, at(9, -5, 4), vary(ctx, color, 0.04), Enum.Material.Sand)
end

local function snowman(ctx: Ctx)
	local snow = pick(ctx, "snow")
	ball(ctx, 4, at(0, 2, 0), snow, SMOOTH, true)
	ball(ctx, 3, at(0, 5, 0), snow, SMOOTH, true)
	ball(ctx, 2.2, at(0, 7.3, 0), snow)
	cyl(ctx, 1.2, 0.3, at(0, 7.3, -1.4) * CFrame.Angles(HALF_PI, 0, 0), Color3.fromRGB(255, 140, 40))
	ball(ctx, 0.35, at(0.45, 7.6, -1), DARK)
	ball(ctx, 0.35, at(-0.45, 7.6, -1), DARK)
	cyl(ctx, 0.2, 2.4, at(0, 8.3, 0), DARK)
	cyl(ctx, 1.3, 1.5, at(0, 9, 0), DARK)
	box(ctx, Vector3.new(3.2, 0.5, 0.5), at(0, 6.2, 0), pick(ctx, "accent"))
end

local function iceCrystal(ctx: Ctx)
	local color = pick(ctx, "ice")
	for index = 1, 3 do
		local h = 6 - index + ctx.rng:NextNumber() * 2
		local tilt = CFrame.Angles((ctx.rng:NextNumber() - 0.5) * 0.6, index * 2, (ctx.rng:NextNumber() - 0.5) * 0.6)
		local part = box(ctx, Vector3.new(1.4, h, 1.4), tilt * at(0, h / 2, 0) * CFrame.Angles(0, math.rad(45), 0), color, Enum.Material.Glass, index == 1)
		part.Transparency = 0.25
		part.Reflectance = 0.1
	end
end

--------------------------------------------------------------------------------
-- Constructions
--------------------------------------------------------------------------------

local function building(ctx: Ctx)
	local floors = ctx.params.floors or ctx.rng:NextInteger(3, 7)
	local w, d = 12, 12
	local h = floors * 4
	local wall = pick(ctx, "building")
	box(ctx, Vector3.new(w, h, d), at(0, h / 2, 0), wall, SMOOTH, true)
	box(ctx, Vector3.new(w + 1, 0.8, d + 1), at(0, h + 0.4, 0), pick(ctx, "roof"))
	local glass = Color3.fromRGB(150, 210, 250)
	for floor = 1, floors do
		local y = (floor - 0.5) * 4
		box(ctx, Vector3.new(w - 2, 1.6, d + 0.2), at(0, y, 0), glass, Enum.Material.Glass)
		box(ctx, Vector3.new(w + 0.2, 1.6, d - 2), at(0, y, 0), glass, Enum.Material.Glass)
	end
	if ctx.rng:NextNumber() < 0.5 then
		box(ctx, Vector3.new(3, 2, 3), at(2, h + 1.8, -2), pick(ctx, "metal"))
	end
end

local function house(ctx: Ctx)
	local wall = pick(ctx, "building")
	local roof = pick(ctx, "roof")
	box(ctx, Vector3.new(10, 6, 8), at(0, 3, 0), wall, SMOOTH, true)
	wedge(ctx, Vector3.new(11, 3.5, 4.6), at(0, 7.75, 2.2), roof)
	wedge(ctx, Vector3.new(11, 3.5, 4.6), at(0, 7.75, -2.2) * CFrame.Angles(0, math.pi, 0), roof)
	box(ctx, Vector3.new(2, 3.4, 0.3), at(0, 1.7, -4.05), Color3.fromRGB(130, 86, 52))
	box(ctx, Vector3.new(1.8, 1.6, 0.25), at(3, 3.4, -4.05), Color3.fromRGB(150, 210, 250), Enum.Material.Glass)
end

local function hut(ctx: Ctx)
	local stripe = pick(ctx, "accent")
	box(ctx, Vector3.new(6, 4.6, 5), at(0, 2.3, 0), WHITE, SMOOTH, true)
	box(ctx, Vector3.new(6.1, 1, 5.1), at(0, 1.4, 0), stripe)
	box(ctx, Vector3.new(6.1, 1, 5.1), at(0, 3.4, 0), stripe)
	wedge(ctx, Vector3.new(6.8, 2, 3), at(0, 5.6, 1.4), stripe)
	wedge(ctx, Vector3.new(6.8, 2, 3), at(0, 5.6, -1.4) * CFrame.Angles(0, math.pi, 0), stripe)
end

local function lamp(ctx: Ctx)
	local metal = pick(ctx, "metal")
	cyl(ctx, 0.6, 1.4, at(0, 0.3, 0), metal, SMOOTH, true)
	cyl(ctx, 9, 0.45, at(0, 4.8, 0), metal, SMOOTH, true)
	box(ctx, Vector3.new(0.3, 0.3, 2), at(0, 9.1, -0.8), metal)
	local bulb = box(ctx, Vector3.new(1.2, 0.8, 1.2), at(0, 8.7, -1.6), Color3.fromRGB(255, 236, 170), Enum.Material.Neon)
	if ctx.params.light then
		local light = Instance.new("PointLight")
		light.Range = 14
		light.Brightness = 1.2
		light.Color = Color3.fromRGB(255, 230, 170)
		light.Parent = bulb
	end
end

local function bench(ctx: Ctx)
	local wood = Color3.fromRGB(176, 120, 70)
	local metal = pick(ctx, "metal")
	box(ctx, Vector3.new(5, 0.4, 1.6), at(0, 1.6, 0), wood, SMOOTH, true)
	box(ctx, Vector3.new(5, 1.2, 0.3), at(0, 2.5, 0.75) * CFrame.Angles(math.rad(-10), 0, 0), wood)
	box(ctx, Vector3.new(0.3, 1.6, 1.4), at(-2.1, 0.8, 0), metal)
	box(ctx, Vector3.new(0.3, 1.6, 1.4), at(2.1, 0.8, 0), metal)
end

local function fence(ctx: Ctx)
	local length = ctx.params.length or 8
	local wood = Color3.fromRGB(236, 230, 214):Lerp(pick(ctx, "trunk"), 0.15)
	box(ctx, Vector3.new(0.5, 3, 0.5), at(-length / 2, 1.5, 0), wood, SMOOTH, true)
	box(ctx, Vector3.new(0.5, 3, 0.5), at(length / 2, 1.5, 0), wood, SMOOTH, true)
	box(ctx, Vector3.new(length, 0.4, 0.25), at(0, 2.4, 0), wood, SMOOTH, true)
	box(ctx, Vector3.new(length, 0.4, 0.25), at(0, 1.2, 0), wood, SMOOTH, true)
end

local function banner(ctx: Ctx)
	local color = ctx.params.color or pick(ctx, "accent")
	cyl(ctx, 10, 0.35, at(0, 5, 0), WHITE, SMOOTH, true)
	box(ctx, Vector3.new(2.4, 0.25, 0.25), at(1.2, 9.6, 0), WHITE)
	box(ctx, Vector3.new(2.2, 4.4, 0.12), at(1.3, 7.2, 0), color)
	wedge(ctx, Vector3.new(0.12, 1.2, 1.1), at(0.75, 4.4, 0) * CFrame.Angles(0, HALF_PI, math.pi), color)
	wedge(ctx, Vector3.new(0.12, 1.2, 1.1), at(1.85, 4.4, 0) * CFrame.Angles(0, -HALF_PI, math.pi), color)
end

local function flag(ctx: Ctx)
	local color = ctx.params.color or pick(ctx, "accent")
	cyl(ctx, 6, 0.25, at(0, 3, 0), WHITE, SMOOTH, true)
	box(ctx, Vector3.new(2.4, 1.5, 0.1), at(1.2, 5.2, 0), color)
end

local function sign(ctx: Ctx)
	local wood = Color3.fromRGB(176, 120, 70)
	box(ctx, Vector3.new(0.5, 4, 0.5), at(0, 2, 0), wood, SMOOTH, true)
	local board = box(ctx, Vector3.new(4.4, 2, 0.35), at(0, 3.8, 0), Color3.fromRGB(250, 236, 200))
	wedge(ctx, Vector3.new(0.35, 2, 1.2), at(2.8, 3.8, 0) * CFrame.Angles(0, HALF_PI, 0) * CFrame.Angles(0, 0, 0), Color3.fromRGB(250, 236, 200))
	local key = ctx.params.textKey
	if type(key) == "string" then
		local text = Locale.t(key, ctx.params.textVars)
		label(board, Enum.NormalId.Front, text, DARK)
		label(board, Enum.NormalId.Back, text, DARK)
	else
		box(ctx, Vector3.new(3, 0.4, 0.4), at(-0.1, 3.8, 0), pick(ctx, "accent"))
	end
end

local function lighthouse(ctx: Ctx)
	local red = Color3.fromRGB(230, 64, 64)
	cyl(ctx, 2, 11, at(0, 1, 0), Color3.fromRGB(170, 166, 160), Enum.Material.Slate, true)
	local y = 2
	for index = 1, 5 do
		local d = 8 - index * 0.7
		cyl(ctx, 4.4, d, at(0, y + 2.2, 0), if index % 2 == 1 then WHITE else red, SMOOTH, true)
		y += 4.4
	end
	cyl(ctx, 0.8, 7.6, at(0, y + 0.4, 0), DARK)
	cyl(ctx, 3, 3.6, at(0, y + 2.3, 0), Color3.fromRGB(255, 230, 120), Enum.Material.Neon)
	cyl(ctx, 1, 4.6, at(0, y + 4.3, 0), red)
	ball(ctx, 1.6, at(0, y + 5.2, 0), red)
end

local function crate(ctx: Ctx)
	local wood = Color3.fromRGB(196, 146, 90)
	box(ctx, Vector3.new(3, 3, 3), at(0, 1.5, 0), wood, Enum.Material.WoodPlanks, true)
	box(ctx, Vector3.new(3.15, 0.5, 3.15), at(0, 2.75, 0), Color3.fromRGB(150, 104, 62))
	box(ctx, Vector3.new(3.15, 0.5, 3.15), at(0, 0.25, 0), Color3.fromRGB(150, 104, 62))
end

local function barrel(ctx: Ctx)
	local wood = Color3.fromRGB(170, 112, 66)
	cyl(ctx, 3.4, 2.4, at(0, 1.7, 0), wood, Enum.Material.WoodPlanks, true)
	cyl(ctx, 0.3, 2.55, at(0, 0.7, 0), pick(ctx, "metal"))
	cyl(ctx, 0.3, 2.55, at(0, 2.7, 0), pick(ctx, "metal"))
end

local function cone(ctx: Ctx)
	local orange = Color3.fromRGB(255, 120, 30)
	box(ctx, Vector3.new(1.8, 0.2, 1.8), at(0, 0.1, 0), orange, SMOOTH, true)
	cyl(ctx, 1, 1.2, at(0, 0.7, 0), orange)
	cyl(ctx, 0.6, 0.9, at(0, 1.5, 0), WHITE)
	cyl(ctx, 0.6, 0.6, at(0, 2.1, 0), orange)
end

local function umbrella(ctx: Ctx)
	local color = pick(ctx, "accent")
	cyl(ctx, 6, 0.3, at(0, 3, 0), WHITE, SMOOTH, true)
	cyl(ctx, 0.5, 7, at(0, 5.6, 0), color)
	cyl(ctx, 0.5, 4.6, at(0, 6, 0), if color == WHITE then Color3.fromRGB(255, 82, 82) else WHITE)
	cyl(ctx, 0.5, 2.2, at(0, 6.4, 0), color)
	ball(ctx, 0.6, at(0, 6.8, 0), WHITE)
end

local function buoy(ctx: Ctx)
	local red = Color3.fromRGB(235, 64, 64)
	cyl(ctx, 1.2, 3, at(0, 0.3, 0), red, SMOOTH, true)
	cyl(ctx, 1, 2.2, at(0, 1.4, 0), WHITE)
	cyl(ctx, 1, 1.4, at(0, 2.4, 0), red)
	ball(ctx, 0.8, at(0, 3.2, 0), Color3.fromRGB(255, 230, 120), Enum.Material.Neon)
end

local function boat(ctx: Ctx)
	local hull = pick(ctx, "accent")
	box(ctx, Vector3.new(4, 1.6, 8), at(0, 0.6, 0), hull, SMOOTH, true)
	wedge(ctx, Vector3.new(4, 1.6, 2.6), at(0, 0.6, -5.3) * CFrame.Angles(0, 0, 0), hull)
	box(ctx, Vector3.new(4.2, 0.3, 8.2), at(0, 1.5, 0), WHITE)
	box(ctx, Vector3.new(3, 1.8, 3), at(0, 2.5, 1.5), WHITE)
	cyl(ctx, 6, 0.25, at(0, 4.5, -1.5), Color3.fromRGB(150, 104, 62))
	wedge(ctx, Vector3.new(0.12, 4.4, 2.6), at(0, 4.6, -0.2) * CFrame.Angles(0, math.pi, 0), WHITE)
end

--------------------------------------------------------------------------------
-- Entraînement
--------------------------------------------------------------------------------

local MARKER_COLORS = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 210, 60),
	Color3.fromRGB(255, 82, 82),
	Color3.fromRGB(86, 156, 255),
}

local function distanceMarker(ctx: Ctx)
	local distance = tonumber(ctx.params.distance) or 0
	local color = MARKER_COLORS[(math.floor(distance / 50) % #MARKER_COLORS) + 1]
	box(ctx, Vector3.new(0.5, 3, 0.5), at(0, 1.5, 0), WHITE, SMOOTH, true)
	local board = box(ctx, Vector3.new(3.6, 2.4, 0.4), at(0, 3.8, 0), color)
	box(ctx, Vector3.new(3.9, 0.3, 0.5), at(0, 2.5, 0), DARK)
	local text = Locale.t("hole.marker.distance", { d = distance })
	label(board, Enum.NormalId.Front, text, DARK)
	label(board, Enum.NormalId.Back, text, DARK)
end

local function targetGreen(ctx: Ctx)
	local radius = tonumber(ctx.params.radius) or 10
	local color = ctx.params.color or pick(ctx, "accent")
	cyl(ctx, 0.12, radius * 2 + 1.2, at(0, 0.06, 0), color)
	cyl(ctx, 0.14, radius * 2, at(0, 0.08, 0), Color3.fromRGB(150, 228, 108))
	cyl(ctx, 0.16, radius * 0.8, at(0, 0.1, 0), WHITE:Lerp(color, 0.5))
	cyl(ctx, 7, 0.25, at(0, 3.5, 0), WHITE)
	local cloth = box(ctx, Vector3.new(3.2, 2, 0.12), at(1.6, 6, 0), color)
	local distance = tonumber(ctx.params.distance)
	if distance then
		local text = Locale.t("hole.marker.target", { d = distance })
		label(cloth, Enum.NormalId.Front, text, DARK)
		label(cloth, Enum.NormalId.Back, text, DARK)
	end
end

--------------------------------------------------------------------------------
-- Registre
--------------------------------------------------------------------------------

local BUILDERS: { [string]: (Ctx) -> () } = {
	tree = tree,
	pine = pine,
	palm = palm,
	birch = birch,
	bush = bush,
	rock = rock,
	boulder = boulder,
	cactus = cactus,
	duneGrass = duneGrass,
	snowman = snowman,
	iceCrystal = iceCrystal,
	building = building,
	house = house,
	hut = hut,
	lamp = lamp,
	bench = bench,
	fence = fence,
	banner = banner,
	buoy = buoy,
	umbrella = umbrella,
	lighthouse = lighthouse,
	crate = crate,
	barrel = barrel,
	cone = cone,
	sign = sign,
	mushroom = mushroom,
	flowerbed = flowerbed,
	reeds = reeds,
	flag = flag,
	boat = boat,
	dune = dune,
	distanceMarker = distanceMarker,
	targetGreen = targetGreen,
}

-- Construit un accessoire. Retourne nil si le type est inconnu. Le modèle n'est PAS parenté.
function Props.make(kind: string, cf: CFrame, scale: number?, rng: Random?, palette: Palette?, params: { [string]: any }?): Model?
	local builder = BUILDERS[kind]
	if builder == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = kind
	local ctx: Ctx = {
		model = model,
		cf = cf,
		s = math.clamp(scale or 1, 0.05, 20),
		rng = rng or Random.new(0),
		pal = palette or DEFAULTS,
		params = params or {},
	}
	builder(ctx)
	model:SetAttribute("PropKind", kind)
	model:SetAttribute("Breakable", Course.BreakableProps[kind] == true)
	model.WorldPivot = cf
	local first = model:FindFirstChildWhichIsA("BasePart")
	if first then
		model.PrimaryPart = first
	end
	return model
end

-- Liste des types, dans l'ordre de Config/Course.PropKinds (puis les éventuels types absents de la config).
function Props.kinds(): { string }
	local list: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, kind in Course.PropKinds do
		if BUILDERS[kind] then
			table.insert(list, kind)
			seen[kind] = true
		end
	end
	local extra: { string } = {}
	for kind in BUILDERS do
		if not seen[kind] then
			table.insert(extra, kind)
		end
	end
	table.sort(extra)
	for _, kind in extra do
		table.insert(list, kind)
	end
	return list
end

function Props.has(kind: string): boolean
	return BUILDERS[kind] ~= nil
end

-- Rend bloquantes (ou non) les pièces « cœur » d'un accessoire.
function Props.setSolid(model: Instance, solid: boolean)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("PropCore") == true then
			descendant.CanCollide = solid
			descendant.CanQuery = solid
			descendant.CanTouch = solid
		end
	end
	model:SetAttribute("Solid", solid)
end

function Props.partCount(model: Instance): number
	local count = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

return Props
