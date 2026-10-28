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
		+ "\tsent.append([type, payload, target_peer])\n\treturn true\n" \
		+ "func broadcast_log_event(_category: int, _text: String, _ai: bool = false, _detail: String = \"\") -> void:\n" \
		+ "\tpass\n"
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


## The owner's answers on the double's wire (#1882 part 2: a replay must not roll again).
func _results() -> Array:
	var out: Array = []
	for s in _net.sent:
		if str((s as Array)[0]) == "roll_result":
			out.append(s)
	return out


## Visible cards whose title mentions `needle` (the save prompt names the defending seat).
func _cards(needle: String) -> Array:
	var out: Array = []
	for node in _main.find_children("*", "PromptCard", true, false):
		if (node as PromptCard).visible and str((node as PromptCard).title).to_lower().contains(needle):
			out.append(node)
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


## #1867: a pending owner request must end as soon as the owner's link is gone, instead of
## waiting out the 120 s bound in silence (maintainer test 5: the prompt stayed, no roll came).
var _req_result: Dictionary = {}
var _req_done := false


func _run_request(peer: int) -> void:
	_req_result = await _main._owner_request(peer, {"unit": "u1", "kind": "morale", "count": 1,
		"target": 4, "purpose": "morale test"})
	_req_done = true


func _started_request(peer: int) -> int:
	_main._owner_roll_timeout_s = 3.0   # the 120 s bound, shortened; the release must beat it
	_req_result = {}
	_req_done = false
	_run_request(peer)
	for _i in 4:
		await get_tree().process_frame
	var reqs: Array = _main._solo_remote_save_waiters.keys()
	assert_int(reqs.size()).override_failure_message("the request is pending").is_equal(1)
	return int(reqs[0])


func _wait_for_request(seconds: float = 0.5) -> void:
	for _i in int(seconds / 0.1):
		if _req_done:
			return
		await get_tree().create_timer(0.1).timeout


## Never leave the request coroutine running after the scene is gone (RED runs wait it out).
func _drain() -> void:
	await _wait_for_request(3.2)


func test_a_pending_request_ends_when_the_owner_leaves(timeout := 120000) -> void:
	assert_bool(_seam_exists()).is_true()
	if not _seam_exists():
		return
	_fake_session({1: 1, GUEST_PEER: 2}, {GUEST_PEER: "Guest"})
	var req := await _started_request(GUEST_PEER)
	_end_session()   # real net: _on_player_left needs a tree-bound MultiplayerAPI
	_main._on_player_left(GUEST_PEER)
	await _wait_for_request(0.5)
	assert_bool(_req_done).override_failure_message("released without waiting for the 3 s timeout").is_true()
	assert_bool(bool((_req_result).get("done", true))).is_false()
	assert_bool(_main._solo_remote_save_waiters.has(req)).is_false()
	_main._rpc_roll_result(req, [6])   # a late result for a released request is ignored
	await get_tree().process_frame
	assert_bool(_main._solo_remote_save_waiters.has(req)).is_false()
	assert_bool(bool((_req_result).get("done", true))).is_false()
	await _drain()


func test_a_failed_reconnect_releases_every_pending_request(timeout := 120000) -> void:
	assert_bool(_seam_exists()).is_true()
	if not _seam_exists():
		return
	_fake_session({1: 1, GUEST_PEER: 2}, {GUEST_PEER: "Guest"})
	var req := await _started_request(GUEST_PEER)
	_end_session()
	_main._on_relay_reconnect_failed("timed out")
	await _wait_for_request(0.5)
	assert_bool(_req_done).override_failure_message("released on a failed rejoin").is_true()
	assert_bool(_main._solo_remote_save_waiters.has(req)).is_false()
	assert_bool(bool((_req_result).get("done", true))).is_false()
	await _drain()


## #1882: every reused-id rejoin is reported as peer_disconnected + peer_connected in the SAME frame
## (relay_multiplayer_peer.gd _emit_peer_connected). A pending owner request must survive that flush
## and still take the returning owner's real answer; only a peer that stays away is a leave.
var _flush_result: Dictionary = {}
var _flush_done := false


func _run_flush_request(peer: int) -> void:
	_flush_result = await _main._owner_request(peer, {"unit": "u1", "kind": "morale", "count": 1,
		"target": 4, "purpose": "morale test"})
	_flush_done = true


