--!strict
--[[
	Grid — zone défilante (ScrollingFrame) à grille ou en liste, toile automatique, barre de défilement stylée.
	Les cellules sélectionnables sont parcourues à la manette ; le cadre défile pour garder la sélection visible.

	  local grid = Grid.new({ parent = panel.Content, cellSize = Vector2.new(140, 160), size = UDim2.fromScale(1, 1) })
	  someCell.Parent = grid.Instance       grid.Clear()       grid.ScrollToTop()

	  local list = Grid.list({ parent = frame, gap = 8 })      -- variante en colonne (lignes pleine largeur)

	Props : cellSize (Vector2, grille) ; gap (Spacing.S) ; padding (Spacing.XS) ; size ; fillColumns (true : les
	cellules s'élargissent pour remplir la ligne, au moins cellSize.X) ; + communs (name, parent, position,
	anchorPoint, layoutOrder, zIndex, visible).
]]

local GuiService = game:GetService("GuiService")

local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Base)

export type GridProps = {
	cellSize: Vector2?,
	gap: number?,
	padding: number?,
	size: UDim2?,
	fillColumns: boolean?,
	name: string?,
	parent: Instance?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

export type GridApi = {
	Instance: ScrollingFrame,
	Layout: UIGridStyleLayout,
	Clear: () -> (),
	ScrollToTop: () -> (),
}

local Grid = {}

local function newScroller(props: GridProps): ScrollingFrame
	local frame = Instance.new("ScrollingFrame")
	frame.Name = props.name or "Grille"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = props.size or UDim2.fromScale(1, 1)
	frame.ScrollingDirection = Enum.ScrollingDirection.Y
	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	frame.CanvasSize = UDim2.new()
	frame.ScrollBarThickness = 8
	frame.ScrollBarImageColor3 = Theme.Colors.Primary
	frame.ScrollBarImageTransparency = 0.1
	frame.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	frame.Selectable = false
	frame.SelectionGroup = false
	frame.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	Base.padding(frame, props.padding or Theme.Spacing.XS)
	return frame
end

-- Garde l'objet focalisé à la manette visible dans le cadre défilant.
local function followSelection(frame: ScrollingFrame)
	local trove = Base.lifetime(frame)
	trove:Connect(GuiService:GetPropertyChangedSignal("SelectedObject"), function()
		local selected = GuiService.SelectedObject
		if not selected or not selected:IsDescendantOf(frame) then
			return
		end
		local top = frame.AbsolutePosition.Y
		local bottom = top + frame.AbsoluteSize.Y
		local itemTop = selected.AbsolutePosition.Y
		local itemBottom = itemTop + selected.AbsoluteSize.Y
		local margin = 12
		local canvas = frame.CanvasPosition
		if itemTop < top + margin then
			frame.CanvasPosition = Vector2.new(canvas.X, math.max(0, canvas.Y - (top + margin - itemTop)))
		elseif itemBottom > bottom - margin then
			frame.CanvasPosition = Vector2.new(canvas.X, canvas.Y + (itemBottom - (bottom - margin)))
		end
	end)
end

local function finish(frame: ScrollingFrame, layout: UIGridStyleLayout, props: GridProps): GridApi
	Base.applyCommon(frame, {
		position = props.position,
		anchorPoint = props.anchorPoint,
		layoutOrder = props.layoutOrder,
		zIndex = props.zIndex,
		visible = props.visible,
	})
	followSelection(frame)
	if props.parent then
		frame.Parent = props.parent
	end

	local api = {} :: GridApi
	api.Instance = frame
	api.Layout = layout

	function api.Clear()
		for _, child in frame:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	function api.ScrollToTop()
		frame.CanvasPosition = Vector2.zero
	end

	return api
end

function Grid.new(props: GridProps): GridApi
	local frame = newScroller(props)
	local cell = props.cellSize or Vector2.new(140, 140)
	local gap = props.gap or Theme.Spacing.S

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(cell.X, cell.Y)
	layout.CellPadding = UDim2.fromOffset(gap, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Parent = frame

	if props.fillColumns ~= false then
		-- Répartit la largeur disponible entre les colonnes (cellules jamais plus étroites que cellSize.X).
		local function relayout()
			local width = frame.AbsoluteSize.X - frame.ScrollBarThickness - 2 * (props.padding or Theme.Spacing.XS)
			local scale = Theme.getScale()
			local logical = width / math.max(scale, 0.01)
			local columns = math.max(1, math.floor((logical + gap) / (cell.X + gap)))
			local cellWidth = math.floor((logical - gap * (columns - 1)) / columns)
			layout.CellSize = UDim2.fromOffset(math.max(cell.X, cellWidth), cell.Y)
		end
		local trove = Base.lifetime(frame)
		trove:Connect(frame:GetPropertyChangedSignal("AbsoluteSize"), relayout)
		task.defer(relayout)
	end

	return finish(frame, layout, props)
end

function Grid.list(props: GridProps): GridApi
	local frame = newScroller(props)
	frame.Name = props.name or "Liste"
	local layout = Base.list(frame, Enum.FillDirection.Vertical, props.gap or Theme.Spacing.S, Enum.HorizontalAlignment.Center)
	return finish(frame, layout, props)
end

return Grid
