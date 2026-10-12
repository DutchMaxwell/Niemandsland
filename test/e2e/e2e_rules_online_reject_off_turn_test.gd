extends GdUnitTestSuite
## Rules 3.3c: the host rejects an OUT-OF-TURN activation fact — the turn token is authoritative.
##
## 3.3a is a LOCAL gate: each machine refuses its own off-turn actions, but a free drag has no gate
## (2.7e), so an out-of-turn activation FACT can still reach the host. 3.3a-fix advances the token only
## when the fact's owner IS the side on turn; 3.3c adds the reject path: the host leaves the token put,
## un-activates the offending unit on the acting machine and logs the off-turn line on both screens.
## Effects the acting machine already resolved and mirrored (e.g. wounds) are NOT rolled back — that is
## plan 3.7 (owner allocates wounds / host-authoritative resolution), deliberately out of scope here.

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
	_net.army_manager = _main.opr_army_manager
	if _net.has_signal("remote_activation_updated"):
		_net.remote_activation_updated.connect(_main._on_remote_activation_updated)


func _agreed_automatic_room() -> void:
	_main.solo_ai_slots = {}
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._hotseat_turn = null


func _unit(pid: int, unit_name: String) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3.ZERO])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _clearing_frames(unit_id: String) -> Array:
	var out: Array = []
	for e in _net.sent:
		var d := e as Dictionary
		if str(d.get("m", "")) == "sync_unit_activation":
			var a: Array = d.get("a", [])
			if not a.is_empty() and str(a[0]) == unit_id and a.size() >= 2 and bool(a[1]) == false:
				out.append(d)
	return out


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


## The host holds the token for P2; a P1 activation fact arrives. It must be refused: token unchanged,
## the P1 unit un-activated on the acting machine, the off-turn line on both screens.
func test_the_host_refuses_an_out_of_turn_activation_fact() -> void:
	_fake_session(1, true)
	_agreed_automatic_room()
	_main.call("_apply_turn_token", 2)
	var p1 := _unit(1, "P1 A")
	_unit(2, "P2 A")
	assert_int(_main._hotseat_side_on_turn()) \
		.override_failure_message("3.3c fixture — the host holds the token for P2") \
		.is_equal(2)
	var p1_id := p1.unit_id
	_main.network_manager.sync_unit_activation(p1_id, true, 1)
	assert_int(_main._hotseat_side_on_turn()) \
		.override_failure_message("3.3c — an out-of-turn fact must NOT advance the token") \
		.is_equal(2)
	assert_bool(p1.is_activated) \
		.override_failure_message("3.3c — the host must un-activate the offending unit") \
		.is_false()
	assert_int(_clearing_frames(p1_id).size()) \
		.override_failure_message("3.3c — the host must send the clearing frame to the acting machine") \
		.is_equal(1)
	assert_int(_logged_containing("It is P2's turn")) \
		.override_failure_message("3.3c — the off-turn line must be logged") \
		.is_equal(1)
	_end_session()


## The guard is not broken: an ON-turn fact still advances + broadcasts the token (3.3a-fix stays).
func test_an_on_turn_activation_fact_still_advances_the_token() -> void:
	_fake_session(1, true)
	_agreed_automatic_room()
	_main.call("_apply_turn_token", 2)
	_unit(1, "P1 A")
	var p2 := _unit(2, "P2 A")
	var p2_id := p2.unit_id
	_main.network_manager.sync_unit_activation(p2_id, true, 1)
	assert_int(_main._hotseat_side_on_turn()) \
		.override_failure_message("3.3c — an on-turn fact must still advance the token (3.3a-fix)") \
		.is_equal(1)
	assert_int(_clearing_frames(p2_id).size()) \
		.override_failure_message("3.3c — an on-turn fact must NOT be cleared") \
		.is_equal(0)
	_end_session()
