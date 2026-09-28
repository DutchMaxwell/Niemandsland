extends GdUnitTestSuite
## Teleport is a before-attack placement; HOLD belongs only to Ethereal.

const Boot := preload("res://test/e2e/e2e_boot.gd")

class FixedTeleportController extends SoloController:
	var chosen_rule := "Teleport"
	func teleport_decision(_unit: GameUnit, _rush: bool) -> Dictionary:
		return {"rule": chosen_rule, "used": true, "to": Vector2(0.2, 0.0)}

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array

func before_test() -> void:
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()

func after_test() -> void:
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null

func test_teleport_hold_is_skipped_but_ethereal_hold_repositions() -> void:
	var unit := Boot.make_unit(_main, 2, "Bearer", [Vector3(0.2, 0, 0)])
	unit.unit_properties["game_system"] = "gf"
	unit.unit_properties["faction_folder"] = "eternal_dynasty"
	unit.unit_properties["special_rules"] = ["Teleport"]
	_main.opr_army_manager.game_units[unit.unit_id] = unit
	var controller: FixedTeleportController = auto_free(FixedTeleportController.new())
	_main.add_child(controller)
	controller.setup(_main.opr_army_manager, _main.network_manager, null)
	_main.solo_controller = controller
	await _main._solo_apply_teleport(unit, {"action": AiDecision.Action.HOLD})
	assert_bool(unit.unit_properties.has("teleport_used_this_activation")).is_false()
	unit.unit_properties["special_rules"] = ["Ethereal"]
	controller.chosen_rule = "Ethereal"
	await _main._solo_apply_teleport(unit, {"action": AiDecision.Action.HOLD})
	assert_bool(unit.unit_properties.has("teleport_used_this_activation")).is_true()