func test_a_rejoin_flush_keeps_the_pending_request_and_takes_the_answer(timeout := 120000) -> void:
	assert_bool(_seam_exists()).is_true()
	if not _seam_exists():
		return
	_fake_session({1: 1, GUEST_PEER: 2}, {GUEST_PEER: "Guest"})
	_main._owner_roll_timeout_s = 5.0
	_run_flush_request(GUEST_PEER)
	for _i in 4:
		await get_tree().process_frame
	var reqs: Array = _main._solo_remote_save_waiters.keys()
	assert_int(reqs.size()).override_failure_message("the request is pending").is_equal(1)
	var req := int(reqs[0])
	# The flush: the relay re-adds the SAME id in the same frame (network_manager.connected_peers),
	# only the disconnect half reaches _on_player_left. The real manager is needed (its own
	# handlers walk the tree); no session runs, so setting the list is inert.
	_end_session()
	_main.network_manager.connected_peers = Array([GUEST_PEER], TYPE_INT, "", null)
	_main._on_player_left(GUEST_PEER)
	for _i in 5:
		await get_tree().process_frame
	assert_bool(_flush_done).override_failure_message(
		"a rejoin flush released the request (the returning owner never got to answer)").is_false()
	assert_bool(_main._solo_remote_save_waiters.has(req)).override_failure_message(
		"the waiter is gone").is_true()
	_main.network_manager.connected_peers.clear()
	_main._rpc_roll_result(req, [6, 3, 1])
	for _i in 20:
		if _flush_done:
			break
		await get_tree().create_timer(0.1).timeout
	assert_bool(_flush_done).is_true()
	assert_array(_flush_result.get("faces", [])).override_failure_message(
		"the returning owner's real faces").is_equal([6, 3, 1])
	assert_bool(bool(_flush_result.get("done", false))).is_true()


## #1882, second half: the next owner roll can land between the flush and the re-handshake, when the
## returning peer is connected but has no slot yet (_solo_peer_for_slot -> 0). A SEATED player must
## not be auto-rolled in that window; the roll waits for the slot, then asks the owner.
var _window_faces: Array = []
var _window_done := false


func _run_window_roll(unit: GameUnit) -> void:
	_window_faces = await _main._owner_roll(unit, 2, 4, "morale", "Morale test: Raiders (4+)",
		{"what": "morale test"})
	_window_done = true


func test_a_roll_in_the_rejoin_window_waits_for_the_returning_owner(timeout := 120000) -> void:
	assert_bool(_seam_exists()).is_true()
	if not _seam_exists():
		return
	# The guest is back (connected) but not re-slotted yet: exactly the re-handshake window.
	_fake_session({1: 1}, {GUEST_PEER: "Guest"})
	_main._owner_roll_timeout_s = 5.0
	_net.connected_peers = Array([GUEST_PEER], TYPE_INT, "", null)
	var raiders := _unit(2, "Raiders")
	_run_window_roll(raiders)
	for _i in 8:
		await get_tree().process_frame
	assert_bool(_window_done).override_failure_message(
		"the seated owner was auto-rolled during the re-handshake").is_false()
	assert_str(_purpose_shown()).not_contains("(owner absent — auto-rolled)")
	assert_int(_requests().size()).override_failure_message("nobody asked yet").is_equal(0)
	# The re-handshake lands: slot 2 is bound again -> the request goes to the owner.
	_net.peer_to_slot = {1: 1, GUEST_PEER: 2}
	for _i in 30:
		if _requests().size() > 0:
			break
		await get_tree().create_timer(0.1).timeout
	assert_int(_requests().size()).override_failure_message("the returning owner was asked").is_equal(1)
	if _requests().is_empty():
		_end_session()
		return
	var rq: Dictionary = _requests()[0][1]
	_main._on_network_command("roll_result", {"req": int(rq["req"]), "faces": [5, 2]}, GUEST_PEER)
	for _i in 30:
		if _window_done:
			break
		await get_tree().create_timer(0.1).timeout
	assert_bool(_window_done).is_true()
	assert_array(_window_faces).override_failure_message("the owner's faces").is_equal([5, 2])
	_end_session()


