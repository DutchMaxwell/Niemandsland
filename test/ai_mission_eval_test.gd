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



# === E5: move-controllable features (NML-995) ===

## Charge exposure uses the R8 geometry (rush 12 + 1 contact, nearest model):
## a squad 10" from the enemy counts exposed, at 20" it does not; cover flags
## count per unit; the focus load is the largest single incoming entry.
func test_e5_features_exposure_cover_and_focus() -> void:
	var brute := _unit(1, [Vector3.ZERO], "Brute")
	var near := _unit(2, [Vector3(10.0 * IN2M, 0, 0)], "Near")
	var far := _unit(2, [Vector3(20.0 * IN2M, 0, 0)], "Far")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Brute": brute, "Near": near, "Far": far}
	var state := BattleSim.capture(army, func() -> Array: return [Vector3.ZERO],
		func(_i: int) -> int: return 0, 1, 4)
	(state["units"]["Near"] as Dictionary)["in_cover"] = true
	var f := AiMissionEval.features(state, 2, {"Near": 1.5, "Far": 0.5})
	assert_float(float(f.get("my_charge_exposed", -1.0))).is_equal_approx(1.0, 0.001)
	assert_float(float(f.get("their_charge_exposed", -1.0))).is_equal_approx(1.0, 0.001)
	assert_float(float(f.get("cover_mine", -1.0))).is_equal_approx(1.0, 0.001)
	assert_float(float(f.get("cover_theirs", -1.0))).is_equal_approx(0.0, 0.001)
	assert_float(float(f.get("my_incoming_max", -1.0))).is_equal_approx(1.5, 0.001)
	assert_float(float(f.get("my_incoming", -1.0))).is_equal_approx(2.0, 0.001)


## E7: weight keys may be product terms "a*b" — the value is the product of
## the two base features; plain keys stay plain.
func test_feature_value_supports_product_terms() -> void:
	var f := {"tail_mine": 2.0, "round_frac": 0.5}
	assert_float(AiMissionEval._feature_value(f, "tail_mine")).is_equal_approx(2.0, 0.0001)
	assert_float(AiMissionEval._feature_value(f, "tail_mine*round_frac")).is_equal_approx(1.0, 0.0001)
	assert_float(AiMissionEval._feature_value(f, "missing*round_frac")).is_equal_approx(0.0, 0.0001)


## E8: ratio keys "a/b" normalise by force size (denominator floored at 1).
func test_feature_value_supports_ratio_terms() -> void:
	var f := {"tail_mine": 3.0, "my_units": 6.0, "my_wounds": 0.0}
	assert_float(AiMissionEval._feature_value(f, "tail_mine/my_units")).is_equal_approx(0.5, 0.0001)
	assert_float(AiMissionEval._feature_value(f, "tail_mine/my_wounds")).is_equal_approx(3.0, 0.0001)


## Feature wave (net stage): the mirror threat, state counters and reserve
## stamp — each asserted in both directions so the check can fail.
func test_feature_wave_mirror_counts_and_reserves() -> void:
	var mine := _unit(1, [Vector3.ZERO], "Mine")
	var mopr := OPRApiClient.OPRUnit.new()
	var mw := OPRApiClient.OPRWeapon.new()
	mw.name = "Rifle"
	mw.range_value = 24
	mw.attacks = 2
	mine.source_type = "opr"
	mine.source_data = mopr
	mopr.weapons.append(mw)
	var theirs := _unit(2, [Vector3(14.0 * IN2M, 0, 0)], "Theirs")
	var state := _state([mine, theirs], [Vector3.ZERO], [0])
	(state["units"]["Theirs"] as Dictionary)["shaken"] = true
	(state["units"]["Mine"] as Dictionary)["fatigued"] = true
	state["reserves"] = {1: 2, 2: 0}
	var f := AiMissionEval.features(state, 1, {}, true)
	assert_float(float(f["their_incoming"])).is_greater(0.0)   # my rifle projects onto them
	assert_float(float(f["their_shaken"])).is_equal(1.0)
	assert_float(float(f["my_shaken"])).is_equal(0.0)
	assert_float(float(f["my_fatigued"])).is_equal(1.0)
	assert_float(float(f["my_reserve"])).is_equal(2.0)
	assert_float(float(f["their_reserve"])).is_equal(0.0)
	# Counter-probe: seen from side 2 the mirror threat is MY rifle's absence.
	var f2 := AiMissionEval.features(state, 2, {}, true)
	assert_float(float(f2["their_incoming"])).is_equal(0.0)   # side 2 has no ranged weapon
	assert_float(float(f2["my_reserve"])).is_equal(0.0)


