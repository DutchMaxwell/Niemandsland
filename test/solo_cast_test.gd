extends GdUnitTestSuite
## Solo-AI wave 6 — the Caster(X) cast phase wired into the real SoloController: the official Solo
## v3.5.0 procedure (cast after moving; spell picked by D3+X over the BOOK-ORDERED faction list;
## cycle to the first valid spell, else hold), legality (threshold/tokens/range/side — never an
## illegal cast), the deterministic token economy (boost from OTHER friendly casters in 18" LoS;
## auto-interference by the defending AI in native both-AI mode), decision records, and a both-AI
## arena smoke where a Caster faction actually casts. Uses the REAL committed spell maps
## (aof / high_elves — the design-doc reference faction).

const IN2M := 0.0254


func _unit(pid: int, positions: Array, uid: String, rules: Array = [],
		system: String = "aof", faction: String = "high_elves") -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


func _army(units: Array) -> OPRArmyManager:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	army.current_round = 1
	return army


func _controller(units: Array, ai_slot: int = 2) -> SoloController:
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(_army(units), null, null, (1 if ai_slot == 2 else 2), ai_slot)
	return solo


## Pre-draw the D3 the plan will roll (same seed ⇒ same die), then reset the seed so the plan
## replays it — the deterministic-replay pattern of the difficulty knobs.
func _predraw_d3(solo: SoloController, seed_value: int) -> int:
	solo._rng.seed = seed_value
	var d3: int = solo._rng.randi_range(1, 3)
	solo._rng.seed = seed_value
	return d3


## Find (deterministically) a seed whose first D3 draw is `want`, and leave the RNG seeded with it —
## pins the official die so a test can assert the cycle's outcome unconditionally.
func _seed_for_d3(solo: SoloController, want: int) -> void:
	for s in range(1, 64):
		if _predraw_d3(solo, s) == want:
			return
	fail("no seed in 1..63 rolls a D3 of %d" % want)


# === The official D3+X pick over the real committed list (aof/high_elves, book order:
#     Eagle-Eyed Focus(1) · Arcane Blast(1) · Magical Surge(2) · High Tempest(2) ·
#     Path to Glory(3) · Magic Arrows(3)) ===

func test_official_d3x_pick_is_deterministic_and_legal() -> void:
	# Caster(2) with 2 tokens, one enemy squad ~8" away: EEF/AB (enemy 18"), Magical Surge (friendly
	# self) and High Tempest (enemy 9") are valid; the 3-token spells are NOT (tokens). The plan must
	# take the FIRST valid spell of the D3+2 cycle — never an unaffordable or out-of-range one.
	var caster := _unit(2, [Vector3(0, 0, 0)], "Mage", ["Caster(2)", "Hero", "Tough(3)"])
	caster.initialize_caster_points()   # casts_per_round = 2, casts_current = 2
	var enemy := _unit(1, [Vector3(8.0 * IN2M, 0, 0)], "Spears")
	var solo := _controller([caster, enemy])
	var d3 := _predraw_d3(solo, 42)
	var plan := solo._plan_member_cast(caster, caster)
	assert_bool(plan.is_empty()).is_false()
	# Replicate the official cycle on the known list to derive the expected pick.
	var names := ["Eagle-Eyed Focus", "Arcane Blast", "Magical Surge", "High Tempest",
		"Path to Glory", "Magic Arrows"]
	var valid := [true, true, true, true, false, false]   # 3-token spells unaffordable
	var expected := ""
	for idx in AiSpell.official_pick_order(6, d3, 2):
		if valid[idx]:
			expected = names[idx]
			break
	assert_str(str(plan.get("name", ""))).is_equal(expected)
	# The attempt's cost is SPENT at plan time (v3.5.1: spend, then roll — one try per spell).
	assert_int(caster.casts_current).is_equal(2 - int(plan.get("threshold", 0)))
	assert_int(int(plan.get("target_num", 0))).is_between(2, 6)
	# The decision is recorded with the official citation and the candidate list.
	var rec := _last_record(solo, "cast")
	assert_bool(rec.is_empty()).is_false()
	assert_str(str(rec.get("chosen", ""))).is_equal(expected)
	assert_int((rec.get("candidates", []) as Array).size()).is_greater(0)


