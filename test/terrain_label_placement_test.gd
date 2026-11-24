extends GdUnitTestSuite
## The flat terrain effect labels must sit on their piece and on the table, as compact plaques that cast no shadow.
## They turn toward the camera around their centre, so each check uses the plaque's whole turning circle (half its
## diagonal, measured with the font) rather than one facing. Red on main: the ruins' rule text ran as one ~19 cm line,
## and a piece at the table edge put its label on the edge cell, so the turning plaque swept far off the board.

const OverlayScript := preload("res://scripts/terrain_overlay.gd")
const RUINS := 1
const FOREST := 2

var _overlay: Node3D


func before_test() -> void:
	_overlay = auto_free(OverlayScript.new())
	add_child(_overlay)


## Every cell of a rectangle of grid cells, origin + size.
func _rect(cells: Dictionary, origin: Vector2i, size: Vector2i, ttype: int) -> void:
	for x in size.x:
		for y in size.y:
			cells[origin + Vector2i(x, y)] = ttype


## Half the diagonal of the plaque as the font lays it out (wrapped when the label wraps).
func _reach(lbl: Label3D) -> float:
	var font: Font = ThemeDB.fallback_font
	var wrap_px := lbl.width if lbl.autowrap_mode != TextServer.AUTOWRAP_OFF else -1.0
	var size := font.get_multiline_string_size(lbl.text, HORIZONTAL_ALIGNMENT_CENTER, wrap_px, lbl.font_size)
	return size.length() * lbl.pixel_size / 2.0


## The label's grid-cell bounding box in world metres (grid rotation 0), as Rect2 in x/z.
func _zone_rect(origin: Vector2i, size: Vector2i) -> Rect2:
	var dims: Vector2i = _overlay._grid_dims
	var cell: float = _overlay._cell_size_m
	var min_x := (origin.x - dims.x / 2.0) * cell
	var min_z := (origin.y - dims.y / 2.0) * cell
	return Rect2(min_x, min_z, size.x * cell, size.y * cell)


func test_labels_stay_on_their_piece_and_on_the_table() -> void:
	# 6x4 ft table: a 30x30 grid of 3" cells, the table covers x 3..26 and y 7..22.
	var cells := {}
	var pieces := [
		[Vector2i(3, 10), Vector2i(3, 3), RUINS],    # 9x9" ruin against the left table edge
		[Vector2i(23, 20), Vector2i(3, 3), FOREST],  # 9x9" forest in the bottom-right corner
		[Vector2i(12, 7), Vector2i(3, 2), RUINS],    # 9x6" ruin against the top edge
	]
	for p in pieces:
		_rect(cells, p[0], p[1], p[2])
	_rect(cells, Vector2i(0, 0), Vector2i(2, 2), RUINS)  # wholly off the table: no label at all
	_overlay.update_overlay(cells, Vector2(6, 4), 0.0)
	var labels: Array = _overlay._terrain_labels
	assert_int(labels.size()).override_failure_message("one label per on-table piece").is_equal(pieces.size())
	var half_w := 6.0 * 12.0 * 0.0254 / 2.0
	var half_d := 4.0 * 12.0 * 0.0254 / 2.0
	for lbl: Label3D in labels:
		var reach := _reach(lbl)
		var at := Vector2(lbl.position.x, lbl.position.z)
		var tag := "%s at %s reach %.3f m" % [lbl.text.get_slice("\n", 0), at, reach]
		assert_int(lbl.cast_shadow).override_failure_message("%s casts a shadow" % tag) \
			.is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_bool(absf(at.x) + reach <= half_w + 0.001 and absf(at.y) + reach <= half_d + 0.001) \
			.override_failure_message("%s sweeps off the table" % tag).is_true()
		var on_piece := false
		for p in pieces:
			var r := _zone_rect(p[0], p[1])
			if r.has_point(at) and at.x - reach >= r.position.x - 0.001 and at.x + reach <= r.end.x + 0.001 \
					and at.y - reach >= r.position.y - 0.001 and at.y + reach <= r.end.y + 0.001:
				on_piece = true
		assert_bool(on_piece).override_failure_message("%s does not stay on its piece" % tag).is_true()


func test_a_piece_partly_off_the_table_keeps_its_label_on_the_board() -> void:
	var cells := {}
	_rect(cells, Vector2i(1, 12), Vector2i(4, 3), RUINS)  # reaches two cells past the left table edge (columns 1 and 2 are off the table)
	_overlay.update_overlay(cells, Vector2(6, 4), 0.0)
	var labels: Array = _overlay._terrain_labels
	assert_int(labels.size()).is_equal(1)
	var lbl: Label3D = labels[0]
	assert_float(lbl.position.x - _reach(lbl)).override_failure_message("label at x %.3f hangs off the left edge" % lbl.position.x) \
		.is_greater_equal(-6.0 * 12.0 * 0.0254 / 2.0 - 0.001)
