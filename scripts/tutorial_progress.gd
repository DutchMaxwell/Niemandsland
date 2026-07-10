class_name TutorialProgress
extends RefCounted
## Persisted tutorial state (T1): the two-question self-assessment and per-lesson
## completion flags, stored in user://tutorial.cfg via the same ConfigFile pattern the
## audio/graphics settings use. The path is injectable so tests (and the smoke harness)
## never touch the player's real progress file.
##
## Schema (cfg):
##   [meta]       version = 1
##   [assessment] answered = bool, knows_opr_rules = bool, used_simulator = bool
##   [lessons]    <lesson_id> = true            ; completed (or explicitly skipped)

# ===== Constants =====
const DEFAULT_PATH := "user://tutorial.cfg"
const CFG_VERSION := 1
const SECTION_META := "meta"
const SECTION_ASSESSMENT := "assessment"
const SECTION_LESSONS := "lessons"
## Lessons the assessment offers to skip for players who already know their way
## around a tabletop simulator: camera basics + select/move/rotate.
const SIM_EXPERIENCED_SKIP: Array[String] = ["W1", "W3"]

# ===== Private state =====
var _path: String = DEFAULT_PATH
var _config: ConfigFile = ConfigFile.new()


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


# ===== Disk =====

## Load from disk. A missing file is fine (fresh state).
func load_from_disk() -> void:
	_config = ConfigFile.new()
	var err := _config.load(_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("TutorialProgress: could not read %s (error %d) — starting fresh" % [_path, err])
		_config = ConfigFile.new()


func save_to_disk() -> Error:
	_config.set_value(SECTION_META, "version", CFG_VERSION)
	var err := _config.save(_path)
	if err != OK:
		push_warning("TutorialProgress: could not write %s (error %d)" % [_path, err])
	return err


## Forget everything (assessment + completions). Persists immediately.
func reset() -> void:
	_config = ConfigFile.new()
	save_to_disk()


# ===== Assessment =====

func assessment_answered() -> bool:
	return bool(_config.get_value(SECTION_ASSESSMENT, "answered", false))


func set_assessment(knows_rules: bool, used_sim: bool) -> void:
	_config.set_value(SECTION_ASSESSMENT, "answered", true)
	_config.set_value(SECTION_ASSESSMENT, "knows_opr_rules", knows_rules)
	_config.set_value(SECTION_ASSESSMENT, "used_simulator", used_sim)


func knows_opr_rules() -> bool:
	return bool(_config.get_value(SECTION_ASSESSMENT, "knows_opr_rules", false))


func used_simulator() -> bool:
	return bool(_config.get_value(SECTION_ASSESSMENT, "used_simulator", false))


## The lessons the assessment should OFFER to skip (T1: only the sim-experience
## axis gates anything — the rules axis becomes relevant with the T2 rule track).
static func skip_offer_lessons(used_sim: bool) -> Array[String]:
	var result: Array[String] = []
	if used_sim:
		result.assign(SIM_EXPERIENCED_SKIP)
	return result


# ===== Lesson completion =====

func mark_lesson_completed(lesson_id: String) -> void:
	if lesson_id.is_empty():
		return
	_config.set_value(SECTION_LESSONS, lesson_id, true)


func is_lesson_completed(lesson_id: String) -> bool:
	return bool(_config.get_value(SECTION_LESSONS, lesson_id, false))


func any_completed(lesson_ids: Array[String]) -> bool:
	for id in lesson_ids:
		if is_lesson_completed(id):
			return true
	return false


func completed_count(lesson_ids: Array[String]) -> int:
	var count := 0
	for id in lesson_ids:
		if is_lesson_completed(id):
			count += 1
	return count


## First lesson in track order that is not yet completed ("" when all are done).
func first_incomplete(lesson_ids: Array[String]) -> String:
	for id in lesson_ids:
		if not is_lesson_completed(id):
			return id
	return ""
