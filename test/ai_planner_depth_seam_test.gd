extends GdUnitTestSuite
## U1: two research seams around the D-wave leaf blend (_blend_score).
## (a) NML_DEPTH_DISCOUNT overrides the geometric discount (default 0.5).
## (b) NML_SEAT_DEPTH grows a third value: "inv" swaps which seat gets the
## last-boundary vote vs. the discount blend (off=0, default=1, inv=2).
## Both are lazy env reads cached in static vars, so every case that touches
## them must restore env + statics or the next case runs contaminated.
##
## seat_mode() and depth_discount() do not exist yet (this file is written
## RED-first, before the fix). Dynamic dispatch via a throwaway instance
## (AiPlanner.new().call(...)) keeps this file PARSING pre-fix — a direct
## AiPlanner.seat_mode() reference would be a parse error, which would mask
## the behavioral REDs this file exists to prove.

const IN2M := 0.0254


func _armed(pid: int, positions: Array, uid: String, weapons: Array) -> GameUnit:
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
	for w in weapons:
		var ow := OPRApiClient.OPRWeapon.new()
		ow.name = str((w as Dictionary).get("name", "W"))
		ow.range_value = int((w as Dictionary).get("range", 0))
		ow.attacks = int((w as Dictionary).get("attacks", 4))
		ow.count = 1
		opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr
	return u


## Same fixture as ai_planner_rollout_test.gd's D-wave suite: a near round-end
## state and a far one (one imagined round deeper) with distinct leaf scores.
func _ends() -> Array:
	var gunner := _armed(1, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)],
		"Gunner", [{"name": "LongRifle", "range": 36, "attacks": 12}])
	var striker := _armed(2, [Vector3(42.0 * IN2M, 0, 0), Vector3(43.0 * IN2M, 0, 0),
		Vector3(44.0 * IN2M, 0, 0), Vector3(45.0 * IN2M, 0, 0)],
		"Striker", [{"name": "CCW", "range": 0}])
	var screamer := _armed(2, [Vector3(60.0 * IN2M, 0, 30.0 * IN2M)], "Screamer",
		[{"name": "CCW", "range": 0}])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Gunner": gunner, "Striker": striker, "Screamer": screamer}
	var near := BattleSim.capture(army, func() -> Array: return [Vector3(30.0 * IN2M, 0, 0)],
		func(_i: int) -> int: return 0, 1, 4)
	var far := AiPlanner.rollout(near, {"unit": "Screamer", "kind": AiDecision.Action.HOLD}, 2, 1)
	return [near, far]


func _leaf(state: Dictionary, me: int) -> float:
	return AiMissionEval.score(state, me, BattleSim.reply_threat(state, me))


## Dynamic dispatch keeps this file PARSING pre-fix (a direct AiPlanner.seat_mode()
## reference would be a parse error). has_method() is required, not optional: a
## bare .call() to a truly nonexistent method throws mid-run and (observed on
## this engine) crashes the gdUnit CI runner outright instead of just failing
## the one test case — has_method() records a clean assertion failure instead.
func _dyn(method: String) -> Variant:
	var inst := AiPlanner.new()
	if inst.has_method(method):
		return inst.call(method)
	assert_bool(false).override_failure_message(
		"%s() not implemented yet (pre-fix RED)" % method).is_true()
	return 0


## Same order-dependence lesson as ai_planner_rollout_test.gd:58-63:
## solo_controller sets AiPlanner.opener_seat on every real pick and never
## resets it, and both lazy env statics leak across cases the same way.
func before_test() -> void:
	AiPlanner.opener_seat = false
	AiPlanner._seat_env = -1
	AiPlanner.new().set("_dd_env", -1.0)


func after_test() -> void:
	OS.set_environment("NML_SEAT_DEPTH", "")
	OS.set_environment("NML_DEPTH_DISCOUNT", "")
	AiPlanner.opener_seat = false
	AiPlanner._seat_env = -1
	AiPlanner.new().set("_dd_env", -1.0)


