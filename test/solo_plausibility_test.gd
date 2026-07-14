extends GdUnitTestSuite
## AI PLAUSIBILITY wave 1 — the maneuver-intent layer on the official trees: final-round objective
## urgency (seize range beats a marginal fight when nothing later can pay off), the fast-unit flanking
## doctrine (a fast ranged unit heads for a firing anchor instead of walking blind), large-bases-first
## activation at high coordination (big models plan before small friends fill the lanes), and the
## joined-hero-aware destroyed bookkeeping the battle log reads.

const IN2M := 0.0254


func _unit(pid: int, positions: Array, rules: Array = [], uid: String = "") -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid if uid != "" else "p%d_%d" % [pid, positions.size()]
	u.unit_properties = {"player_id": pid, "name": (uid if uid != "" else "U%d" % pid),
		"quality": 4, "defense": 4, "special_rules": rules}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
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


func _controller(units: Array) -> SoloController:
	var sc: SoloController = auto_free(SoloController.new())
	add_child(sc)
	sc.setup(_army(units), null, null, 1, 2)
	return sc


func _arm(u: GameUnit, weapons: Array) -> void:
	var opr := OPRApiClient.OPRUnit.new()
	for w in weapons:
		var ow := OPRApiClient.OPRWeapon.new()
		ow.name = str((w as Dictionary).get("name", "W"))
		ow.range_value = int((w as Dictionary).get("range", 0))
		ow.attacks = int((w as Dictionary).get("attacks", 2))
		ow.count = 1
		for r in (w as Dictionary).get("rules", []):
			ow.special_rules.append(str(r))
		opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr


func _wire_objectives(sc: SoloController, markers: Array) -> void:
	sc.objectives_provider = func() -> Array: return markers
	sc.objective_owner_of = func(_i: int) -> int: return 0


# === Final-round objective urgency (WP2) ===

func _urgency_board() -> Array:
	# Melee unit with an enemy IN THE WAY of its marker (within 6" of the path) AND in charge range —
	# the official MELEE tree charges. The uncontrolled marker is 10" out (within rush 12 + seize 3);
	# the enemy stays outside the marker's seize bubble so "charging = contesting" never masks the
	# urgency. Mid-match the charge is right; in the FINAL round only the marker scores.
	var melee := _unit(2, [Vector3.ZERO], [], "Claws")
	_arm(melee, [{"name": "Claws", "range": 0, "attacks": 4, "rules": []}])
	var enemy := _unit(1, [Vector3(-4.0 * IN2M, 0, 3.0 * IN2M)], [], "Grunts")
	var sc := _controller([melee, enemy])
	_wire_objectives(sc, [Vector3(-10.0 * IN2M, 0, 0)])
	return [sc, melee]


func test_final_round_urgency_seizes_instead_of_charging() -> void:
	var pair := _urgency_board()
	var sc: SoloController = pair[0]
	sc.game_rounds = 4
	sc.round_provider = func() -> int: return 4
	sc.activate_next_ai_unit()
	assert_int(int(sc.last_report.get("action", -1))).is_equal(AiDecision.Action.RUSH)
	assert_bool(bool(sc.last_report.get("to_objective", false))).is_true()
	var kinds: Array = []
	for rec in sc.drain_decisions():
		kinds.append(str((rec as Dictionary).get("kind", "")))
	assert_bool(kinds.has("urgency")).is_true()


func test_mid_match_the_same_board_still_charges() -> void:
	var pair := _urgency_board()
	var sc: SoloController = pair[0]
	sc.game_rounds = 4
	sc.round_provider = func() -> int: return 2
	sc.activate_next_ai_unit()
	# Mid-match the MELEE tree keeps its official play (the enemy is in the way and in charge range).
	assert_int(int(sc.last_report.get("action", -1))).is_equal(AiDecision.Action.CHARGE)


