class_name TutorialTips
extends Node
## Contextual first-time tips + MP guest intro (T2). Watches the SAME real gameplay seams
## the tutorial uses and, the FIRST time ever a player touches an advanced feature OUTSIDE
## the guided tutorial, shows one lighter, non-blocking, dismissible toast (TutorialTipToast).
##
## Policy (all enforced here, not in the toast):
##   · once ever      — each tip is persisted in user://tutorial.cfg [tips] and never repeats
##   · one at a time  — a new trigger is ignored while a toast is on screen (the flag is only
##                      written when a toast actually shows, so a skipped trigger fires later)
##   · never modal    — the toast blocks nothing but its own GOT IT button
##   · not in-tutorial — suppressed while a tutorial chapter is active (main toggles this)
##
## Persistence discipline (avoids clobbering the director's lesson writes to the same file):
## the once-ever READ uses a cheap in-memory session set seeded from disk at ready; the WRITE
## reloads the cfg immediately before marking + saving, so a tip flag is merged on top of any
## [lessons]/[assessment] the director wrote during a tutorial rather than overwriting them.

# ===== Constants =====
const TIP_MEASURE := "measure"
const TIP_UNDO := "undo"
const TIP_DICE := "dice"
const TIP_RADIAL := "radial"
const TIP_REGIMENT := "regiment"
const TIP_GUEST_INTRO := "mp_guest_intro"

## Every one-shot tip id (guest intro included) — seeded into the session set at ready.
const ALL_TIP_IDS: Array[String] = [
	TIP_MEASURE, TIP_UNDO, TIP_DICE, TIP_RADIAL, TIP_REGIMENT, TIP_GUEST_INTRO,
]

## The MP guest short track: three toasts (camera · cursor · dice), shown in sequence on
## first join as a guest. Entirely client-side — nothing here touches the network protocol.
const GUEST_STEPS: Array[String] = [
	"You joined as a guest. Orbit with the right mouse button, pan with WASD, and zoom with the mouse wheel — the camera is yours alone.",
	"Everyone sees everyone's cursor. Yours has its own colour; the host and each other player have theirs.",
	"Roll dice any time from the dice tray in the corner — your rolls are shared with the whole table.",
]

# ===== Signals =====
## Emitted when a tip actually shows (id). Handy for the smoke harness and instrumentation.
signal tip_shown(tip_id: String)

# ===== Public state =====
var progress: TutorialProgress = null
var tutorial_active: bool = false

# ===== Scene refs (injected via setup) =====
var _object_manager: Node = null
var _dice_tray: Node = null
var _undo_manager: Node = null

# ===== Private state =====
var _shown_this_session: Dictionary = {}   # tip_id -> true (cheap once-ever read cache)
var _current_toast: TutorialTipToast = null
var _guest_queue: Array[String] = []


# ===== Public API =====

## Wire to the live scene. `refs` keys (all optional, null-guarded): object_manager,
## dice_tray, undo_manager, cfg_path. Seeds the session set from disk so a tip shown in a
## previous run never repeats.
func setup(refs: Dictionary) -> void:
	_object_manager = refs.get("object_manager", null)
	_dice_tray = refs.get("dice_tray", null)
	_undo_manager = refs.get("undo_manager", null)
	var cfg_path := String(refs.get("cfg_path", TutorialProgress.DEFAULT_PATH))
	progress = TutorialProgress.new(cfg_path)
	progress.load_from_disk()
	for id in ALL_TIP_IDS:
		if progress.is_tip_shown(id):
			_shown_this_session[id] = true
	_connect_seams()


## Suppress tips while a guided tutorial chapter is running (main calls this around the
## director's lifetime). Any trigger during suppression is dropped, never queued.
func set_tutorial_active(active: bool) -> void:
	tutorial_active = active


# ===== Static helpers (pure, unit-tested) =====

## True when a selection contains at least one regiment movement tray.
static func selection_has_regiment(selected: Array) -> bool:
	for obj in selected:
		if obj is RegimentTray:
			return true
	return false


