extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-01: Fearless counts MOST living models of a joined unit (ruling D-MOST), a joined hero
## being one model. Below EPOCH_73_V36 every living model has to carry it. The core's twin is
## core/nml-core/src/tests/sim/v36_morale.rs.

const Boot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


## A Q4 AI unit of `models` models carrying `rules`.
func _unit(unit_name: String, rules: Array, models: int) -> GameUnit:
	var positions: Array = []
	for i in models:
		positions.append(Vector3(i, 0, 0))
	var unit := Boot.make_unit(_main, 2, unit_name, positions)
	unit.unit_properties["quality"] = 4
	unit.unit_properties["special_rules"] = rules
	return unit


## Host `unit_name` of `models` models with one joined hero.
func _joined(unit_name: String, host_rules: Array, models: int, hero_rules: Array) -> GameUnit:
	var squad := _unit(unit_name, host_rules, models)
	var hero := _unit(unit_name + " Captain", hero_rules, 1)
	hero.unit_properties["attached_to"] = squad
	squad.unit_properties["attached_heroes"] = [hero]
	return squad


func _log_text() -> String:
	var text := ""
	for entry in _main.battle_log.entries():
		text += str(entry["text"]) + "\n"
	return text


## Runs the Shaken unit's morale test: it fails for certain, so only the Fearless recovery die can save it.
func _shaken_test(squad: GameUnit) -> void:
	squad.is_shaken = true
	_main.seed_tray_rng(7)
	await _main._solo_morale_test(squad, "AI (%s)" % squad.get_name())


func test_most_models_decide_fearless_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var five := _joined("Five", ["Fearless"], 5, ["Hero"])
	assert_bool(BattleSim._morale_fails_expected({"unit": five, "shaken": false})).is_false()
	await _shaken_test(five)
	assert_str(_log_text()).contains("Five is Fearless — recovery die")
	assert_str(_log_text()).contains("Fearless: 5 of 6 models of Five")
	var pair := _joined("Pair", ["Fearless"], 1, ["Hero"])
	assert_bool(BattleSim._morale_fails_expected({"unit": pair, "shaken": false})).is_true()
	await _shaken_test(pair)
	assert_str(_log_text()).not_contains("Pair is Fearless — recovery die")
	var trio := _joined("Trio", [], 3, ["Hero", "Fearless"])
	await _shaken_test(trio)
	assert_str(_log_text()).not_contains("Trio is Fearless — recovery die")
	var whole := _joined("Whole", ["Fearless"], 2, ["Hero", "Fearless"])
	await _shaken_test(whole)
	assert_str(_log_text()).contains("Whole is Fearless — recovery die")
	assert_str(_log_text()).not_contains("models of Whole")


func test_fearless_needs_every_model_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var five := _joined("Five", ["Fearless"], 5, ["Hero"])
	assert_bool(BattleSim._morale_fails_expected({"unit": five, "shaken": false})).is_true()
	await _shaken_test(five)
	assert_str(_log_text()).not_contains("Five is Fearless — recovery die")
	assert_str(_log_text()).not_contains("models of Five")
