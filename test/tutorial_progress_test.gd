extends GdUnitTestSuite
## Unit tests for the persisted tutorial state (TutorialProgress): cfg round-trip via an
## isolated test path (never the player's real user://tutorial.cfg), assessment answers,
## per-lesson completion flags, resume lookup and the sim-experienced skip offer.

const Progress := preload("res://scripts/tutorial_progress.gd")
const TEST_PATH := "user://test_tutorial_progress.cfg"
const TRACK_IDS: Array[String] = ["W1", "W2", "W3", "W4", "W5", "W6"]


func before_test() -> void:
	_delete_test_file()


func after_test() -> void:
	_delete_test_file()


func _delete_test_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _new_progress() -> TutorialProgress:
	var progress := Progress.new(TEST_PATH) as TutorialProgress
	progress.load_from_disk()
	return progress


## ===== Fresh state =====

func test_fresh_state_is_empty() -> void:
	var progress := _new_progress()
	assert_bool(progress.assessment_answered()).is_false()
	assert_bool(progress.knows_opr_rules()).is_false()
	assert_bool(progress.used_simulator()).is_false()
	assert_bool(progress.any_completed(TRACK_IDS)).is_false()
	assert_int(progress.completed_count(TRACK_IDS)).is_equal(0)
	assert_str(progress.first_incomplete(TRACK_IDS)).is_equal("W1")


## ===== Assessment round-trip =====

func test_assessment_round_trip() -> void:
	var progress := _new_progress()
	progress.set_assessment(true, false)
	assert_int(progress.save_to_disk()).is_equal(OK)

	var reloaded := _new_progress()
	assert_bool(reloaded.assessment_answered()).is_true()
	assert_bool(reloaded.knows_opr_rules()).is_true()
	assert_bool(reloaded.used_simulator()).is_false()


## ===== Lesson completion round-trip + resume =====

func test_lesson_completion_round_trip_and_resume() -> void:
	var progress := _new_progress()
	progress.mark_lesson_completed("W1")
	progress.mark_lesson_completed("W3")
	assert_int(progress.save_to_disk()).is_equal(OK)

	var reloaded := _new_progress()
	assert_bool(reloaded.is_lesson_completed("W1")).is_true()
	assert_bool(reloaded.is_lesson_completed("W2")).is_false()
	assert_bool(reloaded.is_lesson_completed("W3")).is_true()
	assert_bool(reloaded.any_completed(TRACK_IDS)).is_true()
	assert_int(reloaded.completed_count(TRACK_IDS)).is_equal(2)
	# Resume = first incomplete in track order (W1 done -> W2, even though W3 is done too).
	assert_str(reloaded.first_incomplete(TRACK_IDS)).is_equal("W2")


func test_first_incomplete_empty_when_all_done() -> void:
	var progress := _new_progress()
	for id in TRACK_IDS:
		progress.mark_lesson_completed(id)
	assert_str(progress.first_incomplete(TRACK_IDS)).is_equal("")


func test_mark_empty_id_is_ignored() -> void:
	var progress := _new_progress()
	progress.mark_lesson_completed("")
	assert_bool(progress.any_completed(TRACK_IDS)).is_false()


## ===== Reset =====

func test_reset_clears_everything() -> void:
	var progress := _new_progress()
	progress.set_assessment(true, true)
	progress.mark_lesson_completed("W1")
	progress.save_to_disk()
	progress.reset()

	var reloaded := _new_progress()
	assert_bool(reloaded.assessment_answered()).is_false()
	assert_bool(reloaded.any_completed(TRACK_IDS)).is_false()


## ===== Assessment gating (skip offer) =====

func test_skip_offer_only_for_sim_experienced() -> void:
	assert_array(Progress.skip_offer_lessons(true)).is_equal(["W1", "W3"])
	assert_array(Progress.skip_offer_lessons(false)).is_equal([])


func test_skip_offer_lessons_gate_the_resume_point() -> void:
	# Applying the offer (as the director does on SKIP THE BASICS) makes the resume
	# lookup land on W2 — the first lesson that is neither completed nor skipped.
	var progress := _new_progress()
	for id in Progress.skip_offer_lessons(true):
		progress.mark_lesson_completed(id)
	assert_str(progress.first_incomplete(TRACK_IDS)).is_equal("W2")


## ===== T2: rule-axis skip offer (both self-assessment axes) =====

func test_rule_skip_offer_from_both_axes() -> void:
	# Sim axis -> tool basics; rules axis -> rule track; both -> union in track order.
	assert_array(Progress.skip_offer_lessons(false, false)).is_equal([])
	assert_array(Progress.skip_offer_lessons(false, true)).is_equal(["R1", "R2", "R3"])
	assert_array(Progress.skip_offer_lessons(true, false)).is_equal(["W1", "W3"])
	assert_array(Progress.skip_offer_lessons(true, true)).is_equal(["W1", "W3", "R1", "R2", "R3"])


## ===== T2: one-time tips / guest intro (once-ever) =====

func test_tip_flags_round_trip_and_are_once_ever() -> void:
	var progress := _new_progress()
	assert_bool(progress.is_tip_shown("radial")).is_false()
	progress.mark_tip_shown("radial")
	# Marking again is idempotent (still a single true flag).
	progress.mark_tip_shown("radial")
	assert_int(progress.save_to_disk()).is_equal(OK)

	var reloaded := _new_progress()
	assert_bool(reloaded.is_tip_shown("radial")).is_true()
	assert_bool(reloaded.is_tip_shown("measure")).is_false()


func test_guest_intro_flag_persists_once_ever() -> void:
	var progress := _new_progress()
	assert_bool(progress.is_tip_shown("mp_guest_intro")).is_false()
	progress.mark_tip_shown("mp_guest_intro")
	progress.save_to_disk()
	assert_bool(_new_progress().is_tip_shown("mp_guest_intro")).is_true()


func test_empty_tip_id_is_ignored() -> void:
	var progress := _new_progress()
	progress.mark_tip_shown("")
	assert_bool(progress.is_tip_shown("")).is_false()


## ===== T2: cfg schema migration from the T1 version (v1 -> v2) =====

func test_migration_from_v1_preserves_state_and_bumps_version() -> void:
	# Author a raw v1 file exactly as T1 wrote it: version 1, an assessment, one lesson,
	# NO [tips] section.
	var v1 := ConfigFile.new()
	v1.set_value("meta", "version", 1)
	v1.set_value("assessment", "answered", true)
	v1.set_value("assessment", "knows_opr_rules", true)
	v1.set_value("assessment", "used_simulator", false)
	v1.set_value("lessons", "W1", true)
	assert_int(v1.save(TEST_PATH)).is_equal(OK)

	# Loading migrates to v2 in memory; existing state survives, tips default to unshown.
	var progress := _new_progress()
	assert_int(progress.cfg_version()).is_equal(Progress.CFG_VERSION)
	assert_bool(progress.assessment_answered()).is_true()
	assert_bool(progress.knows_opr_rules()).is_true()
	assert_bool(progress.is_lesson_completed("W1")).is_true()
	assert_bool(progress.is_tip_shown("radial")).is_false()

	# Saving persists the bumped version without dropping the migrated state.
	assert_int(progress.save_to_disk()).is_equal(OK)
	var reloaded := _new_progress()
	assert_int(reloaded.cfg_version()).is_equal(Progress.CFG_VERSION)
	assert_bool(reloaded.is_lesson_completed("W1")).is_true()
	assert_bool(reloaded.knows_opr_rules()).is_true()
