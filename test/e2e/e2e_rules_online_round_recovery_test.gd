extends GdUnitTestSuite
## Plan 3.4a (konrad 12.10.): round-start recovery online, on the owner's tray.
##
## At a round advance in an Automatic online room the HOST runs the round-start Shaken recovery
## (Battleborn / Steadfast) for BOTH sides — the same `_solo_battleborn_recovery()` the solo and hotseat
## paths use. Each human unit's roll is routed by `_owner_roll` to its OWNER's tray (request_roll, the
## 120 s bound, and a labelled auto-roll fallback for a vacant seat); the guest never runs it and only
## sees the mirrored result (`_solo_mirror_shaken`). So one recovery runs, one line appears on both.

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


## A REAL NetworkManager with only the transport swapped out: a live session, this client on slot 1
## (the host), the guest on slot 2; records every `send_command` and `_remote_call`.
func _fake_session(host: bool) -> void:
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/network_manager.gd\"\nvar sent: Array = []\n" \
		+ "func is_multiplayer_active() -> bool:\n\treturn true\n" \
		+ "func get_my_player_slot() -> int:\n\treturn 1\n" \
		+ "func _validate_rpc_ready(_context: String = \"\") -> bool:\n\treturn true\n" \
		+ "func _remote_call(method: String, args: Array, _target_peer: int = 0) -> void:\n" \
		+ "\tsent.append({\"m\": method, \"a\": args})\n" \
		+ "func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:\n" \
		+ "\tsent.append({\"cmd\": type, \"a\": [payload, target_peer]})\n\treturn true\n"
	assert_int(src.reload()).is_equal(OK)
	_net = src.new()
	_net.is_host = host
	_net.army_manager = _main.opr_army_manager
	_net.peer_to_slot = {1: 1, GUEST_PEER: 2}
	_main.network_manager = _net


func _agreed_automatic_room() -> void:
	_main.solo_ai_slots = {}
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._hotseat_turn = null


func _unit(pid: int, unit_name: String) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3.ZERO])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _cmd(kind: String) -> int:
	var n := 0
	for e in _net.sent:
		if str((e as Dictionary).get("cmd", "")) == kind:
			n += 1
	return n


func _logged_containing(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).contains(needle):
			n += 1
	return n


func _end_session() -> void:
	if _main != null:
		_main.network_manager = _real_net
	if _net != null:
		_net.free()
		_net = null


# === the host runs the recovery, the guest's roll rides its own tray ===========================

func test_the_host_rolls_a_guest_shaken_recovery_on_the_owners_tray() -> void:
	_fake_session(true)
	_agreed_automatic_room()
	_main._owner_roll_timeout_s = 0.5   # the guest never answers; the labelled fallback closes it fast
	var shaken := _unit(2, "Guards")
	shaken.unit_properties["special_rules"] = ["Battleborn"]
	shaken.is_shaken = true
	await _main._do_next_round()
	assert_int(_cmd("request_roll")) \
		.override_failure_message("3.4a — the host must ask the guest's owner tray for a Shaken recovery roll") \
		.is_equal(1)
	assert_int(_logged_containing("Battleborn: Guards")) \
		.override_failure_message("3.4a — the recovery prints one result line, as solo/hotseat") \
		.is_equal(1)
	_end_session()
