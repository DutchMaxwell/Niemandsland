extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 21: a table set up on Age of Fantasy: Skirmish shows that on its chip from the first frame - the chip is
## built before the setup's pick is applied, so applying it must refresh the chip (found by the step 22 end-to-end).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const SETUP_KEY := "niemandsland/pending_table_setup"

var _setup_backup: Variant
var _root_before: Array


func before_test() -> void:
	_setup_backup = ProjectSettings.get_setting(SETUP_KEY, null)
	_root_before = E2EBoot.root_children(get_tree())


func after_test() -> void:
	ProjectSettings.set_setting(SETUP_KEY, _setup_backup)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


func test_the_chip_shows_the_system_the_setup_picked() -> void:
	E2EBoot.arm_harness_mode()
	ProjectSettings.set_setting(SETUP_KEY, {"size": Vector2(4, 4), "biome": "temperate_grassland", "system": "aofs"})
	var runner := scene_runner(E2EBoot.MAIN_SCENE)
	var main: Node = runner.scene()
	await runner.simulate_frames(4)
	assert_str(main._table_system()).is_equal("aofs")
	assert_str(main._system_chip.text).is_equal("SYSTEM: AoFS")
