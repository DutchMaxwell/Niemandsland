class_name SpielschuleProgress
extends RefCounted
## Persisted Game School state: per-chapter completion flags + the one-time first-start hint flag,
## in user://spielschule.cfg via the same ConfigFile pattern TutorialProgress / GraphicsSettings use.
##
## DELIBERATELY a SEPARATE file + namespace from user://tutorial.cfg. The Game School uses FRESH
## chapter ids (S-01..S-10, S-SPELL) that must NEVER migrate from or collide with the old W-/T-track
## ids — so this class has NO _migrate() and never reads the tutorial file. The path is injectable so
## tests (and the smoke harness) never touch the player's real progress.
##
## Schema (cfg):
##   [meta]     version = 1, hint_seen = bool     ; hint_seen gates the first-start pointer
##   [chapters] <chapter_id> = true               ; completed (still replayable)

# ===== Constants =====
const DEFAULT_PATH := "user://spielschule.cfg"
const CFG_VERSION := 1
const SECTION_META := "meta"
const SECTION_CHAPTERS := "chapters"

# ===== Private state =====
var _path: String = DEFAULT_PATH
var _config: ConfigFile = ConfigFile.new()


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


# ===== Disk =====

## Load from disk. A missing file is fine (fresh state). No migration by design (fresh id space).
func load_from_disk() -> void:
	_config = ConfigFile.new()
	var err := _config.load(_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("SpielschuleProgress: could not read %s (error %d) — starting fresh" % [_path, err])
		_config = ConfigFile.new()


func save_to_disk() -> Error:
	_config.set_value(SECTION_META, "version", CFG_VERSION)
	var err := _config.save(_path)
	if err != OK:
		push_warning("SpielschuleProgress: could not write %s (error %d)" % [_path, err])
	return err


## Forget everything (completions + hint flag). Persists immediately.
func reset() -> void:
	_config = ConfigFile.new()
	save_to_disk()


# ===== First-start hint =====

## Whether the one-time "New: Game School" pointer has already been shown/dismissed.
func hint_seen() -> bool:
	return bool(_config.get_value(SECTION_META, "hint_seen", false))


func set_hint_seen(seen: bool) -> void:
	_config.set_value(SECTION_META, "hint_seen", seen)


# ===== Chapter completion =====

func mark_completed(chapter_id: String) -> void:
	if chapter_id.is_empty():
		return
	_config.set_value(SECTION_CHAPTERS, chapter_id, true)


func is_completed(chapter_id: String) -> bool:
	return bool(_config.get_value(SECTION_CHAPTERS, chapter_id, false))


func any_completed(chapter_ids: Array[String]) -> bool:
	for id in chapter_ids:
		if is_completed(id):
			return true
	return false


func completed_count(chapter_ids: Array[String]) -> int:
	var count := 0
	for id in chapter_ids:
		if is_completed(id):
			count += 1
	return count
