extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-18: a unit is MOVED by Mind Control at most once per round. A second
## bearer that picks the same unit in the same round still forces its morale test (and the Shaken
## that follows), but the unit stays put. The latch clears at the start of the next round; epoch 72
## keeps today's reading — the second bearer moves it again.

const Boot := preload("res://test/e2e/e2e_boot.gd")

const IN_A := 0.0254

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
	_main.opr_army_manager.current_round = 3
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


## A Quality 4 enemy unit of player 1, five inches in front of the bearers' line.
func _target_unit() -> GameUnit:
	var u := Boot.make_unit(_main, 1, "Victim", [Vector3(5.0 * IN_A, 0, 0)])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## An AI player-2 Mind Control bearer (the registry's own gf entry) at `spot`.
func _mind_control_bearer(bearer_name: String, spot: Vector3) -> GameUnit:
	var bearer := Boot.make_unit(_main, 2, bearer_name, [spot])
	bearer.unit_properties["game_system"] = "gf"
	bearer.unit_properties["faction_folder"] = "jackals"
	bearer.unit_properties["special_rules"] = ["Mind Control"]
	_main.opr_army_manager.game_units[bearer.unit_id] = bearer
	return bearer


## Seeds the tray so its first die is a 3: a fail on the target's Quality 4.
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


func test_a_second_bearer_does_not_move_the_same_unit_again_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var target := _target_unit()
	var first := _mind_control_bearer("First", Vector3.ZERO)
	var second := _mind_control_bearer("Second", Vector3(0.5 * IN_A, 0, 0))
	var before: Vector3 = _main.solo_controller.unit_centre(target)
	_seed_first_die_three()
	await _main._solo_apply_mind_control(first)
	var after_first: Vector3 = _main.solo_controller.unit_centre(target)
	assert_float(before.distance_to(after_first)).override_failure_message(
		"epoch 73: the first bearer moves the target\n" + _log_text()).is_greater(5.0 * IN_A)
	_seed_first_die_three()
	await _main._solo_apply_mind_control(second)
	var after_second: Vector3 = _main.solo_controller.unit_centre(target)
	assert_float(after_first.distance_to(after_second)).override_failure_message(
		"epoch 73: the second bearer must not move it again\n" + _log_text()).is_equal_approx(0.0, 0.001)
	assert_str(_log_text()).contains("was already moved by Mind Control this round")


func test_the_latch_clears_at_the_start_of_the_next_round() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var target := _target_unit()
	var first := _mind_control_bearer("First", Vector3.ZERO)
	var second := _mind_control_bearer("Second", Vector3(0.5 * IN_A, 0, 0))
	_seed_first_die_three()
	await _main._solo_apply_mind_control(first)
	_main.opr_army_manager.current_round += 1
	var before: Vector3 = _main.solo_controller.unit_centre(target)
	_seed_first_die_three()
	await _main._solo_apply_mind_control(second)
	var after: Vector3 = _main.solo_controller.unit_centre(target)
	assert_float(before.distance_to(after)).override_failure_message(
		"next round: the latch is clear and the second bearer moves it\n" + _log_text()).is_greater(5.0 * IN_A)


func test_at_epoch_72_the_second_bearer_moves_it_again() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var target := _target_unit()
	var first := _mind_control_bearer("First", Vector3.ZERO)
	var second := _mind_control_bearer("Second", Vector3(0.5 * IN_A, 0, 0))
	_seed_first_die_three()
	await _main._solo_apply_mind_control(first)
	var before: Vector3 = _main.solo_controller.unit_centre(target)
	_seed_first_die_three()
	await _main._solo_apply_mind_control(second)
	var after: Vector3 = _main.solo_controller.unit_centre(target)
	assert_float(before.distance_to(after)).override_failure_message(
		"72 keeps today: the second bearer moves it again\n" + _log_text()).is_greater(5.0 * IN_A)
