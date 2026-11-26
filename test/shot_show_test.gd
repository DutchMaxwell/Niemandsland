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
var _motion_before: bool


func before_test() -> void:
	_preset_before = GraphicsSettings.current_preset
	_motion_before = GraphicsSettings.reduce_motion
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.MEDIUM
	GraphicsSettings.reduce_motion = false


func after_test() -> void:
	GraphicsSettings.current_preset = _preset_before
	GraphicsSettings.reduce_motion = _motion_before


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


func _beam_meshes(show: Node3D) -> Array:
	return show.get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D)


## Waits by process frames, never by wall time, until the beam mesh is gone: gone is terminal, so this cannot race
## a slow frame the way a fixed sleep against the beam's short life does.
func _await_no_beam(show: Node3D, timeout := 2000) -> void:
	var deadline := Time.get_ticks_msec() + timeout
	while not _beam_meshes(show).is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func test_an_arrow_flies_on_an_arc_and_a_gout_has_no_round(timeout := 5000) -> void:
	var show := _show()
	var a := Vector3(0, 0.03, 0)
	var b := Vector3(0.3, 0.03, 0)
	show._fire(a, b, VolleyCue.Family.BOW, 7, 2)
	show._fire(a, b, VolleyCue.Family.FLAME, 8, 2)
	assert_int(_rounds(show).size()).override_failure_message("one arrow, no flame round").is_equal(1)
	await get_tree().create_timer(ShotScript.SHOTS[VolleyCue.Family.BOW][0] * 0.5).timeout
	var flying := _rounds(show)
	assert_int(flying.size()).override_failure_message("one arrow still in flight").is_equal(1)
	if flying.is_empty():
		return
	var arrow := flying[0] as Node3D
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


## Reads the beam the moment its tween builds it, so the length check cannot race a slow frame: a loaded runner
## can step a whole short beam life inside one frame, and a poll would never see it.
class BeamSpy extends "res://scripts/vfx/shot_show.gd":
	var beams_made := 0
	var beam_len := -1.0
	func _beam(a: Vector3, b: Vector3, shot: Array, p: int) -> void:
		super._beam(a, b, shot, p)
		var meshes := get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D)
		if meshes.is_empty():
			return
		beams_made += 1
		beam_len = (meshes[meshes.size() - 1] as Node3D).global_transform.basis.y.length()


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
	var spy := auto_free(BeamSpy.new()) as BeamSpy
	spy.force_for_tests = true
	add_child(spy)
	spy.enabled = true
	var a := Vector3(0, 0.03, 0)
	var b := Vector3(0.3, 0.03, 0)
	spy._fire(a, b, VolleyCue.Family.BEAM, 9, 2)
	var deadline := Time.get_ticks_msec() + 2000
	while spy.beams_made == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_int(spy.beams_made).override_failure_message("the beam stands from muzzle to target").is_equal(1)
	if spy.beams_made == 0:
		return
	assert_float(spy.beam_len).is_equal_approx(a.distance_to(b) - 0.012, 0.002)
	await _await_no_beam(spy)
	assert_int(_beam_meshes(spy).size()).override_failure_message("gone after its fade").is_equal(0)


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
	if rings.is_empty():
		return
	assert_float((rings[0] as Node3D).global_position.y).override_failure_message("on the ground").is_less(0.02)


func _planes(show: Node3D, code: String) -> Array:
	return show.get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D and (c as MeshInstance3D).mesh is PlaneMesh \
		and ((c as MeshInstance3D).material_override as ShaderMaterial).shader.code == code)


func test_a_blast_goes_in_three_beats_flash_fireball_and_smoke_that_lingers() -> void:
	var show := _show()
	show._impact(Vector3(0.3, 0.05, 0), Vector3.LEFT, VolleyCue.Family.ARTILLERY, 1, 2, 3, 0.04)
	var lives: Array = show.get_children().filter(func(c: Node) -> bool: return c is FxBurst) \
		.map(func(c: Node) -> float: return float(((c as FxBurst).material_override as ShaderMaterial).get_shader_parameter("life")))
	lives.sort()
	assert_float(lives[0]).override_failure_message("beat 1: a very short flash").is_less_equal(0.08)
	assert_bool(lives.any(func(l: float) -> bool: return l >= 0.25 and l <= 0.35)).override_failure_message("beat 2: a fireball").is_true()
	assert_float(lives[-1]).override_failure_message("beat 3: smoke that lingers").is_greater_equal(1.4)
	assert_int(_planes(show, ShotScript.BLAST_WAVE).size()).override_failure_message("the ring front").is_equal(1)


