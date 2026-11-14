--!strict
--[[
	Catalog/Faces : cosmétiques de l'emplacement « Face » (visages dessinés, coiffures, lunettes, moustaches,
	cache-œil, nez) — 1 visage gratuit par défaut + 15 objets.

	Construction (contrat : Cosmetics/init.luau ; primitives d'équité : Cosmetics/Build.luau) :
	  - build(variant) -> Accessory. Son Handle EST la plaque du visage : une plaque transparente fine posée juste
	    devant la tête (attachement FaceFrontAttachment). Le visage y est dessiné par Build.face (SurfaceGui,
	    aucune image) ; les volumes (lunettes, nez, cheveux...) sont des pièces soudées au Handle ;
	    Build.finalize est appelé sur chaque résultat.
	  - Chaque objet forme un visage COMPLET (traits dessinés + accessoire). L'Accessory porte l'attribut
	    HideDefaultFace = true : CosmeticService doit masquer le décalque « face » d'origine de la tête, sinon
	    il transparaît entre les traits dessinés.
	  - Les coiffures utilisent aussi FaceFrontAttachment (un seul attachement par accessoire) : leurs volumes
	    sont placés par rapport au centre de la tête R15 par défaut (≈ 1.2 × 1.2 × 1.2, face avant à 0.6).
	  - Étincelles (objets légendaires) : texture intégrée du moteur uniquement ; l'émetteur porte l'attribut
	    CosmeticFx = true pour que le client puisse le couper (effets réduits, qualité basse).
	  - Limite Roblox : ni les SurfaceGui ni les particules ne s'affichent dans un ViewportFrame (aperçu à faire
	    dans le monde 3D).

	Repères :
	  - Traits dessinés : (u, v) de 0 à 1 vus DE FACE (u vers la droite de l'écran, v vers le bas) ; la droite
	    de l'écran correspond à la gauche du personnage ; 1 unité = 1 stud (plaque 1 × 1).
	  - front(u, v, d, rot) : CFrame (repère du Handle) d'une pièce centrée d studs devant le point (u, v),
	    tournée de rot degrés dans le plan du visage (sens horaire vu de face, comme les traits dessinés).
	  - head(x, y, z) : CFrame d'un point exprimé depuis le centre de la tête (X = droite du personnage,
	    Y = haut, Z = arrière ; la face avant de la tête est en Z = -0.6).
]]

local Build = require(script.Parent.Parent.Build)
local Cosmetics = require(script.Parent.Parent)

type CosmeticDef = Cosmetics.CosmeticDef
type Variant = Cosmetics.Variant
type Rarity = Cosmetics.Rarity
type Unlock = Cosmetics.Unlock

-- Couleurs d'une variante (l'ordre des couleurs est propre à chaque objet).
type Palette = { Color3 }
-- Dessine le visage et ajoute les volumes sur le Handle, avec les couleurs de la variante choisie.
type Design = (handle: Part, colors: Palette) -> ()
-- Trait dessiné (Frame arrondie du SurfaceGui) : centre (u, v) et taille (w, h) en fraction de plaque.
type Mark = {
	u: number,
	v: number,
	w: number,
	h: number,
	color: Color3,
	corner: number?, -- arrondi 0..1 (0.5 = pilule ou cercle)
	rotation: number?, -- degrés, sens horaire
	alpha: number?, -- transparence du fond (0 = opaque)
}
type MouthOptions = { teeth: boolean?, tongue: Color3?, tongueOut: boolean? }
type Spec = {
	id: string,
	rarity: Rarity,
	price: number,
	unlock: Unlock?, -- par défaut : achat au prix indiqué
	palettes: { Palette }, -- une palette par variante (la première est la variante par défaut)
	tags: { string },
	design: Design,
}

--------------------------------------------------------------------------------
-- Gabarit
--------------------------------------------------------------------------------

local PLATE_SIZE = Vector3.new(1, 1, 0.02) -- plaque du visage (= Handle, transparente)
local PLATE_GAP = 0.03 -- jeu entre la face avant de la tête et le dos de la plaque
local ATTACH_Z = PLATE_SIZE.Z / 2 + PLATE_GAP -- position de FaceFrontAttachment dans le repère du Handle
local HEAD_FRONT = 0.6 -- distance du centre de la tête à FaceFrontAttachment (tête R15 par défaut)

local EYE_U1 = 0.36 -- œil à gauche de l'écran (œil droit du personnage)
local EYE_U2 = 0.64 -- œil à droite de l'écran (œil gauche du personnage)
local EYE_V = 0.42

