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
	# --- T2 rule track (R1-R3) ---
	ROUND_ADVANCED,       # opr_army_manager.round_advanced (all activations cleared) — R1
	ACK,                  # player acknowledged a concept card via the coach "GOT IT" button — R2
	COHERENCY_BROKEN,     # a unit's coherency visualization reported it out of coherency — R3
	COHERENCY_RESTORED,   # a previously-broken unit is back in 1" coherency — R3
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
	]


## The T2 rule track (Tutorial_Plan lessons R1-R3), event-gated on the same real GF
## tutorial board. Rule text verified against the OPR Advanced Rules v3.5.1 PDFs:
##   R1 GF "Game Structure" / "Activating Units" (alternating activations; one action:
##      Hold / Advance / Rush / Charge; round ends when every unit has activated).
##   R2 AoF:R "Unit Facing" / "Unit Formations" (regiments are an Age of Fantasy feature —
##      a single movement tray in ranks with a 45° front arc). The GF tutorial board has
##      no regiments (reloading to a different board mid-tutorial is the "Scythe error"
##      the design forbids), so R2 is a concept card acknowledged with the coach "GOT IT"
##      button; the hands-on controls are taught in context by TutorialTips the first time
##      the player touches a real tray in an AoF:R game.
##   R3 GF "Unit Coherency" (every model within 1" of a neighbour, ≤ 9" across the unit,
##      forming an uninterrupted chain).
static func build_rule_track() -> Array:
	return [
		{"id": "R1", "title": "Activation rhythm", "steps": [
			{"id": "activate", "text": "OnePageRules is played in alternating activations: activate ONE of your units and it takes its whole turn — one action (Hold, Advance, Rush or Charge). Activate a unit now.",
				"event": Event.UNIT_ACTIVATED, "target": TARGET_UNIT, "mask": false},
			{"id": "round", "text": "Then it is your opponent's turn to activate one unit, and so on. When every unit on both sides has activated, the round ends — advance to the next round to clear all activation markers.",
				"event": Event.ROUND_ADVANCED, "target": TARGET_NONE, "mask": false},
		]},
		{"id": "R2", "title": "Regiments (Age of Fantasy)", "steps": [
			{"id": "concept", "text": "In Age of Fantasy: Regiments a unit forms a single movement tray, ranked up (5 or 3 models wide) with a 45° front arc. This Grimdark Future board has no regiments — when you play an AoF:R army, press F to show a tray's arcs and Shift+F to change its frontage. We'll point these out the first time you use them.",
				"event": Event.ACK, "target": TARGET_NONE, "mask": false, "ack": true},
		]},
		{"id": "R3", "title": "Coherency & spacing", "steps": [
			{"id": "spread", "text": "Every model in a unit must stay within 1\" of a neighbour, forming an unbroken chain. Select your highlighted unit and drag one model far away — the coherency warning appears.",
				"event": Event.COHERENCY_BROKEN, "target": TARGET_UNIT, "mask": false},
			{"id": "restore", "text": "Now drag that model back until every model is within 1\" of a neighbour again — the warning clears once the unit is back in coherency.",
				"event": Event.COHERENCY_RESTORED, "target": TARGET_UNIT, "mask": false},
		]},
	]


## The full guided tutorial in track order: the tool track (W1-W6) followed by the rule
## track (R1-R3). This is what the director runs and the chapter picker lists; the two
## sub-track builders stay separate so each can be reasoned about (and tested) on its own.
static func build_full_track() -> Array:
	var full: Array = build_tool_track()
	full.append_array(build_rule_track())
	return full


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
