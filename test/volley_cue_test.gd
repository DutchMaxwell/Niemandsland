extends GdUnitTestSuite
## VFX #2 volley cue (special-effects plan): the tracer is drawn on exactly the eye-to-eye pair it is given
## (the LOS rule's own segment, within 1 mm), the tint family comes from the weapon NAME only with a neutral
## fallback, the still form drops the travelling slug, and nothing spawns when off. It never touches the RNG.

const VolleyCueScript = preload("res://scripts/vfx/volley_cue.gd")
const A := Vector3(0.1, 0.03, -0.15)
const B := Vector3(-0.05, 0.05, 0.16)


func _cue():
	var c = auto_free(VolleyCueScript.new())
	c.force_for_tests = true
	add_child(c)
	c.enabled = true   # the player setting defaults to off
	return c


func _ends(seg: MeshInstance3D) -> Array:
	var half := seg.global_transform.basis.y * (seg.mesh as CylinderMesh).height * 0.5   # length rides the scale
	return [seg.global_position - half, seg.global_position + half]


func test_the_line_runs_eye_to_eye_within_a_millimetre() -> void:
	var c = _cue()
	assert_int(c.fire([[A, B]], VolleyCueScript.Family.BALLISTIC)).is_equal(1)
	var line := c.get_child(0) as MeshInstance3D
	var ends := _ends(line)
	assert_float((ends[0] as Vector3).distance_to(A)).is_less(0.001)
	assert_float((ends[1] as Vector3).distance_to(B)).is_less(0.001)
	assert_object((line.material_override as StandardMaterial3D).albedo_color) \
		.is_equal(VolleyCueScript.TINTS[VolleyCueScript.Family.BALLISTIC])


func test_full_form_adds_a_slug_still_form_does_not() -> void:
	var c = _cue()
	var before: int = GraphicsSettings.current_preset
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.MEDIUM
	c.fire([[A, B], [B, A]], VolleyCueScript.Family.NEUTRAL)
	assert_int(c.get_child_count()).is_equal(4)
	var s = _cue()
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.LOW
	s.fire([[A, B], [B, A]], VolleyCueScript.Family.NEUTRAL)
	GraphicsSettings.current_preset = before
	assert_int(s.get_child_count()).is_equal(2)


func test_the_family_comes_from_the_name_with_a_neutral_fallback() -> void:
	var F = VolleyCueScript.Family
	var table := {"Assault Rifle": F.BALLISTIC, "Heavy Machinegun": F.BALLISTIC, "Autocannon": F.BALLISTIC,
		"Scorpion Pistol": F.BALLISTIC, "Plasma Rifle": F.ENERGY, "Laser Cannon": F.ENERGY, "Heavy Flamer": F.FLAME,
		"Flamethrower": F.FLAME, "Crossbow": F.BOW, "Longbow": F.BOW, "Javelins": F.BOW, "Spore Mine": F.NEUTRAL,
		"Hand Weapon": F.NEUTRAL, "": F.NEUTRAL}
	for weapon: String in table:
		assert_int(VolleyCueScript.family_of(weapon)).override_failure_message(weapon).is_equal(table[weapon])


func test_off_spawns_nothing_and_the_pool_is_capped() -> void:
	var c = _cue()
	c.enabled = false
	assert_int(c.fire([[A, B]], VolleyCueScript.Family.BOW)).is_equal(0)
	assert_int(c.get_child_count()).is_equal(0)
	c.enabled = true
	var pairs: Array = []
	for i in VolleyCueScript.MAX_LIVE * 2:
		pairs.append([A, B + Vector3(0.001 * i, 0, 0)])
	c.fire(pairs, VolleyCueScript.Family.BOW)
	assert_int(c.get_child_count()).is_less_equal(VolleyCueScript.MAX_LIVE)


func test_tracers_leave_the_game_rng_alone() -> void:
	var c = _cue()
	seed(777)
	var expected := randi()
	seed(777)
	c.fire([[A, B], [B, A]], VolleyCueScript.Family.ENERGY)
	assert_int(randi()).is_equal(expected)