func test_same_seed_same_cast_plan() -> void:
	# Full determinism: two controllers with the same seed and board produce the same pick.
	var picks: Array = []
	for run in range(2):
		var caster := _unit(2, [Vector3(0, 0, 0)], "Mage", ["Caster(2)"])
		caster.initialize_caster_points()
		var enemy := _unit(1, [Vector3(8.0 * IN2M, 0, 0)], "Spears")
		var solo := _controller([caster, enemy])
		solo._rng.seed = 7
		var plan := solo._plan_member_cast(caster, caster)
		picks.append(str(plan.get("name", "")))
	assert_str(str(picks[0])).is_equal(str(picks[1]))


func test_no_valid_spell_holds_tokens() -> void:
	# 1 token, the only enemy far out of every spell range: the 1-token enemy spells have no target,
	# the friendly spells cost 2+ — official: "or else don't cast anything". Tokens stay, a
	# cast_skip record explains why.
	var caster := _unit(2, [Vector3(0, 0, 0)], "Mage", ["Caster(1)"])
	caster.initialize_caster_points()
	var enemy := _unit(1, [Vector3(30.0 * IN2M, 0, 0)], "FarSpears")
	var solo := _controller([caster, enemy])
	var plan := solo._plan_member_cast(caster, caster)
	assert_bool(plan.is_empty()).is_true()
	assert_int(caster.casts_current).is_equal(1)
	assert_bool(_last_record(solo, "cast_skip").is_empty()).is_false()


func test_unknown_faction_stays_manual() -> void:
	# No committed spell data for the (system, faction) → the honest fallback: no automated cast,
	# tokens held, the gap recorded (casting stays a manual action, exactly as before wave 6).
	var caster := _unit(2, [Vector3(0, 0, 0)], "Mage", ["Caster(2)"], "aof", "no_such_faction")
	caster.initialize_caster_points()
	var enemy := _unit(1, [Vector3(8.0 * IN2M, 0, 0)], "Spears")
	var solo := _controller([caster, enemy])
	assert_bool(solo._plan_member_cast(caster, caster).is_empty()).is_true()
	assert_int(caster.casts_current).is_equal(2)


# === Token economy: boost (other friendly casters, 18" LoS) + both-AI auto-interference ===

func test_boost_tokens_come_from_other_friendly_casters() -> void:
	# A helper caster 2" away holds 3 tokens; a 5-model Defense-4 squad sits 8" out. Whatever valid
	# damage/debuff spell the cycle lands on, its EV clears the marginal floor, so the default
	# (sharp) AI boosts to the 2+ ceiling: 2 tokens, drawn from the HELPER (the ±1 comes from OTHER
	# models — the caster's own tokens only pay the spell's value).
	var caster := _unit(2, [Vector3(0, 0, 0)], "Mage", ["Caster(2)"])
	caster.initialize_caster_points()
	var helper := _unit(2, [Vector3(2.0 * IN2M, 0, 0)], "Acolyte", ["Caster(3)"])
	helper.initialize_caster_points()   # 3 tokens
	var enemy := _unit(1, [Vector3(8.0 * IN2M, 0, 0), Vector3(8.0 * IN2M, 0, 0.05),
		Vector3(8.0 * IN2M, 0, 0.10), Vector3(8.0 * IN2M, 0, 0.15), Vector3(8.0 * IN2M, 0, 0.20)], "Spears")
	var solo := _controller([caster, helper, enemy])
	_seed_for_d3(solo, 2)   # D3=2 + Caster(2) → the cycle starts at High Tempest (a valued damage spell)
	var plan := solo._plan_member_cast(caster, caster)
	assert_bool(plan.is_empty()).is_false()
	assert_str(str(plan.get("name", ""))).is_equal("High Tempest")
	assert_bool(float(plan.get("ev", 0.0)) > 0.3).is_true()
	# The marginal calculus buys the 2+ ceiling: exactly 2 helper tokens (the third buys nothing).
	assert_int(int(plan.get("boost", 0))).is_equal(2)
	assert_int(helper.casts_current).is_equal(1)
	assert_int(int(plan.get("target_num", 0))).is_equal(2)


