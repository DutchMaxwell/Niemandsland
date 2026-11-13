extends GdUnitTestSuite
## E2E - MP (online co-op, #673): the OWNER places a returning Reinforcement copy ("the owner allocates", the project's
## standing principle for every choice that belongs to a unit).
##
## THE DEFECT. The round-start arrival beat runs on the machine that closed the round, which may be the OTHER human's
## machine. `_reinforcement_pick_spots` gave that machine the placement ghost for a copy it does not own (and the
## automatic spot headless), so the player who owns the unit never chose where it returns.
##
## The suite drives the REAL main.tscn as BOTH machines of the round trip (`my_slot`, the shape of
## e2e_coop_ai_cast_interference_test.gd): the guest (slot 2) closes the round and runs the beat for the host's (slot 1)
## unit. The owner-request seam must carry the question to the owner's machine and the chosen spots back. The ghost
## itself needs a window; headless the owner's machine answers with the automatic spots, which is what the real
## handler is asked to do here.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const HOST_PEER := 1
const GUEST_PEER := 42
const AI_SLOT := 3


## The REAL NetworkManager with its transport swapped out: every direct command is recorded; `my_slot` lets ONE main
## play both machines.
class OwnerNet extends "res://scripts/network_manager.gd":
	var sent: Array = []
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


var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _real_net: Node
var _net: OwnerNet


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main._solo_batch = true
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 2
	_real_net = _main.network_manager


func _end_session() -> void:
	if _main != null:
		_main.solo_ai_slots = {}
		_main.network_manager = _real_net
	if _net != null:
		_net.free()
		_net = null


func after_test() -> void:
	_end_session()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A co-op room: the host (peer 1) on slot 1, the guest (peer 42) on slot 2, NACHTMAHR on slot 3.
func _session(my_slot: int, seated: Dictionary = {HOST_PEER: 1, GUEST_PEER: 2}) -> void:
	_net = OwnerNet.new()
	_net.my_slot = my_slot
	_net.peer_to_slot = seated
	_net.player_names = {HOST_PEER: "Host", GUEST_PEER: "Guest"}
	_main.network_manager = _net
	_main.solo_ai_slots = {AI_SLOT: true}


func _sent(type: String) -> Array:
	var out: Array = []
	for s in _net.sent:
		if str((s as Array)[0]) == type:
			out.append(s)
	return out


func _wait(cond: Callable) -> void:
	for _i in 300:
		if cond.call():
			return
		await get_tree().process_frame


func _profile(unit_name: String, size: int) -> OPRApiClient.OPRUnit:
	var u := OPRApiClient.OPRUnit.new()
	u.name = unit_name
	u.size = size
	u.quality = 4
	u.defense = 4
	u.cost = 130
	u.base_size_round = 25
	u.base_width_mm = 25
	u.base_depth_mm = 25
	u.game_system = "gf"
	u.special_rules.append("Reinforcement")
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rusty Blade"
	w.attacks = 2
	u.weapons.append(w)
	return u


## A sacrificed Reinforcement carrier of `pid`, its copy due this round.
func _original(pid: int) -> GameUnit:
	var positions: Array = []
	for i in 3:
		positions.append(Vector3(float(i) * 1.2 * INCH, 0.0, 0.0))
	var u: GameUnit = _main.opr_army_manager.create_runtime_unit({
		"opr_unit": _profile("Clan Rats", 3), "faction_folder": "ratmen_clans"}, pid, positions, "spawn")
	assert_object(u).is_not_null()
	u.unit_properties["reinforcement_due_round"] = 2
	return u


func _copy_of(original: GameUnit) -> GameUnit:
	for g in _main.opr_army_manager.get_all_game_units():
		var gu := g as GameUnit
		if gu != null and gu != original and str(gu.unit_properties.get("origin", "")) == "reinforcement":
			return gu
	return null


func _arrive(original: GameUnit, done: Array) -> void:
	await _main._reinforcement_arrive_one(original, 2)
	done[0] = true


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The three base spots the OWNER picks: the far edge, away from where the closing machine would put the host's copy.
func _owners_choice() -> Array:
	return [0.30, 0.0, 0.55, 0.33, 0.0, 0.55, 0.36, 0.0, 0.55]


