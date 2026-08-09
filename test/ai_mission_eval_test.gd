extends GdUnitTestSuite
## Phase-1 step 4: AiMissionEval.score — the planner's mission currency.
## Plan fixtures: holder-vs-approacher, dead-unit-cannot-hold, last-round lock.

const IN2M := 0.0254


func _unit(pid: int, positions: Array, uid: String) -> GameUnit:
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
	return u


func _state(units: Array, objectives: Array, owners: Array,
		round_no := 1, rounds_total := 4) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	return BattleSim.capture(army, func() -> Array: return objectives,
		func(i: int) -> int: return owners[i], round_no, rounds_total)


## Equal strength, but the holder already stands in the ring while the
## approacher needs one activation to arrive: the holder's side must lead,
## and the two sides' scores must mirror to exactly 1.
func test_holder_beats_equal_strength_approacher() -> void:
	var state := _state([
		_unit(1, [Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)], "Holder"),
		_unit(2, [Vector3(8.0 * IN2M, 0, 0), Vector3(9.0 * IN2M, 0, 0)], "Approacher"),
	], [Vector3.ZERO], [0])
	var p1 := AiMissionEval.score(state, 1)
	assert_float(p1).is_greater(0.5)
	assert_float(p1).is_less(1.0)   # a reachable approacher still counts for something
	assert_float(AiMissionEval.score(state, 2)).is_equal_approx(1.0 - p1, 0.0001)


func test_dead_unit_cannot_hold() -> void:
	var holder := _unit(1, [Vector3(1.0 * IN2M, 0, 0)], "Holder")
	var approacher := _unit(2, [Vector3(8.0 * IN2M, 0, 0)], "Approacher")
	for m in holder.models:
		(m as ModelInstance).is_alive = false
	var state := _state([holder, approacher], [Vector3.ZERO], [0])
	assert_float(AiMissionEval.score(state, 2)).is_equal_approx(1.0, 0.0001)


## 20" out, plain infantry (12" rush): two activations needed. In the LAST
## round only one remains — the unit can never arrive, so the objective stays
## with its current owner. The same position in round 1 projects fine.
func test_last_round_locks_an_unreachable_objective() -> void:
	var far := [Vector3(20.0 * IN2M, 0, 0)]
	var locked := _state([_unit(2, far, "Far")], [Vector3.ZERO], [1], 4, 4)
	assert_float(AiMissionEval.score(locked, 1)).is_equal_approx(1.0, 0.0001)
	assert_float(AiMissionEval.score(locked, 2)).is_equal_approx(0.0, 0.0001)
	var open := _state([_unit(2, far, "Far")], [Vector3.ZERO], [1], 1, 4)
	assert_float(AiMissionEval.score(open, 2)).is_equal_approx(1.0, 0.0001)


## A shaken holder must idle one activation before it counts again — its
## projection is discounted, so a fresh equal enemy right outside the ring
## pulls the objective to even instead of losing it outright.
func test_shaken_holder_pays_the_recovery_round() -> void:
	var holder := _unit(1, [Vector3(1.0 * IN2M, 0, 0)], "Holder")
	holder.is_shaken = true
	var state := _state([holder,
		_unit(2, [Vector3(8.0 * IN2M, 0, 0)], "Fresh")], [Vector3.ZERO], [0])
	assert_float(AiMissionEval.score(state, 1)).is_equal_approx(0.5, 0.0001)


## Danger term: expected reply wounds shrink a unit's projected hold strength
## (floored at 0); an empty map is byte-identical to the pre-danger score.
func test_incoming_threat_discounts_presence_and_floors_at_zero() -> void:
	var state := _state([
		_unit(1, [Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)], "Holder"),
		_unit(2, [Vector3(8.0 * IN2M, 0, 0), Vector3(9.0 * IN2M, 0, 0)], "Approacher"),
	], [Vector3.ZERO], [0])
	var clean := AiMissionEval.score(state, 1)
	assert_float(AiMissionEval.score(state, 1, {})).is_equal(clean)
	var hurt := AiMissionEval.score(state, 1, {"Holder": 1.0})
	assert_float(hurt).is_less(clean)
	# threat >= strength: the holder projects nothing; only the approacher is left
	assert_float(AiMissionEval.score(state, 1, {"Holder": 99.0})) \
		.is_equal_approx(0.0, 0.0001)


func test_no_objectives_is_even() -> void:
	var state := _state([_unit(1, [Vector3.ZERO], "Solo")], [], [])
	assert_float(AiMissionEval.score(state, 1)).is_equal_approx(0.5, 0.0001)


# === E1: feature vector for the offline eval fit (NML-995) ===

