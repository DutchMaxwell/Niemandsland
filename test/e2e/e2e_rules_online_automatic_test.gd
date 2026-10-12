extends GdUnitTestSuite
## Plan 3.1 (Q6, maintainer 12.10.): an online room that AGREED Automatic runs the engine. The
## resolvers borrow the SoloController for geometry, the other human's units count as enemies, and every
## defender roll goes to its owner (`_owner_roll` -> request_roll/roll_result, step 0.1a). Two guards the
## maintainer added: the JOIN/CREATE clamp stays (a room is Manual until both agree — 3.0), and the
## non-active peer applies NOTHING on its own during the other player's activation — the hotseat turn /
## activation engine stays OFF online (`_solo_hotseat_automatic()` is local-only; the online turn token is
## 3.3), so wounds land once, on the attacker's machine, and only mirror out.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const GUEST_PEER := 42

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


func after_test() -> void:
	if _main != null:
		_main.network_manager = _real_net
	if _net != null:
		_net.free()
		_net = null
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A real session double: active, this client on slot 1, the guest on slot 2; records every send.
func _fake_session() -> void:
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/network_manager.gd\"\nvar sent: Array = []\n" \
		+ "func is_multiplayer_active() -> bool:\n\treturn true\n" \
		+ "func get_my_player_slot() -> int:\n\treturn 1\n" \
		+ "func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:\n" \
		+ "\tsent.append([type, payload, target_peer])\n\treturn true\n"
	assert_int(src.reload()).is_equal(OK)
	_net = src.new()
	_net.peer_to_slot = {1: 1, GUEST_PEER: 2}
	_net.player_names = {GUEST_PEER: "Guest"}
	_main.network_manager = _net


func _clear_controller() -> void:
	if _main.solo_controller != null:
		_main.solo_controller.queue_free()
		_main.solo_controller = null


func _unit(pid: int, unit_name: String) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3.ZERO])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func test_an_agreed_automatic_room_builds_the_engine_controller() -> void:
	_fake_session()
	_clear_controller()
	_main.solo_ai_slots = {}
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_main._ensure_solo_controller()
	assert_object(_main.solo_controller) \
		.override_failure_message("3.1 — an agreed online automatic room must build the engine controller") \
		.is_not_null()


func test_a_manual_room_builds_no_engine_controller() -> void:
	_fake_session()
	_clear_controller()
	_main.solo_ai_slots = {}
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.MANUAL
	_main._ensure_solo_controller()
	assert_object(_main.solo_controller).is_null()


func test_the_remote_human_is_an_enemy_only_when_automatic() -> void:
	_fake_session()
	_main.solo_ai_slots = {}
	var host := _unit(1, "Guards")
	var guest := _unit(2, "Raiders")
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	assert_bool(_main._engine_enemy(host, guest)) \
		.override_failure_message("3.1 — the other human's unit is an enemy in an automatic room") \
		.is_true()
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.MANUAL
	assert_bool(_main._engine_enemy(host, guest)).is_false()


## The maintainer's addition: the guest applies nothing on its own (no double engine). The hotseat turn /
## activation engine must stay LOCAL-ONLY online; only geometry/resolution is unlocked.
func test_the_non_active_peer_runs_no_turn_engine_online() -> void:
	_fake_session()
	_main.solo_ai_slots = {}
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	assert_bool(_main._solo_hotseat_automatic()) \
		.override_failure_message("3.1 — the guest must not run its own activation/turn engine online") \
		.is_false()
