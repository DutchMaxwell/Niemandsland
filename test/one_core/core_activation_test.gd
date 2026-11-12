extends GdUnitTestSuite
## One-core P3 step 19: the table skeleton `CoreActivation` and its three predicates (lifecycle, core, move-path).
## Real: the main scene, its network manager class (transport swapped out, the e2e_mp_auto_verbs_test pattern),
## the NmlCore extension. Constructed: bare units from E2EBoot.make_unit with an OPRUnit profile of one weapon.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _real_net: Node
var _net: Node


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_real_net = _main.network_manager
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main.solo_ai_slots = {}
	CoreActivation._env = 1   # the flag ON for every case; the default case resets it itself


func after_test() -> void:
	CoreActivation._env = -1
	_end_session()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _end_session() -> void:
	if _main != null:
		_main.network_manager = _real_net
	if _net != null:
		_net.free()
		_net = null


## A REAL NetworkManager with only the transport swapped out (pattern: e2e_mp_auto_verbs_test).
func _fake_session(my_slot: int) -> void:
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/network_manager.gd\"\n" \
		+ "func is_multiplayer_active() -> bool:\n\treturn true\n" \
		+ "func get_my_player_slot() -> int:\n\treturn %d\n" % my_slot
	assert_int(src.reload()).is_equal(OK)
	_net = src.new()
	_net.is_host = true
	_net.army_manager = _main.opr_army_manager
	_main.network_manager = _net


func _unit(pid: int, uname: String, unit_rules: Array = [], weapon_rules: Array = []) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, uname, [Vector3(0.3 * pid, 0.0, 0.0)])
	u.unit_properties["special_rules"] = unit_rules
	var src := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.special_rules.assign(weapon_rules)
	src.weapons.append(w)
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func test_enabled_is_false_by_default() -> void:
	CoreActivation._env = -1
	assert_bool(CoreActivation.enabled()).is_false()


func test_a_bare_unit_with_one_plain_weapon_is_plain() -> void:
	assert_bool(CoreActivation.is_plain(_unit(1, "Rifles"))).is_true()


func test_a_special_rule_makes_a_unit_not_plain() -> void:
	assert_bool(CoreActivation.is_plain(_unit(1, "Rifles", ["Furious"]))).is_false()


func test_a_weapon_rule_makes_a_unit_not_plain() -> void:
	assert_bool(CoreActivation.is_plain(_unit(1, "Rifles", [], ["Blast(3)"]))).is_false()


func test_an_attached_hero_makes_a_unit_not_plain() -> void:
	var host := _unit(1, "Rifles")
	var hero := _unit(1, "Captain")
	hero.unit_properties["attached_to"] = host
	assert_bool(CoreActivation.is_plain(hero)).override_failure_message("the joined hero").is_false()
	host.unit_properties["attached_heroes"] = [hero]
	assert_bool(CoreActivation.is_plain(host)).override_failure_message("the host with a hero").is_false()


func test_applies_is_false_with_the_flag_off() -> void:
	_main.solo_ai_slots = {2: true}
	CoreActivation._env = 0
	assert_bool(CoreActivation.applies(_main)).is_false()


func test_applies_is_false_without_an_ai_seat_and_without_a_room() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	assert_bool(CoreActivation.applies(_main)).is_false()


func test_applies_is_true_with_an_ai_seat() -> void:
	_main.solo_ai_slots = {2: true}
	assert_bool(CoreActivation.applies(_main)).is_true()


func test_applies_is_true_in_an_agreed_automatic_room() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_fake_session(1)
	var applies := CoreActivation.applies(_main)
	_end_session()
	assert_bool(applies).is_true()


func test_applies_is_false_in_a_manual_room() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.MANUAL
	_fake_session(1)
	var applies := CoreActivation.applies(_main)
	_end_session()
	assert_bool(applies).is_false()


func test_a_human_unit_with_a_non_movement_rule_is_lifecycle_but_not_core_nor_move_path() -> void:
	_main.solo_ai_slots = {2: true}
	var u := _unit(1, "Rifles", ["Furious"])
	assert_bool(CoreActivation.is_lifecycle_unit(_main, u)).override_failure_message("lifecycle").is_true()
	assert_bool(CoreActivation.is_core_unit(_main, u)).override_failure_message("core").is_false()
	assert_bool(CoreActivation.on_move_path(_main, u)).override_failure_message("move path").is_false()


func test_a_plain_human_unit_is_lifecycle_core_and_move_path() -> void:
	_main.solo_ai_slots = {2: true}
	var u := _unit(1, "Rifles")
	assert_bool(CoreActivation.is_lifecycle_unit(_main, u)).is_true()
	assert_bool(CoreActivation.is_core_unit(_main, u)).is_true()
	assert_bool(CoreActivation.on_move_path(_main, u)).is_true()


func test_an_ai_unit_is_none_of_the_three() -> void:
	_main.solo_ai_slots = {2: true}
	var u := _unit(2, "Drones")
	assert_bool(CoreActivation.is_lifecycle_unit(_main, u)).is_false()
	assert_bool(CoreActivation.is_core_unit(_main, u)).is_false()
	assert_bool(CoreActivation.on_move_path(_main, u)).is_false()


func test_a_unit_another_slot_owns_is_none_of_the_three() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_fake_session(1)
	var u := _unit(2, "Raiders")
	var got := [CoreActivation.is_lifecycle_unit(_main, u), CoreActivation.is_core_unit(_main, u),
		CoreActivation.on_move_path(_main, u)]
	_end_session()
	assert_array(got).is_equal([false, false, false])


func test_no_unit_is_lifecycle_before_the_game_is_playing() -> void:
	_main.solo_ai_slots = {2: true}
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.DEPLOYMENT
	assert_bool(CoreActivation.is_lifecycle_unit(_main, _unit(1, "Rifles"))).is_false()


func test_capture_returns_a_live_core_handle_and_zero_without_a_controller() -> void:
	_main.solo_ai_slots = {2: true}
	_unit(1, "Rifles")
	_unit(2, "Drones")
	_main.solo_controller = null
	assert_int(CoreActivation.capture(_main)).override_failure_message("no controller").is_equal(0)
	_main._ensure_solo_controller()
	assert_int(CoreActivation.capture(_main)).override_failure_message("with a controller").is_not_equal(0)
