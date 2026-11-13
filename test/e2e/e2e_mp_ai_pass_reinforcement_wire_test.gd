extends GdUnitTestSuite
## E2E - MP (online co-op, #673): the AI's Delayed Action stamp and the Reinforcement promise have to
## reach the other table.
##
## THE DEFECT. In an online co-op room two humans face one AI seat and the AI's activation resolves on
## whichever machine's activation it answered; the round-start beats (the Reinforcement arrivals among
## them) run only on the machine that closed the round. Three stamps were plain `unit_properties[...] = ...`
## writes, so the other machine read the rule's state wrongly:
##   - `delayed_action_round`: the AI passed its once-per-round Delayed Action; the machine that answers the
##     NEXT owed reply of that round had no stamp and passed with the same carrier again.
##   - `reinforcement_due_round`: a unit sacrificed on its owner's machine promises a copy for the next
##     round start; the machine that closes the round never heard of it, so the copy never came back.
##   - `reinforcement_spent` (+ the erase of the due round): the machine that brought the copy back knew the
##     rule was spent, the sacrificer's machine still held the promise and brought a SECOND copy.
##
## The suite drives the REAL main.tscn and records what main hands to NetworkManager (the WireNet of
## e2e_mp_ai_door_latch_wire_test.gd: the REAL NetworkManager with its transport swapped out, so the real
## allow-list gate applies), then replays those exact frames into the REAL receiver on a "second machine"
## whose copy of the unit starts without the stamp, and asks the rule's own question there.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const HUMAN_LINE := Vector3(-0.30, 0.0, 0.20)
const AI_LINE := Vector3(0.30, 0.0, -0.20)


class WireNet extends "res://scripts/network_manager.gd":
	var active: bool = true
	var wire: Array = []
	func is_multiplayer_active() -> bool:
		return active
	func _validate_rpc_ready(_context: String = "") -> bool:
		return true
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
var _fake: WireNet
var _real_net: Node


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	_real_net = _main.network_manager   # kept for the receive side (its handler is call_remote)
	_fake = auto_free(WireNet.new())
	_main.network_manager = _fake


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null
	_real_net = null


# --- fixtures ----------------------------------------------------------------------------------

func _register(pid: int, unit_name: String, at: Vector3, models: int = 2) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(at + Vector3(0.03 * i, 0.0, 0.0))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A Delayed Action carrier of the AI, with a human unit well inside a rush band of it and two more humans,
## so the AI's pass condition (more units left on the other side, a threat to wait out) holds.
func _ai_pass_table() -> GameUnit:
	var guard := _register(2, "Waechter", AI_LINE)
	guard.unit_properties["special_rules"] = ["Delayed Action"]
	guard.unit_properties["cost"] = 240
	_register(1, "Jaeger", AI_LINE + Vector3(0.15, 0.0, 0.0))
	for i in range(2):
		_register(1, "Grenzer%d" % (i + 1), HUMAN_LINE + Vector3(0.0, 0.0, 0.12 * (i + 1)))
	return guard


func _profile(unit_name: String, size: int, rules: Array) -> OPRApiClient.OPRUnit:
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
	for r in rules:
		u.special_rules.append(str(r))
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rusty Blade"
	w.attacks = 2
	u.weapons.append(w)
	return u


## A Reinforcement carrier standing on the table, built through the runtime factory like the real e2e suite.
func _carrier(unit_name: String, count: int, pid: int) -> GameUnit:
	var positions: Array = []
	for i in count:
		positions.append(Vector3(float(i) * 1.2 * INCH, 0.0, 0.0))
	var u: GameUnit = _main.opr_army_manager.create_runtime_unit({
		"opr_unit": _profile(unit_name, count, ["Tough(1)", "Reinforcement"]), "faction_folder": "ratmen_clans",
	}, pid, positions, "spawn")
	assert_object(u).is_not_null()
	return u


func _copies_of(original: GameUnit) -> Array:
	var out: Array = []
	for g in _main.opr_army_manager.get_all_game_units():
		var gu := g as GameUnit
		if gu != null and gu != original and str(gu.unit_properties.get("origin", "")) == "reinforcement":
			out.append(gu)
	return out


## The unit-property frames this machine sent, in order: {unit, key, value}.
func _frames() -> Array:
	var out: Array = []
	for w in _fake.wire:
		var p: Dictionary = (w as Dictionary)["p"] as Dictionary
		if str(p.get("m", "")) != "sync_unit_property":
			continue
		var a: Array = p["a"]
		out.append({"unit": str(a[0]), "key": str(a[1]), "value": a[2]})
	return out


func _values(key: String) -> Array:
	var out: Array = []
	for e in _frames():
		if str((e as Dictionary)["key"]) == key:
			out.append((e as Dictionary)["value"])
	return out


