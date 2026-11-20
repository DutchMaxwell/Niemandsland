extends GdUnitTestSuite
## The player's real path from the start menu into a game: the menu stores the chosen table size and
## biome in `niemandsland/pending_table_setup`, Main consumes it once, builds the table, plays the
## intro and only then reveals the gameplay UI. Every other e2e suite arms harness mode, which skips
## exactly this chooser → intro → UI hand-off, so a dead end here would reach players unseen.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const SETUP_KEY := "niemandsland/pending_table_setup"
const HARNESS_KEY := "niemandsland/harness_mode"
## Simulated time the intro may take before the UI must be visible (frames of 100 ms).
const MAX_FRAMES := 900

var _roots: Array
var _prev_harness: Variant
var _prev_setup: Variant


func before_test() -> void:
	_prev_harness = ProjectSettings.get_setting(HARNESS_KEY, false)
	_prev_setup = ProjectSettings.get_setting(SETUP_KEY, null)
	ProjectSettings.set_setting(HARNESS_KEY, false)
	_roots = Boot.root_children(get_tree())


func after_test() -> void:
	ProjectSettings.set_setting(HARNESS_KEY, _prev_harness)
	ProjectSettings.set_setting(SETUP_KEY, _prev_setup)
	Boot.free_stray_root_nodes(get_tree(), _roots)


func test_menu_choice_builds_the_table_and_reveals_the_ui() -> void:
	# A non-default choice, so the assertions prove the menu's values arrived.
	ProjectSettings.set_setting(SETUP_KEY, {"size": Vector2(5, 3), "biome": "arid_desert"})
	var runner := scene_runner(Boot.MAIN_SCENE)
	var main: Node = runner.scene()
	var ui: Node = main.get_node("UI")  # a CanvasLayer: has `visible`, is not a CanvasItem
	var frames := 0
	while not ui.visible and frames < MAX_FRAMES:
		await runner.simulate_frames(10, 100)
		frames += 10
	assert_bool(ui.visible).override_failure_message(
		"the gameplay UI never became visible after the menu hand-off (%d frames of 100 ms)" % frames).is_true()
	assert_vector(main.table.table_size).is_equal(Vector2(5, 3))
	assert_str(str(main.table.biome)).is_equal("arid_desert")
	# Consumed once: a later scene load must not replay the menu's choice.
	assert_object(ProjectSettings.get_setting(SETUP_KEY, null)).is_null()


func test_the_picked_game_system_reaches_the_table_and_the_log() -> void:
	# PLAN_GAME_SYSTEM_SWITCH step 3: the setup dict's "system" is applied once, beside the rules level.
	ProjectSettings.set_setting(SETUP_KEY, {"size": Vector2(4, 4), "biome": "temperate_grassland", "system": "aofs"})
	var runner := scene_runner(Boot.MAIN_SCENE)
	var main: Node = runner.scene()
	await runner.simulate_frames(2, 100)
	assert_str(main.opr_army_manager.table_system).is_equal("aofs")
	assert_str(main._table_system()).is_equal("aofs")
	var lines := 0
	for e in main.battle_log.entries():
		if str((e as Dictionary)["text"]) == "Game system: Age of Fantasy: Skirmish":
			lines += 1
	assert_int(lines).is_equal(1)
