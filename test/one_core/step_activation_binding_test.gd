extends GdUnitTestSuite
## One-core P3 step 16: the Godot binding of the core's activation step API, `NmlCore.step_activation`.
## The table sends the ordered inputs (begin, intent, faces); the core answers need_roll / done / refused.
## Real: the NmlCore extension (the CI shards build and load it; a missing core fails
## test/core_extension_loaded_test.gd instead of skipping these cases), BattleSim.capture + state_to_plain.
## Constructed: two bare units, one weapon on "a".

const IN2M := 0.0254

var _core: Object
var _h := 0
var _plain: Dictionary


func before_test() -> void:
	_core = ClassDB.instantiate("NmlCore")
	var a := _unit(1, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)], "a")
	var b := _unit(2, [Vector3(10.0 * IN2M, 0, 0), Vector3(11.0 * IN2M, 0, 0), Vector3(12.0 * IN2M, 0, 0)], "b")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"a": a, "b": b}
	var state := BattleSim.capture(army, func() -> Array: return [], func(_i: int) -> int: return 0, 1, 4)
	_plain = BattleSim.state_to_plain(state)
	(_plain["units"]["a"]["profile"] as Dictionary)["weapons"] = [
		{"name": "Rifle", "range": 24.0, "attacks": 6, "count": 3, "ap": 0, "rules": []}]
	_h = _core.capture_plain(_plain)


## battle_sim_capture_test.gd:10-24 (copy, don't import); the nodes sit in the tree so global_position reads.
func _unit(pid: int, positions: Array, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4, "special_rules": []}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n: Node3D = auto_free(Node3D.new())
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


func test_a_hold_and_shoot_activation_runs_to_done_and_reports_the_landing() -> void:
	var t: Array = [{"t": "begin"}, {"t": "intent", "kind": 0, "shoot": "b"}]
	var r: Dictionary = _core.step_activation(_h, "a", t, false)
	var rolls := 0
	while r["step"] == "need_roll" and rolls < 20:
		rolls += 1
		var faces: Array = []
		for i in int(r["faces"]):
			faces.append(6 if r["kind"] == "attack" else 1)   # every attack hits, every save fails
		t.append({"t": "faces", "faces": faces})
		r = _core.step_activation(_h, "a", t, false)
	assert_str(r["step"]).is_equal("done")
	assert_int(rolls).is_greater(0)
	# The new handle holds the state after the volley: all three models of "b" are gone.
	assert_int(int(_core.plain_of(int(r["handle"]))["units"]["b"]["alive"])).is_equal(0)
	# The landing names the unit and keeps each model's start position (x in inches 10, 11, 12; metres here).
	var landing: Dictionary = (r["landings"] as Array)[0]
	assert_str(landing["unit"]).is_equal("b")
	var xs: Array = []
	for m in landing["models"]:
		xs.append((m["at"] as Vector3).x)
		assert_bool(m["dead"]).is_true()
	xs.sort()
	assert_int(xs.size()).is_equal(3)
	for i in 3:
		assert_float(xs[i]).is_equal_approx((10.0 + i) * IN2M, 0.0001)
	# The done answer carries the delta: only "b" changed - its three models are gone, nobody moved.
	var delta: Array = r["delta"]
	assert_int(delta.size()).is_equal(1)
	assert_str(delta[0]["unit"]).is_equal("b")
	assert_int(int(delta[0]["alive"])).is_equal(0)
	var removed: Array = (delta[0]["removed"] as Array).duplicate()
	removed.sort()
	assert_array(removed).is_equal([0, 1, 2])


func test_an_input_the_core_does_not_know_is_refused_with_its_index() -> void:
	var r: Dictionary = _core.step_activation(_h, "a", [{"t": "begin"}, {"t": "wat"}], false)
	assert_str(r["step"]).is_equal("refused")
	assert_int(int(r["index"])).is_equal(1)
	assert_str(r["reason"]).is_equal("input 1 is not understood")


