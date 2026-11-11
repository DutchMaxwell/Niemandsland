extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-22b: the table's Precision Tag PLACEMENT. Every shipped map entry declares
## Precision Tag with the "Utility Buff" primitive (assets/solo/rules_mechanics_*.json), so the old finder
## (`unit_rules_of_primitive(member, "Precision Tag")`) returned nothing and a human bearer never marked
## anything, while the core's `tray_precision_markers` (core/nml-core/src/sim.rs) places it at every epoch.
## The table must answer what the core answers: same targets, same count, SHO-22's stack/spread wording.

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


## A HUMAN bearer (player 1) with the shipped gf/jackals entry: Precision Tag is a "Utility Buff" there.
func _tagger(x: int) -> GameUnit:
	var u := _reg(E2EBoot.make_unit(_main, 1, "Marksman", [Vector3.ZERO]))
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "jackals"
	u.unit_properties["special_rules"] = ["Precision Tag(%d)" % x]
	return u


## An AI-side enemy; `models` 2 makes it the tougher pick when two are in reach.
func _foe(pos: Vector3, models: int) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(pos + Vector3(0.02 * INCH * i, 0, 0))
	return _reg(E2EBoot.make_unit(_main, 2, "Alpha" if models > 1 else "Bravo", positions))


func _tokens(u: GameUnit) -> int:
	return int(u.unit_properties.get("tag_markers", 0))


func test_human_precision_tag_spreads_one_token_on_each_of_two_units_at_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var tagger := _tagger(2)
	var alpha := _foe(Vector3(10.0 * INCH, 0, 0), 2)
	var bravo := _foe(Vector3(10.0 * INCH, 0, 6.0 * INCH), 1)
	_main._solo_apply_precision_tag(tagger)
	assert_int(_tokens(alpha)).override_failure_message("one token on the tougher unit").is_equal(1)
	assert_int(_tokens(bravo)).override_failure_message("one token on the second unit").is_equal(1)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log, the placement names the spread — got: %s" % text.strip_edges()) \
		.contains("Precision Tag: Marksman places 1 token each, spread over 2 units")


func test_human_precision_tag_stacks_when_only_one_unit_is_in_reach_at_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var tagger := _tagger(2)
	var alpha := _foe(Vector3(10.0 * INCH, 0, 0), 2)
	_main._solo_apply_precision_tag(tagger)
	assert_int(_tokens(alpha)).override_failure_message("both tokens stack on the one unit").is_equal(2)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log, the placement names the stack — got: %s" % text.strip_edges()) \
		.contains("Precision Tag: Marksman places 2 tokens, stacked on Alpha")


func test_human_precision_tag_piles_everything_on_one_unit_below_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var tagger := _tagger(2)
	var alpha := _foe(Vector3(10.0 * INCH, 0, 0), 2)
	var bravo := _foe(Vector3(10.0 * INCH, 0, 6.0 * INCH), 1)
	_main._solo_apply_precision_tag(tagger)
	assert_int(_tokens(alpha)).override_failure_message("3.5: every marker on the toughest unit").is_equal(2)
	assert_int(_tokens(bravo)).is_equal(0)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log, the 3.5 wording — got: %s" % text.strip_edges()) \
		.contains("Precision Tag: Marksman places 2 markers on Alpha — friendly attackers may remove markers for +1 to hit each")


func test_human_precision_tag_is_once_per_game() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var tagger := _tagger(2)
	var alpha := _foe(Vector3(10.0 * INCH, 0, 0), 2)
	_main._solo_apply_precision_tag(tagger)
	_main._solo_apply_precision_tag(tagger)
	assert_int(_tokens(alpha)).override_failure_message("the second activation places nothing").is_equal(2)
