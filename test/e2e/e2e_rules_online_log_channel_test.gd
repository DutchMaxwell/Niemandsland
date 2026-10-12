extends GdUnitTestSuite
## Plan 3.2 (konrad 12.10.): rule lines on BOTH screens in an agreed online Automatic room.
##
## The log channel itself is not new — NML-946 built it: main._log_rule_event writes the local line AND
## calls network_manager.broadcast_log_event; the peer's copy is written by main._on_remote_log_event;
## and WHICH lines travel is the producer's `travels` flag, routed at the one printing point
## main._print_rule_notes. That much is already pinned by e2e_mp_log_channel_test.
##
## What 3.2 PINS here is that the channel reaches the room 3.0/3.1 create: once two humans AGREE on
## Automatic (3.0) and the host resolver therefore runs (3.1), the host's rule lines — a Fortified or
## Banner refusal the guest cannot observe on their own machine — must land in the guest's log instead
## of stopping at the network card. The channel is mode-independent; the room is the new part, so the
## test establishes the real agreed-room state (rules AUTOMATIC, engine controller built) around it.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const GUEST_PEER := 42
const RULE_LINE := "Fortified: the Guard unit shrugs off the arrow"

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


## The REAL NetworkManager with only its transport swapped out: an active session, this client on slot 1,
## the guest on slot 2, rpc-ready, and every _remote_call recorded — so the actual broadcast_log_event
## body runs and we see the exact wire frame it produces.
func _fake_session() -> void:
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/network_manager.gd\"\nvar sent: Array = []\n" \
		+ "func is_multiplayer_active() -> bool:\n\treturn true\n" \
		+ "func get_my_player_slot() -> int:\n\treturn 1\n" \
		+ "func _validate_rpc_ready(_context: String = \"\") -> bool:\n\treturn true\n" \
		+ "func _remote_call(method: String, args: Array, _target_peer: int = 0) -> void:\n" \
		+ "\tsent.append({\"m\": method, \"a\": args})\n"
	assert_int(src.reload()).is_equal(OK)
	_net = src.new()
	_net.peer_to_slot = {1: 1, GUEST_PEER: 2}
	_main.network_manager = _net


func _clear_controller() -> void:
	if _main.solo_controller != null:
		_main.solo_controller.queue_free()
		_main.solo_controller = null


## Every log line this client put on the wire, in order.
func _sent_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	for e in _net.sent:
		var frame: Dictionary = e as Dictionary
		if str(frame.get("m", "")) == "sync_log_event":
			out.append(str((frame.get("a", []) as Array)[1]))
	return out


func _logged_containing(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).contains(needle):
			n += 1
	return n


## Frees the session double INSIDE the test (gdUnit flags an unparented node still alive at the test's
## end as an orphan; freeing it here keeps the suite orphan-free).
func _end_session() -> void:
	if _main != null:
		_main.network_manager = _real_net
	if _net != null:
		_net.free()
		_net = null


## The pin: in an agreed online Automatic room (3.0 agreement + 3.1 engine) the host resolver's rule
## line is written locally AND broadcast, so the guest's screen is not silent.
func test_a_resolver_rule_line_reaches_the_peer_in_an_agreed_automatic_room() -> void:
	_fake_session()
	_clear_controller()
	_main.solo_ai_slots = {}
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_main._ensure_solo_controller()
	assert_object(_main.solo_controller) \
		.override_failure_message("3.2 setup — the agreed online Automatic room builds the engine (3.1)") \
		.is_not_null()
	_main._print_rule_notes({"rule_notes": [{"text": RULE_LINE, "travels": true}]})
	var sent := _sent_lines()
	var found := 0
	for line in sent:
		if line.contains("Fortified"):
			found += 1
	assert_int(found) \
		.override_failure_message("3.2 — the resolver's Fortified line must reach the peer over broadcast_log_event") \
		.is_equal(1)
	assert_int(_logged_containing("Fortified")) \
		.override_failure_message("3.2 — the resolver's Fortified line must ALSO sit in the local log (both screens)") \
		.is_equal(1)
	_end_session()
