extends GdUnitTestSuite
## G4R5 R14 (PARITY_DIAG_1105_R5_UNEXPL 2.4, gf_1000_net_024 act 26): a UNIT rule that resolves to the Bane primitive
## without cutting Regeneration (Scrapper: the Defense-6 re-roll only, `bypass_regen: false`) still cut the target's
## Regeneration in the table's flag loop and logged "Bane (granted)". The unit-level alias stamp writes
## `bane = true, bypass_regen = false` but sets no `bane_alias`, so the loop's alias guard never held. The core keeps
## the Regeneration roll. From EPOCH_73_V36 an explicit `bypass_regen = false` keeps the roll; an ABSENT key (a printed
## Bane) still bypasses, which the control below pins. Driven through the real AI volley (`_run_ai_shooting`) over
## main.tscn with real units built the way the game builds them (faction book, rule lists).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
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
	# both seats AI: saves auto-resolve, no dialog
	SoloHarness.start(_main, [1, 2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	RulesRegistry.reset_cache()


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	AiActRecorder.rules_epoch = _epoch_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	RulesRegistry.reset_cache()


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## A shooter with a heavy rifle volley; `unit_rules` are its own (Scrapper), `weapon_rules` the rifle's (a printed Bane).
func _shooter(unit_rules: Array, weapon_rules: Array[String]) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 2, "Vultures", [Vector3.ZERO, Vector3(0.02, 0.0, 0.0)])
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "jackals"
	u.unit_properties["special_rules"] = unit_rules
	u.unit_properties["quality"] = 2
	var rifle := OPRApiClient.OPRWeapon.new()
	rifle.name = "Force Blaster"
	rifle.range_value = REACH
	rifle.attacks = 30
	rifle.count = 1
	rifle.special_rules = weapon_rules
	var opr := OPRApiClient.OPRUnit.new()
	opr.weapons.append(rifle)
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A Regeneration target 10" away: Def 6+, plenty of wounds, so the volley lands wounds for certain.
func _regenerator() -> GameUnit:
	var t := E2EBoot.make_unit(_main, 1, "Purgation", [Vector3(10.0 * INCH, 0.0, 0.0)])
	t.unit_properties["game_system"] = "gf"
	t.unit_properties["faction_folder"] = "jackals"
	t.unit_properties["special_rules"] = ["Regeneration"]
	t.unit_properties["defense"] = 6
	t.models[0].wounds_max = 30
	t.models[0].wounds_current = 30
	_main.opr_army_manager.game_units[t.unit_id] = t
	return t


func _volley(unit_rules: Array, weapon_rules: Array[String]) -> String:
	var shooter := _shooter(unit_rules, weapon_rules)
	_regenerator()
	_main._tray_rng.seed = 7
	await _door_ai(ActIntent.blank_report(shooter))
	return _log_text()


## The game's own call: the core door takes the AI's volley (the board is captured first), as the lone-hero door suite does.
## The epoch is the live one: the table's epoch-73 gates are the core's from its own epochs on.
func _door_ai(report: Dictionary) -> void:
	AiActRecorder.rules_epoch = _epoch_before
	CoreActivation._env = 1
	var runs := CoreActivation.ai_runs
	_main._solo_core_ai_h = CoreActivation.capture(_main)
	await _main._run_ai_shooting(report)
	assert_int(CoreActivation.ai_runs).override_failure_message("the core did not take the volley (the table shot it)") \
		.is_equal(runs + 1)
	if _main._solo_core_ai_h != 0:
		_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
	_main._solo_core_ai_h = 0


## The Scrapper alias re-rolls Defense 6s but does not cut Regeneration: the target still rolls its dice.
func test_a_unit_alias_without_bypass_leaves_the_regeneration_roll_at_73(timeout := 60000) -> void:
	var text: String = await _volley(["Scrapper"], [])
	assert_str(text).override_failure_message("the volley must land wounds for the test to bite (log: %s)" % text.strip_edges()) \
		.contains("Purgation takes")
	assert_str(text).override_failure_message("a no-bypass alias must not log a Bane grant (log: %s)" % text.strip_edges()) \
		.not_contains("Bane (granted)")
	assert_str(text).override_failure_message("the Regeneration dice must roll (log: %s)" % text.strip_edges()) \
		.contains("regeneration di")
	await E2EBoot.settle(get_tree())


## Control: a PRINTED Bane has no `bypass_regen` key and still cuts through Regeneration - no regeneration roll.
func test_a_printed_bane_still_cuts_regeneration_at_73(timeout := 60000) -> void:
	var text: String = await _volley([], ["Bane"] as Array[String])
	assert_str(text).override_failure_message("the volley must land wounds for the test to bite (log: %s)" % text.strip_edges()) \
		.contains("Purgation takes")
	assert_str(text).override_failure_message("a printed Bane ignores Regeneration (log: %s)" % text.strip_edges()) \
		.contains("wounds ignore Regeneration")
	assert_str(text).not_contains("regeneration di")
	await E2EBoot.settle(get_tree())