## Hand-computed on a two-unit state (marker at the enemy Gunner): my Squad
## (4x1W, 12" rush) sits 20" out — beyond control ring + rush, so tail_mine
## stays 0 and its presence carries a 2-move discount; the enemy Gunner (3x1W)
## holds the ring: tail_theirs 1, full presence 3. Ownership: marker owned by
## the enemy counts once. The incoming map lands in my_incoming and thins my
## presence.
func test_features_hand_computed_two_unit_state() -> void:
	var gunner := _unit(1, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)], "Gunner")
	var squad_pos: Array = []
	for i in range(4):
		squad_pos.append(Vector3((20.0 + i) * IN2M, 0, 0))
	var squad := _unit(2, squad_pos, "Squad")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Gunner": gunner, "Squad": squad}
	var state := BattleSim.capture(army, func() -> Array: return [Vector3.ZERO],
		func(_i: int) -> int: return 1, 2, 4)
	var f := AiMissionEval.features(state, 2, {"Squad": 1.0})
	assert_float(float(f.get("round_frac", -999.0))).is_equal_approx(0.5, 0.001)
	assert_float(float(f.get("my_wounds", -999.0))).is_equal_approx(4.0, 0.001)
	assert_float(float(f.get("their_wounds", -999.0))).is_equal_approx(3.0, 0.001)
	assert_float(float(f.get("my_units", -999.0))).is_equal_approx(1.0, 0.001)
	assert_float(float(f.get("their_unactivated", -999.0))).is_equal_approx(1.0, 0.001)
	assert_float(float(f.get("my_incoming", -999.0))).is_equal_approx(1.0, 0.001)
	assert_float(float(f.get("tail_mine", -999.0))).is_equal_approx(0.0, 0.001)
	assert_float(float(f.get("tail_theirs", -999.0))).is_equal_approx(1.0, 0.001)
	assert_float(float(f.get("obj_owned_theirs", -999.0))).is_equal_approx(1.0, 0.001)
	assert_float(float(f.get("obj_owned_mine", -999.0))).is_equal_approx(0.0, 0.001)
	# presence: squad 20" out, ring 3", rush 12 -> needed 2 -> (4-1)*0.25
	assert_float(float(f.get("presence_mine", -999.0))).is_equal_approx(0.75, 0.001)
	assert_float(float(f.get("presence_theirs", -999.0))).is_equal_approx(3.0, 0.001)


# === E4: fitted eval (NML-995) ===

## fit_mode routes score() through the fitted logistic: values live in (0,1),
## and MORE enemy unactivated activations must LOWER my score (the fit's
## dominant danger signal, w=-1.29). fit_mode false stays the hand eval.
func test_fit_mode_scores_and_fears_the_enemy_tail() -> void:
	var gunner := _unit(1, [Vector3.ZERO], "Gunner")
	var extra := _unit(1, [Vector3(2.0 * IN2M, 0, 0)], "Extra")
	var squad := _unit(2, [Vector3(20.0 * IN2M, 0, 0)], "Squad")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Gunner": gunner, "Extra": extra, "Squad": squad}
	var state := BattleSim.capture(army, func() -> Array: return [Vector3.ZERO],
		func(_i: int) -> int: return 0, 2, 4)
	var hand := AiMissionEval.score(state, 2)
	AiMissionEval.fit_mode = true
	var fit_full := AiMissionEval.score(state, 2)
	(state["units"]["Extra"] as Dictionary)["activated"] = true
	var fit_less_tail := AiMissionEval.score(state, 2)
	AiMissionEval.fit_mode = false
	assert_float(fit_full).is_between(0.0001, 0.9999)
	assert_bool(abs(fit_full - hand) > 0.0001).override_failure_message(
		"fit eval must actually differ from the hand eval").is_true()
	assert_float(fit_less_tail).override_failure_message(
		"one enemy activation SPENT must RAISE my fitted score").is_greater(fit_full)


## A finished round (everyone activated, round < total) is scored as the NEXT
## round's fresh start — identical to manually building that fresh state.
func test_fit_scores_round_end_as_next_round_start() -> void:
	var gunner := _unit(1, [Vector3.ZERO], "Gunner")
	var squad := _unit(2, [Vector3(20.0 * IN2M, 0, 0)], "Squad")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Gunner": gunner, "Squad": squad}
	var spent := BattleSim.capture(army, func() -> Array: return [Vector3.ZERO],
		func(_i: int) -> int: return 0, 1, 4)
	for k in spent["units"]:
		(spent["units"][k] as Dictionary)["activated"] = true
	var fresh := BattleSim.capture(army, func() -> Array: return [Vector3.ZERO],
		func(_i: int) -> int: return 0, 2, 4)
	AiMissionEval.fit_mode = true
	var a := AiMissionEval.score(spent, 2)
	var b := AiMissionEval.score(fresh, 2)
	AiMissionEval.fit_mode = false
	assert_float(a).is_equal_approx(b, 0.0001)


## The blend ratio is a measurement seam: the score is exactly the convex mix
## of hand and fit at the active ratio (checked at 0.25), and the default
## without the env override stays 0.5.
func test_blend_ratio_mixes_hand_and_fit_exactly() -> void:
	var gunner := _unit(1, [Vector3.ZERO], "Gunner")
	var squad := _unit(2, [Vector3(20.0 * IN2M, 0, 0)], "Squad")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Gunner": gunner, "Squad": squad}
	var state := BattleSim.capture(army, func() -> Array: return [Vector3.ZERO],
		func(_i: int) -> int: return 0, 2, 4)
	var hand := AiMissionEval.score(state, 2)
	AiMissionEval.fit_mode = true
	AiMissionEval._blend = 1.0
	var fit := AiMissionEval.score(state, 2)
	AiMissionEval._blend = 0.25
	var mixed := AiMissionEval.score(state, 2)
	AiMissionEval._blend = -1.0   # back to lazy env/default resolution
	AiMissionEval.fit_mode = false
	assert_float(mixed).is_equal_approx(0.75 * hand + 0.25 * fit, 0.0001)
	assert_float(AiMissionEval.fit_blend()).is_equal_approx(0.5, 0.0001)
	AiMissionEval._blend = -1.0
