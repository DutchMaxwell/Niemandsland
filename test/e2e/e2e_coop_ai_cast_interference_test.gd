extends GdUnitTestSuite
## Online co-op (#673): two humans (the host on slot 1, the guest on slot 2) against NACHTMAHR (slot 3).
## Every enemy caster within 18" of an AI cast may interfere (v3.5.1), and that choice belongs to the
## caster's OWNER. The AI's activation resolves on whichever machine's activation it answered, so the
## interference ask must reach the owning player's machine through the owner-request seam #1842 added
## (`request_roll` with a "spell" ask), never a dialog on the resolving machine for someone else's tokens.
## Real: scenes/main.tscn, _solo_resolve_one_cast, _rpc_request_roll / _rpc_roll_result and the real
## dialog card. The network side is the owner-roll suites' NetworkManager double (records every send);
## `my_slot` lets ONE main play both machines of the round trip.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const HOST_PEER := 1
const GUEST_PEER := 42
const AI_SLOT := 3

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
	_real_net = _main.network_manager


func after_test() -> void:
	_end_session()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A co-op room: the host (peer 1) on slot 1, the guest on slot 2, NACHTMAHR on slot 3 (nobody seated).
func _fake_session(my_slot: int) -> void:
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/network_manager.gd\"\nvar sent: Array = []\nvar my_slot := 1\n" \
		+ "func is_multiplayer_active() -> bool:\n\treturn true\n" \
		+ "func get_my_player_slot() -> int:\n\treturn my_slot\n" \
		+ "func _validate_rpc_ready(_context: String = \"\") -> bool:\n\treturn true\n" \
		+ "func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:\n" \
		+ "\tsent.append([type, payload, target_peer])\n\treturn true\n"
	assert_int(src.reload()).is_equal(OK)
	_net = src.new()
	_net.my_slot = my_slot
	_net.peer_to_slot = {HOST_PEER: 1, GUEST_PEER: 2}
	_net.player_names = {HOST_PEER: "Host", GUEST_PEER: "Guest"}
	_main.network_manager = _net
	_main.solo_ai_slots = {AI_SLOT: true}


func _end_session() -> void:
	if _main != null:
		_main.solo_ai_slots = {}
		_main.network_manager = _real_net
	if _net != null:
		_net.free()
		_net = null


func _reg(pid: int, unit_name: String, x_in: float, tokens: int = 0) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x_in * INCH, 0.0, 0.0)])
	u.unit_properties["special_rules"] = ["Caster(2)"] if tokens > 0 else []
	u.casts_current = tokens
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


## NACHTMAHR's Shaman casts a utility spell at `target`; the planner left the resist window open.
func _ai_cast(shaman: GameUnit, target: GameUnit, done: Array, base: int = AiSpell.CAST_BASE_TARGET) -> void:
	await _main._solo_resolve_one_cast({"caster": shaman, "caster_unit": shaman, "name": "Hex",
		"spell": {"name": "Hex", "threshold": 1, "effect": {}}, "targets": [target], "boost": 0,
		"interference": 0, "base_target": base, "threshold": 1, "interference_open": true})
	done[0] = true


