extends GdUnitTestSuite
## Rules 3.6 lane AIG-G2-L2a: the table's shooting volley applies several army-book rules without
## naming them in the battle log. Every case drives the real AI volley (_solo_resolve_ai_volley)
## over the real scenes/main.tscn with the profile the real card builds (AiShooting.profiles_in_range
## + its production stamps), so the rule fires through the live path. Each RED case also pins the
## volley's outcome (hits / saves / AP / working range): the log line is visibility only, so those
## values must be identical before and after the change. Precision Feat and Shatter already carry
## their book name (control cases): they stay pinned so a later change cannot drop them.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

const SEED := 20260803

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	RulesRegistry.reset_cache()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func after_test() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	RulesRegistry.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, pos: Vector3, rules: Array,
		faction: String, quality: int = 4, system: String = "gf") -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	u.unit_properties["quality"] = quality
	u.unit_properties["defense"] = 4
	u.unit_properties["special_rules"] = rules
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["game_system"] = system
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _weapon(w_name: String, rules: Array[String], attacks: int = 6, range_in: int = 24) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = w_name
	w.range_value = range_in
	w.attacks = attacks
	w.count = 1
	w.special_rules = rules
	return w


## The shot list the real AI shooting build produces: profiles from the card, then the production
## stamps (sergeant facets, alias markers, conditional-AP specs) — never a hand-built profile.
func _shots(attacker: GameUnit, weapons: Array) -> Array:
	var shots: Array = []
	var member_profiles: Array = []
	for w in weapons:
		var base_range: int = int((w as OPRApiClient.OPRWeapon).range_value)
		var prof_list: Array = AiShooting.profiles_in_range([w], float(base_range))
		if prof_list.is_empty():
			continue
		var prof := prof_list[0] as Dictionary
		member_profiles.append(prof)
		shots.append({"member": attacker, "quality": attacker.get_quality(),
			"alive": attacker.get_alive_count(), "max": attacker.models.size(),
			"reach": base_range, "profile": prof})
	AiEv.stamp_sergeant(member_profiles, attacker)
	_main._solo_stamp_alias_markers(attacker, member_profiles)
	AiEv.stamp_conditional_ap(member_profiles, attacker)
	return shots


func _log_from(before: int) -> String:
	var text := ""
	var entries: Array = _main.battle_log.entries()
	for i in range(before, entries.size()):
		text += str((entries[i] as Dictionary)["text"]) + "\n"
	return text


func _volley(attacker: GameUnit, target: GameUnit, weapons: Array, moved: bool = false) -> String:
	var before: int = _main.battle_log.entries().size()
	seed(SEED)
	_main.seed_tray_rng(SEED)
	await _main._solo_resolve_ai_volley(attacker, target, _shots(attacker, weapons), moved)
	var text := _log_from(before)
	await E2EBoot.settle(get_tree())
	return text


## RELIABLE — the weapon shoots at Quality 2+; no line names the rule today.
func test_a_reliable_volley_names_the_rule_and_keeps_its_hits() -> void:
	var shooter := _unit(2, "Gunner", Vector3.ZERO, [], "battle_brothers", 4)
	var target := _unit(2, "Target", Vector3(0.25, 0.0, 0.0), [], "battle_brothers")
	var text := await _volley(shooter, target, [_weapon("Rifle", ["Reliable"] as Array[String])])
	assert_str(text).override_failure_message("Reliable lowered the Quality to 2+ (outcome):\n%s" % text) \
		.contains("hits (2+)")
	assert_str(text).override_failure_message("Reliable's outcome is 4 hits on this seed:\n%s" % text) \
		.contains("— 4 hits")
	assert_str(text).override_failure_message("the battle log must name Reliable:\n%s" % text) \
		.contains("Reliable")


## RANGED SHROUDING family — Shadowborn / Wild Veil / Darkborn: the APPLIED range penalty is silent.
func test_a_shrouded_target_names_its_book_rule_and_keeps_the_reduced_range() -> void:
	var cases := [["Shadowborn", "shadow_stalkers", "aof", 0.0],
		["Wild Veil", "wood_elves", "aof", 2.0],
		["Darkborn", "dark_brothers", "gf", 4.0]]
	var i := 0
	for c in cases:
		i += 1
		var lane: float = float(c[3])
		var shooter := _unit(2, "Gunner%d" % i, Vector3(0.0, lane, 0.0), [], str(c[1]), 3, str(c[2]))
		var target := _unit(2, "Foe%d" % i, Vector3(0.25, lane, 0.0), [c[0]], str(c[1]), 4, str(c[2]))
		assert_float(SoloController.effective_shoot_reach_in(24.0, target)) \
			.override_failure_message("%s reduces the working range to 20\"" % c[0]).is_equal(20.0)
		var text := await _volley(shooter, target, [_weapon("Rifle", [] as Array[String])])
		assert_str(text).override_failure_message("%s: the volley still fires 4 hits:\n%s" % [c[0], text]) \
			.contains("— 4 hits")
		assert_str(text).override_failure_message("%s must be named when its penalty applies:\n%s" % [c[0], text]) \
			.contains(str(c[0]))


