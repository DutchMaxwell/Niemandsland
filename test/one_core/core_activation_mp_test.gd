extends GdUnitTestSuite
## One-core P3 steps 50-52 (N6 b): the digest check between two tables after an activation - the sender (50), the receiver
## (51) and the correction (52). Real: the main scene, its NetworkManager class with only the transport swapped out (every
## frame - the former @rpc calls and the command types alike - lands in ONE ordered list), the NmlCore extension.

const ParityTable := preload("res://test/parity/parity_table.gd")
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")


## The REAL NetworkManager with its transport swapped out: `send_command` records instead of sending, so a
## `broadcast_*` (through `_remote_call`) and a command type keep their send order in `wire`.
class WireNet extends "res://scripts/network_manager.gd":
	var active := true
	var wire: Array = []
	func is_multiplayer_active() -> bool:
		return active
	func _validate_rpc_ready(_context: String = "") -> bool:
		return active
	func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:
		wire.append({"t": type, "p": payload, "to": target_peer})
		return true
	func slot_has_human_peer(_slot: int) -> bool:
		return false
	func get_my_peer_id() -> int:
		return 1
	func get_my_player_slot() -> int:
		return 1


var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _real_net: Node
var _net: WireNet


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
	_main._solo_batch = true
	CoreActivation._env = 1


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	if _main != null:
		_main.network_manager = _real_net
		_main.radial_menu_controller.network_manager = _real_net
	_net = null
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## An agreed Automatic online room, seat 1 on turn (`room` false: the same table, no session - solo or hotseat);
## `seats` = the AI seats.
func _room(room := true, level := RulesAutomation.Level.AUTOMATIC, seats := {}) -> void:
	_main.opr_army_manager.rules_automation = level
	_main.solo_ai_slots = seats
	_net = auto_free(WireNet.new())
	_net.active = room
	_net.army_manager = _main.opr_army_manager
	_main.network_manager = _net
	_main.radial_menu_controller.network_manager = _net   # the activation fact goes out through the radial's own handle
	_main._ensure_solo_controller()
	_main._apply_turn_token(1)


## A unit of `pid` with two models (model_index 0, 1) and a plain rifle; `rules` makes it not plain.
func _plain(pid: int, uname: String, x_in: float, rules: Array = []) -> GameUnit:
	var u := ParityTable._make_unit(_main, {"player": pid, "name": uname, "models": 2, "x_in": x_in, "z_step_in": 1.2,
		"quality": 4, "defense": 4, "tough": 1, "game_system": "gf", "faction_folder": "robot_legions", "rules": rules},
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 2, "rules": []})
	for i in u.models.size():
		(u.models[i] as ModelInstance).model_index = i
		(u.models[i] as ModelInstance).node.set_meta("network_id", 900 + 10 * pid + _main.opr_army_manager.game_units.size() * 2 + i)
	return u


## The wire's frame names in send order (a former @rpc call by its handler name).
func _names() -> Array:
	return _net.wire.map(func(f: Dictionary) -> String: return str(f["p"]["m"]) if str(f["t"]) == "rpc" else str(f["t"]))


func _frames(type: String) -> Array:
	return _net.wire.filter(func(f: Dictionary) -> bool: return str(f["t"]) == type)


## Activate (Start) and Activate again (End): the card's door, both presses.
func _start_and_end(u: GameUnit) -> void:
	await _main.radial_menu_controller.card_toggle_activation(u)
	await _main.radial_menu_controller.card_toggle_activation(u)


## ---- Step 29 fix: an agreed online room has no solo controller before its first Activate ----

## The room as the agreement leaves it (`_apply_rules_automatic_agreed`: Automatic, no AI seat) - and nobody builds the
## solo controller (the other cases' `_room` does, as an attack or a round end would). The first Activate must still
## open a live session, and the unit's drag must lift.
func test_the_first_activate_in_an_agreed_room_opens_a_session_and_the_drag_lifts() -> void:
	_net = auto_free(WireNet.new())
	_net.army_manager = _main.opr_army_manager
	_main.network_manager = _net
	_main.radial_menu_controller.network_manager = _net
	_main._apply_rules_automatic_agreed()
	_main._apply_turn_token(1)
	var u := _plain(1, "Rifles", 0.0)
	_plain(2, "Guards", 18.0)
	assert_object(_main.solo_controller).override_failure_message("precondition: no controller yet").is_null()
	await _main.radial_menu_controller.card_start_activation(u)
	assert_bool(CoreActivation.session_open(u.unit_id)).override_failure_message("no session; activated %s" % u.is_activated) \
		.is_true()
	var om: Node3D = _main.object_manager
	om._selected_objects.clear()
	om._selected_objects.append(u.models[0].node)
	om._start_dragging(Vector2.ZERO)
	var lifted: bool = om._is_dragging and not om._drag_start_positions.is_empty()
	om._cancel_drag()
	assert_bool(lifted).override_failure_message("the started unit's drag was refused").is_true()


