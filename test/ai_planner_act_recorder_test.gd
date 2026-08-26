extends GdUnitTestSuite
## NML-1073 M2-0a: AiActRecorder (scripts/solo/act_recorder.gd) captures every
## planner ACTIVATION — the full input the search read (state, charge-illegal
## matrix, statics) plus the pick it returned — as one JSON line, preceded by
## a one-time header line (per-unit profiles, terrain, search knobs). Same
## contract shape as the existing per-node dump (ai_planner.gd NML_NODE_DUMP),
## just per-activation instead of per-node. NML_ACT_DUMP unset never touches
## disk (begin() returns {} on the cached env check) — not re-asserted here,
## the existing NML_NODE_DUMP recorder already covers that pattern.

const IN2M := 0.0254
const _DUMP_DIR := "user://act_recorder_test_tmp"


func _armed(pid: int, positions: Array, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = 1
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	var ow := OPRApiClient.OPRWeapon.new()
	ow.name = "CCW"
	ow.range_value = 0
	ow.attacks = 4
	ow.count = 1
	opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr
	return u


func _state() -> Dictionary:
	var a := _armed(1, [Vector3.ZERO], "A")
	var b := _armed(2, [Vector3(6.0 * IN2M, 0, 0)], "B")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"A": a, "B": b}
	var state := BattleSim.capture(army, func() -> Array: return [],
		func(_i: int) -> int: return 0, 1, 3)
	state["charge_illegal"] = func(_at: GameUnit, _vt: GameUnit, _gap: float,
		_ca: Vector3, _cb: Vector3) -> bool: return false
	return state


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(_DUMP_DIR)
	OS.set_environment("NML_ACT_DUMP", ProjectSettings.globalize_path(_DUMP_DIR))
	# AiActRecorder's env check + open stream are cached STATIC state (by
	# design — the real game opens the file once per process) — reset it per
	# test so two test_ functions in this suite do not share one header/stream.
	AiActRecorder._checked = false
	AiActRecorder._stream = null
	AiActRecorder._header_written = false
	AiActRecorder._count = 0
	AiPlanner.trace = {}


