extends GdUnitTestSuite
## One-core P3 step 48 (N3 b, the round gate): a plain mission's round end through the core (step 47, flag on) equals the
## table's own (_solo_auto_seize + _solo_book_mission_vp, flag off) on 50 seeded layouts - two objectives, two to four
## plain units per side at seeded spots, some Shaken, some just arrived from Ambush or placed by Spawn, three VP
## flavours: objective owners, VP, the VP memo and every battle-log line byte for byte. The core's round begin names the
## opener ai_opens_next_round names, for both last activations and either side wiped. Step 47's fallbacks: a mission
## with markers (O7) and an empty table are booked by the table without an error; a unit in reserve sends the round
## begin back to the table. Real: the main scene, NmlCore, the table's round code. Constructed: the layouts.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const INCH := 0.0254
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": [], "models": 3}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 3, "rules": []}
const FLAVOURS := [{}, {"majority": "round"}, {"first_seize": true}]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.solo_controller.game_rounds = 4
	SoloController.mission_scoring = "round_vp"
	SoloController.mission_markers = []


func after_test() -> void:
	CoreActivation._env = -1
	SoloController.mission_scoring = "end"
	SoloController.mission_markers = []
	SoloController.mission_vp = [0, 0]
	SoloController.mission_vp_memo = {}
	SoloController.mission_vp_flavour = {}
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _clear_units() -> void:
	for u in _main.opr_army_manager.game_units.values():
		for m in (u as GameUnit).models:
			(m as ModelInstance).node.queue_free()
	_main.opr_army_manager.game_units.clear()


## Layout `s` on fresh units (the same draws in both runs); `wiped` = the side whose models all died (0 = none).
func _layout(s: int, wiped := 0) -> void:
	var army: OPRArmyManager = _main.opr_army_manager
	_clear_units()
	SoloController.mission_markers = []
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	army.current_round = rng.randi_range(1, 4)
	for side in [1, 2]:
		for k in rng.randi_range(2, 4):
			var u: GameUnit = ParityTable._make_unit(_main, SIDE.merged({"player": side, "name": "U%d%d" % [side, k],
				"x_in": rng.randf_range(-10.0, 10.0)}), RIFLE)
			var dz := rng.randf_range(-8.0, 6.0) * INCH
			for m in u.models:
				(m as ModelInstance).node.global_position.z += dz
				(m as ModelInstance).is_alive = side != wiped
			u.is_shaken = rng.randf() < 0.25
			var arrival := rng.randi_range(0, 6)
			if arrival <= 1:
				u.unit_properties["ambush_arrived_round"] = army.current_round
			if arrival == 1:
				u.unit_properties["origin"] = "spawn"
	_main.terrain_overlay.update_objectives([Vector3(-4.0 * INCH, 0, 0), Vector3(4.0 * INCH, 0, 2.0 * INCH)],
		[rng.randi_range(0, 2), rng.randi_range(0, 2)])
	SoloController.mission_vp = [rng.randi_range(0, 5), rng.randi_range(0, 5)]
	SoloController.mission_vp_memo = {}
	SoloController.mission_vp_flavour = (FLAVOURS[rng.randi_range(0, 2)] as Dictionary).duplicate()


## The round end of layout `s`, booked by the table ("table": _solo_auto_seize + _solo_book_mission_vp), by the core
## ("core": step 47's _solo_core_round_end) or by _solo_end_round under the flag ("end_round", the summary skipped).
## `fallback` "markers" / "empty" gives the mission a marker per objective / clears the table, at the last round.
## "path" = the expected path was taken: the core booked a "core" run and declined an "end_round" run.
func _round_end(s: int, how: String, fallback := "") -> Dictionary:
	_layout(s)
	if fallback != "":
		_main.opr_army_manager.current_round = 4
		_main._solo_game_finished = true
	if fallback == "markers":
		SoloController.mission_markers = [{}, {}]
	elif fallback == "empty":
		_clear_units()
	var lines: Array = []
	var on_entry := func(e: Dictionary) -> void: lines.append("%d|%s" % [int(e["category"]), str(e["text"])])
	_main.battle_log.entry_added.connect(on_entry)
	CoreActivation._env = 0 if how == "table" else 1
	var h := 0
	if how == "table":
		_main._solo_auto_seize()
		_main._solo_book_mission_vp(_main.opr_army_manager.current_round >= _main._solo_total_rounds())
	else:
		h = _main._solo_core_round_end()
		(_main.solo_controller as SoloController)._core_node_ready().release(h)
		if how == "end_round":
			_main._solo_end_round()
	_main.battle_log.entry_added.disconnect(on_entry)
	return {"owners": _main.terrain_overlay.get_objective_owners(), "vp": SoloController.mission_vp.duplicate(),
		"memo": SoloController.mission_vp_memo.duplicate(), "lines": lines, "path": h != 0 if how == "core" else h == 0}


