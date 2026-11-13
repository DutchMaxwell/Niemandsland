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


## ---- the header's rules epoch reaches `resolve` and `step_activation` ----
## `seams_now()` carried no epoch, so every epoch-gated rule was OFF inside both calls (plan_inner read the header's).
## Probe rule: Speed Feat (epoch 7) - in the endgame its bearer's once-per-game bonus is +2" Advance. Here "a" (orc_marauders,
## round 4 of 4) has a 6" Advance band, so 8" with the epoch and 6" without it.

## A fresh core with a game header stamped `epoch`, and a handle on "a" (a Speed Feat bearer, 3 models) and "b" (30" away).
func _headed_handle(core: Object, epoch: int) -> int:
	var a := _unit(1, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)], "a")
	var b := _unit(2, [Vector3(30.0 * IN2M, 0, 0), Vector3(31.0 * IN2M, 0, 0), Vector3(32.0 * IN2M, 0, 0)], "b")
	for u in [a, b]:   # the header's rules registry needs a system (e2e_core_ledger_seam_test.gd `_unit`)
		(u as GameUnit).unit_properties["game_system"] = "gf"
		(u as GameUnit).unit_properties["faction_folder"] = "orc_marauders"
	a.unit_properties["special_rules"] = ["Speed Feat"]
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"a": a, "b": b}
	var state := BattleSim.capture(army, func() -> Array: return [], func(_i: int) -> int: return 0, 4, 4)
	var head: Dictionary = AiActRecorder._header_line(state, Callable())
	(head["knobs"] as Dictionary)["rules_epoch"] = epoch
	assert_bool(core.set_game_header(head)).override_failure_message("set_game_header: " + str(core.last_error())).is_true()
	var h: int = core.capture_plain(BattleSim.state_to_plain(state))
	assert_int(h).override_failure_message("capture_plain: " + str(core.last_error())).is_not_equal(0)
	return h


## "a"'s centre x (inches) after `resolve` sent it to x = 11" (its start centre is 1"): the Advance band clamps it.
func _centre_x_after_advance(epoch: int) -> float:
	var core: Object = ClassDB.instantiate("NmlCore")
	var h := _headed_handle(core, epoch)
	var h2: int = core.resolve(h, {"kind": AiDecision.Action.ADVANCE, "unit": "a", "dest": Vector3(11.0 * IN2M, 0, 0)})
	assert_int(h2).override_failure_message("resolve: " + str(core.last_error())).is_not_equal(0)
	var sum := 0.0
	var positions: Array = core.plain_of(h2)["units"]["a"]["positions"]
	for p in positions:
		sum += float((p as Array)[0])
	return sum / positions.size() / IN2M


func test_resolve_reads_the_headers_rules_epoch() -> void:
	assert_float(_centre_x_after_advance(76)).override_failure_message(
		"epoch 76: Speed Feat widens the Advance band to 8\" (centre 1\" -> 9\")").is_equal_approx(9.0, 0.05)
	assert_float(_centre_x_after_advance(6)).override_failure_message(
		"epoch 6: no Speed Feat, the 6\" Advance band (centre 1\" -> 7\")").is_equal_approx(7.0, 0.05)


## One Advance whose three models all go `inches` east, enforcing the movement limit; the core's answer.
func _advance(epoch: int, inches: float) -> Dictionary:
	var core: Object = ClassDB.instantiate("NmlCore")
	var h := _headed_handle(core, epoch)
	var placed: Array = []
	for i in 3:
		placed.append(Vector3((float(i) + inches) * IN2M, 0, 0))
	var t: Array = [{"t": "begin"}, {"t": "placed", "positions": placed}, {"t": "intent", "kind": AiDecision.Action.ADVANCE}]
	return core.step_activation(h, "a", t, true)


func test_step_activation_reads_the_headers_rules_epoch() -> void:
	var r := _advance(76, 7.0)
	assert_str(str(r.get("reason", ""))).override_failure_message(
		"epoch 76: Speed Feat makes 7\" a legal Advance, got " + str(r)).not_contains("allowance")
	# Controls: past the feat's 8" it is refused with the widened band named, and below epoch 7 the 6" band refuses 7".
	assert_str(str(_advance(76, 9.0).get("reason", ""))).contains("the Advance allowance is 8.0")
	assert_str(str(_advance(6, 7.0).get("reason", ""))).contains("the Advance allowance is 6.0")


