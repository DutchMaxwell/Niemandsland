extends GdUnitTestSuite
## P4.D-24 (below the D-23 cases): the owner's #172 prompt answers the choice - a click PREVIEWS, the slot list is the
## answer, the core lands it.
## P4.D-23: the wound-allocation choice (`wound_alloc:<shooter>:<target>:<group>`) on the table - the switch and the owner
## routing, no prompt yet. The REAL core opens the choice where the volley's landing has one (a Tough(3) target, 3 wounds in
## a pool of 9); every die is supplied up front, so the only thing asked is the choice. Its OWNER is the target's owner:
## an AI owner and a human on this machine are answered automatic (no prompt exists yet), a human on another machine is
## asked over the owner-request path, its first answer applies once and a stale second one never overwrites it. The
## switch `NML_ONE_CORE_CHOICE_WOUND_ALLOC` was OFF by default (ON since P4.D-27, `=0` is the way back): OFF, nothing is probed, nobody is asked, the landing is the automatic one.
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


## The step API as the driver sees it (a recording double, for the cases that script the core's answers).
class FakeCore extends RefCounted:
	var answers: Array = []

	func step_activation(_h: int, _unit: String, _t: Array, _enforce: bool) -> Dictionary:
		if not answers.is_empty():
			return answers.pop_front()
		return {"step": "done", "state": 0, "lines": [], "landings": [], "delta": [], "handle": 7}

	func release(_h: int) -> void:
		pass


class FakeSolo extends "res://scripts/solo/solo_controller.gd":
	var fake_core: Object

	func _core_node_ready() -> Object:
		return fake_core


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


## The default is ON since P4.D-27 (the Takedown pick stays OFF); `NML_ONE_CORE_CHOICE_WOUND_ALLOC=0` or "off" is the way back.
func test_the_switch_is_on_by_default_and_the_environment_turns_it_off() -> void:
	var saved := OS.get_environment("NML_ONE_CORE_CHOICE_WOUND_ALLOC")
	OS.unset_environment("NML_ONE_CORE_CHOICE_WOUND_ALLOC")
	CoreActivation._choice_on = {}
	assert_bool(CoreActivation.choice_enabled("wound_alloc:a:b:0")).override_failure_message("the switch is not ON by default").is_true()
	assert_bool(CoreActivation.choice_enabled("takedown_model:a:b")).override_failure_message("the Takedown pick turned on too").is_false()
	for raw in ["0", "off", "OFF"]:
		OS.set_environment("NML_ONE_CORE_CHOICE_WOUND_ALLOC", raw)
		CoreActivation._choice_on = {}
		assert_bool(CoreActivation.choice_enabled("wound_alloc:a:b:0")).override_failure_message("'%s' did not turn it off" % raw).is_false()
	OS.set_environment("NML_ONE_CORE_CHOICE_WOUND_ALLOC", "1")
	CoreActivation._choice_on = {}
	assert_bool(CoreActivation.choice_enabled("wound_alloc:a:b:0")).is_true()
	if saved.is_empty():
		OS.unset_environment("NML_ONE_CORE_CHOICE_WOUND_ALLOC")
	else:
		OS.set_environment("NML_ONE_CORE_CHOICE_WOUND_ALLOC", saved)
	CoreActivation._choice_on = {}


## Switch OFF: the transcript is sent as it always was, nobody is asked, and the core lands its automatic order (the lead
## model takes the three wounds and dies).
func test_with_the_switch_off_the_landing_is_the_automatic_one(timeout := 120000) -> void:
	CoreActivation._choice_on = {"wound_alloc": false, "strike_back": false}   # every switch OFF (strike_back is default ON since E-25)
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


## An AI owner is answered automatic without a word on the wire or a prompt (a human on this machine is prompted: below).
func test_an_ai_owner_is_answered_automatic(timeout := 120000) -> void:
	_session({GUEST_PEER: 2})
	_main.solo_ai_slots = {2: true}   # seat 2 is NACHTMAHR's
	var sc := _scenario(2)
	var out := {}
	_start(sc, out)
	await _finish(sc, out)
	assert_array(_requests()).override_failure_message("an AI owner was asked over the wire").is_empty()
	assert_bool(_main._solo_model_pick.is_empty()).override_failure_message("a prompt opened for an AI owner").is_true()
	assert_array(_wounds(sc["target"])).is_equal([3, 3])


