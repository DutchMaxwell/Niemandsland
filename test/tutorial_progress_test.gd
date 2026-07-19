extends GdUnitTestSuite
## Unit tests for the persisted tutorial state (TutorialProgress): cfg round-trip via an
## isolated test path (never the player's real user://tutorial.cfg), assessment answers,
## per-lesson completion flags, resume lookup and the sim-experienced skip offer.

const Progress := preload("res://scripts/tutorial_progress.gd")
const TEST_PATH := "user://test_tutorial_progress.cfg"
const TRACK_IDS: Array[String] = ["T-01", "T-02", "T-03", "T-04", "W2", "W5", "W6", "W7"]


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
	assert_str(progress.first_incomplete(TRACK_IDS)).is_equal("T-01")


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
	progress.mark_lesson_completed("T-01")
	progress.mark_lesson_completed("T-03")
	assert_int(progress.save_to_disk()).is_equal(OK)

	var reloaded := _new_progress()
	assert_bool(reloaded.is_lesson_completed("T-01")).is_true()
	assert_bool(reloaded.is_lesson_completed("T-02")).is_false()
	assert_bool(reloaded.is_lesson_completed("T-03")).is_true()
	assert_bool(reloaded.any_completed(TRACK_IDS)).is_true()
	assert_int(reloaded.completed_count(TRACK_IDS)).is_equal(2)
	# Resume = first incomplete in track order (T-01 done -> T-02, even though T-03 is done too).
	assert_str(reloaded.first_incomplete(TRACK_IDS)).is_equal("T-02")


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
	assert_array(Progress.skip_offer_lessons(true)).is_equal(["T-01", "T-02", "T-03"])
	assert_array(Progress.skip_offer_lessons(false)).is_equal([])


func test_skip_offer_lessons_gate_the_resume_point() -> void:
	# Applying the offer (as the director does on SKIP THE BASICS) makes the resume
	# lookup land on W2 — the first lesson that is neither completed nor skipped.
	var progress := _new_progress()
	for id in Progress.skip_offer_lessons(true):
		progress.mark_lesson_completed(id)
	assert_str(progress.first_incomplete(TRACK_IDS)).is_equal("T-04")


func test_v1_migration_maps_w1_to_t01_only() -> void:
	# Wave 1 (§17): a v1 file's completed W1 lifts to T-01 (camera unchanged); other W flags
	# stay untouched and must NOT auto-complete the richer T-chapters.
	var path := "user://test_tutorial_migrate.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("lessons", "W1", true)
	cfg.set_value("lessons", "W3", true)
	cfg.save(path)
	var progress := Progress.new(path)
	progress.load_from_disk()
	assert_bool(progress.is_lesson_completed("T-01")).is_true()
	assert_bool(progress.is_lesson_completed("T-02")).is_false()
	assert_bool(progress.is_lesson_completed("T-03")).is_false()
	DirAccess.remove_absolute(path)
