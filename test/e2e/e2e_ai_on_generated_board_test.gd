extends GdUnitTestSuite
## GEN-9 (b): NACHTMAHR deploys on a generated board. Tiefwerk seed 42 on a 4 x 4 ft table through the release door,
## the AI seat's units on their tray, the real guided deployment (main's blocked tests from the table, Front Line 12 in,
## the AI on the negative edge). Every AI model must stand inside its band, outside a solid cell (the core's
## solid_cells and the board's CONTAINER cells), and on the surface of its cell (its height = the cell's tier height).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const TRAY := Vector3(5.0, 0.0, 0.0)
const SEED := 42

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.table.setup_table(Vector2(4, 4))
	SoloHarness.start(_main)
	SoloHarness.instant(_main)


func after_test() -> void:
	_main.restore_generated_board({})   # the board leaves while the table is alive
	await get_tree().process_frame
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _ai_unit(i: int) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 2, "Ai%d" % i, [TRAY, TRAY + Vector3(0.03, 0.0, 0.0)])
	var opr := OPRApiClient.OPRUnit.new()
	opr.cost = 100 - i
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


@warning_ignore('unused_parameter')
func test_nachtmahr_deploys_inside_its_band_on_legal_surfaces(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded", timeout := 120000) -> void:
	var record := GeneratedBoard.resolve("tiefwerk", SEED)
	assert_bool(_main.apply_generated_board(record)).override_failure_message("the board was not laid").is_true()
	await E2EBoot.settle(get_tree(), 8)   # the board's colliders join the physics space
	var ai: Array = []
	for i in 4:
		ai.append(_ai_unit(i))
	await SoloHarness.ai_deploys_all(_main)
	await E2EBoot.settle(get_tree())
	var t := AiActRecorder.tiers_of_board(_main.generated_board())
	var heights: Array = t["tiers"]["level_in"]
	var solid := {}
	for i in t["solid_cells"]:
		solid[int(i)] = true
	for c: Array in t.get("board_cells", []):   # the overlay frame is 4 cells larger on each side (plain.rs grid_margin)
		if int(c[2]) == 3:
			solid[(int(c[1]) - 4) * 16 + int(c[0]) - 4] = true
	var placed := 0
	for u: GameUnit in ai:
		for m: ModelInstance in u.models:
			var p: Vector3 = m.node.global_position
			if absf(p.x) > 1.0:
				continue   # still on the tray: counted below
			placed += 1
			var cx := clampi(int(floor((p.x / INCH + 24.0) / 3.0)), 0, 15)
			var cz := clampi(int(floor((p.z / INCH + 24.0) / 3.0)), 0, 15)
			var where := "%s at (%.1f, %.1f, %.2f) in, cell %d,%d" % [u.get_name(), p.x / INCH, p.z / INCH, p.y / INCH, cx, cz]
			print("GEN9 ", where, " tier ", heights[cz * 16 + cx])
			assert_float(p.z / INCH).override_failure_message("outside its band: " + where).is_less_equal(-12.0 + 0.01)
			assert_bool(solid.has(cz * 16 + cx)).override_failure_message("in a solid cell: " + where).is_false()
			assert_float(p.y / INCH).override_failure_message("not on its cell's surface (%s in): %s" % [heights[cz * 16 + cx], where]) \
				.is_equal_approx(float(heights[cz * 16 + cx]), 0.3)
	assert_int(placed).override_failure_message("NACHTMAHR left models on its tray").is_equal(8)
	# the check can fail: a model at ground height in a raised cell is off its surface
	var raised := heights.find(heights.filter(func(h: Variant) -> bool: return float(h) > 0.0)[0])
	assert_bool(absf(0.0 - float(heights[raised])) > 0.3).override_failure_message("plant: a ground model in a raised cell passes").is_true()
