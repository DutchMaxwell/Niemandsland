extends GdUnitTestSuite
## PLAN_RUINTOWN_DRESSING step 1, the TRUTH TEST: the ruin-town dressing changes no gameplay. The core's layout of seeds 41 and 25,
## the colliders of their plan (the solid boxes) and the number of them are pinned to what origin/main made on 22.11. (the plan's
## header); a built board carries exactly one collider per solid box (size and centre) and no other. A generator change re-pins
## and states old -> new in its commit; a dressing change must not touch a pin. Run with NO NML_RUINTOWN_* variable set.
## Re-pinned 25.11. (look plan D-R2 = C: every building lot intact, raised minimum 10 %, at least 8 houses; solids 89 -> 77, 75 -> 73).

const Census := preload("res://tools/boardgen/truth_census.gd")
const IN := 0.0254
const PINS := {
	41: {"layout": "a7cbb602d34ac1e5041494e1c8510244bfb812aa7cc214a97a101f1b59b72714", "solids": 77,
		"colliders": "7a101f7102133d6076194e2f5c496b630d90159bb656627a485fc45ffc2ce575"},
	25: {"layout": "66e8302e1d65af655f4b02d29430399dc8899b222e3e5ce1d6c20b2cc3f594e8", "solids": 73,
		"colliders": "417395614bfe1bcc6d43e800ad8f7bb69eb0888dc3308becdfc101202e05dc2d"},
}
const BUILT_SEEDS := 20   # seeds 1..20 are built whole


func test_the_layout_of_each_pinned_seed_is_the_recorded_one() -> void:
	for board_seed: int in PINS:
		var layout := Census.layout_of(board_seed)
		assert_bool(layout.is_empty()).override_failure_message("seed %d: no layout (NmlCore without boardgen_layout_themed?)" % board_seed).is_false()
		assert_str(Census.layout_digest(layout)).override_failure_message("seed %d layout digest" % board_seed).is_equal(PINS[board_seed]["layout"])


func test_the_solid_boxes_of_each_pinned_seed_are_the_recorded_ones() -> void:
	for board_seed: int in PINS:
		var layout := Census.layout_of(board_seed)
		assert_int(Census.solid_boxes(layout).size()).override_failure_message("seed %d solid boxes" % board_seed).is_equal(PINS[board_seed]["solids"])
		assert_str(Census.collider_digest(layout)).override_failure_message("seed %d collider digest" % board_seed).is_equal(PINS[board_seed]["colliders"])


func test_the_digests_can_fail() -> void:
	var layout := Census.layout_of(41)
	var cell: Dictionary = layout["cells"][0]
	cell["level"] = (int(cell["level"]) + 1) % 4   # one cell one tier higher: a different board
	assert_str(Census.layout_digest(layout)).is_not_equal(PINS[41]["layout"])
	var again := Census.layout_of(41)
	again["cell_in"] = float(again["cell_in"]) + 0.5   # every box moves: a different collider set
	assert_str(Census.collider_digest(again)).is_not_equal(PINS[41]["colliders"])


func test_a_built_board_has_one_collider_per_solid_box_with_its_size_and_centre_and_no_other() -> void:
	var table: Node3D = auto_free(Node3D.new())
	add_child(table)
	for board_seed in range(1, BUILT_SEEDS + 1):
		var layout := Census.layout_of(board_seed)
		var want: Array[Dictionary] = []
		for b: Dictionary in Census.solid_boxes(layout):
			want.append({"size": (b["hi"] - b["lo"]) * IN, "centre": (b["hi"] + b["lo"]) * 0.5 * IN})
		var board := BoardgenGreybox.attach(table, layout)
		var shapes := board.find_children("*", "CollisionShape3D", true, false)
		assert_int(shapes.size()).override_failure_message("seed %d: CollisionShape3D in the whole board" % board_seed).is_equal(want.size())
		var unmatched := 0
		for shape: CollisionShape3D in shapes:
			var size: Vector3 = (shape.shape as BoxShape3D).size
			var at := -1
			for i in want.size():
				if size.is_equal_approx(want[i]["size"]) and shape.position.is_equal_approx(want[i]["centre"]):
					at = i
					break
			if at < 0:
				unmatched += 1
			else:
				want.remove_at(at)
		assert_int(unmatched).override_failure_message("seed %d: colliders with no solid box (size, centre)" % board_seed).is_equal(0)
		assert_int(want.size()).override_failure_message("seed %d: solid boxes with no collider" % board_seed).is_equal(0)
		board.free()
