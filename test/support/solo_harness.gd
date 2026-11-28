class_name SoloHarness
## Test facade for a solo game on a loaded main.tscn: slots, pacing and dice modes.
##
## WHY THIS LAYER EXISTS. Suites set up a solo game by writing main.gd's private members directly
## (`solo_ai_slots`, `_ensure_solo_controller()`, `solo_controller.ai_slot`,
## `solo_controller.human_slot`, `_solo_batch`, `_solo_fast`, `_solo_auto_saves`). Every extraction
## from main.gd then breaks those tests although no behaviour changes. With this one facade, moving
## that code touches one file.
##
## These six functions are the whole interface: `controller` builds the controller without touching
## the table's seats, `start` builds it on given seats, `instant`/`fast` pick the pacing,
## `auto_saves` skips the save dialog, `auto_verb` runs a player's Auto verb. A test that needs more
## keeps that one line after `start`.


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


## A player's Auto verb (Charge / Advance & Shoot / Rush, AiDecision.Action) of `unit` at
## `target`, as the lit click runs it.
static func auto_verb(main: Node, unit: GameUnit, verb: int, target: GameUnit) -> void:
	await main._run_player_intent(unit, verb, target)


## The table's consolidation after a melee of `charger` against `defender`
## (it waits on the board prompt for a player's unit).
static func consolidate(main: Node, charger: GameUnit, defender: GameUnit) -> void:
	await main._solo_consolidate_melee(charger, defender)


## Resolve a human unit's spell through the table's own cast path (it marks the core session).
static func cast(main: Node, caster: GameUnit, entry: Dictionary, targets: Array) -> void:
	await main._run_human_cast(caster, caster, entry, targets)


## A player's declared split, as the Fire! button of the split prompt runs it: `att` fires
## the `b_names` weapons at `b` and the rest at `a`.
static func split_fire(main: Node, att: GameUnit, a: GameUnit, b: GameUnit, b_names: Array) -> void:
	main._solo_target_mode = {
		"unit": att, "split_first": a, "split_second": b, "split_b_names": b_names
	}
	await main._solo_split_commit()


## The autosave's lesson pause (no save prompt mid-test).
static func lesson_paused(main: Node, on := true) -> void:
	main._autosave_controller.set_lesson_paused(on)


## A player's drop of `moves` as the drop signal hands it to main
## (`ObjectManager.selection_dropped`).
static func drop(main: Node, moves: Array) -> void:
	await main._on_units_dropped(moves)


## Plan step 27-pre P3 / GEN-7: a drawn generated board of `seed_value` / `theme` on a 4 x 4 ft
## table, through the player's door (main.apply_generated_board): lay it before any model.
static func generated_board(main: Node, seed_value: int, theme: String) -> void:
	main.table.setup_table(Vector2(4, 4))
	var id := "ruined_town" if theme.to_lower() == "ruintown" else "tiefwerk"
	main.apply_generated_board(GeneratedBoard.resolve(id, seed_value))


## GEN-9: NACHTMAHR's guided deployment as main runs it - main's blocked tests from the
## table, Front Line `depth_in`, the AI on the negative edge (it won the roll-off) - with the
## human side out, so the AI places every unit it has.
static func ai_deploys_all(main: Node, depth_in := 12.0, seed_value := 5) -> void:
	var blocked: Dictionary = AiDeployment.make_blocked_tests(main.terrain_overlay)
	var feet: Vector2 = main.table.table_size
	main._solo_deploy_fsm = {
		"phase": "side",
		"winner_is_ai": true,
		"human_turn": false,
		"human_out": false,
		"objectives": [],
		"blocked_normal": blocked["normal"],
		"blocked_flying": blocked["flying"],
		"seed": seed_value,
		"w": feet.x * 0.3048,
		"d": feet.y * 0.3048,
		"depth": depth_in * 0.0254,
		"human_placed": {},
		"outcome": [],
	}
	await main._solo_deploy_begin_side(true)
	await main._solo_deploy_human_out()
