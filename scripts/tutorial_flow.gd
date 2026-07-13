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
	# --- Wave 1 tool track (T-02 Selecting) ---
	UNIT_WHOLE_SELECTED,  # selection == every alive model of ONE unit (double-click) — T-02
	MULTI_SELECTED,       # selection spans >= 2 distinct units (Alt+click) — T-02
	BOX_SELECTED,         # selection grew from a rubber-band box drag on empty table — T-02
	SELECTION_CLEARED,    # selection became empty (Esc) — T-02
	# --- Wave 1 tool track (T-03 Moving, rotating & arranging) ---
	ARRANGED,             # object_manager.arrangement_applied (1-9 rows / Shift+A arrow) — T-03
	PASTED,               # object_manager.objects_pasted (Ctrl+V / Ctrl+D) — T-03
	LOCK_TOGGLED,         # object_manager.lock_state_changed (L) — T-03
	OBJECT_DELETED,       # radial_menu_controller.model_deleted / unit_deleted (Delete) — T-03
	# --- Wave 1 tool track (T-04 Measuring, rings & coherency) ---
	RULER_PINNED,         # pinned_rulers.ruler_count() rose (P pins the live ruler) — T-04
	RULER_CLEARED,        # pinned_rulers.ruler_count() fell (K clears pinned rulers) — T-04
	RANGE_RING_SHOWN,     # range_ring_controller.active_count() > 0 (G range rings) — T-04
	SPELL_RANGE_SHOWN,    # range_ring_controller.spell_preview_changed(true) (hover a spell) — T-04
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
const TARGET_ROUND_BUTTON := "round_button"   # the Next Round button (R1: end the round)
const TARGET_R3_MODEL := "r3_model"           # ONE designated model of the unit (R3: click this model)
const TARGET_R3_MARKER := "r3_marker"         # the R3 world-space destination marker, projected to screen
const TARGET_SECOND_UNIT := "second_unit"     # a SECOND player-1 unit's projected AABB (T-02: Alt+click it)

# ===== Chapter metadata keys (for the future tool-vs-rules / system-ladder split) =====
## Each lesson carries a `track` ("tool" | "rule") and `system` tag so a later package can
## split "Niemandsland tool tutorial" from "OPR rules tutorial" and build a GF -> AoF ->
## Skirmish -> Regiments ladder without re-shaping the step data. `archived: true` marks a
## lesson kept in code for a future purpose-built tutorial but NOT part of the active track.
const TRACK_TOOL := "tool"
const TRACK_RULE := "rule"
const SYSTEM_GF := "gf"       # Grimdark Future (this tutorial's system)
const SYSTEM_AOFR := "aofr"   # Age of Fantasy: Regiments (future Regiments tutorial)

# ===== State =====
var lessons: Array = []
var lesson_index: int = 0
var step_index: int = 0
var finished: bool = false


func _init(p_lessons: Array = []) -> void:
	lessons = p_lessons


# ===== Track definition =====

