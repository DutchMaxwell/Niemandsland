class_name TutorialFlow
extends RefCounted
## Pure lesson/step state machine for the guided tutorial (T1 tool track W1-W6).
## Holds the ordered lesson definitions and a cursor; `consume(event)` advances the
## cursor ONLY when the fed event matches the current step's required event. No scene
## access, no signals, no persistence — the TutorialDirector translates real gameplay
## signals into `Event`s and applies the results; TutorialProgress persists completions.
## Fully unit-testable headless.

# ===== Events (the real-signal vocabulary of the tutorial) =====
enum Event {
	NONE,
	CAMERA_ORBIT,     # camera yaw delta accumulated (right-drag / Q/E)
	CAMERA_ZOOM,      # zoom distance ratio change (mouse wheel)
	CAMERA_PAN,       # orbit pivot moved (WASD / middle-drag)
	MENU_OPENED,      # left game-menu panel became visible (hamburger)
	IMPORT_OPENED,    # OPR import dialog became visible
	IMPORT_CLOSED,    # OPR import dialog closed again
	UNIT_SELECTED,    # selection includes a model of the highlighted unit
	UNIT_MOVED,       # selection_dropped moved a model of the highlighted unit
	ROTATED,          # rotation_committed (R-hold aim / Shift+R / Ctrl+R)
	UNDONE,           # undo_manager.action_undone
	MEASURED,         # measurement_finished (Shift+drag ruler)
	BANDS_SHOWN,      # movement bands became active (M on a selection)
	DICE_ROLLED,      # dice_tray.roll_finnished
	DOCK_OPENED,      # unit dock strip opened
	CARD_PRESENTED,   # a unit card was presented (strip card clicked)
	UNIT_ACTIVATED,   # radial_menu_controller.unit_activated (card chip or radial)
	MODEL_KILLED,     # loose_model_dead_changed dead=true (casualty parked)
	MODEL_REVIVED,    # loose_model_dead_changed dead=false (parked model revived)
	GAME_STARTED,     # game_phase_changed -> PLAYING (Start Game / both-ready)
	MOVE_CAPPED,      # movement_capped with dry=true (dry-brush cap reached mid-drag)
	MODELS_SEPARATED, # drop_separated (the 1" spacing rule snapped/pushed a dropped base)
	# — Wave 1 (toolstrack spec T-02/T-03/T-04) —
	UNIT_WHOLE_SELECTED, # selection == every alive node of one unit (double-click)
	MULTI_SELECTED,      # selection spans >=2 distinct units (Alt+click)
	BOX_SELECTED,        # selection grew via a rubber-band drag over empty table
	SELECTION_CLEARED,   # selection became empty (Esc)
	ARRANGED,            # object_manager.arrangement_applied (1-9 rows / Shift+A arrow)
	PASTED,              # object_manager.objects_pasted (Ctrl+V / Ctrl+D)
	LOCK_TOGGLED,        # object_manager.lock_state_changed (L)
	OBJECT_DELETED,      # radial_menu_controller.model_deleted / unit_deleted (Delete key)
	RULER_PINNED,        # pinned-ruler count increased (P)
	RULER_CLEARED,       # pinned-ruler count decreased (K)
	RANGE_RING_SHOWN,    # a G range ring became active
	SPELL_RANGE_SHOWN,   # the spell-range preview ring became active (card spell hover)
	# — Wave 2 (toolstrack spec T-05/T-06/T-07) —
	DICE_COUNT_SET,      # dice_controls_changed kind=count
	DICE_QUICK_ROLLED,   # the Quick roll button was pressed
	DICE_SUCCESS_SET,    # dice_controls_changed kind=success
	DICE_MODIFIER_SET,   # dice_controls_changed kind=modifier
	DICE_REROLLED,       # dice_controls_changed kind=reroll (a re-roll was armed)
	DICE_MOVECAP_SET,    # dice_controls_changed kind=movecap
	DICE_COLOUR_TAGGED,  # dice_tray.color_tag_changed
	CARD_RULE_HOVERED,   # timed banner step (read the card — no gate seam by design)
	RADIAL_OPENED,       # object_manager.context_menu_requested
	WOUNDS_SET,          # wounds_dialog.wounds_changed
	CASTS_SET,           # casts_dialog.casts_changed
	STATE_TOGGLED,       # radial_menu.action_selected toggle_fatigued / toggle_shaken
	MARKER_ADDED,        # marker_dialog.marker_added
	OBJECTIVE_SET,       # radial_menu.action_selected objective-owner id
	UNIT_RETURNED,       # radial_menu.action_selected return_unit_*
}

