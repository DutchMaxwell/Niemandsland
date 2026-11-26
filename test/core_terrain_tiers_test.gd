extends GdUnitTestSuite
## Plan step 27-pre P2: from PENDING_EPOCH_CORE_TIERS the terrain line the table hands the core carries the generated
## board's ledges (`tiers`, `solid_cells`), taken from the SAME layout the BoardgenGreybox drew - so the core's jumps,
## falls and climbs happen on the board the player sees. Below the epoch, or with no generated board, the line keeps
## its bytes (no key).

var _table: Node3D
var _ov: Node


func before_test() -> void:
	_table = auto_free(Node3D.new())
	add_child(_table)
	_ov = auto_free(Node.new())
	add_child(_ov)


func _core() -> Object:
	return ClassDB.instantiate("NmlCore") if ClassDB.class_exists("NmlCore") else null


func test_the_line_carries_the_drawn_boards_ledges() -> void:
	if _core() == null:
		return   # the binding lives in the core; CI builds the extension
	var g := BoardgenGreybox.attach(_table, _core().boardgen_layout_themed(7, ""))
	var t := AiActRecorder._tiers_for_line(_ov, AiActRecorder.PENDING_EPOCH_CORE_TIERS)
	assert_bool(t.has("tiers") and t.has("solid_cells")).is_true()
	var heights: Array = t["tiers"]["level_in"]
	var cells: Array = g._layout["cells"]
	var level_in: Array = g._layout["level_in"]
	assert_int(heights.size()).is_equal(cells.size())
	var raised := 0
	for i in cells.size():   # every cell: the height the core reads is the level the greybox drew
		assert_float(float(heights[i])).override_failure_message("cell %d" % i) \
			.is_equal_approx(float(level_in[int(cells[i]["level"])]), 0.0001)
		raised += 1 if float(heights[i]) > 0.0 else 0
	assert_int(raised).override_failure_message("a generated board has ledges").is_greater(0)


func test_below_the_epoch_or_without_a_board_the_line_keeps_its_bytes() -> void:
	assert_dict(AiActRecorder._tiers_for_line(_ov, AiActRecorder.PENDING_EPOCH_CORE_TIERS)).override_failure_message("no board").is_empty()
	if _core() == null:
		return
	BoardgenGreybox.attach(_table, _core().boardgen_layout_themed(7, ""))
	assert_dict(AiActRecorder._tiers_for_line(_ov, AiActRecorder.PENDING_EPOCH_CORE_TIERS - 1)).is_empty()