## ---- Step 50: the sender ----

func test_an_ended_core_activation_in_a_room_sends_one_check_after_the_activation_fact() -> void:
	_room()
	var u := _plain(1, "Rifles", 0.0)
	_plain(2, "Guards", 18.0)
	await _start_and_end(u)
	assert_bool(u.is_activated).override_failure_message("precondition: the End activated the unit").is_true()
	var order := _names().filter(func(n: String) -> bool: return n in ["sync_unit_activation", "activation_check"])
	assert_array(order).override_failure_message("frames: %s" % [_names()]) \
		.contains_exactly(["sync_unit_activation", "activation_check"])
	if _frames("activation_check").is_empty():
		return
	var check: Dictionary = _frames("activation_check")[0]
	var touched := CoreActivation.touched_units(_main, u)
	assert_int(int(check["to"])).is_equal(0)
	assert_dict(check["p"]).is_equal({"unit": u.unit_id, "units": [u.unit_id], "round": 1,
		"digest": CoreActivation.digest(touched), "rows": CoreActivation.rows(touched), "retry": 0})
	assert_int(int(CoreActivation._announced.get(u.unit_id, -1))).is_equal(1)


## Solo (an AI seat, no session) and hotseat (no seat, no session): the End sends nothing. A second own unit keeps the
## round open, and the frames let the AI's owed reply finish before the table is freed.
func test_no_check_leaves_a_table_without_a_session() -> void:
	for seat in [{2: true}, {}]:
		_room(false, RulesAutomation.Level.AUTOMATIC, seat)
		var u := _plain(1, "Rifles%d" % seat.size(), 0.0)
		_plain(1, "Reserves%d" % seat.size(), 6.0)
		await _start_and_end(u)
		await _runner.simulate_frames(10)
		assert_array(_frames("activation_check")).override_failure_message("seat %s: %s" % [seat, _names()]).is_empty()
		CoreActivation.reset_all(_main)


## Flag off, and a Manual room (the engine does not resolve): the activation fact goes out as today, no check.
func test_no_check_with_the_flag_off_or_in_a_manual_room() -> void:
	for manual in [false, true]:
		_room(true, RulesAutomation.Level.MANUAL if manual else RulesAutomation.Level.AUTOMATIC)
		CoreActivation._env = 1 if manual else 0
		var u := _plain(1, "Rifles%s" % manual, 0.0)
		_plain(2, "Guards%s" % manual, 18.0)
		await _start_and_end(u)
		assert_bool("sync_unit_activation" in _names()).override_failure_message("manual %s: %s" % [manual, _names()]).is_true()
		assert_array(_frames("activation_check")).override_failure_message("manual %s: %s" % [manual, _names()]).is_empty()


## A lifecycle unit with one special rule is not a core unit: its End sends no check.
func test_no_check_for_a_unit_with_a_special_rule() -> void:
	_room()
	var u := _plain(1, "Berserkers", 0.0, ["Furious"])
	_plain(2, "Guards", 18.0)
	await _start_and_end(u)
	assert_bool(u.is_activated).is_true()
	assert_array(_frames("activation_check")).override_failure_message("%s" % [_names()]).is_empty()


## A plain AI unit this table runs announces too (step 42 calls this at the end of the AI body); a non-plain one not.
func test_a_plain_ai_unit_announces_and_a_non_plain_one_does_not() -> void:
	_room(true, RulesAutomation.Level.AUTOMATIC, {2: true})
	var ai := _plain(2, "Bots", 18.0)
	var odd := _plain(2, "Brutes", 24.0, ["Furious"])
	CoreActivation.announce(_main, odd)
	CoreActivation.announce(_main, ai)
	assert_array(_frames("activation_check").map(func(f: Dictionary) -> String: return str(f["p"]["unit"]))) \
		.contains_exactly([ai.unit_id])


