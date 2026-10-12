extends GdUnitTestSuite
## Plan 3.3a (Q4 Road 2, konrad 12.10.): the online turn token, LOCAL gate.
##
## In a room the two players agreed on (3.0) with the engine on (3.1) the turn alternates one-for-one
## (Q4 Road 2), but the refusal is LOCAL: the acting player's own machine applies the hotseat gate
## (2.T2a verbs + Pass, 2.T2b off-turn drag snap-back) against the token IT has, so an off-turn drag
## still snaps back with no fact on the wire. The host owns the token (2.T1 TwoHumanTurn): after an
## activation completes it computes the next side and broadcasts `turn_state`; a guest applies the
## received token and never advances its own. Host-authoritative refusal (the host rejecting an
## out-of-turn FACT) is deliberately NOT V1 — it is plan step 3.3c, for friends at a table.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const HOST_PEER := 1

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


## A REAL NetworkManager with only the transport swapped out: a live session, this client on `my_slot`,
## records every _remote_call so a test can see the exact wire frames.
func _fake_session(my_slot: int, host: bool) -> void:
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/network_manager.gd\"\nvar sent: Array = []\n" \
		+ "func is_multiplayer_active() -> bool:\n\treturn true\n" \
		+ "func get_my_player_slot() -> int:\n\treturn %d\n" % my_slot \
		+ "func _validate_rpc_ready(_context: String = \"\") -> bool:\n\treturn true\n" \
		+ "func _remote_call(method: String, args: Array, _target_peer: int = 0) -> void:\n" \
		+ "\tsent.append({\"m\": method, \"a\": args})\n"
	assert_int(src.reload()).is_equal(OK)
	_net = src.new()
	_net.is_host = host
	_main.network_manager = _net


func _agreed_automatic_room() -> void:
	_main.solo_ai_slots = {}
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._hotseat_turn = null


func _unit(pid: int, unit_name: String) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3.ZERO])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _sent(kind: String) -> int:
	var n := 0
	for e in _net.sent:
		if str((e as Dictionary).get("m", "")) == kind:
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


# === the gate is live online ===================================================================

## An off-turn guest is refused: the token starts with P1, our slot 2 may not activate, and a drag of
## our own unit snaps back with the 2.T2b line and NOTHING on the wire.
func test_an_off_turn_guest_drag_snaps_back_with_no_fact_on_the_wire() -> void:
	_fake_session(2, false)
	_agreed_automatic_room()
	var mine := _unit(2, "Raiders")
	assert_str(_main.hotseat_turn_refusal(2)) \
		.override_failure_message("3.3a — online the off-turn side must be refused (the token starts with P1)") \
		.is_equal("It is P1's turn")
	assert_bool(_main.hotseat_off_turn_drag(mine)) \
		.override_failure_message("3.3a — an off-turn drag online must snap back (reuses 2.T2b)") \
		.is_true()
	assert_int(_logged_containing("is not on turn — moved back")) \
		.override_failure_message("3.3a — the snap-back line must be written on the dragging machine") \
		.is_equal(1)
	assert_int(_sent("sync_move_log") + _sent("sync_log_event") + _sent("sync_turn_state")) \
		.override_failure_message("3.3a — the snap-back must put no fact on the wire") \
		.is_equal(0)
	_end_session()


## After the host's activation the guest receives the token and may act.
func test_the_token_crosses_the_wire_and_then_the_guest_may_activate() -> void:
	_fake_session(2, false)
	_agreed_automatic_room()
	var mine := _unit(2, "Raiders")
	# On main the receive path does not exist yet (it lands with 3.3a); the suite must still compile
	# and the gate test above is the red. Guarded so the debugger does not abort on a missing method.
	if _main.has_method("_on_turn_state_received"):
		_main.call("_on_turn_state_received", 2)
	assert_str(_main.hotseat_turn_refusal(2)) \
		.override_failure_message("3.3a — once the token is ours the guest's side may act") \
		.is_equal("")
	assert_bool(_main.hotseat_off_turn_drag(mine)).is_false()
	_end_session()


## The host owns the token: after an activation completes it broadcasts the next side.
func test_the_host_broadcasts_the_next_token_after_an_activation() -> void:
	_fake_session(1, true)
	_agreed_automatic_room()
	_unit(2, "Raiders")
	await _main.hotseat_record_activation(1)
	var frames := _sent("sync_turn_state")
	assert_int(frames) \
		.override_failure_message("3.3a — the host must broadcast turn_state after an activation completes") \
		.is_equal(1)
	if frames == 1:
		assert_int(int((_net.sent[-1] as Dictionary)["a"][0])) \
			.override_failure_message("3.3a — the broadcast token must be the OTHER side (P2)") \
			.is_equal(2)
	_end_session()


## A guest never advances its own token — it only mirrors what the host sends.
func test_a_guest_does_not_broadcast_or_advance_on_its_own_activation() -> void:
	_fake_session(2, false)
	_agreed_automatic_room()
	_unit(2, "Raiders")
	await _main.hotseat_record_activation(2)
	assert_int(_sent("sync_turn_state")) \
		.override_failure_message("3.3a — a guest must not broadcast a token it does not own") \
		.is_equal(0)
	_end_session()
