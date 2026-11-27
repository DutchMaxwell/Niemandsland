extends GdUnitTestSuite
## E2E - MP, plan step 29e-2b (D-29 Q3 by the book: "then the opponent must place any other models from the unit within 1"
## of it"): in an online room the attacker's machine pushes a model of the GUEST's unit; the guest - its owner - places the
## rest on ITS machine and the answer comes back over the owner-request wire.
##
## The REAL main.tscn plays both machines of the round trip (`my_slot`, the shape of e2e_mp_reinforcement_owner_places_test):
## the host (slot 1) attacks and asks; the recorded `request_roll` is handed to the guest's handler (slot 2), whose owner
## drags and presses Enter; the recorded `roll_result` goes back to the host's waiting driver. The positions the core lands
## on the host must be the guest's drags to 1 mm. No answer within the bound: the core's D14 placer, and the line naming
## the timeout goes on the wire for the other table.
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const INCH := 0.0254
const HOST_PEER := 1
const GUEST_PEER := 42
const AI_SLOT := 3


## The REAL NetworkManager with its transport swapped out: every direct command and log line is recorded.
class OwnerNet extends "res://scripts/network_manager.gd":
	var sent: Array = []
	var logs: Array = []
	var my_slot := 1
	func is_multiplayer_active() -> bool:
		return true
	func get_my_player_slot() -> int:
		return my_slot
	func _validate_rpc_ready(_context: String = "") -> bool:
		return true
	func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:
		sent.append([type, payload, target_peer])
		return true
	func broadcast_log_event(_category: int, text: String, _ai: bool = false, _detail: String = "") -> void:
		logs.append(text)


var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _net: OwnerNet
var _real_net: Variant


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.fast(_main)
	SoloHarness.auto_saves(_main)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_real_net = _main.network_manager
	_net = OwnerNet.new()
	_net.peer_to_slot = {HOST_PEER: 1, GUEST_PEER: 2}
	_net.player_names = {HOST_PEER: "Host", GUEST_PEER: "Guest"}
	_main.network_manager = _net
	_main.solo_ai_slots = {AI_SLOT: true}


func after_test() -> void:
	CoreActivation.finish_replace_pick(false)
	CoreActivation.skip_push_pick()
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	_main.solo_ai_slots = {}
	_main.network_manager = _real_net
	_net.free()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(player: int, name: String, models: int, quality: int, weapon: Dictionary) -> GameUnit:
	var u := ParityTable._make_unit(_main, {"player": player, "name": name, "models": models, "x_in": 0.0, "z_step_in": 0.0,
		"quality": quality, "defense": 6, "tough": 1, "game_system": "gff", "faction_folder": "robot_legions", "rules": []}, weapon)
	for k in u.models.size():
		(u.models[k] as ModelInstance).node.global_position = Vector3((12.0 if player == 2 else 0.0) * INCH, 0, k * 1.5 * INCH)
		(u.models[k] as ModelInstance).node.set_meta("network_id", 900 + player * 10 + k)
		(u.models[k] as ModelInstance).node.set_meta("model_instance", u.models[k])
	return u


func _sent(type: String) -> Array:
	return _net.sent.filter(func(s: Array) -> bool: return str(s[0]) == type)


func _drag(n: Node3D, to: Vector3) -> void:
	var from := n.global_position
	n.global_position = to
	await SoloHarness.drop(_main, [{"node": n, "inches": from.distance_to(to) / INCH, "from_raw": from,
		"path": PackedVector2Array([Vector2(from.x, from.z), Vector2(to.x, to.z)])}])


