class_name TutorialProgress
extends RefCounted
## Persisted tutorial state: the two-question self-assessment, per-lesson completion flags
## (tool track W1-W6 + rule track R1-R3), and the T2 one-time contextual-tip / MP-guest-intro
## flags, stored in user://tutorial.cfg via the same ConfigFile pattern the audio/graphics
## settings use. The path is injectable so tests (and the smoke harness) never touch the
## player's real progress file.
##
## Schema (cfg):
##   [meta]       version = 3
##                last_system = "gf"            ; drives the RULES chapter picker (design §17)
##   [assessment] answered = bool, knows_opr_rules = bool, used_simulator = bool
##   [lessons]    <lesson_id> = true            ; completed (or explicitly skipped) — any id string
##   [tips]       <tip_id> = true               ; a one-time tip / guest-intro shown once ever
##
## Migration (forward-only, additive): a v1 file (no [tips]) loads unchanged; v2 -> v3 stamps
## last_system = "gf" and maps the one identical chapter (completed W1 -> T-01, since the camera
## lesson is unchanged). Old W2..W6 / R* flags are left as-is (harmless: they are not members of
## the richer T-track, so a returning player replays the fuller chapters). `_migrate` is the
## forward-only hook.

# ===== Constants =====
const DEFAULT_PATH := "user://tutorial.cfg"
const CFG_VERSION := 3
const DEFAULT_SYSTEM := "gf"    # game system the RULES picker defaults to (Grimdark Future)
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


## The last game system the player was in (GF/GFF/AoF/AoFS/AoFR) — drives which RULES
## chapters the picker shows. Defaults to Grimdark Future (design §17).
func last_system() -> String:
	return String(_config.get_value(SECTION_META, "last_system", DEFAULT_SYSTEM))


func set_last_system(system: String) -> void:
	if system.is_empty():
		return
	_config.set_value(SECTION_META, "last_system", system)


## Forward-only migration of an older on-disk schema to CFG_VERSION, in memory only
## (persisted on the next save). v1 -> v2 is purely additive (the new [tips] section
## simply did not exist), so there is nothing to transform — we only stamp the version
## so a subsequent save writes the current shape. Future non-additive steps slot in here.
func _migrate() -> void:
	var from := int(_config.get_value(SECTION_META, "version", 1))
	if from >= CFG_VERSION:
		return
	# v1 -> v2: additive only (the [tips] section). Nothing to transform.
	# v2 -> v3: the camera chapter W1 became T-01 (identical content), so a player who finished
	# W1 keeps that completion; default the RULES-picker system. Other legacy W2..W6 / R* flags
	# stay as-is (a returning player replays the richer T-chapters — design §17).
	if from < 3:
		if bool(_config.get_value(SECTION_LESSONS, "W1", false)):
			_config.set_value(SECTION_LESSONS, "T-01", true)
		if not _config.has_section_key(SECTION_META, "last_system"):
			_config.set_value(SECTION_META, "last_system", DEFAULT_SYSTEM)
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
