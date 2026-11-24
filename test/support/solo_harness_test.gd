extends GdUnitTestSuite
## The SoloHarness test facade on a loaded main.tscn, driven ONLY through the facade and checked on
## the observable result: `start` gives a controller on the requested seats, `instant` takes the
## pacing holds out, `auto_saves` leaves the save dialog closed. The facade is the one place tests
## touch main.gd's solo setup members, so extracting that code later touches one file instead of
## every suite. Real: the main scene. No core path is driven here.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## `start` builds the controller on the requested seats: the AI plays `ai_slot`, the human holds
## `human_slot`.
func test_start_gives_a_controller_on_the_requested_seats() -> void:
	var controller := SoloHarness.start(_main, [2], 1)
	assert_object(controller).is_not_null()
	(
		assert_int(controller.ai_slot)
		. override_failure_message("start put the AI on the wrong seat")
		. is_equal(2)
	)
	(
		assert_int(controller.human_slot)
		. override_failure_message("start put the human on the wrong seat")
		. is_equal(1)
	)
	assert_bool(_main.solo_ai_slots.has(2)).is_true()


## `controller` builds the controller without touching the table's seats: a hotseat table that keeps
## its own slot set gets a controller and the set comes back exactly as it was.
func test_controller_leaves_the_slots_untouched() -> void:
	_main.solo_ai_slots = {1: true}
	var before: Dictionary = _main.solo_ai_slots.duplicate()
	var controller := SoloHarness.controller(_main)
	assert_object(controller).is_not_null()
	(
		assert_dict(_main.solo_ai_slots)
		. override_failure_message("controller() rewrote solo_ai_slots")
		. is_equal(before)
	)


## `instant` removes the pacing holds: an announce hold returns in the same frame (batch means no
## timer). The off run first proves the measurement sees a real hold, so the on run cannot pass
## vacuously.
func test_instant_takes_the_pacing_holds_out() -> void:
	SoloHarness.instant(_main, false)
	var off_before := Engine.get_process_frames()
	await _main._solo_pace_hold(SoloController.Pace.ANNOUNCE)
	var off_frames := Engine.get_process_frames() - off_before
	(
		assert_int(off_frames)
		. override_failure_message("no pacing hold with instant off: the check proves nothing")
		. is_greater(0)
	)
	SoloHarness.instant(_main, true)
	var on_before := Engine.get_process_frames()
	await _main._solo_pace_hold(SoloController.Pace.ANNOUNCE)
	(
		assert_int(Engine.get_process_frames() - on_before)
		. override_failure_message("instant still waited a pacing hold")
		. is_equal(0)
	)


## `auto_saves` leaves the "Incoming fire!" save dialog closed: the asks returns without adding a
## card.
func test_auto_saves_leaves_the_save_dialog_closed() -> void:
	SoloHarness.start(_main, [2], 1)
	SoloHarness.auto_saves(_main, true)
	var before := _prompt_cards()
	_main._solo_ask_saves(_unit("Att", 2), _unit("Def", 1), "Rifle", 3, 4, 0)
	await _main.get_tree().process_frame
	(
		assert_int(_prompt_cards())
		. override_failure_message("auto_saves opened the save dialog")
		. is_equal(before)
	)


func _unit(unit_name: String, slot: int) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_id = unit_name
	unit.unit_properties = {
		"player_id": slot, "name": unit_name, "quality": 4, "defense": 4, "special_rules": []
	}
	return unit


func _prompt_cards() -> int:
	var count := 0
	for child in _main.get_children():
		if child is PromptCard:
			count += 1
	return count