func test_both_ai_auto_interference_spends_enemy_tokens() -> void:
	# Native both-AI: the DEFENDING side's caster (2 tokens, in 18" LoS) auto-interferes against a
	# valued cast — deterministically, no dialogs — driving the target number up (4+ → 6+).
	var caster := _unit(2, [Vector3(0, 0, 0)], "Mage", ["Caster(2)"])
	caster.initialize_caster_points()
	var enemy_caster := _unit(1, [Vector3(6.0 * IN2M, 0, 0)], "Witch", ["Caster(2)"])
	enemy_caster.initialize_caster_points()
	var enemy := _unit(1, [Vector3(8.0 * IN2M, 0, 0), Vector3(8.0 * IN2M, 0, 0.05),
		Vector3(8.0 * IN2M, 0, 0.10)], "Spears")
	var solo := _controller([caster, enemy_caster, enemy])
	solo.auto_interference = true
	_seed_for_d3(solo, 2)   # D3=2 → High Tempest, a cast worth resisting
	var plan := solo._plan_member_cast(caster, caster)
	assert_bool(plan.is_empty()).is_false()
	assert_bool(bool(plan.get("interference_open", true))).is_false()   # decided at plan time
	assert_bool(float(plan.get("ev", 0.0)) > 0.3).is_true()
	assert_int(int(plan.get("interference", 0))).is_equal(2)
	assert_int(enemy_caster.casts_current).is_equal(0)
	# In human-vs-AI mode the same board leaves the resist choice OPEN for the human prompt.
	var caster2 := _unit(2, [Vector3(0, 0, 0)], "Mage2", ["Caster(2)"])
	caster2.initialize_caster_points()
	var enemy_caster2 := _unit(1, [Vector3(6.0 * IN2M, 0, 0)], "Witch2", ["Caster(2)"])
	enemy_caster2.initialize_caster_points()
	var enemy2 := _unit(1, [Vector3(8.0 * IN2M, 0, 0)], "Spears2")
	var solo2 := _controller([caster2, enemy_caster2, enemy2])
	_seed_for_d3(solo2, 2)
	var plan2 := solo2._plan_member_cast(caster2, caster2)
	assert_bool(plan2.is_empty()).is_false()
	assert_int(int(plan2.get("interference", 0))).is_equal(0)
	assert_bool(bool(plan2.get("interference_open", false))).is_true()
	assert_int(enemy_caster2.casts_current).is_equal(2)   # the human's tokens are THEIRS to spend


func test_aura_respects_the_eighteen_inch_range() -> void:
	# A friendly caster 25" away is OUTSIDE the 18" boost aura — no boost, its tokens untouched.
	var caster := _unit(2, [Vector3(0, 0, 0)], "Mage", ["Caster(2)"])
	caster.initialize_caster_points()
	var far_helper := _unit(2, [Vector3(25.0 * IN2M, 0, 0)], "FarAcolyte", ["Caster(3)"])
	far_helper.initialize_caster_points()
	var enemy := _unit(1, [Vector3(8.0 * IN2M, 0, 0)], "Spears")
	var solo := _controller([caster, far_helper, enemy])
	_seed_for_d3(solo, 2)   # a valued damage spell — boost WOULD pay if the helper were in range
	var plan := solo._plan_member_cast(caster, caster)
	assert_bool(plan.is_empty()).is_false()
	assert_bool(float(plan.get("ev", 0.0)) > 0.3).is_true()
	assert_int(int(plan.get("boost", 0))).is_equal(0)
	assert_int(far_helper.casts_current).is_equal(3)


