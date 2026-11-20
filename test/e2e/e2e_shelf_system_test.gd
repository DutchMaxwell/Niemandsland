extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 11 over the real scenes/main.tscn: on a table set to a fantasy system the shelf drops the
## urban filter and the catalogue, but a piece that is already there - a saved urban ruin, a peer's - still loads and is drawn.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


func test_the_shelf_follows_the_table_and_existing_pieces_stay() -> void:
	var om: ObjectManager = _main.object_manager
	assert_int(om.sandbox_catalog("urban_").size()).is_equal(12)   # the table plays gf by default
	_main.opr_army_manager.table_system = "aofs"   # what the switch sets (step 6)
	assert_str(om.table_system()).is_equal("aofs")
	assert_array(om.sandbox_catalog("urban_")).is_empty()
	assert_int(om.sandbox_catalog("desert_").size()).is_equal(12)
	var labels: Array = []
	_main._sandbox_shelf.open()
	var option: OptionButton = _main._sandbox_shelf._biome_option
	for i in option.item_count:
		labels.append(option.get_item_text(i))
	assert_bool(labels.has("Urban Ruins")).override_failure_message("a fantasy shelf lists Urban Ruins").is_false()
	assert_bool(labels.has("Grassland")).is_true()
	# a piece that already exists (a save, a peer) is never asked about its biome: it loads and is built
	var piece := om.spawn_sandbox_terrain("urban_ruin_small_1f", ObjectManager.SandboxPropKind.RUIN, Vector3.ZERO, false)
	assert_object(piece).override_failure_message("a saved urban ruin did not load on a fantasy table").is_not_null()
	assert_bool(piece.is_inside_tree()).is_true()
