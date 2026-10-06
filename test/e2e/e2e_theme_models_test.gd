extends GdUnitTestSuite
## Lead D16: the one-click theme is refused while a model stands inside the footprint of a piece it would place, and it
## never moves the model (positions are rules). The probe model stands 4" from the centre of the large wood at
## (-31.35", -3.58"), turned 81.3°: along the table's depth that is inside the turned 9x6" footprint, along its width
## it is outside — so the check follows the piece's turn.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const IN2M := 0.0254
const WOOD := Vector3(-31.35, 0.0, -3.58) * IN2M

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.object_manager.solid_models_library().apply_manifest_text("{}")
	_main.table.setup_table(Vector2(6, 4))
	_main.terrain_overlay.grid_cells.clear()


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _live() -> int:
	return ObjectManager.sandbox_pieces(_main.get_tree()).filter(func(n: Node) -> bool:
		return not bool(n.get_meta("deleted", false))).size()


func test_refused_while_a_model_stands_where_a_piece_would_go() -> void:
	var model: Node3D = auto_free(Node3D.new())
	model.add_to_group("miniature")
	_main.object_manager.add_child(model)
	model.global_position = WOOD + Vector3(0.0, 0.0, 4.0 * IN2M)   # along the depth: inside the turned wood
	assert_bool(_main.apply_table_theme("ruined_borderland")).is_false()
	assert_int(_live()).is_equal(0)
	assert_vector(model.global_position).is_equal_approx(WOOD + Vector3(0.0, 0.0, 4.0 * IN2M), Vector3.ONE * 1e-4)
	model.global_position = WOOD + Vector3(4.0 * IN2M, 0.0, 0.0)   # along the width: outside it
	assert_bool(_main.apply_table_theme("ruined_borderland")).is_true()
	assert_int(_live()).is_equal(14)
