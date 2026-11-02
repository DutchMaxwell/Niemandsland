extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-23-fix: the table's Precision Target PLACEMENT. The core stopped stacking the
## markers at EPOCH_73_V36 (`tag_picks` + flat `hit_mod` in core/nml-core/src/sim.rs), but the table twin
## `_solo_apply_precision_target` still piled all X markers on one pick. From 73 it must put ONE token on
## each of up to X units (flat +1 each); the EPOCH_72 leg keeps the old single stacked record byte-exact.
## The core's twin is core/nml-core/src/tests/sim/v36_shoot_rows/sho_23.rs.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const MAP := "res://test/v36/sho_23fix_map.json"

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
	RulesRegistry.map_path_override.clear()
	RulesRegistry.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## The fixture map keeps a primitive-named common row, so the OLD primitive lookup still fires and its
## stacking is what the RED leg shows.
func _use_map() -> void:
	RulesRegistry.map_path_override["gf"] = MAP
	RulesRegistry.reset_cache()


func _use_real_map() -> void:
	RulesRegistry.map_path_override.clear()
	RulesRegistry.reset_cache()


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The AI's bearer in the GF faction (`test_fixture` has no faction row, so the map's common row answers;
## `blessed_sisters` is the shipped faction whose entry carries the Utility Buff primitive).
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


func _hit_mods(u: GameUnit) -> Array:
	var out: Array = []
	for rd in _main._solo_spell_mods.get(u.get_instance_id(), []):
		out.append(int((rd as Dictionary).get("hit_mod", 0)))
	return out


## RED on main: one record with +2 on the toughest pick, nothing on the second unit (the 3.5 stack).
func test_precision_target_puts_one_token_on_each_of_two_units_at_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_use_map()
	var bearer := _bearer("Marksman", "Precision Target(2)", "test_fixture")
	var alpha := _big(Vector3(10.0 * INCH, 0, 0))
	var bravo := _small(Vector3(10.0 * INCH, 0, 6.0 * INCH))
	_main._solo_apply_precision_target(bearer)
	assert_array(_hit_mods(alpha)).override_failure_message("one flat +1 token on the tougher unit").is_equal([1])
	assert_array(_hit_mods(bravo)).override_failure_message("one flat +1 token on the second unit").is_equal([1])
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log, the placement names each tagged unit — got: %s" % text.strip_edges()) \
		.contains("Precision Target: Marksman places 1 token on each of Alpha, Bravo")


## The pinned 3.5 leg: every marker rides ONE record on the toughest pick (byte-exact old stacking).
func test_precision_target_still_stacks_two_tokens_on_one_unit_at_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	_use_map()
	var bearer := _bearer("Marksman", "Precision Target(2)", "test_fixture")
	var alpha := _big(Vector3(10.0 * INCH, 0, 0))
	var bravo := _small(Vector3(10.0 * INCH, 0, 6.0 * INCH))
	_main._solo_apply_precision_target(bearer)
	assert_array(_hit_mods(alpha)).override_failure_message("3.5: both markers ride one record").is_equal([2])
	assert_array(_hit_mods(bravo)).is_equal([])
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log, the 3.5 record line — got: %s" % text.strip_edges()) \
		.contains("Precision Target on Alpha is ACTIVE: attackers get +2 to hit against it")


## The shipped map stamps Precision Target with the "Utility Buff" primitive (the SHO-22b shape), so the
## old primitive-named lookup never matched and the twin placed nothing; the Utility Buff entry must fire.
func test_precision_target_reads_the_shipped_utility_buff_entry_at_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_use_real_map()
	var bearer := _bearer("Marksman", "Precision Target(2)", "blessed_sisters")
	var alpha := _big(Vector3(10.0 * INCH, 0, 0))
	var bravo := _small(Vector3(10.0 * INCH, 0, 6.0 * INCH))
	_main._solo_apply_precision_target(bearer)
	assert_array(_hit_mods(alpha)).override_failure_message("the shipped entry places one flat +1").is_equal([1])
	assert_array(_hit_mods(bravo)).override_failure_message("the second pick gets its own +1").is_equal([1])