func test_the_core_round_end_equals_the_tables(timeout := 600000) -> void:
	var bad: Array = []
	var seen := {"seize": 0, "reason": 0}
	for s in 50:
		var table := _round_end(s, "table")
		var core := _round_end(s, "core")
		if table != core:
			bad.append("layout %d:\n  table %s\n  core  %s" % [s, table, core])
		var text := "\n".join(table["lines"])
		seen["seize"] += 1 if text.contains("seized by") or text.contains("goes neutral") else 0
		seen["reason"] += 1 if text.contains("cannot seize or contest") else 0
	print("round gate: %d of 50 layouts differ; %s" % [bad.size(), seen])
	assert_array(bad).is_empty()
	assert_bool(seen["seize"] >= 10 and seen["reason"] >= 5).override_failure_message("layouts too tame: %s" % seen).is_true()
	await E2EBoot.settle(get_tree())


func test_the_core_opener_equals_ai_opens_next_round(timeout := 240000) -> void:
	CoreActivation._env = 1
	var sc: SoloController = _main.solo_controller
	for took_last in [true, false]:
		for wiped in [0, 1, 2]:
			_layout(7, wiped)
			_main._solo_ai_took_last_activation = took_last
			var round_no: int = _main.opr_army_manager.current_round
			var want := SoloController.ai_opens_next_round(took_last, not sc.eligible_units_for(sc.human_slot).is_empty(),
				not sc.eligible_ai_units().is_empty())
			var lines: Array = []
			var on_entry := func(e: Dictionary) -> void: lines.append(str(e["text"]))
			_main.battle_log.entry_added.connect(on_entry)
			var opener: int = _main._solo_core_round_begin(_main._solo_core_round_end())
			_main.battle_log.entry_added.disconnect(on_entry)
			var why := "took_last %s, wiped %d" % [took_last, wiped]
			assert_int(opener).override_failure_message(why).is_equal(sc.ai_slot if want else sc.human_slot)
			assert_str(lines.back()).override_failure_message(why).is_equal("Round %d begins" % (round_no + 1))
	await E2EBoot.settle(get_tree())


func test_markers_and_an_empty_table_are_booked_by_the_table(timeout := 240000) -> void:
	(_main.solo_controller as SoloController)._core_node_ready()   # its one-time warnings stay outside the asserts
	for fallback in ["markers", "empty"]:
		var want := _round_end(3, "table", fallback)
		var got := {}
		await assert_error(func() -> void: got.merge(_round_end(3, "end_round", fallback))).is_success()
		assert_dict(got).override_failure_message("%s: %s" % [fallback, got]).is_equal(want)
	await E2EBoot.settle(get_tree())


func test_a_unit_in_reserve_sends_the_round_begin_to_the_table(timeout := 240000) -> void:
	CoreActivation._env = 1
	_layout(7)
	var held: GameUnit = ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Held", "x_in": 200.0}), RIFLE)
	held.unit_properties["ambush_reserve"] = true
	var h: int = _main._solo_core_round_end()
	assert_int(h).is_not_equal(0)
	var lines: Array = []
	var on_entry := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(on_entry)
	assert_int(_main._solo_core_round_begin(h)).is_equal(0)
	_main.battle_log.entry_added.disconnect(on_entry)
	assert_array(lines).is_empty()
	await E2EBoot.settle(get_tree())
