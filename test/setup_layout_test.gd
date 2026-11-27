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
