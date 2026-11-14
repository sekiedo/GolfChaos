--!strict
--[[
	Course.LobbyExtras — décor « soirée en famille » de l'accueil : Clubhouse en bois et pierre (porche, auvent
	rayé, fenêtres, cheminée, enseigne), guirlandes lumineuses, auvents des stands et bacs à fleurs.
	Tout est procédural (aucun asset). Les pièces décoratives ne gênent ni la balle ni les joueurs :
	seuls les murs et le sol du Clubhouse sont solides, et il est posé hors des zones de jeu.

	  LobbyExtras.build(folder, origin, kioskPositions)
]]

local LobbyExtras = {}

local WOOD = Color3.fromRGB(176, 120, 72)
local WOOD_DARK = Color3.fromRGB(116, 78, 48)
local STONE = Color3.fromRGB(176, 172, 164)
local CREAM = Color3.fromRGB(246, 236, 214)
local ROOF = Color3.fromRGB(196, 78, 62)
local GLASS = Color3.fromRGB(150, 210, 240)
local WARM = Color3.fromRGB(255, 214, 140)
local STRIPES = { Color3.fromRGB(240, 82, 82), Color3.fromRGB(250, 248, 242) }
local BULBS = {
	Color3.fromRGB(255, 214, 120),
	Color3.fromRGB(255, 150, 120),
	Color3.fromRGB(150, 220, 255),
	Color3.fromRGB(190, 255, 160),
}

type Options = { solid: boolean?, shadow: boolean?, transparency: number?, shape: Enum.PartType? }

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, options: Options?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local solid = options ~= nil and options.solid == true
	p.CanCollide = solid
	p.CanQuery = solid
	p.CanTouch = false
	p.CastShadow = not (options ~= nil and options.shadow == false)
	if options ~= nil and options.transparency ~= nil then
		p.Transparency = options.transparency
	end
	if options ~= nil and options.shape ~= nil then
		p.Shape = options.shape
	end
	p.Parent = parent
	return p
end

local function bulb(parent: Instance, position: Vector3, color: Color3, light: boolean)
	local b = part(parent, "Ampoule", Vector3.one * 0.7, CFrame.new(position), color, Enum.Material.Neon, { shadow = false, shape = Enum.PartType.Ball })
	if light then
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = 9
		l.Brightness = 0.8
		l.Parent = b
	end
end