## #1882 part 2: the relay drops an answer whose target socket is gone (the host's own outage).
## After the rejoin the host re-sends the SAME request id; the owner must replay the stored faces
## at once — no second card, no new roll.
func _save_request(req: int, unit: GameUnit) -> Dictionary:
	return {"req": req, "unit": unit.unit_id, "kind": "defense", "count": 2, "target": 4,
		"purpose": "Defense save", "ask": {"weapon": "Rifles", "striker": "Raiders",
		"defense": 4, "ap": 0}}


func test_a_replayed_request_replays_the_stored_answer(timeout := 120000) -> void:
	assert_bool(_seam_exists()).is_true()
	if not _seam_exists():
		return
	_fake_session({1: 1, GUEST_PEER: 2}, {GUEST_PEER: "Host"})
	_main._solo_auto_saves = true
	var unit := _unit(1, "Rifles")
	var rq := _save_request(77, unit)
	_main._rpc_request_roll(rq, GUEST_PEER)
	for _i in 6:
		await get_tree().process_frame
	var first := _results()
	assert_int(first.size()).override_failure_message("the first answer is on the wire").is_equal(1)
	if first.is_empty():
		_end_session()
		return
	var faces: Array = (first[0] as Array)[1].get("faces", [])
	var dice_before: int = _main._dice_log_vbox.get_child_count()
	_main._rpc_request_roll(rq, GUEST_PEER)
	for _i in 6:
		await get_tree().process_frame
	var again := _results()
	assert_int(again.size()).override_failure_message(
		"the re-sent request must be answered from the stored result").is_equal(2)
	if again.size() > 1:
		assert_array((again[1] as Array)[1].get("faces", [])).override_failure_message(
			"the SAME faces, not a new roll").is_equal(faces)
	assert_int(_main._dice_log_vbox.get_child_count()).override_failure_message(
		"a replay must not roll again").is_equal(dice_before)
	_end_session()


## #1882 part 2 fix round: the bare request id is NOT unique across host sessions - a restarted
## host starts counting at 1 again. The owner keys its cache by the resolver's session token too, so
## an old session's dice are never replayed into a new game.
func test_a_new_host_session_with_a_reused_id_rolls_fresh(timeout := 120000) -> void:
	assert_bool(_seam_exists()).is_true()
	if not _seam_exists():
		return
	_fake_session({1: 1, GUEST_PEER: 2}, {GUEST_PEER: "Host"})
	_main._solo_auto_saves = true
	var unit := _unit(1, "Rifles")
	var old_rq := _save_request(77, unit)
	old_rq["rs"] = "a"
	_main._rpc_request_roll(old_rq, GUEST_PEER)
	for _i in 6:
		await get_tree().process_frame
	var first := _results()
	assert_int(first.size()).override_failure_message("the first session's answer").is_equal(1)
	var dice_before: int = _main._dice_log_vbox.get_child_count()
	var new_rq := _save_request(77, unit)
	new_rq["rs"] = "b"
	_main._rpc_request_roll(new_rq, GUEST_PEER)
	for _i in 6:
		await get_tree().process_frame
	assert_int(_results().size()).override_failure_message(
		"a new host session's request must be answered").is_equal(2)
	assert_int(_main._dice_log_vbox.get_child_count()).override_failure_message(
		"a new session must ROLL again, not replay the old session's dice").is_greater(dice_before)
	_end_session()


## A duplicate that arrives WHILE the first card is still open must not open a second card.
func test_a_duplicate_request_keeps_one_open_card(timeout := 120000) -> void:
	assert_bool(_seam_exists()).is_true()
	if not _seam_exists():
		return
	_fake_session({1: 1, GUEST_PEER: 2}, {GUEST_PEER: "Host"})
	_main._solo_auto_saves = false
	var rq := _save_request(88, _unit(1, "Rifles"))
	_main._rpc_request_roll(rq, GUEST_PEER)
	for _i in 4:
		await get_tree().process_frame
	assert_int(_cards("incoming fire").size()).override_failure_message(
		"the first card is open").is_equal(1)
	_main._rpc_request_roll(rq, GUEST_PEER)
	for _i in 4:
		await get_tree().process_frame
	assert_int(_cards("incoming fire").size()).override_failure_message(
		"a duplicate opened a second card").is_equal(1)
	var card: PromptCard = _cards("incoming fire")[0]
	card.resolve(true)
	for _i in 30:
		if not _results().is_empty():
			break
		await get_tree().create_timer(0.1).timeout
	assert_int(_results().size()).override_failure_message(
		"the first request still answers exactly once").is_equal(1)
	_end_session()


