extends GdUnitTestSuite
## One-core P3 step 16: the Godot binding of the core's activation step API, `NmlCore.step_activation`.
## The table sends the ordered inputs (begin, intent, faces); the core answers need_roll / done / refused.
## Real: the NmlCore extension (the CI shards build and load it; a missing core fails
## test/core_extension_loaded_test.gd instead of skipping these cases), BattleSim.capture + state_to_plain.
## Constructed: two bare units, one weapon on "a".

const IN2M := 0.0254

var _core: Object
var _h := 0


func before_test() -> void:
	_core = ClassDB.instantiate("NmlCore")
	var a := _unit(1, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)], "a")
	var b := _unit(2, [Vector3(10.0 * IN2M, 0, 0), Vector3(11.0 * IN2M, 0, 0), Vector3(12.0 * IN2M, 0, 0)], "b")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"a": a, "b": b}
	var state := BattleSim.capture(army, func() -> Array: return [], func(_i: int) -> int: return 0, 1, 4)
	var plain := BattleSim.state_to_plain(state)
	(plain["units"]["a"]["profile"] as Dictionary)["weapons"] = [
		{"name": "Rifle", "range": 24.0, "attacks": 6, "count": 3, "ap": 0, "rules": []}]
	_h = _core.capture_plain(plain)


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


func test_an_input_the_core_does_not_know_is_refused_with_its_index() -> void:
	var r: Dictionary = _core.step_activation(_h, "a", [{"t": "begin"}, {"t": "wat"}], false)
	assert_str(r["step"]).is_equal("refused")
	assert_int(int(r["index"])).is_equal(1)
	assert_str(r["reason"]).is_equal("input 1 is not understood")


func test_an_unknown_handle_is_refused() -> void:
	var r: Dictionary = _core.step_activation(9999, "a", [{"t": "begin"}], false)
	assert_str(r["step"]).is_equal("refused")
	assert_str(r["reason"]).is_equal("unknown handle")


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
