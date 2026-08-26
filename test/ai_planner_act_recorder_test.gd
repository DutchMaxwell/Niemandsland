extends GdUnitTestSuite

const ActRecheck := preload("res://tools/act_recheck.gd")   ## NML-1073 M3-0b
const NodeRecheck := preload("res://tools/node_recheck.gd")   ## NML-1073 M3-0c
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
	# NML-1073 M2-0b: close the stream AND the planner's statics now. The
	# fixture's state carries a charge_illegal LAMBDA bound to this suite;
	# plan_with_rollout parks the winning leaf (that same state) in
	# AiPlanner._last_leaf_state, and a lambda still sitting in a script static
	# when the process tears down is freed after its script instance is gone —
	# the measured "corrupted size vs. prev_size in fastbins" (exit 134) that
	# turned CI red AFTER a fully green suite.
	AiActRecorder.close()
	AiPlanner.close()
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
	# NML-1073 M2-5b: the header is STATIC-only. The two SoloController bonuses
	# used to be stamped on here; both are live reads (shooting_range_bonus sums
	# unit_properties["spell_range_mod"] verbatim, and both walk special_rules),
	# so they moved into the per-ACTIVATION block asserted below.
	assert_bool(a_profile.has("shooting_range_bonus")).is_false()
	assert_bool(a_profile.has("max_activation_advance_bonus_in")).is_false()
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
	# NML-1073 M2-5b: every unit of every act carries the DYNAMIC half of its
	# profile — the fields a live game rewrites between two activations.
	var a_dyn := (((act["state"] as Dictionary)["units"] as Dictionary)["A"]
		as Dictionary)["prof"] as Dictionary
	for k in ["special_rules", "tough", "caster_value", "item_grants",
			"attached_hero_rules", "shooting_range_bonus", "max_activation_advance_bonus_in"]:
		assert_bool(a_dyn.has(k)).is_true()
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


## NML-1073 M2-5b: a hero that FALLS stops lending its rules to the unit it
## joined. `AiEv.rule_on_all_models` (ai_ev.gd:79-83) only asks the ALIVE
## attached heroes, so the host GAINS every unit-wide rule the dead hero lacked
## — and the recorder has to say so on the very next activation, not at the next
## game. The header's copy is taken once and cannot.
func test_a_dead_attached_hero_drops_out_of_the_per_act_profile() -> void:
	var host := _armed(1, [Vector3.ZERO], "H")
	host.unit_properties["special_rules"] = ["Shielded"]
	var hero := _armed(1, [Vector3(0.02, 0, 0)], "X")
	hero.unit_properties["special_rules"] = ["Hero", "Tough(3)"]   # no Shielded
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host

	var alive := BattleSim.unit_profile_dyn(host)
	assert_array(alive["attached_hero_rules"] as Array).is_equal([["Hero", "Tough(3)"]])
	assert_bool(AiEv.rule_on_all_models(host, "Shielded")).is_false()

	for m in hero.models:
		(m as ModelInstance).is_alive = false
	var fallen := BattleSim.unit_profile_dyn(host)
	assert_array(fallen["attached_hero_rules"] as Array).is_empty()
	assert_bool(AiEv.rule_on_all_models(host, "Shielded")).is_true()
	# and the STATIC half is untouched by the death — it is the same unit
	assert_array(fallen["special_rules"] as Array).is_equal(["Shielded"])


## NML-1073 M3-0b: state_to_plain must carry a DORMANT (Ambush-reserve) unit's
## snapshot verbatim — capture() already writes "dormant"/"dormant_models"/
## "dormant_wounds"/"earliest_arrival_round" on it (battle_sim.gd:1346-1351)
## and _UNIT_DYNAMIC already lists all four; this pins the contract so a
## future edit to either list can't silently drop a reserve unit from a
## core_selfplay act (arena corpora never carry one to catch the regression).
func test_state_to_plain_keeps_a_dormant_reserve_unit() -> void:
	var a := _armed(1, [Vector3.ZERO], "A")
	var r := _armed(2, [Vector3(6.0 * IN2M, 0, 0)], "R")
	r.unit_properties["ambush_reserve"] = true
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"A": a, "R": r}
	var state := BattleSim.capture(army, func() -> Array: return [],
		func(_i: int) -> int: return 0, 1, 3)
	var plain := BattleSim.state_to_plain(state, false)
	assert_bool((plain["units"] as Dictionary).has("R")).is_true()
	var pr := (plain["units"] as Dictionary)["R"] as Dictionary
	assert_bool(bool(pr.get("dormant", false))).is_true()
	assert_int(int(pr.get("alive", -1))).is_equal(0)
	assert_int(int(pr.get("dormant_models", -1))).is_equal(1)
	assert_array(pr.get("dormant_wounds", []) as Array).is_equal([1])
	assert_int(int(pr.get("earliest_arrival_round", -1))).is_equal(2)


