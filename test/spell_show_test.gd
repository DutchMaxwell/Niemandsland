extends GdUnitTestSuite
## SpellShow, the charge (the spells lane's gates, maintainer look verdicts 05.10.: all spells GO): a declaration
## counts once; invalid origins, radii and elements draw nothing;
## Performance draws nothing, Low and Reduce Motion a still form (no particles, no lights, no spin); waiting charges
## are capped and expire; a charge never touches the game's RNG.

var _preset: int
var _motion: bool


func before_test() -> void:
	_preset = GraphicsSettings.current_preset
	_motion = GraphicsSettings.reduce_motion
	GraphicsSettings.current_preset = 2
	GraphicsSettings.reduce_motion = false


func after_test() -> void:
	GraphicsSettings.current_preset = _preset
	GraphicsSettings.reduce_motion = _motion


func _show() -> SpellShow:
	var show := auto_free(SpellShow.new()) as SpellShow
	show.force_for_tests = true
	add_child(show)
	show.enabled = true
	return show


func test_a_declaration_counts_once_and_leaves_the_game_rng_alone() -> void:
	seed(5)
	var expected := randi()
	seed(5)
	var show := _show()
	show.begin("cast", Vector3.ZERO, 0.3, 0, 71)
	var count := show.get_child_count()
	show.begin("cast", Vector3.ZERO, 0.3, 0, 71)
	assert_int(show.get_child_count()).is_equal(count)
	assert_int(show._columns.size()).is_equal(1)
	assert_int(randi()).is_equal(expected)


func test_invalid_origins_radii_and_elements_draw_nothing() -> void:
	var show := _show()
	for point: Vector3 in [Vector3.INF, Vector3(NAN, 0, 0), Vector3(101, 0, 0)]:
		show.begin("bad", point, 0.3, 0, 1)
	for radius: float in [-1.0, 0.0, NAN, INF]:
		show.begin("bad", Vector3.ZERO, radius, 0, 1)
	for element: int in [-1, 5, 999]:
		show.begin("bad", Vector3.ZERO, 0.3, element, 1)
	assert_int(show.get_child_count()).is_zero()
	assert_int(show._columns.size()).is_zero()


func test_quality_ladder_and_reduced_motion() -> void:
	GraphicsSettings.current_preset = 0
	var off := _show()
	off.begin("cast", Vector3.ZERO, 0.3, 0, 1)
	assert_int(off.get_child_count()).is_zero()
	GraphicsSettings.current_preset = 1
	var low := _show()
	low.begin("cast", Vector3.ZERO, 0.3, 0, 1)
	assert_int(low.get_child_count()).is_equal(1)
	assert_int(low.find_children("*", "MultiMeshInstance3D", true, false).size()).is_zero()
	assert_int(low.find_children("*", "Light3D", true, false).size()).is_zero()
	var focus: Node3D = low.get_child(0)
	var transform := focus.transform
	await get_tree().create_timer(0.15).timeout
	assert_object(focus.transform).override_failure_message("Low: no spin").is_equal(transform)
	GraphicsSettings.current_preset = 2
	GraphicsSettings.reduce_motion = true
	var still := _show()
	still.begin("cast", Vector3.ZERO, 0.3, 1, 1)
	var still_focus: Node3D = still.get_child(0)
	var still_transform := still_focus.transform
	await get_tree().create_timer(0.15).timeout
	assert_object(still_focus.transform).override_failure_message("Reduce Motion: no spin").is_equal(still_transform)
	assert_int(still.find_children("*", "MultiMeshInstance3D", true, false).size()).is_zero()


func test_waiting_charges_are_capped_and_expire(timeout := 40000) -> void:
	var show := _show()
	for i in SpellShow.MAX_CASTS + 3:
		show.begin(str(i), Vector3.ZERO, 0.3, 0, 71)
	assert_int(show._columns.size()).is_equal(SpellShow.MAX_CASTS)
	await get_tree().create_timer(SpellShow.MAX_HOLD_S + 0.1).timeout
	assert_int(show._columns.size()).is_zero()
	assert_int(show.get_child_count()).is_zero()