## The host's attack (two hits kill two of the guest's four models, the morale test fails, the push die is a 5; the
## host drags survivor 1 1.9 in east). `answer` = what the guest's machine does with the request: "place" (drag survivor 2
## 0.5 in from the pushed model, Enter), "none" (no answer: the timeout). `wire` may rewrite the reply on its way back.
## Returns [drive answer, guest unit, the guest's dragged spot].
func _round_trip(answer: String, wire := Callable()) -> Array:
	var gunner := _unit(1, "Gunner", 1, 2, {"name": "Rifle", "range_in": 24, "attacks": 2, "count": 1, "rules": []})
	var squad := _unit(2, "Squad", 4, 6, {})
	CoreActivation._env = 1
	assert_bool(_main.core_activation_start(gunner)).override_failure_message("no Start").is_true()
	var s: Dictionary = CoreActivation._sessions[gunner.unit_id]
	var t: Array = (s["transcript"] as Array).duplicate()
	t.append_array([{"t": "intent", "kind": 0, "shoot": squad.unit_id}, {"t": "faces", "faces": [6, 6]}, {"t": "faces", "faces": [1, 1]},
		{"t": "faces", "faces": [1]}, {"t": "faces", "faces": [5]}])
	var done := [null]
	(func() -> void: done[0] = await CoreActivation.drive(_main, int(s["handle"]), gunner, t, false)).call()
	var spot := [null]
	var asked := false
	var until := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < until and done[0] == null:
		for c in _main.find_children("*", "PromptCard", false, false):
			var title := str((c as PromptCard).title)
			if title == "Push?":
				(c as PromptCard).resolve(true)
			elif title == "Place the rest":
				(c as PromptCard).resolve(true)
		if not CoreActivation.push_pick.is_empty():
			var n: Node3D = (squad.get_alive_models()[0] as ModelInstance).node
			await _drag(n, n.global_position + Vector3(1.9 * INCH, 0, 0))
		var asks := _sent("request_roll")
		if not asks.is_empty() and not asked and answer == "place":
			asked = true
			# The guest's machine: the request opens its placement; its owner drags and presses Enter.
			_net.my_slot = 2
			var rq: Dictionary = asks[0][1]
			(func() -> void: await _main._rpc_request_roll(rq, HOST_PEER)).call()
			var wait_until := Time.get_ticks_msec() + 10000
			while CoreActivation.replace_pick.is_empty() and Time.get_ticks_msec() < wait_until:
				for c in _main.find_children("*", "PromptCard", false, false):
					if str((c as PromptCard).title) == "Place the rest":
						(c as PromptCard).resolve(true)
				await get_tree().process_frame
			# On the guest's machine its own unit has no open activation: the drag lock must stand aside while it places.
			assert_bool(_main.core_drag_blocked(squad, true)).override_failure_message("the guest's drags are locked").is_false()
			var pushed: Vector3 = (squad.get_alive_models()[0] as ModelInstance).node.global_position
			var r := SoloController.model_base_radius_m(squad.get_alive_models()[0] as ModelInstance)
			spot[0] = pushed + Vector3(0, 0, 2 * r + 0.5 * INCH)
			await _drag((squad.get_alive_models()[1] as ModelInstance).node, spot[0])
			CoreActivation.finish_replace_pick(true)
			wait_until = Time.get_ticks_msec() + 10000
			while _sent("roll_result").is_empty() and Time.get_ticks_msec() < wait_until:
				await get_tree().process_frame
			# Back on the host: the guest's reply over the wire.
			_net.my_slot = 1
			var reply: Array = _sent("roll_result")
			assert_bool(reply.is_empty()).override_failure_message("the guest's machine never answered").is_false()
			if not reply.is_empty():
				var faces: Array = (reply[0][1] as Dictionary)["faces"]
				_main._rpc_roll_result(int(rq["req"]), wire.call(faces) if wire.is_valid() else faces)
		await get_tree().process_frame
	assert_object(done[0]).override_failure_message("the host's drive did not end").is_not_null()
	return [done[0] if done[0] != null else {}, squad, spot[0]]


@warning_ignore('unused_parameter')
func test_the_guest_places_and_the_host_lands_its_spots(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	var r := await _round_trip("place")
	assert_str(str((r[0] as Dictionary).get("step", ""))).override_failure_message("%s" % [r[0]]).is_equal("done")
	assert_int(_sent("request_roll").size()).override_failure_message("one question to the guest").is_equal(1)
	if _sent("request_roll").is_empty():
		return
	assert_int(int(_sent("request_roll")[0][2])).override_failure_message("the question went to the owner's peer").is_equal(GUEST_PEER)
	var landed: Vector3 = ((r[1] as GameUnit).get_alive_models()[1] as ModelInstance).node.global_position
	var dragged: Vector3 = r[2]
	assert_float(Vector2(landed.x, landed.z).distance_to(Vector2(dragged.x, dragged.z))) \
		.override_failure_message("the host lands the guest's spot to 1 mm: %s vs %s" % [landed, dragged]).is_less(0.001)


@warning_ignore('unused_parameter')
func test_no_answer_within_the_bound_is_the_d14_placer_named_on_the_wire(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	_main._owner_roll_timeout_s = 1.0
	var r := await _round_trip("none")
	assert_str(str((r[0] as Dictionary).get("step", ""))).is_equal("done")
	assert_bool(_net.logs.has("Push: no answer from Guest within 1 s - the core places the rest within 1 in")) \
		.override_failure_message("the timeout line goes to the other table: %s" % [_net.logs]).is_true()
	assert_bool(_net.logs.any(func(l: String) -> bool: return l.contains("model 2 placed within 1 in of it"))) \
		.override_failure_message("the D14 line goes too: %s" % [_net.logs]).is_true()
