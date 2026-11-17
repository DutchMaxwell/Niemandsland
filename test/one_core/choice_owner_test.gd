extends GdUnitTestSuite
## P4.0-6: NeedChoice on the table and in MP. The step API's `need_choice` is answered by the choice's
## OWNER through the existing owner-request seam (a local machine answers here, another human's unit is
## asked over `request_roll`/`roll_result`), accepted once, and a timeout (or a vacant seat) leaves the
## core's automatic pick with ONE battle-log line. Every choice sits behind its own switch, OFF by
## default: with the switch off the driver sends exactly the transcript it always sent, so nothing a
## player sees changes. The core is a recording double here (the driver's contract, not the rules); the
## real extension is exercised by the step-5 binding suites.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const GUEST_PEER := 42

## The step API as the driver sees it: records every transcript, then answers a scripted result.
class FakeCore extends RefCounted:
	var steps: Array = []
	var answers: Array = []

	func step_activation(_h: int, _unit: String, t: Array, _enforce: bool) -> Dictionary:
		steps.append(t.duplicate(true))
		if not answers.is_empty():
			return answers.pop_front()
		return {"step": "done", "state": 0, "lines": [], "landings": [], "delta": [], "handle": 7}

	func release(_h: int) -> void:
		pass

## The controller the driver asks for its core; only `_core_node_ready` matters here.
class FakeSolo extends "res://scripts/solo/solo_controller.gd":
	var fake_core: Object

	func _core_node_ready() -> Object:
		return fake_core

## A real NetworkManager with only the transport swapped out; every send is recorded.
class FakeNet extends "res://scripts/network_manager.gd":
	var sent: Array = []
	var my_slot := 1

	func is_multiplayer_active() -> bool:
		return true

	func get_my_player_slot() -> int:
		return my_slot

	func _validate_rpc_ready(_context: String = "") -> bool:
		return true

	func slot_has_human_peer(_slot: int) -> bool:
		return false

	func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:
		sent.append({"t": type, "p": payload, "to": target_peer})
		return true

	func broadcast_log_event(_category: int, _text: String, _ai: bool = false, _detail: String = "") -> void:
		pass


var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _real_net: Node
var _net: FakeNet


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_real_net = _main.network_manager
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main.solo_ai_slots = {}
	_main._solo_batch = false
	CoreActivation._env = 1
	CoreActivation._choice_on = {"takedown_model": false, "wound_alloc": false}


func after_test() -> void:
	CoreActivation._choice_on = {}
	CoreActivation._env = -1
	if _main != null:
		_main.network_manager = _real_net
		_main.solo_controller = null
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A shooter with one Takedown weapon and a two-model target on the table.
func _pair(shooter_pid: int = 1) -> Array:
	var a := E2EBoot.make_unit(_main, shooter_pid, "Sniper", [Vector3(-0.3, 0.0, 0.0)])
	var b := E2EBoot.make_unit(_main, 1, "Target", [Vector3(0.3, 0.0, 0.0), Vector3(0.4, 0.0, 0.0)])
	_main.opr_army_manager.game_units[a.unit_id] = a
	_main.opr_army_manager.game_units[b.unit_id] = b
	var src := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Sniper"
	w.special_rules = ["Takedown"]
	src.weapons = [w]
	a.source_data = src
	return [a, b]


func _fake_core(core: FakeCore) -> void:
	var sc := auto_free(FakeSolo.new()) as SoloController
	sc.fake_core = core
	_main.solo_controller = sc


func _session(peers: Dictionary) -> void:
	_net = auto_free(FakeNet.new())
	_net.army_manager = _main.opr_army_manager
	_net.peer_to_slot = peers
	_main.network_manager = _net


func _results() -> Array:
	return _net.sent.filter(func(f: Dictionary) -> bool: return str(f["t"]) == "roll_result")


func _requests() -> Array:
	return _net.sent.filter(func(f: Dictionary) -> bool: return str(f["t"]) == "request_roll")


func _log_text(since: int = 0) -> String:
	var text := ""
	var entries: Array = _main.battle_log.entries()
	for i in range(since, entries.size()):
		text += str((entries[i] as Dictionary)["text"]) + "\n"
	return text


## Switch OFF (the default): the driver hands the core exactly the transcript it was given — no probe.
func test_switch_off_sends_no_choice_input() -> void:
	var core := FakeCore.new()
	_fake_core(core)
	var pair := _pair()
	var t: Array = [{"t": "begin"}, {"t": "intent", "kind": 0, "shoot": pair[1].unit_id}]
	var r: Dictionary = await CoreActivation.drive(_main, 1, pair[0], t, true)
	assert_str(str(r["step"])).is_equal("done")
	assert_int(core.steps.size()).is_equal(1)
	assert_bool((core.steps[0] as Array).any(func(e: Dictionary) -> bool: return str(e["t"]) == "choice")) \
		.override_failure_message("switch off must send no choice at all: %s" % str(core.steps[0])).is_false()
	await E2EBoot.settle(get_tree())