## Read defensively: with no frame at all every assertion must still FAIL cleanly (an out-of-bounds index
## takes gdUnit's -d run into the debugger and the whole headless process down).
func _first_unit(key: String) -> String:
	for e in _frames():
		if str((e as Dictionary)["key"]) == key:
			return str((e as Dictionary)["unit"])
	return "<no message>"


## The frames sent so far, and the recording starts over (one machine's sentence at a time).
func _take_frames() -> Array:
	var out := _frames()
	_fake.wire.clear()
	return out


## The other machine receives exactly these frames through the REAL receiver.
func _replay(frames: Array) -> void:
	for e in frames:
		var d := e as Dictionary
		_real_net.sync_unit_property(str(d["unit"]), str(d["key"]), d["value"])


func _log_count(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).contains(needle):
			n += 1
	return n


# === 1. Delayed Action: the AI passes once per round, whichever machine answers ======================

func test_the_ais_pass_stamp_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	var guard := _ai_pass_table()
	_main._solo_pending_replies = 1
	assert_bool(_main._solo_ai_delayed_action_pass()) \
		.override_failure_message("fixture check: the AI passes the first owed reply") \
		.is_true()
	assert_array(_values("delayed_action_round")) \
		.override_failure_message("the once-per-round stamp never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([1])
	assert_str(_first_unit("delayed_action_round")).is_equal(guard.unit_id)

	# The other machine answers the next owed reply of the SAME round: its copy of the carrier never saw the stamp.
	var frames := _take_frames()
	guard.unit_properties.erase("delayed_action_round")
	_replay(frames)
	_main._solo_pending_replies = 1
	assert_bool(_main._solo_ai_delayed_action_pass()) \
		.override_failure_message("the other table passes a second time with the same carrier in one round") \
		.is_false()
	assert_int(_log_count("passes the turn")).is_equal(1)


# === 2. Reinforcement: the promise travels, and so does its keeping =================================

func test_a_humans_promised_copy_arrives_on_the_table_that_closes_the_round(timeout := 120000) -> void:
	var u := _carrier("Clan Rats", 3, 1)
	u.is_shaken = true
	await _main.solo_begin_reinforcement(u)
	assert_array(_values("reinforcement_due_round")) \
		.override_failure_message("the promise never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([2])
	assert_str(_first_unit("reinforcement_due_round")).is_equal(u.unit_id)

	# The machine that closes round 1 is not the sacrificer's: it never heard of the promise.
	var frames := _take_frames()
	u.unit_properties.erase("reinforcement_due_round")
	_replay(frames)
	await _main._reinforcement_arrivals(2)
	assert_int(_copies_of(u).size()) \
		.override_failure_message("the promised copy never came back on the table that closed the round") \
		.is_equal(1)
	await E2EBoot.settle(get_tree())


func test_a_kept_promise_is_not_kept_again_on_the_other_table(timeout := 120000) -> void:
	var u := _carrier("Clan Rats", 3, 1)
	u.is_shaken = true
	await _main.solo_begin_reinforcement(u)
	_take_frames()
	await _main._reinforcement_arrivals(2)
	assert_int(_copies_of(u).size()).override_failure_message("fixture check: the copy came back once").is_equal(1)
	assert_array(_values("reinforcement_spent")) \
		.override_failure_message("the kept promise never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([true])
	assert_array(_values("reinforcement_due_round")) \
		.override_failure_message("the erase of the due round never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([null])

	# The sacrificer's machine: it still holds the promise and has not heard of the arrival.
	var frames := _take_frames()
	u.unit_properties["reinforcement_due_round"] = 2
	u.unit_properties.erase("reinforcement_spent")
	_replay(frames)
	assert_str(SoloController.reinforcement_refusal(u)) \
		.override_failure_message("the other table does not know the once-per-game rule is spent") \
		.contains("already used")
	await _main._reinforcement_arrivals(3)
	assert_int(_copies_of(u).size()) \
		.override_failure_message("the other table brought a SECOND copy back at the next round start") \
		.is_equal(1)
	await E2EBoot.settle(get_tree())


func test_the_ais_sacrifice_reaches_the_table_that_closes_the_next_round(timeout := 120000) -> void:
	var u := _carrier("Clan Rats", 3, 2)
	u.is_shaken = true
	await _main._solo_reinforcement_ai_offers()
	assert_array(_values("reinforcement_due_round")) \
		.override_failure_message("the AI's promise never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([2])

	var frames := _take_frames()
	u.unit_properties.erase("reinforcement_due_round")
	_replay(frames)
	assert_array(SoloController.reinforcement_due(_main.opr_army_manager.get_all_game_units(), 2)) \
		.override_failure_message("the other table does not owe the AI's copy at the next round start") \
		.is_equal([u])
	await E2EBoot.settle(get_tree())


# === 3. A look-ahead never speaks ====================================================================

## `_sync_unit_property` writes AND broadcasts, so none of the three doors may run inside a preview. None can
## (callers: the AI pump / arena driver for the pass, the radial verb, the AI offer beat and the round-start
## arrival beat for Reinforcement; the only look-ahead main has is `_solo_preview_for`). Runtime proof, with a
## control that a real door in the same test does send a frame.
func test_a_landing_preview_sends_no_pass_or_reinforcement_frame(timeout := 120000) -> void:
	var fast0: bool = MovementPlanner.fast_planner
	var guard0: Variant = MovementPlanner.fast_planner_guard
	MovementPlanner.fast_planner = false   # deterministic precise planner (as e2e_auto_preview_test.gd)
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD
	_main._solo_fast = true
	_ai_pass_table()
	var shaken_ai := _carrier("Clan Rats", 3, 2)
	shaken_ai.is_shaken = true
	var shooter := E2EBoot.make_unit(_main, 1, "Riflemen", [Vector3(-0.8, 0, 0), Vector3(-0.8, 0, 1.5 * INCH), Vector3(-0.8, 0, -1.5 * INCH)])
	var opr := OPRApiClient.OPRUnit.new()
	var rifle := OPRApiClient.OPRWeapon.new()
	rifle.name = "Rifle"
	rifle.range_value = 12
	rifle.attacks = 1
	opr.weapons = [rifle]
	shooter.source_type = "opr"
	shooter.source_data = opr
	_main.opr_army_manager.game_units[shooter.unit_id] = shooter
	var enemy := _register(2, "Foe", Vector3(-0.8 + 16.0 * INCH, 0, 0), 1)
	enemy.is_activated = true
	_fake.wire.clear()   # the carriers' own creation frames are not the question

	var advance: Dictionary = _main._solo_preview_for(shooter, AiDecision.Action.ADVANCE, enemy)
	_main._solo_preview_for(shooter, AiDecision.Action.CHARGE, enemy)

	assert_int((advance.get("landing", []) as Array).size()) \
		.override_failure_message("fixture check: the preview must really have run (landing ghosts)") \
		.is_greater(0)
	assert_array(_frames()) \
		.override_failure_message("a look-ahead sent hidden state to the other table: %s" % str(_frames())) \
		.is_empty()
	# CONTROL: the same recording does see a real door.
	var human := _carrier("Rat Pack", 3, 1)
	human.is_shaken = true
	await _main.solo_begin_reinforcement(human)
	assert_array(_values("reinforcement_due_round")).is_equal([2])

	MovementPlanner.fast_planner = fast0
	MovementPlanner.fast_planner_guard = guard0
	await E2EBoot.settle(get_tree())


# === 4. Counter-proofs ================================================================================

## Offline the whole thing must stay silent and still latch.
func test_a_solo_game_stamps_without_a_frame(timeout := 120000) -> void:
	_fake.active = false
	var guard := _ai_pass_table()
	_main._solo_pending_replies = 1
	assert_bool(_main._solo_ai_delayed_action_pass()).is_true()
	var u := _carrier("Clan Rats", 3, 1)
	u.is_shaken = true
	await _main.solo_begin_reinforcement(u)
	await _main._reinforcement_arrivals(2)

	assert_int(int(guard.unit_properties.get("delayed_action_round", -1))).is_equal(1)
	assert_bool(bool(u.unit_properties.get("reinforcement_spent", false))).is_true()
	assert_bool(u.unit_properties.has("reinforcement_due_round")).is_false()
	assert_array(_frames()) \
		.override_failure_message("an offline game broadcast hidden state") \
		.is_empty()
	await E2EBoot.settle(get_tree())


## The allow-list is still a boundary: the three keys are listed, ownership still is not.
func test_the_receiver_takes_the_three_keys_and_still_refuses_ownership(timeout := 120000) -> void:
	var alpha := _register(1, "Alpha", HUMAN_LINE, 1)
	for key in ["delayed_action_round", "reinforcement_due_round", "reinforcement_spent"]:
		_real_net.sync_unit_property(alpha.unit_id, key, 3)
		assert_int(int(alpha.unit_properties.get(key, 0))).override_failure_message(key).is_equal(3)
	_real_net.sync_unit_property(alpha.unit_id, "reinforcement_due_round", null)
	assert_bool(alpha.unit_properties.has("reinforcement_due_round")).is_false()
	_real_net.sync_unit_property(alpha.unit_id, "player_id", 2)
	assert_int(int(alpha.unit_properties.get("player_id", 0))).is_equal(1)
