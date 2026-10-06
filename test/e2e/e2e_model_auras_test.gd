extends GdUnitTestSuite
## Hero auras live in the real game (maintainer look verdict 05.10.: Frog-Mage aura GO): main.tscn carries one
## ModelAuras node, off until the Combat Effects switch is on, and once on it gives a Frog-Mage miniature on the real
## table its aura — no cue needed, the aura belongs to the model.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_the_game_carries_the_auras_and_they_follow_the_switch() -> void:
	var auras: Variant = _main.get("model_auras")
	assert_bool(auras is ModelAuras).override_failure_message("main.tscn has no ModelAuras").is_true()
	if not (auras is ModelAuras):
		return
	assert_bool((auras as ModelAuras).is_inside_tree()).is_true()
	assert_bool((auras as ModelAuras).enabled).override_failure_message("follows the Combat Effects switch") 		.is_equal(GraphicsSettings.show_combat_effects)
	var unit := GameUnit.new()
	unit.unit_properties = {"name": "Frog Mage", "faction_folder": "saurian_starhost"}
	var mi := ModelInstance.new()
	mi.unit = unit
	var mini := Node3D.new()
	_main.add_child(mini)
	mini.add_to_group("miniature")
	mini.set_meta("model_instance", mi)
	(auras as ModelAuras).force_for_tests = true
	(auras as ModelAuras).enabled = true
	(auras as ModelAuras).refresh()
	assert_object(mini.get_node_or_null("ModelAura")).override_failure_message("the frog got no aura").is_not_null()
	mini.queue_free()