## The owner answers locally: the click pick names slot 1, and that option is what reaches the core.
func test_the_owner_answers_and_the_answer_reaches_the_core(timeout := 120000) -> void:
	CoreActivation._choice_on = {"takedown_model": true, "wound_alloc": false}
	var pair := _pair()
	var core := FakeCore.new()
	core.answers = [{"step": "need_choice", "id": "takedown_model:%s:%s" % [pair[0].unit_id, pair[1].unit_id],
		"options": ["slot:0", "slot:1"], "owner": pair[0].unit_id}]
	_fake_core(core)
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		if not _main._solo_model_pick.is_empty():
			(_main._solo_model_pick["outcome"] as Array).append({"unit": pair[1], "index": 1}))
	var t: Array = [{"t": "begin"}, {"t": "intent", "kind": 0, "shoot": pair[1].unit_id}]
	var r: Dictionary = await CoreActivation.drive(_main, 1, pair[0], t, false)
	assert_str(str(r["step"])).is_equal("done")
	assert_int(core.steps.size()).is_equal(2)
	assert_bool((core.steps[0] as Array).any(func(e: Dictionary) -> bool:
		return str(e["t"]) == "choice" and str(e["option"]) == "")).is_true()
	var last: Dictionary = (core.steps[1] as Array).back()
	assert_str(str(last["t"])).is_equal("choice")
	assert_str(str(last["option"])).override_failure_message("the owner's click must name slot 1").is_equal("slot:1")
	await E2EBoot.settle(get_tree())


## A request for a unit that is not ours is refused: no prompt, no answer on the wire.
func test_a_non_owner_does_not_answer(timeout := 120000) -> void:
	_session({GUEST_PEER: 2})
	var pair := _pair(2)
	var rq := {"req": 5, "rs": "s", "unit": pair[0].unit_id,
		"ask": {"choice": {"id": "takedown_model:x:y", "options": ["slot:0"]}}}
	await _main._rpc_request_roll(rq, GUEST_PEER)
	assert_array(_results()).override_failure_message("a foreign unit answered a choice").is_empty()
	assert_bool(_main._solo_model_pick.is_empty()).is_true()
	await E2EBoot.settle(get_tree())


## Nobody answers in time: the automatic pick stands, with exactly one battle-log line and no choice
## input in the next call.
func test_a_timeout_falls_back_to_the_automatic_pick_with_one_line(timeout := 120000) -> void:
	CoreActivation._choice_on = {"takedown_model": true, "wound_alloc": false}
	_session({GUEST_PEER: 2})
	_main._owner_roll_timeout_s = 0.2
	var pair := _pair(2)
	var core := FakeCore.new()
	core.answers = [{"step": "need_choice", "id": "takedown_model:%s:%s" % [pair[0].unit_id, pair[1].unit_id],
		"options": ["slot:0", "slot:1"], "owner": pair[0].unit_id}]
	_fake_core(core)
	var since: int = _main.battle_log.entries().size()
	var t: Array = [{"t": "begin"}, {"t": "intent", "kind": 0, "shoot": pair[1].unit_id}]
	var r: Dictionary = await CoreActivation.drive(_main, 1, pair[0], t, false)
	assert_str(str(r["step"])).is_equal("done")
	assert_int(_requests().size()).override_failure_message("the remote owner was asked first").is_equal(1)
	assert_bool((core.steps[1] as Array).any(func(e: Dictionary) -> bool: return str(e["t"]) == "choice")) \
		.override_failure_message("an unanswered choice must leave the automatic pick").is_false()
	var text := _log_text(since)
	assert_int(text.count("no answer to the Takedown model pick")).override_failure_message(text).is_equal(1)
	await E2EBoot.settle(get_tree())


## A duplicate request opens no second prompt; a re-sent one replays the stored answer.
func test_a_duplicate_answer_is_ignored(timeout := 120000) -> void:
	_session({})
	var pair := _pair()
	var rq := {"req": 9, "rs": "s", "unit": pair[0].unit_id,
		"ask": {"choice": {"id": "takedown_model:%s:%s" % [pair[0].unit_id, pair[1].unit_id],
			"options": ["slot:0", "slot:1"]}}}
	var call := func() -> void: await _main._rpc_request_roll(rq, GUEST_PEER)
	call.call()
	call.call()   # the duplicate must return on `_solo_owner_open`
	await _runner.simulate_frames(4)
	if not _main._solo_model_pick.is_empty():
		(_main._solo_model_pick["outcome"] as Array).append({"unit": pair[1], "index": 1})
	for _i in 20:
		if not _results().is_empty():
			break
		await get_tree().create_timer(0.1).timeout
	assert_int(_results().size()).override_failure_message("the pick was asked twice").is_equal(1)
	assert_array((_results()[0]["p"] as Dictionary)["faces"]).is_equal(["slot:1"])
	call.call()   # a re-sent request replays the stored answer, no prompt
	await _runner.simulate_frames(4)
	assert_int(_results().size()).override_failure_message("the stored answer was not replayed").is_equal(2)
	assert_array((_results()[1]["p"] as Dictionary)["faces"]).is_equal(["slot:1"])
	await E2EBoot.settle(get_tree())