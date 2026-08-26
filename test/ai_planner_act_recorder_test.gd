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
	var pick := {"used": true, "unit_key": "A", "action": {"unit": "A", "kind": AiDecision.Action.HOLD}}
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
	# ordered pair, both directions, opposite sides only — A|B and B|A, never A|A/B|B
	var ci := act["charge_illegal"] as Dictionary
	assert_bool(ci.has("A|B")).is_true()
	assert_bool(ci.has("B|A")).is_true()
	assert_int(ci.size()).is_equal(2)
