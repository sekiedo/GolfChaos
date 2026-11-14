--!strict
--[[
	Theme — jetons visuels de l'interface de Golf Chaos (style cartoon, lisible, contrasté) et petites aides
	communes à tous les écrans. Aucun effet de bord au require (seulement des tables et des valeurs).

	JETONS
	  Theme.Colors.<Nom>          Ink (contours, texte foncé), Night / NightRaised / NightHover (panneaux),
	                              Paper / PaperDim (textes clairs), Primary, Secondary, Success, Warning,
	                              Danger, Accent, Backdrop, Disabled, DisabledText, White
	  Theme.Fonts.<Nom>           Display (FredokaOne), Body / Bold / Heavy (Builder Sans), Mono (Roboto Mono)
	  Theme.Teams.Red / .Blue     { id, color, dark, text, glyph, shape, labelKey } : la couleur n'est jamais le
	                              seul indicateur (glyphe ◆ / ● et libellé « Rouge » / « Bleu »)
	  Theme.Radius / Spacing / StrokeWidth / Touch / Motion   (pixels « design », voir l'échelle plus bas)

	AIDES
	  Theme.font(nom?) -> Font                    Theme.textSize(nom?) -> number
	  Theme.defaultFont(taille) -> nom de police  Theme.applyText(objet, taille?, police?)
	        applyText pose police + taille puis suit les changements (écran compact, taille de texte préférée)
	  Theme.corner(nom | px | "Pill") -> UDim
	  Theme.team(team) -> TeamStyle?              Theme.teamLabel(team) -> "◆ Rouge"
	  Theme.luminance(c), Theme.contrast(a, b), Theme.textOn(fond), Theme.ensureContrast(texte, fond, min?)
	  Theme.lighten(c, t), Theme.darken(c, t), Theme.toHex(c)
	  Theme.variant(nom?) -> VariantStyle         couleurs d'un bouton (fond, texte contrasté, lèvre, survol, appui)
	  Theme.isReducedMotion() / Theme.isNoFlash()
	  Theme.tween(objet, durée, buts, style?, sens?) -> Tween?   instantané quand les animations sont réduites
	  Theme.fade(objet, durée, buts) -> Tween?                   fondu (couleur, transparence) : toujours permis
	  Theme.backgroundTransparency(base) -> number             respecte la préférence Roblox de transparence
	  Theme.selectionImage(forme?) -> GuiObject                 cadre de sélection manette partagé ("Rounded" | "Pill")

	ÉCHELLE ET ÉCRANS COMPACTS
	  Les tailles sont en pixels « design ». UIController applique aux racines un UIScale >= 1 (grands écrans) ;
	  il n'est jamais < 1, donc une cible tactile de 44 px design fait toujours au moins 44 px réels.
	  Sur petit écran (téléphone), Theme.isCompact() est vrai et Theme.textSize() renvoie des tailles réduites.
	  Theme.getScale() / Theme.isCompact() / Theme.updateViewport(taille)   (appelé par UIController)
	  Theme.Changed : Signal(quoi)   "layout" | "motion" | "flash" | "text"
	  Theme.Layers                   DisplayOrder des ScreenGui (bannière, écrans de phase, menus, notifications)
	  Le réglage « textSize » (Normal | Large | Larger) de SettingsController agrandit tous les textes suivis.
	  Theme.bindSettings()           branche SettingsController et les préférences Roblox (idempotent)
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Locale = require(Shared.Locale)

export type FontName = "Display" | "Body" | "Bold" | "Heavy" | "Mono"
export type TextSizeName = "Caption" | "Small" | "Body" | "Button" | "Heading" | "Title" | "Display" | "Hero"
export type VariantName =
	"Primary"
	| "Secondary"
	| "Success"
	| "Warning"
	| "Danger"
	| "Accent"
	| "Dark"
	| "Light"
	| "Ghost"
	| "Disabled"

export type TeamStyle = {
	id: string,
	color: Color3, -- remplissage (badges, barres) : texte Ink dessus
	dark: Color3, -- variante foncée (lèvres, ombres)
	text: Color3, -- couleur de texte lisible sur fond sombre (contraste >= 4,5 sur Night)
	glyph: string, -- marqueur non coloré
	shape: string, -- "Diamond" | "Circle" (dessiné par Label.teamBadge)
	labelKey: string,
}

export type VariantStyle = {
	background: Color3,
	text: Color3,
	lip: Color3,
	hover: Color3,
	pressed: Color3,
	stroke: Color3,
	transparency: number,
}

local Theme = {}

Theme.Changed = Signal.new()

--------------------------------------------------------------------------------
-- Palette (contrastes vérifiés : texte Ink >= 5:1 sur toutes les couleurs vives, Paper >= 10:1 sur Night)
--------------------------------------------------------------------------------

local INK = Color3.fromRGB(23, 26, 46)
local PAPER = Color3.fromRGB(255, 248, 231)
local NIGHT_RAISED = Color3.fromRGB(47, 55, 101)

Theme.Colors = table.freeze({
	Ink = INK,
	Night = Color3.fromRGB(34, 40, 74),
	NightRaised = NIGHT_RAISED,
	NightHover = Color3.fromRGB(62, 72, 130),
	Paper = PAPER,
	PaperDim = Color3.fromRGB(201, 204, 235),
	Primary = Color3.fromRGB(255, 201, 60),
	Secondary = Color3.fromRGB(77, 166, 255),
	Success = Color3.fromRGB(91, 209, 91),
	Warning = Color3.fromRGB(255, 159, 46),
	Danger = Color3.fromRGB(255, 92, 92),
	Accent = Color3.fromRGB(166, 107, 255),
	Backdrop = Color3.fromRGB(8, 10, 22),
	Disabled = Color3.fromRGB(86, 92, 126),
	DisabledText = Color3.fromRGB(178, 182, 206),
	White = Color3.new(1, 1, 1),
})

--------------------------------------------------------------------------------
-- Polices (familles intégrées au moteur : aucun asset téléversé)
--------------------------------------------------------------------------------

local FAMILY_DISPLAY = "rbxasset://fonts/families/FredokaOne.json"
local FAMILY_BODY = "rbxasset://fonts/families/BuilderSans.json"
local FAMILY_MONO = "rbxasset://fonts/families/RobotoMono.json"

local FONTS: { [string]: Font } = {
	Display = Font.new(FAMILY_DISPLAY),
	Body = Font.new(FAMILY_BODY, Enum.FontWeight.Medium),
	Bold = Font.new(FAMILY_BODY, Enum.FontWeight.Bold),
	Heavy = Font.new(FAMILY_BODY, Enum.FontWeight.ExtraBold),
	Mono = Font.new(FAMILY_MONO, Enum.FontWeight.Bold),
}

Theme.Fonts = table.freeze({
	Display = FONTS.Display,
	Body = FONTS.Body,
	Bold = FONTS.Bold,
	Heavy = FONTS.Heavy,
	Mono = FONTS.Mono,
})

-- Tailles de texte en pixels design : normal / compact (téléphone). « scalable » : suit entièrement la taille
-- de texte préférée du joueur (paramètre Roblox) ; les très grands titres n'en suivent que la moitié.
local TEXT_SIZES: { [string]: { normal: number, compact: number, scalable: boolean } } = {
	Caption = { normal = 13, compact = 12, scalable = true },
	Small = { normal = 15, compact = 13, scalable = true },
	Body = { normal = 18, compact = 15, scalable = true },
	Button = { normal = 20, compact = 17, scalable = true },
	Heading = { normal = 24, compact = 19, scalable = true },
	Title = { normal = 32, compact = 25, scalable = false },
	Display = { normal = 48, compact = 34, scalable = false },
	Hero = { normal = 84, compact = 56, scalable = false },
}

local DISPLAY_FONT_SIZES: { [string]: boolean } = {
	Button = true,
	Heading = true,
	Title = true,
	Display = true,
	Hero = true,
}

-- Taille de texte préférée Roblox (accessibilité) -> multiplicateur.
local TEXT_SIZE_FACTORS: { [string]: number } = {
	Medium = 1,
	Large = 1.12,
	Larger = 1.25,
	Largest = 1.4,
}

-- Réglage « taille du texte » du jeu (SettingsController, clé textSize) -> multiplicateur supplémentaire.
local USER_TEXT_FACTORS: { [string]: number } = {
	Normal = 1,
	Large = 1.15,
	Larger = 1.3,
}

--------------------------------------------------------------------------------
-- Équipes : couleur + glyphe + libellé (jamais la couleur seule)
--------------------------------------------------------------------------------

local RED: TeamStyle = {
	id = "Red",
	color = Color3.fromRGB(255, 77, 77),
	dark = Color3.fromRGB(170, 36, 48),
	text = Color3.fromRGB(255, 122, 122),
	glyph = "◆",
	shape = "Diamond",
	labelKey = "ui.team.Red",
}

local BLUE: TeamStyle = {
	id = "Blue",
	color = Color3.fromRGB(61, 139, 255),
	dark = Color3.fromRGB(26, 76, 172),
	text = Color3.fromRGB(127, 178, 255),
	glyph = "●",
	shape = "Circle",
	labelKey = "ui.team.Blue",
}

local TEAMS: { [string]: TeamStyle } = { Red = table.freeze(RED), Blue = table.freeze(BLUE) }

Theme.Teams = table.freeze({ Red = RED, Blue = BLUE })

--------------------------------------------------------------------------------
-- Dimensions (pixels design)
--------------------------------------------------------------------------------

local RADIUS: { [string]: number } = { Small = 8, Medium = 14, Large = 20, Huge = 28 }

Theme.Radius = table.freeze({ Small = 8, Medium = 14, Large = 20, Huge = 28 })
Theme.Spacing = table.freeze({ XS = 4, S = 8, M = 12, L = 16, XL = 24, XXL = 32 })
Theme.StrokeWidth = table.freeze({ Thin = 2, Normal = 3, Thick = 4 })
-- Cibles tactiles : jamais moins de 44 px ; Lip = épaisseur de la « lèvre » 3D des boutons cartoon.
Theme.Touch = table.freeze({ Min = 44, Small = 44, Medium = 52, Large = 64, Lip = 4 })
Theme.Motion = table.freeze({ Fast = 0.1, Normal = 0.18, Slow = 0.3 })
-- Couches d'affichage (DisplayOrder des ScreenGui) : le HUD de jeu se place entre Banner et Phase (10..19).
Theme.Layers = table.freeze({
	Banner = 5,
	MenuButton = 8,
	Phase = 20,
	Results = 30,
	Loading = 40,
	Lobby = 50,
	Menu = 60,
	Settings = 70,
	Notifications = 90,
})

-- Échelle des racines : référence 1280 x 720, jamais < 1, plafonnée pour les très grands écrans.
local REFERENCE_SIZE = Vector2.new(1280, 720)
local COMPACT_HEIGHT = 540
local COMPACT_WIDTH = 900
local MAX_SCALE = 1.35
local SCALE_STEP = 0.05

local layout = {
	scale = 1,
	compact = false,
	textFactor = 1,
	textFactorRead = false,
	userFactor = 1,
	userFactorRead = false,
}

--------------------------------------------------------------------------------
-- Réglages du joueur (lecture paresseuse de SettingsController : pas de cycle de require)
--------------------------------------------------------------------------------

local settingsModule: any = nil
local settingsLooked = false
local bound = false

local function getSettings(): any
	if not settingsLooked then
		settingsLooked = true
		local ui = script.Parent
		local client = if ui then ui.Parent else nil
		local controllers = if client then client:FindFirstChild("Controllers") else nil
		local module = if controllers then controllers:FindFirstChild("SettingsController") else nil
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				settingsModule = result
			end
		end
	end
	return settingsModule
end

local function readSetting(key: string): any
	local settings = getSettings()
	if settings and type(settings.Get) == "function" then
		local ok, value = pcall(settings.Get, key)
		if ok then
			return value
		end
	end
	return nil
end

-- Propriétés récentes de GuiService (préférences d'accessibilité Roblox), lues par pcall.
local function readGuiServiceProperty(name: string): any
	local ok, value = pcall(function(): any
		return (GuiService :: any)[name]
	end)
	if ok then
		return value
	end
	return nil
end

local function preferredTextFactor(): number
	local value = readGuiServiceProperty("PreferredTextSize")
	if typeof(value) == "EnumItem" then
		return TEXT_SIZE_FACTORS[(value :: EnumItem).Name] or 1
	end
	return 1
end

--------------------------------------------------------------------------------
-- Polices et tailles
--------------------------------------------------------------------------------

function Theme.font(name: string?): Font
	return FONTS[name or "Body"] or FONTS.Body
end

function Theme.defaultFont(sizeName: string?): string
	return if sizeName and DISPLAY_FONT_SIZES[sizeName] then "Display" else "Body"
end

function Theme.textSize(name: string?): number
	local entry = TEXT_SIZES[name or "Body"] or TEXT_SIZES.Body
	if not layout.textFactorRead then
		layout.textFactorRead = true
		layout.textFactor = preferredTextFactor()
	end
	if not layout.userFactorRead then
		layout.userFactorRead = true
		layout.userFactor = USER_TEXT_FACTORS[tostring(readSetting("textSize"))] or 1
	end
	local base = if layout.compact then entry.compact else entry.normal
	local factor = layout.textFactor * layout.userFactor
	if not entry.scalable then
		factor = 1 + (factor - 1) * 0.5
	end
	return math.floor(base * factor + 0.5)
end

-- Objets texte suivis (clés faibles : un objet détruit disparaît de lui-même).
local textRegistry: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any

local function refreshTexts()
	for object, sizeName in textRegistry do
		pcall(function()
			(object :: any).TextSize = Theme.textSize(sizeName)
		end)
	end
end

function Theme.applyText(object: Instance, size: string?, font: string?)
	local sizeName = size or "Body"
	textRegistry[object] = sizeName
	local target = object :: any
	target.FontFace = Theme.font(font or Theme.defaultFont(sizeName))
	target.TextSize = Theme.textSize(sizeName)
end

function Theme.corner(radius: (string | number)?): UDim
	if radius == "Pill" then
		return UDim.new(0.5, 0)
	elseif type(radius) == "number" then
		return UDim.new(0, radius)
	elseif type(radius) == "string" then
		return UDim.new(0, RADIUS[radius] or RADIUS.Medium)
	end
	return UDim.new(0, RADIUS.Medium)
end

--------------------------------------------------------------------------------
-- Équipes
--------------------------------------------------------------------------------

function Theme.team(team: any): TeamStyle?
	if type(team) ~= "string" then
		return nil
	end
	return TEAMS[team]
end

function Theme.teamLabel(team: any): string
	local style = Theme.team(team)
	if not style then
		return Locale.t("ui.team.none")
	end
	return style.glyph .. " " .. Locale.t(style.labelKey)
end

--------------------------------------------------------------------------------
-- Couleurs et contraste (WCAG 2.x)
--------------------------------------------------------------------------------

local function channel(value: number): number
	if value <= 0.04045 then
		return value / 12.92
	end
	return ((value + 0.055) / 1.055) ^ 2.4
end

function Theme.luminance(color: Color3): number
	return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
end

function Theme.contrast(a: Color3, b: Color3): number
	local la, lb = Theme.luminance(a), Theme.luminance(b)
	local high, low = math.max(la, lb), math.min(la, lb)
	return (high + 0.05) / (low + 0.05)
end

-- Couleur de texte (Ink ou Paper) la plus lisible sur un fond donné.
function Theme.textOn(background: Color3): Color3
	if Theme.contrast(INK, background) >= Theme.contrast(PAPER, background) then
		return INK
	end
	return PAPER
end

-- Garde la couleur demandée si elle est assez contrastée (4,5:1 par défaut), sinon Ink ou Paper.
function Theme.ensureContrast(text: Color3, background: Color3, minimum: number?): Color3
	if Theme.contrast(text, background) >= (minimum or 4.5) then
		return text
	end
	return Theme.textOn(background)
end

function Theme.lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), math.clamp(amount, 0, 1))
end

function Theme.darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), math.clamp(amount, 0, 1))
end

