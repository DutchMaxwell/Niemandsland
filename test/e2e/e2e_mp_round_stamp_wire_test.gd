extends GdUnitTestSuite
## E2E - MP (online co-op, #673): the round stamps and counters that ANOTHER table's attack reads have to reach it.
##
## THE DEFECT. In an online co-op room two humans face one AI seat and the AI's activation resolves on whichever
## machine's activation it answered, so one unit is attacked, defended and moved on either table. These writes were
## plain `unit_properties[...] = ...`, so the other table read a stale unit:
##   - `moved_round` (a human drop, an AI move, a move take-back): Entrenched / Artillery read the TARGET's stamp, the
##     AI's Hold read as well; a unit that moved on one table still counted as held on the other.
##   - `ravage_round`, `regenerative_strength_round`: once per ROUND, read at the strike-back of every melee, which
##     can resolve on either table; the second table rolled the dice again.
##   - `reckless_ap_round` / `reckless_backfire_round`: round-long AP(+1), read at every attack by or against the bearer.
##   - `mind_control_moved_round`: a unit is MOVED by Mind Control once per round, whichever bearer's table answers.
##   - `vengeance_markers`: +1 to hit per marker for everyone who attacks the destroyer.
##   - `growth_<rule>` (the on-kill accrual): the round tick runs on both tables, the kill only where it resolves.
##
## The suite drives the REAL main.tscn and records what main hands to NetworkManager (the WireNet of
## e2e_mp_ai_door_latch_wire_test.gd: the REAL NetworkManager, transport swapped out, so the real allow-list gate
## applies), replays those exact frames into the REAL receiver on a "second machine" whose copy of the unit starts
## without the stamp, and asks the rule's own question there.

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
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
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
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null
	_real_net = null


# --- fixtures ----------------------------------------------------------------------------------

func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _unit(pid: int, unit_name: String, at: Vector3, models: int = 1) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(at + Vector3(0.03 * i, 0.0, 0.0))
	return _reg(E2EBoot.make_unit(_main, pid, unit_name, positions))


## One Q4 melee striker of player 1 carrying `rule` (a book that fields it), and a ten-model foe that outlives
## two strikes (the mel_11 / mel_12 shape). The striker is returned.
func _striker(rule: String, faction: String, tokens: int = 0) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Maulers", [Vector3.ZERO])
	(u.models[0] as ModelInstance).model_index = 0
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Club"
	w.range_value = 0
	w.attacks = 1
	w.count = 1
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	u.source_type = "opr"
	u.source_data = src
	u.unit_properties["special_rules"] = [rule]
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["game_system"] = "gf"
	if tokens > 0:
		u.unit_properties["growth_%s" % rule.to_snake_case()] = tokens
	_reg(u)
	var spots: Array = []
	for i in range(10):
		spots.append(Vector3((0.5 + i) * INCH, 0, 0.5 * INCH))
	_reg(E2EBoot.make_unit(_main, 2, "Grunts", spots))
	return u


func _foe_of(striker: GameUnit) -> GameUnit:
	for g in _main.opr_army_manager.get_all_game_units():
		if g != striker and int((g as GameUnit).unit_properties.get("player_id", 0)) == 2:
			return g as GameUnit
	return null


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


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _seed_first_die(face: int) -> void:
	var rng := RandomNumberGenerator.new()
	for candidate in range(500):
		rng.seed = candidate
		if rng.randi_range(1, 6) == face:
			_main.seed_tray_rng(candidate)
			return
	fail("no seed rolls a %d first" % face)


# === 1. moved_round: a drop, an AI move, a take-back ================================================

