extends GdUnitTestSuite
## Plan 3.3a FIX (konrad 12.10., defect in #1771): the host records a received activation FACT and
## advances + broadcasts the token.
##
## 3.3a made the token a LOCAL gate: the acting machine advances its own token, and a guest never
## advances its own (it only mirrors the host). That left a hole the #1771 review missed — when the
## GUEST took its turn, its activation fact travelled (`sync_unit_activation`) but NOTHING on the host
## reacted: `sync_unit_activation` only set the flag and emitted `remote_activation_updated`, and the
## host's handler ignored the token. So host P1 -> token 2 -> guest P2 -> token stayed 2 -> deadlock.
## The fix is the plan's own 3.3a wording: "after each completed activation (activation facts already
## travel) [the host] computes the next side and broadcasts turn_state". Host-authoritative REFUSAL of
## an out-of-turn fact stays 3.3c (NOT V1) — this only advances when the owner is the side on turn.

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
	# The receive path under test: sync_unit_activation needs the army manager and the decoded fact
	# must reach main's handler exactly as it does in production (the signal was wired on the real net).
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


## The host owns the token and the guest took its turn: the guest's activation FACT arrives on the host
## (`sync_unit_activation` is the wire frame) and must flip the token back to P1 + broadcast it. Two
## units per side so no round end is reached (that path is unchanged, 3.3b).
func test_the_host_advances_the_token_when_the_guest_activation_fact_arrives() -> void:
	_fake_session(1, true)
	_agreed_automatic_room()
	_unit(1, "P1 A")
	_unit(1, "P1 B")
	var p2a := _unit(2, "P2 A")
	_unit(2, "P2 B")
	# The host has already taken P1's turn; the token is the guest's.
	await _main.hotseat_record_activation(1)
	assert_int(_main._hotseat_side_on_turn()) \
		.override_failure_message("3.3a-fix fixture — after P1 activates the token is P2's") \
		.is_equal(2)
	var before := _sent("sync_turn_state")
	# The guest's activation fact arrives on the host through the real receive path.
	_main.network_manager.sync_unit_activation(p2a.unit_id, true, 1)
	assert_int(_main._hotseat_side_on_turn()) \
		.override_failure_message(
			"3.3a-fix — a guest activation fact must advance the host's token back to P1 (defect in #1771)") \
		.is_equal(1)
	assert_int(_sent("sync_turn_state")) \
		.override_failure_message("3.3a-fix — the host must broadcast the flipped token") \
		.is_equal(before + 1)
	if _sent("sync_turn_state") == before + 1:
		assert_int(int((_net.sent[-1] as Dictionary)["a"][0])) \
			.override_failure_message("3.3a-fix — the broadcast token must be P1") \
			.is_equal(1)
	assert_int(_logged_containing("P1 to activate")) \
		.override_failure_message("3.3a-fix — the hand-over line is written on the host") \
		.is_equal(1)
	_end_session()


## The mirror guard stays: on a guest a received activation fact must NOT advance its own token.
func test_the_guest_does_not_advance_on_a_received_activation_fact() -> void:
	_fake_session(2, false)
	_agreed_automatic_room()
	var p1a := _unit(1, "P1 A")
	_unit(2, "P2 A")
	_main.call("_on_turn_state_received", 2)
	_main.network_manager.sync_unit_activation(p1a.unit_id, true, 1)
	assert_int(_sent("sync_turn_state")) \
		.override_failure_message("3.3a-fix — a guest must never broadcast a token it does not own") \
		.is_equal(0)
	_end_session()