## The TOOL track: the shipped basics (W1-W6) followed by Wave 1 of the comprehensive
## track (T-02, T-03, T-04 — appended by build_wave1_track). Each step: one imperative
## sentence, the real-signal event that completes it, a spotlight target key, and
## whether input outside the spotlight is soft-masked (never for 3D drag steps).
static func build_tool_track() -> Array:
	return [
		{"id": "W1", "title": "Camera & table", "track": TRACK_TOOL, "system": SYSTEM_GF, "steps": [
			{"id": "orbit", "text": "Hold the right mouse button and drag to orbit the camera.",
				"event": Event.CAMERA_ORBIT, "target": TARGET_NONE, "mask": false},
			{"id": "zoom", "text": "Scroll the mouse wheel to zoom in and out.",
				"event": Event.CAMERA_ZOOM, "target": TARGET_NONE, "mask": false},
			{"id": "pan", "text": "Pan across the table with WASD or by dragging the middle mouse button.",
				"event": Event.CAMERA_PAN, "target": TARGET_NONE, "mask": false},
		]},
		{"id": "W2", "title": "Importing armies", "track": TRACK_TOOL, "system": SYSTEM_GF, "steps": [
			{"id": "menu", "text": "Open the game menu with the button in the top-left corner.",
				"event": Event.MENU_OPENED, "target": TARGET_HAMBURGER, "mask": true},
			{"id": "import_open", "text": "Click IMPORT OPR ARMY — this is where armies come from.",
				"event": Event.IMPORT_OPENED, "target": TARGET_IMPORT_BUTTON, "mask": true},
			{"id": "import_close", "text": "In a real game you would paste an Army Forge share link here. Your tutorial armies are already on the table — close the dialog to continue.",
				"event": Event.IMPORT_CLOSED, "target": TARGET_NONE, "mask": false},
		]},
		{"id": "W3", "title": "Select, move, rotate & undo", "track": TRACK_TOOL, "system": SYSTEM_GF, "steps": [
			{"id": "select", "text": "Click a model of the highlighted unit to select it.",
				"event": Event.UNIT_SELECTED, "target": TARGET_UNIT, "mask": true},
			{"id": "move", "text": "Drag the selected models to a new spot, then release.",
				"event": Event.UNIT_MOVED, "target": TARGET_UNIT, "mask": false},
			{"id": "rotate", "text": "Hold R and move the cursor — the models turn to face it. Release R to confirm.",
				"event": Event.ROTATED, "target": TARGET_UNIT, "mask": false},
			{"id": "undo", "text": "Press Ctrl+Z to undo your last action.",
				"event": Event.UNDONE, "target": TARGET_NONE, "mask": false},
		]},
		{"id": "W4", "title": "Dice & measuring", "track": TRACK_TOOL, "system": SYSTEM_GF, "steps": [
			{"id": "measure", "text": "Hold Shift and drag with the left mouse button to measure a distance.",
				"event": Event.MEASURED, "target": TARGET_NONE, "mask": false},
			{"id": "bands", "text": "Press M on your selected model to show its movement bands (Advance / Rush).",
				"event": Event.BANDS_SHOWN, "target": TARGET_UNIT, "mask": false},
			{"id": "roll", "text": "Roll the dice in the dice tray.",
				"event": Event.DICE_ROLLED, "target": TARGET_DICE_PANEL, "mask": true},
		]},
		{"id": "W5", "title": "Unit cards & activation", "track": TRACK_TOOL, "system": SYSTEM_GF, "steps": [
			{"id": "dock", "text": "Open the Units dock — click the Units tab at the bottom of the screen.",
				"event": Event.DOCK_OPENED, "target": TARGET_DOCK_TAB, "mask": true},
			{"id": "present", "text": "Click one of the unit cards — it selects the unit and presents its card.",
				"event": Event.CARD_PRESENTED, "target": TARGET_DOCK_STRIP, "mask": true},
			{"id": "activate", "text": "Activate the unit with the ACTIVATE chip on its card.",
				"event": Event.UNIT_ACTIVATED, "target": TARGET_PRESENTED_CARD, "mask": true},
		]},
		{"id": "W6", "title": "Wounds & casualties", "track": TRACK_TOOL, "system": SYSTEM_GF, "steps": [
			{"id": "kill", "text": "Right-click a model of the highlighted unit and remove it as a casualty.",
				"event": Event.MODEL_KILLED, "target": TARGET_UNIT, "mask": false},
			{"id": "revive", "text": "The casualty is parked on your army tray. Right-click it and revive it.",
				"event": Event.MODEL_REVIVED, "target": TARGET_PARKED_MODEL, "mask": false},
		]},
	] + build_wave1_track()


