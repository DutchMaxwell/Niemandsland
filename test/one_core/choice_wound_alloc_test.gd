extends GdUnitTestSuite
## P4.D-23: the wound-allocation choice (`wound_alloc:<shooter>:<target>:<group>`) on the table - the switch and the owner
## routing, no prompt yet. The REAL core opens the choice where the volley's landing has one (a Tough(3) target, 3 wounds in
## a pool of 9); every die is supplied up front, so the only thing asked is the choice. Its OWNER is the target's owner:
## an AI owner and a human on this machine are answered automatic (no prompt exists yet), a human on another machine is
## asked over the owner-request path, its first answer applies once and a stale second one never overwrites it. The
## switch `NML_ONE_CORE_CHOICE_WOUND_ALLOC` is OFF by default: nothing is probed, nobody is asked, the landing is today's.
## Constructed: the units (ParityTable) and the peer (a recording NetworkManager whose owner this test plays).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const GUEST_PEER := 42
const ALLOC := "slot:2,slot:2,slot:1"
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}


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

	func broadcast_model_wounds(_m: Variant) -> void:
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
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = false
	_main._solo_fast = true
	_main._solo_auto_saves = true
	CoreActivation._env = 1
	CoreActivation._choice_on = {"wound_alloc": true}


func after_test() -> void:
	CoreActivation._choice_on = {}
	CoreActivation._env = -1
	if _main != null:
		CoreActivation.reset_all(_main)
		_main.network_manager = _real_net
		_main.solo_ai_slots = {}
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Seat 1's shooter (3 Rifles, 3 attacks) at 12" from seat `seat`'s three Tough(3) models; the transcript carries every die:
## the attacks hit (6), the saves fail (1), a morale die (if the core asks) fails (1). The choice is not probed here.
func _scenario(seat: int) -> Dictionary:
	var shooter: GameUnit = ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Gun", "models": 3, "x_in": 0.0}, true),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 3, "rules": []})
	var target: GameUnit = ParityTable._make_unit(_main, SIDE.merged({"player": seat, "name": "Wall", "models": 3,
		"x_in": 12.0, "tough": 3}, true), {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 3, "rules": []})
	var core: Object = (_main.solo_controller as SoloController)._core_node_ready()
	var h: int = CoreActivation.capture(_main)
	assert_int(h).override_failure_message("no core capture").is_greater(0)
	var t: Array = [{"t": "begin"}, {"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": target.unit_id}]
	var r: Dictionary = core.step_activation(h, shooter.unit_id, t, false)
	while str(r["step"]) == "need_roll" and t.size() < 16:
		t.append({"t": "faces", "faces": range(int(r["faces"])).map(func(_i: int) -> int: return 6 if str(r["kind"]) == "attack" else 1)})
		r = core.step_activation(h, shooter.unit_id, t, false)
	assert_str(str(r["step"])).override_failure_message("the supplied dice must end the volley: %s" % str(r)).is_equal("done")
	core.release(int(r.get("handle", 0)))
	return {"h": h, "shooter": shooter, "target": target, "t": t, "core": core}


func _session(peers: Dictionary) -> void:
	_net = auto_free(FakeNet.new())
	_net.army_manager = _main.opr_army_manager
	_net.peer_to_slot = peers
	_main.network_manager = _net
	_main.solo_ai_slots = {}


func _requests() -> Array:
	return _net.sent.filter(func(f: Dictionary) -> bool: return str(f["t"]) == "request_roll") if _net != null else []


func _wounds(target: GameUnit) -> Array:
	return target.get_alive_models().map(func(m: ModelInstance) -> int: return m.wounds_current)


func _log_text(since: int) -> String:
	var text := ""
	var entries: Array = _main.battle_log.entries()
	for i in range(since, entries.size()):
		text += str((entries[i] as Dictionary)["text"]) + "\n"
	return text


## Starts the activation without waiting for it: `out["r"]` is set when it ends.
func _start(sc: Dictionary, out: Dictionary) -> void:
	var run := func() -> void:
		out["r"] = await CoreActivation.drive(_main, int(sc["h"]), sc["shooter"], sc["t"], false)
	run.call()


