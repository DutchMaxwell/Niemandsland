extends GdUnitTestSuite
## W1.1c (0.3.15, rules 3.6): a save carries the rules version it was played under. Loading a save made
## under other rules, or one from before saves carried the stamp, is refused with a plain-words message
## naming both sides instead of loading onto this build's rules. Only major.minor counts: 3.6.0 and
## 3.6.9 are the same rules. The bundled Game School saves carry the stamp, so the lessons still open.
## The expected rules come from the rule maps (`rules_core_version`), never a second constant.

const SAVE_PATH := "user://w1_1c_rules_stamp_probe.nml"
const BUNDLED_SCENARIOS := "res://assets/tutorial/scenarios/"
const BUNDLED_BOARD := "res://assets/tutorial/tutorial_board.nml"
const BUNDLED_COUNT := 12  # 11 lesson scenarios + the tutorial board

var _failures: Array = []
var _completed := 0


## Counts table clears: a refused load must not touch the table at all.
class OmStub extends Node3D:
	var clears := 0
	var _object_counter: int = 0

	func clear_all_objects(_broadcast: bool = true) -> void:
		clears += 1


func before_test() -> void:
	# The reader caches per system; every case starts from the maps on disk.
	OPRApiClient._core_versions.clear()
	_failures.clear()
	_completed = 0


func after_test() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _build_rules() -> String:
	return OPRApiClient._major_minor(OPRApiClient.rules_core_version("gf"))


func _save_manager(om: OmStub) -> SaveManager:
	var sm: SaveManager = auto_free(SaveManager.new())
	sm.object_manager = om
	sm.load_failed.connect(func(error: String) -> void: _failures.append(error))
	sm.load_completed.connect(func(_count: int) -> void: _completed += 1)
	return sm


## A minimal save in today's format; `rules` "" leaves the stamp out (a save from before 0.3.15).
func _write_save(rules: String) -> void:
	var state := {"version": SaveManager.SAVE_VERSION, "table": {}, "game_units": [], "objects": []}
	if not rules.is_empty():
		state["rules_version"] = rules
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(state))
	f.close()


func _assert_refused(err: int, om: OmStub, what: String) -> void:
	assert_int(err).override_failure_message("%s loaded (err OK)" % what).is_not_equal(OK)
	assert_int(om.clears).override_failure_message("%s cleared the table before refusing" % what).is_equal(0)
	assert_int(_completed).override_failure_message("%s reported a completed load" % what).is_equal(0)
	assert_int(_failures.size()).override_failure_message("%s emitted no load_failed message" % what).is_equal(1)


func test_a_save_without_a_rules_stamp_is_refused_with_a_clear_message() -> void:
	var om: OmStub = auto_free(OmStub.new())
	var sm := _save_manager(om)
	_write_save("")
	var err: int = await sm.load_game(SAVE_PATH)
	_assert_refused(err, om, "a save without a rules stamp")
	var message := str(_failures[0]) if not _failures.is_empty() else ""
	assert_str(message).override_failure_message(
		"the refusal does not name this build's rules %s: '%s'" % [_build_rules(), message]).contains(_build_rules())
	assert_str(message).override_failure_message(
		"the refusal does not say the save carries no rules version: '%s'" % message).contains("no rules version")


func test_a_save_stamped_351_is_refused_naming_both_rules() -> void:
	var om: OmStub = auto_free(OmStub.new())
	var sm := _save_manager(om)
	_write_save("3.5.1")
	var err: int = await sm.load_game(SAVE_PATH)
	_assert_refused(err, om, "a 3.5.1 save")
	var message := str(_failures[0]) if not _failures.is_empty() else ""
	assert_str(message).override_failure_message(
		"the refusal does not name the save's rules 3.5: '%s'" % message).contains("rules 3.5")
	assert_str(message).override_failure_message(
		"the refusal does not name this build's rules %s: '%s'" % [_build_rules(), message]).contains(
		"rules %s" % _build_rules())


## CONTROL: a later patch of the same rules is the same rules and loads.
func test_a_save_from_a_later_patch_of_the_same_rules_loads() -> void:
	var om: OmStub = auto_free(OmStub.new())
	var sm := _save_manager(om)
	_write_save("%s.9" % _build_rules())
	var err: int = await sm.load_game(SAVE_PATH)
	assert_int(err).override_failure_message("a %s.9 save is refused: %s" % [_build_rules(), _failures]).is_equal(OK)
	assert_int(om.clears).is_equal(1)
	assert_int(_completed).is_equal(1)


func test_a_save_carries_the_rules_this_build_plays_and_loads_again() -> void:
	var om: OmStub = auto_free(OmStub.new())
	var sm := _save_manager(om)
	assert_int(sm.save_game(SAVE_PATH)).is_equal(OK)
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	assert_bool(saved is Dictionary).is_true()
	var stamp := str((saved as Dictionary).get("rules_version", "")) if saved is Dictionary else ""
	assert_str(stamp).override_failure_message(
		"the save carries rules '%s', the build plays '%s'" % [stamp, OPRApiClient.rules_core_version("gf")]).is_equal(
		OPRApiClient.rules_core_version("gf"))
	var err: int = await sm.load_game(SAVE_PATH)
	assert_int(err).override_failure_message("a fresh save of this build is refused: %s" % [_failures]).is_equal(OK)


## CONTROL: the stamp is read from the GF map; it stands for AoF too only while both play the same rules.
func test_gf_and_aof_play_the_same_rules() -> void:
	assert_str(OPRApiClient.rules_core_version("gf")).is_not_empty()
	assert_str(OPRApiClient.rules_core_version("aof")).is_equal(OPRApiClient.rules_core_version("gf"))


## Guard: every bundled save (Game School lessons + tutorial board) carries this build's rules, so the
## Game School still opens. The count proves the walk found the files.
func test_every_bundled_save_carries_this_builds_rules() -> void:
	var paths: Array = [BUNDLED_BOARD]
	for file: String in DirAccess.get_files_at(BUNDLED_SCENARIOS):
		if file.ends_with(".nml"):
			paths.append(BUNDLED_SCENARIOS + file)
	assert_int(paths.size()).is_equal(BUNDLED_COUNT)
	var wrong: Array = []
	for path: String in paths:
		var state: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var stamp := str((state as Dictionary).get("rules_version", "")) if state is Dictionary else ""
		if OPRApiClient._major_minor(stamp) != _build_rules():
			wrong.append("%s ('%s')" % [path.get_file(), stamp])
	assert_array(wrong).override_failure_message(
		"bundled saves without this build's rules %s: %s" % [_build_rules(), wrong]).is_empty()