## The host's machine resolves the AI cast; only the GUEST's Witch stands within 18". The guest is asked
## at its own machine, spends one token there, and the answer worsens the cast roll on the host. The cast's
## own base (3+, a casting modifier) travels with the ask, so both machines read the same roll.
func test_the_host_resolves_an_ai_cast_and_the_guest_is_asked_at_its_machine(timeout := 120000) -> void:
	_fake_session(1)
	var shaman := _reg(AI_SLOT, "Shaman", 0.0, 2)
	var squad := _reg(1, "Squad", 10.0)
	var witch := _reg(2, "Witch", -6.0, 2)
	_main._ensure_solo_controller()
	assert_object(_main.solo_controller).override_failure_message("fixture: no AI controller").is_not_null()
	var start: int = _main.battle_log.entries().size()
	var done := [false]
	_ai_cast(shaman, squad, done, 3)
	await _wait(func() -> bool: return done[0] or not _sent("request_roll").is_empty() or _interference_card() != null)
	assert_object(_interference_card()).override_failure_message(
		"the host's screen opened the interference dialog for the guest's tokens:\n%s" % _log_from(start)).is_null()
	var asks := _sent("request_roll")
	assert_bool(asks.is_empty()).override_failure_message(
		"the guest was never asked to interfere against the AI cast:\n%s" % _log_from(start)).is_false()
	if asks.is_empty():
		await _wait(func() -> bool: return done[0])
		_end_session()
		return
	assert_int(int(asks[0][2])).override_failure_message("the question went to the wrong peer").is_equal(GUEST_PEER)
	assert_str(_log_from(start)).override_failure_message("the routed ask left no log line:\n%s" % _log_from(start)) \
		.contains("Waiting for Guest — interference against Hex")
	var rq: Dictionary = asks[0][1]
	# — the guest's machine (slot 2): the request opens ITS dialog, its player spends ONE token —
	_net.my_slot = 2
	(func() -> void: await _main._rpc_request_roll(rq, HOST_PEER)).call()
	await _wait(func() -> bool: return _interference_card() != null)
	var card := _interference_card()
	assert_object(card).override_failure_message("the guest's machine showed no interference card").is_not_null()
	if card != null:
		card.resolve(1)
	await _wait(func() -> bool: return not _sent("roll_result").is_empty())
	var replies := _sent("roll_result")
	assert_bool(replies.is_empty()).override_failure_message("the guest's machine never answered").is_false()
	# — back on the host's machine: the answer releases the cast —
	_net.my_slot = 1
	if not replies.is_empty():
		_main._rpc_roll_result(int(replies[0][1]["req"]), replies[0][1]["faces"])
	await _wait(func() -> bool: return done[0])
	var text := _log_from(start)
	assert_bool(done[0]).override_failure_message("the cast never resolved:\n%s" % text).is_true()
	assert_str(text).override_failure_message("the guest's token did not worsen the roll:\n%s" % text) \
		.contains("Interference: Witch ×1 spends 1 token — the cast roll worsens to 4+")
	assert_str(text).override_failure_message("the host rolled at another target:\n%s" % text).contains("vs 4+")
	assert_int(witch.casts_current).override_failure_message("the guest's token was not spent:\n%s" % text).is_equal(1)
	await E2EBoot.settle(get_tree())
	_end_session()   # inside the test: an unparented double alive at its end counts as an orphan


## The guest's machine resolves the AI cast (it answered the guest's activation); only the HOST's Seer
## stands within 18". The guest's screen must not offer the host's tokens — the host is asked instead.
func test_the_guest_resolves_an_ai_cast_and_the_host_is_asked_at_its_machine(timeout := 120000) -> void:
	_fake_session(2)
	var shaman := _reg(AI_SLOT, "Shaman", 0.0, 2)
	var raiders := _reg(2, "Raiders", 10.0)
	var seer := _reg(1, "Seer", -6.0, 2)
	_main._ensure_solo_controller()
	assert_object(_main.solo_controller).override_failure_message("fixture: no AI controller").is_not_null()
	var start: int = _main.battle_log.entries().size()
	var done := [false]
	_ai_cast(shaman, raiders, done)
	await _wait(func() -> bool: return done[0] or not _sent("request_roll").is_empty() or _interference_card() != null)
	var stray := _interference_card()
	assert_object(stray).override_failure_message(
		"the guest's screen opened the interference dialog for the host's tokens:\n%s" % _log_from(start)).is_null()
	if stray != null:
		stray.resolve(0)
	var asks := _sent("request_roll")
	assert_bool(asks.is_empty()).override_failure_message(
		"the host was never asked to interfere against the AI cast:\n%s" % _log_from(start)).is_false()
	if not asks.is_empty():
		assert_int(int(asks[0][2])).override_failure_message("the question went to the wrong peer").is_equal(HOST_PEER)
		# — the host's machine answers "no interference" —
		_main._rpc_roll_result(int((asks[0][1] as Dictionary)["req"]), [0])
	await _wait(func() -> bool: return done[0])
	assert_bool(done[0]).override_failure_message("the cast never resolved:\n%s" % _log_from(start)).is_true()
	assert_int(seer.casts_current).override_failure_message("the host's tokens moved without the host").is_equal(2)
	await E2EBoot.settle(get_tree())
	_end_session()


## Regression guard: the resolving machine's OWN caster is asked right here, as before (no wire ask).
func test_the_resolving_players_own_caster_is_asked_locally(timeout := 120000) -> void:
	_fake_session(1)
	var shaman := _reg(AI_SLOT, "Shaman", 0.0, 2)
	var squad := _reg(1, "Squad", 10.0)
	var seer := _reg(1, "Seer", -6.0, 2)
	_main._ensure_solo_controller()
	var start: int = _main.battle_log.entries().size()
	var done := [false]
	_ai_cast(shaman, squad, done)
	await _wait(func() -> bool: return done[0] or _interference_card() != null)
	var card := _interference_card()
	assert_object(card).override_failure_message("the host's own caster was not asked:\n%s" % _log_from(start)).is_not_null()
	if card != null:
		card.resolve(1)
	await _wait(func() -> bool: return done[0])
	assert_bool(done[0]).is_true()
	assert_array(_sent("request_roll")).override_failure_message("a local ask went over the wire").is_empty()
	assert_int(seer.casts_current).is_equal(1)
	await E2EBoot.settle(get_tree())
	_end_session()
