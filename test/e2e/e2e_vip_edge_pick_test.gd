extends GdUnitTestSuite
## VIP Escort, the human defender's edge choice (maintainer choice B): the Map Tool shades both 6" edge
## bands and ONE click inside a band picks the starting spot; the z sign is the deploy edge. RED (the
## parent): the Map Tool has no such mode, so a human defender cannot place the VIP at all.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _chosen: Array = []
var _refused := 0


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_chosen = []
	_refused = 0
	var editor: Control = _main.map_layout_editor
	editor.vip_spot_chosen.connect(func(spot: Vector2) -> void: _chosen.append(spot))
	editor.vip_pick_refused.connect(func() -> void: _refused += 1)
	_main._on_map_layout_pressed()
	await _runner.simulate_frames(2)
	editor.begin_vip_pick()


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


func _click_table_spot(x_in: float, z_in: float) -> void:
	var editor: Control = _main.map_layout_editor
	var inch: Vector2 = editor._relic_world_to_inch(Vector3(x_in * 0.0254, 0.0, z_in * 0.0254))
	var canvas_pos: Vector2 = editor.grid_container.get_global_transform() * editor._inch_to_screen_pos(inch)
	E2EBoot.motion_canvas(get_viewport(), canvas_pos)
	E2EBoot.click_canvas(get_viewport(), canvas_pos, true)
	E2EBoot.click_canvas(get_viewport(), canvas_pos, false)


func test_a_click_inside_either_band_picks_the_spot() -> void:
	_click_table_spot(10.0, -21.0)
	_click_table_spot(-7.0, 21.0)
	assert_int(_chosen.size()).is_equal(2)
	assert_float((_chosen[0] as Vector2).x).is_equal_approx(10.0, 0.3)
	assert_float((_chosen[0] as Vector2).y).is_equal_approx(-21.0, 0.3)
	assert_float((_chosen[1] as Vector2).y).is_equal_approx(21.0, 0.3)
	assert_int(_refused).is_equal(0)


func test_a_click_outside_the_bands_is_refused() -> void:
	_click_table_spot(0.0, 0.0)
	_click_table_spot(0.0, 17.0)   # 7" from the edge: just outside the 6" band
	assert_int(_chosen.size()).is_equal(0)
	assert_int(_refused).is_equal(2)


func test_the_bands_are_the_two_z_edges_and_escape_leaves_the_mode() -> void:
	var editor: Control = _main.map_layout_editor
	var bands: Array = editor.vip_band_polygons()
	assert_int(bands.size()).is_equal(2)
	assert_int((bands[0] as PackedVector2Array).size()).is_equal(4)
	editor._on_close_pressed()
	assert_bool(editor.vip_pick_active).is_false()