func test_urgency_never_fires_without_round_wiring() -> void:
	var pair := _urgency_board()
	var sc: SoloController = pair[0]
	sc.activate_next_ai_unit()   # no round_provider/game_rounds → sandbox play, official tree only
	assert_int(int(sc.last_report.get("action", -1))).is_equal(AiDecision.Action.CHARGE)


func test_urgency_respects_low_mission_focus_grades() -> void:
	# A rekrut (mission_focus 0.35) keeps its knob-shaped play — the urgency is a HIGH-grade sharpening.
	var pair := _urgency_board()
	var sc: SoloController = pair[0]
	sc.game_rounds = 4
	sc.round_provider = func() -> int: return 4
	sc.difficulty_seed = 7
	sc.set_difficulty(2, SoloDifficulty.for_grade("rekrut", 7))
	sc.activate_next_ai_unit()
	var kinds: Array = []
	for rec in sc.drain_decisions():
		kinds.append(str((rec as Dictionary).get("kind", "")))
	assert_bool(kinds.has("urgency")).is_false()


# === Fast-unit flanking doctrine (WP4 — the Brother Bikers regression class) ===

func test_fast_ranged_unit_advances_to_a_firing_anchor_instead_of_walking_blind() -> void:
	# Fast bikes (Advance 8") with a 24" rifle, target 30" away: straight-line play would advance to
	# ~22" and pray; the doctrine picks a firing anchor ON THE RING (range - slack) it can REACH this
	# activation — the post-move report must be shooting-capable.
	var bikes := _unit(2, [Vector3.ZERO], ["Fast"], "Bikers")
	_arm(bikes, [{"name": "Twin Rifle", "range": 24, "attacks": 4, "rules": []}])
	var enemy := _unit(1, [Vector3(28.0 * IN2M, 0, 0)], [], "Beasts")
	var sc := _controller([bikes, enemy])
	sc.activate_next_ai_unit()
	assert_int(int(sc.last_report.get("action", -1))).is_equal(AiDecision.Action.ADVANCE)
	assert_bool(bool(sc.last_report.get("can_shoot", false))).is_true()
	var kinds: Array = []
	for rec in sc.drain_decisions():
		kinds.append(str((rec as Dictionary).get("kind", "")))
	assert_bool(kinds.has("flank")).is_true()


func test_flank_doctrine_leaves_in_range_shooters_alone() -> void:
	# Already in range WITH line of sight → the official kite/shoot play stays untouched.
	var bikes := _unit(2, [Vector3.ZERO], ["Fast"], "Bikers")
	_arm(bikes, [{"name": "Twin Rifle", "range": 24, "attacks": 4, "rules": []}])
	var enemy := _unit(1, [Vector3(12.0 * IN2M, 0, 0)], [], "Beasts")
	var sc := _controller([bikes, enemy])
	sc.activate_next_ai_unit()
	var kinds: Array = []
	for rec in sc.drain_decisions():
		kinds.append(str((rec as Dictionary).get("kind", "")))
	assert_bool(kinds.has("flank")).is_false()
	assert_bool(bool(sc.last_report.get("can_shoot", false))).is_true()


func test_slow_ranged_unit_keeps_the_official_walk() -> void:
	# No Fast rule, Advance 6 < the doctrine floor → the tree's straight play is untouched.
	var foot := _unit(2, [Vector3.ZERO], [], "Foot")
	_arm(foot, [{"name": "Rifle", "range": 24, "attacks": 2, "rules": []}])
	var enemy := _unit(1, [Vector3(40.0 * IN2M, 0, 0)], [], "Beasts")
	var sc := _controller([foot, enemy])
	sc.activate_next_ai_unit()
	var kinds: Array = []
	for rec in sc.drain_decisions():
		kinds.append(str((rec as Dictionary).get("kind", "")))
	assert_bool(kinds.has("flank")).is_false()


# === Large-bases-first activation (WP3) ===

