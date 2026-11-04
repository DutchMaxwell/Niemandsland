extends GdUnitTestSuite
## Rules 3.6 wave, AI gate AI-G4 (T-GATE-REACH): the table's shooting reach test measures the NEAREST model
## of the target (base edge to base edge, like the core), never the unit centres, from the 3.6 epoch on. A
## Mounted-Peasants-like block of ten bowmen stands 33" (centre to centre) from a lone foe whose nearest
## model is 22.7" from the block's nearest bowman: the 24" bow reaches, and the battle log names the rule.
## Below the epoch the centre reading stays byte for byte. The controls come first (gdUnit drops the cases
## declared after a failing one in a scene suite).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := Vector3(0.03, 0.0, 0.03)   # a point inside some 3" terrain cell
const REACH := 24

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
	RulesRegistry.reset_cache()


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


## Ten bowmen in a line, 2" apart (the unit centre sits 9" along it), a 24" bow each.
func _peasants() -> GameUnit:
	var spots: Array = []
	for i in range(10):
		spots.append(SEED + Vector3(i * 2.0 * INCH, 0.0, 0.0))
	var u := E2EBoot.make_unit(_main, 2, "Mounted Peasants", spots)
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["special_rules"] = []
	var bow := OPRApiClient.OPRWeapon.new()
	bow.name = "Bow"
	bow.range_value = REACH
	bow.attacks = 1
	bow.count = 1
	var opr := OPRApiClient.OPRUnit.new()
	opr.weapons.append(bow)
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A lone foe whose model stands `pair_in` inches (centre to centre) east of the block's last bowman.
func _foe(unit_name: String, pair_in: float) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, unit_name, [SEED + Vector3((18.0 + pair_in) * INCH, 0.0, 0.0)])
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["special_rules"] = []
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## One Hold-and-shoot activation of `shooter` at `target`, through the controller's own intent door and the
## table's rule-note printer. `source` "ai" lets the post-move retarget run; "player" never retargets.
func _hold(shooter: GameUnit, target: GameUnit, source: String) -> Dictionary:
	var solo: SoloController = _main.solo_controller
	var intent := solo.player_intent(shooter, AiDecision.Action.HOLD, target)
	intent["source"] = source
	var report := solo.execute_intent(intent, ActIntent.blank_report(shooter))
	_main._print_rule_notes(report)
	return report


## Control: at 73 a foe whose nearest model is still beyond the bow (25.2") stays out of reach, and the
## no-shot reason reads the nearest-model gap (25.2"), not the centre gap (35.5").
func test_a_foe_beyond_the_nearest_model_reach_stays_unshot_at_73() -> void:
	var shooter := _peasants()
	var foe := _foe("Woodsman", 26.5)
	var report := _hold(shooter, foe, "ai")
	var text := _log_text()
	assert_bool(bool(report["can_shoot"])).is_false()
	assert_str(text) \
		.override_failure_message("the reason must read the nearest-model gap (log: %s)" % text.strip_edges()) \
		.contains("nearest enemy 25.2\" away")
	assert_str(text).not_contains("Mounted Peasants: Shooting")


## Control: below the 3.6 epoch the centre reading stands byte for byte - the same block and foe stay unshot
## and the reason prints the 33.0" centre gap.
func test_below_73_the_centre_reading_stays() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var shooter := _peasants()
	var foe := _foe("Woodsman", 24.0)
	var report := _hold(shooter, foe, "ai")
	var text := _log_text()
	assert_bool(bool(report["can_shoot"])).is_false()
	assert_str(text) \
		.override_failure_message("below 73 the reason keeps the centre gap (log: %s)" % text.strip_edges()) \
		.contains("nearest enemy 33.0\" away")
	assert_str(text).not_contains("Mounted Peasants: Shooting")


## The decided target is reached by its nearest model, though the unit centres are 33" apart.
func test_a_hold_shoots_when_the_nearest_model_is_in_reach_at_73() -> void:
	var shooter := _peasants()
	var foe := _foe("Woodsman", 24.0)
	var report := _hold(shooter, foe, "player")
	var text := _log_text()
	assert_bool(bool(report["can_shoot"])) \
		.override_failure_message("the nearest bowman is 22.7\" from the foe - the bow reaches").is_true()
	assert_str(text) \
		.override_failure_message("rules-must-log: the shot names the Shooting rule (log: %s)" % text.strip_edges()) \
		.contains("Mounted Peasants: Shooting")


## The post-move retarget: the decided target is far out, a second foe is in reach by its nearest model only.
func test_the_retarget_picks_the_foe_in_nearest_model_reach_at_73() -> void:
	var shooter := _peasants()
	var decoy := _foe("Decoy", 60.0)
	var near := _foe("Woodsman", 24.0)
	assert_object(_main.solo_controller.best_shoot_target_now(shooter, true)) \
		.override_failure_message("the picker measured the unit centres").is_same(near)
	var report := _hold(shooter, decoy, "ai")
	var text := _log_text()
	assert_bool(bool(report["can_shoot"])).is_true()
	assert_str(text) \
		.override_failure_message("rules-must-log: the retarget names the Shooting rule (log: %s)" % text.strip_edges()) \
		.contains("Mounted Peasants: Shooting")