function Theme.toHex(color: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.clamp(math.floor(color.R * 255 + 0.5), 0, 255),
		math.clamp(math.floor(color.G * 255 + 0.5), 0, 255),
		math.clamp(math.floor(color.B * 255 + 0.5), 0, 255)
	)
end

local VARIANT_BASES: { [string]: Color3 } = {
	Primary = Theme.Colors.Primary,
	Secondary = Theme.Colors.Secondary,
	Success = Theme.Colors.Success,
	Warning = Theme.Colors.Warning,
	Danger = Theme.Colors.Danger,
	Accent = Theme.Colors.Accent,
	Dark = NIGHT_RAISED,
	Light = PAPER,
	Ghost = NIGHT_RAISED,
	Disabled = Theme.Colors.Disabled,
}

local variantCache: { [string]: VariantStyle } = {}

function Theme.variant(name: string?): VariantStyle
	local key = if name and VARIANT_BASES[name] then name else "Primary"
	local cached = variantCache[key]
	if cached then
		return cached
	end
	local base = VARIANT_BASES[key]
	local style: VariantStyle
	if key == "Ghost" then
		style = {
			background = base,
			text = PAPER,
			lip = INK,
			hover = Theme.Colors.NightHover,
			pressed = Theme.darken(base, 0.15),
			stroke = Theme.Colors.PaperDim,
			transparency = 1,
		}
	elseif key == "Disabled" then
		style = {
			background = base,
			text = Theme.Colors.DisabledText,
			lip = Theme.darken(base, 0.35),
			hover = base,
			pressed = base,
			stroke = INK,
			transparency = 0,
		}
	elseif key == "Dark" then
		style = {
			background = base,
			text = PAPER,
			lip = INK,
			hover = Theme.Colors.NightHover,
			pressed = Theme.darken(base, 0.2),
			stroke = INK,
			transparency = 0,
		}
	else
		style = {
			background = base,
			text = Theme.textOn(base),
			lip = Theme.darken(base, 0.32),
			hover = Theme.lighten(base, 0.16),
			pressed = Theme.darken(base, 0.12),
			stroke = INK,
			transparency = 0,
		}
	end
	table.freeze(style)
	variantCache[key] = style
	return style
