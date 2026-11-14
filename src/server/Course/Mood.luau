--!strict
--[[
	Course.Mood — ambiance « soirée en famille » : effets de post-traitement chaleureux (Bloom, ColorCorrection,
	SunRays, DepthOfField) posés dans Lighting, réglés par biome. Aucun asset : tout est procédural.

	  Mood.apply(biome, animate)   crée les effets au besoin et les règle (transition douce quand `animate`)
	  Mood.clear()                 retire les effets créés ici

	Les effets portent l'attribut GolfChaosMood pour ne jamais toucher à ceux d'un autre script.
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Mood = {}

local TAG = "GolfChaosMood"
local TWEEN = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

type Settings = {
	bloom: { Intensity: number, Size: number, Threshold: number },
	color: { Brightness: number, Contrast: number, Saturation: number, TintColor: Color3 },
	rays: { Intensity: number, Spread: number },
	depth: { FarIntensity: number, FocusDistance: number, InFocusRadius: number, NearIntensity: number },
}

local function settings(warm: Color3, saturation: number, bloom: number, rays: number): Settings
	return {
		bloom = { Intensity = bloom, Size = 28, Threshold = 1.05 },
		color = { Brightness = 0.02, Contrast = 0.08, Saturation = saturation, TintColor = warm },
		rays = { Intensity = rays, Spread = 0.6 },
		depth = { FarIntensity = 0.12, FocusDistance = 60, InFocusRadius = 120, NearIntensity = 0 },
	}
end

-- Heure dorée par défaut ; chaque biome ajuste la teinte, la saturation et l'éclat.
local PRESETS: { [string]: Settings } = {
	Lobby = settings(Color3.fromRGB(255, 236, 205), 0.28, 0.45, 0.07),
	Training = settings(Color3.fromRGB(255, 238, 210), 0.26, 0.4, 0.06),
	Coast = settings(Color3.fromRGB(255, 240, 220), 0.3, 0.45, 0.08),
	Forest = settings(Color3.fromRGB(255, 244, 208), 0.3, 0.4, 0.1),
	Desert = settings(Color3.fromRGB(255, 226, 190), 0.22, 0.55, 0.06),
	Snow = settings(Color3.fromRGB(235, 242, 255), 0.12, 0.5, 0.05),
	City = settings(Color3.fromRGB(255, 218, 190), 0.3, 0.6, 0.08),
}

local function ensure(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created:SetAttribute(TAG, true)
	created.Parent = Lighting
	return created
end

local function push(instance: Instance, values: { [string]: any }, animate: boolean)
	if animate then
		TweenService:Create(instance, TWEEN, values):Play()
	else
		for key, value in values do
			(instance :: any)[key] = value
		end
	end
end

function Mood.apply(biome: string?, animate: boolean)
	local preset = PRESETS[if biome then biome else "Lobby"] or PRESETS.Lobby
	push(ensure("BloomEffect", "GC_Bloom"), preset.bloom, animate)
	push(ensure("ColorCorrectionEffect", "GC_Couleur"), preset.color, animate)
	push(ensure("SunRaysEffect", "GC_Rayons"), preset.rays, animate)
	push(ensure("DepthOfFieldEffect", "GC_Profondeur"), preset.depth, animate)
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
end

function Mood.clear()
	for _, child in Lighting:GetChildren() do
		if child:GetAttribute(TAG) == true then
			child:Destroy()
		end
	end
end

return Mood
