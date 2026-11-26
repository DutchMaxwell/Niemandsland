extends GdUnitTestSuite
## Plan step 27-pre P2: from PENDING_EPOCH_CORE_TIERS the terrain line the table hands the core carries the generated
## board's ledges (`tiers`, `solid_cells`) of the board main's door drew (`generated_board()`: its seed and theme) - the
## SAME layout the player sees, so the core's jumps, falls and climbs happen on it. Below the epoch, or with no generated
## board, the line keeps its bytes (no key). The board look itself stays behind main.gd's door (tools/ci_path_classes.py).

var _ov: Node


## main's shape as `_tiers_for_line` reads it: an ancestor of the overlay that answers `generated_board()`.
class BoardOwner extends Node:
	var board := {}
	func generated_board() -> Dictionary:
		return board


func before_test() -> void:
	_ov = auto_free(Node.new())
	add_child(_ov)


## The line finds the board through the overlay's owner (main), at any depth - not through the tree's current scene.
func test_the_line_reads_the_board_of_the_overlays_owner() -> void:
	if _core() == null:
		return
	var owner_node: BoardOwner = auto_free(BoardOwner.new())
	owner_node.board = {"seed": 7, "theme": "deepworks"}
	add_child(owner_node)
	var mid: Node = auto_free(Node.new())
	owner_node.add_child(mid)
	var ov: Node = auto_free(Node.new())
	mid.add_child(ov)
	assert_bool(AiActRecorder._tiers_for_line(ov, AiActRecorder.PENDING_EPOCH_CORE_TIERS).has("tiers")).is_true()
	assert_dict(AiActRecorder._tiers_for_line(ov, AiActRecorder.PENDING_EPOCH_CORE_TIERS - 1)).is_empty()


func _core() -> Object:
	return ClassDB.instantiate("NmlCore") if ClassDB.class_exists("NmlCore") else null


func test_the_ledges_are_the_drawn_boards() -> void:
	if _core() == null:
		return   # the binding lives in the core; CI builds the extension
	var t := AiActRecorder.tiers_of_board({"seed": 7, "theme": "deepworks"})
	assert_bool(t.has("tiers") and t.has("solid_cells")).is_true()
	var drawn: Dictionary = _core().boardgen_layout_themed(7, "deepworks")   # what the door draws for seed 7
	var heights: Array = t["tiers"]["level_in"]
	var cells: Array = drawn["cells"]
	assert_int(heights.size()).is_equal(cells.size())
	var raised := 0
	for i in cells.size():   # every cell: the height the core reads is the level the board shows
		assert_float(float(heights[i])).override_failure_message("cell %d" % i) \
			.is_equal_approx(float(drawn["level_in"][int(cells[i]["level"])]), 0.0001)
		raised += 1 if float(heights[i]) > 0.0 else 0
	assert_int(raised).override_failure_message("a generated board has ledges").is_greater(0)


func test_below_the_epoch_or_without_a_board_the_line_keeps_its_bytes() -> void:
	assert_dict(AiActRecorder._tiers_for_line(_ov, AiActRecorder.PENDING_EPOCH_CORE_TIERS)) \
		.override_failure_message("this scene has no generated board").is_empty()
	assert_dict(AiActRecorder.tiers_of_board({})).is_empty()
	if _core() == null:
		return
	var board := {"seed": 7, "theme": "deepworks"}
	assert_dict(AiActRecorder.tiers_at_epoch(board, AiActRecorder.PENDING_EPOCH_CORE_TIERS - 1)) \
		.override_failure_message("one epoch below: the line a record played").is_empty()
	assert_bool(AiActRecorder.tiers_at_epoch(board, AiActRecorder.PENDING_EPOCH_CORE_TIERS).has("tiers")).is_true()
