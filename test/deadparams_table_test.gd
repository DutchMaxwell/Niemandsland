extends GdUnitTestSuite
## Dead-parameter fold — TABLE half (the GDScript twin of core PR #1006). The
## registry params the core already reads must reach the table folds: Counter
## (strikes_first, impact_reduction_per_model), Artillery (hold_only,
## shooter_hit_bonus, target_hit_penalty), Indirect (ignores_los,
## hold_and_shoot). Every fold's fallback equals the old hard-coded constant
## and every shipped book entry prints exactly that constant — a real-book
## replay is byte-identical; only a deviating fixture entry moves the fold
## (the RED/GREEN pairs below).

const IN2M := 0.0254


func _unit_with(rules: Array, system: String, faction: String, id: String = "T", n: int = 3) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = id
	u.unit_properties = {"player_id": 2, "name": id, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var od := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Cannon"
	w.range_value = 24
	w.attacks = 2
	od.weapons = [w] as Array[OPRApiClient.OPRWeapon]
	u.source_type = "opr"
	u.source_data = od
	for i in range(n):
		var m: ModelInstance = ModelInstance.new()
		m.unit = u
		m.is_alive = true
		m.node = auto_free(Node3D.new())
		add_child(m.node)
		m.node.global_position = Vector3(float(i) * IN2M, 0, 0)
		u.models.append(m)
	return u


func _weapon(rng: int, rules: Array) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "W%d" % rng
	w.range_value = rng
	w.attacks = 2
	w.count = 1
	for r in rules:
		w.special_rules.append(str(r))
	return w


func _inject(system: String, name: String, primitive: String, params: Dictionary) -> void:
	# The rules_registry_test fixture shape: a cache override, reset before
	# and after (statics leak across gdUnit tests).
	RulesRegistry.reset_cache()
	RulesRegistry._cache[system] = {"factions": {"testfac": {name: {
		"primitive": primitive, "rated": false, "book_version": "3.5.3",
		"params": params}}}, "common": {}}


func _state_with(rules: Array, system: String, faction: String) -> Dictionary:
	var gun := _unit_with(rules, system, faction, "Gun", 2)
	var foe := _unit_with([], system, faction, "Foe", 2)
	for i in range(2):
		(foe.models[i] as ModelInstance).node.global_position = Vector3(float(i) * IN2M, 0, 10.0 * IN2M)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Gun": gun, "Foe": foe}
	return BattleSim.capture(army, func() -> Array: return [Vector3(0, 0, 5.0 * IN2M)],
		func(_i: int) -> int: return 0, 1, 4)


func _kinds(menu: Array) -> Dictionary:
	var out := {}
	for c in menu:
		out[int((c as Dictionary).get("kind", -1))] = true
	return out


func test_counter_impact_reduction_param_scales_the_counter_models() -> void:
	# GF/AoF v3.5.1 p.13: "-1 total Impact rolls per model with Counter" — the
	# per-model magnitude is the entry's param. A fixture saying 2 must scale 3
	# alive Counter models to 6; on main the constant 1 wins (3) — RED.
	_inject("gf", "Counter", "Counter", {"strikes_first": true, "impact_reduction_per_model": 2})
	var u := _unit_with(["Counter"], "gf", "testfac")
	assert_int(SoloController.counter_models_of(u)) \
		.override_failure_message("3 alive Counter models at per-model 2 must scale to 6") \
		.is_equal(6)
	RulesRegistry.reset_cache()


func test_counter_models_replay_the_old_count_without_a_param() -> void:
	# No entry (or the shipped 1): the recorded count replays byte-identically.
	RulesRegistry.reset_cache()
	var u := _unit_with(["Counter"], "gf", "testfac")
	assert_int(SoloController.counter_models_of(u)).is_equal(3)
	RulesRegistry.reset_cache()


func test_counter_strikes_first_param_gates_the_strike_first_slot() -> void:
	# The strike-first gate reads the entry (core twin: strikes_first.unwrap_or(true)):
	# the default true keeps the recorded order, a false opts the unit out.
	RulesRegistry.reset_cache()
	var on := _unit_with(["Counter"], "gf", "testfac")
	assert_bool(SoloController.counter_strikes_first(on)) \
		.override_failure_message("no param: the recorded strike-first order stands").is_true()
	_inject("gf", "Counter", "Counter", {"strikes_first": false, "impact_reduction_per_model": 1})
	var off := _unit_with(["Counter"], "gf", "testfac")
	assert_bool(SoloController.counter_strikes_first(off)) \
		.override_failure_message("the entry opted Counter out of the strike-first slot").is_false()
	RulesRegistry.reset_cache()


func test_hold_only_param_reopens_the_immobile_menu() -> void:
	# The menu gate is the core twin (forces_hold && hold_only.unwrap_or(true)):
	# an entry saying hold_only = false must offer the carrier its moves again.
	_inject("gf", "Immobile", "Immobile", {"hold_only": false})
	var state := _state_with(["Immobile"], "gf", "testfac")
	assert_bool(_kinds(AiPlanner.candidates(state, "Gun")).has(AiDecision.Action.RUSH)) \
		.override_failure_message("hold_only = false must reopen the move menu") \
		.is_true()
	RulesRegistry.reset_cache()


func test_hold_only_replays_the_hold_only_menu_without_a_param() -> void:
	# The shipped entry (or no entry): the menu stays hold-only — byte-identical.
	for rules in [["Immobile"], ["Artillery"]]:
		RulesRegistry.reset_cache()
		var state := _state_with(rules, "gf", "testfac")
		assert_bool(_kinds(AiPlanner.candidates(state, "Gun")).has(AiDecision.Action.RUSH)) \
			.override_failure_message("%s must keep the hold-only menu" % str(rules)).is_false()
	RulesRegistry.reset_cache()


func test_artillery_hit_params_reach_the_hit_modifier() -> void:
	# The Artillery magnitudes are entry params (core twin: shooter_hit_bonus /
	# target_hit_penalty). Over 9", a fixture pair (+2 shooter, -3 target) nets -1;
	# without params the recorded +1 / -2 constants replay.
	var got: Variant = AiCombatMath.call("shooting_hit_modifier", 12.0, true, false, true, false, 2, 3)
	assert_int(int(got) if got != null else -999) \
		.override_failure_message("entry magnitudes (+2 shooter, -3 target) must reach the modifier") \
		.is_equal(-1)
	assert_int(AiCombatMath.shooting_hit_modifier(12.0, true, false, true, false)) \
		.override_failure_message("no params: the recorded +1 / -2 replay").is_equal(-1)
	RulesRegistry.reset_cache()


func test_indirect_ignores_los_param_gates_the_weapon_waiver() -> void:
	# The LOS-waiver half (core twin: (p.indirect && ignores_los.unwrap_or(true)) || mark):
	# the default true keeps the waiver, a false drops the weapon-indirect term —
	# spell/mark grants stay unconditional (they never route through this read).
	RulesRegistry.reset_cache()
	var on := _unit_with(["Indirect"], "gf", "testfac")
	assert_bool(SoloController.indirect_ignores_los(on)) \
		.override_failure_message("no param: the recorded waiver stands").is_true()
	_inject("gf", "Indirect", "Indirect", {"ignores_los": false, "hold_and_shoot": true, "moved_hit_penalty": 1})
	var off := _unit_with(["Indirect"], "gf", "testfac")
	assert_bool(SoloController.indirect_ignores_los(off)) \
		.override_failure_message("the entry dropped the weapon-indirect LOS waiver").is_false()
	RulesRegistry.reset_cache()


func test_indirect_hold_and_shoot_param_gates_the_overlay() -> void:
	# The hold-and-shoot overlay's Indirect trigger reads the entry (core twin:
	# hold_and_shoot.unwrap_or(true)): the default fires, a false leaves the unit
	# free to manoeuvre (Relentless keeps its own name-driven trigger).
	_inject("gf", "Indirect", "Indirect", {"ignores_los": true, "hold_and_shoot": false, "moved_hit_penalty": 1})
	var u := _unit_with(["Indirect"], "gf", "testfac")
	assert_str(SoloController.hold_and_shoot_rule([_weapon(24, ["Indirect"])], true, u)) \
		.override_failure_message("hold_and_shoot = false must not force the overlay").is_equal("")
	# No unit read (the pre-wave-5 contract): the recorded overlay fires.
	assert_str(SoloController.hold_and_shoot_rule([_weapon(24, ["Indirect"])], true)) \
		.override_failure_message("no param: the recorded Indirect overlay").is_equal("Indirect")
	RulesRegistry.reset_cache()
