extends GdUnitTestSuite
## NML-1114: AiRolloutTrace (scripts/solo/rollout_trace.gd) — env NML_ROLLOUT_TRACE=<path>
## writes ONE JSON line per planner pick carrying the per-unit fold behind
## presence_*/tail_*, the two features that diverged in the 28.08. Gate C capture.
## Unset, it must not touch disk and must not perturb the decision the pick logs.

const IN2M := 0.0254
const _TRACE_PATH := "user://rollout_trace_test_tmp.jsonl"


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
	return BattleSim.capture(army, func() -> Array: return [Vector3(3.0 * IN2M, 0, 0)],
		func(_i: int) -> int: return 0, 1, 3)


func _reset() -> void:
	AiRolloutTrace._checked = false
	AiRolloutTrace._stream = null
	AiRolloutTrace._count = 0


func before_test() -> void:
	_reset()
	DirAccess.remove_absolute(_TRACE_PATH)


func after_test() -> void:
	AiRolloutTrace.close()
	OS.set_environment("NML_ROLLOUT_TRACE", "")
	DirAccess.remove_absolute(_TRACE_PATH)


func _lines() -> Array:
	if not FileAccess.file_exists(_TRACE_PATH):
		return []
	var f := FileAccess.open(_TRACE_PATH, FileAccess.READ)
	var out: Array = []
	while not f.eof_reached():
		var l := f.get_line()
		if not l.is_empty():
			out.append(l)
	return out


## ARMED: one pick -> one line, carrying the keys a reader needs to re-derive
## presence_theirs/tail_theirs (per-unit rush band, marker gaps, eligibility).
func test_env_set_writes_one_line_with_the_rollout_inputs() -> void:
	OS.set_environment("NML_ROLLOUT_TRACE", ProjectSettings.globalize_path(_TRACE_PATH))
	var state := _state()
	var features := AiMissionEval.features(state, 1, {}, true)
	AiRolloutTrace.write(state, 1, "A", "A", features)

	var lines := _lines()
	assert_int(lines.size()).is_equal(1)
	var line: Dictionary = JSON.parse_string(lines[0])
	for k in ["kind", "seq", "round", "player", "pick_key", "pick_unit", "objectives",
			"units", "statics", "env", "playout_sig", "features"]:
		assert_bool(line.has(k)).override_failure_message("missing key %s" % k).is_true()
	assert_str(str(line["kind"])).is_equal("pick")
	assert_int((line.get("objectives", []) as Array).size()).is_equal(1)
	var rows: Array = line["units"]
	assert_int(rows.size()).is_equal(2)
	for r in rows:
		var row := r as Dictionary
		for k in ["key", "mine", "alive", "activated", "shaken", "aircraft", "eligible",
				"rush_in", "gaps_in", "pos_xz", "radii_m"]:
			assert_bool(row.has(k)).override_failure_message("missing unit key %s" % k).is_true()
		assert_int((row.get("gaps_in", []) as Array).size()).is_equal(1)   # one gap per marker
	# The logged vector is the decision's own, verbatim.
	assert_float(float((line["features"] as Dictionary)["presence_theirs"])) \
		.is_equal_approx(float(features["presence_theirs"]), 0.0001)
	# The statics block names the caches a divergence would have to be explained by.
	for k in ["fast_planner", "opener_seat", "playout_search", "core", "top_k", "horizon"]:
		assert_bool((line["statics"] as Dictionary).has(k)) \
			.override_failure_message("missing static %s" % k).is_true()


## UNARMED (the shipped default): no file, and the feature vector the decision
## record carries is bit-for-bit what it was before the trace call.
func test_env_unset_writes_nothing_and_leaves_the_decision_identical() -> void:
	OS.set_environment("NML_ROLLOUT_TRACE", "")
	var state := _state()
	var before := AiMissionEval.features(state, 1, {}, true)
	AiRolloutTrace.write(state, 1, "A", "A", before)
	var after := AiMissionEval.features(state, 1, {}, true)

	assert_bool(AiRolloutTrace.active()).is_false()
	assert_bool(FileAccess.file_exists(_TRACE_PATH)).is_false()
	assert_str(JSON.stringify(after, "", true, true)) \
		.is_equal(JSON.stringify(before, "", true, true))