## The shot's target joins the check, and the note never outlives its activation: the End clears it, so do the next
## Start (a cancelled activation hands nothing on) and `reset_all` (the next game).
func test_the_target_joins_the_check_and_is_cleared_at_end_start_and_reset() -> void:
	_room()
	var u := _plain(1, "Rifles", 0.0)
	var foe := _plain(2, "Guards", 18.0)
	await _main.radial_menu_controller.card_toggle_activation(u)
	CoreActivation.last_target = foe
	await _main.radial_menu_controller.card_toggle_activation(u)
	var checks := _frames("activation_check")
	assert_array(checks.map(func(f: Dictionary) -> Array: return f["p"]["units"])).contains_exactly([[u.unit_id, foe.unit_id]])
	assert_object(CoreActivation.last_target).override_failure_message("the End kept the target").is_null()
	var next := _plain(1, "Reserves", 6.0)
	CoreActivation.reset_all(_main)
	CoreActivation.last_target = foe
	await _main.radial_menu_controller.card_toggle_activation(next)
	assert_bool(CoreActivation.session_open(next.unit_id)).override_failure_message("precondition: Start").is_true()
	assert_object(CoreActivation.last_target).override_failure_message("the Start kept a stale target").is_null()
	CoreActivation.last_target = foe
	CoreActivation.reset_all(_main)
	assert_object(CoreActivation.last_target).override_failure_message("reset_all kept the target").is_null()
	assert_dict(CoreActivation._announced).override_failure_message("reset_all kept the announcements").is_empty()


## Step 51 (the AI call site, lead 13.11.): an AI activation the core resolved (`run_ai`, step 42) announces one check in a
## room with an AI seat - the shooter and its target - and none in solo (no session).
func test_an_ai_volley_through_the_core_announces_one_check_in_a_room_and_none_in_solo() -> void:
	for room in [true, false]:
		_room(room, RulesAutomation.Level.AUTOMATIC, {2: true})
		_main._solo_auto_saves = true
		var ai := _plain(2, "Bots%s" % room, 0.0)
		var foe := _plain(1, "Rifles%s" % room, 10.0)
		_main.seed_tray_rng(7)
		var took: bool = await CoreActivation.run_ai(_main, ai, {"action": AiDecision.Action.HOLD}, foe,
			CoreActivation.capture(_main))
		var checks := _frames("activation_check").map(func(f: Dictionary) -> Array: return [f["p"]["unit"], f["p"]["units"]])
		assert_bool(took).override_failure_message("room %s: the core path was not taken" % room).is_true()
		assert_array(checks).override_failure_message("room %s: %s" % [room, checks]) \
			.is_equal([[ai.unit_id, [ai.unit_id, foe.unit_id]]] if room else [])
		CoreActivation.reset_all(_main)
		ai.models.map(func(m: ModelInstance) -> void: m.node.queue_free())
		foe.models.map(func(m: ModelInstance) -> void: m.node.queue_free())
		_main.opr_army_manager.game_units.erase(ai.unit_id)
		_main.opr_army_manager.game_units.erase(foe.unit_id)


## ---- Step 51: the receiver ----

const SENDER_PEER := 7


## This table's units as the other table's check names them, the check built from them as they stand now.
func _check_of(units: Array, round_no := 1, retry := 0) -> Dictionary:
	return {"unit": (units[0] as GameUnit).unit_id, "units": units.map(func(gu: GameUnit) -> String: return gu.unit_id),
		"round": round_no, "digest": CoreActivation.digest(units), "rows": CoreActivation.rows(units), "retry": retry}


func _receive(check: Dictionary) -> void:
	_main._on_network_command("activation_check", check, SENDER_PEER)


func test_a_matching_check_is_silent() -> void:
	_room()
	var units := [_plain(2, "Guards", 18.0), _plain(1, "Rifles", 0.0)]
	var ok_before := CoreActivation.checks_ok
	_receive(_check_of(units))
	assert_array(_net.wire).is_empty()
	assert_int(CoreActivation.checks_ok).is_equal(ok_before + 1)