## The body text for a one-shot tip id ("" if unknown).
static func tip_text(tip_id: String) -> String:
	match tip_id:
		TIP_MEASURE:
			return "You measured a distance. Hold Shift and drag with the left mouse button any time you need to check a range."
		TIP_UNDO:
			return "Made a mistake? Press Ctrl+Z to undo it — Ctrl+Y (or Ctrl+Shift+Z) redoes."
		TIP_DICE:
			return "Nice roll. Set the dice count and type in the dice tray, then roll as often as you like — results are read automatically."
		TIP_RADIAL:
			return "That is the radial menu. Every unit and model action lives here: activate, wounds, park a casualty, revive, delete and more."
		TIP_REGIMENT:
			return "This is a regiment movement tray (Age of Fantasy). Press F to show its 45° arcs, Shift+F to change frontage, and Ctrl+R to snap its facing."
		_:
			return ""


# ===== Seam wiring =====

func _connect_seams() -> void:
	if _object_manager != null:
		if _object_manager.has_signal("measurement_finished"):
			_object_manager.measurement_finished.connect(_on_measurement_finished)
		if _object_manager.has_signal("context_menu_requested"):
			_object_manager.context_menu_requested.connect(_on_context_menu_requested)
		if _object_manager.has_signal("selection_changed"):
			_object_manager.selection_changed.connect(_on_selection_changed)
	if _undo_manager != null and _undo_manager.has_signal("action_undone"):
		_undo_manager.action_undone.connect(_on_action_undone)
	if _dice_tray != null and _dice_tray.has_signal("roll_finnished"):
		_dice_tray.roll_finnished.connect(_on_roll_finnished)


# ===== Seam handlers (thin: route to a tip id) =====

func _on_measurement_finished(_distance_inches: float) -> void:
	_maybe_fire(TIP_MEASURE)


func _on_action_undone(_description: String) -> void:
	_maybe_fire(TIP_UNDO)


func _on_roll_finnished(_total: int) -> void:
	_maybe_fire(TIP_DICE)


func _on_context_menu_requested(_screen_pos: Vector2, _selected: Array) -> void:
	_maybe_fire(TIP_RADIAL)


func _on_selection_changed(selected: Array) -> void:
	if selection_has_regiment(selected):
		_maybe_fire(TIP_REGIMENT)


# ===== MP guest short track =====

## Play the guest intro (camera · cursor · dice) once ever. Called by main on first join as
## a GUEST. The flag is written up front so an interrupted sequence never replays.
func show_guest_intro() -> void:
	if not can_fire(TIP_GUEST_INTRO):
		return
	_record_shown(TIP_GUEST_INTRO)
	tip_shown.emit(TIP_GUEST_INTRO)
	_guest_queue = GUEST_STEPS.duplicate()
	_play_next_guest()


func _play_next_guest() -> void:
	if _guest_queue.is_empty():
		return
	var text: String = _guest_queue.pop_front()
	_present(text, _play_next_guest)


# ===== Firing policy =====

## True when `tip_id` may fire right now: not during a tutorial, no toast already on screen,
## a progress store exists, and the tip has never been shown. Pure (no scene work) so the
## whole gate is unit-testable.
func can_fire(tip_id: String) -> bool:
	if tutorial_active:
		return false
	if _current_toast != null and is_instance_valid(_current_toast):
		return false
	if progress == null:
		return false
	return not _shown_this_session.get(tip_id, false)


func _maybe_fire(tip_id: String) -> void:
	if not can_fire(tip_id):
		return
	_record_shown(tip_id)
	tip_shown.emit(tip_id)
	_present(tip_text(tip_id), func() -> void: pass)


## Persist a tip as shown. Reloads the cfg first so the write merges on top of any lesson /
## assessment values the director wrote to the same file (rather than clobbering them).
func _record_shown(tip_id: String) -> void:
	_shown_this_session[tip_id] = true
	if progress == null:
		return
	progress.load_from_disk()
	progress.mark_tip_shown(tip_id)
	progress.save_to_disk()


## Build and present one toast; `then` runs after it is dismissed (button or timeout).
func _present(text: String, then: Callable) -> void:
	var toast := TutorialTipToast.new()
	_current_toast = toast
	add_child(toast)
	toast.show_tip(text)
	toast.dismissed.connect(func() -> void:
		_current_toast = null
		then.call(), CONNECT_ONE_SHOT)