## Melee magnitude: an armed charger in reach raises my_melee_in; out of
## reach it contributes nothing (and the binary exposure flag matches).
func test_melee_magnitude_tracks_the_worst_charger() -> void:
	var brute := _unit(2, [Vector3(8.0 * IN2M, 0, 0)], "Brute")
	var bopr := OPRApiClient.OPRUnit.new()
	var bw := OPRApiClient.OPRWeapon.new()
	bw.name = "Claws"
	bw.range_value = 0
	bw.attacks = 6
	brute.source_type = "opr"
	brute.source_data = bopr
	bopr.weapons.append(bw)
	var target := _unit(1, [Vector3.ZERO], "Target")
	var near := _state([target, brute], [Vector3.ZERO], [0])
	var fn := AiMissionEval.features(near, 1, {}, true)
	assert_float(float(fn["my_charge_exposed"])).is_equal(1.0)
	assert_float(float(fn["my_melee_in"])).is_greater(0.0)
	for m in brute.models:
		(m as ModelInstance).node.global_position = Vector3(40.0 * IN2M, 0, 0)
	var far := _state([target, brute], [Vector3.ZERO], [0])
	var ff := AiMissionEval.features(far, 1, {}, true)
	assert_float(float(ff["my_charge_exposed"])).is_equal(0.0)
	assert_float(float(ff["my_melee_in"])).is_equal(0.0)


## Morale proximity: just above half strength counts as near-half; full
## strength does not.
func test_near_half_counts_the_cliff_edge() -> void:
	var squad := _unit(1, [Vector3.ZERO, Vector3(IN2M, 0, 0)], "Squad")
	for m in squad.models:
		(m as ModelInstance).wounds_max = 5
	var state := _state([squad], [Vector3.ZERO], [0])
	(state["units"]["Squad"] as Dictionary)["wounds"] = [5, 1]   # 6 of 10 = 60%
	var f := AiMissionEval.features(state, 1, {})
	assert_float(float(f["my_near_half"])).is_equal(1.0)
	(state["units"]["Squad"] as Dictionary)["wounds"] = [5, 5]   # full strength
	var f2 := AiMissionEval.features(state, 1, {})
	assert_float(float(f2["my_near_half"])).is_equal(0.0)


## Net v1: an injected known-weight net must produce the hand-computed
## sigmoid and differ from the linear formula; clearing the override
## restores the linear path (the check can fail in both directions).
func test_net_override_forward_pass() -> void:
	var state := _state([_unit(1, [Vector3.ZERO], "A"),
		_unit(2, [Vector3(30.0 * IN2M, 0, 0)], "B")], [Vector3.ZERO], [0])
	var lin: float = AiMissionEval._score_fit(state, 1, {})
	AiMissionEval._net_override = {"keys": ["round_frac"], "mu": [0.0], "sd": [1.0],
		"W1": [[0.0]], "b1": [0.0], "W2": [0.0], "b2": 2.0}
	var net: float = AiMissionEval._score_fit(state, 1, {})
	AiMissionEval._net_override = {}
	assert_float(net).is_equal_approx(1.0 / (1.0 + exp(-2.0)), 0.0001)
	assert_bool(absf(lin - net) > 0.0001).is_true()
	assert_float(AiMissionEval._score_fit(state, 1, {})).is_equal_approx(lin, 0.000001)


## Linear value-model JSONs ("w"/"b" keys) score EXACTLY linearly through the
## net loader — hand-computed sigmoid, and clearing restores the default path.
func test_linear_value_model_override() -> void:
	var state := _state([_unit(1, [Vector3.ZERO], "A")], [Vector3.ZERO], [0])
	AiMissionEval._net_override = {"keys": ["round_frac"], "mu": [0.0], "sd": [1.0],
		"w": [2.0], "b": 0.5}
	var got: float = AiMissionEval._score_fit(state, 1, {})
	AiMissionEval._net_override = {}
	assert_float(got).is_equal_approx(1.0 / (1.0 + exp(-(2.0 * 0.25 + 0.5))), 0.0001)


