extends GdUnitTestSuite
## VFX #2 volley cue (special-effects plan): the tracer is drawn on exactly the eye-to-eye pair it is given
## (the LOS rule's own segment, within 1 mm), the tint family comes from the weapon NAME only with a neutral
## fallback, the still form drops the travelling slug, and nothing spawns when off. It never touches the RNG.

const VolleyCueScript = preload("res://scripts/vfx/volley_cue.gd")
const A := Vector3(0.1, 0.03, -0.15)
const B := Vector3(-0.05, 0.05, 0.16)
var _motion_before: bool


func before_test() -> void:
	_motion_before = GraphicsSettings.reduce_motion
	GraphicsSettings.reduce_motion = false


func after_test() -> void:
	GraphicsSettings.reduce_motion = _motion_before


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
	var F: Dictionary = VolleyCueScript.Family
	var table := {"Assault Rifle": "BALLISTIC", "Heavy Machinegun": "AUTO", "Autocannon": "AUTO", "Gatling Gun": "AUTO",
		"Scorpion Pistol": "BALLISTIC", "Plasma Rifle": "ENERGY", "Laser Cannon": "BEAM", "Heavy Flamer": "FLAME",
		"Flamethrower": "FLAME", "Crossbow": "BOW", "Longbow": "BOW", "Javelins": "THROWN", "Sling": "THROWN",
		"Frag Grenades": "THROWN", "Mortar": "ARTILLERY", "Rocket Launcher": "ARTILLERY", "Missile Pod": "ARTILLERY",
		"Spore Mine": "NEUTRAL", "Hand Weapon": "NEUTRAL", "": "NEUTRAL"}
	for weapon: String in table:
		assert_int(VolleyCueScript.family_of(weapon)).override_failure_message(weapon).is_equal(F.get(table[weapon], -1))


## Where the name says nothing, the rules do: Indirect is a lobbed shell, Blast an explosive; a ballistic weapon with
## four or more attacks per copy is a machine gun.
func test_the_rules_decide_what_the_name_leaves_open() -> void:
	var F: Dictionary = VolleyCueScript.Family
	var table := [[{"name": "Spore Mine", "indirect": true}, "ARTILLERY"], [{"name": "Big Shooty", "blast": 3}, "ARTILLERY"],
		[{"name": "Heavy Rifle", "attacks": 8, "count": 2}, "AUTO"], [{"name": "Heavy Rifle", "attacks": 6, "count": 2}, "BALLISTIC"],
		[{"name": "Plasma Cannon", "blast": 3}, "ENERGY"], [{"name": "Claws", "attacks": 4, "count": 1}, "NEUTRAL"]]
	for row: Array in table:
		assert_int(VolleyCueScript.family_for(row[0])).override_failure_message(str(row[0])).is_equal(F.get(row[1], -1))


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


func test_reduce_motion_draws_static_lines_only_and_frees(timeout := 5000) -> void:
	var preset_before: int = GraphicsSettings.current_preset
	var motion_before: bool = GraphicsSettings.reduce_motion
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.HIGH
	GraphicsSettings.reduce_motion = true
	var c = _cue()
	c.fire([[A, B], [B, A]], VolleyCueScript.Family.BALLISTIC)
	assert_int(c.get_child_count()).override_failure_message("static lines only, no moving slugs").is_equal(2)
	await get_tree().create_timer(VolleyCueScript.STILL_LINGER_S + 0.2).timeout
	GraphicsSettings.reduce_motion = motion_before
	GraphicsSettings.current_preset = preset_before
	assert_int(c.get_child_count()).override_failure_message("static lines freed with no orphans").is_equal(0)