## GUARD: with no env set, the blend is unchanged from today — the normalized
## geometric discount at responder seat (opener_seat=false is the default).
## This case is expected GREEN both before and after the fix.
func test_default_blend_matches_today() -> void:
	var ends := _ends()
	var l1 := _leaf(ends[0], 2)
	var l2 := _leaf(ends[1], 2)
	assert_float(AiPlanner._blend_score(ends, 2)).is_equal_approx((l1 + 0.5 * l2) / 1.5, 0.0001)


## NML_SEAT_DEPTH=off: seat_mode() must report 0, and BOTH seats now take the
## discount blend — the opener no longer gets the last-boundary vote either.
func test_seat_depth_off_discounts_both_seats() -> void:
	OS.set_environment("NML_SEAT_DEPTH", "off")
	AiPlanner._seat_env = -1
	var ends := _ends()
	var l1 := _leaf(ends[0], 2)
	var l2 := _leaf(ends[1], 2)
	var expect := (l1 + 0.5 * l2) / 1.5
	assert_int(int(_dyn("seat_mode"))).is_equal(0)
	AiPlanner.opener_seat = false
	assert_float(AiPlanner._blend_score(ends, 2)).is_equal_approx(expect, 0.0001)
	AiPlanner.opener_seat = true
	assert_float(AiPlanner._blend_score(ends, 2)).is_equal_approx(expect, 0.0001)


## NML_SEAT_DEPTH=inv: seat_mode() must report 2, and the seats SWAP —
## responder (opener_seat=false) now gets the last-boundary vote, opener
## takes the discount blend.
func test_seat_depth_inv_swaps_the_seats() -> void:
	OS.set_environment("NML_SEAT_DEPTH", "inv")
	AiPlanner._seat_env = -1
	var ends := _ends()
	var l1 := _leaf(ends[0], 2)
	var l2 := _leaf(ends[1], 2)
	assert_int(int(_dyn("seat_mode"))).is_equal(2)
	AiPlanner.opener_seat = false
	assert_float(AiPlanner._blend_score(ends, 2)).is_equal_approx(l2, 0.0001)
	AiPlanner.opener_seat = true
	assert_float(AiPlanner._blend_score(ends, 2)).is_equal_approx((l1 + 0.5 * l2) / 1.5, 0.0001)


## NML_DEPTH_DISCOUNT=1.0: every boundary weighs equally (plain average).
## NML_DEPTH_DISCOUNT=0.25: the deeper round is almost muted.
func test_depth_discount_env_reweights_the_blend() -> void:
	var ends := _ends()
	var l1 := _leaf(ends[0], 2)
	var l2 := _leaf(ends[1], 2)
	OS.set_environment("NML_DEPTH_DISCOUNT", "1.0")
	AiPlanner.new().set("_dd_env", -1.0)
	assert_float(float(_dyn("depth_discount"))).is_equal_approx(1.0, 0.0001)
	assert_float(AiPlanner._blend_score(ends, 2)).is_equal_approx((l1 + l2) / 2.0, 0.0001)
	OS.set_environment("NML_DEPTH_DISCOUNT", "0.25")
	AiPlanner.new().set("_dd_env", -1.0)
	assert_float(float(_dyn("depth_discount"))).is_equal_approx(0.25, 0.0001)
	assert_float(AiPlanner._blend_score(ends, 2)).is_equal_approx((l1 + 0.25 * l2) / 1.25, 0.0001)


## Junk NML_DEPTH_DISCOUNT (empty/non-numeric/out of (0,1]) falls back to the
## documented default 0.5 — same as no env at all.
func test_depth_discount_env_junk_falls_back_to_default() -> void:
	var ends := _ends()
	var l1 := _leaf(ends[0], 2)
	var l2 := _leaf(ends[1], 2)
	var expect := (l1 + 0.5 * l2) / 1.5
	for junk in ["banana", "0", "1.5", "-1", ""]:
		OS.set_environment("NML_DEPTH_DISCOUNT", junk)
		AiPlanner.new().set("_dd_env", -1.0)
		assert_float(float(_dyn("depth_discount"))).override_failure_message(
			"junk '%s' must fall back to 0.5" % junk).is_equal_approx(0.5, 0.0001)
		assert_float(AiPlanner._blend_score(ends, 2)).is_equal_approx(expect, 0.0001)
