extends GdUnitTestSuite
## The landmark meshes of a seeded boardgen layout: a tank cluster has its tanks and manifold, a crane keeps its tower in
## its cell and its arm high and over the board, everything is two instanced meshes with no colliders, and the same layout
## always plans the same parts. The layouts are the recorded seed 42 (so this suite stands on its own) with the landmarks
## written out by hand, and live seeds when NmlCore hands landmarks over.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"
const LIVE_SEEDS := [1, 7, 11, 23]
const BOARD_HALF_IN := 24.0


func _fixture() -> Dictionary:
	return str_to_var(FileAccess.get_file_as_string(FIXTURE))


func _core() -> Object:
	var core: Object = ClassDB.instantiate("NmlCore") if ClassDB.class_exists("NmlCore") else null
	return core if core != null and core.has_method("boardgen_layout") else null


## The recorded board with only `landmarks` on it.
func _with(landmarks: Array) -> Dictionary:
	var layout := _fixture().duplicate(true)
	layout["landmarks"] = landmarks
	return layout


func _lm(kind: String, x: int, z: int, w: int, h: int, turn := 0) -> Dictionary:
	return {"kind": kind, "x": x, "z": z, "w": w, "h": h, "turn": turn, "terrain": 3, "solid": true}


## Footprint of a landmark in board inches: [lo, hi] as Vector2.
func _rect(lm: Dictionary) -> Array[Vector2]:
	var lo := Vector2(lm["x"], lm["z"]) * 3.0 - Vector2(24, 24)
	return [lo, lo + Vector2(lm["w"], lm["h"]) * 3.0]


func _inside(p: Dictionary, r: Array[Vector2], slack := 0.001) -> bool:
	return p["lo"].x >= r[0].x - slack and p["lo"].z >= r[0].y - slack and p["hi"].x <= r[1].x + slack and p["hi"].z <= r[1].y + slack


func test_a_tank_cluster_has_a_shell_a_cap_and_a_catwalk_per_cell_and_a_valved_pipe_per_neighbouring_pair() -> void:
	var lm := _lm("TankCluster", 5, 5, 3, 2)
	var parts := BoardgenLandmarks.plan(_with([lm]))
	var of_look := func(look: int) -> Array: return parts.filter(func(p: Dictionary) -> bool: return p.get("look", 0) == look)
	assert_int(of_look.call(BoardgenLandmarks.LOOK_TANK).size()).is_equal(6)
	assert_int(of_look.call(BoardgenLandmarks.LOOK_CAP).size()).is_equal(6)
	assert_int(of_look.call(BoardgenLandmarks.LOOK_PIPE).size()).is_equal(2 * 2 + 1 * 3)   # one pipe per pair of neighbouring cells
	var shells: Array = of_look.call(BoardgenLandmarks.LOOK_TANK)
	assert_bool(shells.all(func(p: Dictionary) -> bool: return is_equal_approx(p["hi"].y - p["lo"].y, BoardgenLandmarks.TANK_H))).is_true()
	var rings := parts.filter(func(p: Dictionary) -> bool: return p["shape"] == "torus")
	assert_int(rings.size()).is_equal(6 + 7)   # a hand rail round each tank top and a valve wheel on each pipe
	var rungs := parts.filter(func(p: Dictionary) -> bool: return p["shape"] == "box" and is_equal_approx(p["hi"].y - p["lo"].y, 0.05) and p["hi"].y < BoardgenLandmarks.TANK_H)
	assert_int(rungs.size()).is_equal(6 * 5)   # five rungs on each tank's ladder
	var hoops := parts.filter(func(p: Dictionary) -> bool: return p["shape"] == "box" and is_equal_approx(p["hi"].y - p["lo"].y, 0.04))
	assert_int(hoops.size()).is_equal(6 * 3 * 3)   # three cage hoops of three bars on each ladder
	var legs := parts.filter(func(p: Dictionary) -> bool: return p["shape"] == "box" and is_equal_approx(p["lo"].y, BoardgenLandmarks.SKIN_IN) and p["hi"].y > BoardgenLandmarks.TANK_H and p["hi"].x - p["lo"].x > 0.09)   # 0.1 in square; a ladder rail is 0.05
	assert_int(legs.size()).is_equal(6 * 4)   # the catwalk of each tank stands on four legs that reach the floor, it does not float
	var wheels := parts.filter(func(p: Dictionary) -> bool: return p["shape"] == "torus" and p["colour"] == BoardgenLandmarks.VALVE)
	assert_int(wheels.size()).is_equal(7)
	assert_bool(wheels.all(func(p: Dictionary) -> bool: return p["hi"].x - p["lo"].x >= 0.7)).is_true()   # a valve wheel you can see from the top of the board
	assert_int(parts.filter(func(p: Dictionary) -> bool: return p["colour"] == BoardgenLandmarks.GAUGE).size()).is_equal(6 + 7)   # a gauge on each tank and on each pipe
	assert_int(of_look.call(BoardgenLandmarks.LOOK_JACKET).size()).is_equal(2 * 7)   # two insulated stretches on each pipe
	for p in parts:
		assert_bool(_inside(p, _rect(lm))).override_failure_message("part leaves the footprint: %s" % [p]).is_true()
		assert_float(p["hi"].y).is_less(BoardgenLandmarks.TANK_H + 0.8)   # nothing tall: a tank is a tier-1 block with its rail


