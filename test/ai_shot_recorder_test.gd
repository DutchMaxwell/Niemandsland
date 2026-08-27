extends GdUnitTestSuite
## NML-1073 M5 D6a-B6: AiShotRecorder (scripts/solo/shot_recorder.gd) — env NML_SHOT_DUMP=<dir>
## appends one JSON line per shot to shots.jsonl, same contract shape as AiDiceRecorder
## (scripts/solo/dice_recorder.gd — no dedicated test suite exists for it to mirror, so this
## suite follows AiActRecorder's before_test/after_test idiom instead). Unset (default) must
## never touch disk: main.gd's tap calls record() unconditionally either way.

const _DUMP_DIR := "user://shot_recorder_test_tmp"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(_DUMP_DIR)
	# AiShotRecorder's env check + open stream are cached STATIC state (by design — the real
	# game opens the file once per process) — reset it per test so two test_ functions in this
	# suite do not share one stream.
	AiShotRecorder._checked = false
	AiShotRecorder._stream = null
	AiShotRecorder._count = 0
	OS.set_environment("NML_SHOT_DUMP", "")


func after_test() -> void:
	AiShotRecorder.close()
	OS.set_environment("NML_SHOT_DUMP", "")
	var d := DirAccess.open(_DUMP_DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(_DUMP_DIR)


func _dump_lines() -> Array:
	var f := FileAccess.open(_DUMP_DIR.path_join("shots.jsonl"), FileAccess.READ)
	if f == null:
		return []
	var out: Array = []
	while not f.eof_reached():
		var line := f.get_line()
		if line != "":
			out.append(line)
	f.close()
	return out


## NML_SHOT_DUMP unset (the default) — record() must no-op, never creating shots.jsonl.
func test_record_no_ops_when_env_unset() -> void:
	AiShotRecorder.record({"act": 1, "round": 1, "player": 1, "shooter": "A", "member": "A",
		"weapon": "Rifle", "target": "B", "alive": 5, "sighted": 3, "bearers": -1,
		"max_models": 5, "attacks": 3, "reach_in": 24.0, "indirect": false})
	assert_bool(FileAccess.file_exists(_DUMP_DIR.path_join("shots.jsonl"))).is_false()


## NML_SHOT_DUMP set — record() writes one parsable line carrying every field the tap fills.
func test_record_writes_a_line_when_env_set() -> void:
	OS.set_environment("NML_SHOT_DUMP", ProjectSettings.globalize_path(_DUMP_DIR))
	AiShotRecorder.record({"act": 4, "round": 2, "player": 1, "shooter": "Squad A", "member": "Sergeant",
		"weapon": "Special Rifle", "target": "Squad B", "alive": 4, "sighted": 2, "bearers": 1,
		"max_models": 5, "attacks": 2, "reach_in": 25.4, "indirect": true})

	var lines := _dump_lines()
	assert_int(lines.size()).is_equal(1)
	var rec: Dictionary = JSON.parse_string(lines[0])
	for key in ["act", "round", "player", "shooter", "member", "weapon", "target",
			"alive", "sighted", "bearers", "max_models", "attacks", "reach_in", "indirect"]:
		assert_bool(rec.has(key)).is_true()
	assert_int(int(rec["act"])).is_equal(4)
	assert_str(str(rec["shooter"])).is_equal("Squad A")
	assert_str(str(rec["member"])).is_equal("Sergeant")
	assert_int(int(rec["bearers"])).is_equal(1)
	assert_bool(bool(rec["indirect"])).is_true()


## NML_SHOT_DUMP_MAX caps the line count — the same cap contract as AiDiceRecorder/AiActRecorder.
func test_record_respects_the_line_cap() -> void:
	OS.set_environment("NML_SHOT_DUMP", ProjectSettings.globalize_path(_DUMP_DIR))
	OS.set_environment("NML_SHOT_DUMP_MAX", "1")
	AiShotRecorder.record({"act": 1, "round": 1, "player": 1, "shooter": "A", "member": "A",
		"weapon": "W", "target": "B", "alive": 1, "sighted": 1, "bearers": -1,
		"max_models": 1, "attacks": 1, "reach_in": 12.0, "indirect": false})
	AiShotRecorder.record({"act": 2, "round": 1, "player": 1, "shooter": "A", "member": "A",
		"weapon": "W", "target": "B", "alive": 1, "sighted": 1, "bearers": -1,
		"max_models": 1, "attacks": 1, "reach_in": 12.0, "indirect": false})
	assert_int(_dump_lines().size()).is_equal(1)
	OS.set_environment("NML_SHOT_DUMP_MAX", "")
