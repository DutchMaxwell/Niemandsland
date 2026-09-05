class_name ConsentStore
extends RefCounted
## Small, independent consent record. The player's game saves and identity state are
## deliberately never read here.

const DEFAULT_PATH := "user://privacy.json"
const CONSENT_SCHEMA_VERSION := 1

var evaluation_sharing := false
var training_use := false
var prompt_seen := false
var deletion_code := ""
var consent_schema_version := CONSENT_SCHEMA_VERSION
var _path: String


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


func load_from_disk() -> void:
	_reset()
	var needs_save := false
	if FileAccess.file_exists(_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(_path))
		if parsed is Dictionary:
			var data := parsed as Dictionary
			var candidate := str(data.get("deletion_code", ""))
			if _valid_code(candidate):
				deletion_code = candidate
			var saved_schema := int(data.get("consent_schema_version", 0))
			if saved_schema == CONSENT_SCHEMA_VERSION:
				evaluation_sharing = bool(data.get("evaluation_sharing", false))
				training_use = bool(data.get("training_use", false)) and evaluation_sharing
				prompt_seen = bool(data.get("prompt_seen", false))
			else:
				needs_save = true
	if deletion_code.is_empty():
		deletion_code = _new_code()
		needs_save = true
	if needs_save:
		save_to_disk()


func save_to_disk() -> Error:
	var absolute_dir := ProjectSettings.globalize_path(_path.get_base_dir())
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return mkdir_error
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({
		"consent_schema_version": consent_schema_version,
		"deletion_code": deletion_code,
		"evaluation_sharing": evaluation_sharing,
		"prompt_seen": prompt_seen,
		"training_use": training_use,
	}, "", true, true))
	file.close()
	return OK


func set_consent(allow_evaluation: bool, allow_training: bool) -> Error:
	evaluation_sharing = allow_evaluation
	training_use = allow_training and allow_evaluation
	prompt_seen = true
	return save_to_disk()


func mark_prompt_seen() -> Error:
	prompt_seen = true
	return save_to_disk()


func withdraw() -> Error:
	evaluation_sharing = false
	training_use = false
	return save_to_disk()


func should_prompt_after_completed_game() -> bool:
	return not prompt_seen


func _reset() -> void:
	evaluation_sharing = false
	training_use = false
	prompt_seen = false
	deletion_code = ""
	consent_schema_version = CONSENT_SCHEMA_VERSION


static func _new_code() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	return bytes.hex_encode() if bytes.size() == 16 else ""


static func _valid_code(value: String) -> bool:
	if value.length() != 32:
		return false
	for character in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true
