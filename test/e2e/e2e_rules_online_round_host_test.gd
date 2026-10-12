extends GdUnitTestSuite
## Plan 3.3b (Q4 Road 2, konrad 12.10.): ONE round advance, by the host.
##
## In an Automatic online room only the host advances the round. A guest pressing Next Round sends
## `request_next_round` and does NOT advance its own state; the host runs the end-round path and
## broadcasts `sync_round_advance`, which guests apply. That removes the `any_peer` double advance
## (network_manager.gd sync_round_advance) for Automatic rooms — two near-simultaneous presses must
## land exactly one advance on every peer. Manual rooms keep the old behaviour.

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
## recording every `send_command` and every `_remote_call` so a test sees the exact frames.
func _fake_session(my_slot: int, host: bool) -> void:
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/network_manager.gd\"\nvar sent: Array = []\n" \
		+ "func is_multiplayer_active() -> bool:\n\treturn true\n" \
		+ "func get_my_player_slot() -> int:\n\treturn %d\n" % my_slot \
		+ "func _validate_rpc_ready(_context: String = \"\") -> bool:\n\treturn true\n" \
		+ "func _remote_call(method: String, args: Array, _target_peer: int = 0) -> void:\n" \
		+ "\tsent.append({\"m\": method, \"a\": args})\n" \
		+ "func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:\n" \
		+ "\tsent.append({\"cmd\": type, \"a\": [payload, target_peer]})\n\treturn true\n"
	assert_int(src.reload()).is_equal(OK)
	_net = src.new()
	_net.is_host = host
	_net.army_manager = _main.opr_army_manager
	_main.network_manager = _net


func _agreed_automatic_room() -> void:
	_main.solo_ai_slots = {}
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._hotseat_turn = null


func _rpc(kind: String) -> int:
	var n := 0
	for e in _net.sent:
		if str((e as Dictionary).get("m", "")) == kind:
			n += 1
	return n


func _cmd(kind: String) -> int:
	var n := 0
	for e in _net.sent:
		if str((e as Dictionary).get("cmd", "")) == kind:
			n += 1
	return n


func _end_session() -> void:
	if _main != null:
		_main.network_manager = _real_net
	if _net != null:
		_net.free()
		_net = null


# === the guest requests, the host advances ======================================================

## A guest's Next Round must NOT advance its own state — it asks the host.
func test_a_guest_next_round_requests_the_host_and_stays_put() -> void:
	_fake_session(2, false)
	_agreed_automatic_room()
	await _main._do_next_round()
	assert_int(_main.opr_army_manager.current_round) \
		.override_failure_message("3.3b — a guest must not advance the round on its own") \
		.is_equal(1)
	assert_int(_cmd("request_next_round")) \
		.override_failure_message("3.3b — a guest's Next Round must ask the host to advance") \
		.is_equal(1)
	assert_int(_rpc("sync_round_advance")) \
		.override_failure_message("3.3b — a guest must not broadcast a round advance") \
		.is_equal(0)
	_end_session()


## The host's own Next Round advances exactly once and broadcasts.
func test_the_host_next_round_advances_once_and_broadcasts() -> void:
	_fake_session(1, true)
	_agreed_automatic_room()
	await _main._do_next_round()
	assert_int(_main.opr_army_manager.current_round) \
		.override_failure_message("3.3b — the host advances the round") \
		.is_equal(2)
	assert_int(_rpc("sync_round_advance")) \
		.override_failure_message("3.3b — the host broadcasts exactly one round advance") \
		.is_equal(1)
	_end_session()


## The host serves a guest's request: one advance on the host, one broadcast.
func test_the_host_advances_when_a_guest_requests() -> void:
	_fake_session(1, true)
	_agreed_automatic_room()
	_main._on_network_command("request_next_round", {}, 42)
	await _runner.simulate_frames(4)
	assert_int(_main.opr_army_manager.current_round) \
		.override_failure_message("3.3b — the host advances on a guest's request") \
		.is_equal(2)
	assert_int(_rpc("sync_round_advance")) \
		.override_failure_message("3.3b — one advance, one broadcast, no double") \
		.is_equal(1)
	_end_session()


## A guest applies the host's broadcast once and never re-broadcasts (no echo, no double advance).
func test_the_guest_applies_the_hosts_advance_without_rebroadcasting() -> void:
	_fake_session(2, false)
	_agreed_automatic_room()
	_net.sync_round_advance()   # the host's broadcast arriving
	assert_int(_main.opr_army_manager.current_round) \
		.override_failure_message("3.3b — the guest applies the host's advance") \
		.is_equal(2)
	assert_int(_rpc("sync_round_advance")) \
		.override_failure_message("3.3b — the guest must not echo the advance") \
		.is_equal(0)
	_end_session()
