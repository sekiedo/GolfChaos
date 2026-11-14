--!strict
--[[
	Build : primitives communes pour construire les cosmétiques par code (client et serveur).
	Garantit les règles d'équité : toute pièce créée ici est Massless, sans collision, sans requête,
	sans contact — un cosmétique ne peut jamais changer la physique, la portée ou une hitbox.

	  local Build = require(script.Parent.Parent.Build)   -- depuis Catalog/*.luau
	  local acc, handle = Build.accessory("Chapeau", "HatAttachment", Vector3.new(1.4, 0.2, 1.4), Vector3.new(0, -0.1, 0))
	  local brim = Build.part({ Size = Vector3.new(2, 0.2, 2), Color = ..., Shape = Enum.PartType.Cylinder })
	  Build.attach(handle, brim, CFrame.new(0, 0.1, 0))        -- place relativement au Handle puis soude
	  Build.cylinderY(...)                                     -- cylindre debout (axe Y) prêt à l'emploi
	  Build.wedge(...) / Build.ball(...) / Build.block(...)
	  Build.face(handle, { eyes = ..., mouth = ... })          -- visage dessiné en SurfaceGui (pas d'image)
	  Build.finalize(instance)                                 -- réapplique les règles d'équité à tout le sous-arbre

	Dimensions de référence du personnage R15 par défaut (échelle 1, approximatives) :
	  Head ≈ 1.2 × 1.2 × 1.2 ; UpperTorso ≈ 2 × 1.6 × 1 ; LowerTorso ≈ 2 × 0.4 × 1 ;
	  bras (Upper/Lower/Hand) ≈ 1 × 1.17 / 1.05 / 0.3 × 1 ; jambes (Upper/Lower/Foot) ≈ 1 × 1.5 / 1.2 / 0.3 × 1.
	Attachements R15 : Head (HatAttachment, HairAttachment, FaceFrontAttachment, FaceCenterAttachment),
	UpperTorso (BodyFrontAttachment, BodyBackAttachment, NeckAttachment, LeftCollarAttachment, RightCollarAttachment),
	LowerTorso (WaistFrontAttachment, WaistBackAttachment, WaistCenterAttachment),
	LeftUpperArm (LeftShoulderAttachment), RightUpperArm (RightShoulderAttachment),
	mains (LeftGripAttachment, RightGripAttachment), pieds (LeftFootAttachment, RightFootAttachment).
]]

local Build = {}

export type PartProps = {
	Name: string?,
	Size: Vector3?,
	Color: Color3?,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
	Transparency: number?,
	Reflectance: number?,
	CFrame: CFrame?,
}

-- Applique les règles d'équité à une pièce.
function Build.makeSafe(part: BasePart)
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

-- Réapplique les règles d'équité à tout un sous-arbre (à appeler en fin de construction).
function Build.finalize(root: Instance): Instance
	if root:IsA("BasePart") then
		Build.makeSafe(root)
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			Build.makeSafe(descendant)
		end
	end
	return root
end

function Build.part(props: PartProps): Part
	local part = Instance.new("Part")
	part.Name = props.Name or "Piece"
	part.Size = props.Size or Vector3.new(0.4, 0.4, 0.4)
	part.Color = props.Color or Color3.fromRGB(240, 240, 240)
	part.Material = props.Material or Enum.Material.SmoothPlastic
	if props.Shape then
		part.Shape = props.Shape
	end
	part.Transparency = props.Transparency or 0
	part.Reflectance = props.Reflectance or 0
	if props.CFrame then
		part.CFrame = props.CFrame
	end
	Build.makeSafe(part)
	return part
end

function Build.block(size: Vector3, color: Color3, material: Enum.Material?): Part
	return Build.part({ Size = size, Color = color, Material = material })
end

function Build.ball(diameter: number, color: Color3, material: Enum.Material?): Part
	return Build.part({ Size = Vector3.new(diameter, diameter, diameter), Color = color, Material = material, Shape = Enum.PartType.Ball })
end

-- Cylindre dont l'axe est l'axe X local (convention Roblox). Utiliser cylinderY pour un cylindre debout.
function Build.cylinder(length: number, diameter: number, color: Color3, material: Enum.Material?): Part
	return Build.part({ Size = Vector3.new(length, diameter, diameter), Color = color, Material = material, Shape = Enum.PartType.Cylinder })
end

-- Cylindre debout (axe vertical). L'orientation est portée par la CFrame relative passée à Build.attach :
-- multiplier l'offset par Build.UP pour coucher l'axe X sur l'axe Y.
Build.UP = CFrame.Angles(0, 0, math.rad(90))

function Build.wedge(size: Vector3, color: Color3, material: Enum.Material?): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Name = "Biseau"
	wedge.Size = size
	wedge.Color = color
	wedge.Material = material or Enum.Material.SmoothPlastic
	Build.makeSafe(wedge)
	return wedge
end

function Build.cornerWedge(size: Vector3, color: Color3, material: Enum.Material?): CornerWedgePart
	local wedge = Instance.new("CornerWedgePart")
	wedge.Name = "Coin"
	wedge.Size = size
	wedge.Color = color
	wedge.Material = material or Enum.Material.SmoothPlastic
	Build.makeSafe(wedge)
	return wedge
end

-- Crée un Accessory dont le Handle porte l'attachement `attachmentName`, positionné à `attachmentOffset`
-- (position de l'attachement dans le repère du Handle). Retourne (accessory, handle).
function Build.accessory(name: string, attachmentName: string, handleSize: Vector3, attachmentOffset: Vector3?): (Accessory, Part)
	local accessory = Instance.new("Accessory")
	accessory.Name = name
	local handle = Build.part({ Name = "Handle", Size = handleSize, Transparency = 1 })
	handle.CFrame = CFrame.new()
	local attachment = Instance.new("Attachment")
	attachment.Name = attachmentName
	attachment.Position = attachmentOffset or Vector3.zero
	attachment.Parent = handle
	handle.Parent = accessory
	return accessory, handle
end

-- Place `part` à `offset` relativement au Handle (ou à toute pièce de référence) puis la soude.
function Build.attach(reference: BasePart, part: BasePart, offset: CFrame): BasePart
	part.CFrame = reference.CFrame * offset
	part.Parent = reference.Parent
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = reference
	weld.Part1 = part
	weld.Parent = part
	return part
end

-- Visage dessiné en SurfaceGui (aucune image) sur la face avant d'une pièce. Chaque élément est une Frame
-- arrondie : { position = UDim2, size = UDim2, color = Color3, corner = number? (0..1, 1 = cercle), rotation = number? }.
export type FaceShape = { position: UDim2, size: UDim2, color: Color3, corner: number?, rotation: number? }
function Build.face(part: BasePart, shapes: { FaceShape }, face: Enum.NormalId?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Visage"
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0.6
	gui.Parent = part
	for index, shape in shapes do
		local frame = Instance.new("Frame")
		frame.Name = "Trait" .. index
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = shape.position
		frame.Size = shape.size
		frame.BackgroundColor3 = shape.color
		frame.BorderSizePixel = 0
		frame.Rotation = shape.rotation or 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(shape.corner or 0.5, 0)
		corner.Parent = frame
		frame.Parent = gui
	end
	return gui
end

-- Couleur de variante sûre : variants[variant].colors[index] ou repli.
function Build.color(variants: { { colors: { Color3 } } }?, variant: number?, index: number, fallback: Color3): Color3
	if not variants then
		return fallback
	end
	local chosen = variants[variant or 1] or variants[1]
	if not chosen or not chosen.colors then
		return fallback
	end
	return chosen.colors[index] or fallback
end

return Build