## `move_allowance` reads the header's rules epoch as well (it handed the core `seams_now()`, epoch 0): the Speed Feat bearer
## "a" (round 4 of 4) has 8" Advance at epoch 76 and names the feat, and the plain 6" below epoch 7.
func test_move_allowance_reads_the_headers_rules_epoch() -> void:
	var core: Object = ClassDB.instantiate("NmlCore")
	var a: Dictionary = core.move_allowance(_headed_handle(core, 76), "a")
	assert_float(a["advance"]).override_failure_message("epoch 76: Speed Feat widens the Advance band to 8.0, got " + str(a)).is_equal(8.0)
	assert_array(a["widened_by"]).is_equal(["Speed Feat"])
	var old: Object = ClassDB.instantiate("NmlCore")
	var b: Dictionary = old.move_allowance(_headed_handle(old, 6), "a")
	assert_float(b["advance"]).is_equal(6.0)
	assert_array(b["widened_by"]).is_empty()


## ---- step 18: `check_move` and `check_begin` ----

## A drop of "a" (models at x = 0", 1", 2"): every model goes `dx` inches east; `trails` as given (per model).
func _drop(mode: int, dx: float, trails: Array = []) -> Dictionary:
	var placed := PackedVector3Array()
	for i in 3:
		placed.append(Vector3((float(i) + dx) * IN2M, 0, 0))
	return {"mode": mode, "positions": placed, "trails": trails}


func test_an_enforced_drop_past_the_band_is_refused_with_the_sentence() -> void:
	var r: Dictionary = _core.check_move(_h, "a", _drop(1, 13.0), true)
	assert_bool(r["ok"]).is_false()
	assert_str(str(r.get("reason", ""))).is_equal("a: a model moved 13.0\" - the Advance allowance is 6.0\".")
	var inside: Dictionary = _core.check_move(_h, "a", _drop(1, 5.0), true)
	assert_bool(inside["ok"]).is_true()
	assert_array(inside.get("lines", [1])).is_empty()
	# The mode number picks the band: 11" is a legal Rush (12") and an illegal Advance (6").
	assert_bool(_core.check_move(_h, "a", _drop(2, 11.0), true)["ok"]).is_true()
	assert_bool(_core.check_move(_h, "a", _drop(1, 11.0), true)["ok"]).is_false()
	assert_str(str(_core.check_move(_h, "a", _drop(3, 13.0), true).get("reason", ""))).contains("the Charge allowance is 12.0")


func test_an_overrun_with_enforce_off_is_accepted_with_one_line() -> void:
	var r: Dictionary = _core.check_move(_h, "a", _drop(1, 13.0), false)
	assert_bool(r["ok"]).is_true()
	var lines: Array = r.get("lines", [])
	assert_int(lines.size()).is_equal(1)
	assert_str(lines[0]["rule"]).is_equal("move_overrun")
	assert_str(lines[0]["text"]).is_equal("a: a model moved 13.0\" - the Advance allowance is 6.0\".")


## Model 0 walks 5" east, then 2" along z: 7" walked, chord 5.39" - inside the 6" band by its chord, outside by its walk.
func test_the_walked_path_of_a_trail_is_measured_not_its_chord() -> void:
	var placed := PackedVector3Array([Vector3(5.0 * IN2M, 0, 2.0 * IN2M), Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)])
	var trail := PackedVector2Array([Vector2(0, 0), Vector2(5.0 * IN2M, 0), Vector2(5.0 * IN2M, 2.0 * IN2M)])
	var with_trail := {"mode": 1, "positions": placed, "trails": [trail, PackedVector2Array(), PackedVector2Array()]}
	var r: Dictionary = _core.check_move(_h, "a", with_trail, true)
	assert_bool(r["ok"]).is_false()
	assert_str(str(r.get("reason", ""))).is_equal("a: a model moved 7.0\" - the Advance allowance is 6.0\".")
	assert_bool(_core.check_move(_h, "a", {"mode": 1, "positions": placed}, true)["ok"]).is_true()
	# A trail that does not end at the placed model is refused as such.
	var off := PackedVector2Array([Vector2(0, 0), Vector2(5.0 * IN2M, 0), Vector2(5.0 * IN2M, 3.0 * IN2M)])
	var bad: Dictionary = _core.check_move(_h, "a", {"mode": 1, "positions": placed, "trails": [off]}, true)
	assert_str(str(bad.get("reason", ""))).is_equal("trail does not match the placed model")


func test_a_drop_that_is_not_understood_is_refused_with_a_reason() -> void:
	assert_str(str(_core.check_move(9999, "a", _drop(1, 1.0), true).get("reason", ""))).is_equal("unknown handle")
	assert_str(str(_core.check_move(_h, "zzz", _drop(1, 1.0), true).get("reason", ""))).is_equal("unknown unit")
	assert_str(str(_core.check_move(_h, "a", {"mode": 1, "positions": [1, 2, 3]}, true).get("reason", ""))).is_equal("positions are not all Vector3")
	assert_str(str(_core.check_move(_h, "a", {"mode": 1, "positions": _drop(1, 1.0)["positions"], "trails": [[1]]}, true).get("reason", ""))).is_equal("trails are not all Vector2")
	assert_str(str(_core.check_move(_h, "a", _drop(0, 1.0), true).get("reason", ""))).is_equal("movement mode not declared")
	assert_str(str(_core.check_move(_h, "a", {"mode": 1, "positions": PackedVector3Array([Vector3.ZERO])}, true).get("reason", ""))).is_equal("placement does not match the unit's models")


