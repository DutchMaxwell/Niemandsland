extends GdUnitTestSuite
## GEN-9 (b): NACHTMAHR deploys on a generated board. Tiefwerk seed 42 on a 4 x 4 ft table through the release door,
## the AI seat's units on their tray, the real guided deployment (main's blocked tests from the table, Front Line 12 in,
## the AI on the negative edge). Every AI model must stand inside its band, outside a solid cell (the core's
## solid_cells and the board's CONTAINER cells), and on the surface of its cell (its height = the cell's tier height).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
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


## GEN-9 (c): NACHTMAHR activates on the board - three gff riflemen on ground cells of its band, a human rifleman on a ground
## cell across the board - with no SCRIPT ERROR (the run would stop), and every AI model ends on a legal surface: at its cell's
## tier height, outside a solid cell.
@warning_ignore('unused_parameter')
func test_nachtmahr_activates_on_the_board_and_stays_on_legal_surfaces(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded", timeout := 180000) -> void:
	assert_bool(_main.apply_generated_board(GeneratedBoard.resolve("tiefwerk", SEED))).is_true()
	await E2EBoot.settle(get_tree(), 8)
	var t := AiActRecorder.tiers_of_board(_main.generated_board())
	var heights: Array = t["tiers"]["level_in"]
	var centre := func(cell: int) -> Vector3:
		return Vector3(((cell % 16) * 3.0 + 1.5 - 24.0) * INCH, 0.0, ((cell / 16) * 3.0 + 1.5 - 24.0) * INCH)
	var ground := func(rows: Array) -> Array:
		return range(256).filter(func(c: int) -> bool: return rows.has(c / 16) and float(heights[c]) == 0.0 \
			and not (t["solid_cells"] as Array).has(c))
	var mine: Array = ground.call([1, 2])
	var theirs: Array = ground.call([13, 14])
	var ai: Array = []
	for i in 3:
		var u := ParityTable._make_unit(_main, {"player": 2, "name": "Ai%d" % i, "models": 1, "x_in": 0.0, "z_step_in": 0.0,
			"quality": 4, "defense": 4, "tough": 1, "game_system": "gff", "faction_folder": "robot_legions", "rules": []},
			{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 1, "rules": []})
		(u.models[0] as ModelInstance).node.global_position = centre.call(mine[i * (mine.size() / 3)])
		ai.append(u)
	var foe := ParityTable._make_unit(_main, {"player": 1, "name": "Foe", "models": 1, "x_in": 0.0, "z_step_in": 0.0,
		"quality": 4, "defense": 4, "tough": 3, "game_system": "gff", "faction_folder": "robot_legions", "rules": []},
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 1, "rules": []})
	(foe.models[0] as ModelInstance).node.global_position = centre.call(theirs[theirs.size() / 2])
	await E2EBoot.settle(get_tree())
	var acted := 0
	for i in ai.size():
		var gu: GameUnit = _main.solo_controller.activate_next_ai_unit()
		if gu != null:
			acted += 1
			var r: Dictionary = _main.solo_controller.last_report
			print("GEN9c act %s action=%s shoot=%s dist=%.1f" % [gu.get_name(), r.get("action"), r.get("shoot"), float(r.get("dist_in", 0.0))])
		await E2EBoot.settle(get_tree())
	assert_int(acted).override_failure_message("not every AI unit activated").is_equal(3)
	for u: GameUnit in ai:
		var p: Vector3 = (u.models[0] as ModelInstance).node.global_position
		var cell := clampi(int(floor((p.z / INCH + 24.0) / 3.0)), 0, 15) * 16 + clampi(int(floor((p.x / INCH + 24.0) / 3.0)), 0, 15)
		var where := "%s at (%.1f, %.1f, %.2f) in, tier %s" % [u.get_name(), p.x / INCH, p.z / INCH, p.y / INCH, heights[cell]]
		print("GEN9c ", where)
		assert_bool((t["solid_cells"] as Array).has(cell)).override_failure_message("in a solid cell: " + where).is_false()
		assert_float(p.y / INCH).override_failure_message("off its cell's surface: " + where).is_equal_approx(float(heights[cell]), 0.3)