## The one test an answer passes: an option of the choice, or - the wound allocation only - a list of them.
func test_answer_fits_is_one_option_or_a_slot_list_for_the_wound_allocation() -> void:
	var options := ["slot:0", "slot:1", "slot:2"]
	assert_bool(CoreActivation.answer_fits("wound_alloc:a:b:0", options, "slot:2,slot:2,slot:1")).is_true()
	assert_bool(CoreActivation.answer_fits("wound_alloc:a:b:0", options, "slot:1")).is_true()
	for bad in ["", "b", "slot:3", "slot:0,slot:3", "slot:0,,slot:1"]:
		assert_bool(CoreActivation.answer_fits("wound_alloc:a:b:0", options, bad)).override_failure_message(bad).is_false()
	assert_bool(CoreActivation.answer_fits("takedown_model:a:b", options, "slot:1")).is_true()
	assert_bool(CoreActivation.answer_fits("takedown_model:a:b", options, "slot:0,slot:1")).override_failure_message("a list is no Takedown pick").is_false()


## ---- P4.D-24: the prompt answers the choice ----

## The owner's clicks, fed whenever the prompt waits: a model index, or -1 = right-click. `seen` gets the models' wounds at
## every feed - the state the prompt left behind before the NEXT click, i.e. what a preview must not have touched.
func _feed_clicks(target: GameUnit, clicks: Array, seen: Array) -> void:
	var timer := Timer.new()
	timer.wait_time = 0.05
	_main.add_child(timer)
	var queue := clicks.duplicate()
	timer.timeout.connect(func() -> void:
		if _main._solo_model_pick.is_empty() or queue.is_empty() or not (_main._solo_model_pick["outcome"] as Array).is_empty():
			return
		seen.append(target.models.map(func(m: ModelInstance) -> int: return m.wounds_current))
		var i := int(queue.pop_front())
		(_main._solo_model_pick["outcome"] as Array).append({} if i < 0 else {"unit": target, "index": i}))
	timer.start()


func _alive(target: GameUnit) -> Array:
	return target.models.map(func(m: ModelInstance) -> bool: return m.is_alive)


## A human on THIS machine owns the target: each click only previews (no wound while the prompt waits), the clicked models
## in order are the answer, and the core lands exactly those wounds (slot 2 twice, slot 1 once).
func test_a_local_owner_previews_each_click_and_the_core_lands_the_clicked_models(timeout := 120000) -> void:
	_session({GUEST_PEER: 2})
	var sc := _scenario(1)
	var target: GameUnit = sc["target"]
	var seen: Array = []
	_feed_clicks(target, [2, 2, 1, -1], seen)
	var out := {}
	_start(sc, out)
	await _finish(sc, out)
	assert_int(seen.size()).override_failure_message("the prompt did not take 3 clicks and a right-click: %s" % str(seen)).is_equal(4)
	for state in seen:
		assert_array(state).override_failure_message("a click wounded a model before the core landed it: %s" % str(seen)).is_equal([3, 3, 3])
	assert_array(_requests()).override_failure_message("a local owner was asked over the wire").is_empty()
	assert_array(_wounds(target)).override_failure_message("the clicked models did not take the wounds: %s" % str(_wounds(target))).is_equal([3, 2, 1])
	assert_array(_alive(target)).is_equal([true, true, true])
	assert_bool((sc["t"] as Array).any(func(e: Dictionary) -> bool:
		return str(e["t"]) == "choice" and str(e["option"]) == "slot:2,slot:2,slot:1")).is_true()


## A right-click ends the list: the clicked wounds land first, the core's order takes the rest (the wounded model dies).
func test_a_right_click_ends_the_list_and_the_core_lands_the_rest(timeout := 120000) -> void:
	_session({GUEST_PEER: 2})
	var sc := _scenario(1)
	var target: GameUnit = sc["target"]
	_feed_clicks(target, [2, 2, -1], [])
	var out := {}
	_start(sc, out)
	await _finish(sc, out)
	assert_array(_alive(target)).override_failure_message("the clicked model must take the wounds first").is_equal([true, true, false])
	assert_bool((sc["t"] as Array).any(func(e: Dictionary) -> bool:
		return str(e["t"]) == "choice" and str(e["option"]) == "slot:2,slot:2")).is_true()


## No click at all (right-click at once): no answer, the core's automatic order, as before this step.
func test_an_immediate_right_click_leaves_the_automatic_landing(timeout := 120000) -> void:
	_session({GUEST_PEER: 2})
	var sc := _scenario(1)
	_feed_clicks(sc["target"], [-1], [])
	var out := {}
	_start(sc, out)
	await _finish(sc, out)
	assert_array(_alive(sc["target"])).is_equal([false, true, true])
	assert_bool((sc["t"] as Array).any(func(e: Dictionary) -> bool: return str(e["t"]) == "choice")).is_false()