func test_a_humans_drop_stamp_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	var u := _unit(1, "Riflemen", HUMAN_LINE)
	await _main._on_units_dropped([{"node": (u.models[0] as ModelInstance).node, "inches": 3.0}])
	assert_array(_values("moved_round")) \
		.override_failure_message("the move stamp never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([1])
	assert_str(_first_unit("moved_round")).is_equal(u.unit_id)

	# The AI answers on the other table, and reads the target's Hold there.
	var frames := _take_frames()
	u.unit_properties.erase("moved_round")
	assert_bool(_main.solo_controller._held_now(u)).override_failure_message("control: a table that heard nothing reads it as held").is_true()
	_replay(frames)
	assert_bool(_main.solo_controller._held_now(u)) \
		.override_failure_message("the other table's AI still reads a unit that moved this round as held (Entrenched / Artillery)") \
		.is_false()


func test_an_ai_moves_stamp_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	var ai := _unit(2, "Raiders", AI_LINE)
	var mi := ai.models[0] as ModelInstance
	var start: Vector3 = mi.node.global_position
	await _main._solo_animate_move([{"model": mi, "path": [start, start + Vector3(0.01, 0.0, 0.0)], "radius_m": 0.0125}])
	assert_array(_values("moved_round")) \
		.override_failure_message("the AI's move stamp never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([1])

	var frames := _take_frames()
	ai.unit_properties.erase("moved_round")
	_replay(frames)
	assert_bool(_main._solo_unit_held(ai)) \
		.override_failure_message("the other table reads the AI unit that moved this round as held") \
		.is_false()


## The take-back puts the previous stamp (here: none) back, and the other table has to hear it, or its copy of the unit
## keeps saying "moved" after the move never happened.
func test_a_take_back_unstamps_the_other_table_too(timeout := 120000) -> void:
	var u := _unit(1, "Riflemen", HUMAN_LINE)
	var node: Node3D = (u.models[0] as ModelInstance).node
	var from: Vector3 = node.global_position
	node.global_position = from + Vector3(0.2, 0, 0)
	var moves := [{"node": node, "from": from, "to": node.global_position, "from_raw": from, "from_rot": 0.0,
		"inches": 0.2 / INCH, "path": PackedVector2Array([Vector2(from.x, from.z), Vector2(node.global_position.x, node.global_position.z)]),
		"radius_m": 0.0125, "drop_id": 1}]
	_main._on_trails_dropped(moves, true)
	await _main._on_units_dropped(moves)
	assert_int(int(u.unit_properties.get("moved_round", -1))).override_failure_message("fixture check: the drop stamped").is_equal(1)
	_take_frames()   # the drop's own frame is not the question
	assert_str(_main.undo_manager.undo_for(_fake.get_my_peer_id())).override_failure_message("fixture check: the take-back ran").contains("Take back")
	assert_bool(u.unit_properties.has("moved_round")).override_failure_message("fixture check: the stamp is gone here").is_false()
	var frames := _take_frames()
	assert_array(frames.filter(func(f): return str((f as Dictionary)["key"]) == "moved_round").map(func(f): return (f as Dictionary)["value"])) \
		.override_failure_message("the take-back never told the other table (frames: %s)" % str(frames)) \
		.is_equal([null, ])

	# The other table had heard about the drop and now hears the take-back.
	u.unit_properties["moved_round"] = 1
	_replay(frames)
	assert_bool(_main.solo_controller._held_now(u)) \
		.override_failure_message("the other table still reads the unit as moved after the take-back") \
		.is_true()


# === 2. Ravage / Regenerative Strength: once per round, on either table =============================

func test_the_ravage_stamp_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	var u := _striker("Ravage(2)", "alien_hives")
	var foe := _foe_of(u)
	await _main._solo_melee_strike_phase(u, foe, false, 0)
	assert_int(_log_text().count("Ravage(2): Maulers rolls")).override_failure_message("fixture check: Ravage rolled once").is_equal(1)
	assert_array(_values("ravage_round")) \
		.override_failure_message("the once-per-round stamp never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([1])
	assert_str(_first_unit("ravage_round")).is_equal(u.unit_id)

	# The same unit is attacked on the other table later in the round: its strike-back reads its own copy there.
	var frames := _take_frames()
	u.unit_properties.erase("ravage_round")
	_replay(frames)
	await _main._solo_melee_strike_phase(u, foe, false, 0)
	assert_int(_log_text().count("Ravage(2): Maulers rolls")) \
		.override_failure_message("the other table rolled the once-per-round Ravage a second time:\n%s" % _log_text()) \
		.is_equal(1)
	await E2EBoot.settle(get_tree())


func test_the_regenerative_strength_stamp_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	var u := _striker("Regenerative Strength", "alien_hives", 3)
	var foe := _foe_of(u)
	await _main._solo_melee_strike_phase(u, foe, false, 0)
	assert_int(_log_text().count("Regenerative Strength: Maulers rolls 3 dice")).override_failure_message("fixture check: the dice rolled once").is_equal(1)
	assert_array(_values("regenerative_strength_round")) \
		.override_failure_message("the once-per-round stamp never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([1])

	var frames := _take_frames()
	u.unit_properties.erase("regenerative_strength_round")
	_replay(frames)
	await _main._solo_melee_strike_phase(u, foe, false, 0)
	assert_int(_log_text().count("Regenerative Strength: Maulers rolls 3 dice")) \
		.override_failure_message("the other table rolled the once-per-round token dice a second time:\n%s" % _log_text()) \
		.is_equal(1)
	await E2EBoot.settle(get_tree())


# === 3. Reckless Piercing: the round stamps on the bearer chain ======================================

func _reckless_bearer() -> GameUnit:
	var bearer := _unit(2, "Wildlings", AI_LINE)
	bearer.unit_properties["game_system"] = "aof"
	bearer.unit_properties["faction_folder"] = "daemons_of_war"
	bearer.unit_properties["special_rules"] = ["Reckless Piercing"]
	return bearer


func test_reckless_ap_stamp_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	var bearer := _reckless_bearer()
	var other := _unit(1, "Defenders", HUMAN_LINE)
	_seed_first_die(3)   # 2+ : the weapons get AP(+1)
	await _main._solo_apply_reckless_piercing(bearer)
	assert_array(_values("reckless_ap_round")) \
		.override_failure_message("the buff stamp never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([1])
	assert_str(_first_unit("reckless_ap_round")).is_equal(bearer.unit_id)

	# The bearer's strike-back on the other table is an attack there: it must carry the AP.
	var frames := _take_frames()
	bearer.unit_properties.erase("reckless_ap_round")
	assert_int(_main._solo_reckless_ap(bearer, other)).override_failure_message("control: a table that heard nothing adds no AP").is_equal(0)
	_replay(frames)
	assert_int(_main._solo_reckless_ap(bearer, other)) \
		.override_failure_message("the other table's attack by the bearer carries no AP(+1)") \
		.is_equal(1)


func test_reckless_backfire_stamp_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	var bearer := _reckless_bearer()
	var other := _unit(1, "Defenders", HUMAN_LINE)
	_seed_first_die(1)   # a 1: the enemies get AP(+1) against the bearer
	await _main._solo_apply_reckless_piercing(bearer)
	assert_array(_values("reckless_backfire_round")) \
		.override_failure_message("the backfire stamp never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([1])

	var frames := _take_frames()
	bearer.unit_properties.erase("reckless_backfire_round")
	_replay(frames)
	assert_int(_main._solo_reckless_ap(other, bearer)) \
		.override_failure_message("the other table's attack against the bearer carries no AP(+1) from the backfire") \
		.is_equal(1)


# === 4. Mind Control: moved once per round, whichever bearer's table answers =========================

func test_the_mind_control_stamp_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	_main.opr_army_manager.current_round = 3
	var target := _unit(1, "Victim", Vector3(5.0 * INCH, 0, 0))
	var first := _unit(2, "First", Vector3.ZERO)
	var second := _unit(2, "Second", Vector3(0.5 * INCH, 0, 0))
	for b in [first, second]:
		(b as GameUnit).unit_properties["game_system"] = "gf"
		(b as GameUnit).unit_properties["faction_folder"] = "jackals"
		(b as GameUnit).unit_properties["special_rules"] = ["Mind Control"]
	_seed_first_die(3)   # a fail on the target's Quality 4
	var before: Vector3 = _main.solo_controller.unit_centre(target)
	await _main._solo_apply_mind_control(first)
	var after_first: Vector3 = _main.solo_controller.unit_centre(target)
	assert_float(before.distance_to(after_first)).override_failure_message("fixture check: the first bearer moves it").is_greater(5.0 * INCH)
	assert_array(_values("mind_control_moved_round")) \
		.override_failure_message("the once-per-round stamp never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([3])
	assert_str(_first_unit("mind_control_moved_round")).is_equal(target.unit_id)

	# The second bearer is answered on the other table.
	var frames := _take_frames()
	target.unit_properties.erase("mind_control_moved_round")
	_replay(frames)
	_seed_first_die(3)
	await _main._solo_apply_mind_control(second)
	assert_float(after_first.distance_to(_main.solo_controller.unit_centre(target))) \
		.override_failure_message("the other table moved the unit by Mind Control a second time in one round:\n%s" % _log_text()) \
		.is_equal_approx(0.0, 0.001)
	await E2EBoot.settle(get_tree())


# === 5. Vengeance markers ============================================================================

func test_vengeance_markers_ride_the_wire_and_hold_on_the_other_table(timeout := 120000) -> void:
	var fallen := _unit(2, "Honour Guard", AI_LINE, 3)
	fallen.unit_properties["game_system"] = "gf"
	fallen.unit_properties["faction_folder"] = "eternal_dynasty"
	fallen.unit_properties["special_rules"] = ["Vengeance"]
	var slayer := _unit(1, "Slayers", HUMAN_LINE, 2)
	_main._solo_vengeance_on_destroyed(fallen, slayer)
	assert_array(_values("vengeance_markers")) \
		.override_failure_message("the markers never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([3])
	assert_str(_first_unit("vengeance_markers")).is_equal(slayer.unit_id)

	# Whoever attacks the slayer on the other table reads the markers there.
	var frames := _take_frames()
	slayer.unit_properties.erase("vengeance_markers")
	assert_int(_main._solo_vengeance_bonus(slayer)).override_failure_message("control: a table that heard nothing adds no bonus").is_equal(0)
	_replay(frames)
	assert_int(_main._solo_vengeance_bonus(slayer)) \
		.override_failure_message("the other table's attackers get no +1 to hit per Vengeance marker") \
		.is_equal(3)


# === 6. Growth Markers: the on-kill accrual =========================================================

func test_the_on_kill_growth_marker_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	var u := _unit(2, "Berserkers", AI_LINE)
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "daemons_of_war"
	u.unit_properties["special_rules"] = ["Defensive Frenzy"]
	_main._solo_growth_on_kill(u)
	assert_array(_values("growth_defensive_frenzy")) \
		.override_failure_message("the marker never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([1])

	# The unit is defended on the other table: its save reads the marker there.
	var frames := _take_frames()
	u.unit_properties.erase("growth_defensive_frenzy")
	assert_int(_main._solo_growth_markers(u, "Defensive Frenzy")).override_failure_message("control: a table that heard nothing has none").is_equal(0)
	_replay(frames)
	assert_int(_main._solo_growth_markers(u, "Defensive Frenzy")) \
		.override_failure_message("the other table does not know the marker earned for the kill") \
		.is_equal(1)


# === 7. A look-ahead never speaks ====================================================================

## `_sync_unit_property` writes AND broadcasts, so no door may run inside a preview. The writers are the human drop,
## the executed AI move, the melee strike phase, the Reckless / Mind Control / Vengeance doors and the kill seam: all
## real resolutions; the only look-ahead main has is `_solo_preview_for` (the controller under `_preview_depth`).
## Runtime proof with a control that a real door in the same test does send a frame.
func test_a_landing_preview_sends_no_stamp_frame(timeout := 120000) -> void:
	var fast0: bool = MovementPlanner.fast_planner
	var guard0: Variant = MovementPlanner.fast_planner_guard
	MovementPlanner.fast_planner = false   # deterministic precise planner (as e2e_auto_preview_test.gd)
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD
	_main._solo_fast = true
	var reckless := _reckless_bearer()
	reckless.unit_properties["special_rules"] = ["Reckless Piercing", "Ravage(2)"]
	var shooter := E2EBoot.make_unit(_main, 1, "Riflemen", [Vector3(-0.8, 0, 0), Vector3(-0.8, 0, 1.5 * INCH), Vector3(-0.8, 0, -1.5 * INCH)])
	var opr := OPRApiClient.OPRUnit.new()
	var rifle := OPRApiClient.OPRWeapon.new()
	rifle.name = "Rifle"
	rifle.range_value = 12
	rifle.attacks = 1
	opr.weapons = [rifle]
	shooter.source_type = "opr"
	shooter.source_data = opr
	_reg(shooter)
	var enemy := _unit(2, "Foe", Vector3(-0.8 + 16.0 * INCH, 0, 0))
	enemy.is_activated = true
	_fake.wire.clear()

	var advance: Dictionary = _main._solo_preview_for(shooter, AiDecision.Action.ADVANCE, enemy)
	_main._solo_preview_for(shooter, AiDecision.Action.CHARGE, enemy)

	assert_int((advance.get("landing", []) as Array).size()) \
		.override_failure_message("fixture check: the preview must really have run (landing ghosts)") \
		.is_greater(0)
	assert_array(_frames()) \
		.override_failure_message("a look-ahead sent hidden state to the other table: %s" % str(_frames())) \
		.is_empty()
	# CONTROL: the same recording does see a real door.
	await _main._on_units_dropped([{"node": (shooter.models[0] as ModelInstance).node, "inches": 3.0}])
	assert_array(_values("moved_round")).is_equal([1])

	MovementPlanner.fast_planner = fast0
	MovementPlanner.fast_planner_guard = guard0


# === 8. Counter-proofs ================================================================================

## Offline the whole thing must stay silent and still stamp.
func test_a_solo_game_stamps_without_a_frame(timeout := 120000) -> void:
	_fake.active = false
	var u := _unit(1, "Riflemen", HUMAN_LINE)
	await _main._on_units_dropped([{"node": (u.models[0] as ModelInstance).node, "inches": 3.0}])
	var berserkers := _unit(2, "Berserkers", AI_LINE)
	berserkers.unit_properties["game_system"] = "gf"
	berserkers.unit_properties["faction_folder"] = "daemons_of_war"
	berserkers.unit_properties["special_rules"] = ["Defensive Frenzy"]
	_main._solo_growth_on_kill(berserkers)

	assert_int(int(u.unit_properties.get("moved_round", -1))).is_equal(1)
	assert_int(int(berserkers.unit_properties.get("growth_defensive_frenzy", 0))).is_equal(1)
	assert_array(_frames()).override_failure_message("an offline game broadcast hidden state").is_empty()


## The allow-list is still a boundary: the seven keys and the growth prefix are listed, ownership is not.
func test_the_receiver_takes_the_stamp_keys_and_still_refuses_other_keys(timeout := 120000) -> void:
	var alpha := _unit(1, "Alpha", HUMAN_LINE)
	for key in ["moved_round", "ravage_round", "regenerative_strength_round", "reckless_ap_round", "reckless_backfire_round",
			"mind_control_moved_round", "vengeance_markers", "growth_defensive_frenzy", "growth_piercing_growth"]:
		_real_net.sync_unit_property(alpha.unit_id, key, 2)
		assert_int(int(alpha.unit_properties.get(key, 0))).override_failure_message(key).is_equal(2)
	_real_net.sync_unit_property(alpha.unit_id, "moved_round", null)
	assert_bool(alpha.unit_properties.has("moved_round")).is_false()
	for key in ["player_id", "growth", "growthX", "moved_rounds", "game_system"]:
		_real_net.sync_unit_property(alpha.unit_id, key, 9)
		assert_bool(alpha.unit_properties.get(key) == 9).override_failure_message(key).is_false()