end

--------------------------------------------------------------------------------
-- Mouvement, flashs, transparence
--------------------------------------------------------------------------------

function Theme.isReducedMotion(): boolean
	return readSetting("reducedEffects") == true or readGuiServiceProperty("ReducedMotionEnabled") == true
end

function Theme.isNoFlash(): boolean
	return readSetting("noFlash") == true
end

local function setInstantly(instance: Instance, goals: { [string]: any })
	-- Un tween de durée nulle annule les tweens en cours sur ces propriétés ; l'affectation directe
	-- applique la valeur sans attendre l'image suivante.
	pcall(function()
		TweenService:Create(instance, TweenInfo.new(0), goals):Play()
	end)
	for property, value in goals do
		(instance :: any)[property] = value
	end
end

-- Animation de mouvement/échelle : instantanée quand les animations sont réduites.
function Theme.tween(
	instance: Instance,
	duration: number,
	goals: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween?
	if duration <= 0 or Theme.isReducedMotion() then
		setInstantly(instance, goals)
		return nil
	end
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goals
	)
	tween:Play()
	return tween
end

-- Fondu de couleur ou de transparence (pas un mouvement : conservé même avec les animations réduites).
function Theme.fade(instance: Instance, duration: number, goals: { [string]: any }): Tween?
	if duration <= 0 then
		setInstantly(instance, goals)
		return nil
	end
	local tween = TweenService:Create(instance, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals)
	tween:Play()
	return tween