func test_a_shell_marks_its_landing_before_it_lands_and_not_on_low(timeout := 6000) -> void:
	var show := _show()
	var a := Vector3(0, 0.03, 0)
	var b := Vector3(0.3, 0.03, 0)
	var flight: float = ShotScript.SHOTS[VolleyCue.Family.ARTILLERY][0]
	show._fire(a, b, VolleyCue.Family.ARTILLERY, 3, 2, 1.0, false, 3, 0.03)
	show._fire(a, b + Vector3(0, 0, 0.2), VolleyCue.Family.ARTILLERY, 4, 1, 1.0, false, 3, 0.03)   # Low: no reticle
	assert_int(_planes(show, ShotScript.BLAST_RETICLE).size()).is_equal(0)
	await get_tree().create_timer(flight - ShotScript.RETICLE_S + 0.08).timeout
	assert_int(_planes(show, ShotScript.BLAST_RETICLE).size()).override_failure_message("one reticle, Medium only").is_equal(1)
	await get_tree().create_timer(ShotScript.RETICLE_S + 0.1).timeout
	assert_int(_planes(show, ShotScript.BLAST_RETICLE).size()).override_failure_message("gone when it lands").is_equal(0)
	assert_int(_planes(show, ShotScript.BLAST_WAVE).size()).is_greater_equal(1)


func test_a_flamer_fires_a_continuous_stream_along_the_line_not_a_puff(timeout := 5000) -> void:
	var show := _show()
	show._fire(Vector3(0, 0.03, 0), Vector3(0.127, 0.03, 0), VolleyCue.Family.FLAME, 8, 2)
	var bursts: Array = show.get_children().filter(func(c: Node) -> bool: return c is FxBurst)
	var quads := 0
	var stream: ShaderMaterial = null
	for c in bursts:
		var mm := (c as FxBurst).multimesh
		quads += mm.instance_count
		var m := (c as FxBurst).material_override as ShaderMaterial
		if float(m.get_shader_parameter("emit_gap")) > 0.0:
			stream = m
	assert_object(stream).override_failure_message("the gout is one streamed burst").is_not_null()
	assert_float(float(stream.get_shader_parameter("emit_gap")) * ShotScript.FLAME_QUADS) \
		.override_failure_message("tongues are born over the whole stream, not in one frame").is_equal_approx(ShotScript.FLAME_STREAM_S, 1e-4)
	assert_int(quads).override_failure_message("modest: at most 56 quads for the whole gout").is_less_equal(56)
	await get_tree().create_timer(0.5).timeout
	assert_bool(show.get_children().any(func(c: Node) -> bool: return c is FxBurst \
		and float(((c as FxBurst).material_override as ShaderMaterial).get_shader_parameter("emit_gap")) > 0.0)) \
		.override_failure_message("still burning 0.5 s in").is_true()
	assert_float(ShotScript._start_delay(VolleyCue.Family.FLAME, ShotScript.CHAOS_S)).is_between(0.1, 0.25)
	assert_float(ShotScript._start_delay(VolleyCue.Family.BALLISTIC, 0.4)).is_equal(0.4)


func test_a_flame_lands_as_fire_licking_the_base() -> void:
	var show := _show()
	show._impact(Vector3(0.1, 0.03, 0), Vector3.LEFT, VolleyCue.Family.FLAME, 5, 2, 0, 0.03)
	var lives: Array = show.get_children().filter(func(c: Node) -> bool: return c is FxBurst) \
		.map(func(c: Node) -> float: return float(((c as FxBurst).material_override as ShaderMaterial).get_shader_parameter("life")))
	assert_bool(lives.any(func(l: float) -> bool: return is_equal_approx(l, 0.6))).override_failure_message("a 0.6 s base fire").is_true()


func test_batched_hdr_ribbons_and_light_pool_cap_create_and_free(timeout := 5000) -> void:
	var show := _show()
	for i in 10:
		var a := Vector3(0.0, 0.03, i * 0.08)
		var b := Vector3(0.3, 0.03, i * 0.08)
		show._fire(a, b, VolleyCue.Family.BALLISTIC, 200 + i, 2)
	await get_tree().process_frame
	var batches := show.get_children().filter(func(c: Node) -> bool: return c is VfxRibbonBatch)
	var lights := show.get_children().filter(func(c: Node) -> bool: return c is OmniLight3D)
	assert_int(batches.size()).override_failure_message("all 10 tracers batched in 1 MultiMesh draw call").is_equal(1)
	assert_int((batches[0] as VfxRibbonBatch).active_count()).is_equal(10)
	assert_int(lights.size()).override_failure_message("pooled ring buffer capped at MAX_LIGHTS").is_equal(ShotScript.MAX_LIGHTS)
	assert_float((lights[0] as OmniLight3D).omni_range).is_between(ShotScript.LIGHT_RANGE_M * ShotScript.LIGHT_RANGE_END_K, ShotScript.LIGHT_RANGE_M)
	assert_float(ShotScript.LIGHT_RANGE_M).override_failure_message("muzzle light stays base-local").is_less_equal(0.09)
	assert_float(ShotScript.LIGHT_ATTENUATION).override_failure_message("metres: a decay above ~0.3 burns the core to white (d^-decay)").is_less_equal(0.3)
	assert_float(ShotScript.LIGHT_ENERGY).is_between(1.0, 3.0)
	assert_bool((lights[0] as OmniLight3D).shadow_enabled).is_false()
	await get_tree().create_timer(2.6).timeout
	assert_int(show.get_child_count()).override_failure_message("ribbon batch, light pool and bursts all freed").is_equal(0)


