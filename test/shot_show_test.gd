extends GdUnitTestSuite
## ShotShow (maintainer look verdicts: "not in a row, more like chaotic fire", then shots GO): the volley's chaos is a
## pure function of the cue's seed (every peer sees the same) and not a row; Performance draws nothing; a whole volley
## leaves the game's RNG alone and cleans up after itself. An arrow flies on an arc above the rule line and is gone after
## its flight; a flamer's gout has no round.

const ShotScript = preload("res://scripts/vfx/shot_show.gd")
const PAIRS := [[Vector3(0, 0.03, 0), Vector3(0.3, 0.03, 0)], [Vector3(0, 0.03, 0.03), Vector3(0.3, 0.03, 0.03)],
	[Vector3(0, 0.03, 0.06), Vector3(0.3, 0.03, 0.06)]]
var _preset_before: int


func before_test() -> void:
	_preset_before = GraphicsSettings.current_preset
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.MEDIUM


func after_test() -> void:
	GraphicsSettings.current_preset = _preset_before


func _show() -> Node3D:
	var show = auto_free(ShotScript.new())
	show.force_for_tests = true
	add_child(show)
	show.enabled = true
	return show


func test_the_volley_plan_is_chaotic_and_the_same_on_every_peer() -> void:
	var plan: Array = ShotScript.plan(12, 4242)
	assert_array(plan).is_equal(ShotScript.plan(12, 4242))
	var delays: Array = plan.map(func(s): return float(s["delay"]))
	assert_bool(delays.all(func(d): return d >= 0.0 and d <= ShotScript.CHAOS_S)).is_true()
	var sorted := delays.duplicate()
	sorted.sort()
	assert_array(delays).override_failure_message("not in a row: the order is shuffled").is_not_equal(sorted)
	assert_bool(plan.all(func(s): return (s["jitter"] as Vector3).length() <= ShotScript.JITTER_M * 1.6)).is_true()


func test_performance_draws_no_volley() -> void:
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.PERFORMANCE
	var show := _show()
	show.volley(PAIRS, VolleyCue.Family.BALLISTIC, 5)
	await get_tree().create_timer(0.7).timeout
	assert_int(show.get_child_count()).is_equal(0)


func test_a_volley_fires_leaves_the_game_rng_alone_and_cleans_up(timeout := 8000) -> void:
	var show := _show()
	seed(41)
	var expected := randi()
	seed(41)
	for f in [VolleyCue.Family.BALLISTIC, VolleyCue.Family.BOW, VolleyCue.Family.FLAME, VolleyCue.Family.ENERGY]:
		show.volley(PAIRS, f, 100 + f)
	await get_tree().create_timer(0.7).timeout
	assert_int(randi()).is_equal(expected)
	assert_int(show.get_child_count()).override_failure_message("the muzzles fired").is_greater(4)
	await get_tree().create_timer(2.5).timeout
	assert_int(show.get_child_count()).override_failure_message("everything cleaned up").is_equal(0)


func _rounds(show: Node3D) -> Array:
	return show.get_children().filter(func(c: Node) -> bool: return not (c is FxBurst) and not (c is OmniLight3D))


func test_an_arrow_flies_on_an_arc_and_a_gout_has_no_round(timeout := 5000) -> void:
	var show := _show()
	var a := Vector3(0, 0.03, 0)
	var b := Vector3(0.3, 0.03, 0)
	show._fire(a, b, VolleyCue.Family.BOW, 7, 2)
	show._fire(a, b, VolleyCue.Family.FLAME, 8, 2)
	assert_int(_rounds(show).size()).override_failure_message("one arrow, no flame round").is_equal(1)
	await get_tree().create_timer(ShotScript.SHOTS[VolleyCue.Family.BOW][0] * 0.5).timeout
	var arrow := _rounds(show)[0] as Node3D
	assert_float(arrow.global_position.x).is_between(0.05, 0.25)
	assert_float(arrow.global_position.y).override_failure_message("above the rule line").is_greater(0.03 + 0.01)
	await get_tree().create_timer(ShotScript.SHOTS[VolleyCue.Family.BOW][0] * 0.6 + 0.1).timeout
	assert_int(_rounds(show).size()).override_failure_message("gone after its flight").is_equal(0)
