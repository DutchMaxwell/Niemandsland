extends GdUnitTestSuite
## A save whose write fails is reported as a failure and leaves the previous file intact. save_state_to_file used
## to open the destination itself for overwrite, write without checking anything after the open and report OK: a
## write that failed after a successful open (disk full, quota) left a truncated file in place of the previous
## save, and the player, or the autosave, was told it had saved. The fault is injected AFTER a successful open by
## overriding the single text write (_store_text); the open, the check and the replace are the real code. No real
## disk is filled.

const SAVE_PATH := "user://save_write_failure_test.nml"
const OLD_TEXT := "{\"previous\": \"save\"}"


## The real SaveManager with its one text write replaced by a fault.
class FaultySaveManager extends SaveManager:
	## "short": half the text lands and the write still reports success (data the OS lost without saying so, the
	## case only a read-back catches); "refused": half lands and the write reports the failure.
	var fault := ""

	func _store_text(file: FileAccess, text: String) -> bool:
		if fault.is_empty():
			return file.store_string(text)
		file.store_string(text.left(text.length() / 2))
		return fault == "short"


var _sm: FaultySaveManager
var _completed: Array = []


func before_test() -> void:
	_completed = []
	_sm = auto_free(FaultySaveManager.new())
	add_child(_sm)
	_sm.save_completed.connect(func(path: String) -> void: _completed.append(path))
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(OLD_TEXT)
	f.close()


func after_test() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _assert_failed_and_old_file_kept(what: String, err: int) -> void:
	assert_int(err).override_failure_message("%s: the save reported OK" % what).is_not_equal(OK)
	assert_array(_completed).override_failure_message("%s: save_completed fired" % what).is_empty()
	var now := FileAccess.get_file_as_string(SAVE_PATH)
	# A bool, not assert_str: gdUnit's string diff of a large file costs gigabytes.
	assert_bool(now == OLD_TEXT).override_failure_message(
		"%s: the previous save was overwritten (now %d bytes)" % [what, now.length()]).is_true()
	assert_bool(FileAccess.file_exists(SAVE_PATH + ".tmp")) \
		.override_failure_message("%s: the temp file was left behind" % what).is_false()


func test_a_short_write_that_reports_success_fails_and_keeps_the_old_save() -> void:
	_sm.fault = "short"
	_assert_failed_and_old_file_kept("short write", _sm.save_game(SAVE_PATH))


func test_a_failed_write_fails_and_keeps_the_old_save() -> void:
	_sm.fault = "refused"
	_assert_failed_and_old_file_kept("failed write", _sm.save_state_to_file({"objects": []}, SAVE_PATH))


## CONTROL: a healthy save replaces the old file completely, leaves no temp file and reports success.
func test_a_healthy_save_replaces_the_old_file() -> void:
	assert_int(_sm.save_game(SAVE_PATH)).is_equal(OK)
	assert_array(_completed).is_equal([SAVE_PATH])
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	assert_bool(saved is Dictionary and (saved as Dictionary).get("version") == SaveManager.SAVE_VERSION).is_true()
	assert_bool(FileAccess.file_exists(SAVE_PATH + ".tmp")).is_false()