## Wave 1 of the comprehensive TOOL track (design spec 2026-07-13): T-02 Selecting,
## T-03 Moving/rotating/arranging, T-04 Measuring/rings/coherency. Appended to the shipped
## W1-W6 track — same standard GF board, no reload. Clears the maintainer's named gaps:
## multi-select (Alt+click), Anordnen/Formation (1-9 / Shift+A), Pin Rule (P), G-Ringe,
## Zauberreichweiten, and *names* the auto coherency lines. Every step gates on a real seam
## (existing signal, poll edge, or a Wave-1 additive signal — see TutorialDirector).
static func build_wave1_track() -> Array:
	return [
		{"id": "T-02", "title": "Selecting", "track": TRACK_TOOL, "system": SYSTEM_GF, "steps": [
			{"id": "single", "text": "Left-click one model of the highlighted unit to select it.",
				"event": Event.UNIT_SELECTED, "target": TARGET_UNIT, "mask": true},
			{"id": "unit", "text": "Double-click any model to select its whole unit at once.",
				"event": Event.UNIT_WHOLE_SELECTED, "target": TARGET_UNIT, "mask": true},
			{"id": "multi", "text": "Hold Alt and click a model of the second highlighted unit — Alt+click adds it to your selection.",
				"event": Event.MULTI_SELECTED, "target": TARGET_SECOND_UNIT, "mask": true},
			{"id": "box", "text": "Drag a box across empty table to rubber-band-select everything inside it.",
				"event": Event.BOX_SELECTED, "target": TARGET_NONE, "mask": false},
			{"id": "cancel", "text": "Press Esc to clear the selection.",
				"event": Event.SELECTION_CLEARED, "target": TARGET_NONE, "mask": false},
		]},
		{"id": "T-03", "title": "Moving, rotating & arranging", "track": TRACK_TOOL, "system": SYSTEM_GF, "steps": [
			{"id": "move", "text": "Drag the selected models to a new spot, then release.",
				"event": Event.UNIT_MOVED, "target": TARGET_UNIT, "mask": false},
			{"id": "aim", "text": "Hold R and move the cursor — the models turn to face it. Release R to confirm.",
				"event": Event.ROTATED, "target": TARGET_UNIT, "mask": false},
			{"id": "group_rotate", "text": "Select the whole unit, hold Shift and press R to spin the group around its centre.",
				"event": Event.ROTATED, "target": TARGET_UNIT, "mask": false},
			{"id": "snap", "text": "Press Ctrl+R to snap the unit's facing to the nearest 90°.",
				"event": Event.ROTATED, "target": TARGET_UNIT, "mask": false},
			{"id": "arrange", "text": "Press a number key 1–9 to arrange the selected models into that many rows.",
				"event": Event.ARRANGED, "target": TARGET_UNIT, "mask": false},
			{"id": "arrow", "text": "Press Shift+A to fan the unit into an arrow formation.",
				"event": Event.ARRANGED, "target": TARGET_UNIT, "mask": false},
			{"id": "duplicate", "text": "Press Ctrl+D to duplicate the selected unit right at the cursor.",
				"event": Event.PASTED, "target": TARGET_UNIT, "mask": false},
			{"id": "lock", "text": "Press L to lock the unit so it can't be moved by accident. Press L again to unlock.",
				"event": Event.LOCK_TOGGLED, "target": TARGET_UNIT, "mask": false},
			{"id": "delete", "text": "Select the duplicate you just made and press Delete to remove it.",
				"event": Event.OBJECT_DELETED, "target": TARGET_UNIT, "mask": false},
			{"id": "undo", "text": "Press Ctrl+Z to undo — and Ctrl+Y to redo.",
				"event": Event.UNDONE, "target": TARGET_NONE, "mask": false},
		]},
		{"id": "T-04", "title": "Measuring, rings & coherency", "track": TRACK_TOOL, "system": SYSTEM_GF, "steps": [
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
			{"id": "coherency", "text": "As you drag a selected unit, watch the green chain lines. Green = every model within 1\" coherency; red = the chain is broken. Move a model to see them.",
				"event": Event.UNIT_MOVED, "target": TARGET_UNIT, "mask": false},
		]},
	]


