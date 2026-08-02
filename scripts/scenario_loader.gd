class_name ScenarioLoader
extends RefCounted

## Where bundled lesson scenarios live. _on_load_file_selected uses this marker to tell a lesson
## load from the player loading their OWN battle — which must LEAVE the lesson (autosave pause is
## scoped to lesson state, never to the scene).
const SCENARIO_DIR := "res://assets/tutorial/scenarios/"
## Loads a bundled .nml Game School lesson through the REAL save/load path, isolating it from the
## player's own table:
##   begin_lesson()  captures the current table into memory AND pauses autosave for the lesson.
##   load_scenario() loads the chapter's bundled .nml via save_manager.load_game (migration + signals).
##   end_lesson()    restores the captured table through the real load path AND resumes autosave.
##
## WHY reuse the real path (not a parallel loader): a bundled .nml is stamped at build-time
## SAVE_VERSION, so a chapter authored today must survive a future SAVE_VERSION bump — it only does if
## every load runs through SaveMigrations.migrate, which load_game does. Restoring the player's own
## table via save_manager.restore_state (temp file -> load_game) keeps that direction identical too.
##
## Isolation surface (the adversarial focus of review):
##  - autosave: a lesson table must NEVER hit the player's real save slots — paused for the whole
##    lesson lifetime (the restore lock alone only covers the brief begin/end_restore window).
##  - chalk trails / move ledger are runtime-only (NOT serialized), so a lesson would otherwise leave
##    trails on the player's restored table — cleared on end_lesson.
## The refs are duck-typed (has_method) so the loader is unit-testable with lightweight fakes.

var _save_manager: Node = null
var _autosave: Node = null       # AutosaveController (optional)
var _move_trails: Node = null    # MoveTrails (optional; chalk-trail cleanup)
var _snapshot: Dictionary = {}
var _captured: bool = false


func setup(save_manager: Node, autosave: Node = null, move_trails: Node = null) -> void:
	_save_manager = save_manager
	_autosave = autosave
	_move_trails = move_trails


## Capture the player's current in-memory table and pause autosave. Call BEFORE load_scenario.
func begin_lesson() -> void:
	if _save_manager != null and _save_manager.has_method("serialize_game_state"):
		_snapshot = _save_manager.serialize_game_state()
		_captured = true
	_set_autosave_paused(true)


## Load a bundled .nml scenario through the REAL load path (clear + migration + deserialize +
## load_completed/load_failed signals). Returns ERR_FILE_NOT_FOUND for an unbundled chapter without
## touching the table, so a "scenario coming soon" chapter can never wipe the board.
func load_scenario(scenario_path: String) -> Error:
	if _save_manager == null or not _save_manager.has_method("load_game"):
		return ERR_UNCONFIGURED
	if scenario_path.is_empty() or not FileAccess.file_exists(scenario_path):
		return ERR_FILE_NOT_FOUND
	return await _save_manager.load_game(scenario_path)


## Restore the captured table through the real load path and resume autosave. Idempotent: a second
## call (finish AND abort both fire it) is a no-op once the snapshot is consumed.
func end_lesson() -> Error:
	_clear_trails()
	var err := OK
	if _captured and _save_manager != null and _save_manager.has_method("restore_state"):
		err = await _save_manager.restore_state(_snapshot)
	_captured = false
	_snapshot = {}
	_set_autosave_paused(false)
	return err


## Whether a table snapshot is currently held (captured, not yet restored).
func has_snapshot() -> bool:
	return _captured


## The captured snapshot (empty when none is held) — exposed for tests + a future in-scene restore.
func snapshot() -> Dictionary:
	return _snapshot


## The player loads a REAL save from inside a lesson: the lesson is over. The external load
## replaces the whole board anyway, so the captured snapshot is dropped WITHOUT a restore (restoring
## first would double-load), and the autosave pause lifts so the player's own game keeps its safety
## net. Review finding: without this, begin_lesson()'s pause outlived the lesson for the entire
## scene, and an in-scene "Load Game" left the real battle without periodic or round autosaves.
func leave_lesson_for_external_load() -> void:
	_clear_trails()
	_captured = false
	_snapshot = {}
	_set_autosave_paused(false)


func _set_autosave_paused(paused: bool) -> void:
	if _autosave != null and _autosave.has_method("set_lesson_paused"):
		_autosave.set_lesson_paused(paused)


func _clear_trails() -> void:
	if _move_trails != null and _move_trails.has_method("clear_all"):
		_move_trails.clear_all()
