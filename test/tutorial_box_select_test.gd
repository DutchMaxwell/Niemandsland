extends GdUnitTestSuite
## S8-U3: tutorial T-02 step "box" ("Drag a box across empty table to rubber-band-select everything inside
## it") must complete from a REAL rubber band. ObjectManager adds one object per selection_changed emission,
## so the old "selection grew by 2 in one callback" predicate could never fire; the step now listens to
## ObjectManager.box_selection_finished, emitted once when the band is released. These tests drive the real
## producer (_start/_update/_finish_box_selection) through the real director wiring, not a synthetic 2->4 jump.

const Director := preload("res://scripts/tutorial_director.gd")
const Flow := preload("res://scripts/tutorial_flow.gd")
const Progress := preload("res://scripts/tutorial_progress.gd")
const TEST_CFG := "user://test_tutorial_box_select.cfg"


func after_test() -> void:
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))


## An ObjectManager in the tree with a current camera and `count` selectable props in front of it.
## Awaits one frame: the camera's transform only reaches unproject_position after it.
func _table(count: int) -> Dictionary:
	var camera: Camera3D = auto_free(Camera3D.new())
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 1, 1), Vector3.ZERO)
	camera.current = true
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	var props: Array[Node3D] = []
	for i in range(count):
		var prop := Node3D.new()
		prop.add_to_group("selectable")
		om.add_child(prop)
		prop.global_position = Vector3(-0.1 + 0.1 * i, 0, 0)
		props.append(prop)
	await get_tree().process_frame
	return {"om": om, "props": props}


## A director at T-02 "box" (the earlier steps are completed with their own events), wired to `om`.
func _director_at_box_step(om: ObjectManager) -> TutorialDirector:
	var director := auto_free(Director.new()) as TutorialDirector
	director.flow = Flow.new(Flow.build_tool_track())
	director.flow.start_at("T-02")
	director.progress = Progress.new(TEST_CFG)
	director.progress.load_from_disk()
	director._object_manager = om
	director._connect_seams()
	for event in [Flow.Event.UNIT_SELECTED, Flow.Event.UNIT_WHOLE_SELECTED, Flow.Event.MULTI_SELECTED]:
		director._on_event(event)
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("box")
	return director


## The real gesture: press, drag, release. The band covers the whole viewport, or nothing.
func _rubber_band(om: ObjectManager, covers_everything: bool, alt_pressed: bool = false) -> void:
	var size := get_viewport().get_visible_rect().size
	om._start_box_selection(Vector2(1, 1), alt_pressed)
	om._update_box_selection(size - Vector2(1, 1) if covers_everything else Vector2(3, 3))
	om._finish_box_selection(alt_pressed)


func _step_id(director: TutorialDirector) -> String:
	return String(director.flow.current_step().get("id", ""))


func test_a_real_rubber_band_over_several_models_completes_the_box_step() -> void:
	var table := await _table(3)
	var om: ObjectManager = table["om"]
	var director := _director_at_box_step(om)

	_rubber_band(om, true)

	assert_int(om.get_selected_objects().size()).is_equal(3)
	assert_str(_step_id(director)).is_equal("cancel")


func test_a_band_that_catches_a_single_model_does_not_complete_the_step() -> void:
	var table := await _table(1)
	var om: ObjectManager = table["om"]
	var director := _director_at_box_step(om)

	_rubber_band(om, true)

	assert_int(om.get_selected_objects().size()).is_equal(1)
	assert_str(_step_id(director)).is_equal("box")


func test_a_band_over_empty_table_does_not_complete_the_step() -> void:
	var table := await _table(3)
	var om: ObjectManager = table["om"]
	var director := _director_at_box_step(om)

	_rubber_band(om, false)

	assert_int(om.get_selected_objects().size()).is_equal(0)
	assert_str(_step_id(director)).is_equal("box")


func test_selecting_the_same_models_without_a_band_does_not_complete_the_step() -> void:
	# Double-click / select_objects add the models one by one too; only the rubber band is the "box" gesture.
	var table := await _table(3)
	var om: ObjectManager = table["om"]
	var director := _director_at_box_step(om)

	om.select_objects(table["props"])

	assert_int(om.get_selected_objects().size()).is_equal(3)
	assert_str(_step_id(director)).is_equal("box")
