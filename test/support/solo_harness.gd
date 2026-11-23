class_name SoloHarness
## Test facade for a solo game on a loaded main.tscn: slots, pacing and dice modes.
##
## WHY THIS LAYER EXISTS. Suites set up a solo game by writing main.gd's private members directly
## (`solo_ai_slots`, `_ensure_solo_controller()`, `solo_controller.ai_slot`, `solo_controller.human_slot`,
## `_solo_batch`, `_solo_fast`, `_solo_auto_saves`). Every extraction from main.gd then breaks those
## tests although no behaviour changes. With this one facade, moving that code touches one file.
##
## These four functions are the whole interface: `start` builds the controller, `instant`/`fast` pick the
## pacing, `auto_saves` skips the save dialog. A test that needs more keeps that one line after `start`.

## Start a solo game on a loaded main scene: AI slots, the human slot, the controller ready.
## `ai_slots` are the player ids the Solo AI controls; the controller's active seat is the first AI slot
## that is not `human_slot` (the shape the suites use: `solo_ai_slots = {1: true, 2: true}`, `ai_slot = 2`).
static func start(main: Node, ai_slots: Array[int] = [2], human_slot := 1) -> SoloController:
	var slots: Dictionary = {}
	for slot in ai_slots:
		slots[slot] = true
	main.solo_ai_slots = slots
	main._ensure_solo_controller()
	var controller: SoloController = main.solo_controller
	if controller == null:
		return null
	var ai_slot: int = human_slot
	for slot in ai_slots:
		if slot != human_slot:
			ai_slot = slot
			break
	controller.ai_slot = ai_slot
	controller.human_slot = human_slot
	return controller


## Instant dice and no pacing holds (headless sweeps); implies fast.
static func instant(main: Node, on := true) -> void:
	main._solo_batch = on
	main._solo_fast = on


## Shorter pacing holds and no move animation.
static func fast(main: Node, on := true) -> void:
	main._solo_fast = on


## Saves roll straight to the tray without the save dialog.
static func auto_saves(main: Node, on := true) -> void:
	main._solo_auto_saves = on
