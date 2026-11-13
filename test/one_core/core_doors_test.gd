extends GdUnitTestSuite
## One-core P3 step 62 (O14 (1b)): the transport doors - Disembark, Unload, Embark, Stay aboard - spend an activation, so
## with NML_ONE_CORE_ACTIVATION on a lifecycle unit whose activation is not open is refused there, with the drag gate's
## sentences: "Activate <Unit> first." (O15 (1)), or the O5 sentence while another unit's activation is open.
## Real: the main scene, its radial controller's dispatch, the army manager's transport state, the NmlCore extension.
## Constructed: bare units (E2EBoot.make_unit) with an OPRUnit profile; the truck/cargo/spare fixture of
## e2e_embark_activation_test.

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
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	CoreActivation._env = 1   # the flag ON; the flag-off case resets it itself


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(uname: String, at: Vector3, rules: Array = []) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, uname, [at])
	u.unit_properties["special_rules"] = rules
	var src := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	src.weapons.append(w)
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A Transport(6) truck at the origin, its cargo (aboard or beside it) and an idle spare, so the round stays open.
func _truck_and_cargo(aboard: bool) -> Array:
	var truck := _unit("Truck", Vector3.ZERO, ["Transport(6)"])
	var cargo := _unit("Riders", Vector3(0.04, 0, 0))
	_unit("Spare", Vector3(1.0, 0, 0))
	if aboard:
		_main.opr_army_manager.set_unit_embarked(cargo, truck, true)
	return [truck, cargo]


func _lines(text: String) -> int:
	return _main.battle_log.entries().filter(func(e: Dictionary) -> bool: return str(e["text"]) == text).size()


func _act(action: String, context: Dictionary) -> void:
	await _main.radial_menu_controller._on_action_selected(action, context)


func test_disembark_needs_the_cargos_own_start() -> void:
	var tc := _truck_and_cargo(true)
	await _act("disembark", {"disembark_unit": tc[1]})
	assert_object(_main.opr_army_manager.transport_of(tc[1])).override_failure_message("disembarked").is_equal(tc[0])
	assert_int(_lines("Activate Riders first.")).is_equal(1)
	assert_bool(CoreActivation.open_session(_main, tc[1])).override_failure_message("no session").is_true()
	await _act("disembark", {"disembark_unit": tc[1]})
	assert_object(_main.opr_army_manager.transport_of(tc[1])).override_failure_message("still aboard").is_null()


## Unload is the CARGO's activation: the transport's own open activation does not let the cargo out.
func test_unload_asks_the_cargo_not_the_transport() -> void:
	var tc := _truck_and_cargo(true)
	assert_bool(CoreActivation.open_session(_main, tc[0])).override_failure_message("no session").is_true()
	await _act("unload_cargo_0", {"cargo_units": [tc[1]], "game_unit": tc[0]})
	assert_object(_main.opr_army_manager.transport_of(tc[1])).override_failure_message("unloaded").is_equal(tc[0])
	assert_int(_lines("Finish Truck's activation first.")).is_equal(1)


func test_embark_while_another_activation_is_open_names_it() -> void:
	var tc := _truck_and_cargo(false)
	CoreActivation.open_session(_main, _unit("Alpha", Vector3(-1.0, 0, 0)))
	await _act("embark_0", {"game_unit": tc[1], "embark_targets": [tc[0]]})
	assert_object(_main.opr_army_manager.transport_of(tc[1])).override_failure_message("embarked").is_null()
	assert_int(_lines("Finish Alpha's activation first.")).is_equal(1)


func test_stay_aboard_needs_the_start() -> void:
	var tc := _truck_and_cargo(true)
	await _act("stay_embarked", {"disembark_unit": tc[1]})
	assert_int(_lines("Activate Riders first.")).is_equal(1)
	assert_bool((tc[1] as GameUnit).is_activated).override_failure_message("the stay was spent").is_false()
	assert_int(_lines("Riders stays aboard")).is_equal(0)


func test_with_the_flag_off_disembark_needs_no_start() -> void:
	CoreActivation._env = 0
	var tc := _truck_and_cargo(true)
	await _act("disembark", {"disembark_unit": tc[1]})
	assert_object(_main.opr_army_manager.transport_of(tc[1])).is_null()
