--!strict
--[[
	Catalog/HoleEffects : effets d'entrée dans le trou (emplacement "HoleEffect") — 1 effet gratuit par défaut
	+ 5 effets.

	CONTRAT (Cosmetics/init.luau) : play(position, parent) — joué CÔTÉ CLIENT quand la balle du joueur entre dans
	le trou (Golf.Holed porte l'identifiant de l'effet équipé ; BallVisualController l'appelle). `position` est le
	centre du trou dans le monde ; `parent` est le dossier d'effets locaux (Workspace.ClientEffects).

	PROPRIÉTÉS COMMUNES
	  - purement visuels et locaux : aucune pièce n'est tangible (CanCollide / CanQuery / CanTouch faux) ;
	  - tout est détruit automatiquement (Debris) : durée de vie ≤ 4 s ;
	  - jamais de scintillement répété (accessibilité) : un seul éclat bref au plus ; les particules portent
	    CosmeticFx = true (coupées en effets réduits) ;
	  - n'utilisent que des textures et du matériel intégrés au moteur : aucun asset importé.

	Prix : Common ≈ 400, Rare ≈ 700, Epic ≈ 1200, Legendary ≈ 2200.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Cosmetics = require(script.Parent.Parent)

type CosmeticDef = Cosmetics.CosmeticDef
type Rarity = Cosmetics.Rarity
type Unlock = Cosmetics.Unlock

local rgb = Color3.fromRGB
local rad = math.rad
local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local SQUARE = "rbxasset://textures/particles/SquareParticle.png"

local function seq(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local points = {}
	for index, color in colors do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(points)
end

-- Pièce d'effet : ancrée, invisible aux collisions, détruite après `life` secondes.
local function piece(parent: Instance, cframe: CFrame, size: Vector3, life: number): Part
	local part = Instance.new("Part")
	part.Name = "EffetTrou"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Size = size
	part.CFrame = cframe
	part.Transparency = 1
	part.Parent = parent
	Debris:AddItem(part, life)
	return part
end

local function emitterOn(part: Part, props: { [string]: any }): ParticleEmitter
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.LightEmission = 0.3
	emitter.Texture = SPARKLES
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = attachment
	emitter:SetAttribute("CosmeticFx", true)
	return emitter
end

local function glow(parent: Instance, cframe: CFrame, size: Vector3, color: Color3, life: number, shape: Enum.PartType?): Part
	local part = piece(parent, cframe, size, life + 0.2)
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.1
	if shape then
		part.Shape = shape
	end
	TweenService:Create(part, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
	return part
end

local function effect(id: string, rarity: Rarity, price: number, unlock: Unlock, tags: { string }, play: (position: Vector3, parent: Instance) -> ()): CosmeticDef
	return {
		id = id,
		slot = "HoleEffect",
		nameKey = "cos." .. id,
		descKey = "cos." .. id .. ".desc",
		rarity = rarity,
		price = price,
		unlock = unlock,
		tags = tags,
		play = play,
	}
end

local DEFAULT = { kind = "Default" } :: Unlock
local PRICE = { kind = "Price" } :: Unlock

return {
	-- Gratuit : confettis -------------------------------------------------------------------------
	effect("hole_confetti", "Common", 0, DEFAULT, { "starter", "celebration" }, function(position, parent)
		local anchor = piece(parent, CFrame.new(position + Vector3.new(0, 1, 0)), Vector3.new(1, 1, 1), 4)
		local emitter = emitterOn(anchor, {
			Texture = SQUARE,
			Color = seq({ rgb(255, 90, 90), rgb(255, 210, 70), rgb(90, 210, 120), rgb(80, 160, 255), rgb(200, 110, 255) }),
			Size = NumberSequence.new(0.35, 0.25),
			Lifetime = NumberRange.new(1.4, 2.4),
			Speed = NumberRange.new(18, 34),
			SpreadAngle = Vector2.new(35, 35),
			Acceleration = Vector3.new(0, -28, 0),
			RotSpeed = NumberRange.new(-260, 260),
			Rotation = NumberRange.new(0, 360),
			Drag = 1.5,
			LightEmission = 0.1,
		})
		emitter:Emit(46)
	end),

	-- Communs --------------------------------------------------------------------------------------
	-- Une fusée monte puis éclate en gerbe de couleurs.
	effect("hole_fireworks", "Common", 400, PRICE, { "celebration", "city" }, function(position, parent)
		local launch = piece(parent, CFrame.new(position), Vector3.new(1, 1, 1), 4)
		emitterOn(launch, {
			Color = seq({ rgb(255, 235, 150), rgb(255, 150, 60) }),
			Size = NumberSequence.new(0.5, 0),
			Lifetime = NumberRange.new(0.5, 0.7),
			Speed = NumberRange.new(34, 44),
			SpreadAngle = Vector2.new(4, 4),
			Acceleration = Vector3.new(0, -4, 0),
		}):Emit(10)
		task.delay(0.6, function()
			if not parent.Parent then
				return
			end
			local top = piece(parent, CFrame.new(position + Vector3.new(0, 20, 0)), Vector3.new(1, 1, 1), 3)
			emitterOn(top, {
				Color = seq({ rgb(255, 90, 120), rgb(255, 220, 80), rgb(110, 220, 255), rgb(170, 120, 255) }),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
				Lifetime = NumberRange.new(1.0, 1.6),
				Speed = NumberRange.new(14, 26),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, -14, 0),
				Drag = 1.2,
				LightEmission = 0.8,
			}):Emit(70)
		end)
	end),

	-- Rares ----------------------------------------------------------------------------------------
	-- Un jet d'eau jaillit du trou.
	effect("hole_geyser", "Rare", 700, PRICE, { "coast", "water" }, function(position, parent)
		local anchor = piece(parent, CFrame.new(position), Vector3.new(1, 1, 1), 3.5)
		local emitter = emitterOn(anchor, {
			Color = seq({ rgb(235, 250, 255), rgb(110, 190, 255) }),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.1) }),
			Lifetime = NumberRange.new(0.9, 1.4),
			Speed = NumberRange.new(30, 42),
			SpreadAngle = Vector2.new(7, 7),
			Acceleration = Vector3.new(0, -52, 0),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		})
		emitter.Rate = 140
		task.delay(0.9, function()
			emitter.Rate = 0
		end)
		glow(parent, CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, rad(90)), Vector3.new(0.1, 3, 3), rgb(160, 215, 255), 0.7, Enum.PartType.Cylinder)
	end),

	-- Des cœurs montent en flottant.
	effect("hole_hearts", "Rare", 700, PRICE, { "celebration", "cute" }, function(position, parent)
		for index = 1, 9 do
			task.delay((index - 1) * 0.08, function()
				if not parent.Parent then
					return
				end
				local offset = Vector3.new(math.random(-20, 20) / 10, 0.5, math.random(-20, 20) / 10)
				local anchor = piece(parent, CFrame.new(position + offset), Vector3.new(0.5, 0.5, 0.5), 2.4)
				local gui = Instance.new("BillboardGui")
				gui.Size = UDim2.fromOffset(46, 46)
				gui.AlwaysOnTop = false
				gui.LightInfluence = 0
				gui.Parent = anchor
				gui:SetAttribute("CosmeticFx", true)
				local label = Instance.new("TextLabel")
				label.Size = UDim2.fromScale(1, 1)
				label.BackgroundTransparency = 1
				label.Text = "♥"
				label.TextScaled = true
				label.Font = Enum.Font.GothamBold
				label.TextColor3 = if index % 2 == 0 then rgb(255, 90, 140) else rgb(255, 150, 190)
				label.Parent = gui
				TweenService:Create(anchor, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					CFrame = anchor.CFrame + Vector3.new(math.random(-10, 10) / 10, 9, math.random(-10, 10) / 10),
				}):Play()
				TweenService:Create(label, TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
			end)
		end
	end),

	-- Épique ---------------------------------------------------------------------------------------
	-- Un éclair tombe du ciel dans le trou (un seul éclat bref, sans clignotement).
	effect("hole_lightning", "Epic", 1200, PRICE, { "storm", "fx" }, function(position, parent)
		local points: { Vector3 } = { position + Vector3.new(0, 44, 0) }
		for step = 1, 7 do
			local height = 44 - step * 6.2
			local jitter = if step == 7 then Vector3.zero else Vector3.new(math.random(-18, 18) / 10, 0, math.random(-18, 18) / 10)
			table.insert(points, position + Vector3.new(0, math.max(height, 0.2), 0) + jitter)
		end
		for index = 1, #points - 1 do
			local a, b = points[index], points[index + 1]
			local length = (b - a).Magnitude
			glow(parent, CFrame.lookAt((a + b) / 2, b), Vector3.new(0.5, 0.5, length), rgb(235, 245, 255), 0.4)
		end
		glow(parent, CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, rad(90)), Vector3.new(0.1, 3, 3), rgb(180, 210, 255), 0.5, Enum.PartType.Cylinder)
		local ringPart = glow(parent, CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, rad(90)), Vector3.new(0.1, 2, 2), rgb(180, 210, 255), 0.6, Enum.PartType.Cylinder)
		TweenService:Create(ringPart, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.1, 18, 18) }):Play()
		local sparks = piece(parent, CFrame.new(position + Vector3.new(0, 0.5, 0)), Vector3.new(1, 1, 1), 2.5)
		emitterOn(sparks, {
			Color = seq({ rgb(255, 255, 255), rgb(150, 190, 255) }),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.4, 0.8),
			Speed = NumberRange.new(14, 28),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -20, 0),
			LightEmission = 0.9,
		}):Emit(36)
	end),

	-- Légendaire -----------------------------------------------------------------------------------
	-- Un arc-en-ciel se déploie au-dessus du trou, puis s'efface.
	effect("hole_rainbow", "Legendary", 2200, PRICE, { "celebration", "champion", "fx" }, function(position, parent)
		local colors = { rgb(235, 60, 60), rgb(250, 150, 50), rgb(250, 225, 60), rgb(90, 200, 90), rgb(70, 160, 240), rgb(110, 90, 220), rgb(220, 100, 190) }
		local segments = 14
		for band, color in colors do
			local radius = 8 + band * 0.75
			for index = 0, segments - 1 do
				local a0 = index / segments * math.pi
				local a1 = (index + 1) / segments * math.pi
				local p0 = position + Vector3.new(math.cos(a0) * radius, math.sin(a0) * radius, 0)
				local p1 = position + Vector3.new(math.cos(a1) * radius, math.sin(a1) * radius, 0)
				task.delay(index * 0.04, function()
					if not parent.Parent then
						return
					end
					local length = (p1 - p0).Magnitude + 0.05
					local part = piece(parent, CFrame.lookAt((p0 + p1) / 2, p1), Vector3.new(0.7, 0.7, length), 3.4)
					part.Material = Enum.Material.Neon
					part.Color = color
					part.Transparency = 0.25
					task.delay(1.6, function()
						if part.Parent then
							TweenService:Create(part, TweenInfo.new(1.4), { Transparency = 1 }):Play()
						end
					end)
				end)
			end
		end
		local sparks = piece(parent, CFrame.new(position + Vector3.new(0, 1, 0)), Vector3.new(1, 1, 1), 3)
		emitterOn(sparks, {
			Color = seq(colors),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.8, 1.4),
			Speed = NumberRange.new(10, 22),
			SpreadAngle = Vector2.new(60, 60),
			Acceleration = Vector3.new(0, -10, 0),
			LightEmission = 0.7,
		}):Emit(50)
	end),
}