## A wound only this table lost: one notice, to the sender alone, with both digests; nothing here changes.
func test_a_planted_wound_sends_one_mismatch_to_the_sender() -> void:
	_room()
	var units := [_plain(2, "Guards", 18.0)]
	var check := _check_of(units)
	var m: ModelInstance = (units[0] as GameUnit).models[1]
	m.wounds_current = 0
	_receive(check)
	var notes := _frames("activation_mismatch")
	assert_array(_names()).override_failure_message("%s" % [_names()]).contains_exactly(["activation_mismatch"])
	if notes.is_empty():
		return
	assert_int(int(notes[0]["to"])).is_equal(SENDER_PEER)
	assert_dict(notes[0]["p"]).is_equal({"unit": check["unit"], "units": check["units"], "round": 1,
		"theirs": check["digest"], "ours": CoreActivation.digest(units), "rows": CoreActivation.rows(units), "retry": 0})
	assert_int(m.wounds_current).override_failure_message("the receiver touched its own state").is_equal(0)


## The lead's rounding case: X at 100.4999 mm on one table and 100.5001 mm on the other rounds to 100 and 101, so the
## hashes differ; the rows agree within 1 mm and the check stays silent. A 2 mm difference is a mismatch.
func test_a_rounding_split_is_silent_and_two_millimetres_are_not() -> void:
	_room()
	var units := [_plain(2, "Guards", 18.0)]
	var n: Node3D = (units[0] as GameUnit).models[0].node
	n.global_position.x = 0.1004999
	var check := _check_of(units)
	n.global_position.x = 0.1005001
	assert_str(CoreActivation.digest(units)).override_failure_message("precondition: the hashes differ") \
		.is_not_equal(str(check["digest"]))
	_receive(check)
	assert_array(_net.wire).override_failure_message("rounding split: %s" % [_names()]).is_empty()
	n.global_position.x = 0.1025
	_receive(check)
	assert_array(_names()).override_failure_message("2 mm: %s" % [_names()]).contains_exactly(["activation_mismatch"])


## Another round, the flag off: ignored. A unit this table does not know: a mismatch.
func test_another_round_and_the_flag_off_are_ignored_and_an_unknown_unit_is_a_mismatch() -> void:
	_room()
	var units := [_plain(2, "Guards", 18.0)]
	var check := _check_of(units)
	(units[0] as GameUnit).models[0].wounds_current = 0
	var later := check.duplicate(true)
	later["round"] = 2
	_receive(later)
	CoreActivation._env = 0
	_receive(check)
	assert_array(_net.wire).override_failure_message("%s" % [_names()]).is_empty()
	CoreActivation._env = 1
	var ghost := check.duplicate(true)
	ghost["units"] = ["no_such_unit"]
	ghost["digest"] = CoreActivation.digest([])
	ghost["rows"] = []
	_receive(ghost)
	assert_array(_names()).contains_exactly(["activation_mismatch"])


## ---- Step 52: the correction ----

## The table that ran `u`'s activation (Start, End: it announced it); the wire is empty afterwards.
func _announced_activation() -> GameUnit:
	_room()
	var u := _plain(1, "Rifles", 0.0)
	_plain(2, "Guards", 18.0)
	await _start_and_end(u)
	_net.wire.clear()
	return u


## The reporter's notice: its rows are `units` as they stand after `change`; `undo` restores this table's own state.
func _notice(units: Array, change: Callable, undo: Callable) -> Dictionary:
	change.call()
	var their_rows := CoreActivation.rows(units)
	undo.call()
	return {"unit": (units[0] as GameUnit).unit_id, "units": units.map(func(gu: GameUnit) -> String: return gu.unit_id),
		"round": 1, "theirs": "x", "ours": "y", "rows": their_rows, "retry": 0}


## A wound the reporter lacks: ONE wound frame (that model, this table's wounds), the O15 (5) line, ONE re-check (retry 1)
## to the reporter alone - and nothing for what agrees (an alive wound frame re-parks a model on the receiver).
func test_the_winner_pushes_only_the_wound_that_differs_and_checks_once_more() -> void:
	var u: GameUnit = await _announced_activation()
	var m: ModelInstance = u.models[1]
	_main._on_network_command("activation_mismatch", _notice([u], func() -> void: m.wounds_current = 0,
		func() -> void: m.wounds_current = 1), SENDER_PEER)
	assert_array(_names()).override_failure_message("%s" % [_names()]) \
		.contains_exactly(["sync_model_wounds", "sync_log_event", "activation_check"])
	if _names().size() != 3:
		return
	assert_array((_net.wire[0]["p"]["a"] as Array).slice(0, 4)).is_equal([u.unit_id, 1, 1, true])
	var line := "Rifles: the tables disagreed after its activation - the state of %s was applied." % _main._solo_player_label(1)
	assert_str(str(_net.wire[1]["p"]["a"][1])).is_equal(line)
	assert_dict(_net.wire[2]).is_equal({"t": "activation_check", "to": SENDER_PEER, "p": {"unit": u.unit_id,
		"units": [u.unit_id], "round": 1, "digest": CoreActivation.digest([u]), "rows": CoreActivation.rows([u]), "retry": 1}})