func after_test() -> void:
	OS.set_environment("NML_ACT_DUMP", "")
	var d := DirAccess.open(_DUMP_DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(_DUMP_DIR)


## begin() before the pick, finish() after — one header line + one act line,
## every key from the M2-0a spec present and parsable.
func test_begin_and_finish_write_header_and_act_line() -> void:
	var state := _state()
	var pool: Array = [(state["units"]["A"] as Dictionary)["unit"]]
	var pending := AiActRecorder.begin(state, 1, pool, Callable())
	assert_bool(pending.is_empty()).is_false()
	# NML-1073 M2-0b: a Vector3 "dest" in the picked action — the 0a finding
	# was that this reached JSON as JSON.stringify's native "(x, y, z)"
	# STRING, unparsable back into numbers, unlike every other Vector3 this
	# recorder writes via BattleSim._plain_vec3.
	var pick := {"used": true, "unit_key": "A", "action": {"unit": "A",
		"kind": AiDecision.Action.RUSH, "dest": Vector3(1.0, 2.0, 3.0)}}
	AiActRecorder.finish(pending, pick)

	var f := FileAccess.open(_DUMP_DIR.path_join("acts.jsonl"), FileAccess.READ)
	assert_object(f).is_not_null()
	var lines: Array = []
	while not f.eof_reached():
		var line := f.get_line()
		if line != "":
			lines.append(line)
	f.close()
	assert_int(lines.size()).is_equal(2)

	var header := JSON.parse_string(lines[0]) as Dictionary
	assert_str(str(header.get("kind", ""))).is_equal("header")
	assert_bool(header.has("profiles")).is_true()
	assert_bool((header["profiles"] as Dictionary).has("A")).is_true()
	var a_profile := (header["profiles"] as Dictionary)["A"] as Dictionary
	assert_bool(a_profile.has("shooting_range_bonus")).is_true()
	assert_bool(a_profile.has("max_activation_advance_bonus_in")).is_true()
	assert_bool(header.has("knobs")).is_true()
	for knob in ["top_k", "horizon", "tail_cap_p1", "tail_cap_p2", "imagined_round_end",
			"depth_discount", "seat_mode", "playout_margin", "playout_rich",
			"seam_cast", "seam_spacing"]:
		assert_bool((header["knobs"] as Dictionary).has(knob)).is_true()
	assert_object(header.get("terrain")).is_null()   # no terrain_type_at seam in this fixture

	var act := JSON.parse_string(lines[1]) as Dictionary
	assert_str(str(act.get("kind", ""))).is_equal("act")
	for key in ["round", "player", "statics", "state", "charge_illegal", "pool", "pick"]:
		assert_bool(act.has(key)).is_true()
	assert_int(int(act["round"])).is_equal(1)
	assert_int(int(act["player"])).is_equal(1)
	assert_array(act["pool"] as Array).contains(["A"])
	assert_bool(bool((act["pick"] as Dictionary).get("used", false))).is_true()
	var pick_dest = ((act["pick"] as Dictionary)["action"] as Dictionary)["dest"]
	assert_bool(pick_dest is Array).is_true()
	assert_array(pick_dest as Array).is_equal([1.0, 2.0, 3.0])
	# ordered pair, both directions, opposite sides only — A|B and B|A, never A|A/B|B
	var ci := act["charge_illegal"] as Dictionary
	assert_bool(ci.has("A|B")).is_true()
	assert_bool(ci.has("B|A")).is_true()
	assert_int(ci.size()).is_equal(2)
	# NML-1073 M2-0d: the same pairs over the GAP GRID (the oracle the pure gate is
	# diffed against), plus the per-unit gate reads inside the plain state.
	var grid := act["charge_illegal_grid"] as Dictionary
	assert_int(grid.size()).is_equal(2)
	assert_int((grid["A|B"] as Array).size()).is_equal(AiActRecorder.GATE_GRID_STEPS)
	var a_state := ((act["state"] as Dictionary)["units"] as Dictionary)["A"] as Dictionary
	assert_bool(a_state.has("charge_probe_r")).is_true()
	assert_bool(a_state.has("charge_no_difficult")).is_true()
	assert_bool(a_state.has("bands")).is_true()


## NML-1073 M2-0b: plan_with_rollout's search TRACE — root menus, the sorted
## 1-ply list, the rollout pool, every pool candidate's rolled score, and the
## winner/runner-up — rides on AiActRecorder.finish()'s act line, gated by
## AiActRecorder.active() (env NML_ACT_DUMP set, true here). top_k=1 keeps the
## rollout pool to exactly A's own best candidate — the only engaged unit on
## this objective-less fixture, where _safe_advance/_second_wave both return
## {} for both units — so len(menus) == len(pool_idx) == 1 is provable, and
## with a single-candidate pool no runner is ever set (runner_idx == -1).
func test_trace_carries_search_and_flattens_menu_dests() -> void:
	var state := _state()
	var pool: Array = [(state["units"]["A"] as Dictionary)["unit"]]
	var pending := AiActRecorder.begin(state, 1, pool, Callable())
	var pick := AiPlanner.plan_with_rollout(state, 1, 1)
	AiActRecorder.finish(pending, pick)

	var f := FileAccess.open(_DUMP_DIR.path_join("acts.jsonl"), FileAccess.READ)
	var lines: Array = []
	while not f.eof_reached():
		var line := f.get_line()
		if line != "":
			lines.append(line)
	f.close()
	var act := JSON.parse_string(lines[1]) as Dictionary
	assert_bool(act.has("trace")).is_true()
	var trace := act["trace"] as Dictionary
	for key in ["menus", "scored", "pool_idx", "rs", "best_idx", "runner_idx", "arbitration"]:
		assert_bool(trace.has(key)).is_true()
	var menus := trace["menus"] as Dictionary
	var pool_idx := trace["pool_idx"] as Array
	assert_bool(menus.has("A")).is_true()
	assert_int(menus.size()).is_equal(pool_idx.size())
	assert_int(int(trace["best_idx"])).is_equal(0)
	assert_int(int(trace["runner_idx"])).is_equal(-1)
	assert_object(trace["arbitration"]).is_null()   # playout_search is off by default
	for cand in (menus["A"] as Array):
		var dest = (cand as Dictionary).get("dest")
		if dest != null:
			assert_bool(dest is Array).is_true()
			assert_int((dest as Array).size()).is_equal(3)


## NML-1073 M2-0d: BattleSim.charge_illegal_plain reproduces
## SoloController.charge_candidate_illegal (solo_controller.gd:1434-1447) from the
## CAPTURE alone — no GameUnit, no live overlay. Every gate line has its own case:
## the aircraft veto, the rush band (incl. Melee Shrouding), the 6" difficult cap and
## its Strider/Flying exemption, and the terrain corridor via the header Callable.
func test_charge_illegal_plain_is_a_pure_function_of_the_capture() -> void:
	var board := {"units": {
		"A": {"positions": [[0.0, 0.0, 0.0]], "alive": 1, "player": 1, "aircraft": false,
			"bands": {"advance": 6.0, "rush": 12.0},
			"charge_probe_r": 0.016, "charge_no_difficult": false},
		"B": {"positions": [[6.0 * IN2M, 0.0, 0.0]], "alive": 1, "player": 2, "aircraft": false,
			"bands": {"advance": 6.0, "rush": 12.0},
			"charge_probe_r": 0.016, "charge_no_difficult": false},
		"P": {"positions": [[6.0 * IN2M, 0.0, 0.0]], "alive": 1, "player": 2, "aircraft": true,
			"bands": {"advance": 6.0, "rush": 12.0},
			"charge_probe_r": 0.016, "charge_no_difficult": false},
		"S": {"positions": [[6.0 * IN2M, 0.0, 0.0]], "alive": 1, "player": 2, "aircraft": false,
			"bands": {"advance": 6.0, "rush": 12.0}, "shroud": [3.0, 6.0],
			"charge_probe_r": 0.016, "charge_no_difficult": false}}}
	var open_board := {}   # no header terrain seam = no difficult ground anywhere

	# 6" apart in the open, 12" rush band: a 5" gap is inside the band AND under the
	# 6" difficult cap -> legal. 13" is past the band -> illegal.
	assert_bool(BattleSim.charge_illegal_plain(board, open_board, "A", "B", 5.0)).is_false()
	assert_bool(BattleSim.charge_illegal_plain(board, open_board, "A", "B", 13.0)).is_true()
	# Aircraft victim: the gate's first line, illegal at any gap.
	assert_bool(BattleSim.charge_illegal_plain(board, open_board, "A", "P", 0.0)).is_true()
	# Melee Shrouding -3" to a floor of 6": the 12" band reaches 9", not 9.5".
	assert_bool(BattleSim.charge_illegal_plain(board, open_board, "A", "S", 9.0)).is_false()
	assert_bool(BattleSim.charge_illegal_plain(board, open_board, "A", "S", 9.5)).is_true()

	# All-forest board: over the cap, every corridor (straight + both 4" doglegs)
	# crosses difficult ground -> capped out; under the cap the rule never triggers.
	var forest := {"terrain_at": func(_p: Vector3) -> int: return TerrainRules.TerrainType.FOREST}
	assert_bool(BattleSim.charge_illegal_plain(board, forest, "A", "B", 10.0)).is_true()
	assert_bool(BattleSim.charge_illegal_plain(board, forest, "A", "B", 5.0)).is_false()
	# Strider/Flying ignore difficult (p.13).
	(board["units"]["A"] as Dictionary)["charge_no_difficult"] = true
	assert_bool(BattleSim.charge_illegal_plain(board, forest, "A", "B", 10.0)).is_false()