# === The both-AI arena smoke: a Caster faction actually casts ===

func test_both_ai_arena_smoke_casters_actually_cast() -> void:
	# Two graded AI sides, BOTH fielding a High-Elves caster + a line squad, driven through the real
	# alternation loop (the native both-AI driver's core, sans dice tray). Proves end-to-end: the
	# cast phase runs inside real activations, at least one cast is PLANNED with spent tokens, the
	# report carries it for main's tray resolution, and every cast decision is recorded + legal.
	var p1_mage := _unit(1, [Vector3(-10.0 * IN2M, 0, 0)], "P1Mage", ["Caster(2)"])
	p1_mage.initialize_caster_points()
	var p1_line := _unit(1, [Vector3(-8.0 * IN2M, 0, 0.1)], "P1Line")
	var p2_mage := _unit(2, [Vector3(10.0 * IN2M, 0, 0)], "P2Mage", ["Caster(2)"])
	p2_mage.initialize_caster_points()
	var p2_line := _unit(2, [Vector3(8.0 * IN2M, 0, 0.1)], "P2Line")
	var army := _army([p1_mage, p1_line, p2_mage, p2_line])
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	solo.auto_interference = true   # native both-AI: the defending AI auto-resists
	solo.difficulty_seed = 99
	solo.set_difficulty(1, SoloDifficulty.for_grade("kriegsherr", 99))
	solo.set_difficulty(2, SoloDifficulty.for_grade("kriegsherr", 99))
	solo._rng.seed = 99
	var cast_reports := 0
	var tokens_spent := 0
	const ROUNDS := 2
	for round_no in range(1, ROUNDS + 1):
		for u in [p1_mage, p1_line, p2_mage, p2_line]:
			(u as GameUnit).is_activated = false
		army.current_round = round_no
		var side := 1
		var guard := 0
		while guard < 40:
			guard += 1
			var other := 2 if side == 1 else 1
			solo.ai_slot = side
			solo.human_slot = other
			if solo.eligible_ai_units().is_empty():
				solo.ai_slot = other
				solo.human_slot = side
				if solo.eligible_ai_units().is_empty():
					break
			var unit: GameUnit = solo.activate_next_ai_unit()
			if unit != null and solo.last_report.has("casts"):
				for c in solo.last_report["casts"]:
					cast_reports += 1
					var cast := c as Dictionary
					tokens_spent += int(cast.get("tokens_before", 0)) - int(cast.get("tokens_after", 0))
					# LEGALITY: the spend equals the spell's threshold, never more than held.
					assert_int(int(cast.get("tokens_before", 0)) - int(cast.get("tokens_after", 0))) \
						.is_equal(int(cast.get("threshold", 0)))
					assert_int(int(cast.get("tokens_after", 0))).is_greater_equal(0)
					assert_bool((cast.get("targets", []) as Array).is_empty()).is_false()
			side = 2 if side == 1 else 1
		# Round bookkeeping: casters accumulate tokens (capped at 6) like the real round advance.
		for u in [p1_mage, p2_mage]:
			(u as GameUnit).add_round_caster_points()
	assert_int(cast_reports).override_failure_message(
		"no caster ever cast in the both-AI smoke").is_greater(0)
	assert_int(tokens_spent).is_greater(0)
	# Every cast decision carries the official citation and reproducible data.
	var cast_recs := 0
	for rec in solo.decision_log:
		if str((rec as Dictionary).get("kind", "")) == "cast":
			cast_recs += 1
			var data: Dictionary = (rec as Dictionary).get("data", {})
			assert_bool(data.has("d3") and data.has("boost") and data.has("interference") \
				and data.has("p_cast") and data.has("tokens_before")).is_true()
	assert_int(cast_recs).is_greater(0)


func _last_record(solo: SoloController, kind: String) -> Dictionary:
	for i in range(solo.decision_log.size() - 1, -1, -1):
		var rec := solo.decision_log[i] as Dictionary
		if str(rec.get("kind", "")) == kind:
			return rec
	return {}
