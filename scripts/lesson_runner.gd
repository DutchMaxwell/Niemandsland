class_name LessonRunner
extends Node
## Polls lesson facts against the baseline taken at the start of each step.

signal step_changed(index: int, total: int, step: Dictionary)
signal chapter_completed(chapter_id: String)

## Poll every frame (0.0). A lesson gate can be TRANSIENT: activating the last unit of a side makes the
## solo alternation end the round in the same pump, clearing `activated` before a coarse poll would see
## it (S-04 step 3). Per-frame snapshots are cheap on a lesson table and make every gate observable.
const POLL_SECONDS := 0.0

var _chapter_id := ""
var _facts: Variant
var _progress: SpielschuleProgress
var _steps: Array = []
var _index := 0
var _base: Dictionary = {}
var _elapsed := 0.0
var _active := false


func setup(chapter_id: String, facts: Variant, progress: SpielschuleProgress) -> void:
	_chapter_id = chapter_id
	_facts = facts
	_progress = progress
	_steps = SpielschuleLessons.steps_for(chapter_id)
	_active = false
	set_process(false)

func begin() -> void:
	_index = 0
	_elapsed = 0.0
	if _steps.is_empty():
		push_warning("LessonRunner: no steps for chapter %s" % _chapter_id)
		return
	_base = _facts.snapshot()
	_active = true
	set_process(true)
	step_changed.emit(_index, _steps.size(), _steps[_index])


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	if _elapsed < POLL_SECONDS:
		return
	_elapsed = 0.0
	if LessonChecks.passes(_steps[_index], _facts.snapshot(), _base):
		_advance()

func skip_step() -> void:
	if _active:
		_advance()


func _advance() -> void:
	if _index + 1 < _steps.size():
		_index += 1
		_base = _facts.snapshot()
		_elapsed = 0.0
		step_changed.emit(_index, _steps.size(), _steps[_index])
		return
	_active = false
	set_process(false)
	_progress.mark_completed(_chapter_id)
	_progress.save_to_disk()
	chapter_completed.emit(_chapter_id)

func current_index() -> int:
	return _index

func total() -> int:
	return _steps.size()
