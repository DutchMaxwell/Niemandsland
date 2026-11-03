extends GdUnitTestSuite
## Rules 3.6 log wave, row AIG-G2-L4: two rules that already change the dice must name themselves.
##   * A MODEL-level Regeneration bypass ("Unstoppable when Shooting" / "Unstoppable in Melee",
##     printed or aura-granted; Lacerate primitive + `bypass_regen`) used to answer in silence —
##     the weapon-rule arm of the same reader already names its rule.
##   * Piercing Growth folds its marker AP into the attack profile; the save batch now names the
##     rule that supplied it instead of landing one AP better out of nowhere.
## Log-only: no die, no target and no number moves. The controls are declared first, because
## gdUnit drops the cases declared after a failing one on a scene suite.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	RulesRegistry.reset_cache()
	AiActRecorder.rules_epoch = _epoch_before


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _unit(pid: int, unit_name: String, pos: Vector3, rules: Array, system: String, faction: String) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	u.unit_properties["quality"] = 2
	u.unit_properties["game_system"] = system
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A 24" gun on the unit's own OPR data — the profile _solo_attack_groups builds for a volley.
func _arm(u: GameUnit) -> void:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Test Gun"
	w.range_value = 24
	w.attacks = 60
	w.count = 1
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	u.source_type = "opr"
	u.source_data = src


func _markers(u: GameUnit, rule: String) -> int:
	return int(u.unit_properties.get("growth_%s" % rule.to_snake_case(), 0))


# ===== controls (all green on main) =====

func test_control_below_epoch_73_the_scoped_bypass_stays_silent() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36 - 1
	var striker := _unit(1, "Gunners", Vector3.ZERO, ["Unstoppable when Shooting"], "gf", "robot_legions")
	var trolls := _unit(2, "Trolls", Vector3(0.5 * INCH, 0, 0), ["Regeneration"], "gf", "robot_legions")
	assert_bool(_main._solo_ignores_regen(striker, {"range": 24, "rules": []}, trolls)) \
		.override_failure_message("below 73 the recorded bypass stays byte-exact").is_true()
	assert_str(_log_text()) \
		.override_failure_message("below 73 no new line may appear (log: %s)" % _log_text().strip_edges()) \
		.not_contains("Regeneration ignored")


func test_control_a_plain_carrier_keeps_the_bypass_silent() -> void:
	var striker := _unit(1, "Gunners", Vector3.ZERO, [], "gf", "robot_legions")
	var trolls := _unit(2, "Trolls", Vector3(0.5 * INCH, 0, 0), ["Regeneration"], "gf", "robot_legions")
	assert_bool(_main._solo_ignores_regen(striker, {"range": 24, "rules": []}, trolls)).is_false()
	assert_str(_log_text()).not_contains("Regeneration ignored")


func test_control_piercing_growth_without_markers_adds_no_ap_line() -> void:
	var shooter := _unit(1, "Gunners", Vector3.ZERO, ["Piercing Growth"], "gf", "alien_hives")
	_arm(shooter)
	var foe := _unit(2, "Foemen", Vector3(0.20, 0, 0), [], "gf", "alien_hives")
	assert_int(_markers(shooter, "Piercing Growth")).is_equal(0)
	await _main._run_human_shooting(shooter, foe)
	assert_str(_log_text()).not_contains("from its growth markers")
	await E2EBoot.settle(get_tree())


# ===== the two named lines =====

func test_the_scoped_unstoppable_names_its_model_level_bypass() -> void:
	var striker := _unit(1, "Gunners", Vector3.ZERO, ["Unstoppable when Shooting"], "gf", "robot_legions")
	var trolls := _unit(2, "Trolls", Vector3(0.5 * INCH, 0, 0), ["Regeneration"], "gf", "robot_legions")
	assert_bool(_main._solo_ignores_regen(striker, {"range": 24, "rules": []}, trolls)) \
		.override_failure_message("fixture broken: the granted shooting bypass did not fire").is_true()
	assert_str(_log_text()) \
		.override_failure_message("rules-must-log: the bypass names the scoped rule (log: %s)" % _log_text().strip_edges()) \
		.contains("Unstoppable when Shooting: Regeneration ignored")


func test_piercing_growth_names_the_ap_it_adds() -> void:
	var shooter := _unit(1, "Gunners", Vector3.ZERO, ["Piercing Growth"], "gf", "alien_hives")
	_arm(shooter)
	var foe := _unit(2, "Foemen", Vector3(0.20, 0, 0), [], "gf", "alien_hives")
	_main._solo_growth_round_start()
	_main._solo_growth_round_start()
	assert_int(_markers(shooter, "Piercing Growth")) \
		.override_failure_message("fixture broken: the round ticks earned no marker").is_equal(2)
	await _main._run_human_shooting(shooter, foe)
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	assert_str(text) \
		.override_failure_message("rules-must-log: the marker AP names Piercing Growth (log: %s)" % text.strip_edges()) \
		.contains("Piercing Growth: Gunners adds AP(+1) from its growth markers")


# ===== Growth markers: applied and named on aof as well (verification, no new line) =====

func test_fortified_growth_applies_on_the_aof_carrier() -> void:
	var u := _unit(2, "Plague Bearers", Vector3(0.5 * INCH, 0, 0), ["Fortified Growth"], "aof", "daemons_of_plague")
	_main._solo_growth_round_start()
	_main._solo_growth_round_start()
	assert_int(_markers(u, "Fortified Growth")).is_equal(2)
	var fg: Dictionary = _main._solo_growth_incoming_ap(u)
	assert_str(str(fg.get("name", ""))) \
		.override_failure_message("fixture broken: the aof carrier's Fortified Growth did not resolve").is_equal("Fortified Growth")
	assert_int(int(fg.get("delta", 0))).is_equal(-1)
