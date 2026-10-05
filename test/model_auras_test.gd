extends GdUnitTestSuite
## Hero auras (maintainer look verdict 05.10.: Frog-Mage aura GO): the data table, keyed exactly like the model
## library, says which miniature carries an aura ("Frog Mage" and "Frog-Mage" are one key, other units carry none); a
## miniature gets its aura once, with a soft glow at each anchor; the glow hides when the model is a casualty and on
## Performance, and stays on Low (it is the whole aura there). The arcs crackle at the data rate, three times as busy
## while the model casts and calm again after, from the aura's own RNG; Low draws no arcs.

const AuraScript = preload("res://scripts/vfx/model_auras.gd")
var _preset_before: int


func before_test() -> void:
	_preset_before = GraphicsSettings.current_preset


func after_test() -> void:
	GraphicsSettings.current_preset = _preset_before


func _frog(unit_name := "Frog Mage") -> ModelInstance:
	var unit := GameUnit.new()
	unit.unit_properties = {"name": unit_name, "faction_folder": "saurian_starhost"}
	var mi := ModelInstance.new()
	mi.unit = unit
	return mi


func _auras() -> Node3D:
	var auras = auto_free(AuraScript.new())
	auras.force_for_tests = true
	add_child(auras)
	auras.enabled = true
	return auras


func _miniature(mi: ModelInstance) -> Node3D:
	var mini := auto_free(Node3D.new()) as Node3D
	add_child(mini)
	mini.add_to_group("miniature")
	mini.set_meta("model_instance", mi)
	return mini


func test_the_frog_mage_carries_a_lightning_aura() -> void:
	assert_str(str(AuraScript.spec_for(_frog()).get("kind", ""))).is_equal("lightning")
	assert_str(str(AuraScript.spec_for(_frog("Frog-Mage")).get("kind", ""))).is_equal("lightning")
	assert_bool(AuraScript.spec_for(_frog("Warriors")).is_empty()).is_true()


func test_a_miniature_gets_its_aura_once_with_a_glow_per_anchor() -> void:
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.MEDIUM
	var auras := _auras()
	var frog := _miniature(_frog())
	var warriors := _miniature(_frog("Warriors"))
	auras.refresh()
	auras.refresh()
	assert_int(frog.get_child_count()).override_failure_message("one aura per miniature").is_equal(1)   # a 2nd would be renamed
	assert_object(warriors.get_node_or_null("ModelAura")).is_null()
	var anchors: int = (AuraScript.spec_for(_frog()).get("anchors", []) as Array).size()
	assert_int(frog.get_node("ModelAura").get_child_count()).is_equal(anchors)


func test_the_glow_hides_with_its_model_and_on_performance() -> void:
	var auras := _auras()
	var mi := _frog()
	var frog := _miniature(mi)
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.LOW
	auras.refresh()
	var aura = frog.get_node("ModelAura")
	aura._process(0.1)
	assert_bool(aura.visible).override_failure_message("Low keeps the glow").is_true()
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.PERFORMANCE
	aura._process(0.1)
	assert_bool(aura.visible).override_failure_message("Performance draws no aura").is_false()
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.MEDIUM
	mi.is_alive = false
	aura._process(0.1)
	assert_bool(aura.visible).override_failure_message("a casualty keeps no aura").is_false()


func test_the_arcs_crackle_busier_while_casting_and_leave_the_game_rng_alone() -> void:
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.MEDIUM
	var auras := _auras()
	var frog := _miniature(_frog())
	auras.refresh()
	var aura = frog.get_node("ModelAura")
	seed(7)
	var expected := randi()
	seed(7)
	aura._process(1.0)
	var calm: int = aura.arcs
	auras.boost_near("k", frog.global_position, 0.15)
	aura._process(1.0)
	var wild: int = aura.arcs - calm
	auras.settle("k", 0.0)
	aura._process(1.0)
	assert_int(randi()).override_failure_message("an aura drew from the game RNG").is_equal(expected)
	assert_int(calm).is_equal(10)
	assert_int(wild).override_failure_message("a cast makes it three times as busy").is_equal(30)
	assert_int(aura.arcs - calm - wild).override_failure_message("after the cast it calms down").is_equal(10)
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.LOW
	var before: int = aura.arcs
	aura._process(1.0)
	assert_int(aura.arcs).override_failure_message("Low is the glow only").is_equal(before)