## Loader path (the box counter-probe found this): a LINEAR JSON ("w"/"b")
## must load through _net() from disk — the earlier W1-only gate silently
## rejected it and fell back to v8.
func test_net_loader_accepts_linear_json_from_disk() -> void:
	var path := "user://test_glasses.json"
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(JSON.stringify({"keys": ["round_frac"], "mu": [0.0], "sd": [1.0],
		"w": [1.0], "b": 0.0}))
	fa.close()
	OS.set_environment("NML_FIT_WEIGHTS", "net")
	OS.set_environment("NML_NET_PATH", ProjectSettings.globalize_path(path))
	AiMissionEval._net_cache = {}
	AiMissionEval._net_tried = false
	var n := AiMissionEval._net()
	OS.set_environment("NML_FIT_WEIGHTS", "")
	OS.set_environment("NML_NET_PATH", "")
	AiMissionEval._net_cache = {}
	AiMissionEval._net_tried = false
	assert_bool(n.has("w")).is_true()


## --- Stage B: position-encoder scoring (tournament hook) -----------------


func _zero_mat(rows: int, cols: int) -> Array:
	var m: Array = []
	for i in range(rows):
		var r: Array = []
		r.resize(cols)
		r.fill(0.0)
		m.append(r)
	return m


## Tiny hand-computed encoder: unit h0 = relu(mine_flag + x/30), h1 = obj
## flag; head reads mine-pool h0 + round_frac. in_dim 24 = 22 + one vocab
## slot. Identity second unit layer.
func _tiny_encoder() -> Dictionary:
	var uw1 := _zero_mat(24, 2)
	(uw1[0] as Array)[0] = 1.0
	(uw1[1] as Array)[0] = 1.0
	(uw1[8] as Array)[1] = 1.0
	var hw1 := _zero_mat(10, 1)
	(hw1[0] as Array)[0] = 1.0
	(hw1[9] as Array)[0] = 1.0
	return {"keys": ["round_frac"], "mu": [0.0], "sd": [1.0],
		"slots": {"0": 0},
		"unit_w1": uw1, "unit_b1": [0.0, 0.0],
		"unit_w2": [[1.0, 0.0], [0.0, 1.0]], "unit_b2": [0.0, 0.0],
		"head_w1": hw1, "head_b1": [0.0],
		"head_w2": [1.0], "head_b2": 0.0}


## Both perspectives hand-computed: side 1 pools its unit at x=+6" (0.2),
## side 2 sees its unit 180-degree ROTATED to x=-3" (-0.1) — the two
## outputs pin perspective flag and rotation together (without the flip
## side 2 would score sigmoid(1.35), not sigmoid(1.15)).
func test_encoder_override_scores_both_perspectives() -> void:
	var state := _state([_unit(1, [Vector3(6.0 * IN2M, 0, 0)], "A"),
		_unit(2, [Vector3(3.0 * IN2M, 0, 0)], "B")], [Vector3.ZERO], [0])
	AiMissionEval._net_override = _tiny_encoder()
	var p1: float = AiMissionEval._score_fit(state, 1, {})
	var p2: float = AiMissionEval._score_fit(state, 2, {})
	AiMissionEval._net_override = {}
	assert_float(p1).is_equal_approx(1.0 / (1.0 + exp(-1.45)), 0.0001)
	assert_float(p2).is_equal_approx(1.0 / (1.0 + exp(-1.15)), 0.0001)


