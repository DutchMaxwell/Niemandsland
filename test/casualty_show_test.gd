extends GdUnitTestSuite
## CasualtyShow, step 1 (maintainer look verdicts: "more gore and blood", then gore GO "not too bloody but not
## harmless"): a wound on flesh leaves pools by the Gore setting (Off none, Normal one, Extra three); a big wound on a
## machine leaves one oil spot, on the undead no pool; nothing draws when the show is off; the game RNG stays alone.

const CasualtyScript = preload("res://scripts/vfx/casualty_show.gd")
var _gore_before: int
var _preset_before: int


func before_test() -> void:
	_gore_before = GraphicsSettings.gore_level
	_preset_before = GraphicsSettings.current_preset
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.MEDIUM


func after_test() -> void:
	GraphicsSettings.gore_level = _gore_before
	GraphicsSettings.current_preset = _preset_before


func _show(on := true) -> Node3D:
	var show = auto_free(CasualtyScript.new())
	show.force_for_tests = true
	add_child(show)
	show.enabled = on
	return show


func _pools(show: Node3D) -> int:
	var sp := show.get_node_or_null("Splatters")
	return 0 if sp == null else sp.get_child_count()


func test_gore_off_draws_no_blood_extra_draws_more() -> void:
	var counts: Array = []
	for gore in [0, 1, 2]:
		GraphicsSettings.gore_level = gore
		var show := _show()
		show.wound(Vector3(0, 0.03, 0), Vector3.ZERO, ModelStuff.Stuff.FLESH, 1, 7)
		counts.append(_pools(show))
	assert_array(counts).is_equal([0, 1, 3])


func test_machines_leak_oil_and_the_undead_leave_no_pool() -> void:
	GraphicsSettings.gore_level = 1
	var machine := _show()
	machine.wound(Vector3(0, 0.03, 0), Vector3.ZERO, ModelStuff.Stuff.MACHINE, 2, 9, true)
	assert_int(_pools(machine)).is_equal(1)
	var oil: ShaderMaterial = (machine.get_node("Splatters").get_child(0) as MeshInstance3D).material_override
	assert_float(float(oil.get_shader_parameter("splash"))).override_failure_message("oil is a smooth puddle").is_equal(0.0)
	var undead := _show()
	undead.wound(Vector3(0, 0.03, 0), Vector3.ZERO, ModelStuff.Stuff.UNDEAD, 2, 9, true)
	assert_int(_pools(undead)).is_equal(0)
	assert_int(undead.get_child_count()).override_failure_message("bone dust and chips").is_greater(0)


func test_off_draws_nothing_and_the_game_rng_stays_alone() -> void:
	var off := _show(false)
	off.wound(Vector3(0, 0.03, 0), Vector3.ZERO, ModelStuff.Stuff.FLESH, 2, 3, true)
	off.ricochets([Vector3.ZERO, Vector3.ONE], 4)
	assert_int(off.get_child_count()).is_equal(0)
	seed(23)
	var expected := randi()
	seed(23)
	var on := _show()
	on.wound(Vector3(0, 0.03, 0), Vector3.ZERO, ModelStuff.Stuff.FLESH, 2, 3, true)
	on.ricochets([Vector3.ZERO, Vector3.ONE], 4)
	assert_int(randi()).is_equal(expected)
	assert_int(on.get_child_count()).is_greater(2)