func test_an_unknown_handle_is_refused() -> void:
	var r: Dictionary = _core.step_activation(9999, "a", [{"t": "begin"}], false)
	assert_str(r["step"]).is_equal("refused")
	assert_str(r["reason"]).is_equal("unknown handle")


## Rolls a started activation to its end: `faces_for(roll_no, step)` answers every need_roll (roll_no counts from 0).
func _drive(t: Array, faces_for: Callable) -> Dictionary:
	var r: Dictionary = _core.step_activation(_h, "a", t, false)
	var n := 0
	while r["step"] == "need_roll" and n < 20:
		t.append({"t": "faces", "faces": faces_for.call(n, r)})
		n += 1
		r = _core.step_activation(_h, "a", t, false)
	return r


func test_the_delta_reports_casualties_and_shaken_of_a_partial_volley() -> void:
	# Roll 0 = attacks (all hit), roll 1 = saves (the first two fail), roll 2 = the morale test (fails).
	var faces_for := func(n: int, r: Dictionary) -> Array:
		var f: Array = []
		for i in int(r["faces"]):
			f.append(6 if n == 0 else (1 if n == 2 or i < 2 else 6))
		return f
	var r := _drive([{"t": "begin"}, {"t": "intent", "kind": 0, "shoot": "b"}], faces_for)
	assert_str(r["step"]).is_equal("done")
	var delta: Array = r["delta"]
	assert_int(delta.size()).is_equal(1)
	assert_str(delta[0]["unit"]).is_equal("b")
	assert_int(int(delta[0]["alive"])).is_equal(1)
	assert_int((delta[0]["removed"] as Array).size()).is_equal(2)
	assert_bool(delta[0]["shaken"]).is_true()
	assert_bool(delta[0]["moved"]).is_false()
	assert_bool(delta[0]["unknown"]).is_false()


func test_the_delta_marks_a_unit_that_moved() -> void:
	var to := [Vector3(3.0 * IN2M, 0, 0), Vector3(4.0 * IN2M, 0, 0), Vector3(5.0 * IN2M, 0, 0)]
	var r := _drive([{"t": "begin"}, {"t": "intent", "kind": 1, "shoot": ""}, {"t": "placed", "positions": to}], func(_n: int, _r: Dictionary) -> Array: return [])
	assert_str(r["step"]).is_equal("done")
	var delta: Array = r["delta"]
	assert_int(delta.size()).is_equal(1)
	assert_str(delta[0]["unit"]).is_equal("a")
	assert_bool(delta[0]["moved"]).is_true()
	assert_bool(delta[0]["unknown"]).is_false()
	assert_int(int(delta[0]["alive"])).is_equal(3)
	assert_array(delta[0]["removed"]).is_empty()


func test_the_move_allowance_of_a_unit_is_its_own_band_and_names_no_rule_for_a_plain_one() -> void:
	# A band that is not the default 6/12 (a constant answer or an Advance/Rush swap shows).
	var p := _plain.duplicate(true)
	(p["units"]["a"]["bands"] as Dictionary)["advance"] = 5.0
	(p["units"]["a"]["bands"] as Dictionary)["rush"] = 11.0
	var a: Dictionary = _core.move_allowance(_core.capture_plain(p), "a")
	assert_float(a["advance"]).is_equal(5.0)
	assert_float(a["rush"]).is_equal(11.0)
	assert_float(a["charge"]).is_equal(11.0)
	assert_array(a["widened_by"]).is_empty()
	# And the default unit: 6 / 12.
	var d: Dictionary = _core.move_allowance(_h, "a")
	assert_float(d["advance"]).is_equal(6.0)
	assert_float(d["rush"]).is_equal(12.0)


func test_the_move_allowance_of_an_unknown_unit_or_handle_is_empty_with_a_reason() -> void:
	assert_dict(_core.move_allowance(_h, "zzz")).is_empty()
	assert_str(_core.last_error()).is_equal("unknown unit")
	assert_dict(_core.move_allowance(9999, "a")).is_empty()
	assert_str(_core.last_error()).is_equal("unknown handle")
