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
		{"id": "W1", "title": "Camera & table", "steps": [
			{"id": "orbit", "text": "Hold the right mouse button and drag to orbit the camera.",
				"event": Event.CAMERA_ORBIT, "target": TARGET_NONE, "mask": false},
			{"id": "zoom", "text": "Zoom in and out with the mouse wheel.",
				"event": Event.CAMERA_ZOOM, "target": TARGET_NONE, "mask": false},
			{"id": "pan", "text": "Pan across the table with WASD or by dragging the middle mouse button.",
				"event": Event.CAMERA_PAN, "target": TARGET_NONE, "mask": false},
		]},
		{"id": "W2", "title": "Importing armies", "steps": [
			{"id": "menu", "text": "Open the game menu with the button in the top-left corner.",
				"event": Event.MENU_OPENED, "target": TARGET_HAMBURGER, "mask": true},
			{"id": "import_open", "text": "Click IMPORT OPR ARMY — this is where armies come from.",
				"event": Event.IMPORT_OPENED, "target": TARGET_IMPORT_BUTTON, "mask": true},
			{"id": "import_close", "text": "In a real game you would paste an Army Forge share link here. Your tutorial armies are already on the table — close the dialog to continue.",
				"event": Event.IMPORT_CLOSED, "target": TARGET_NONE, "mask": false},
		]},
		{"id": "W3", "title": "Select, move, rotate & undo", "steps": [
			{"id": "select", "text": "Click a model of the highlighted unit to select it.",
				"event": Event.UNIT_SELECTED, "target": TARGET_UNIT, "mask": true},
			{"id": "move", "text": "Drag the selected models to a new spot, then release.",
				"event": Event.UNIT_MOVED, "target": TARGET_UNIT, "mask": false},
			{"id": "rotate", "text": "Hold R and move the cursor — the models turn to face it. Release R to confirm.",
				"event": Event.ROTATED, "target": TARGET_UNIT, "mask": false},
			{"id": "undo", "text": "Press Ctrl+Z to undo your last action.",
				"event": Event.UNDONE, "target": TARGET_NONE, "mask": false},
		]},
		{"id": "W4", "title": "Dice & measuring", "steps": [
			{"id": "measure", "text": "Hold Shift and drag with the left mouse button to measure a distance.",
				"event": Event.MEASURED, "target": TARGET_NONE, "mask": false},
			{"id": "bands", "text": "Select a model and press M to show its movement bands (Advance / Rush).",
				"event": Event.BANDS_SHOWN, "target": TARGET_UNIT, "mask": false},
			{"id": "roll", "text": "Roll the dice in the dice tray.",
				"event": Event.DICE_ROLLED, "target": TARGET_DICE_PANEL, "mask": true},
		]},
		{"id": "W5", "title": "Unit cards & activation", "steps": [
			{"id": "dock", "text": "Open the Units dock — click the Units tab at the bottom of the screen.",
				"event": Event.DOCK_OPENED, "target": TARGET_DOCK_TAB, "mask": true},
			{"id": "present", "text": "Click one of the unit cards — it selects the unit and presents its card.",
				"event": Event.CARD_PRESENTED, "target": TARGET_DOCK_STRIP, "mask": true},
			{"id": "activate", "text": "Activate the unit with the ACTIVATE chip on its card.",
				"event": Event.UNIT_ACTIVATED, "target": TARGET_PRESENTED_CARD, "mask": true},
		]},
		{"id": "W6", "title": "Wounds & casualties", "steps": [
			{"id": "kill", "text": "Right-click a model of the highlighted unit and remove it as a casualty.",
				"event": Event.MODEL_KILLED, "target": TARGET_UNIT, "mask": false},
			{"id": "revive", "text": "The casualty is parked on your army tray. Right-click it and revive it.",
				"event": Event.MODEL_REVIVED, "target": TARGET_PARKED_MODEL, "mask": false},
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