-- Guirlande entre deux points : câble en chaînette + ampoules colorées (une lumière sur trois).
local function garland(parent: Instance, from: Vector3, to: Vector3, sag: number, count: number)
	local previous = from
	for index = 1, count do
		local t = index / count
		local point = from:Lerp(to, t) - Vector3.new(0, 4 * sag * t * (1 - t), 0)
		local mid = (previous + point) / 2
		part(parent, "Cable", Vector3.new(0.12, 0.12, (point - previous).Magnitude), CFrame.lookAt(mid, point), WOOD_DARK, Enum.Material.Fabric, { shadow = false })
		if index < count then
			bulb(parent, point - Vector3.new(0, 0.5, 0), BULBS[(index % #BULBS) + 1], index % 3 == 0)
		end
		previous = point
	end
end

local function pole(parent: Instance, base: Vector3, height: number)
	part(parent, "PoteauGuirlande", Vector3.new(0.7, height, 0.7), CFrame.new(base + Vector3.new(0, height / 2, 0)), WOOD_DARK, Enum.Material.Wood, { solid = true })
end

local function buildClubhouse(folder: Folder, origin: Vector3)
	local house = Instance.new("Model")
	house.Name = "Clubhouse"
	house:SetAttribute("Surface", "Rock")
	local center = origin + Vector3.new(0, 0, 77)
	local width, depth, wallHeight = 40, 12, 11
	local frame = CFrame.new(center) -- porte côté -Z (vers la place)

	part(house, "Fondation", Vector3.new(width + 4, 1.4, depth + 4), frame * CFrame.new(0, 0.7, 0), STONE, Enum.Material.Cobblestone, { solid = true })
	-- Murs : planches sombres en bas, crépi crème en haut, façade percée d'une porte et de fenêtres.
	local base = 1.4
	part(house, "MurArriere", Vector3.new(width, wallHeight, 1), frame * CFrame.new(0, base + wallHeight / 2, depth / 2), CREAM, Enum.Material.SmoothPlastic, { solid = true })
	for _, side in { -1, 1 } do
		part(house, "MurCote", Vector3.new(1, wallHeight, depth), frame * CFrame.new(side * (width / 2 - 0.5), base + wallHeight / 2, 0), CREAM, Enum.Material.SmoothPlastic, { solid = true })
	end
	local doorWidth = 7
	local sideWidth = (width - doorWidth) / 2
	for _, side in { -1, 1 } do
		part(house, "Facade", Vector3.new(sideWidth, wallHeight, 1), frame * CFrame.new(side * (doorWidth / 2 + sideWidth / 2), base + wallHeight / 2, -depth / 2), CREAM, Enum.Material.SmoothPlastic, { solid = true })
		part(house, "Soubassement", Vector3.new(sideWidth + 0.2, 3, 1.3), frame * CFrame.new(side * (doorWidth / 2 + sideWidth / 2), base + 1.5, -depth / 2 - 0.15), WOOD, Enum.Material.WoodPlanks)
		-- Fenêtres à croisillons.
		for _, offset in { -7, 7 } do
			local wx = side * (doorWidth / 2 + sideWidth / 2) + offset * 0.45
			part(house, "Fenetre", Vector3.new(5, 4, 0.3), frame * CFrame.new(wx, base + 6, -depth / 2 - 0.55), GLASS, Enum.Material.Glass, { transparency = 0.35 })
			part(house, "Croisillon", Vector3.new(5.4, 0.3, 0.5), frame * CFrame.new(wx, base + 6, -depth / 2 - 0.7), WOOD_DARK, Enum.Material.Wood)
			part(house, "Croisillon", Vector3.new(0.3, 4.4, 0.5), frame * CFrame.new(wx, base + 6, -depth / 2 - 0.7), WOOD_DARK, Enum.Material.Wood)
			part(house, "Volet", Vector3.new(1.2, 4.2, 0.3), frame * CFrame.new(wx - 3.2, base + 6, -depth / 2 - 0.6), Color3.fromRGB(70, 150, 190), Enum.Material.Wood)
			part(house, "Volet", Vector3.new(1.2, 4.2, 0.3), frame * CFrame.new(wx + 3.2, base + 6, -depth / 2 - 0.6), Color3.fromRGB(70, 150, 190), Enum.Material.Wood)
		end
	end
	part(house, "LinteauPorte", Vector3.new(doorWidth, wallHeight - 8, 1), frame * CFrame.new(0, base + 8 + (wallHeight - 8) / 2, -depth / 2), CREAM, Enum.Material.SmoothPlastic, { solid = true })
	-- Porte ouverte sur un intérieur chaleureux (lumière chaude).
	part(house, "Interieur", Vector3.new(doorWidth - 0.4, 8, 0.4), frame * CFrame.new(0, base + 4, depth / 2 - 1), WARM, Enum.Material.Neon, { shadow = false })
	for _, side in { -1, 1 } do
		part(house, "MontantPorte", Vector3.new(0.6, 8.4, 0.8), frame * CFrame.new(side * doorWidth / 2, base + 4.2, -depth / 2 - 0.3), WOOD_DARK, Enum.Material.Wood)
	end
	part(house, "Seuil", Vector3.new(doorWidth + 2, 0.4, 3), frame * CFrame.new(0, 1.6, -depth / 2 - 1.5), STONE, Enum.Material.Cobblestone, { solid = true })

	-- Toit à deux pans (prismes) + faîtage + cheminée en pierre.
	local roofRise, overhang = 6, 2
	local halfRun = depth / 2 + overhang
	local slope = math.atan2(roofRise, halfRun)
	local slabLength = math.sqrt(roofRise * roofRise + halfRun * halfRun) + 0.4
	for _, side in { -1, 1 } do
		part(
			house,
			"Toit",
			Vector3.new(width + overhang * 2, 0.8, slabLength),
			frame * CFrame.new(0, base + wallHeight + roofRise / 2, side * halfRun / 2) * CFrame.Angles(side * slope, 0, 0),
			ROOF,
			Enum.Material.Slate
		)
	end
	part(house, "Faitage", Vector3.new(width + overhang * 2 + 0.6, 0.6, 1), frame * CFrame.new(0, base + wallHeight + roofRise + 0.2, 0), WOOD_DARK, Enum.Material.Wood)
	part(house, "Cheminee", Vector3.new(3, 8, 3), frame * CFrame.new(width / 2 - 6, base + wallHeight + 5, 2), STONE, Enum.Material.Brick)
	part(house, "ChemineeCouronne", Vector3.new(3.8, 0.6, 3.8), frame * CFrame.new(width / 2 - 6, base + wallHeight + 9.2, 2), WOOD_DARK, Enum.Material.Slate)

	-- Porche : deux poteaux, auvent rayé rouge et blanc, lanternes.
	local porchZ = -depth / 2 - 4
	for _, side in { -1, 1 } do
		part(house, "PoteauPorche", Vector3.new(0.9, 9, 0.9), frame * CFrame.new(side * 5.5, base + 4.5, porchZ), WOOD, Enum.Material.Wood, { solid = true })
		local lamp = part(house, "Lanterne", Vector3.new(1, 1.4, 1), frame * CFrame.new(side * 5.5, base + 7, porchZ - 0.8), WARM, Enum.Material.Neon, { shadow = false })
		local light = Instance.new("PointLight")
		light.Color = WARM
		light.Range = 20
		light.Brightness = 1.2
		light.Parent = lamp
	end
	for index = 1, 8 do
		local x = -5.6 + (index - 1) * 1.6
		part(house, "Auvent", Vector3.new(1.6, 0.4, 5.4), frame * CFrame.new(x + 0.8, base + 9.2, porchZ + 0.4) * CFrame.Angles(math.rad(-10), 0, 0), STRIPES[(index % 2) + 1], Enum.Material.Fabric)
	end
	-- Enseigne en bois suspendue : texte via SurfaceGui (aucune image).
	local sign = part(house, "Enseigne", Vector3.new(14, 3, 0.5), frame * CFrame.new(0, base + wallHeight - 1.2, -depth / 2 - 0.8), WOOD_DARK, Enum.Material.WoodPlanks)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "CLUBHOUSE"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(255, 226, 150)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui

	-- Bacs à fleurs sous les fenêtres.
	local colors = { Color3.fromRGB(255, 110, 150), Color3.fromRGB(255, 200, 60), Color3.fromRGB(190, 120, 240), Color3.fromRGB(255, 255, 255) }
	for _, x in { -15, -9, 9, 15 } do
		part(house, "Bac", Vector3.new(5, 1.2, 1.4), frame * CFrame.new(x, base + 3.6, -depth / 2 - 1.4), WOOD, Enum.Material.WoodPlanks)
		for flower = 1, 7 do
			part(house, "Fleur", Vector3.one * 0.8, frame * CFrame.new(x - 2.1 + (flower - 1) * 0.7, base + 4.5 + (flower % 2) * 0.25, -depth / 2 - 1.4), colors[(flower % #colors) + 1], Enum.Material.SmoothPlastic, { shadow = false, shape = Enum.PartType.Ball })
		end
	end
	house.Parent = folder
end

local function buildGarlands(folder: Folder, origin: Vector3, kiosks: { Vector3 })
	local group = Instance.new("Folder")
	group.Name = "Guirlandes"
	-- Anneau de poteaux autour de la place, reliés par des guirlandes.
	local count, radius, height = 12, 44, 12
	local posts: { Vector3 } = {}
	for index = 1, count do
		local angle = (index - 0.5) / count * math.pi * 2
		local base = origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		-- Évite l'axe des stands : pas de poteau à moins de 7 studs d'un stand.
		local clear = true
		for _, k in kiosks do
			if (Vector3.new(base.X, 0, base.Z) - Vector3.new(origin.X + k.X, 0, origin.Z + k.Z)).Magnitude < 7 then
				clear = false
			end
		end
		if clear then
			pole(group, base, height)
			table.insert(posts, base + Vector3.new(0, height, 0))
		end
	end
	for index, top in posts do
		local nextTop = posts[(index % #posts) + 1]
		if (nextTop - top).Magnitude < 34 then
			garland(group, top, nextTop, 2.2, 7)
		end
	end
	-- Fanions colorés entre la fontaine et la place.
	group.Parent = folder
end

local function buildAwnings(folder: Folder, origin: Vector3, kiosks: { Vector3 })
	local group = Instance.new("Folder")
	group.Name = "Auvents"
	for _, position in kiosks do
		local base = origin + position
		local toCenter = (Vector3.new(origin.X, base.Y, origin.Z) - base).Unit
		local frame = CFrame.lookAt(base + Vector3.new(0, 8.6, 0) + toCenter * 2.4, base + Vector3.new(0, 8.6, 0) + toCenter * 6) * CFrame.Angles(math.rad(-12), 0, 0)
		for index = 1, 8 do
			part(group, "Lamelle", Vector3.new(1.3, 0.3, 4.6), frame * CFrame.new(-5.2 + (index - 0.5) * 1.3, 0, 0), STRIPES[(index % 2) + 1], Enum.Material.Fabric)
		end
	end
	group.Parent = folder
end

function LobbyExtras.build(folder: Folder, origin: Vector3, kioskPositions: { Vector3 })
	buildClubhouse(folder, origin)
	buildGarlands(folder, origin, kioskPositions)
	buildAwnings(folder, origin, kioskPositions)
end

return LobbyExtras
