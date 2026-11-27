extends GdUnitTestSuite
## Step 04 of the setup, at the table (menu step 65.1): the layout the setup chose is on the table when it is
## revealed. The setup stores it in niemandsland/pending_table_layout; the reveal gate applies it through the
## layout editor's own load-and-close path. Red before the step: the table opened empty.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const SETUP_KEY := "niemandsland/pending_table_setup"
const LAYOUT_KEY := "niemandsland/pending_table_layout"
const HARNESS_KEY := "niemandsland/harness_mode"
const FIXTURE := "res://test/fixtures/setup_layout/three_pieces_6x4.json"
const PENDING := "user://pending_layout_test.json"
const MAX_FRAMES := 900

var _roots: Array
var _prev: Dictionary = {}


func before_test() -> void:
	for key: String in [SETUP_KEY, LAYOUT_KEY, HARNESS_KEY]:
		_prev[key] = ProjectSettings.get_setting(key, null)
	ProjectSettings.set_setting(HARNESS_KEY, false)
	ProjectSettings.set_setting(SETUP_KEY, {"size": Vector2(6, 4), "biome": "urban_ruins"})
	_roots = Boot.root_children(get_tree())


func after_test() -> void:
	for key: String in _prev:
		ProjectSettings.set_setting(key, _prev[key])
	DirAccess.remove_absolute(PENDING)
	Boot.free_stray_root_nodes(get_tree(), _roots)


func _boot() -> Node:
	var runner := scene_runner(Boot.MAIN_SCENE)
	var main: Node = runner.scene()
	var frames := 0
	while not main.get_node("UI").visible and frames < MAX_FRAMES:
		await runner.simulate_frames(10, 100)
		frames += 10
	return main


func test_the_setups_layout_is_on_the_table_after_the_reveal() -> void:
	FileAccess.open(PENDING, FileAccess.WRITE).store_string(FileAccess.get_file_as_string(FIXTURE))
	ProjectSettings.set_setting(LAYOUT_KEY, {"path": PENDING})
	var main := await _boot()
	assert_int(main.map_layout_editor.placed_pieces.size()).is_equal(3)
	assert_object(ProjectSettings.get_setting(LAYOUT_KEY, null)).override_failure_message("not cleared").is_null()
	assert_bool(FileAccess.file_exists(PENDING)).override_failure_message("the pending file stayed").is_false()


func test_a_missing_file_reveals_the_table_empty() -> void:
	ProjectSettings.set_setting(LAYOUT_KEY, {"path": "user://no_such_pending_layout.json"})
	var main := await _boot()
	assert_bool(main.get_node("UI").visible).is_true()
	assert_int(main.map_layout_editor.placed_pieces.size()).is_equal(0)
	assert_object(ProjectSettings.get_setting(LAYOUT_KEY, null)).is_null()


## Step 65.9: Front Line chosen in the setup stands on the table after the reveal.
func test_front_line_from_the_setup_reaches_the_table() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	data.deployment_type = 1
	FileAccess.open(PENDING, FileAccess.WRITE).store_string(JSON.stringify(data))
	ProjectSettings.set_setting(LAYOUT_KEY, {"path": PENDING})
	var main := await _boot()
	assert_int(int(main.map_layout_editor.deployment_type)).is_equal(1)


## GEN-4: a generated board chosen in the setup stands on the table after the reveal - through the release door, with
## no developer flag - and the rules get its ledges. Red before the step: the "board" choice was ignored.
@warning_ignore('unused_parameter')
func test_a_generated_board_from_the_setup_stands_at_the_table(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	ProjectSettings.set_setting(SETUP_KEY, {"size": Vector2(4, 4), "biome": "urban_ruins"})
	ProjectSettings.set_setting(LAYOUT_KEY, {"board": {"id": "tiefwerk", "theme": "deepworks", "seed": 42}})
	var main := await _boot()
	var board: Dictionary = main.generated_board()
	assert_int(int(board.get("seed", -1))).is_equal(42)
	assert_str(str(board.get("id", ""))).is_equal("tiefwerk")
	assert_bool(AiActRecorder.tiers_of_board(board).has("tiers")).override_failure_message("the core gets no ledges").is_true()
	assert_object(ProjectSettings.get_setting(LAYOUT_KEY, null)).is_null()
	# the board leaves while the table is alive: TableBiomePresenter.request_rebuild asks get_tree() after teardown
	(main.get("_board_look") as Node).queue_free()
	await get_tree().process_frame
