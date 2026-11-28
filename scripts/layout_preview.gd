class_name LayoutPreview
extends Control
## The picture on step 04's rail: the table top-down on a 3-inch grid, the terrain cells in the layout editor's own
## colours, the deployment bands of Front Line and the objective marks; for the ready-made table the theme's picture.
## Draws from a SetupLayout and redraws on its `changed`.

const THEME_PICTURE := "res://assets/whats_new/borderland.webp"
const INCH := 12.0
const GRID := 3.0
const FRONT_LINE := 12.0   # inches from each long edge
const EditorGrid := preload("res://scripts/map_layout_grid.gd")
const Terrain := preload("res://scripts/map_layout.gd").TerrainType   # the editor's own lines: the picture is its picture
const DOTS := [Vector2(0.3, 0.3), Vector2(0.7, 0.45), Vector2(0.4, 0.75)]   # forest / dangerous texture in a cell

var layout: SetupLayout
var tagline: Label


func _init() -> void:
	tagline = Label.new()
	tagline.add_theme_font_override(&"font", HouseStyle.mono())
	tagline.add_theme_font_size_override(&"font_size", 14)
	tagline.add_theme_color_override(&"font_color", HouseStyle.MUTED)
	tagline.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT)
	var plate := StyleBoxFlat.new()   # the caption sits on the board's lower edge on a dark plate (sheet 03c)
	plate.bg_color = HouseStyle.SHEET_FILL
	plate.set_corner_radius_all(HouseStyle.RADIUS_KEYCAP)
	plate.content_margin_left = HouseStyle.PAD_PILL_X
	plate.content_margin_right = HouseStyle.PAD_PILL_X
	tagline.add_theme_stylebox_override(&"normal", plate)
	add_child(tagline)


func show_layout(source: SetupLayout) -> void:
	layout = source
	layout.changed.connect(queue_redraw)
	queue_redraw()


## The board inside `box`, centred, keeping the table's shape.
static func board_rect(table_feet: Vector2, box: Rect2) -> Rect2:
	var scale := minf(box.size.x / table_feet.x, box.size.y / table_feet.y)
	var size := table_feet * scale
	return Rect2(box.position + (box.size - size) / 2, size)


## The editor's cells (a square grid of `grid_n` cells centred on the table) as rects on `board`, cut to the board.
static func cell_rects(cells: Array[Vector2i], grid_n: int, table_feet: Vector2, board: Rect2) -> Array[Rect2]:
	var per_inch := board.size.x / (table_feet.x * INCH)
	var rects: Array[Rect2] = []
	for cell in cells:
		var inches := (Vector2(cell) - Vector2.ONE * grid_n / 2.0) * GRID + table_feet * INCH / 2
		var rect := Rect2(board.position + inches * per_inch, Vector2.ONE * GRID * per_inch).intersection(board)
		if rect.has_area():
			rects.append(rect)
	return rects


func _draw() -> void:
	if layout == null:
		return
	var editor := layout.editor
	var feet: Vector2 = editor.table_size_feet
	var board := board_rect(feet, Rect2(Vector2.ZERO, size))
	tagline.text = "TOP-DOWN · %s × %s FT · 3 IN GRID" % [String.num(feet.x).trim_suffix(".0"),
		String.num(feet.y).trim_suffix(".0")]
	tagline.reset_size()
	tagline.position = board.position + Vector2(HouseStyle.GAP_ROW, board.size.y - tagline.size.y - HouseStyle.GAP_ROW)
	if layout.way == "theme":
		draw_texture_rect(load(THEME_PICTURE), board, false)
		return
	draw_rect(board, HouseStyle.WELL)
	var per_inch := board.size.x / (feet.x * INCH)
	for x in range(0, int(feet.x * INCH) + 1, int(GRID)):
		draw_line(board.position + Vector2(x * per_inch, 0), board.position + Vector2(x * per_inch, board.size.y), EditorGrid.GRID_LINE)
	for y in range(0, int(feet.y * INCH) + 1, int(GRID)):
		draw_line(board.position + Vector2(0, y * per_inch), board.position + Vector2(board.size.x, y * per_inch), EditorGrid.GRID_LINE)
	if editor.deployment_type == 1:
		for edge: float in [0.0, board.size.y - FRONT_LINE * per_inch]:
			draw_rect(Rect2(board.position + Vector2(0, edge), Vector2(board.size.x, FRONT_LINE * per_inch)),
				Color(HouseStyle.ACCENT, 0.12))
	var grid_n: int = editor._calculate_grid_dimensions().x
	for cell: Vector2i in editor.grid_cells:
		var type: int = editor.grid_cells[cell]
		var colour: Color = editor.TERRAIN_COLORS.get(type, Color.TRANSPARENT)
		for rect in cell_rects([cell] as Array[Vector2i], grid_n, feet, board):
			_draw_cell(rect, type, colour)
	for objective: Vector2 in editor.mission_objectives:
		draw_circle(board.position + objective * per_inch, 6.0, HouseStyle.GOLD, false, 2.0, true)
	draw_rect(board, HouseStyle.MUTED, false, 1.0)   # the board's edge, as the editor's table rim


## One cell as the layout editor draws it: the fill, its rim, a ruin's accent wall inset, dots on forest and hazard.
func _draw_cell(rect: Rect2, type: int, colour: Color) -> void:
	draw_rect(rect, colour)
	draw_rect(rect, EditorGrid.CELL_BORDER, false, 1.0)
	match type:
		Terrain.RUINS:
			draw_rect(rect.grow(-rect.size.x * 0.15), EditorGrid.RUIN_INSET_LINE, false, 2.0)
		Terrain.FOREST, Terrain.DANGEROUS:
			for dot: Vector2 in DOTS:
				draw_circle(rect.position + rect.size * dot, maxf(1.0, rect.size.x * 0.06), Color(HouseStyle.INK, 0.6))