## `check_move` reads the header's rules epoch: 7" is a legal Advance for the Speed Feat bearer "a" at epoch 76, not at epoch 6.
func test_check_move_reads_the_headers_rules_epoch() -> void:
	var core: Object = ClassDB.instantiate("NmlCore")
	assert_bool(core.check_move(_headed_handle(core, 76), "a", _drop(1, 7.0), true)["ok"]).override_failure_message("epoch 76: Advance 8\"").is_true()
	var old: Object = ClassDB.instantiate("NmlCore")
	assert_str(old.check_move(_headed_handle(old, 6), "a", _drop(1, 7.0), true).get("reason", "")).contains("the Advance allowance is 6.0")


func test_a_unit_may_not_begin_while_another_is_open() -> void:
	assert_bool(_core.check_begin("")["ok"]).is_true()
	var r: Dictionary = _core.check_begin("Blades")
	assert_bool(r["ok"]).is_false()
	assert_str(str(r.get("reason", ""))).is_equal("Finish Blades's activation first.")


## ---- the step path runs with the table's casualty order and the moving shot (step 17b) ----
## "a" (3 models, a 24" Rifle) and "b" (5 models in a 1" line whose slot 0 stands in the MIDDLE) under a game header
## of `epoch`. Slot order kills slot 0 first; the table's order (`tray_exact` from epoch 70) kills an outer model.
func _volley_handle(core: Object, epoch: int) -> int:
	var a := _unit(1, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)], "a")
	var b := _unit(2, [14.0, 12.0, 13.0, 15.0, 16.0].map(func(x: float) -> Vector3: return Vector3(x * IN2M, 0, 0)), "b")
	for u in [a, b]:
		(u as GameUnit).unit_properties["game_system"] = "gf"
		(u as GameUnit).unit_properties["faction_folder"] = "robot_legions"
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 1
	w.count = 3
	a.source_type = "opr"
	a.source_data = OPRApiClient.OPRUnit.new()
	(a.source_data as OPRApiClient.OPRUnit).weapons.append(w)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"a": a, "b": b}
	var state := BattleSim.capture(army, func() -> Array: return [], func(_i: int) -> int: return 0, 1, 4)
	var head: Dictionary = AiActRecorder._header_line(state, Callable())
	(head["knobs"] as Dictionary)["rules_epoch"] = epoch
	assert_bool(core.set_game_header(head)).override_failure_message("set_game_header: " + str(core.last_error())).is_true()
	return core.capture_plain(BattleSim.state_to_plain(state))


## One hit, one failed save: which slot of "b" the core removed.
func _one_kill_removes(epoch: int) -> Array:
	var core: Object = ClassDB.instantiate("NmlCore")
	var h := _volley_handle(core, epoch)
	var t: Array = [{"t": "begin"}, {"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": "b"}]
	var r: Dictionary = core.step_activation(h, "a", t, false)
	while r["step"] == "need_roll" and t.size() < 8:
		t.append({"t": "faces", "faces": range(int(r["faces"])).map(func(i: int) -> int:
			return 6 if r["kind"] == "attack" and i == 0 else 1)})
		r = core.step_activation(h, "a", t, false)
	assert_str(r["step"]).override_failure_message(str(r)).is_equal("done")
	return r["delta"][0]["removed"]


func test_step_activation_removes_casualties_in_the_tables_order_from_the_tray_exact_epoch() -> void:
	assert_array(_one_kill_removes(76)).override_failure_message("epoch 76: an outer model goes first").is_equal([1])
	assert_array(_one_kill_removes(69)).override_failure_message("epoch 69: slot order").is_equal([0])


func test_step_activation_lets_a_unit_that_advanced_shoot() -> void:
	var core: Object = ClassDB.instantiate("NmlCore")
	var h := _volley_handle(core, 76)
	var placed: Array = []
	for i in 3:
		placed.append(Vector3((float(i) + 4.0) * IN2M, 0, 0))
	var t: Array = [{"t": "begin"}, {"t": "placed", "positions": placed},
		{"t": "intent", "kind": AiDecision.Action.ADVANCE, "shoot": "b"}]
	var r: Dictionary = core.step_activation(h, "a", t, true)
	assert_str("%s %s" % [r.get("step"), r.get("kind")]).override_failure_message(str(r)).is_equal("need_roll attack")