## NML-1073 M3-0b: los_pairs must be ordered by a STABLE KEY (unit id, sorted),
## never by Dictionary insertion order — a live Dictionary preserves insertion
## order, but the recorded corpus round-trips through JSON.stringify's
## sort_keys, which comes back key-sorted; a writer that iterates raw
## insertion order and a reader that assumes key-sorted order silently swap
## rows/cols past ~10 units (the M1-6 trap: "U10" sorts before "U2"). Three
## units inserted OUT of key-sorted order (U9, U10, U2) pin the writer
## against a hand-computed grid over the SORTED key order (U10, U2, U9).
func test_los_pairs_is_ordered_by_sorted_unit_key() -> void:
	var u9 := _armed(1, [Vector3(9.0 * IN2M, 0, 0)], "U9")
	var u10 := _armed(1, [Vector3(10.0 * IN2M, 0, 0)], "U10")
	var u2 := _armed(2, [Vector3(2.0 * IN2M, 0, 0)], "U2")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"U9": u9, "U10": u10, "U2": u2}
	var state := BattleSim.capture(army, func() -> Array: return [],
		func(_i: int) -> int: return 0, 1, 3)
	state["los_blocked"] = func(from: Vector3, to: Vector3) -> bool: return from.x > to.x
	var plain := BattleSim.state_to_plain(state, false)
	assert_array(plain["los_pairs"] as Array).is_equal(["100", "111", "101"])


## NML-1073 M3-0b: a core_selfplay-shaped state — NO "charge_illegal" wired, exactly
## like tools/core_selfplay.gd (SoloController wires SoloController.charge_candidate_illegal
## at solo_controller.gd:3002/:3358/:3475/:3704; core_selfplay never does) — must record
## charge_gate=false, and act_recheck.gd's own decision (_stamps_charge_gate) must read that
## false back and skip stamping the pure gate, replaying the live search (which never gated
## charges) instead of manufacturing a veto it never applied. The M3-0b root-cause fix's
## round trip, recorder to recheck, in one test.
func test_a_gateless_activation_records_and_replays_without_the_charge_gate() -> void:
	var state := _state()
	state.erase("charge_illegal")   # core_selfplay never wires one
	var pool: Array = [(state["units"]["A"] as Dictionary)["unit"]]
	var pending := AiActRecorder.begin(state, 1, pool, Callable())
	var pick := {"used": true, "unit_key": "A", "action": {"unit": "A",
		"kind": AiDecision.Action.RUSH, "dest": Vector3.ZERO}}
	AiActRecorder.finish(pending, pick)

	var f := FileAccess.open(_DUMP_DIR.path_join("acts.jsonl"), FileAccess.READ)
	var lines: Array = []
	while not f.eof_reached():
		var line := f.get_line()
		if line != "":
			lines.append(line)
	f.close()
	var act := JSON.parse_string(lines[1]) as Dictionary
	assert_bool(bool(act.get("charge_gate", true))).is_false()
	assert_bool(ActRecheck._stamps_charge_gate(act)).is_false()
	# a pre-M3-0b corpus (no "charge_gate" key at all) must default to true — unchanged
	assert_bool(ActRecheck._stamps_charge_gate({})).is_true()


## NML-1073 M3-0c: a state whose insertion order differs from SORTED key order
## must round-trip through state_to_plain() + NodeRecheck._rebuild_state() with
## the SAME (non-sorted) keys() order it had live — the root cause this fixes:
## the recorded "units" JSON round-trips key-sorted (JSON.stringify's
## sort_keys), and ai_planner.gd's root search walks `for key in
## state["units"]`, so a rebuild that leans on plain_units' own (sorted) order
## hands the search a DIFFERENT unit than the one the recorded pick chose. Three
## units inserted OUT of key-sorted order (U9, U10, U2) pin both halves of the
## fix: state_to_plain's "unit_order" and _rebuild_state's reinsertion. The
## JSON round-trip (JSON.stringify(sort_keys=true) -> JSON.parse_string, the
## EXACT act_recorder.gd/act_recheck.gd pipeline) is load-bearing here — a live
## GDScript Dictionary never loses insertion order on its own, so skipping the
## round-trip would pass even with the bug (caught once by hand against a
## temporary "ignore unit_order" edit: this test still passed without it).
func test_unit_order_round_trips_through_plain_form_and_rebuild() -> void:
	var u9 := _armed(1, [Vector3(9.0 * IN2M, 0, 0)], "U9")
	var u10 := _armed(1, [Vector3(10.0 * IN2M, 0, 0)], "U10")
	var u2 := _armed(2, [Vector3(2.0 * IN2M, 0, 0)], "U2")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"U9": u9, "U10": u10, "U2": u2}
	var state := BattleSim.capture(army, func() -> Array: return [],
		func(_i: int) -> int: return 0, 1, 3)
	var plain := BattleSim.state_to_plain(state, false)
	assert_array(plain.get("unit_order", []) as Array).is_equal(["U9", "U10", "U2"])
	# the same JSON round trip act_recorder.gd writes (JSON.stringify(..., "",
	# true, true) = sort_keys) and act_recheck.gd reads back — this is what
	# actually reorders "units" to U10/U2/U9; a bare in-memory Dictionary never
	# forgets its insertion order on its own.
	var round_tripped: Dictionary = JSON.parse_string(JSON.stringify(plain, "", true, true))

	var profiles := {}
	for uid in (state["units"] as Dictionary):
		profiles[uid] = BattleSim._unit_profile((state["units"][uid] as Dictionary)["unit"])
	var rebuilt := NodeRecheck._rebuild_state(round_tripped, profiles)
	assert_array((rebuilt["units"] as Dictionary).keys()).is_equal(["U9", "U10", "U2"])