## The T2 rule track (rule lessons R1, R3), event-gated on the same real GF tutorial board.
## Rule text verified against the OPR Grimdark Future Advanced Rules v3.5.1 PDF, p.6:
##   R1 "Rounds, Turns & Activations" / "Activating Units": a turn is one activation, an
##      activation is exactly one action — Hold (stay, can shoot) / Advance (6", can shoot) /
##      Rush (12", no shoot) / Charge (12" into melee). "This continues until all units have
##      activated, at which point the round ends and a new one begins." R1 is taught as three
##      explicit imperatives: activate ONE unit -> resolve its shot on the dice -> end the round.
##   R3 "Unit Coherency": "All models in a unit must always stay within 1" of at least one
##      other model, and must stay within 9" of all other models ... forming an uninterrupted
##      chain of models in 1" coherency." R3 is four micro-steps with a world-space marker and
##      the live coherency visualizer running on the taught unit the whole time: pick THIS
##      model -> drag it onto the far marker (breaks the chain; the warning flares) -> drag it
##      back onto the marker at its old spot (the warning clears) -> a "restored" success card.
##
## R2 (Regiments) is intentionally NOT in this track — see build_regiment_track().
static func build_rule_track() -> Array:
	return [
		{"id": "R1", "title": "Activation rhythm", "track": TRACK_RULE, "system": SYSTEM_GF, "steps": [
			{"id": "activate", "text": "OnePageRules uses alternating activations: on your turn you activate ONE unit and it takes exactly ONE action — Hold (stay and shoot), Advance (move 6\" and shoot), Rush (move 12\") or Charge (move 12\" into melee). Activate your highlighted unit now.",
				"event": Event.UNIT_ACTIVATED, "target": TARGET_UNIT, "mask": false},
			{"id": "shoot", "text": "An action is resolved with dice. Roll the unit's shooting attack now — throw the dice in the dice tray.",
				"event": Event.DICE_ROLLED, "target": TARGET_DICE_PANEL, "mask": true},
			{"id": "round", "text": "Your turn now ends and your opponent activates one unit — this alternates until every unit on both sides has activated, which ends the round. End the round now with the Next Round button.",
				"event": Event.ROUND_ADVANCED, "target": TARGET_ROUND_BUTTON, "mask": true},
		]},
		{"id": "R3", "title": "Coherency & spacing", "track": TRACK_RULE, "system": SYSTEM_GF, "steps": [
			{"id": "pick", "text": "Coherency keeps a unit together: every model must stay within 1\" of a neighbour AND within 9\" of all other models — one unbroken chain. Click the pulsing model to pick it up.",
				"event": Event.UNIT_SELECTED, "target": TARGET_R3_MODEL, "mask": false},
			{"id": "spread", "text": "Now drag that model onto the glowing ring, away from the rest of the unit. Watch the coherency warning flare up the instant it leaves the 1\" chain.",
				"event": Event.COHERENCY_BROKEN, "target": TARGET_R3_MARKER, "mask": false},
			{"id": "restore", "text": "The unit is torn apart — the red line marks the model that is out of range. Drag it back onto the ring, next to the unit, until every model is within 1\" of a neighbour again.",
				"event": Event.COHERENCY_RESTORED, "target": TARGET_R3_MARKER, "mask": false},
			{"id": "done", "text": "Coherency restored ✓  Every model is back within 1\" of a neighbour and 9\" of the unit. Keep your models in one tight chain and the unit never loses coherency.",
				"event": Event.ACK, "target": TARGET_NONE, "mask": false, "ack": true},
		]},
	]


## ARCHIVE (not in the active track): the Regiments concept lesson (R2), kept in code for the
## future purpose-built "Age of Fantasy: Regiments" tutorial. It was pulled from the GF track
## because teaching Regiments needs a full regiment miniature set and different terrain — the
## GF tutorial board has none, and reloading to a different board mid-tutorial is the design's
## forbidden "Scythe error". A cfg that still has R2 marked done stays valid: R2 is simply not
## a member of the active track, so it is never visited (see TutorialProgress migration note).
static func build_regiment_track() -> Array:
	return [
		{"id": "R2", "title": "Regiments (Age of Fantasy)", "track": TRACK_RULE, "system": SYSTEM_AOFR, "archived": true, "steps": [
			{"id": "concept", "text": "In Age of Fantasy: Regiments a unit forms a single movement tray, ranked up (5 or 3 models wide) with a 45° front arc. This Grimdark Future board has no regiments — when you play an AoF:R army, press F to show a tray's arcs and Shift+F to change its frontage. We'll point these out the first time you use them.",
				"event": Event.ACK, "target": TARGET_NONE, "mask": false, "ack": true},
		]},
	]


## The full guided tutorial in track order: the tool track (W1-W6 + Wave 1 T-02/T-03/T-04)
## followed by the rule track (R1, R3). This is what the director runs and the chapter picker
## lists; the sub-track builders stay separate so each can be reasoned about (and tested) on its
## own, and so the future package can recombine them (tool-only, rules-only, per-system ladder).
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