## ENHANCED WARBOUND — the Shred family's upgrade folds silently; no line names the book rule.
func test_an_enhanced_warbound_volley_names_the_rule_and_keeps_its_wounds() -> void:
	var shooter := _unit(2, "Gunner", Vector3.ZERO, ["Enhanced Warbound", "Warbound"], "daemons_of_war")
	var target := _unit(2, "Target", Vector3(0.25, 0.0, 0.0), [], "daemons_of_war")
	var text := await _volley(shooter, target, [_weapon("Gun", [] as Array[String])])
	assert_str(text).override_failure_message("the volley's outcome is 3 hits:\n%s" % text) \
		.contains("— 3 hits")
	assert_str(text).override_failure_message("and still lands its wound:\n%s" % text) \
		.contains("takes 1 wound")
	assert_str(text).override_failure_message("the battle log must name Enhanced Warbound:\n%s" % text) \
		.contains("Enhanced Warbound")


## QUICK THROW — the AI volley gets the LOS waiver (Indirect after moving) but never names the rule.
func test_a_quick_throw_volley_names_the_rule_and_keeps_the_waiver() -> void:
	var shooter := _unit(2, "Gunner", Vector3.ZERO, ["Quick Throw"], "human_inquisition")
	shooter.unit_properties["moved_round"] = _main.opr_army_manager.current_round
	var target := _unit(2, "Target", Vector3(0.25, 0.0, 0.0), [], "human_inquisition")
	assert_bool(SoloController.indirect_ignores_los(shooter, true)) \
		.override_failure_message("fixture: Quick Throw lifts the Hold need").is_true()
	assert_bool(SoloController.indirect_ignores_los(shooter, false)) \
		.override_failure_message("fixture: without the waiver the moved volley is blind").is_false()
	var text := await _volley(shooter, target, [_weapon("Launcher", ["Indirect"] as Array[String])], true)
	assert_str(text).override_failure_message("the volley still fires 3 hits:\n%s" % text) \
		.contains("— 3 hits")
	assert_str(text).override_failure_message("the battle log must name Quick Throw:\n%s" % text) \
		.contains("Quick Throw")


## ANTI-COVER WHEN SHOOTING — the rule skips the save today but the applied skip names no rule.
func test_anti_cover_when_shooting_names_the_rule_and_keeps_the_skip() -> void:
	var shooter := _unit(2, "Gunner", Vector3.ZERO, ["Anti-Cover when Shooting"], "dwarf_guilds")
	var target := _unit(2, "Target", Vector3(0.25, 0.0, 0.0), [], "dwarf_guilds")
	var o: Node3D = _main.terrain_overlay
	o.grid_cells[o.world_to_cell(Vector3(0.25, 0.0, 0.0))] = o.TerrainType.FOREST
	assert_bool(_main._solo_majority_in_cover(target)) \
		.override_failure_message("fixture: the target stands in cover").is_true()
	var text := await _volley(shooter, target, [_weapon("Gun", [] as Array[String])])
	assert_str(text).override_failure_message("the cover really is skipped (outcome):\n%s" % text) \
		.not_contains("is in cover")
	assert_str(text).override_failure_message("the save uses the uncovered Defense:\n%s" % text) \
		.contains("saves on 4+")
	assert_str(text).override_failure_message("the applied cover skip must name Anti-Cover when Shooting:\n%s" % text) \
		.contains("Anti-Cover when Shooting: Gunner ignores")


## UNPREDICTABLE SHOOTER — the volley die's AP(+1) applies today; the applied effect names no rule.
func test_an_unpredictable_shooter_volley_names_the_rule_and_keeps_its_ap() -> void:
	var shooter := _unit(2, "Gunner", Vector3.ZERO, ["Unpredictable Shooter"], "duchies_of_vinci", 4, "aof")
	var target := _unit(2, "Target", Vector3(0.25, 0.0, 0.0), [], "duchies_of_vinci", 4, "aof")
	var text := await _volley(shooter, target, [_weapon("Gun", [] as Array[String])])
	assert_str(text).override_failure_message("the AP(+1) leg is applied (saves on 5+):\n%s" % text) \
		.contains("saves on 5+")
	assert_str(text).override_failure_message("the volley lands 5 hits on this seed:\n%s" % text) \
		.contains("— 5 hits")
	assert_str(text).override_failure_message("the applied die must name Unpredictable Shooter:\n%s" % text) \
		.contains("Unpredictable Shooter: Gunner's volley rolls 2")


## CONTROL — Precision Feat already names itself in the to-hit breakdown; pin it and its outcome.
func test_precision_feat_still_names_itself_and_keeps_its_hits() -> void:
	var shooter := _unit(2, "Gunner", Vector3.ZERO, ["Precision Feat"], "ghostly_undead", 4, "aof")
	var target := _unit(2, "Target", Vector3(0.25, 0.0, 0.0), [], "ghostly_undead", 4, "aof")
	var text := await _volley(shooter, target, [_weapon("Gun", [] as Array[String])])
	assert_str(text).override_failure_message("the +1 came from Precision Feat:\n%s" % text) \
		.contains("Precision Feat +1")
	assert_str(text).override_failure_message("its outcome is 4 hits:\n%s" % text) \
		.contains("— 4 hits")


## CONTROL — Shatter already names itself on the on-6 AP sub-batch; pin it and its outcome.
func test_shatter_still_names_itself_and_keeps_its_hits() -> void:
	var shooter := _unit(2, "Gunner", Vector3.ZERO, [], "jackals")
	var target := _unit(2, "Target", Vector3(0.25, 0.0, 0.0), ["Tough(3)"], "jackals")
	var text := await _volley(shooter, target, [_weapon("Gun", ["Shatter"] as Array[String])])
	assert_str(text).override_failure_message("the on-6 AP came from Shatter:\n%s" % text) \
		.contains("Shatter")
	assert_str(text).override_failure_message("its outcome is 3 hits:\n%s" % text) \
		.contains("— 3 hits")
