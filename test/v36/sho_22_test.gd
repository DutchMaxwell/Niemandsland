extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-22: Piercing Tag and Precision Tag carry TOKENS. The bearer stacks X tokens on one enemy
## unit or puts one token on each of up to X enemy units, and each friendly attack spends ONE token for +1.
## Rules 3.5 (the EPOCH_72 leg) piled every marker on one unit and the first attack spent them all. The core's twin
## is core/nml-core/src/tests/sim/v36_shoot.rs. Placement is the AI's pick on the table; the human spends the same way.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The AI's tagger (alien_hives prints the plain Piercing Tag) rated for `x` tokens.
func _tagger(x: int) -> GameUnit:
	var u := _reg(E2EBoot.make_unit(_main, 2, "Marksman", [Vector3.ZERO]))
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "alien_hives"
	u.unit_properties["special_rules"] = ["Piercing Tag(%d)" % x]
	return u


## Two living models make this the tougher pick when two enemies are in reach.
func _big(pos: Vector3) -> GameUnit:
	return _reg(E2EBoot.make_unit(_main, 1, "Alpha", [pos, pos + Vector3(0.02 * INCH, 0, 0)]))


func _small(pos: Vector3) -> GameUnit:
	return _reg(E2EBoot.make_unit(_main, 1, "Bravo", [pos]))


func _tokens(u: GameUnit) -> int:
	return int(u.unit_properties.get("piercing_tag_markers", 0))


func test_piercing_tag_spreads_one_token_on_each_of_two_units_at_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var tagger := _tagger(2)
	var alpha := _big(Vector3(10.0 * INCH, 0, 0))
	var bravo := _small(Vector3(10.0 * INCH, 0, 6.0 * INCH))
	_main._solo_apply_piercing_tag(tagger)
	assert_int(_tokens(alpha)).override_failure_message("one token on the tougher unit").is_equal(1)
	assert_int(_tokens(bravo)).override_failure_message("one token on the second unit").is_equal(1)
	var spent: int = _main._solo_spend_piercing_tag(alpha)
	assert_int(spent).override_failure_message("ONE token for +1, not every marker").is_equal(1)
	assert_int(_tokens(alpha)).is_equal(0)
	assert_int(_tokens(bravo)).override_failure_message("the other unit keeps its token").is_equal(1)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log, the placement names the spread — got: %s" % text.strip_edges()) \
		.contains("Piercing Tag: Marksman places 1 token each, spread over 2 units")
	assert_str(text) \
		.override_failure_message("rules-must-log, the spend names one token, +1 — got: %s" % text.strip_edges()) \
		.contains("Piercing Tag: one token spent — +1 AP")


func test_piercing_tag_stacks_when_only_one_unit_is_in_reach_at_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var tagger := _tagger(2)
	var alpha := _big(Vector3(10.0 * INCH, 0, 0))
	_main._solo_apply_piercing_tag(tagger)
	assert_int(_tokens(alpha)).override_failure_message("both tokens stack on the one unit").is_equal(2)
	var spent: int = _main._solo_spend_piercing_tag(alpha)
	assert_int(spent).override_failure_message("ONE token for +1 even from a stack").is_equal(1)
	assert_int(_tokens(alpha)).is_equal(1)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log, the placement names the stack — got: %s" % text.strip_edges()) \
		.contains("Piercing Tag: Marksman places 2 tokens, stacked on Alpha")


func test_piercing_tag_still_piles_everything_on_one_unit_at_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var tagger := _tagger(2)
	var alpha := _big(Vector3(10.0 * INCH, 0, 0))
	var bravo := _small(Vector3(10.0 * INCH, 0, 6.0 * INCH))
	_main._solo_apply_piercing_tag(tagger)
	assert_int(_tokens(alpha)).override_failure_message("3.5: every marker on the toughest unit").is_equal(2)
	assert_int(_tokens(bravo)).is_equal(0)
	var spent: int = _main._solo_spend_piercing_tag(alpha)
	assert_int(spent).override_failure_message("3.5: the first attack spends them all").is_equal(2)
	assert_int(_tokens(alpha)).is_equal(0)


## Precision Tag's pool is spent one token per attack too (the placement is the core's; the table's pick pool rides
## the same property the replay ledger carries).
func test_precision_tag_spends_one_token_per_attack_at_73_and_all_at_72() -> void:
	var target := _small(Vector3(10.0 * INCH, 0, 0))
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	target.unit_properties["tag_markers"] = 2
	assert_int(_main._solo_consume_tag_markers(target)).override_failure_message("3.5: both removed").is_equal(2)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	target.unit_properties["tag_markers"] = 2
	assert_int(_main._solo_consume_tag_markers(target)).override_failure_message("3.6: one token, +1").is_equal(1)
	assert_int(int(target.unit_properties.get("tag_markers", 0))).override_failure_message("one token is left").is_equal(1)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log — got: %s" % text.strip_edges()) \
		.contains("Precision Tag: one token spent — +1 to hit")
