extends GdUnitTestSuite
## Plan 3.5 (konrad 12.10.): disconnect + token.
##
## The 120 s roll bound is already on every roll kind (all rolls route through `_owner_roll`) and the
## reconnect restore is already the 3.3a full-state push (`turn_state`). The new work is the disconnect
## itself: in an Automatic online room, when the player whose side is ON TURN drops, the table waits —
## the host says so and KEEPS the token (the off-turn gate already blocks the other player, so nothing
## advances). An off-turn drop is silent.

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


func _fake_session() -> void:
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/network_manager.gd\"\nvar sent: Array = []\n" \
		+ "func is_multiplayer_active() -> bool:\n\treturn true\n" \
		+ "func get_my_player_slot() -> int:\n\treturn 1\n" \
		+ "func get_my_peer_id() -> int:\n\treturn 1\n" \
		+ "func _validate_rpc_ready(_context: String = \"\") -> bool:\n\treturn true\n" \
		+ "func _remote_call(method: String, args: Array, _target_peer: int = 0) -> void:\n" \
		+ "\tsent.append({\"m\": method, \"a\": args})\n"
	assert_int(src.reload()).is_equal(OK)
	_net = src.new()
	_net.is_host = true
	_net.peer_to_slot = {1: 1, GUEST_PEER: 2}
	_main.network_manager = _net


func _agreed_automatic_room(on_turn_slot: int) -> void:
	_main.solo_ai_slots = {}
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._hotseat_turn = TwoHumanTurn.new()
	_main._hotseat_turn.side_on_turn = on_turn_slot


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


func test_the_token_waits_when_the_on_turn_player_drops() -> void:
	_fake_session()
	_agreed_automatic_room(2)   # the guest (slot 2) is on turn
	_main._on_player_left(GUEST_PEER)
	assert_int(_logged_containing("dropped while on turn")) \
		.override_failure_message("3.5 — the host must say the table waits when the on-turn player drops") \
		.is_equal(1)
	assert_int(_main._hotseat_side_on_turn()) \
		.override_failure_message("3.5 — the token is kept for the player who dropped") \
		.is_equal(2)
	_end_session()


func test_an_off_turn_drop_is_silent() -> void:
	_fake_session()
	_agreed_automatic_room(1)   # the host (slot 1) is on turn; the guest leaving is off-turn
	_main._on_player_left(GUEST_PEER)
	assert_int(_logged_containing("dropped while on turn")) \
		.override_failure_message("3.5 — an off-turn drop must not print the waiting line") \
		.is_equal(0)
	_end_session()
