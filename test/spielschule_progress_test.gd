extends GdUnitTestSuite
## Unit tests for the Game School progress store (SpielschuleProgress): cfg round-trip via an
## isolated test path (never the player's real user://spielschule.cfg), chapter completion, the
## first-start hint flag, and — the mission's HARD rule — a fresh id space with NO W-/T-track bleed.

const Progress := preload("res://scripts/spielschule_progress.gd")
const TEST_PATH := "user://test_spielschule_progress.cfg"
const CHAPTER_IDS: Array[String] = ["S-01", "S-02", "S-03", "S-04", "S-05", "S-06", "S-07", "S-08", "S-09", "S-10"]


func before_test() -> void:
	_delete_test_file()


func after_test() -> void:
	_delete_test_file()


func _delete_test_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _new_progress() -> SpielschuleProgress:
	var progress := Progress.new(TEST_PATH) as SpielschuleProgress
	progress.load_from_disk()
	return progress


# ===== Fresh state =====

func test_fresh_state_is_empty() -> void:
	var progress := _new_progress()
	assert_bool(progress.hint_seen()).is_false()
	assert_bool(progress.any_completed(CHAPTER_IDS)).is_false()
	assert_int(progress.completed_count(CHAPTER_IDS)).is_equal(0)


# ===== Chapter completion round-trip =====

func test_completion_round_trip() -> void:
	var progress := _new_progress()
	progress.mark_completed("S-01")
	progress.mark_completed("S-03")
	assert_int(progress.save_to_disk()).is_equal(OK)

	var reloaded := _new_progress()
	assert_bool(reloaded.is_completed("S-01")).is_true()
	assert_bool(reloaded.is_completed("S-02")).is_false()
	assert_bool(reloaded.is_completed("S-03")).is_true()
	assert_bool(reloaded.any_completed(CHAPTER_IDS)).is_true()
	assert_int(reloaded.completed_count(CHAPTER_IDS)).is_equal(2)


func test_mark_empty_id_is_ignored() -> void:
	var progress := _new_progress()
	progress.mark_completed("")
	assert_bool(progress.any_completed(CHAPTER_IDS)).is_false()


# ===== First-start hint flag =====

func test_hint_flag_round_trip() -> void:
	var progress := _new_progress()
	assert_bool(progress.hint_seen()).is_false()
	progress.set_hint_seen(true)
	assert_int(progress.save_to_disk()).is_equal(OK)

	var reloaded := _new_progress()
	assert_bool(reloaded.hint_seen()).is_true()


# ===== No W-/T-track bleed (fresh namespace) =====

func test_does_not_read_old_tutorial_completions() -> void:
	# A cfg carrying old W-/T-track flags (as tutorial.cfg would) must NOT surface as a completed
	# Game School chapter — the two files are independent id spaces.
	var cfg := ConfigFile.new()
	cfg.set_value("lessons", "T-01", true)   # tutorial.cfg section/id
	cfg.set_value("chapters", "W1", true)    # a stray W id in our section must not match any S-*
	cfg.save(TEST_PATH)

	var progress := _new_progress()
	assert_bool(progress.any_completed(CHAPTER_IDS)).is_false()
	assert_bool(progress.is_completed("S-01")).is_false()


# ===== Reset =====

func test_reset_clears_completions_and_hint() -> void:
	var progress := _new_progress()
	progress.mark_completed("S-01")
	progress.set_hint_seen(true)
	progress.save_to_disk()
	progress.reset()

	var reloaded := _new_progress()
	assert_bool(reloaded.any_completed(CHAPTER_IDS)).is_false()
	assert_bool(reloaded.hint_seen()).is_false()
