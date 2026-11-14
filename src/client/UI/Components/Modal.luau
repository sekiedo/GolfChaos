--!strict
--[[
	Modal — fenêtre modale : voile sombre plein écran (bloque les clics derrière), panneau centré qui « saute »
	à l'ouverture (animation coupée quand les effets sont réduits), bouton de fermeture ✕, navigation manette
	confinée au panneau (SelectionGroup).

	  local modal = Modal.new({ parent = gui, titleKey = "menu.title", size = Vector2.new(560, 520),
	                            onClose = function() ScreenManager.Hide("LobbyMenu") end })
	  modal.Content             -- Frame du contenu (marges posées)
	  modal.Open() / modal.Close() -> secondes de l'animation de sortie
	  modal.CloseButton         -- IconButtonApi (nil si closable = false)

	Props : parent (ScreenGui ou Frame plein écran) ; title | titleKey (+ titleVars) ; titleVariant ; size (Vector2
	en pixels design ; le panneau rétrécit sur petit écran : jamais plus de 94 % de la largeur, 88 % de la
	hauteur) ; closable (true) ; onClose ; backdropTransparency (0.35) ; closeOnBackdrop (false) ; name ;
	scroll (true : Content est un cadre défilant à liste verticale ; ses enfants utilisent AutomaticSize Y).
	Avec scroll = false, Content est le cadre fixe du panneau (l'écran gère lui-même le défilement).
	Le panneau porte un UIScale suivi par Theme (échelle des grands écrans).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trove = require(Shared.Util.Trove)

local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Base)
local Panel = require(script.Parent.Panel)
local IconButton = require(script.Parent.IconButton)
local Grid = require(script.Parent.Grid)

export type ModalProps = {
	parent: Instance,
	title: string?,
	titleKey: string?,
	titleVars: { [string]: any }?,
	titleVariant: string?,
	size: Vector2?,
	closable: boolean?,
	onClose: (() -> ())?,
	backdropTransparency: number?,
	closeOnBackdrop: boolean?,
	scroll: boolean?,
	name: string?,
}

export type ModalApi = {
	Root: Frame,
	Backdrop: TextButton,
	Panel: Panel.PanelApi,
	Content: Frame,
	CloseButton: IconButton.IconButtonApi?,
	Scale: UIScale,
	Open: () -> (),
	Close: () -> number,
	IsOpen: () -> boolean,
}

local OPEN_TIME = 0.28
local CLOSE_TIME = 0.14

local Modal = {}

-- UIScale suivis par l'échelle du thème (clés faibles).
local scales: { [UIScale]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local scaleHooked = false

-- UIScale qui suit Theme.getScale() (grands écrans) ; facteur d'animation multiplié par-dessus.
function Modal.trackScale(scale: UIScale)
	scales[scale] = true
	scale.Scale = Theme.getScale()
	if not scaleHooked then
		scaleHooked = true
		Theme.Changed:Connect(function(what: any)
			if what == "layout" then
				for tracked in scales do
					if tracked.Parent then
						tracked.Scale = Theme.getScale()
					end
				end
			end
		end)
	end
end

function Modal.new(props: ModalProps): ModalApi
	local design = props.size or Vector2.new(560, 480)
	local trove = Trove.new()

	local root = Instance.new("Frame")
	root.Name = props.name or "Modale"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = false
	root.ZIndex = 1
	trove:Connect(root.Destroying, function()
		trove:Clean()
	end)

	local backdropTarget = props.backdropTransparency or 0.35
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Voile"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Selectable = false
	backdrop.Active = true
	backdrop.BorderSizePixel = 0
	backdrop.BackgroundColor3 = Theme.Colors.Backdrop
	backdrop.BackgroundTransparency = 1
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 1
	backdrop.Parent = root

	-- Le cadre de placement prend la taille design, plafonnée par l'écran (UISizeConstraint relatif impossible :
	-- on utilise une taille relative avec un maximum en pixels).
	local holder = Instance.new("Frame")
	holder.Name = "Support"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(0.94, 0.88)
	holder.ZIndex = 2
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = design
	constraint.Parent = holder
	holder.Parent = root

	local scale = Instance.new("UIScale")
	scale.Parent = holder
	Modal.trackScale(scale)

	local panel = Panel.new({
		name = "Panneau",
		title = props.title,
		titleKey = props.titleKey,
		titleVars = props.titleVars,
		titleVariant = props.titleVariant,
		size = UDim2.fromScale(1, 1),
		parent = holder,
	})
	panel.Instance.SelectionGroup = true
	panel.Instance.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	panel.Instance.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	panel.Instance.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	panel.Instance.SelectionBehaviorRight = Enum.SelectionBehavior.Stop

	local open = false
	local animToken = 0

	local function requestClose()
		if props.onClose then
			Base.safeCall(props.onClose)
		end
	end

	local closeButton: IconButton.IconButtonApi? = nil
	if props.closable ~= false then
		closeButton = IconButton.new({
			name = "Fermer",
			glyph = "✕",
			variant = "Danger",
			size = "Small",
			anchorPoint = Vector2.new(0.5, 0.5),
			position = UDim2.new(1, -10, 0, 10),
			zIndex = 6,
			parent = panel.Instance,
			onActivated = requestClose,
		})
	end

	if props.closeOnBackdrop then
		trove:Connect(backdrop.Activated, requestClose)
	end

	local api = {} :: ModalApi
	api.Root = root
	api.Backdrop = backdrop
	api.Panel = panel
	if props.scroll ~= false then
		-- Contenu défilant : sur petit écran, la modale garde sa taille tactile et fait défiler son contenu.
		local scroller = Grid.list({ name = "Defilement", gap = 0, padding = 2, size = UDim2.fromScale(1, 1), parent = panel.Content })
		api.Content = scroller.Instance :: any
	else
		api.Content = panel.Content
	end
	api.CloseButton = closeButton
	api.Scale = scale

	function api.Open()
		animToken += 1
		open = true
		root.Visible = true
		backdrop.BackgroundTransparency = 1
		Theme.fade(backdrop, OPEN_TIME * 0.7, { BackgroundTransparency = Theme.backgroundTransparency(backdropTarget) })
		local target = UDim2.fromScale(0.5, 0.5)
		if Theme.isReducedMotion() then
			holder.Position = target
		else
			holder.Position = UDim2.new(0.5, 0, 0.5, 40)
			Theme.tween(holder, OPEN_TIME, { Position = target }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
	end

	function api.Close(): number
		if not open then
			return 0
		end
		open = false
		animToken += 1
		local token = animToken
		Theme.fade(backdrop, CLOSE_TIME, { BackgroundTransparency = 1 })
		if not Theme.isReducedMotion() then
			Theme.tween(holder, CLOSE_TIME, { Position = UDim2.new(0.5, 0, 0.5, 30) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		task.delay(CLOSE_TIME, function()
			if token == animToken and not open then
				root.Visible = false
			end
		end)
		return CLOSE_TIME
	end

	function api.IsOpen(): boolean
		return open
	end

	root.Parent = props.parent
	return api
end

return Modal