# ===== Spotlight target keys (resolved to rects by the director) =====
const TARGET_NONE := ""                       # banner only, no spotlight, no dim
const TARGET_UNIT := "unit"                   # highlighted unit's projected AABB
const TARGET_HAMBURGER := "hamburger"         # the top-left menu button
const TARGET_IMPORT_BUTTON := "import_button" # IMPORT OPR ARMY button in the menu
const TARGET_DICE_PANEL := "dice_panel"       # the dice tray panel
const TARGET_DOCK_TAB := "dock_tab"           # Units dock tab at the bottom
const TARGET_DOCK_STRIP := "dock_strip"       # the open card strip
const TARGET_PRESENTED_CARD := "presented_card"
const TARGET_PARKED_MODEL := "parked_model"   # the casualty parked on the tray
const TARGET_START_GAME := "start_game"       # the Start Game / Ready button in the left panel
const TARGET_SECOND_UNIT := "second_unit"     # a SECOND highlighted unit (multi-select step)

# ===== State =====
var lessons: Array = []
var lesson_index: int = 0
var step_index: int = 0
var finished: bool = false


func _init(p_lessons: Array = []) -> void:
	lessons = p_lessons


# ===== Track definition =====

## The T1 tool track (Tutorial_Plan lessons W1-W6). Each step: one imperative
## sentence, the real-signal event that completes it, a spotlight target key, and
## whether input outside the spotlight is soft-masked (never for 3D drag steps).
static func build_tool_track() -> Array:
	return [
		{"id": "T-01", "title": "Camera & table", "steps": [
			{"id": "orbit", "text": "Hold the right mouse button and drag to orbit the camera.",
				"event": Event.CAMERA_ORBIT, "target": TARGET_NONE, "mask": false},
			{"id": "zoom", "text": "Zoom in and out with the mouse wheel.",
				"event": Event.CAMERA_ZOOM, "target": TARGET_NONE, "mask": false},
			{"id": "pan", "text": "Pan across the table with WASD or by dragging the middle mouse button.",
				"event": Event.CAMERA_PAN, "target": TARGET_NONE, "mask": false},
		]},
		{"id": "T-02", "title": "Selecting", "steps": [
			{"id": "single", "text": "Left-click one model of the highlighted unit to select it.",
				"event": Event.UNIT_SELECTED, "target": TARGET_UNIT, "mask": true},
			{"id": "unit", "text": "Double-click any model to select its whole unit at once.",
				"event": Event.UNIT_WHOLE_SELECTED, "target": TARGET_UNIT, "mask": false},
			{"id": "multi", "text": "Hold Alt and click a model of a second unit — Alt+click adds to your selection.",
				"event": Event.MULTI_SELECTED, "target": TARGET_SECOND_UNIT, "mask": false},
			{"id": "box", "text": "Drag a box across empty table to rubber-band-select everything inside it.",
				"event": Event.BOX_SELECTED, "target": TARGET_NONE, "mask": false},
			{"id": "cancel", "text": "Press Esc to clear the selection.",
				"event": Event.SELECTION_CLEARED, "target": TARGET_NONE, "mask": false},
		]},
		{"id": "T-03", "title": "Moving, rotating & arranging", "steps": [
			{"id": "move", "text": "Drag the selected models to a new spot, then release.",
				"event": Event.UNIT_MOVED, "target": TARGET_UNIT, "mask": false},
			{"id": "aim", "text": "Hold R and move the cursor — the models turn to face it. Release R to confirm.",
				"event": Event.ROTATED, "target": TARGET_UNIT, "mask": false},
			{"id": "group_rotate", "text": "Select the whole unit, hold Shift and press R to rotate the group around its centre.",
				"event": Event.ROTATED, "target": TARGET_UNIT, "mask": false},
			{"id": "snap", "text": "Press Ctrl+R to snap the unit's facing to the nearest 90 degrees.",
				"event": Event.ROTATED, "target": TARGET_UNIT, "mask": false},
			{"id": "arrange", "text": "Press a number key 1-9 to arrange the selected models into that many rows.",
				"event": Event.ARRANGED, "target": TARGET_UNIT, "mask": false},
			{"id": "arrow", "text": "Press Shift+A to fan the unit into an arrow formation.",
				"event": Event.ARRANGED, "target": TARGET_UNIT, "mask": false},
			{"id": "duplicate", "text": "Press Ctrl+D to duplicate the selected unit right where the cursor is.",
				"event": Event.PASTED, "target": TARGET_UNIT, "mask": false},
			{"id": "lock", "text": "Press L to lock the unit so it can't be moved by accident. Press L again to unlock.",
				"event": Event.LOCK_TOGGLED, "target": TARGET_UNIT, "mask": false},
			{"id": "delete", "text": "Select the duplicate you just made and press Delete to remove it.",
				"event": Event.OBJECT_DELETED, "target": TARGET_UNIT, "mask": false},
			{"id": "undo", "text": "Press Ctrl+Z to undo — and Ctrl+Y to redo.",
				"event": Event.UNDONE, "target": TARGET_NONE, "mask": false},
		]},
		{"id": "T-04", "title": "Measuring, rings & the lines you already see", "steps": [
			{"id": "measure", "text": "Hold Shift and drag the left mouse button to measure a distance.",
				"event": Event.MEASURED, "target": TARGET_NONE, "mask": false},
			{"id": "pin", "text": "While a measurement is on screen, press P to pin that ruler so it stays.",
				"event": Event.RULER_PINNED, "target": TARGET_NONE, "mask": false},
			{"id": "clear", "text": "Press K to clear your pinned rulers again.",
				"event": Event.RULER_CLEARED, "target": TARGET_NONE, "mask": false},
			{"id": "bands", "text": "Select a unit and press M to show its movement bands — Advance 6\" and Rush 12\".",
				"event": Event.BANDS_SHOWN, "target": TARGET_UNIT, "mask": false},
			{"id": "rings", "text": "Press G to cycle a range ring (3 / 6 / 9 / 12 / 18 / 24\") — press G again to step through, Shift+G to clear.",
				"event": Event.RANGE_RING_SHOWN, "target": TARGET_UNIT, "mask": false},
			{"id": "spell", "text": "Open a caster's card and hover a spell name — a purple ring shows that spell's range.",
				"event": Event.SPELL_RANGE_SHOWN, "target": TARGET_PRESENTED_CARD, "mask": false},
			{"id": "coherency", "text": "As you drag a selected unit, watch the green chain lines. Green = every model in 1\" coherency; red = the chain is broken. Move a model until you see them.",
				"event": Event.UNIT_MOVED, "target": TARGET_UNIT, "mask": false},
		]},
		{"id": "T-05", "title": "The dice tray in full", "steps": [
			{"id": "count", "text": "Set how many dice you'll throw — use the preset grid or the +/-1, +/-5, +/-10 buttons.",
				"event": Event.DICE_COUNT_SET, "target": TARGET_DICE_PANEL, "mask": false},
			{"id": "roll", "text": "Throw the dice — press Roll to tumble them physically.",
				"event": Event.DICE_ROLLED, "target": TARGET_DICE_PANEL, "mask": true},
			{"id": "quick", "text": "In a hurry? Press Quick for an instant result with no physics.",
				"event": Event.DICE_QUICK_ROLLED, "target": TARGET_DICE_PANEL, "mask": true},
			{"id": "success", "text": "Pick a success target (e.g. 4+). The tray counts hits for you.",
				"event": Event.DICE_SUCCESS_SET, "target": TARGET_DICE_PANEL, "mask": false},
			{"id": "modifier", "text": "Add a modifier with the -/+ stepper — say +1 to every die.",
				"event": Event.DICE_MODIFIER_SET, "target": TARGET_DICE_PANEL, "mask": false},
			{"id": "reroll", "text": "Re-roll the misses — press Re-roll Fails (or 1s / 6s / All).",
				"event": Event.DICE_REROLLED, "target": TARGET_DICE_PANEL, "mask": false},
			{"id": "movecap", "text": "The Movement row caps a drag to Advance or Rush distance — try setting it.",
				"event": Event.DICE_MOVECAP_SET, "target": TARGET_DICE_PANEL, "mask": false},
			{"id": "colour", "text": "Click a die to cycle its colour tag — handy for grouping attacks.",
				"event": Event.DICE_COLOUR_TAGGED, "target": TARGET_DICE_PANEL, "mask": false},
		]},
		{"id": "T-06", "title": "Unit cards & the radial menu", "steps": [
			{"id": "dock", "text": "Open the Units dock — click the Units tab at the bottom.",
				"event": Event.DOCK_OPENED, "target": TARGET_DOCK_TAB, "mask": true},
			{"id": "present", "text": "Click a unit card to select the unit and present its full card.",
				"event": Event.CARD_PRESENTED, "target": TARGET_DOCK_STRIP, "mask": true},
			{"id": "read", "text": "Hover a weapon or rule on the card to read its description.",
				"event": Event.CARD_RULE_HOVERED, "target": TARGET_PRESENTED_CARD, "mask": false, "timed_sec": 4.0},
			{"id": "open", "text": "Right-click a model to open its radial menu — every unit action lives here.",
				"event": Event.RADIAL_OPENED, "target": TARGET_UNIT, "mask": false},
			{"id": "activate", "text": "Choose Activate to mark the unit as activated this round.",
				"event": Event.UNIT_ACTIVATED, "target": TARGET_NONE, "mask": false},
			{"id": "wounds", "text": "Right-click a Tough model and open Wounds — set its remaining wounds.",
				"event": Event.WOUNDS_SET, "target": TARGET_UNIT, "mask": false},
			{"id": "casts", "text": "Open Casts on your caster to spend or restore caster points.",
				"event": Event.CASTS_SET, "target": TARGET_UNIT, "mask": false},
			{"id": "state", "text": "Toggle Fatigued or Shaken to mark the unit's state after a fight or failed morale.",
				"event": Event.STATE_TOGGLED, "target": TARGET_UNIT, "mask": false},
			{"id": "token", "text": "Open the token dialog to drop a custom marker or counter on a unit.",
				"event": Event.MARKER_ADDED, "target": TARGET_UNIT, "mask": false},
			{"id": "objective", "text": "Right-click an objective marker and set its owner.",
				"event": Event.OBJECTIVE_SET, "target": TARGET_NONE, "mask": false},
		]},
		{"id": "T-07", "title": "Wounds, casualties & revive", "steps": [
			{"id": "kill", "text": "Right-click a model of the highlighted unit and remove it as a casualty — it parks on your army tray.",
				"event": Event.MODEL_KILLED, "target": TARGET_UNIT, "mask": false},
			{"id": "revive", "text": "Right-click the parked model and revive it back onto the table.",
				"event": Event.MODEL_REVIVED, "target": TARGET_PARKED_MODEL, "mask": false},
			{"id": "multi_revive", "text": "Lost several models? Use Revive Unit-Dead to bring the whole unit's casualties back.",
				"event": Event.MODEL_REVIVED, "target": TARGET_PARKED_MODEL, "mask": false},
			{"id": "return_unit", "text": "A fully destroyed unit lands on the army tray — choose Return Unit to redeploy it.",
				"event": Event.UNIT_RETURNED, "target": TARGET_NONE, "mask": false},
		]},
		{"id": "W2", "title": "Importing armies", "steps": [
			{"id": "menu", "text": "Open the game menu with the button in the top-left corner.",
				"event": Event.MENU_OPENED, "target": TARGET_HAMBURGER, "mask": true},
			{"id": "import_open", "text": "Click IMPORT OPR ARMY — this is where armies come from.",
				"event": Event.IMPORT_OPENED, "target": TARGET_IMPORT_BUTTON, "mask": true},
			{"id": "import_close", "text": "In a real game you would paste an Army Forge share link here. Your tutorial armies are already on the table — close the dialog to continue.",
				"event": Event.IMPORT_CLOSED, "target": TARGET_NONE, "mask": false},
		]},
		{"id": "W7", "title": "Movement & trails", "steps": [
			{"id": "start_game", "text": "Deployment is done — press Start Game in the left panel to begin play. Chalk move-trails only paint once the game has started.",
				"event": Event.GAME_STARTED, "target": TARGET_START_GAME, "mask": false},
			{"id": "trail", "text": "Drag the highlighted unit across the table. A chalk trail paints behind it along the ACTUAL path you took, and the counter reads the inches travelled. Click a finished trail to read its distance again.",
				"event": Event.UNIT_MOVED, "target": TARGET_UNIT, "mask": false},
			{"id": "cap", "text": "With Enforce Movement Limit on, pick Advance above the dice, then drag the unit past 6\". The counter turns red as the brush runs dry — Advance caps at 6\", Rush/Charge at 12\".",
				"event": Event.MOVE_CAPPED, "target": TARGET_UNIT, "mask": false},
			{"id": "spacing", "text": "Now drag the unit up to an enemy model. A red 1\" wall stops you and snaps the base to contact — models can never stack or crowd inside 1\".",
				"event": Event.MODELS_SEPARATED, "target": TARGET_UNIT, "mask": false},
		]},
	]