## A model 3 mm off, Shaken and the activation flag differ: the Shaken marker, the flag as a CORRECTION (never the
## activation fact), and one move and one rotation batch holding that model alone.
func test_the_winner_pushes_a_moved_model_shaken_and_the_activation_flag_as_a_correction() -> void:
	var u: GameUnit = await _announced_activation()
	var n: Node3D = u.models[0].node
	var x := n.global_position.x
	var off := func() -> void:
		n.global_position.x = x + 0.003
		u.is_shaken = true
		u.is_activated = false
	var back := func() -> void:
		n.global_position.x = x
		u.is_shaken = false
		u.is_activated = true
	_main._on_network_command("activation_mismatch", _notice([u], off, back), SENDER_PEER)
	assert_array(_names()).override_failure_message("%s" % [_names()]).contains_exactly(["sync_unit_marker",
		"correct_unit_activated", "move_objects_batch_networked", "rotate_objects_batch_networked", "sync_log_event",
		"activation_check"])
	if _names().size() != 6:
		return
	assert_dict(_net.wire[1]).is_equal({"t": "correct_unit_activated", "to": SENDER_PEER,
		"p": {"unit": u.unit_id, "activated": true, "activation_round": u.activation_round}})
	var p := n.global_position
	assert_array(_net.wire[2]["p"]["a"][0]).is_equal([n.get_meta("network_id"), p.x, p.y, p.z])


## The correction sets the flag off turn too: the token stays, no activation line, nothing goes back on the wire. This
## table is the host and its activation-fact handler is wired as main wires its own network manager, so a correction that
## went through the fact path would be refused off turn and undone here.
func test_the_activation_correction_is_never_a_new_activation() -> void:
	_room()
	_net.is_host = true
	_net.remote_activation_updated.connect(_main._on_remote_activation_updated)
	var u := _plain(1, "Rifles", 0.0)
	_plain(2, "Guards", 18.0)
	_main._apply_turn_token(2)
	var lines: int = _main.battle_log.entries().size()
	_main._on_network_command("correct_unit_activated", {"unit": u.unit_id, "activated": true, "activation_round": 1},
		SENDER_PEER)
	await _runner.simulate_frames(2)
	assert_bool(u.is_activated).is_true()
	assert_int(_main._hotseat_side_on_turn()).is_equal(2)
	assert_array(_net.wire).override_failure_message("%s" % [_names()]).is_empty()
	assert_int(_main.battle_log.entries().size()).override_failure_message("a line was written").is_equal(lines)


## A table that did not run that activation does nothing on the notice: it waits for the push.
func test_a_table_that_did_not_announce_does_not_push() -> void:
	var u: GameUnit = await _announced_activation()
	var m: ModelInstance = u.models[1]
	CoreActivation._announced.clear()
	_main._on_network_command("activation_mismatch", _notice([u], func() -> void: m.wounds_current = 0,
		func() -> void: m.wounds_current = 1), SENDER_PEER)
	assert_array(_net.wire).override_failure_message("%s" % [_names()]).is_empty()


## The re-check after the push still differs: one line, and no notice - never a loop.
func test_a_failed_re_check_writes_the_still_disagree_line_and_sends_no_notice() -> void:
	_room()
	var units := [_plain(2, "Guards", 18.0)]
	var check := _check_of(units, 1, 1)
	(units[0] as GameUnit).models[0].wounds_current = 0
	_receive(check)
	assert_array(_names()).override_failure_message("%s" % [_names()]).contains_exactly(["sync_log_event"])
	assert_int(_main.battle_log.entries().filter(func(e: Dictionary) -> bool:
		return str(e["text"]) == "Guards: the tables still disagree - nothing more was changed.").size()).is_equal(1)