func test_volley_caps_pooled_lights_per_volley_even_across_a_pool_release(timeout := 6000) -> void:
	var show := _show()
	var wide_pairs: Array = []
	for i in 10:
		wide_pairs.append([Vector3(0.0, 0.03, i * 0.12), Vector3(0.3, 0.03, i * 0.12)])
	show.volley(wide_pairs, VolleyCue.Family.BALLISTIC, 77)
	await get_tree().create_timer(ShotScript.CHAOS_S * 0.4).timeout
	show.release_light_pool()   # what the idle timer does after 0.35 s without a light: the cap must outlive it
	await get_tree().create_timer(ShotScript.CHAOS_S + 0.5).timeout
	assert_int(show.light_starts).override_failure_message("a 10-pair volley lights at most 2 muzzle + 2 impact lights") \
		.is_less_equal(ShotScript.MAX_MUZZLE_LIGHTS_PER_VOLLEY + ShotScript.MAX_IMPACT_LIGHTS_PER_VOLLEY)
	assert_int(show.light_starts).is_greater(0)
	assert_bool(show._volley_lights.is_empty() and show._volley_open.is_empty()) \
		.override_failure_message("the volley's light budget is dropped with its last round").is_true()
	await get_tree().create_timer(2.5).timeout
	assert_int(show.get_child_count()).is_equal(0)


func test_the_flash_eases_out_without_a_cut() -> void:
	assert_float(ShotScript.light_curve(0.0)).is_equal(1.0)
	assert_float(ShotScript.light_curve(1.0)).is_equal(0.0)
	var prev := 1.0
	for i in range(1, 21):
		var e: float = ShotScript.light_curve(i / 20.0)
		assert_float(e).override_failure_message("never rises again").is_less_equal(prev)
		prev = e
	assert_float(ShotScript.light_curve(0.95)).override_failure_message("a soft tail, no step at the end").is_less(0.02)


func test_ensure_ribbon_batch_replaces_batch_queued_for_deletion() -> void:
	var show := _show()
	var first: VfxRibbonBatch = show._ensure_ribbon_batch()
	first.queue_free()
	assert_bool(first.is_queued_for_deletion()).is_true()
	var second: VfxRibbonBatch = show._ensure_ribbon_batch()
	assert_object(second).is_not_null()
	assert_object(second).override_failure_message("must not push into a batch queued for deletion").is_not_same(first)
	assert_bool(second.is_queued_for_deletion()).is_false()
	second.queue_free()


func test_low_preset_uses_zero_lights_and_reduce_motion_draws_static_threads(timeout := 5000) -> void:
	var low_show := _show()
	low_show._fire(Vector3(0, 0.03, 0), Vector3(0.3, 0.03, 0), VolleyCue.Family.BALLISTIC, 11, 1)
	assert_int(low_show.get_children().filter(func(c: Node) -> bool: return c is OmniLight3D).size()).is_equal(0)
	var motion_before: bool = GraphicsSettings.reduce_motion
	GraphicsSettings.reduce_motion = true
	var rm_show := _show()
	rm_show.volley(PAIRS, VolleyCue.Family.BALLISTIC, 12)
	var batches := rm_show.get_children().filter(func(c: Node) -> bool: return c is VfxRibbonBatch)
	assert_int(batches.size()).override_failure_message("static sight-line thread batch created immediately").is_equal(1)
	var batch := batches[0] as VfxRibbonBatch
	assert_int(batch.active_count()).is_equal(PAIRS.size())
	assert_bool(batch.is_slot_static(0)).override_failure_message("reduced motion takes static thread path").is_true()
	assert_int(rm_show.get_children().filter(func(c: Node) -> bool: return c is OmniLight3D).size()).is_equal(0)
	await get_tree().create_timer(ShotScript.STATIC_THREAD_LIFE_S + 0.25).timeout
	GraphicsSettings.reduce_motion = motion_before
	assert_int(rm_show.get_children().filter(func(c: Node) -> bool: return c is VfxRibbonBatch).size()) \
		.override_failure_message("static thread batch freed after 0.5 s fade").is_equal(0)