## Canonicalisation parity with netlab canon10 SCHEMA=21: norms, flag
## passthrough, sparse pairs -> dense via the shipped slot map (unknown
## slot SKIPPED, matching python .get), marker owner relative to side.
func test_encoder_canon_matches_canon10() -> void:
	var unit_row: Array = [1, 6.0, 3.0, 3, 2, 1, 0, 1, 24, 10, 4, 5,
		2.5, 1.5, 1, 0, 0, 1, 0, 0, 2, 0, 3, 205, 2]
	var marker_row: Array = [3, 6.0, 0.0, 2,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	var slots := {"0": 0, "205": 1}
	var c := AiMissionEval._encoder_canon([unit_row, marker_row], 1, slots)
	var cu: Array = c[0]
	assert_int(cu.size()).is_equal(26)
	assert_float(float(cu[1])).is_equal_approx(0.2, 0.000001)   # x 6/30
	assert_float(float(cu[3])).is_equal_approx(0.3, 0.000001)   # alive 3/10
	assert_float(float(cu[10])).is_equal_approx(0.8, 0.000001)  # range 24/30
	assert_float(float(cu[13])).is_equal_approx(5.0 / 6.0, 0.000001)
	assert_float(float(cu[16])).is_equal(1.0)                   # flag u14 passthrough
	assert_float(float(cu[19])).is_equal(1.0)                   # flag u17 passthrough
	assert_float(float(cu[22])).is_equal(1.0)                   # slot 0 present
	assert_float(float(cu[23])).is_equal_approx(0.5, 0.000001)  # value 3/6
	assert_float(float(cu[24])).is_equal(1.0)                   # slot 205 present
	assert_float(float(cu[25])).is_equal_approx(2.0 / 6.0, 0.000001)
	var cm: Array = c[1]
	assert_float(float(cm[8])).is_equal(1.0)
	assert_float(float(cm[9])).is_equal(-1.0)                   # enemy-owned marker
	var c2 := AiMissionEval._encoder_canon([unit_row], 2, slots)
	assert_float(float((c2[0] as Array)[1])).is_equal_approx(-0.2, 0.000001)
	var cx := AiMissionEval._encoder_canon(
		[[1, 0.0, 0.0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0.0, 0.0,
		0, 0, 0, 0, 0, 0, 1, 7, 4]], 1, slots)
	assert_float(float((cx[0] as Array)[22])).is_equal(0.0)     # unknown slot 7
	assert_float(float((cx[0] as Array)[24])).is_equal(0.0)


## The mandatory selftest gate: a matching block passes, a drifted
## expectation REJECTS the net (the check can fail).
func test_encoder_selftest_gate() -> void:
	var net := _tiny_encoder()
	var board: Array = [
		[1, 6.0, 0.0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0.0, 0.0,
			0, 0, 0, 0, 0, 0, 0],
		[2, 3.0, 0.0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0.0, 0.0,
			0, 0, 0, 0, 0, 0, 0],
		[3, 0.0, 0.0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]]
	net["selftest"] = {"board": board, "side": 1, "features": [0.25],
		"expected": 1.0 / (1.0 + exp(-1.45))}
	assert_bool(AiMissionEval._encoder_selftest_ok(net)).is_true()
	net["selftest"] = {"board": board, "side": 1, "features": [0.25],
		"expected": 1.0 / (1.0 + exp(-1.45)) + 0.01}
	assert_bool(AiMissionEval._encoder_selftest_ok(net)).is_false()
	net.erase("selftest")
	assert_bool(AiMissionEval._encoder_selftest_ok(net)).is_false()


## NML-1005 — the embedding cache must be INVISIBLE in the numbers: cold and
## warm scores match the hand-computed uncached truth exactly; a poisoned
## cache entry CHANGES the score (proves the cache is really consumed — the
## check can fail); swapping the net object flushes the poison.
func test_encoder_embedding_cache_identity_and_poison() -> void:
	var state := _state([_unit(1, [Vector3(6.0 * IN2M, 0, 0)], "A"),
		_unit(2, [Vector3(3.0 * IN2M, 0, 0)], "B")], [Vector3.ZERO], [0])
	AiMissionEval._net_override = _tiny_encoder()
	var truth := 1.0 / (1.0 + exp(-1.45))
	var cold: float = AiMissionEval._score_fit(state, 1, {})
	var warm: float = AiMissionEval._score_fit(state, 1, {})
	assert_float(cold).is_equal_approx(truth, 0.0001)
	assert_float(warm).is_equal(cold)
	assert_bool(AiMissionEval._emb_cache.size() > 0).is_true()
	var poison_key: String = ""
	for k in AiMissionEval._emb_cache:
		poison_key = k
		break
	AiMissionEval._emb_cache[poison_key] = [9.0, 9.0]
	var poisoned: float = AiMissionEval._score_fit(state, 1, {})
	assert_bool(absf(poisoned - truth) > 0.0001).is_true()
	AiMissionEval._net_override = _tiny_encoder()   # NEW dict object -> flush
	assert_float(AiMissionEval._score_fit(state, 1, {})).is_equal_approx(truth, 0.0001)
	AiMissionEval._net_override = {}
