extends GdUnitTestSuite
## RULES_AUTOMATION_PLAN step 0.1a — the owner-roll seam ("jeder selbst", maintainer 04.09.): a roll
## that belongs to a unit is rolled on its OWNER's tray. main._owner_roll(unit, count, target,
## roll_kind, purpose, ask) has three branches, pinned here over the real main.tscn:
##   1. local owner (solo / our own slot / an AI unit)  -> the local tray, nothing on the wire;
##   2. another human's unit                           -> `request_roll` to that peer, the faces come
##                                                        back as `roll_result`, waiting + rolled lines;
##   3. vacant seat, or no answer within the timeout   -> a visible auto-roll "(owner absent — auto-rolled)".
## The network side is a test double of NetworkManager (a real session would need a relay): it reports
## an active session with this client on slot 1 and records every send_command instead of sending it.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const GUEST_PEER := 42

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _real_net: Node
var _net: Node
var _seam_result: Array = []
var _seam_done := false


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main._solo_batch = true   # instant tray faces (the headless sweep path), same faces contract
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


func _fake_session(peer_to_slot: Dictionary, names: Dictionary) -> void:
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/network_manager.gd\"\nvar sent: Array = []\n" \
		+ "func is_multiplayer_active() -> bool:\n\treturn true\n" \
		+ "func get_my_player_slot() -> int:\n\treturn 1\n" \
		+ "func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:\n" \
		+ "\tsent.append([type, payload, target_peer])\n\treturn true\n"
	assert_int(src.reload()).is_equal(OK)
	_net = src.new()
	_net.peer_to_slot = peer_to_slot
	_net.player_names = names
	_main.network_manager = _net


## The roll requests on the double's wire (every tray roll ALSO mirrors itself to the peers through
## send_command, so the raw count is not the request count).
func _requests() -> Array:
	var out: Array = []
	for s in _net.sent:
		if str((s as Array)[0]) == "request_roll":
			out.append(s)
	return out


## The tray's visible purpose line (community #170) — it stays up while the dice lie there.
func _purpose_shown() -> String:
	return str(_main.roll_purpose_label.text) if _main.roll_purpose_label != null else ""


func _end_session() -> void:
	_main.network_manager = _real_net
	_net.free()
	_net = null


func _unit(pid: int, unit_name: String) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3.ZERO])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _run_seam(u: GameUnit) -> void:
	_seam_result = await _main._owner_roll(u, 2, 4, "morale", "Morale test: Raiders (4+)", {"what": "morale test"})
	_seam_done = true


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _seam_exists() -> bool:
	return _main.has_method("_owner_roll")


func test_a_local_owner_rolls_on_the_local_tray(timeout := 120000) -> void:
	assert_bool(_seam_exists()).override_failure_message("0.1a — main has no _owner_roll seam").is_true()
	if not _seam_exists():
		return
	var faces: Array = await _main._owner_roll(_unit(1, "Rifles"), 3, 4, "morale", "Morale test: Rifles (4+)")
	assert_int(faces.size()).override_failure_message("solo: the local tray rolls the 3 dice").is_equal(3)


func test_another_humans_unit_is_rolled_by_its_owner(timeout := 120000) -> void:
	assert_bool(_seam_exists()).override_failure_message("0.1a — main has no _owner_roll seam").is_true()
	if not _seam_exists():
		return
	_fake_session({1: 1, GUEST_PEER: 2}, {GUEST_PEER: "Guest"})
	var raiders := _unit(2, "Raiders")
	_run_seam(raiders)   # suspends on the reply wait
	await _runner.simulate_frames(2)
	assert_int(_requests().size()).override_failure_message("exactly one request to the owner").is_equal(1)
	var sent: Array = _requests()[0]
	assert_str(str(sent[0])).is_equal("request_roll")
	assert_int(int(sent[2])).override_failure_message("addressed to the owner's peer").is_equal(GUEST_PEER)
	var rq: Dictionary = sent[1]
	assert_str(str(rq["unit"])).is_equal(raiders.unit_id)
	assert_str(str(rq["kind"])).is_equal("morale")
	assert_int(int(rq["count"])).is_equal(2)
	assert_int(int(rq["target"])).is_equal(4)
	assert_bool(_seam_done).override_failure_message("the resolver must WAIT for the owner's faces").is_false()
	_main._on_network_command("roll_result", {"req": int(rq["req"]), "faces": [6, 1]}, GUEST_PEER)
	for _i in 20:
		if _seam_done:
			break
		await get_tree().create_timer(0.1).timeout
	assert_bool(_seam_done).is_true()
	assert_array(_seam_result).override_failure_message("the owner's faces, not a local roll").is_equal([6, 1])
	assert_str(_log_text()).contains("Waiting for Guest — morale test")
	assert_str(_log_text()).contains("Guest rolled their morale test")
	_end_session()


func test_a_vacant_seat_is_auto_rolled_visibly(timeout := 120000) -> void:
	assert_bool(_seam_exists()).override_failure_message("0.1a — main has no _owner_roll seam").is_true()
	if not _seam_exists():
		return
	# Slot 2 is a human seat (not designated for NACHTMAHR) with nobody on it: no peer to ask.
	_fake_session({1: 1}, {})
	_main.solo_ai_slots = {}
	var faces: Array = await _main._owner_roll(_unit(2, "Raiders"), 2, 4, "morale", "Morale test: Raiders (4+)",
		{"what": "morale test"})
	assert_int(faces.size()).is_equal(2)
	assert_int(_requests().size()).override_failure_message("nobody to ask — no request on the wire").is_equal(0)
	assert_str(_purpose_shown()).contains("(owner absent — auto-rolled)")
	assert_str(_log_text()).contains("Waiting for player 2 — morale test")
	_end_session()


func test_an_owner_who_never_answers_is_auto_rolled_after_the_timeout(timeout := 120000) -> void:
	assert_bool(_seam_exists()).override_failure_message("0.1a — main has no _owner_roll seam").is_true()
	if not _seam_exists():
		return
	_fake_session({1: 1, GUEST_PEER: 2}, {GUEST_PEER: "Guest"})
	_main._owner_roll_timeout_s = 0.3   # the 120 s bound, shortened for the test
	var faces: Array = await _main._owner_roll(_unit(2, "Raiders"), 2, 4, "morale", "Morale test: Raiders (4+)",
		{"what": "morale test"})
	assert_int(faces.size()).is_equal(2)
	assert_int(_requests().size()).override_failure_message("the owner WAS asked first").is_equal(1)
	assert_str(_purpose_shown()).contains("(owner absent — auto-rolled)")
	assert_str(_log_text()).not_contains("Guest rolled their morale test")
	_end_session()