## #1887 part (1): after the host's rejoin the foe's peer is back but not re-slotted yet
## (connected, no seat in peer_to_slot). The interference question must wait through that window
## instead of declaring the SEATED guest's seat empty - same wait `_owner_roll` has had since #1882.
var _interf_result := -1
var _interf_done := false


func _run_interference(caster: GameUnit) -> void:
	_interf_result = await _main._solo_remote_interference(caster, caster, "Test Hex", 0, "", 2)
	_interf_done = true


## Geometry for the caster auras: a solo controller plus a Caster(1) on the foe slot within reach.
func _seed_interference_foe() -> GameUnit:
	_main.solo_ai_slots = {3: true}
	_main._ensure_solo_controller()
	var caster := _unit(1, "Spell Guard")
	var foe_caster := E2EBoot.make_unit(_main, 2, "Foe Witch", [Vector3(0.05, 0.0, 0.0)])
	foe_caster.unit_properties["special_rules"] = ["Caster(1)"]
	foe_caster.initialize_caster_points()
	_main.opr_army_manager.game_units[foe_caster.unit_id] = foe_caster
	return caster


func test_control_an_empty_seat_still_logs_empty(timeout := 120000) -> void:
	assert_bool(_main.has_method("_solo_remote_interference")).is_true()
	if not _main.has_method("_solo_remote_interference"):
		return
	_fake_session({1: 1}, {})
	var caster := _seed_interference_foe()
	var spent: int = await _main._solo_remote_interference(caster, caster, "Test Hex", 0, "", 2)
	assert_int(spent).override_failure_message("an empty seat spends nothing").is_equal(0)
	assert_str(_log_text()).override_failure_message(
		"nobody is reconnecting - the seat is empty at once").contains("seat is empty")
	assert_int(_requests().size()).override_failure_message("no request to a vacant seat").is_equal(0)
	_end_session()


func test_interference_waits_for_a_returning_owner(timeout := 120000) -> void:
	assert_bool(_main.has_method("_solo_remote_interference")).is_true()
	if not _main.has_method("_solo_remote_interference"):
		return
	# The guest is back (connected) but not re-slotted yet: exactly the re-handshake window.
	_fake_session({1: 1}, {GUEST_PEER: "Guest"})
	_main._owner_roll_timeout_s = 5.0
	_net.connected_peers = Array([GUEST_PEER], TYPE_INT, "", null)
	var caster := _seed_interference_foe()
	_run_interference(caster)
	for _i in 8:
		await get_tree().process_frame
	assert_bool(_interf_done).override_failure_message(
		"the seated guest was called an empty seat during the re-handshake").is_false()
	assert_str(_log_text()).override_failure_message(
		"a returning owner is not an empty seat").not_contains("seat is empty")
	assert_int(_requests().size()).override_failure_message("nobody asked yet").is_equal(0)
	# The re-handshake lands: slot 2 is bound again -> the question goes to the owner.
	_net.peer_to_slot = {1: 1, GUEST_PEER: 2}
	for _i in 40:
		if _requests().size() > 0:
			break
		await get_tree().create_timer(0.1).timeout
	assert_int(_requests().size()).override_failure_message("the returning owner was asked").is_equal(1)
	if _requests().is_empty():
		_end_session()
		return
	var sent: Array = _requests()[0]
	assert_int(int(sent[2])).override_failure_message("addressed to the owner's peer").is_equal(GUEST_PEER)
	var rq: Dictionary = sent[1]
	assert_str(str(rq["kind"])).is_equal("interference")
	_main._on_network_command("roll_result", {"req": int(rq["req"]), "faces": [1]}, GUEST_PEER)
	for _i in 40:
		if _interf_done:
			break
		await get_tree().create_timer(0.1).timeout
	assert_bool(_interf_done).is_true()
	assert_int(_interf_result).override_failure_message("the owner's one token").is_equal(1)
	assert_str(_log_text()).override_failure_message(
		"a returning owner is not an empty seat").not_contains("seat is empty")
	_end_session()