## Lesson ids in track order.
static func ids(p_lessons: Array) -> Array[String]:
	var result: Array[String] = []
	for lesson in p_lessons:
		result.append(String(lesson.get("id", "")))
	return result


## Title of a lesson by id ("" if unknown).
static func title_of(p_lessons: Array, lesson_id: String) -> String:
	for lesson in p_lessons:
		if String(lesson.get("id", "")) == lesson_id:
			return String(lesson.get("title", ""))
	return ""


# ===== Cursor =====

func current_lesson() -> Dictionary:
	if finished or lesson_index < 0 or lesson_index >= lessons.size():
		return {}
	return lessons[lesson_index]


func current_step() -> Dictionary:
	var lesson := current_lesson()
	if lesson.is_empty():
		return {}
	var steps: Array = lesson.get("steps", [])
	if step_index < 0 or step_index >= steps.size():
		return {}
	return steps[step_index]


func lesson_count() -> int:
	return lessons.size()


func step_count() -> int:
	return current_lesson().get("steps", []).size()


## Jump the cursor to the start of the lesson with the given id. False if unknown.
func start_at(lesson_id: String) -> bool:
	for i in lessons.size():
		if String(lessons[i].get("id", "")) == lesson_id:
			lesson_index = i
			step_index = 0
			finished = false
			return true
	return false