local FORWARD = CFrame.Angles(0, math.rad(90), 0) -- couche l'axe d'un cylindre vers l'avant (disques, nez)
local FLIP = CFrame.Angles(0, math.pi, 0) -- demi-tour (biseau dont la pente regarde vers l'arrière)
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

-- Couleurs communes.
local INK = Color3.fromRGB(40, 30, 38)
local WHITE = Color3.fromRGB(255, 255, 255)
local MOUTH = Color3.fromRGB(92, 30, 44)
local TEETH = Color3.fromRGB(252, 250, 242)
local TONGUE = Color3.fromRGB(240, 112, 132)
local BLUSH = Color3.fromRGB(255, 130, 145)
local DROP = Color3.fromRGB(120, 200, 255)
local FRECKLE = Color3.fromRGB(190, 120, 90)
local SCAR = Color3.fromRGB(215, 115, 115)
local GOLD = Color3.fromRGB(255, 196, 60)
local COAL = Color3.fromRGB(32, 32, 36)
local GLASS_TINT = Color3.fromRGB(215, 235, 255)
local RUBBER = Color3.fromRGB(30, 30, 32)
local FAKE_NOSE = Color3.fromRGB(240, 175, 155)

--------------------------------------------------------------------------------
-- Outils de construction
--------------------------------------------------------------------------------

-- Couleurs de la variante demandée (repli sur la variante 1 si l'indice est inconnu).
local function pick(palettes: { Palette }, variant: number?): Palette
	return palettes[variant or 1] or palettes[1]
end

local function front(u: number, v: number, d: number, rot: number?): CFrame
	local cframe = CFrame.new((0.5 - u) * PLATE_SIZE.X, (0.5 - v) * PLATE_SIZE.Y, -PLATE_SIZE.Z / 2 - d)
	if rot then
		cframe *= CFrame.Angles(0, 0, math.rad(rot))
	end
	return cframe
end

local function head(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z + HEAD_FRONT + ATTACH_Z)
end

-- Barre tendue entre deux points du repère du Handle (section width × height).
local function beam(handle: BasePart, from: Vector3, to: Vector3, width: number, height: number, color: Color3): BasePart
	local bar = Build.block(Vector3.new(width, height, (to - from).Magnitude), color)
	return Build.attach(handle, bar, CFrame.lookAt((from + to) / 2, to))
end

-- Branche de lunettes en deux segments (charnière vers l'extérieur, puis le long de la tête jusqu'à l'oreille)
-- pour contourner la courbure de la tête. side = 1 : côté droit du personnage (gauche de l'écran).
local function temple(handle: BasePart, hinge: Vector3, side: number, y: number, color: Color3)
	local knee = head(side * 0.5, y, -0.45).Position
	local ear = head(side * 0.62, y - 0.02, 0).Position
	beam(handle, hinge, knee, 0.025, 0.03, color)
	beam(handle, knee, ear, 0.025, 0.03, color)
end

-- Étincelles discrètes autour d'une pièce (texture intégrée du moteur, aucune connexion).
local function addSparkles(part: BasePart, color: Color3, rate: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = "Etincelles"
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Etincelles"
	emitter.Texture = SPARKLE_TEXTURE
	emitter.Color = ColorSequence.new(color, WHITE)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.14), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(0.2, 0.6)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter:SetAttribute("CosmeticFx", true)
	emitter.Parent = attachment
end

--------------------------------------------------------------------------------
-- Traits dessinés
--------------------------------------------------------------------------------

local function mark(u: number, v: number, w: number, h: number, color: Color3, corner: number?, rotation: number?, alpha: number?): Mark
	return { u = u, v = v, w = w, h = h, color = color, corner = corner, rotation = rotation, alpha = alpha }
end

-- Dessine les traits sur la face avant du Handle, dans l'ordre de la liste (les suivants passent devant).
local function paint(handle: BasePart, marks: { Mark })
	local shapes: { Build.FaceShape } = {}
	for index, item in marks do
		shapes[index] = {
			position = UDim2.fromScale(item.u, item.v),
			size = UDim2.fromScale(item.w, item.h),
			color = item.color,
			corner = item.corner,
			rotation = item.rotation,
		}
	end
	local gui = Build.face(handle, shapes)
	for index, item in marks do
		local frame = gui:FindFirstChild("Trait" .. index)
		if frame and frame:IsA("GuiObject") then
			frame.ZIndex = index
			local alpha = item.alpha
			if alpha then
				frame.BackgroundTransparency = alpha
			end
		end
	end
end

-- Œil ovale (pilule) avec reflet blanc.
local function ovalEye(list: { Mark }, u: number, v: number, w: number, h: number, color: Color3)
	table.insert(list, mark(u, v, w, h, color, 0.5))
	table.insert(list, mark(u - w * 0.2, v - h * 0.22, w * 0.4, w * 0.4, WHITE, 1))
end

local function roundEye(list: { Mark }, u: number, v: number, size: number, color: Color3)
	ovalEye(list, u, v, size, size, color)
end

-- Œil mi-clos : haut plat (paupière), bas arrondi.
local function halfEye(list: { Mark }, u: number, v: number, w: number, h: number, color: Color3)
	table.insert(list, mark(u, v, w, h, color, 0.5))
	table.insert(list, mark(u, v - h * 0.25, w, h * 0.5, color, 0.15))
	table.insert(list, mark(u, v - h * 0.5, w * 1.25, h * 0.22, color, 0.5))
	table.insert(list, mark(u - w * 0.2, v + h * 0.05, w * 0.3, w * 0.3, WHITE, 1))
end

-- Œil fermé en accent circonflexe « ^ » (joie, clin d'œil) ; (u, v) = sommet.
local function caretEye(list: { Mark }, u: number, v: number, size: number, thickness: number, color: Color3)
	local angle = math.rad(35)
	local dx, dy = size / 2 * math.cos(angle), size / 2 * math.sin(angle)
	table.insert(list, mark(u - dx, v + dy, size, thickness, color, 0.5, -35))
	table.insert(list, mark(u + dx, v + dy, size, thickness, color, 0.5, 35))
end

-- Sourcil : rotation positive = extrémité droite (à l'écran) plus basse.
local function brow(list: { Mark }, u: number, v: number, w: number, thickness: number, rotation: number, color: Color3)
	table.insert(list, mark(u, v, w, thickness, color, 0.5, rotation))
end

local function blush(list: { Mark }, v: number, alpha: number)
	table.insert(list, mark(0.25, v, 0.12, 0.06, BLUSH, 0.5, 0, alpha))
	table.insert(list, mark(0.75, v, 0.12, 0.06, BLUSH, 0.5, 0, alpha))
end

-- Sourire fermé en arc (trois segments arrondis).
local function smileArc(list: { Mark }, u: number, v: number, width: number, thickness: number, color: Color3)
	local segment = width / 3
	local side = segment * 1.1
	local angle = math.rad(25)
	local dx, dy = side / 2 * math.cos(angle), side / 2 * math.sin(angle)
	table.insert(list, mark(u, v, segment, thickness, color, 0.5))
	table.insert(list, mark(u - segment / 2 - dx, v - dy, side, thickness, color, 0.5, 25))
	table.insert(list, mark(u + segment / 2 + dx, v - dy, side, thickness, color, 0.5, -25))
end

-- Sourire en coin (relevé à droite de l'écran).
local function smirk(list: { Mark }, u: number, v: number, color: Color3)
	table.insert(list, mark(u - 0.01, v, 0.13, 0.03, color, 0.5, -6))
	table.insert(list, mark(u + 0.074, v - 0.023, 0.05, 0.03, color, 0.5, -40))
end

-- Bouche ondulée (gêne) : trois segments en zigzag.
local function wavyMouth(list: { Mark }, u: number, v: number, segment: number, thickness: number, color: Color3)
	for index, offset in { -1, 0, 1 } do
		local rotation = if index == 2 then -22 else 22
		table.insert(list, mark(u + offset * segment, v, segment * 1.2, thickness, color, 0.5, rotation))
	end
end

-- Bouche ouverte : haut plat, bas arrondi ; dents du haut et langue (dedans ou tirée) facultatives.
local function openMouth(list: { Mark }, u: number, v: number, w: number, h: number, options: MouthOptions?)
	local opts: MouthOptions = options or {}
	table.insert(list, mark(u, v, w, h, MOUTH, 0.5))
	table.insert(list, mark(u, v - h * 0.25, w, h * 0.5, MOUTH, 0.2))
	local tongue = opts.tongue
	if tongue then
		if opts.tongueOut then
			table.insert(list, mark(u, v + h * 0.45, w * 0.46, h * 0.95, tongue, 0.5))
			table.insert(list, mark(u, v + h * 0.55, w * 0.05, h * 0.45, tongue:Lerp(Color3.new(0, 0, 0), 0.25), 0.5))
		else
			table.insert(list, mark(u, v + h * 0.24, w * 0.5, h * 0.38, tongue, 0.5))
		end
	end
	if opts.teeth then
		table.insert(list, mark(u, v - h * 0.36, w * 0.78, h * 0.25, TEETH, 0.4))
	end
end

-- Dents serrées (concentration).
local function gritTeeth(list: { Mark }, u: number, v: number, w: number, h: number)
	table.insert(list, mark(u, v, w + 0.03, h + 0.03, INK, 0.35))
	table.insert(list, mark(u, v, w, h, TEETH, 0.3))
	table.insert(list, mark(u, v, w, 0.012, INK, 0))
	for _, offset in { -0.25, 0, 0.25 } do
		table.insert(list, mark(u + w * offset, v, 0.012, h, INK, 0))
	end
end

-- Goutte de sueur (rond + pointe en losange).
local function sweatDrop(list: { Mark }, u: number, v: number, size: number)
	table.insert(list, mark(u, v + size * 0.15, size, size, DROP, 1))
	table.insert(list, mark(u, v - size * 0.12, size * 0.6, size * 0.6, DROP, 0.1, 45))
end

-- Étoile à huit branches (deux carrés croisés).
local function star(list: { Mark }, u: number, v: number, size: number, color: Color3)
	table.insert(list, mark(u, v, size, size, color, 0.12))
	table.insert(list, mark(u, v, size, size, color, 0.12, 45))
end

-- Scintillement à quatre branches.
local function twinkle(list: { Mark }, u: number, v: number, size: number, color: Color3)
	table.insert(list, mark(u, v, size * 0.28, size, color, 0.5))
	table.insert(list, mark(u, v, size, size * 0.28, color, 0.5))
end

local FRECKLE_DOTS = { Vector2.new(0.24, 0.56), Vector2.new(0.28, 0.6), Vector2.new(0.22, 0.615) } -- joue gauche (u, v)
local function freckles(list: { Mark })
	for _, dot in FRECKLE_DOTS do
		table.insert(list, mark(dot.X, dot.Y, 0.022, 0.022, FRECKLE, 1))
		table.insert(list, mark(1 - dot.X, dot.Y, 0.022, 0.022, FRECKLE, 1))
	end
end

--------------------------------------------------------------------------------
-- Visages dessinés
--------------------------------------------------------------------------------

-- Bonne Bouille (gratuit) : 1 = yeux.
local function drawFriendly(handle: Part, colors: Palette)
	local marks: { Mark } = {}
	blush(marks, 0.58, 0.35)
	brow(marks, EYE_U1, 0.29, 0.11, 0.028, 0, INK)
	brow(marks, EYE_U2, 0.29, 0.11, 0.028, 0, INK)
	ovalEye(marks, EYE_U1, EYE_V, 0.1, 0.16, colors[1])
	ovalEye(marks, EYE_U2, EYE_V, 0.1, 0.16, colors[1])
	smileArc(marks, 0.5, 0.68, 0.3, 0.035, INK)
	paint(handle, marks)
end

-- Tire-Langue : 1 = langue.
local function drawCheeky(handle: Part, colors: Palette)
	local marks: { Mark } = {}
	blush(marks, 0.57, 0.4)
	brow(marks, EYE_U1, 0.3, 0.1, 0.028, 12, INK)
	brow(marks, EYE_U2, 0.3, 0.1, 0.028, -12, INK)
	caretEye(marks, EYE_U1, 0.4, 0.09, 0.032, INK)
	caretEye(marks, EYE_U2, 0.4, 0.09, 0.032, INK)
	openMouth(marks, 0.5, 0.65, 0.24, 0.13, { teeth = true, tongue = colors[1], tongueOut = true })
	paint(handle, marks)
end

-- Mode Compétition : 1 = yeux.
local function drawGameFace(handle: Part, colors: Palette)
	local marks: { Mark } = {}
	sweatDrop(marks, 0.77, 0.3, 0.06)
	roundEye(marks, EYE_U1, 0.43, 0.1, colors[1])
	roundEye(marks, EYE_U2, 0.43, 0.1, colors[1])
	brow(marks, EYE_U1, 0.32, 0.15, 0.042, 18, INK)
	brow(marks, EYE_U2, 0.32, 0.15, 0.042, -18, INK)
	gritTeeth(marks, 0.5, 0.67, 0.27, 0.085)
	paint(handle, marks)
end

-- Yeux Étoilés : 1 = étoiles et scintillements.
local function drawStarEyes(handle: Part, colors: Palette)
	local starColor = colors[1]
	local marks: { Mark } = {}
	blush(marks, 0.6, 0.35)
	twinkle(marks, 0.2, 0.24, 0.07, starColor)
	twinkle(marks, 0.81, 0.21, 0.05, starColor)
	twinkle(marks, 0.85, 0.33, 0.035, starColor)
	brow(marks, EYE_U1, 0.27, 0.09, 0.025, -10, INK)
	brow(marks, EYE_U2, 0.27, 0.09, 0.025, 10, INK)
	star(marks, EYE_U1, 0.43, 0.17, starColor)
	star(marks, EYE_U2, 0.43, 0.17, starColor)
	table.insert(marks, mark(EYE_U1 - 0.03, 0.4, 0.045, 0.045, WHITE, 1))
	table.insert(marks, mark(EYE_U2 - 0.03, 0.4, 0.045, 0.045, WHITE, 1))
	openMouth(marks, 0.5, 0.69, 0.2, 0.14, { tongue = TONGUE })
	paint(handle, marks)
end

--------------------------------------------------------------------------------
-- Nez
--------------------------------------------------------------------------------

-- Nez Pouet : 1 = nez.
local function drawClownNose(handle: Part, colors: Palette)
	local marks: { Mark } = {}
	blush(marks, 0.6, 0.4)
	brow(marks, EYE_U1, 0.27, 0.1, 0.026, -10, INK)
	brow(marks, EYE_U2, 0.27, 0.1, 0.026, 10, INK)
	ovalEye(marks, EYE_U1, 0.41, 0.09, 0.15, INK)
	ovalEye(marks, EYE_U2, 0.41, 0.09, 0.15, INK)
	openMouth(marks, 0.5, 0.69, 0.3, 0.14, { teeth = true, tongue = TONGUE })
	paint(handle, marks)

	local nose = Build.ball(0.2, colors[1])
	nose.Reflectance = 0.12
	Build.attach(handle, nose, front(0.5, 0.52, 0.09))
	Build.attach(handle, Build.ball(0.055, WHITE), front(0.47, 0.49, 0.17)) -- reflet
end

-- Nez Carotte : 1 = carotte, 2 = cerclage.
local COAL_SMILE = { -- sourire en morceaux de charbon (u, v)
	Vector2.new(0.38, 0.655),
	Vector2.new(0.44, 0.685),
	Vector2.new(0.5, 0.695),
	Vector2.new(0.56, 0.685),
	Vector2.new(0.62, 0.655),
}
local function drawCarrotNose(handle: Part, colors: Palette)
	local marks: { Mark } = {}
	blush(marks, 0.6, 0.25)
	roundEye(marks, 0.37, EYE_V, 0.09, COAL)
	roundEye(marks, 0.63, EYE_V, 0.09, COAL)
	for _, dot in COAL_SMILE do
		table.insert(marks, mark(dot.X, dot.Y, 0.045, 0.045, COAL, 1))
	end
	paint(handle, marks)

	-- Carotte en trois tronçons de plus en plus fins (pointe vers l'avant).
	local function piece(length: number, diameter: number, d: number, color: Color3)
		Build.attach(handle, Build.cylinder(length, diameter, color), front(0.5, 0.53, d) * FORWARD)
	end
	piece(0.12, 0.15, 0.06, colors[1])
	piece(0.014, 0.156, 0.1, colors[2])
	piece(0.12, 0.105, 0.17, colors[1])
	piece(0.1, 0.06, 0.275, colors[1])
end

--------------------------------------------------------------------------------
-- Moustaches
--------------------------------------------------------------------------------

-- Moustache Guidon : 1 = poils (moustache et sourcils).
local function drawHandlebar(handle: Part, colors: Palette)
	local hair = colors[1]
	local marks: { Mark } = {}
	blush(marks, 0.6, 0.3)
	brow(marks, EYE_U1, 0.29, 0.12, 0.034, 0, hair)
	brow(marks, EYE_U2, 0.29, 0.12, 0.034, 0, hair)
	ovalEye(marks, EYE_U1, EYE_V, 0.09, 0.14, INK)
	ovalEye(marks, EYE_U2, EYE_V, 0.09, 0.14, INK)
	smileArc(marks, 0.5, 0.69, 0.16, 0.028, INK)
	paint(handle, marks)

	Build.attach(handle, Build.block(Vector3.new(0.16, 0.065, 0.06), hair), front(0.5, 0.56, 0.03))
	for _, side in { -1, 1 } do
		-- side = -1 : branche à gauche de l'écran ; les branches remontent vers l'extérieur puis s'enroulent.
		Build.attach(handle, Build.block(Vector3.new(0.15, 0.055, 0.05), hair), front(0.5 + side * 0.13, 0.55, 0.025, -side * 15))
		Build.attach(handle, Build.ball(0.075, hair), front(0.5 + side * 0.22, 0.5, 0.025))
		Build.attach(handle, Build.ball(0.05, hair), front(0.5 + side * 0.225, 0.45, 0.022))
	end
end

--------------------------------------------------------------------------------
-- Coiffures
--------------------------------------------------------------------------------

-- Mèche Rabattue : 1 = cheveux.
local COMBOVER_STRANDS = {
	{ z = -0.3, length = 0.56 },
	{ z = -0.15, length = 0.8 },
	{ z = 0, length = 0.9 },
	{ z = 0.15, length = 0.84 },
	{ z = 0.3, length = 0.62 },
}
local function drawCombover(handle: Part, colors: Palette)
	local hair = colors[1]
	local marks: { Mark } = {}
	brow(marks, EYE_U1, 0.3, 0.1, 0.026, -10, INK)
	brow(marks, EYE_U2, 0.3, 0.1, 0.026, 10, INK)
	ovalEye(marks, EYE_U1, 0.43, 0.09, 0.14, INK)
	ovalEye(marks, EYE_U2, 0.43, 0.09, 0.14, INK)
	wavyMouth(marks, 0.5, 0.68, 0.055, 0.03, INK)
	sweatDrop(marks, 0.76, 0.29, 0.065)
	paint(handle, marks)

	-- Couronne (côtés et nuque) : cylindre décalé vers l'arrière, masqué devant par la tête.
	Build.attach(handle, Build.cylinder(0.32, 1.24, hair), head(0, 0.24, 0.12) * Build.UP)
	-- Mèches rabattues d'un côté à l'autre du crâne.
	for _, strand in COMBOVER_STRANDS do
		local cframe = head(-0.03, 0.61, strand.z) * CFrame.Angles(0, math.rad(6), 0)
		Build.attach(handle, Build.block(Vector3.new(strand.length, 0.04, 0.085), hair), cframe)
	end
end

-- Crête Punk : 1 = pointes, 2 = base.
local MOHAWK_SPIKES = {
	{ z = -0.38, height = 0.36 },
	{ z = -0.19, height = 0.5 },
	{ z = 0, height = 0.52 },
	{ z = 0.19, height = 0.44 },
	{ z = 0.36, height = 0.3 },
}
local function drawMohawk(handle: Part, colors: Palette)
	local marks: { Mark } = {}
	brow(marks, EYE_U1, 0.32, 0.11, 0.032, 10, INK)
	brow(marks, EYE_U2, 0.27, 0.11, 0.032, -8, INK)
	halfEye(marks, EYE_U1, 0.43, 0.11, 0.1, INK)
	halfEye(marks, EYE_U2, 0.43, 0.11, 0.1, INK)
	smirk(marks, 0.5, 0.68, INK)
	paint(handle, marks)

	Build.attach(handle, Build.block(Vector3.new(0.14, 0.12, 1), colors[2]), head(0, 0.58, 0))
	-- Pointes en dents de scie : face verticale à l'arrière, pente vers l'avant (crête rejetée en arrière).
	for _, spike in MOHAWK_SPIKES do
		Build.attach(handle, Build.wedge(Vector3.new(0.12, spike.height, 0.26), colors[1]), head(0, 0.62 + spike.height / 2, spike.z))
	end
end

-- Banane Gominée : 1 = cheveux, 2 = peigne.
local function drawPompadour(handle: Part, colors: Palette)
	local hair = colors[1]
	local marks: { Mark } = {}
	brow(marks, EYE_U1, 0.28, 0.11, 0.03, -6, INK)
	brow(marks, EYE_U2, 0.31, 0.11, 0.03, 4, INK)
	ovalEye(marks, EYE_U1, 0.43, 0.1, 0.15, INK)
	caretEye(marks, EYE_U2, 0.42, 0.09, 0.03, INK) -- clin d'œil
	openMouth(marks, 0.53, 0.67, 0.24, 0.11, { teeth = true })
	twinkle(marks, 0.675, 0.6, 0.06, WHITE) -- sourire étincelant
	paint(handle, marks)

	local function glossy(part: BasePart, cframe: CFrame)
		part.Reflectance = 0.12 -- reflet du gel
		Build.attach(handle, part, cframe)
	end
	glossy(Build.cylinder(0.24, 1.26, hair), head(0, 0.54, 0.02) * Build.UP) -- calotte
	glossy(Build.cylinder(0.4, 1.24, hair), head(0, 0.26, 0.12) * Build.UP) -- côtés et nuque
	glossy(Build.cylinder(1, 0.44, hair), head(0, 0.72, -0.44)) -- rouleau de la banane
	glossy(Build.wedge(Vector3.new(0.98, 0.3, 0.62), hair), head(0, 0.79, -0.1) * FLIP) -- dessus en pente
	-- Peigne oublié dans la banane.
	local comb = head(0.36, 0.9, -0.3) * CFrame.Angles(0, math.rad(-20), math.rad(28))
	Build.attach(handle, Build.block(Vector3.new(0.4, 0.05, 0.035), colors[2]), comb)
	Build.attach(handle, Build.block(Vector3.new(0.36, 0.08, 0.012), colors[2]), comb * CFrame.new(0, -0.06, 0))
end

--------------------------------------------------------------------------------
-- Lunettes et accessoires des yeux
--------------------------------------------------------------------------------

-- Binocles du Premier de la Classe : 1 = monture, 2 = teinte des verres.
local function drawNerdGlasses(handle: Part, colors: Palette)
	local frameColor, tint = colors[1], colors[2]
	local marks: { Mark } = {}
	freckles(marks)
	brow(marks, EYE_U1, 0.265, 0.1, 0.026, 0, INK)
	brow(marks, EYE_U2, 0.265, 0.1, 0.026, 0, INK)
	ovalEye(marks, EYE_U1, EYE_V, 0.11, 0.15, INK) -- grands yeux (effet loupe)
	ovalEye(marks, EYE_U2, EYE_V, 0.11, 0.15, INK)
	smileArc(marks, 0.5, 0.68, 0.21, 0.03, INK)
	paint(handle, marks)

	local halfW, halfH, rim, depth = 0.1, 0.09, 0.03, 0.035
	for _, u in { EYE_U1, EYE_U2 } do
		local lens = Build.block(Vector3.new(halfW * 2, halfH * 2, 0.012), tint, Enum.Material.Glass)
		lens.Transparency = 0.6
		Build.attach(handle, lens, front(u, EYE_V, 0.025))
		for _, sign in { -1, 1 } do
			Build.attach(handle, Build.block(Vector3.new((halfW + rim) * 2, rim, depth), frameColor), front(u, EYE_V + sign * (halfH + rim / 2), 0.03))
			Build.attach(handle, Build.block(Vector3.new(rim, halfH * 2, depth), frameColor), front(u + sign * (halfW + rim / 2), EYE_V, 0.03))
		end
	end
	Build.attach(handle, Build.block(Vector3.new(0.06, 0.025, 0.03), frameColor), front(0.5, EYE_V - 0.03, 0.03)) -- pont
	temple(handle, front(EYE_U1 - halfW - rim, EYE_V - halfH, 0.03).Position, 1, 0.16, frameColor)
	temple(handle, front(EYE_U2 + halfW + rim, EYE_V - halfH, 0.03).Position, -1, 0.16, frameColor)
end

-- Kit Incognito : 1 = poils (sourcils et moustache).
local function drawDisguise(handle: Part, colors: Palette)
	local hair = colors[1]
	local marks: { Mark } = {}
	roundEye(marks, EYE_U1 + 0.025, 0.43, 0.06, INK) -- regard en coin, méfiant
	roundEye(marks, EYE_U2 + 0.025, 0.43, 0.06, INK)
	table.insert(marks, mark(0.5, 0.745, 0.07, 0.022, INK, 0.5))
	paint(handle, marks)

	-- Lunettes à grosse monture haute (verres sans cerclage en bas).
	for _, u in { EYE_U1, EYE_U2 } do
		local lens = Build.block(Vector3.new(0.21, 0.16, 0.012), GLASS_TINT, Enum.Material.Glass)
		lens.Transparency = 0.5
		Build.attach(handle, lens, front(u, 0.43, 0.025))
	end
	Build.attach(handle, Build.block(Vector3.new(0.6, 0.06, 0.045), RUBBER), front(0.5, 0.33, 0.035))
	temple(handle, front(0.205, 0.33, 0.035).Position, 1, 0.17, RUBBER)
	temple(handle, front(0.795, 0.33, 0.035).Position, -1, 0.17, RUBBER)
	-- Sourcils broussailleux.
	Build.attach(handle, Build.block(Vector3.new(0.2, 0.055, 0.05), hair), front(EYE_U1, 0.285, 0.05, 8))
	Build.attach(handle, Build.block(Vector3.new(0.2, 0.055, 0.05), hair), front(EYE_U2, 0.285, 0.05, -8))
	-- Faux nez et moustache.
	Build.attach(handle, Build.ball(0.12, FAKE_NOSE), front(0.5, 0.45, 0.06))
	Build.attach(handle, Build.ball(0.2, FAKE_NOSE), front(0.5, 0.55, 0.1))
	Build.attach(handle, Build.block(Vector3.new(0.32, 0.085, 0.07), hair), front(0.5, 0.66, 0.05))
	Build.attach(handle, Build.ball(0.1, hair), front(0.34, 0.67, 0.05))
	Build.attach(handle, Build.ball(0.1, hair), front(0.66, 0.67, 0.05))
end

-- Cache-Œil du Cogneur : 1 = cache, 2 = lanières, 3 = emblème.
local function drawEyepatch(handle: Part, colors: Palette)
	local patchColor, strapColor, emblem = colors[1], colors[2], colors[3]
	local marks: { Mark } = {}
	-- Cicatrice (en partie sous le cache) avec deux points de suture.
	table.insert(marks, mark(EYE_U1, EYE_V, 0.025, 0.44, SCAR, 0.5, 15))
	table.insert(marks, mark(0.408, 0.239, 0.07, 0.016, SCAR, 0.5, 15))
	table.insert(marks, mark(0.312, 0.601, 0.07, 0.016, SCAR, 0.5, 15))
	brow(marks, EYE_U1, 0.27, 0.13, 0.04, 18, INK)
	brow(marks, EYE_U2, 0.31, 0.14, 0.04, -18, INK)
	roundEye(marks, EYE_U2, 0.43, 0.1, INK)
	openMouth(marks, 0.52, 0.68, 0.26, 0.12, { teeth = true })
	table.insert(marks, mark(0.47, 0.637, 0.035, 0.03, GOLD, 0.2)) -- dent en or
	paint(handle, marks)

	Build.attach(handle, Build.cylinder(0.03, 0.27, patchColor), front(EYE_U1, EYE_V, 0.025) * FORWARD)
	-- Emblème : deux clubs de golf croisés.
	for _, angle in { 40, -40 } do
		local shaft = front(EYE_U1, EYE_V, 0.045, angle)
		local side = if angle > 0 then 1 else -1
		Build.attach(handle, Build.block(Vector3.new(0.016, 0.15, 0.01), emblem), shaft)
		Build.attach(handle, Build.block(Vector3.new(0.045, 0.024, 0.012), emblem), shaft * CFrame.new(side * 0.014, -0.072, 0))
	end
	-- Lanières : vers l'oreille droite, et en travers du front jusqu'au côté gauche de la tête.
	local strap = 0.032
	beam(handle, front(EYE_U1 - 0.13, 0.41, 0.015).Position, head(0.61, 0.12, -0.06).Position, strap, strap, strapColor)
	local forehead = head(-0.3, 0.46, -0.56).Position
	local sidePoint = head(-0.52, 0.42, -0.36).Position
	beam(handle, front(EYE_U1 + 0.09, 0.32, 0.015).Position, forehead, strap, strap, strapColor)
	beam(handle, forehead, sidePoint, strap, strap, strapColor)
	beam(handle, sidePoint, head(-0.62, 0.34, 0).Position, strap, strap, strapColor)
end

-- Lunettes Essuie-Glaces : 1 = monture, 2 = verres miroir.
local function drawWiperShades(handle: Part, colors: Palette)
	local frameColor, lensColor = colors[1], colors[2]
	local marks: { Mark } = {}
	brow(marks, EYE_U1, 0.235, 0.12, 0.03, -6, INK)
	brow(marks, EYE_U2, 0.235, 0.12, 0.03, 6, INK)
	smirk(marks, 0.5, 0.68, INK)
	paint(handle, marks)

	for _, u in { 0.35, 0.65 } do
		local lens = Build.block(Vector3.new(0.27, 0.19, 0.03), lensColor)
		lens.Reflectance = 0.35
		Build.attach(handle, lens, front(u, 0.43, 0.03))
		-- Essuie-glace : bras incliné depuis un pivot au bas du verre.
		Build.attach(handle, Build.block(Vector3.new(0.02, 0.17, 0.012), RUBBER), front(u + 0.049, 0.435, 0.055, 35))
		Build.attach(handle, Build.ball(0.035, RUBBER), front(u, 0.505, 0.055))
	end
	Build.attach(handle, Build.block(Vector3.new(0.66, 0.05, 0.045), frameColor), front(0.5, 0.315, 0.035))
	Build.attach(handle, Build.block(Vector3.new(0.05, 0.035, 0.04), frameColor), front(0.5, 0.39, 0.03)) -- pont
	temple(handle, front(0.185, 0.32, 0.035).Position, 1, 0.17, frameColor)
	temple(handle, front(0.815, 0.32, 0.035).Position, -1, 0.17, frameColor)
end

-- Monocle du Baron : 1 = métal, 2 = moustache. Monocle sur l'œil gauche du personnage.
local function drawMonocle(handle: Part, colors: Palette)
	local metal, stache = colors[1], colors[2]
	local eyeU, eyeV = EYE_U2, 0.38
	local marks: { Mark } = {}
	brow(marks, eyeU, 0.215, 0.12, 0.03, 8, INK) -- sourcil haussé au-dessus du monocle
	brow(marks, EYE_U1, 0.33, 0.12, 0.035, 10, INK)
	ovalEye(marks, eyeU, eyeV, 0.12, 0.17, INK) -- œil agrandi par le verre
	table.insert(marks, mark(EYE_U1, 0.395, 0.1, 0.03, INK, 0.5, -4)) -- œil plissé
	table.insert(marks, mark(0.5, 0.72, 0.05, 0.05, MOUTH, 1)) -- « oh ! »
	paint(handle, marks)

	-- Cerclage octogonal et verre.
	for index = 0, 7 do
		local angle = index * 45
		local radians = math.rad(angle)
		local segment = Build.block(Vector3.new(0.03, 0.118, 0.035), metal, Enum.Material.Metal)
		segment.Reflectance = 0.25
		Build.attach(handle, segment, front(eyeU + 0.13 * math.cos(radians), eyeV + 0.13 * math.sin(radians), 0.03, angle))
	end
	local lens = Build.cylinder(0.012, 0.25, GLASS_TINT, Enum.Material.Glass)
	lens.Transparency = 0.5
	Build.attach(handle, lens, front(eyeU, eyeV, 0.025) * FORWARD)
	addSparkles(lens, metal, 2)
	-- Chaînette pendante.
	local chainTop = front(eyeU + 0.126, eyeV + 0.073, 0.03).Position
	local chainMid = front(0.82, 0.78, 0).Position
	beam(handle, chainTop, chainMid, 0.016, 0.016, metal)
	beam(handle, chainMid, head(-0.44, -0.62, -0.3).Position, 0.016, 0.016, metal)
	-- Moustache en guidon, assez basse pour laisser la place au monocle.
	Build.attach(handle, Build.block(Vector3.new(0.16, 0.075, 0.065), stache), front(0.5, 0.635, 0.03))
	for _, side in { -1, 1 } do
		Build.attach(handle, Build.block(Vector3.new(0.14, 0.062, 0.055), stache), front(0.5 + side * 0.105, 0.615, 0.025, -side * 18))
		Build.attach(handle, Build.ball(0.08, stache), front(0.5 + side * 0.185, 0.575, 0.025))
	end
end

-- Visière Néon 3000 : 1 = néon, 2 = coque.
local function drawNeonVisor(handle: Part, colors: Palette)
	local neon, shell = colors[1], colors[2]
	local marks: { Mark } = {}
	brow(marks, EYE_U1, 0.28, 0.12, 0.034, 6, INK)
	brow(marks, EYE_U2, 0.28, 0.12, 0.034, -6, INK)
	smirk(marks, 0.5, 0.68, INK)
	paint(handle, marks)

	local band = Build.block(Vector3.new(0.74, 0.17, 0.05), shell)
	band.Reflectance = 0.1
	Build.attach(handle, band, front(0.5, EYE_V, 0.03))
	local strip = Build.block(Vector3.new(0.62, 0.045, 0.02), neon, Enum.Material.Neon)
	Build.attach(handle, strip, front(0.5, EYE_V, 0.065))
	Build.attach(handle, Build.block(Vector3.new(0.08, 0.055, 0.024), WHITE, Enum.Material.Neon), front(0.42, EYE_V, 0.07)) -- point de balayage
	addSparkles(strip, neon, 3)
	for _, side in { 1, -1 } do
		-- side = 1 : côté droit du personnage (gauche de l'écran).
		beam(handle, front(0.5 - side * 0.37, EYE_V, 0.03).Position, head(side * 0.6, 0.08, -0.12).Position, 0.03, 0.13, shell)
		Build.attach(handle, Build.cylinder(0.08, 0.22, shell), head(side * 0.63, 0.06, -0.06)) -- écouteur
		Build.attach(handle, Build.cylinder(0.02, 0.13, neon, Enum.Material.Neon), head(side * 0.68, 0.06, -0.06))
	end
	Build.attach(handle, Build.block(Vector3.new(0.03, 0.26, 0.03), shell), head(0.65, 0.3, -0.06)) -- antenne
	Build.attach(handle, Build.ball(0.07, neon, Enum.Material.Neon), head(0.65, 0.45, -0.06))
end

--------------------------------------------------------------------------------
-- Définitions
--------------------------------------------------------------------------------

local function entry(spec: Spec): CosmeticDef
	local id, palettes, design = spec.id, spec.palettes, spec.design
	local variants: { Variant } = {}
	for index, colors in palettes do
		variants[index] = { nameKey = string.format("cos.%s.v%d", id, index), colors = colors }
	end
	local unlock: Unlock = { kind = "Price" }
	local given = spec.unlock
	if given then
		unlock = given
	end
	local def: CosmeticDef = {
		id = id,
		slot = "Face",
		nameKey = "cos." .. id,
		descKey = "cos." .. id .. ".desc",
		rarity = spec.rarity,
		price = spec.price,
		unlock = unlock,
		variants = variants,
		tags = spec.tags,
		build = function(variant: number?): Instance
			local accessory, handle = Build.accessory(id, "FaceFrontAttachment", PLATE_SIZE, Vector3.new(0, 0, ATTACH_Z))
			accessory:SetAttribute("HideDefaultFace", true)
			design(handle, pick(palettes, variant))
			return Build.finalize(accessory)
		end,
	}
	return def
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

return {
	-- Gratuit (visage de départ de tous les joueurs).
	entry({
		id = "face_friendly",
		rarity = "Common",
		price = 0,
		unlock = { kind = "Default" },
		palettes = { { rgb(40, 30, 38) }, { rgb(30, 85, 175) }, { rgb(125, 78, 36) } },
		tags = { "drawn" },
		design = drawFriendly,
	}),

	-- Communs.
	entry({
		id = "face_cheeky",
		rarity = "Common",
		price = 160,
		palettes = { { rgb(240, 100, 125) }, { rgb(95, 125, 235) }, { rgb(120, 205, 90) } },
		tags = { "drawn" },
		design = drawCheeky,
	}),
	entry({
		id = "face_game_face",
		rarity = "Common",
		price = 180,
		palettes = { { rgb(40, 30, 38) }, { rgb(175, 45, 30) }, { rgb(60, 105, 145) } },
		tags = { "drawn" },
		design = drawGameFace,
	}),
	entry({
		id = "face_clown_nose",
		rarity = "Common",
		price = 200,
		palettes = { { rgb(230, 30, 40) }, { rgb(40, 110, 240) }, { rgb(150, 60, 205) } },
		tags = { "nose" },
		design = drawClownNose,
	}),
	entry({
		id = "face_handlebar",
		rarity = "Common",
		price = 200,
		palettes = { { rgb(100, 62, 35) }, { rgb(32, 28, 28) }, { rgb(225, 185, 95) }, { rgb(190, 85, 35) } },
		tags = { "moustache" },
		design = drawHandlebar,
	}),
	entry({
		id = "face_combover",
		rarity = "Common",
		price = 220,
		palettes = { { rgb(110, 70, 40) }, { rgb(35, 30, 30) }, { rgb(150, 150, 155) }, { rgb(200, 95, 40) } },
		tags = { "hair" },
		design = drawCombover,
	}),
	entry({
		id = "face_nerd_glasses",
		rarity = "Common",
		price = 240,
		palettes = {
			{ rgb(30, 30, 35), rgb(205, 230, 255) },
			{ rgb(125, 72, 35), rgb(225, 238, 255) },
			{ rgb(200, 35, 50), rgb(255, 235, 240) },
		},
		tags = { "glasses" },
		design = drawNerdGlasses,
	}),

	-- Rares.
	entry({
		id = "face_carrot_nose",
		rarity = "Rare",
		price = 450,
		palettes = {
			{ rgb(255, 130, 30), rgb(215, 98, 20) },
			{ rgb(135, 50, 165), rgb(100, 35, 130) },
			{ rgb(255, 205, 60), rgb(225, 168, 40) },
		},
		tags = { "nose" },
		design = drawCarrotNose,
	}),
	entry({
		id = "face_mohawk",
		rarity = "Rare",
		price = 500,
		palettes = {
			{ rgb(110, 240, 60), rgb(55, 150, 40) },
			{ rgb(255, 80, 175), rgb(175, 40, 120) },
			{ rgb(50, 140, 255), rgb(30, 80, 190) },
			{ rgb(255, 150, 30), rgb(215, 45, 30) },
		},
		tags = { "hair" },
		design = drawMohawk,
	}),
	entry({
		id = "face_star_eyes",
		rarity = "Rare",
		price = 550,
		palettes = { { rgb(255, 205, 40) }, { rgb(255, 105, 180) }, { rgb(60, 220, 255) } },
		tags = { "drawn" },
		design = drawStarEyes,
	}),
	entry({
		id = "face_disguise",
		rarity = "Rare",
		price = 600,
		palettes = { { rgb(45, 35, 32) }, { rgb(225, 190, 110) }, { rgb(195, 90, 40) } },
		tags = { "glasses", "nose", "moustache" },
		design = drawDisguise,
	}),

	-- Épiques.
	entry({
		id = "face_eyepatch",
		rarity = "Epic",
		price = 0,
		unlock = { kind = "Achievement", value = "ach_ko_25" },
		palettes = {
			{ rgb(25, 25, 28), rgb(55, 45, 40), rgb(245, 245, 245) },
			{ rgb(180, 25, 35), rgb(90, 20, 25), rgb(255, 205, 90) },
			{ rgb(25, 40, 95), rgb(20, 25, 50), rgb(225, 230, 240) },
		},
		tags = { "eyepatch" },
		design = drawEyepatch,
	}),
	entry({
		id = "face_wiper_shades",
		rarity = "Epic",
		price = 1000,
		palettes = {
			{ rgb(25, 25, 30), rgb(35, 40, 70) },
			{ rgb(210, 40, 40), rgb(255, 145, 40) },
			{ rgb(240, 245, 250), rgb(80, 170, 255) },
		},
		tags = { "glasses" },
		design = drawWiperShades,
	}),
	entry({
		id = "face_pompadour",
		rarity = "Epic",
		price = 1100,
		palettes = {
			{ rgb(28, 24, 32), rgb(255, 110, 170) },
			{ rgb(105, 65, 35), rgb(40, 40, 45) },
			{ rgb(235, 228, 210), rgb(35, 35, 40) },
			{ rgb(40, 75, 205), rgb(255, 215, 60) },
		},
		tags = { "hair" },
		design = drawPompadour,
	}),

	-- Légendaires.
	entry({
		id = "face_monocle",
		rarity = "Legendary",
		price = 0,
		unlock = { kind = "Achievement", value = "ach_hole_in_one" },
		palettes = {
			{ rgb(255, 196, 60), rgb(240, 238, 230) },
			{ rgb(235, 150, 130), rgb(185, 85, 40) },
			{ rgb(215, 222, 232), rgb(35, 30, 30) },
		},
		tags = { "glasses", "moustache" },
		design = drawMonocle,
	}),
	entry({
		id = "face_neon_visor",
		rarity = "Legendary",
		price = 2200,
		palettes = {
			{ rgb(40, 230, 255), rgb(40, 44, 52) },
			{ rgb(255, 50, 200), rgb(40, 44, 52) },
			{ rgb(150, 255, 60), rgb(232, 236, 242) },
		},
		tags = { "glasses" },
		design = drawNeonVisor,
	}),
}
