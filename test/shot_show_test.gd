extends GdUnitTestSuite
## ShotShow (maintainer look verdicts: "not in a row, more like chaotic fire", then shots GO): the volley's chaos is a
## pure function of the cue's seed (every peer sees the same) and not a row; Performance draws nothing; a whole volley
## leaves the game's RNG alone and cleans up after itself. An arrow flies on an arc above the rule line and is gone after
## its flight; a flamer's gout has no round. Weapon types (maintainer 05.10.: "differentiate by WEAPON TYPE", then GO): no
## two families look alike; a machine gun fires a burst of rounds per model; a beam stands from muzzle to target at
## once and fades. Sound-ready: every round tells the sound hook when it leaves and lands, a Blast weapon also when it
## blasts (and draws a ring on the ground), and the hook still hears every round with Reduce Motion (no picture).

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


class FireSpy extends "res://scripts/vfx/shot_show.gd":
	var fired := 0
	func _fire(a: Vector3, b: Vector3, family: int, s: int, p: int, muzzle_k := 1.0, echo := false, blast := 0,
			ground_drop := 0.0) -> void:
		fired += 1
		super._fire(a, b, family, s, p, muzzle_k, echo, blast, ground_drop)


func test_no_two_families_look_the_same() -> void:
	var rows: Array = ShotScript.SHOTS.values()
	assert_int(rows.size()).is_equal(VolleyCue.Family.size())
	for i in rows.size():
		for j in range(i + 1, rows.size()):
			assert_array(rows[i]).override_failure_message("families %d and %d look alike" % [i, j]).is_not_equal(rows[j])


func test_a_machine_gun_fires_a_burst_per_model(timeout := 5000) -> void:
	var spy := auto_free(FireSpy.new()) as FireSpy
	spy.force_for_tests = true
	add_child(spy)
	spy.enabled = true
	spy.volley(PAIRS, VolleyCue.Family.AUTO, 3)
	spy.volley(PAIRS, VolleyCue.Family.BALLISTIC, 4)
	await get_tree().create_timer(ShotScript.CHAOS_S + ShotScript.AUTO_ROUNDS * ShotScript.ROUND_GAP_S + 0.2).timeout
	assert_int(ShotScript.AUTO_ROUNDS).override_failure_message("a burst, not a single shot").is_greater_equal(3)
	assert_int(spy.fired).is_equal(PAIRS.size() * ShotScript.AUTO_ROUNDS + PAIRS.size())


func test_a_beam_stands_from_muzzle_to_target_and_fades(timeout := 5000) -> void:
	var show := _show()
	var a := Vector3(0, 0.03, 0)
	var b := Vector3(0.3, 0.03, 0)
	show._fire(a, b, VolleyCue.Family.BEAM, 9, 2)
	await get_tree().create_timer(0.08).timeout
	var beams := show.get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D)
	assert_int(beams.size()).is_equal(1)
	assert_float((beams[0] as Node3D).global_transform.basis.y.length()).is_equal_approx(a.distance_to(b) - 0.012, 0.002)
	await get_tree().create_timer(0.4).timeout
	assert_int(show.get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D).size()).is_equal(0)


func test_every_round_tells_the_sound_hook_and_blast_adds_a_ring(timeout := 10000) -> void:
	var show := _show()
	var heard := {}
	show.sound_cue.connect(func(f: int, moment: String, _at: Vector3) -> void:
		heard["%d:%s" % [f, moment]] = int(heard.get("%d:%s" % [f, moment], 0)) + 1)
	var F: Dictionary = VolleyCue.Family
	for f: int in F.values():
		show.volley(PAIRS, f, 100 + f, 3 if f == F.ARTILLERY else 0, 0.03)
	await get_tree().create_timer(2.0).timeout
	for f: int in F.values():
		var rounds := PAIRS.size() * (ShotScript.AUTO_ROUNDS if f == F.AUTO else 1)
		assert_int(int(heard.get("%d:launch" % f, 0))).override_failure_message("launch " + str(F.keys()[f])).is_equal(rounds)
		assert_int(int(heard.get("%d:impact" % f, 0))).override_failure_message("impact " + str(F.keys()[f])).is_equal(rounds)
	assert_int(int(heard.get("%d:blast" % F.ARTILLERY, 0))).is_equal(PAIRS.size())
	assert_int(int(heard.get("%d:blast" % F.BALLISTIC, 0))).is_equal(0)


func test_reduce_motion_draws_nothing_but_the_hook_still_hears(timeout := 5000) -> void:
	var motion: bool = GraphicsSettings.reduce_motion
	GraphicsSettings.reduce_motion = true
	var show := _show()
	var heard := [0]
	show.sound_cue.connect(func(_f: int, _m: String, _at: Vector3) -> void: heard[0] += 1)
	show.volley(PAIRS, VolleyCue.Family.BALLISTIC, 5)
	await get_tree().create_timer(1.2).timeout
	GraphicsSettings.reduce_motion = motion
	assert_int(heard[0]).is_equal(PAIRS.size() * 2)
	assert_int(show.get_child_count()).override_failure_message("no picture with Reduce Motion").is_equal(0)


func test_a_blast_draws_a_ring_on_the_ground() -> void:
	var show := _show()
	show._impact(Vector3(0.3, 0.05, 0), Vector3.LEFT, VolleyCue.Family.ARTILLERY, 1, 2, 3, 0.04)
	show._impact(Vector3(0.3, 0.05, 0.1), Vector3.LEFT, VolleyCue.Family.BALLISTIC, 2, 2, 0, 0.04)
	var rings := show.get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D and (c as MeshInstance3D).mesh is PlaneMesh)
	assert_int(rings.size()).override_failure_message("one ring, for the Blast impact only").is_equal(1)
	assert_float((rings[0] as Node3D).global_position.y).override_failure_message("on the ground").is_less(0.02)
