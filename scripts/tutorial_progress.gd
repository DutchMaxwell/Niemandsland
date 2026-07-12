class_name TutorialProgress
extends RefCounted
## Persisted tutorial state: the two-question self-assessment, per-lesson completion flags
## (tool track W1-W6 + rule track R1-R3), and the T2 one-time contextual-tip / MP-guest-intro
## flags, stored in user://tutorial.cfg via the same ConfigFile pattern the audio/graphics
## settings use. The path is injectable so tests (and the smoke harness) never touch the
## player's real progress file.
##
## Schema (cfg):
##   [meta]       version = 2
##   [assessment] answered = bool, knows_opr_rules = bool, used_simulator = bool
##   [lessons]    <lesson_id> = true            ; completed (or explicitly skipped)
##   [tips]       <tip_id> = true               ; a one-time tip / guest-intro shown once ever
##
## Migration: a v1 file (no [tips] section) loads unchanged — the schema is purely
## additive — and is rewritten as v2 on the next save. `_migrate` is the forward-only
## hook for any future non-additive change.

# ===== Constants =====
const DEFAULT_PATH := "user://tutorial.cfg"
const CFG_VERSION := 2
const SECTION_META := "meta"
const SECTION_ASSESSMENT := "assessment"
const SECTION_LESSONS := "lessons"
const SECTION_TIPS := "tips"
## Lessons the assessment offers to skip for players who already know their way
## around a tabletop simulator: camera basics + select/move/rotate.
const SIM_EXPERIENCED_SKIP: Array[String] = ["W1", "W3"]
## Lessons the assessment offers to skip for players who already know the OPR rules:
## the whole active rule track. R2 (Regiments) was pulled from the track into an archive
## for a future purpose-built tutorial, so it is NOT offered here. A cfg written by an older
## build that has R2 marked done stays valid — R2 is not a track member, so it is never
## visited; a stale [lessons] R2=true flag is simply ignored (no migration needed).
const RULES_KNOWN_SKIP: Array[String] = ["R1", "R3"]

# ===== Private state =====
var _path: String = DEFAULT_PATH
var _config: ConfigFile = ConfigFile.new()


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


# ===== Disk =====

## Load from disk. A missing file is fine (fresh state). An older schema is migrated
## forward in memory so the caller always sees the current shape.
func load_from_disk() -> void:
	_config = ConfigFile.new()
	var err := _config.load(_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("TutorialProgress: could not read %s (error %d) — starting fresh" % [_path, err])
		_config = ConfigFile.new()
	_migrate()


func save_to_disk() -> Error:
	_config.set_value(SECTION_META, "version", CFG_VERSION)
	var err := _config.save(_path)
	if err != OK:
		push_warning("TutorialProgress: could not write %s (error %d)" % [_path, err])
	return err


## Forget everything (assessment + completions + tips). Persists immediately.
func reset() -> void:
	_config = ConfigFile.new()
	save_to_disk()


## The schema version currently held in memory (post-migration after load).
func cfg_version() -> int:
	return int(_config.get_value(SECTION_META, "version", 1))


## Forward-only migration of an older on-disk schema to CFG_VERSION, in memory only
## (persisted on the next save). v1 -> v2 is purely additive (the new [tips] section
## simply did not exist), so there is nothing to transform — we only stamp the version
## so a subsequent save writes the current shape. Future non-additive steps slot in here.
func _migrate() -> void:
	var from := int(_config.get_value(SECTION_META, "version", 1))
	if from >= CFG_VERSION:
		return
	# v1 -> v2: additive only (tips). No field moves.
	_config.set_value(SECTION_META, "version", CFG_VERSION)


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


## The lessons the assessment should OFFER to skip, from both self-assessment axes:
## sim-experienced players may skip the camera + select/move basics (W1/W3); players who
## already know the OPR rules may skip the whole rule track (R1-R3). The axes are
## independent, so the offer is their union in track order.
static func skip_offer_lessons(used_sim: bool, knows_rules: bool = false) -> Array[String]:
	var result: Array[String] = []
	if used_sim:
		result.append_array(SIM_EXPERIENCED_SKIP)
	if knows_rules:
		result.append_array(RULES_KNOWN_SKIP)
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


# ===== One-time tips / guest intro (T2) =====

## True once a given one-time tip (or the MP guest intro) has ever been shown. The tip
## ids are opaque strings owned by TutorialTips — this store is deliberately generic,
## exactly like the lessons section.
func is_tip_shown(tip_id: String) -> bool:
	return bool(_config.get_value(SECTION_TIPS, tip_id, false))


func mark_tip_shown(tip_id: String) -> void:
	if tip_id.is_empty():
		return
	_config.set_value(SECTION_TIPS, tip_id, true)
