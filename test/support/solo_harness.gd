class_name SoloHarness
## Test facade for a solo game on a loaded main.tscn: slots, pacing and dice modes.
##
## WHY THIS LAYER EXISTS. Suites set up a solo game by writing main.gd's private members directly
## (`solo_ai_slots`, `_ensure_solo_controller()`, `solo_controller.ai_slot`,
## `solo_controller.human_slot`, `_solo_batch`, `_solo_fast`, `_solo_auto_saves`). Every extraction
## from main.gd then breaks those tests although no behaviour changes. With this one facade, moving
## that code touches one file.
##
## These five functions are the whole interface: `controller` builds the controller without touching
## the table's seats, `start` builds it on given seats, `instant`/`fast` pick the pacing,
## `auto_saves` skips the save dialog. A test that needs more keeps that one line after `start`.


## Build the solo controller for the current table and touch nothing else: no slot set, no seat.
## Use this instead of `start` on hotseat tables (and agreed online rooms / geometry-only fixtures)
## that keep their own seats and would lose them to `start`'s slot and seat writes. Returns the
## controller `_ensure_solo_controller()` left behind — null when the table has no AI seat and is
## not engine-Automatic.
static func controller(main: Node) -> SoloController:
	main._ensure_solo_controller()
	return main.solo_controller


## Start a solo game on a loaded main scene: AI slots, the human slot, the controller ready.
## `ai_slots` are the player ids the Solo AI controls; the controller's active seat is the first AI
## slot that is not `human_slot` (the shape the suites use: `solo_ai_slots = {1: true, 2: true}`,
## `ai_slot = 2`).
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


## Instant dice and no pacing holds (headless sweeps).
static func instant(main: Node, on := true) -> void:
	main._solo_batch = on


## Shorter pacing holds and no move animation.
static func fast(main: Node, on := true) -> void:
	main._solo_fast = on


## Saves roll straight to the tray without the save dialog.
static func auto_saves(main: Node, on := true) -> void:
	main._solo_auto_saves = on


## Resolve a human unit's spell through the table's own cast path (it marks the core session).
static func cast(main: Node, caster: GameUnit, entry: Dictionary, targets: Array) -> void:
	await main._run_human_cast(caster, caster, entry, targets)
