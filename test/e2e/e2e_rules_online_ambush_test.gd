extends GdUnitTestSuite
## Plan 3.4b (konrad 12.10., ruling (a)): Ambush online in turn order, host-driven handshake.
##
## At the round start (round >= 2) the HOST drives the reserve step for each side, opener first:
##   * a side with NO reserve is skipped at once (no wire, no wait);
##   * otherwise the host sends `request_ambush_turn` to that side's peer; the owner runs its OWN
##     `_solo_ambush_human_turn` (its tray / beacons / enemies), places ONE reserve unit — the placement
##     travels over the existing unit channel — and answers `ambush_turn_done`;
##   * the host waits with a 120 s bound and, on no answer, prints a labelled auto-skip line.
## Hotseat keeps `_hotseat_ambush_arrivals`; solo keeps `_solo_alternate_ambush_arrivals`.

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


## A REAL NetworkManager with only the transport swapped out: the host on slot 1, the guest on slot 2,
## recording every `send_command`.
func _fake_session() -> void:
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
	_net.is_host = true
	_net.army_manager = _main.opr_army_manager
	_net.peer_to_slot = {1: 1, GUEST_PEER: 2}
	_main.network_manager = _net


func _agreed_automatic_room() -> void:
	_main.solo_ai_slots = {}
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 2
	_main._hotseat_turn = null
	_main._ensure_solo_controller()


func _unit(pid: int, unit_name: String) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3.ZERO])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Ambush-turn requests the host sent to `slot`, in order.
func _ambush_requests_for(slot: int) -> int:
	var n := 0
	for e in _net.sent:
		var frame := e as Dictionary
		if str(frame.get("cmd", "")) != "request_ambush_turn":
			continue
		if int((frame["a"][0] as Dictionary).get("slot", -1)) == slot:
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


# === the host asks only a side that has a reserve, in turn order ===============================

func test_the_host_asks_only_a_side_with_a_reserve_and_skips_the_empty_one() -> void:
	_fake_session()
	_agreed_automatic_room()
	_main.set("_ambush_turn_timeout_s", 0.3)   # harmless on main (property lands with 3.4b)
	var reservist := _unit(2, "Raiders")
	reservist.unit_properties["ambush_reserve"] = true
	# opener = the host (slot 1, no reserve), then the guest (slot 2, reserve)
	if _main.has_method("_online_ambush_arrivals"):
		await _main._online_ambush_arrivals(2, 1)
	assert_int(_ambush_requests_for(2)) \
		.override_failure_message("3.4b — the host must ask the reserve-holding side for its Ambush turn") \
		.is_equal(1)
	assert_int(_ambush_requests_for(1)) \
		.override_failure_message("3.4b — a side with no reserve is skipped at once (no request)") \
		.is_equal(0)
	assert_int(_logged_containing("no answer — skipped")) \
		.override_failure_message("3.4b — an unanswered Ambush turn is skipped with a labelled line") \
		.is_equal(1)
	_end_session()


## The owner's answer clears the host's wait.
func test_a_done_message_marks_the_side_answered() -> void:
	_fake_session()
	_agreed_automatic_room()
	_main.set("_ambush_turn_waiters", {2: false})
	_main._on_network_command("ambush_turn_done", {"slot": 2}, GUEST_PEER)
	var waiters = _main.get("_ambush_turn_waiters")
	assert_bool(waiters != null and bool((waiters as Dictionary).get(2, false))) \
		.override_failure_message("3.4b — ambush_turn_done from the owner must clear the host's wait") \
		.is_true()
	_end_session()