func test_a_crane_keeps_tower_and_plinth_in_its_cell_and_its_arm_high_and_over_the_board() -> void:
	for cell in [Vector2i(0, 5), Vector2i(15, 5), Vector2i(6, 4), Vector2i(6, 11), Vector2i(8, 8)]:
		for turn in 4:
			var lm := _lm("Crane", cell.x, cell.y, 1, 1, turn)
			var parts := BoardgenLandmarks.plan(_with([lm]))
			assert_int(parts.size()).is_greater(20)
			var hook: Dictionary = parts.filter(func(p: Dictionary) -> bool: return p.get("look", 0) == BoardgenLandmarks.LOOK_STRIPE and p["lo"].y > 5.0)[0]   # the hook block: the arm is never a stub, even beside the table edge
			var tip := Vector2(hook["lo"].x + hook["hi"].x, hook["lo"].z + hook["hi"].z) * 0.5
			assert_float(tip.distance_to((_rect(lm)[0] + _rect(lm)[1]) * 0.5)).is_greater(3.0)
			for p in parts:
				assert_float(p["hi"].y).is_less(BoardgenLandmarks.CRANE_TOP + 2.0)
				assert_bool(absf(p["lo"].x) <= BOARD_HALF_IN and absf(p["hi"].x) <= BOARD_HALF_IN and absf(p["lo"].z) <= BOARD_HALF_IN and absf(p["hi"].z) <= BOARD_HALF_IN) \
					.override_failure_message("crane part over the table edge: %s" % [p]).is_true()
				if not _inside(p, _rect(lm)):   # the arm, its cable and hook hang above every model (tier 3 + a model's height)
					assert_float(p["lo"].y).is_greater(8.0)


func test_a_crane_has_warning_stripes_on_its_base_and_its_hook_block_a_cable_pair_and_struts_between_the_chords() -> void:
	var lm := _lm("Crane", 6, 5, 1, 1, 0)
	var parts := BoardgenLandmarks.plan(_with([lm]))
	var striped := parts.filter(func(p: Dictionary) -> bool: return p.get("look", 0) == BoardgenLandmarks.LOOK_STRIPE)
	assert_int(striped.size()).is_equal(2)   # the plinth and the hook block
	assert_bool(striped.any(func(p: Dictionary) -> bool: return p["lo"].y < 0.1 and p["hi"].y == 3.0)).is_true()
	var cables := parts.filter(func(p: Dictionary) -> bool: return p["colour"] == BoardgenLandmarks.DARK)
	assert_int(cables.size()).is_equal(2)
	var struts := parts.filter(func(p: Dictionary) -> bool: return is_equal_approx(p["lo"].y, BoardgenLandmarks.CRANE_TOP + 0.35))
	assert_int(struts.size()).is_greater(3)


func test_one_layout_plans_the_same_parts_and_a_different_layout_other_parts() -> void:
	var a := _with([_lm("TankCluster", 5, 5, 2, 2), _lm("Crane", 9, 9, 1, 1, 1)])
	assert_array(BoardgenLandmarks.plan(a)).is_equal(BoardgenLandmarks.plan(a.duplicate(true)))
	assert_bool(BoardgenLandmarks.plan(a) == BoardgenLandmarks.plan(_with([_lm("TankCluster", 6, 5, 2, 2), _lm("Crane", 9, 9, 1, 1, 1)]))).is_false()


func test_build_draws_every_part_in_a_few_instanced_meshes_and_makes_no_colliders() -> void:
	var layout := _with([_lm("TankCluster", 5, 5, 3, 2), _lm("Crane", 9, 9, 1, 1, 1)])
	var node: BoardgenLandmarks = auto_free(BoardgenLandmarks.new())
	add_child(node)
	node.build(layout)
	var meshes := node.find_children("*", "MultiMeshInstance3D", false, false)
	assert_int(meshes.size()).is_equal(3)   # boxes, cylinders and rings
	var instances := 0
	for m: MultiMeshInstance3D in meshes:
		instances += m.multimesh.instance_count
	assert_int(instances).is_equal(BoardgenLandmarks.plan(layout).size())
	assert_int(node.find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)


func test_live_boards_keep_every_part_over_the_board_and_a_tank_cluster_inside_its_footprint() -> void:
	var core := _core()
	if core == null:
		return
	for board_seed in LIVE_SEEDS:
		var layout: Dictionary = core.boardgen_layout(board_seed)
		if not layout.has("landmarks"):
			continue   # a core from before the landmarks
		for p in BoardgenLandmarks.plan(layout):
			assert_bool(absf(p["lo"].x) <= BOARD_HALF_IN and absf(p["hi"].x) <= BOARD_HALF_IN and absf(p["lo"].z) <= BOARD_HALF_IN and absf(p["hi"].z) <= BOARD_HALF_IN) \
				.override_failure_message("seed %s: part over the table edge: %s" % [board_seed, p]).is_true()
		for lm: Dictionary in layout["landmarks"]:
			if lm["kind"] != "TankCluster":
				continue
			for p in BoardgenLandmarks.plan(_with_layout(layout, [lm])):
				assert_bool(_inside(p, _rect(lm), 0.001)).override_failure_message("seed %s: %s part %s" % [board_seed, lm["kind"], p]).is_true()


func _with_layout(layout: Dictionary, landmarks: Array) -> Dictionary:
	var copy := layout.duplicate(true)
	copy["landmarks"] = landmarks
	return copy
