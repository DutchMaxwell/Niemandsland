extends GdUnitTestSuite
## The spells live in the game (maintainer look verdicts 05.10.: all spells GO): a cast's seal cue carries its element
## from the spell's name and its end cue the resolved targets, so the spell show charges in the element's tint and
## releases at the targets on every peer; a hero's aura at the caster runs wild while it casts and calms after; a
## malformed peer payload draws nothing and raises nothing (the spells lane's gate over the real cue path).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _preset_before: int


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_preset_before = GraphicsSettings.current_preset
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.MEDIUM   # the harness may run lower; the show needs Medium
	for fx: String in ["spell_seal", "spell_show", "model_auras"]:
		var node: Variant = _main.get(fx)
		if node != null:
			node.force_for_tests = true
			node.enabled = true


func after_test() -> void:
	GraphicsSettings.current_preset = _preset_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_a_fire_cast_charges_in_its_tint_and_releases_at_its_target(timeout := 30000) -> void:
	assert_bool(_main.get("spell_show") is SpellShow).override_failure_message("main.tscn has no SpellShow").is_true()
	var caster := E2EBoot.make_unit(_main, 1, "Mage", [Vector3(0, 0, 0)])
	var target := E2EBoot.make_unit(_main, 2, "Targets", [Vector3(0, 0, 0.3)])
	var sid: int = _main._vfx_seal_begin(caster, {"range_in": 12}, {"kind": "damage"}, "Fire Ball")
	assert_int(sid).is_greater(0)
	var charge := _main.spell_show.find_child("SpellCharge", true, false) as Node3D
	assert_object(charge).override_failure_message("the cast gathers at the caster").is_not_null()
	var ribbon := charge.get_child(0) as MeshInstance3D
	assert_object((ribbon.material_override as ShaderMaterial).get_shader_parameter("tint")) \
		.override_failure_message("fire's tint, read from the name").is_equal(SpellLook.TINTS[SpellLook.Element.FIRE])
	_main._vfx_emit({"k": "seal_end", "sid": sid, "o": int(SpellSeal.Outcome.SUCCESS),
		"tg": [_main._vfx_unit_eye(target)], "dmg": true})
	assert_object(_main.spell_show.find_child("SpellSuccess", true, false)).is_not_null()


func test_a_hero_aura_at_the_caster_runs_wild_while_it_casts(timeout := 30000) -> void:
	var caster := E2EBoot.make_unit(_main, 1, "Frog Mage", [Vector3(0.1, 0, 0.1)])
	caster.unit_properties["faction_folder"] = "saurian_starhost"
	var mi := caster.models[0] as ModelInstance
	mi.node.add_to_group("miniature")
	mi.node.set_meta("model_instance", mi)
	_main.model_auras.refresh()
	var aura = mi.node.get_node_or_null("ModelAura")
	assert_object(aura).override_failure_message("the Frog-Mage carries its aura").is_not_null()
	if aura == null:
		return
	var sid: int = _main._vfx_seal_begin(caster, {"range_in": 12}, {"kind": "damage"}, "Lightning Fog")
	var now := Time.get_ticks_msec() / 1000.0
	assert_float(float(aura.boost_until)).override_failure_message("wild while it casts").is_greater(now + 30.0)
	_main._vfx_emit({"k": "seal_end", "sid": sid, "o": int(SpellSeal.Outcome.FAIL), "tg": [], "dmg": true})
	assert_float(float(aura.boost_until)).override_failure_message("calm again after").is_less(now + 5.0)


func test_spell_payload_validation_uses_the_real_cue_path(timeout := 60000) -> void:
	var bad: Array = [{"r": {}}, {"r": NAN}, {"at": Vector3.INF}, {"el": []}, {"kind": []}]
	var id := 1
	for override: Dictionary in bad:
		var cue := {"k": "seal", "id": id, "s": 91, "at": Vector3.ZERO, "r": 0.3, "el": 0, "kind": "damage"}
		cue.merge(override, true)
		_main._vfx_draw(cue, 2)
		id += 1
	assert_int(_main.spell_show.get_child_count()).is_zero()
	assert_int(_main.spell_seal.get_child_count()).is_zero()
	var begin := {"k": "seal", "id": 100, "s": 91, "at": Vector3.ZERO, "r": 0.3, "el": 3, "kind": "damage"}
	_main._vfx_draw(begin, 2)
	var count: int = _main.spell_show.get_child_count()
	assert_int(count).is_greater(0)
	_main._vfx_draw(begin, 2)
	assert_int(_main.spell_show.get_child_count()).is_equal(count)
	for extra: Dictionary in [{"o": []}, {"tg": "there"}, {"dmg": []}]:
		var cue := {"k": "seal_end", "id": id, "sid": 100, "s": 91, "o": 0, "tg": [], "dmg": true}
		cue.merge(extra, true)
		_main._vfx_draw(cue, 2)
		id += 1
	assert_int(_main.spell_show._columns.size()).is_equal(1)
	_main._vfx_draw({"k": "seal_end", "id": 101, "sid": 100, "s": 91, "o": 0,
		"tg": [Vector3.INF, "bad", Vector3(0.2, 0.03, 0)], "dmg": true}, 2)
	await get_tree().create_timer(2.2).timeout
	assert_int(_main.spell_show.get_child_count()).is_zero()
