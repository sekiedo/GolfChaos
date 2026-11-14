--!strict
--[[
	EffectsController — rendu client des effets visuels et sonores (contrat docs/ARCHITECTURE.md §9).

	  EffectsController.PlaySound(nom, opts?)      opts = { position: Vector3?, parent: Instance?, volume: number?,
	                                                        pitch: number?, maxDuration: number?, fadeOut: number? }
	  EffectsController.PlayMusic(nom | nil)       fondu enchaîné entre musiques d'ambiance (nil = silence)
	  EffectsController.Play(nomEffet, params)     effet du registre client/Effects/*.luau
	  EffectsController.GetQuality() -> "Low" | "Medium" | "High"
	  EffectsController.IsReduced() / IsNoFlash()

	Registre : chaque ModuleScript de client/Effects retourne { [nomEffet] = function(params, api) end }.
	`api` fournit : reduced, noFlash, quality, folder (dossier local des effets), anchorAt(position) -> Attachment,
	emit(attachment, preset, count), debris(instance, secondes), sound(nom, opts), scale(n) (applique qualité/réduction).

	Tout est purement cosmétique et local : un effet qui échoue est journalisé et ignoré ; un son qui ne charge
	pas reste silencieux. Les réglages viennent de SettingsController (s'il existe) : masterVolume, sfxVolume,
	musicVolume, reducedEffects, noFlash, quality.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Log = require(Shared.Util.Log)
local Sounds = require(Shared.Config.Sounds)
local Cosmetics = require(Shared.Cosmetics)

local EffectsController = {}
EffectsController.Priority = 65

type EffectHandler = (params: { [string]: any }, api: any) -> ()

local MAX_ACTIVE_SOUNDS = 28
local MUSIC_FADE = 1.2

local registry: { [string]: EffectHandler } = {}
local folder: Folder? = nil
local activeSounds: { Sound } = {}
local currentMusic: Sound? = nil
local currentMusicName: string? = nil
local settingsModule: any = nil

-- Réglages -----------------------------------------------------------------------

local function setting(key: string, default: any): any
	if settingsModule and type(settingsModule.Get) == "function" then
		local ok, value = pcall(settingsModule.Get, key)
		if ok and value ~= nil then
			return value
		end
	end
	return default
end

local function categoryVolume(category: string): number
	local master = tonumber(setting("masterVolume", 1)) or 1
	local key = if category == "Music" then "musicVolume" elseif category == "Ui" then "sfxVolume" else "sfxVolume"
	local volume = tonumber(setting(key, 1)) or 1
	return math.clamp(master, 0, 1) * math.clamp(volume, 0, 1)
end

function EffectsController.IsReduced(): boolean
	return setting("reducedEffects", false) == true
end

function EffectsController.IsNoFlash(): boolean
	return setting("noFlash", false) == true
end

function EffectsController.GetQuality(): string
	local chosen = setting("quality", "Auto")
	if chosen == "Low" or chosen == "Medium" or chosen == "High" then
		return chosen
	end
	local ok, level = pcall(function()
		return UserSettings().GameSettings.SavedQualityLevel.Value
	end)
	if ok and type(level) == "number" and level > 0 then
		if level <= 3 then
			return "Low"
		elseif level <= 7 then
			return "Medium"
		end
		return "High"
	end
	return "Medium"
end

-- Multiplicateur appliqué aux quantités de particules selon qualité et effets réduits.
local function amountScale(): number
	local quality = EffectsController.GetQuality()
	local scale = if quality == "Low" then 0.4 elseif quality == "Medium" then 0.7 else 1
	if EffectsController.IsReduced() then
		scale *= 0.4
	end
	return scale
end

-- Sons ---------------------------------------------------------------------------

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "ClientEffects"
	created.Parent = workspace
	folder = created
	return created
end

local function trimSounds()
	for index = #activeSounds, 1, -1 do
		local sound = activeSounds[index]
		if not sound.Parent then
			table.remove(activeSounds, index)
		end
	end
	while #activeSounds >= MAX_ACTIVE_SOUNDS do
		local oldest = table.remove(activeSounds, 1)
		if oldest then
			oldest:Destroy()
		end
	end
end

function EffectsController.PlaySound(name: string, opts: { [string]: any }?): Sound?
	local def = (Sounds :: any)[name]
	if type(def) ~= "table" then
		Log.debug("Effects", "son inconnu", name)
		return nil
	end
	local options = opts or {}
	trimSounds()
	local sound = Instance.new("Sound")
	sound.Name = "Sfx_" .. name
	sound.SoundId = def.id
	local relative = if type(options.volume) == "number" then options.volume else 1
	sound.Volume = math.clamp(def.volume * relative * categoryVolume(def.category), 0, 3)
	local pitch = if type(options.pitch) == "number" then options.pitch else (def.pitch or 1)
	if def.pitchVariance and def.pitchVariance > 0 then
		pitch *= 1 + (math.random() * 2 - 1) * def.pitchVariance
	end
	sound.PlaybackSpeed = pitch
	sound.Looped = def.looped == true

	local parent: Instance
	if typeof(options.parent) == "Instance" then
		parent = options.parent
	elseif typeof(options.position) == "Vector3" then
		local attachment = Instance.new("Attachment")
		attachment.Name = "SonPositionne"
		attachment.WorldPosition = options.position
		attachment.Parent = workspace.Terrain
		parent = attachment
		sound.RollOffMinDistance = 12
		sound.RollOffMaxDistance = 220
		sound.Ended:Once(function()
			attachment:Destroy()
		end)
		task.delay(30, function()
			if attachment.Parent then
				attachment:Destroy()
			end
		end)
	else
		parent = SoundService
	end
	sound.Parent = parent
	table.insert(activeSounds, sound)
	sound:Play()

	if not sound.Looped then
		sound.Ended:Once(function()
			sound:Destroy()
		end)
		local maxDuration = if type(options.maxDuration) == "number" then options.maxDuration else 12
		local fade = if type(options.fadeOut) == "number" then options.fadeOut else 0.4
		task.delay(maxDuration, function()
			if sound.Parent then
				local tween = TweenService:Create(sound, TweenInfo.new(fade), { Volume = 0 })
				tween:Play()
				tween.Completed:Once(function()
					sound:Destroy()
				end)
			end
		end)
	end
	return sound
end

function EffectsController.PlayMusic(name: string?)
	if name == currentMusicName then
		return
	end
	local previous = currentMusic
	currentMusic = nil
	currentMusicName = name
	if previous then
		local tween = TweenService:Create(previous, TweenInfo.new(MUSIC_FADE), { Volume = 0 })
		tween:Play()
		tween.Completed:Once(function()
			previous:Destroy()
		end)
	end
	if not name or name == "" then
		return
	end
	local def = (Sounds :: any)[name]
	if type(def) ~= "table" then
		return
	end
	local music = Instance.new("Sound")
	music.Name = "Musique_" .. name
	music.SoundId = def.id
	music.Looped = true
	music.Volume = 0
	music.Parent = SoundService
	music:Play()
	currentMusic = music
	TweenService:Create(music, TweenInfo.new(MUSIC_FADE), { Volume = def.volume * categoryVolume("Music") }):Play()
end

local function refreshMusicVolume()
	local music = currentMusic
	local name = currentMusicName
	if music and name then
		local def = (Sounds :: any)[name]
		if type(def) == "table" then
			music.Volume = def.volume * categoryVolume("Music")
		end
	end
end

-- Effets visuels -------------------------------------------------------------------

export type EmitPreset = {
	texture: string,
	color: ColorSequence?,
	size: NumberSequence?,
	transparency: NumberSequence?,
	lifetime: NumberRange?,
	speed: NumberRange?,
	spread: Vector2?,
	acceleration: Vector3?,
	lightEmission: number?,
	rotSpeed: NumberRange?,
	drag: number?,
}

local api = {}

function api.anchorAt(position: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = "PointEffet"
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	return attachment
end

function api.debris(instance: Instance, seconds: number)
	task.delay(seconds, function()
		if instance.Parent then
			instance:Destroy()
		end
	end)
end

function api.scale(count: number): number
	return math.max(1, math.floor(count * amountScale() + 0.5))
end

function api.emit(attachment: Attachment, preset: EmitPreset, count: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = preset.texture
	emitter.Color = preset.color or ColorSequence.new(Color3.new(1, 1, 1))
	emitter.Size = preset.size or NumberSequence.new(0.6, 0)
	emitter.Transparency = preset.transparency or NumberSequence.new(0, 1)
	emitter.Lifetime = preset.lifetime or NumberRange.new(0.5, 0.9)
	emitter.Speed = preset.speed or NumberRange.new(8, 16)
	emitter.SpreadAngle = preset.spread or Vector2.new(180, 180)
	emitter.Acceleration = preset.acceleration or Vector3.zero
	emitter.LightEmission = preset.lightEmission or 0.3
	emitter.RotSpeed = preset.rotSpeed or NumberRange.new(-90, 90)
	emitter.Drag = preset.drag or 0
	emitter.Enabled = false
	emitter.Parent = attachment
	emitter:Emit(api.scale(count))
	return emitter
end

function api.sound(name: string, opts: { [string]: any }?): Sound?
	return EffectsController.PlaySound(name, opts)
end

function api.folder(): Folder
	return getFolder()
end

function api.isReduced(): boolean
	return EffectsController.IsReduced()
end

function api.isNoFlash(): boolean
	return EffectsController.IsNoFlash()
end

function api.quality(): string
	return EffectsController.GetQuality()
end

api.localPlayer = Players.LocalPlayer

function EffectsController.Play(effectName: string, params: { [string]: any }?)
	local handler = registry[effectName]
	if not handler then
		Log.debug("Effects", "effet inconnu", effectName)
		return
	end
	task.spawn(function()
		local ok, err = pcall(handler, params or {}, api)
		if not ok then
			Log.warn("Effects", "effet " .. effectName .. " :", err)
		end
	end)
end

function EffectsController.Register(name: string, handler: EffectHandler)
	registry[name] = handler
end

function EffectsController.HasEffect(name: string): boolean
	return registry[name] ~= nil
end

-- Cycle de vie -----------------------------------------------------------------------

function EffectsController.Init()
	local client = script.Parent.Parent
	local settings = script.Parent:FindFirstChild("SettingsController")
	if settings and settings:IsA("ModuleScript") then
		local ok, module = pcall(require, settings)
		if ok then
			settingsModule = module
		end
	end
	local effectsFolder = client:FindFirstChild("Effects")
	if effectsFolder then
		for _, module in effectsFolder:GetChildren() do
			if module:IsA("ModuleScript") then
				local ok, handlers = pcall(require, module)
				if ok and type(handlers) == "table" then
					for name, handler in handlers :: { [string]: EffectHandler } do
						if type(handler) == "function" then
							if registry[name] then
								Log.warn("Effects", "effet défini deux fois :", name)
							end
							registry[name] = handler
						end
					end
				else
					Log.error("Effects", "registre illisible :", module.Name, handlers)
				end
			end
		end
	end
end

-- Effet de trou cosmétique : Golf.Holed(userId, { effectId, practice, ... }) -> Cosmetics[effectId].play(position, parent).
-- La position est celle de la balle du joueur (Workspace.Balls, attribut OwnerUserId) à l'instant de l'événement.
local function onHoled(userId: any, info: any)
	if type(userId) ~= "number" or type(info) ~= "table" then
		return
	end
	if info.practice == true or type(info.effectId) ~= "string" or info.effectId == "" then
		return
	end
	if EffectsController.IsReduced() then
		return
	end
	local def = Cosmetics.get(info.effectId)
	if not def or def.slot ~= "HoleEffect" or type(def.play) ~= "function" then
		return
	end
	local balls = workspace:FindFirstChild("Balls")
	local position: Vector3? = nil
	if balls then
		for _, ball in balls:GetChildren() do
			if ball:IsA("BasePart") and ball:GetAttribute("OwnerUserId") == userId then
				position = ball.Position
				break
			end
		end
	end
	if not position then
		return
	end
	local play = def.play :: (Vector3, Instance) -> ()
	local ok, err = pcall(play, position, getFolder())
	if not ok then
		Log.warn("Effects", "effet de trou en échec :", info.effectId, err)
	end
end

function EffectsController.Start()
	Net.listen("Golf.Holed", onHoled)
	Net.listen("Effects.Play", function(effectName: any, params: any)
		if type(effectName) == "string" then
			EffectsController.Play(effectName, if type(params) == "table" then params else nil)
		end
	end)
	Net.listen("Effects.Burst", function(effectName: any, params: any)
		if type(effectName) == "string" then
			EffectsController.Play(effectName, if type(params) == "table" then params else nil)
		end
	end)
	Net.listen("Effects.Sound", function(name: any, position: any, volume: any)
		if type(name) == "string" then
			EffectsController.PlaySound(name, {
				position = if typeof(position) == "Vector3" then position else nil,
				volume = if type(volume) == "number" then volume else nil,
			})
		end
	end)
	Net.listen("Effects.Music", function(name: any)
		EffectsController.PlayMusic(if type(name) == "string" and name ~= "" then name else nil)
	end)
	if settingsModule and settingsModule.Changed and type(settingsModule.Changed.Connect) == "function" then
		settingsModule.Changed:Connect(function(key: string)
			if key == "masterVolume" or key == "musicVolume" then
				refreshMusicVolume()
			end
		end)
	end
end

return EffectsController
