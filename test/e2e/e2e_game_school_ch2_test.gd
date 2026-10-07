extends GdUnitTestSuite
## E2E walk of Game School chapter 2 (S-02, Build the Table) over the real scenes/main.tscn:
## the five state steps (resize, biome, one scenery piece, auto-layout, deployment type) complete
## the chapter, and an idle boot stays on step 0 and uncompleted.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const TEST_CFG := "user://test_game_school_ch2.cfg"
const FLAGS := ["niemandsland/scenario_mode", "niemandsland/scenario_path",
	"niemandsland/scenario_chapter", "niemandsland/pending_load_path"]

var _saved: Dictionary = {}
var _root_before: Array
var _runner: GdUnitSceneRunner
var _main: Node
var _lesson: LessonRunner


func before_test() -> void:
	_root_before = Boot.root_children(get_tree())
	for flag in FLAGS:
		_saved[flag] = ProjectSettings.get_setting(flag)
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))
	ProjectSettings.set_setting("niemandsland/scenario_mode", true)
	ProjectSettings.set_setting("niemandsland/scenario_path", Spielschule.chapter("S-02").scenario)
	ProjectSettings.set_setting("niemandsland/scenario_chapter", "S-02")
	ProjectSettings.set_setting("niemandsland/pending_load_path", "")
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	_main._lesson_progress_path = TEST_CFG
	await _main.save_manager.load_completed
	_lesson = _main.get_node("LessonRunner") as LessonRunner


func after_test() -> void:
	for flag in FLAGS:
		ProjectSettings.set_setting(flag, _saved[flag])
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))
	Boot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _wait_index(target: int) -> bool:
	var deadline := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		if _lesson.current_index() == target:
			return true
		await get_tree().process_frame
	return false


func _place_one_scenery_piece() -> void:
	var shelf: SandboxTerrainShelf = _main._sandbox_shelf
	shelf.open()
	shelf._refresh_list()
	if shelf._list.item_count > 0:
		shelf._on_item_activated(0)
	else:
		_main.object_manager.spawn_sandbox_terrain("", 0, Vector3.ZERO)


func test_s02_five_state_steps_complete_and_persist(timeout := 60000) -> void:
	assert_int(_lesson.current_index()).is_equal(0)
	_main._set_table_size(Vector2(6, 4))
	assert_bool(await _wait_index(1)).is_true()
	var biomes: Array = _main.table.get_biomes()
	var other := ""
	for key in biomes:
		if String(key) != _main.table.biome:
			other = String(key)
			break
	assert_str(other).is_not_empty()
	_main.table.set_biome(other)
	assert_bool(await _wait_index(2)).is_true()
	_place_one_scenery_piece()
	assert_bool(await _wait_index(3)).is_true()
	_main.map_layout_editor._generate_terrain_layout()
	_main.map_layout_editor._rebuild_derived()
	assert_bool(await _wait_index(4)).is_true()
	_main.map_layout_editor.deployment_type = 1
	_main.map_layout_editor.deployment_type_changed.emit(1)
	var progress := SpielschuleProgress.new(TEST_CFG)
	var deadline := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		progress.load_from_disk()
		if progress.is_completed("S-02"):
			break
		await get_tree().process_frame
	assert_bool(progress.is_completed("S-02")).is_true()
	assert_str((_main.get_node("UI/LessonCard") as LessonCard).get_node("Content/StepText").text).contains("Chapter complete")
	await Boot.settle(get_tree())


func test_idle_s02_stays_unfinished(timeout := 60000) -> void:
	await get_tree().create_timer(3.0).timeout
	var progress := SpielschuleProgress.new(TEST_CFG)
	progress.load_from_disk()
	assert_int(_lesson.current_index()).is_equal(0)
	assert_bool(progress.is_completed("S-02")).is_false()
	await Boot.settle(get_tree())