func _until(cond: Callable, seconds := 20.0) -> void:
	var waited := 0.0
	while not cond.call() and waited < seconds:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05


func _finish(sc: Dictionary, out: Dictionary) -> void:
	await _until(func() -> bool: return out.has("r"))
	assert_bool(out.has("r")).override_failure_message("the activation never ended").is_true()
	if not out.has("r"):
		return
	assert_str(str((out["r"] as Dictionary)["step"])).override_failure_message(str(out["r"])).is_equal("done")
	(sc["core"] as Object).release(int((out["r"] as Dictionary).get("handle", 0)))
	await E2EBoot.settle(get_tree())


func _frames_asking_for_the_choice() -> Array:
	return _requests().filter(func(f: Dictionary) -> bool:
		var ask: Dictionary = (f["p"] as Dictionary).get("ask", {})
		return ask.has("choice") and str((ask["choice"] as Dictionary)["id"]).begins_with("wound_alloc:"))


## OFF is the default: with no environment and no test override the switch reads false, the transcript is sent as it
## always was, nobody is asked, and the core lands its automatic order (the lead model takes the three wounds and dies).
func test_the_switch_is_off_by_default_and_the_landing_is_the_automatic_one(timeout := 120000) -> void:
	CoreActivation._choice_on = {}
	assert_bool(OS.has_environment("NML_ONE_CORE_CHOICE_WOUND_ALLOC")).override_failure_message("the environment sets the switch").is_false()
	assert_bool(CoreActivation.choice_enabled("wound_alloc:a:b:0")).is_false()
	assert_bool(CoreActivation.any_choice_enabled()).is_false()
	_session({GUEST_PEER: 2})
	var sc := _scenario(2)
	assert_array(CoreActivation.pending_choices(_main, sc["shooter"], sc["t"])).is_empty()
	var out := {}
	_start(sc, out)
	await _finish(sc, out)
	assert_array(_frames_asking_for_the_choice()).override_failure_message("a switch that is off asked the owner").is_empty()
	assert_array(_wounds(sc["target"])).override_failure_message("the automatic landing changed: %s" % str(_wounds(sc["target"]))).is_equal([3, 3])


## ON: the probe names the volley's one group; the remote owner is asked - not the host - and its list is what lands.
func test_the_remote_owner_is_asked_and_its_answer_lands_once(timeout := 120000) -> void:
	_session({GUEST_PEER: 2})
	var sc := _scenario(2)
	var shooter: GameUnit = sc["shooter"]
	var target: GameUnit = sc["target"]
	assert_array(CoreActivation.pending_choices(_main, shooter, sc["t"])) \
		.is_equal(["wound_alloc:%s:%s:0" % [shooter.unit_id, target.unit_id]])
	var out := {}
	_start(sc, out)
	await _until(func() -> bool: return not _requests().is_empty() or out.has("r"))
	var asked := _frames_asking_for_the_choice()
	assert_int(asked.size()).override_failure_message("the owner was not asked exactly once: %s" % str(_net.sent)).is_equal(1)
	if asked.is_empty():
		return
	assert_int(int(asked[0]["to"])).override_failure_message("the host answered for a remote owner").is_equal(GUEST_PEER)
	assert_str(str((asked[0]["p"] as Dictionary)["unit"])).is_equal(target.unit_id)
	assert_array(((asked[0]["p"] as Dictionary)["ask"]["choice"] as Dictionary)["options"]).is_equal(["slot:0", "slot:1", "slot:2"])
	assert_bool(_main._solo_model_pick.is_empty()).override_failure_message("the host opened a prompt").is_true()
	var req := int((asked[0]["p"] as Dictionary)["req"])
	_main._rpc_roll_result(req, [ALLOC])
	_main._rpc_roll_result(req, ["slot:0,slot:0,slot:0"])   # a stale second answer: refused, the first stands
	await _finish(sc, out)
	assert_array(_wounds(target)).override_failure_message("the owner's list did not land: %s" % str(_wounds(target))).is_equal([3, 2, 1])
	assert_int(_frames_asking_for_the_choice().size()).override_failure_message("the choice was asked twice").is_equal(1)
	assert_bool((sc["t"] as Array).any(func(e: Dictionary) -> bool:
		return str(e["t"]) == "choice" and str(e["option"]) == ALLOC)).override_failure_message("the answer is not in the transcript").is_true()


