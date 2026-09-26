extends GdUnitTestSuite
## E2E — D15 / Q6 (GF/AoF v3.5.1 p.11 "COVER TERRAIN"): the reader the dice run on, main._solo_majority_in_cover, on
## the REAL terrain overlay. A multi-model unit gets the +1 Defense only when the majority of its models stand FULLY
## inside cover terrain; the old centre probe gave it to a squad whose bases straddled the wood's rim.
## A single-model unit keeps "mostly inside" = the centre probe. Companion of test/cover_fully_inside_test.gd
## (SoloController's EV readers + the TerrainRules helper). Controls are declared first (gdUnit drops tests
## declared after a failing one).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const SEED := Vector3(0.03, 0.0, 0.03)   # a point that certainly lies inside SOME 3" cell

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Paints ONE forest cell around SEED and measures its world extent with the overlay itself (1 mm steps), so the
## test never hard-codes the grid geometry. Returns Rect2(x_lo, z_lo, width, depth) in metres.
func _paint_one_forest_cell() -> Rect2:
	var o: Node3D = _main.terrain_overlay
	assert_float(o.grid_rotation_degrees).override_failure_message("precondition: an unrotated grid").is_equal(0.0)
	o.grid_cells[o.world_to_cell(SEED)] = o.TerrainType.FOREST
	var forest: int = int(o.TerrainType.FOREST)
	var lo := SEED
	var hi := SEED
	while o.get_terrain_at_world_position(lo - Vector3(0.001, 0, 0)) == forest:
		lo.x -= 0.001
	while o.get_terrain_at_world_position(hi + Vector3(0.001, 0, 0)) == forest:
		hi.x += 0.001
	var z_lo := SEED.z
	var z_hi := SEED.z
	while o.get_terrain_at_world_position(Vector3(SEED.x, 0, z_lo - 0.001)) == forest:
		z_lo -= 0.001
	while o.get_terrain_at_world_position(Vector3(SEED.x, 0, z_hi + 0.001)) == forest:
		z_hi += 0.001
	return Rect2(lo.x, z_lo, hi.x - lo.x, z_hi - z_lo)


func _unit(pid: int, unit_name: String, positions: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func test_a_squad_well_inside_the_wood_gets_cover_on_the_dice_reader() -> void:
	var cell := _paint_one_forest_cell()
	var mid := cell.get_center()
	var squad := _unit(1, "Woodsmen", [Vector3(mid.x, 0, mid.y), Vector3(mid.x + 0.01, 0, mid.y), Vector3(mid.x - 0.01, 0, mid.y)])
	assert_bool(_main._solo_majority_in_cover(squad)).is_true()
	assert_int(_main._solo_cover_defense(squad, 4)).is_equal(3)


func test_a_single_model_straddling_the_rim_is_mostly_inside() -> void:
	var cell := _paint_one_forest_cell()
	var hero := _unit(1, "Lone Hero", [Vector3(cell.end.x - 0.004, 0, cell.get_center().y)])
	assert_bool(_main._solo_majority_in_cover(hero)).is_true()
	assert_int(_main._solo_cover_defense(hero, 4)).is_equal(3)


func test_a_squad_straddling_the_rim_gets_no_cover_on_the_dice_reader() -> void:
	# Every centre is in the wood, every base crosses its edge: the centre probe gave the +1, the book says
	# "fully inside" — so the defender saves at the printed Defense.
	var cell := _paint_one_forest_cell()
	var z := cell.get_center().y
	var squad := _unit(1, "Rim Squad", [Vector3(cell.end.x - 0.004, 0, z), Vector3(cell.end.x - 0.005, 0, z), Vector3(cell.end.x - 0.006, 0, z)])
	assert_bool(_main._solo_majority_in_cover(squad)) \
		.override_failure_message("D15 — the dice reader gave a squad straddling the wood's edge the +1 Defense (centre probe)") \
		.is_false()
	assert_int(_main._solo_cover_defense(squad, 4)).is_equal(4)
