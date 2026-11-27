extends GdUnitTestSuite
## The layout behind step 04 of the table setup (step 65.2): one hidden layout editor instance, run from the menu
## without a table. This is also the probe of point (b) of the spec: the editor scene works under a plain node.
## Red before the step: there is no res://scripts/setup_layout.gd.

const SCRIPT := "res://scripts/setup_layout.gd"
const KEY := "niemandsland/pending_table_layout"

var _prev: Variant


func before_test() -> void:
	_prev = ProjectSettings.get_setting(KEY, null)


func after_test() -> void:
	ProjectSettings.set_setting(KEY, _prev)


func _layout() -> Node:
	assert_bool(ResourceLoader.exists(SCRIPT)).override_failure_message("no setup layout").is_true()
	if not ResourceLoader.exists(SCRIPT):
		return null
	var layout: Node = auto_free((load(SCRIPT) as GDScript).new())
	add_child(layout)
	layout.call("set_table", Vector2(6, 4), "gf")
	return layout


func test_the_empty_table_has_no_pieces_and_commits_nothing() -> void:
	var layout := _layout()
	if layout == null:
		return
	assert_str(str(layout.get("way"))).is_equal("empty")
	assert_int(int((layout.call("facts") as Dictionary).pieces)).is_equal(0)
	assert_str(layout.call("label")).is_equal("Empty table")
	layout.call("commit")
	assert_dict(ProjectSettings.get_setting(KEY, null)).is_equal({})


func test_a_generated_layout_has_pieces_and_the_editors_lines() -> void:
	var layout := _layout()
	if layout == null:
		return
	layout.call("choose", "generated")
	var facts: Dictionary = layout.call("facts")
	assert_int(int(facts.pieces)).is_greater(0)
	assert_int((facts.lines as Array).size()).is_greater_equal(2)
	assert_str(str((facts.lines as Array)[0].text)).contains("terrain pieces")
	assert_str(layout.call("label")).is_equal("Auto-generated")


func test_commit_writes_a_file_a_second_editor_loads_with_the_same_pieces() -> void:
	var layout := _layout()
	if layout == null:
		return
	layout.call("choose", "generated")
	var pieces: int = (layout.get("editor").get("placed_pieces") as Array).size()
	layout.call("commit")
	var choice: Dictionary = ProjectSettings.get_setting(KEY, {})
	assert_bool(FileAccess.file_exists(str(choice.get("path", "")))).is_true()
	var second: Node = auto_free((load("res://scenes/map_layout.tscn") as PackedScene).instantiate())
	add_child(second)
	assert_bool(second.load_layout(str(choice.path))).is_true()
	assert_int((second.get("placed_pieces") as Array).size()).is_equal(pieces)
	DirAccess.remove_absolute(str(choice.path))


## Step 65.3: the ready-made table, a layout file, the mirror and the deployment zones (red before: no such ways).
func test_the_ready_made_table_needs_6_by_4() -> void:
	var layout := _layout()
	if layout == null:
		return
	layout.call("set_table", Vector2(4, 4), "gf")
	assert_bool(layout.call("choose", "theme")).is_false()
	assert_str(str(layout.get("way"))).is_equal("empty")
	layout.call("set_table", Vector2(6, 4), "gf")
	assert_bool(layout.call("choose", "theme")).is_true()
	layout.call("commit")
	assert_dict(ProjectSettings.get_setting(KEY, null)).is_equal({"theme": "ruined_borderland"})
	layout.call("set_table", Vector2(4, 4), "gf")   # the size rules the theme out: back to the default
	assert_str(str(layout.get("way"))).is_equal("empty")


func test_a_file_for_another_size_is_refused_and_changes_nothing() -> void:
	var layout := _layout()
	if layout == null or not layout.has_method("load_file"):
		fail("no load_file")
		return
	var path := "user://setup_layout_4x4.json"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://test/fixtures/setup_layout/three_pieces_6x4.json"))
	data.table_size = {"x": 4.0, "y": 4.0}
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(data))
	assert_str(layout.call("load_file", path)).is_equal("This layout is for a 4 × 4 ft table.")
	assert_str(str(layout.get("way"))).is_equal("empty")
	assert_str(layout.call("load_file", "res://test/fixtures/setup_layout/three_pieces_6x4.json")).is_empty()
	assert_str(layout.call("label")).is_equal("Loaded layout")
	assert_int((layout.call("facts") as Dictionary).pieces).is_greater(0)
	DirAccess.remove_absolute(path)


func test_front_line_survives_the_commit_and_a_new_size_generates_again() -> void:
	var layout := _layout()
	if layout == null or not layout.has_method("set_deployment"):
		fail("no set_deployment")
		return
	layout.call("choose", "generated")
	layout.call("set_mirror", true)
	assert_bool(layout.get("editor").get("point_symmetry_enabled")).is_true()
	layout.call("set_deployment", 1)
	layout.call("commit")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		str((ProjectSettings.get_setting(KEY, {}) as Dictionary).get("path", ""))))
	assert_int(int(saved.deployment_type)).is_equal(1)
	layout.call("set_table", Vector2(4, 4), "gf")
	assert_str(str(layout.get("way"))).is_equal("generated")
	assert_int((layout.call("facts") as Dictionary).pieces).is_greater(0)


## GEN-5: the way "board" - a generated board for a 4 x 4 ft table of a system that is offered one (gff: Tiefwerk).
## Commit hands the record and Front Line to the table; off 4 x 4 or off-system the way is refused or dropped.
@warning_ignore('unused_parameter')
func test_a_generated_board_is_a_way_on_4_by_4_for_its_system(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	var layout := _layout()
	if layout == null:
		return
	assert_bool(layout.call("choose", "board")).override_failure_message("6 x 4 gf took a board").is_false()
	layout.call("set_table", Vector2(4, 4), "gf")
	assert_bool(layout.call("choose", "board")).override_failure_message("gf has no generated board").is_false()
	layout.call("set_table", Vector2(4, 4), "gff")
	assert_bool(layout.call("choose", "board")).is_true()
	assert_str(layout.call("label")).is_equal("Generated board")
	var first: Dictionary = layout.get("board")
	assert_dict(first).override_failure_message("no board record (does the core name its boards?)").is_not_empty()
	if first.is_empty():
		return
	assert_str(str(first.get("id", ""))).is_equal("tiefwerk")
	assert_int(int(layout.get("editor").deployment_type)).is_equal(1)
	layout.call("generate")
	assert_int(int((layout.get("board") as Dictionary).get("seed", -1))).is_not_equal(int(first["seed"]))
	layout.call("commit")
	var stored: Dictionary = ProjectSettings.get_setting(KEY, {})
	assert_dict(stored.get("board", {})).is_equal(layout.get("board"))
	assert_str(str(stored.get("path", ""))).is_not_empty()
	layout.call("set_table", Vector2(6, 4), "gff")
	assert_str(str(layout.get("way"))).is_equal("empty")
	assert_dict(layout.get("board")).is_empty()
