extends GdUnitTestSuite
## "No AI without its tick" (#1719), the online cast. Since #1834 a local table without an AI seat asks
## the caster's opponent whether to interfere; an online room only logged "an online room does not offer
## the opponent the choice yet". The opponent sits at ANOTHER machine, so the question rides the
## owner-roll seam (`request_roll` / `roll_result`, step 0.1a): the caster's machine sends the cast, the
## opponent's machine opens its own InterferenceDialog, spends its own tokens and answers with the count.
## Real: scenes/main.tscn, _run_human_cast, _rpc_request_roll / _rpc_roll_result and the real dialog card.
## The network side is the owner-roll suites' NetworkManager double (records every send instead of
## sending, every broadcast included); `my_slot` lets ONE main play both machines of the round trip.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
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
	_main._solo_batch = true
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC   # the room agreed (3.0)
	_real_net = _main.network_manager


func after_test() -> void:
	_end_session()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## An active session: the host (peer 1) on slot 1, the guest on slot 2 — or nobody there (vacant seat).
func _fake_session(guest_seated: bool = true) -> void:
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/network_manager.gd\"\nvar sent: Array = []\nvar my_slot := 1\n" \
		+ "func is_multiplayer_active() -> bool:\n\treturn true\n" \
		+ "func get_my_player_slot() -> int:\n\treturn my_slot\n" \
		+ "func _validate_rpc_ready(_context: String = \"\") -> bool:\n\treturn true\n" \
		+ "func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:\n" \
		+ "\tsent.append([type, payload, target_peer])\n\treturn true\n"
	assert_int(src.reload()).is_equal(OK)
	_net = src.new()
	_net.peer_to_slot = {1: 1, GUEST_PEER: 2} if guest_seated else {1: 1}
	_net.player_names = {GUEST_PEER: "Guest"} if guest_seated else {}
	_main.network_manager = _net


func _end_session() -> void:
	if _main != null:
		_main.network_manager = _real_net
	if _net != null:
		_net.free()
		_net = null


func _reg(pid: int, unit_name: String, x_in: float, rules: Array = []) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x_in * INCH, 0.0, 0.0)])
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _sent(type: String) -> Array:
	var out: Array = []
	for s in _net.sent:
		if str((s as Array)[0]) == type:
			out.append(s)
	return out


func _log_from(start: int) -> String:
	var t := ""
	for e in _main.battle_log.entries().slice(start):
		t += str((e as Dictionary)["text"]) + "\n"
	return t


func _interference_card() -> PromptCard:
	for n in _main.get_children():
		if n is InterferenceDialog:
			for c in n.get_children():
				if c is PromptCard and (c as PromptCard).title == "Enemy spell!":
					return c
	return null


func _wait(cond: Callable) -> void:
	for _i in 300:
		if cond.call():
			return
		await get_tree().process_frame


## P1 (this machine) casts at P2's unit; P2's caster stands within 18" with two tokens.
func _cast_setup() -> Array:
	var seer := _reg(1, "Seer", 0.0, ["Caster(2)"])
	seer.casts_current = 2
	var foe := _reg(2, "Raiders", 10.0)
	var witch := _reg(2, "Witch", -6.0, ["Caster(2)"])
	witch.casts_current = 2
	_main._ensure_solo_controller()   # an agreed Automatic room borrows the controller for geometry (3.1)
	assert_object(_main.solo_controller).override_failure_message("fixture: no engine controller").is_not_null()
	return [seer, foe, witch]


func test_an_online_cast_asks_the_remote_opponent(timeout := 120000) -> void:
	_fake_session()
	var units := _cast_setup()
	var seer: GameUnit = units[0]
	var witch: GameUnit = units[2]
	var start: int = _main.battle_log.entries().size()
	var done := [false]
	(func() -> void:
		await _main._run_human_cast(seer, seer, {"name": "Bolt", "threshold": 2}, [units[1]])
		done[0] = true).call()
	await _wait(func() -> bool: return done[0] or not _sent("request_roll").is_empty())
	var asks := _sent("request_roll")
	assert_bool(asks.is_empty()).override_failure_message(
		"the online opponent was never asked to interfere:\n%s" % _log_from(start)).is_false()
	if asks.is_empty():
		_end_session()
		return
	assert_int(int(asks[0][2])).override_failure_message("the question went to the wrong peer").is_equal(GUEST_PEER)
	var rq: Dictionary = asks[0][1]
	# — the guest's machine (slot 2): the request opens ITS dialog, its player spends ONE token —
	_net.my_slot = 2
	(func() -> void: await _main._rpc_request_roll(rq, 1)).call()
	await _wait(func() -> bool: return _interference_card() != null)
	var card := _interference_card()
	assert_object(card).override_failure_message("the guest's machine showed no interference card").is_not_null()
	if card != null:
		card.resolve(1)
	await _wait(func() -> bool: return not _sent("roll_result").is_empty())
	var replies := _sent("roll_result")
	assert_bool(replies.is_empty()).override_failure_message("the guest's machine never answered").is_false()
	# — back on the caster's machine: the answer releases the cast —
	_net.my_slot = 1
	if not replies.is_empty():
		_main._rpc_roll_result(int(replies[0][1]["req"]), replies[0][1]["faces"])
	await _wait(func() -> bool: return done[0])
	var text := _log_from(start)
	assert_bool(done[0]).override_failure_message("the cast never resolved:\n%s" % text).is_true()
	assert_str(text).override_failure_message("the guest's token did not worsen the roll:\n%s" % text) \
		.contains("-1 interference")
	assert_int(witch.casts_current).override_failure_message("P2's token was not spent by P2's choice:\n%s" % text) \
		.is_equal(1)
	await E2EBoot.settle(get_tree())
	_end_session()   # inside the test: an unparented double alive at its end counts as an orphan