## An answer that is not a list of the core's slots is no answer: the automatic landing stands. The core would refuse it.
func test_an_answer_outside_the_options_is_dropped_and_the_automatic_landing_stands(timeout := 120000) -> void:
	_session({GUEST_PEER: 2})
	var sc := _scenario(2)
	var out := {}
	_start(sc, out)
	await _until(func() -> bool: return not _requests().is_empty() or out.has("r"))
	assert_int(_requests().size()).override_failure_message("the owner was not asked").is_equal(1)
	if _requests().is_empty():
		return
	_main._rpc_roll_result(int((_requests()[0]["p"] as Dictionary)["req"]), ["slot:2,slot:9"])
	await _finish(sc, out)
	assert_array(_wounds(sc["target"])).is_equal([3, 3])
	assert_bool((sc["t"] as Array).any(func(e: Dictionary) -> bool: return str(e["t"]) == "choice")).is_false()


## Nobody answers in time: the automatic landing, with exactly one battle-log line.
func test_a_silent_owner_leaves_the_automatic_landing_with_one_line(timeout := 120000) -> void:
	_session({GUEST_PEER: 2})
	_main._owner_roll_timeout_s = 0.2
	var sc := _scenario(2)
	var since: int = _main.battle_log.entries().size()
	var out := {}
	_start(sc, out)
	await _finish(sc, out)
	assert_int(_frames_asking_for_the_choice().size()).is_equal(1)
	assert_array(_wounds(sc["target"])).is_equal([3, 3])
	var text := _log_text(since)
	assert_int(text.count("no answer to the wound allocation")).override_failure_message(text).is_equal(1)


## An AI owner and a human on THIS machine are answered automatic without a word on the wire or a prompt.
func test_an_ai_owner_and_a_local_human_are_answered_automatic(timeout := 120000) -> void:
	_session({GUEST_PEER: 2})
	_main.solo_ai_slots = {2: true}   # seat 2 is NACHTMAHR's
	var sc := _scenario(2)
	var out := {}
	_start(sc, out)
	await _finish(sc, out)
	assert_array(_requests()).override_failure_message("an AI owner was asked over the wire").is_empty()
	assert_array(_wounds(sc["target"])).is_equal([3, 3])
	CoreActivation.reset_all(_main)
	_main.solo_ai_slots = {}
	_net.sent.clear()
	var mine := _scenario(1)   # a human owner on this machine: the prompt arrives with P4.D-24
	var out2 := {}
	_start(mine, out2)
	await _finish(mine, out2)
	assert_array(_requests()).override_failure_message("the local owner was asked over the wire").is_empty()
	assert_bool(_main._solo_model_pick.is_empty()).override_failure_message("a prompt opened before it exists").is_true()
	assert_array(_wounds(mine["target"])).is_equal([3, 3])


## The one test an answer passes: an option of the choice, or - the wound allocation only - a list of them.
func test_answer_fits_is_one_option_or_a_slot_list_for_the_wound_allocation() -> void:
	var options := ["slot:0", "slot:1", "slot:2"]
	assert_bool(CoreActivation.answer_fits("wound_alloc:a:b:0", options, "slot:2,slot:2,slot:1")).is_true()
	assert_bool(CoreActivation.answer_fits("wound_alloc:a:b:0", options, "slot:1")).is_true()
	for bad in ["", "b", "slot:3", "slot:0,slot:3", "slot:0,,slot:1"]:
		assert_bool(CoreActivation.answer_fits("wound_alloc:a:b:0", options, bad)).override_failure_message(bad).is_false()
	assert_bool(CoreActivation.answer_fits("takedown_model:a:b", options, "slot:1")).is_true()
	assert_bool(CoreActivation.answer_fits("takedown_model:a:b", options, "slot:0,slot:1")).override_failure_message("a list is no Takedown pick").is_false()