## Feed one event. Advances only when it matches the current step's required event.
## Returns {advanced: bool, lesson_completed: String ("" or the finished lesson's id),
## finished: bool}. When a lesson's last step completes, the cursor auto-moves to the
## next lesson in track order (the director may then jump past already-completed ones).
func consume(event: Event) -> Dictionary:
	var result := {"advanced": false, "lesson_completed": "", "finished": finished}
	if finished:
		return result
	var step := current_step()
	if step.is_empty() or int(step.get("event", Event.NONE)) != event:
		return result
	result.advanced = true
	step_index += 1
	if step_index >= step_count():
		result.lesson_completed = String(current_lesson().get("id", ""))
		lesson_index += 1
		step_index = 0
		if lesson_index >= lessons.size():
			finished = true
	result.finished = finished
	return result


## Complete the current lesson without playing its remaining steps (Skip lesson).
## Same return shape as consume().
func skip_current_lesson() -> Dictionary:
	var result := {"advanced": false, "lesson_completed": "", "finished": finished}
	if finished:
		return result
	result.advanced = true
	result.lesson_completed = String(current_lesson().get("id", ""))
	lesson_index += 1
	step_index = 0
	if lesson_index >= lessons.size():
		finished = true
	result.finished = finished
	return result


## End the track immediately (all remaining lessons already completed elsewhere).
func finish_track() -> void:
	finished = true
