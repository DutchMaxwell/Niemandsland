extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-23: one Target token per marked unit gives a FLAT +1 (AP for Piercing, to hit for
## Precision), and the Spotter rolls before the bearer's own attacks. Rules 3.5 (the EPOCH_72 leg) keeps the
## stacking reading. The core's twin is core/nml-core/src/tests/sim/v36_shoot_rows/sho_23.rs.

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


## The AI's bearer in the GF faction whose book prints the family (`custodian_brothers` = Piercing Target,
## `blessed_sisters` = Precision Target).
func _bearer(name: String, rule: String, faction: String) -> GameUnit:
	var u := _reg(E2EBoot.make_unit(_main, 2, name, [Vector3.ZERO]))
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = [rule]
	return u


## Two living models make this the tougher pick when two enemies are in reach.
func _big(pos: Vector3) -> GameUnit:
	return _reg(E2EBoot.make_unit(_main, 1, "Alpha", [pos, pos + Vector3(0.02 * INCH, 0, 0)]))


func _small(pos: Vector3) -> GameUnit:
	return _reg(E2EBoot.make_unit(_main, 1, "Bravo", [pos]))


func _tokens(u: GameUnit) -> int:
	return int(u.unit_properties.get("piercing_tag_markers", 0))


func test_piercing_target_spreads_one_token_on_each_of_two_units_at_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var bearer := _bearer("Marksman", "Piercing Target(2)", "custodian_brothers")
	var alpha := _big(Vector3(10.0 * INCH, 0, 0))
	var bravo := _small(Vector3(10.0 * INCH, 0, 6.0 * INCH))
	_main._solo_apply_piercing_tag(bearer)
	assert_int(_tokens(alpha)).override_failure_message("one token on the tougher unit").is_equal(1)
	assert_int(_tokens(bravo)).override_failure_message("one token on the second unit").is_equal(1)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log, the placement names each tagged unit — got: %s" % text.strip_edges()) \
		.contains("Piercing Target: Marksman places 1 token on each of")


## RED on main: two tokens on the same standing Target still return two +1s (stacking). From 73 the read is flat 1.
func test_piercing_target_reads_one_flat_ap_however_many_tokens_stand_at_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var alpha := _big(Vector3(10.0 * INCH, 0, 0))
	alpha.unit_properties["piercing_tag_markers"] = 2
	alpha.unit_properties["piercing_tag_source"] = "Piercing Target"
	var spent: int = _main._solo_spend_piercing_tag(alpha)
	assert_int(spent).override_failure_message("rules 3.6: one token, flat +1").is_equal(1)
	assert_int(_tokens(alpha)).override_failure_message("the standing token is never spent").is_equal(2)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log, the attack line says +1 (Target) — got: %s" % text.strip_edges()) \
		.contains("+1 (Target)")


func test_piercing_target_still_stacks_two_tokens_at_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var bearer := _bearer("Marksman", "Piercing Target(2)", "custodian_brothers")
	var alpha := _big(Vector3(10.0 * INCH, 0, 0))
	var bravo := _small(Vector3(10.0 * INCH, 0, 6.0 * INCH))
	_main._solo_apply_piercing_tag(bearer)
	assert_int(_tokens(alpha)).override_failure_message("3.5: every marker on the toughest unit").is_equal(2)
	assert_int(_tokens(bravo)).is_equal(0)
	assert_int(_main._solo_spend_piercing_tag(alpha)).override_failure_message("3.5: the stack reads whole").is_equal(2)