func test_high_coordination_activates_large_bases_before_small_friends() -> void:
	# Same section (both west), one 120 mm base and one 25 mm base: at kriegsherr the big model
	# activates FIRST every time (the pick stays random only within the preferred pool).
	var big := _unit(2, [Vector3(-0.30, 0, 0)], ["Tough(12)"], "Rex")
	big.unit_properties["base_size_round"] = 120
	var small := _unit(2, [Vector3(-0.20, 0, 0)], [], "Grunts")
	var enemy := _unit(1, [Vector3(0.45, 0, 0)], [], "Foe")
	var sc := _controller([big, small, enemy])
	sc.difficulty_seed = 11
	sc.set_difficulty(2, SoloDifficulty.for_grade("kriegsherr", 11))
	var first := sc.activate_next_ai_unit()
	assert_str(first.get_name()).is_equal("Rex")


func test_rekrut_keeps_the_official_random_pick_pool() -> void:
	# Rekrut (coordination 0) never re-orders: with the same board the pick record must not carry the
	# large-first label (which unit wins stays the seeded die).
	var big := _unit(2, [Vector3(-0.30, 0, 0)], ["Tough(12)"], "Rex")
	big.unit_properties["base_size_round"] = 120
	var small := _unit(2, [Vector3(-0.20, 0, 0)], [], "Grunts")
	var enemy := _unit(1, [Vector3(0.45, 0, 0)], [], "Foe")
	var sc := _controller([big, small, enemy])
	sc.difficulty_seed = 11
	sc.set_difficulty(2, SoloDifficulty.for_grade("rekrut", 11))
	sc.activate_next_ai_unit()
	for rec in sc.drain_decisions():
		if str((rec as Dictionary).get("kind", "")) == "pick":
			assert_bool(bool(((rec as Dictionary).get("data", {}) as Dictionary).get("large_first", false))).is_false()


# === Joined-hero destroyed bookkeeping (WP5a) ===

func test_combined_alive_and_total_count_the_attached_hero() -> void:
	var squad := _unit(1, [Vector3.ZERO, Vector3(0.03, 0, 0), Vector3(0.06, 0, 0)], [], "Squad")
	var hero := _unit(1, [Vector3(0.09, 0, 0)], ["Hero", "Tough(3)"], "Hero")
	squad.unit_properties["attached_heroes"] = [hero]
	assert_int(SoloController.combined_alive(squad)).is_equal(4)
	assert_int(SoloController.combined_total(squad)).is_equal(4)
	# The squad's own models fall — the unit is NOT destroyed while the hero stands.
	for m in squad.models:
		(m as ModelInstance).is_alive = false
	assert_int(SoloController.combined_alive(squad)).is_equal(1)
	assert_int(squad.get_alive_count()).is_equal(0)   # the own-models count the old check used
	# The hero falls too — NOW the pool is empty.
	(hero.models[0] as ModelInstance).is_alive = false
	assert_int(SoloController.combined_alive(squad)).is_equal(0)


# === Move-record instrumentation (WP2 metric plumbing) ===

func test_move_records_carry_goal_gap_and_acting_context() -> void:
	var runner := _unit(2, [Vector3.ZERO], [], "Runner")
	_arm(runner, [{"name": "Claws", "range": 0, "attacks": 2, "rules": []}])
	var enemy := _unit(1, [Vector3(0.9, 0, 0)], [], "FarFoe")
	var sc := _controller([runner, enemy])
	sc.activate_next_ai_unit()
	var move_rec := {}
	for rec in sc.drain_decisions():
		if str((rec as Dictionary).get("kind", "")) == "move":
			move_rec = rec
	assert_bool(move_rec.is_empty()).is_false()
	var data := move_rec.get("data", {}) as Dictionary
	assert_bool(data.has("goal_gap_in")).is_true()
	assert_bool(data.has("enemy_gap_in")).is_true()
	assert_bool(data.has("large")).is_true()
	assert_float(float(data.get("goal_gap_in", 0.0))).is_greater(12.0)