## A known wound count ends the prompt by itself, a click on a model the preview already took down is skipped (as the core
## skips a pick on a dead model), and nothing is wounded.
func test_a_counted_prompt_ends_itself_and_skips_a_previewed_dead_model(timeout := 120000) -> void:
	var wall: GameUnit = ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Wall", "models": 3, "x_in": 12.0,
		"tough": 3}, true), {})
	var seen: Array = []
	_feed_clicks(wall, [2, 2, 2, 2, 1], seen)   # the 4th click on slot 2 is skipped; 4 wounds are placed
	var picks: Array = []
	var left: int = await _main._solo_prompt_wound_allocation(wall, 4, 1, Callable(), "", picks)
	assert_int(left).is_equal(0)
	assert_array(picks).is_equal([2, 2, 2, 1])
	assert_array(_wounds(wall)).override_failure_message("a preview wounded a model").is_equal([3, 3, 3])
	assert_bool(_main._solo_model_pick.is_empty()).is_true()


## The owner's machine (another human's unit asked over `request_roll`) runs the prompt for the host's request and answers with
## the slot list; it wounds nothing itself - the host's core lands the wounds, this table sees them with the sync.
func test_the_owners_machine_answers_the_request_with_the_slot_list(timeout := 120000) -> void:
	_session({GUEST_PEER: 1})
	_net.my_slot = 2
	var wall: GameUnit = ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Wall", "models": 3, "x_in": 12.0,
		"tough": 3}, true), {})
	var rq := {"req": 5, "rs": "s", "unit": wall.unit_id, "ask": {"choice": {"id": "wound_alloc:e2e_p1_Gun:%s:0" % wall.unit_id,
		"options": ["slot:0", "slot:1", "slot:2"], "wounds": 3}}}
	var seen: Array = []
	_feed_clicks(wall, [2, 2, 1], seen)
	await _main._rpc_request_roll(rq, GUEST_PEER)
	var results := _net.sent.filter(func(f: Dictionary) -> bool: return str(f["t"]) == "roll_result")
	assert_int(results.size()).is_equal(1)
	assert_array((results[0]["p"] as Dictionary)["faces"]).is_equal(["slot:2,slot:2,slot:1"])
	assert_array(_wounds(wall)).override_failure_message("the owner's machine wounded its own model").is_equal([3, 3, 3])


## The driver counts the saves the defender failed and hands the count to the remote owner's prompt (the request carries it).
func test_the_remote_owner_is_told_how_many_saves_failed(timeout := 120000) -> void:
	_session({GUEST_PEER: 2})
	var shooter: GameUnit = ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Gun", "models": 3, "x_in": 0.0}, true), {})
	var wall: GameUnit = ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Wall", "models": 3, "x_in": 12.0,
		"tough": 3}, true), {})
	var core := FakeCore.new()
	core.answers = [
		{"step": "need_roll", "index": 0, "faces": 3, "kind": "defense", "count": 3, "target": 4, "owner": "Wall",
			"owner_key": wall.unit_id, "lines": [], "landings": []},
		{"step": "need_choice", "id": "wound_alloc:%s:%s:0" % [shooter.unit_id, wall.unit_id],
			"options": ["slot:0", "slot:1", "slot:2"], "owner": wall.unit_id}]
	var sc := auto_free(FakeSolo.new()) as SoloController
	sc.fake_core = core
	_main.solo_controller = sc
	var out := {}
	var run := func() -> void:
		out["r"] = await CoreActivation.drive(_main, 1, shooter, [{"t": "begin"}], false)
	run.call()
	await _until(func() -> bool: return _requests().size() >= 1)
	_main._rpc_roll_result(int((_requests()[0]["p"] as Dictionary)["req"]), [1, 2, 5])   # two saves fail, one is made
	await _until(func() -> bool: return _requests().size() >= 2)
	var ask: Dictionary = ((_requests()[1]["p"] as Dictionary)["ask"] as Dictionary).get("choice", {})
	assert_int(int(ask.get("wounds", -1))).override_failure_message("the choice ask: %s" % str(_requests())).is_equal(2)
	_main._rpc_roll_result(int((_requests()[1]["p"] as Dictionary)["req"]), ["slot:0"])
	await _until(func() -> bool: return out.has("r"))
	assert_bool(out.has("r")).is_true()


## The core's save rule, for the prompt's count only: a 6 saves, a 1 fails, the rest need the target.
func test_failed_saves_follow_the_cores_rule() -> void:
	assert_int(CoreActivation.failed_saves([1, 2, 3, 4, 5, 6], 4)).is_equal(3)
	assert_int(CoreActivation.failed_saves([1, 2, 6, 6], 2)).is_equal(1)   # a 1 fails even on a 2+ save
	assert_int(CoreActivation.failed_saves([5, 6, 6], 7)).is_equal(1)   # a 7+ save: only a 6 saves
