extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-08: a Banner's +1 only helps a morale test that shooting or melee caused.
## Mind Control forces a test that is neither, so from epoch 73 a Banner unit tests on its plain
## Quality there. Volley and melee tests keep the +1; epoch 72 keeps the old reading everywhere.

const Boot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
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
	AiActRecorder.rules_epoch = _epoch_before
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


## A Quality 4 Banner unit of `models` models for player 1, registered on the board.
func _banner_unit(models: int) -> GameUnit:
	var spots: Array = []
	for i in range(models):
		spots.append(Vector3(0.05 + 0.03 * i, 0, 0))
	var u := Boot.make_unit(_main, 1, "Victim", spots)
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["special_rules"] = ["Banner"]
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The AI Mind Control bearer next to the target (the registry's own gf entry).
func _mind_control_bearer() -> GameUnit:
	var bearer := Boot.make_unit(_main, 2, "Controller", [Vector3.ZERO])
	bearer.unit_properties["game_system"] = "gf"
	bearer.unit_properties["faction_folder"] = "jackals"
	bearer.unit_properties["special_rules"] = ["Mind Control"]
	_main.opr_army_manager.game_units[bearer.unit_id] = bearer
	return bearer


## Seeds the tray so its first die is a 3: a pass on 3+ (with the Banner), a fail on 4+ (without).
func _seed_first_die_three() -> void:
	var rng := RandomNumberGenerator.new()
	for candidate in range(200):
		rng.seed = candidate
		if rng.randi_range(1, 6) == 3:
			_main.seed_tray_rng(candidate)
			return
	fail("no seed rolls a 3 first")


func _log_text() -> String:
	var out := ""
	for entry in _main.battle_log.entries():
		out += str(entry["text"]) + "\n"
	return out


func test_mind_control_tests_a_banner_unit_on_its_plain_quality_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var target := _banner_unit(1)
	var bearer := _mind_control_bearer()
	_seed_first_die_three()
	await _main._solo_apply_mind_control(bearer)
	assert_bool(target.is_shaken) \
		.override_failure_message("epoch 73: the Banner must not help against Mind Control, the 3 fails 4+\n" + _log_text()) \
		.is_true()
	assert_str(_log_text()).contains("Banner: Victim gets no +1 against Mind Control")


func test_mind_control_keeps_the_banner_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var target := _banner_unit(1)
	var bearer := _mind_control_bearer()
	_seed_first_die_three()
	await _main._solo_apply_mind_control(bearer)
	assert_bool(target.is_shaken).is_false()
	assert_str(_log_text()).contains("Banner: Victim gets +1 to morale test rolls (passes on 3+)")
	assert_str(_log_text()).not_contains("gets no +1")


func test_a_shooting_morale_test_keeps_the_banner_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var target := _banner_unit(2)
	var wounds_before: int = _main._solo_unit_wounds_now(target)
	(target.models[1] as ModelInstance).is_alive = false
	_seed_first_die_three()
	await _main._solo_shooting_morale(target, 2, "Victim", wounds_before)
	assert_bool(target.is_shaken).is_false()
	assert_str(_log_text()).contains("Banner: Victim gets +1 to morale test rolls (passes on 3+)")
	assert_str(_log_text()).not_contains("gets no +1")


func test_a_melee_morale_test_keeps_the_banner_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var target := _banner_unit(1)
	_seed_first_die_three()
	await _main._solo_morale_test(target, "Victim", true)
	assert_bool(target.is_shaken).is_false()
	assert_str(_log_text()).contains("Banner: Victim gets +1 to morale test rolls (passes on 3+)")
	assert_str(_log_text()).not_contains("gets no +1")