func test_the_closing_machine_asks_the_owner_where_the_copy_lands(timeout := 120000) -> void:
	_session(2)   # the guest closed the round and runs the beat for the host's unit
	var original := _original(1)
	var done := [false]
	_arrive(original, done)
	await _wait(func() -> bool: return done[0] or not _sent("request_roll").is_empty())
	var asks := _sent("request_roll")
	assert_bool(asks.is_empty()) \
		.override_failure_message("the closing machine placed the host's copy itself; its owner was never asked:\n%s" % _log_text()) \
		.is_false()
	if asks.is_empty():
		await _wait(func() -> bool: return done[0])
		_end_session()
		return
	assert_int(int(asks[0][2])).override_failure_message("the question went to the wrong peer").is_equal(HOST_PEER)
	assert_str(_log_text()).override_failure_message("the routed ask left no log line:\n%s" % _log_text()) \
		.contains("Waiting for Host — places the returning Clan Rats")
	assert_bool(done[0]).override_failure_message("the copy landed before its owner answered").is_false()
	assert_object(_copy_of(original)).override_failure_message("a copy stood on the table before its owner answered").is_null()

	# The owner's machine answers with its choice: the copy lands exactly there.
	_main._rpc_roll_result(int((asks[0][1] as Dictionary)["req"]), _owners_choice())
	await _wait(func() -> bool: return done[0])
	var copy := _copy_of(original)
	assert_bool(done[0]).override_failure_message("the arrival never finished:\n%s" % _log_text()).is_true()
	assert_object(copy).override_failure_message("the copy never came back:\n%s" % _log_text()).is_not_null()
	if copy != null:
		for i in 3:
			var p: Vector3 = (copy.models[i] as ModelInstance).node.global_position
			assert_float(p.x).override_failure_message("model %d is not where its owner put it: %s" % [i, str(p)]) \
				.is_equal_approx(float(_owners_choice()[3 * i]), 0.001)
			assert_float(p.z).is_equal_approx(float(_owners_choice()[3 * i + 2]), 0.001)
	await E2EBoot.settle(get_tree())
	_end_session()   # inside the test: an unparented double alive at its end counts as an orphan


## The owner's side: the request opens ITS placement (headless: its automatic search) and the spots go back.
func test_the_owners_machine_answers_with_its_own_spots(timeout := 120000) -> void:
	_session(1)   # the host's machine receives the guest's question
	var original := _original(1)
	var rq := {"req": 7, "rs": "t", "unit": original.unit_id, "kind": "place", "count": 1, "target": 0,   # count 1: a build without the branch rolls one die instead of crashing the red run
		"purpose": "Reinforcement placement", "ask": {"reinforce": [0.0125, 0.0125, 0.0125]}}
	(func() -> void: await _main._rpc_request_roll(rq, GUEST_PEER)).call()
	await _wait(func() -> bool: return not _sent("roll_result").is_empty())
	var replies := _sent("roll_result")
	assert_bool(replies.is_empty()).override_failure_message("the owner's machine never answered").is_false()
	if replies.is_empty():
		_end_session()
		return
	assert_int(int(replies[0][2])).is_equal(GUEST_PEER)
	var faces: Array = (replies[0][1] as Dictionary)["faces"]
	assert_int(faces.size()).override_failure_message("the answer is not three spots (x, y, z each): %s" % str(faces)).is_equal(9)
	if faces.size() != 9:
		_end_session()
		return   # read defensively: an out-of-bounds index takes gdUnit's -d run into the debugger
	for i in 3:
		assert_float(absf(float(faces[3 * i]))).override_failure_message("a spot outside the table: %s" % str(faces)).is_less(0.62)
	await E2EBoot.settle(get_tree())
	_end_session()   # inside the test: an unparented double alive at its end counts as an orphan


## A vacant seat cannot be asked: the copy lands on the automatic spots, at once.
func test_a_vacant_owner_seat_lands_the_copy_on_the_automatic_spots(timeout := 120000) -> void:
	_session(2, {GUEST_PEER: 2})
	var original := _original(1)
	var done := [false]
	_arrive(original, done)
	await _wait(func() -> bool: return done[0])
	assert_array(_sent("request_roll")).override_failure_message("a vacant seat was asked").is_empty()
	assert_object(_copy_of(original)).override_failure_message("the copy never came back").is_not_null()
	await E2EBoot.settle(get_tree())
	_end_session()   # inside the test: an unparented double alive at its end counts as an orphan


## An owner who does not answer must not stall the round for ever: the seam's bound, then the automatic spots.
func test_an_owner_who_never_answers_lands_the_copy_on_the_automatic_spots(timeout := 120000) -> void:
	_session(2)
	_main._owner_roll_timeout_s = 0.3
	var original := _original(1)
	var done := [false]
	_arrive(original, done)
	await _wait(func() -> bool: return done[0])
	assert_bool(done[0]).override_failure_message("the arrival waited for ever for its owner").is_true()
	assert_object(_copy_of(original)).override_failure_message("the copy never came back:\n%s" % _log_text()).is_not_null()
	await E2EBoot.settle(get_tree())
	_end_session()   # inside the test: an unparented double alive at its end counts as an orphan


## Counter-proofs: a unit the closing machine owns, and an offline game, are placed there without any question.
func test_a_unit_the_closing_machine_owns_is_not_asked_about(timeout := 120000) -> void:
	_session(1)   # the host closes the round and the unit is the host's
	var original := _original(1)
	var done := [false]
	_arrive(original, done)
	await _wait(func() -> bool: return done[0])
	assert_array(_sent("request_roll")).override_failure_message("the owner was asked about its own unit on its own machine").is_empty()
	assert_object(_copy_of(original)).is_not_null()
	await E2EBoot.settle(get_tree())
	_end_session()   # inside the test: an unparented double alive at its end counts as an orphan


func test_an_offline_game_places_the_copy_without_a_question(timeout := 120000) -> void:
	_main.solo_ai_slots = {2: true}
	var original := _original(1)
	await _main._reinforcement_arrive_one(original, 2)
	assert_object(_copy_of(original)).is_not_null()
	await E2EBoot.settle(get_tree())
	_end_session()   # inside the test: an unparented double alive at its end counts as an orphan
