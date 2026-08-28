extends GdUnitTestSuite
## E2E — NML-1091: a lone Tough model reports its WOUNDS, not the meaningless model counter.
##
## What was broken: the wound line always printed the model counter, so a single-model Tough(6) unit
## read "Ogre takes 2 wounds (1/1)" on every hit — the same two numbers from full health to the last
## wound, while the number the reader actually needs (how much is left in the model) was nowhere.
## Multi-model units are NOT affected: their model counter is exactly the right figure and must stay.
##
## This has to ride the real scene: the counter is assembled in main.gd's own wound path
## (_solo_apply_wounds), which no unit-level suite reaches.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	# Batch mode is the harness lever for the physics dice tray: fair faces, drawn instantly.
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## A registered unit of `models` models, each with `wounds` wounds (Tough(N) when N > 1).
func _unit(unit_name: String, models: int, wounds: int) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(Vector3(8.0 * INCH, 0.0, 0.02 * i))
	var u := E2EBoot.make_unit(_main, 2, unit_name, positions)
	if wounds > 1:
		u.unit_properties["special_rules"] = ["Tough(%d)" % wounds]
	for m in u.models:
		(m as ModelInstance).wounds_max = wounds
		(m as ModelInstance).wounds_current = wounds
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


# ===== (1) the ROT case: one Tough model, and the counter that never moved =====

func test_a_lone_tough_model_logs_its_remaining_wounds(timeout := 240000) -> void:
	var target := _unit("Ogre", 1, 6)
	await _main._solo_apply_wounds(target, 2)
	assert_int(int(target.models[0].wounds_current)) \
		.override_failure_message("fixture check: the two wounds must actually land on the model") \
		.is_equal(4)
	assert_str(_log_text()) \
		.override_failure_message("a lone Tough model must report the wounds it has left:\n%s" % _log_text()) \
		.contains("Ogre takes 2 wounds (4/6 wounds)")
	assert_str(_log_text()) \
		.override_failure_message("the model counter says nothing at all for a one-model unit:\n%s" % _log_text()) \
		.not_contains("(1/1)")
	await E2EBoot.settle(get_tree())


## The counter has to keep MOVING — the whole point is that a second hit reads differently.
func test_the_counter_moves_with_every_hit(timeout := 240000) -> void:
	var target := _unit("Ogre", 1, 6)
	await _main._solo_apply_wounds(target, 2)
	await _main._solo_apply_wounds(target, 3)
	var text := _log_text()
	assert_str(text).contains("Ogre takes 2 wounds (4/6 wounds)")
	assert_str(text) \
		.override_failure_message("the second hit must read differently from the first:\n%s" % text) \
		.contains("Ogre takes 3 wounds (1/6 wounds)")
	await E2EBoot.settle(get_tree())


# ===== (2) counter-check: the model counter is right for everybody else and must not move =====

func test_a_multi_model_unit_keeps_the_model_counter(timeout := 240000) -> void:
	var target := _unit("Grunts", 3, 1)
	await _main._solo_apply_wounds(target, 1)
	assert_str(_log_text()) \
		.override_failure_message("a multi-model unit's counter is the right figure and must not change:\n%s" % _log_text()) \
		.contains("Grunts takes 1 wound (2/3)")
	assert_str(_log_text()) \
		.override_failure_message("a multi-model unit must not report wounds instead of models:\n%s" % _log_text()) \
		.not_contains("wounds)")
	await E2EBoot.settle(get_tree())


func test_a_multi_model_tough_unit_keeps_the_model_counter(timeout := 240000) -> void:
	# Tough alone is not the trigger — with more than one model the counter still says something.
	var target := _unit("Trolls", 2, 3)
	await _main._solo_apply_wounds(target, 3)
	assert_str(_log_text()) \
		.override_failure_message("a Tough unit of two models still has a meaningful model counter:\n%s" % _log_text()) \
		.contains("Trolls takes 3 wounds (1/2)")
	await E2EBoot.settle(get_tree())


func test_a_lone_single_wound_model_keeps_the_model_counter(timeout := 240000) -> void:
	# No Tough, one model: nothing to report but the model itself — the old line stands.
	var target := _unit("Scout", 1, 1)
	await _main._solo_apply_wounds(target, 1)
	assert_str(_log_text()) \
		.override_failure_message("a one-wound model has no wound counter to print:\n%s" % _log_text()) \
		.contains("Scout takes 1 wound (0/1)")
	await E2EBoot.settle(get_tree())
