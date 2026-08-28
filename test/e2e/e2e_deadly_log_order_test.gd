extends GdUnitTestSuite
## E2E — NML-1090: the Deadly(X) line must stand BEFORE the removal it caused.
##
## What was broken: _solo_land_deadly_wounds applied the multiplied wounds first and logged the
## multiplication afterwards. The model death runs through set_loose_model_dead, whose
## loose_model_dead_changed signal writes "<unit> destroyed" / "<unit> loses a model" into the battle
## log — so the reader saw the EFFECT one line above its CAUSE:
##     Ogre destroyed
##     Deadly(3): 1 unsaved ×3, no carry-over → 3 wounds dealt
## Only the log ORDER is at stake here; the wounds dealt are asserted alongside, so a "fix" that
## changed the arithmetic instead of the order cannot pass.
##
## This has to ride the real scene: the destruction line is emitted by main.gd's own signal wiring,
## which no unit-level suite has.

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


## Position of the first entry containing `needle`, or -1.
func _index_of(needle: String) -> int:
	var entries: Array = _main.battle_log.entries()
	for i in range(entries.size()):
		if str((entries[i] as Dictionary)["text"]).contains(needle):
			return i
	return -1


## A registered unit of Tough(3) models — one unsaved wound with Deadly(3) takes a whole model down.
func _tough_unit(unit_name: String, models: int) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(Vector3(8.0 * INCH, 0.0, 0.02 * i))
	var u := E2EBoot.make_unit(_main, 2, unit_name, positions)
	u.unit_properties["special_rules"] = ["Tough(3)"]
	for m in u.models:
		(m as ModelInstance).wounds_max = 3
		(m as ModelInstance).wounds_current = 3
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


# ===== (1) the ROT case: the last model dies, and the log read effect-before-cause =====

func test_the_deadly_line_stands_before_the_destruction_it_caused(timeout := 240000) -> void:
	var target := _tough_unit("Ogre", 1)
	var dealt: int = await _main._solo_land_deadly_wounds(target, "Hammer", 3, 0, 1)
	assert_int(dealt) \
		.override_failure_message("fixture check: 1 unsaved ×3 must take the whole Tough(3) model down") \
		.is_equal(3)
	var deadly_at := _index_of("Deadly(3)")
	var destroyed_at := _index_of("Ogre destroyed")
	assert_int(deadly_at) \
		.override_failure_message("the Deadly line vanished from the log:\n%s" % _log_text()) \
		.is_greater_equal(0)
	assert_int(destroyed_at) \
		.override_failure_message("the destruction line vanished from the log:\n%s" % _log_text()) \
		.is_greater_equal(0)
	assert_int(deadly_at) \
		.override_failure_message("cause before effect: the Deadly line must be logged BEFORE the destruction it caused:\n%s" % _log_text()) \
		.is_less(destroyed_at)
	await E2EBoot.settle(get_tree())


# ===== (2) the same inversion one step down: a single model lost out of a surviving unit =====

func test_the_deadly_line_stands_before_the_lost_model_line(timeout := 240000) -> void:
	var target := _tough_unit("Ogres", 2)
	var dealt: int = await _main._solo_land_deadly_wounds(target, "Hammer", 3, 0, 1)
	assert_int(dealt).is_equal(3)
	var deadly_at := _index_of("Deadly(3)")
	var lost_at := _index_of("Ogres loses a model")
	assert_int(lost_at) \
		.override_failure_message("the lost-model line vanished from the log:\n%s" % _log_text()) \
		.is_greater_equal(0)
	assert_int(deadly_at) \
		.override_failure_message("cause before effect: the Deadly line must be logged BEFORE the model it removed:\n%s" % _log_text()) \
		.is_less(lost_at)
	await E2EBoot.settle(get_tree())


# ===== (3) counter-check: the wounds themselves are untouched — order only =====

func test_the_wounds_dealt_and_the_line_text_are_unchanged(timeout := 240000) -> void:
	var target := _tough_unit("Brutes", 1)
	target.models[0].wounds_current = 3
	# One unsaved wound, Deadly(2): 2 of the 3 wounds land, the model survives, nothing is removed.
	var dealt: int = await _main._solo_land_deadly_wounds(target, "Axe", 2, 0, 1)
	assert_int(dealt).is_equal(2)
	assert_int(int(target.models[0].wounds_current)) \
		.override_failure_message("the arithmetic must be untouched — this ticket is log ORDER only") \
		.is_equal(1)
	assert_bool(bool(target.models[0].is_alive)).is_true()
	assert_str(_log_text()) \
		.override_failure_message("the standing Deadly line text must not change:\n%s" % _log_text()) \
		.contains("Deadly(2): 1 unsaved ×2, no carry-over → 2 wounds dealt")
	await E2EBoot.settle(get_tree())