func test_an_online_cast_at_a_vacant_seat_resolves_without_interference(timeout := 120000) -> void:
	_fake_session(false)
	var units := _cast_setup()
	var start: int = _main.battle_log.entries().size()
	var done := [false]
	(func() -> void:
		await _main._run_human_cast(units[0], units[0], {"name": "Bolt", "threshold": 2}, [units[1]])
		done[0] = true).call()
	await _wait(func() -> bool: return done[0])
	var text := _log_from(start)
	assert_bool(done[0]).override_failure_message("the cast hung on an empty seat:\n%s" % text).is_true()
	assert_array(_sent("request_roll")).override_failure_message("a request went to nobody").is_empty()
	assert_str(text).override_failure_message("the empty seat was not named:\n%s" % text) \
		.contains("seat is empty — no interference")
	assert_int((units[2] as GameUnit).casts_current).is_equal(2)
	await E2EBoot.settle(get_tree())
	_end_session()


## P1 (Seer) casts at P2 (Raiders); P2 caster (Witch) is behind a Wall Guards blocker, so the
## Seer has LoS only to the Raiders but not the Witch — the game must log why nobody interferes.
func test_an_online_cast_with_the_sight_line_blocked_logs_why_nobody_interferes(timeout := 120000) -> void:
	_fake_session()
	var units := _cast_setup()
	_reg(1, "Wall Guards", -3.0)
	var start: int = _main.battle_log.entries().size()
	var done := [false]
	(func() -> void:
		await _main._run_human_cast(units[0], units[0], {"name": "Bolt", "threshold": 2}, [units[1]])
		done[0] = true).call()
	await _wait(func() -> bool: return done[0])
	var text := _log_from(start)
	assert_bool(done[0]).override_failure_message("the cast hung on a blocked sight line:\n%s" % text).is_true()
	assert_array(_sent("request_roll")).override_failure_message("a request went to the blocked caster:\n%s" % text).is_empty()
	assert_str(text).override_failure_message("no explanation why nobody interfered:\n%s" % text) \
		.contains("no caster of P2 within 18\" and line of sight — no interference")
	assert_int((units[2] as GameUnit).casts_current).is_equal(2)
	await E2EBoot.settle(get_tree())
	_end_session()


## P1 has only one caster and that caster has no tokens left — no second caster exists at all.
## The game stays silent: no "no boost" line, because there is nobody to boost with.
func test_control_a_lone_caster_without_tokens_logs_no_boost_line(timeout := 120000) -> void:
	_fake_session()
	var seer := _reg(1, "Seer", 0.0, ["Caster(2)"])
	seer.casts_current = 2
	var foe := _reg(2, "Raiders", 10.0)
	_main._ensure_solo_controller()
	var start: int = _main.battle_log.entries().size()
	var done := [false]
	(func() -> void:
		await _main._run_human_cast(seer, seer, {"name": "Bolt", "threshold": 2}, [foe])
		done[0] = true).call()
	await _wait(func() -> bool: return done[0])
	var text := _log_from(start)
	assert_bool(done[0]).override_failure_message("the cast hung:\n%s" % text).is_true()
	assert_str(text).override_failure_message("unexpected 'no boost' line:\n%s" % text) \
		.not_contains("no boost")
	await E2EBoot.settle(get_tree())
	_end_session()


## P1 (Seer) casts at P2 (Raiders); the only other P1 caster (Witch) stands with tokens
## but beyond 18" LoS from the Seer — the boost pool is 0 and the game must log why.
func test_a_cast_with_the_friendly_caster_out_of_sight_logs_why_nobody_boosts(timeout := 120000) -> void:
	_fake_session()
	var seer := _reg(1, "Seer", 0.0, ["Caster(2)"])
	seer.casts_current = 2
	var foe := _reg(2, "Raiders", 10.0)
	# Second P1 caster WITH tokens but 20" away — beyond 18" aura range
	var witch := _reg(1, "Witch", -20.0, ["Caster(2)"])
	witch.casts_current = 2
	_main._ensure_solo_controller()
	assert_object(_main.solo_controller).override_failure_message("fixture: no engine controller").is_not_null()
	var start: int = _main.battle_log.entries().size()
	var done := [false]
	(func() -> void:
		await _main._run_human_cast(seer, seer, {"name": "Bolt", "threshold": 2}, [foe])
		done[0] = true).call()
	await _wait(func() -> bool: return done[0])
	var text := _log_from(start)
	assert_bool(done[0]).override_failure_message("the cast hung:\n%s" % text).is_true()
	assert_str(text).override_failure_message("no 'no boost' explanation logged:\n%s" % text) \
		.contains("no caster of P1 within 18\" and line of sight — no boost")
	await E2EBoot.settle(get_tree())
	_end_session()