end

-- Transparence de fond ajustée à la préférence Roblox (0 = le joueur préfère des fonds opaques).
function Theme.backgroundTransparency(base: number): number
	local preferred = readGuiServiceProperty("PreferredTransparency")
	local factor = if type(preferred) == "number" then math.clamp(preferred, 0, 1) else 1
	return math.clamp(base * factor, 0, 1)
end

--------------------------------------------------------------------------------
-- Cadre de sélection manette (modèle partagé, jamais parenté : le moteur le dessine autour de l'objet focalisé)
--------------------------------------------------------------------------------

local selectionImages: { [string]: GuiObject } = {}

function Theme.selectionImage(shape: string?): GuiObject
	local key = if shape == "Pill" then "Pill" else "Rounded"
	local existing = selectionImages[key]
	if existing then
		return existing
	end
	local radius = if key == "Pill" then UDim.new(0.5, 0) else UDim.new(0, RADIUS.Medium + 4)

	local outer = Instance.new("Frame")
	outer.Name = "SelectionGolfChaos" .. key
	outer.BackgroundTransparency = 1
	outer.BorderSizePixel = 0
	outer.Size = UDim2.new(1, 12, 1, 12)
	outer.Position = UDim2.fromOffset(-6, -6)
	local outerCorner = Instance.new("UICorner")
	outerCorner.CornerRadius = radius
	outerCorner.Parent = outer
	local outerStroke = Instance.new("UIStroke")
	outerStroke.Color = INK
	outerStroke.Thickness = 6
	outerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outerStroke.Parent = outer

	local inner = Instance.new("Frame")
	inner.Name = "Anneau"
	inner.BackgroundTransparency = 1
	inner.BorderSizePixel = 0
	inner.Size = UDim2.new(1, -4, 1, -4)
	inner.Position = UDim2.fromOffset(2, 2)
	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = radius
	innerCorner.Parent = inner
	local innerStroke = Instance.new("UIStroke")
	innerStroke.Color = Theme.Colors.Primary
	innerStroke.Thickness = 3.5
	innerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	innerStroke.Parent = inner
	inner.Parent = outer

	selectionImages[key] = outer
	return outer
end

--------------------------------------------------------------------------------
-- Échelle et écrans compacts
--------------------------------------------------------------------------------

function Theme.getScale(): number
	return layout.scale
end

function Theme.isCompact(): boolean
	return layout.compact
end

function Theme.updateViewport(size: Vector2)
	if size.X <= 1 or size.Y <= 1 then
		return -- taille pas encore connue (premier rendu)
	end
	local compact = size.Y < COMPACT_HEIGHT or size.X < COMPACT_WIDTH
	local scale = 1
	if not compact then
		local raw = math.min(size.X / REFERENCE_SIZE.X, size.Y / REFERENCE_SIZE.Y)
		scale = math.clamp(math.floor(raw / SCALE_STEP + 0.5) * SCALE_STEP, 1, MAX_SCALE)
	end
	if scale == layout.scale and compact == layout.compact then
		return
	end
	local compactChanged = compact ~= layout.compact
	layout.scale = scale
	layout.compact = compact
	if compactChanged then
		refreshTexts()
	end
	Theme.Changed:Fire("layout")
end

function Theme.bindSettings()
	if bound then
		return
	end
	bound = true
	local settings = getSettings()
	if settings and type(settings.Changed) == "table" and type(settings.Changed.Connect) == "function" then
		settings.Changed:Connect(function(key: any)
			if key == "reducedEffects" then
				Theme.Changed:Fire("motion")
			elseif key == "noFlash" then
				Theme.Changed:Fire("flash")
			elseif key == "textSize" then
				layout.userFactor = USER_TEXT_FACTORS[tostring(readSetting("textSize"))] or 1
				layout.userFactorRead = true
				refreshTexts()
				Theme.Changed:Fire("text")
			end
		end)
	end
	pcall(function()
		GuiService:GetPropertyChangedSignal("ReducedMotionEnabled" :: any):Connect(function()
			Theme.Changed:Fire("motion")
		end)
	end)
	pcall(function()
		GuiService:GetPropertyChangedSignal("PreferredTextSize" :: any):Connect(function()
			layout.textFactor = preferredTextFactor()
			layout.textFactorRead = true
			refreshTexts()
			Theme.Changed:Fire("text")
		end)
	end)
	layout.textFactor = preferredTextFactor()
	layout.textFactorRead = true
	refreshTexts()
end

return Theme
