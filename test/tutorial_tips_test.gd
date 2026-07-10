extends GdUnitTestSuite
## Tests for the contextual first-time tips + MP guest intro (TutorialTips): the pure firing
## policy (once-ever, one-at-a-time, not-during-a-tutorial), the regiment-selection predicate,
## the tip copy, and once-ever persistence through an isolated cfg (never the player's file).
## The toast presentation itself touches the scene tree and is covered by the launch smoke;
## these tests drive only the scene-free gate, so the tips node is never added to the tree.

const Tips := preload("res://scripts/tutorial_tips.gd")
const Progress := preload("res://scripts/tutorial_progress.gd")
const TEST_CFG := "user://test_tutorial_tips.cfg"


func before_test() -> void:
	_delete_test_cfg()


func after_test() -> void:
	_delete_test_cfg()


func _delete_test_cfg() -> void:
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))


## A tips manager wired to the isolated cfg. Not in the tree; scene refs stay null (guarded).
func _new_tips() -> TutorialTips:
	var tips := auto_free(Tips.new()) as TutorialTips
	tips.setup({"cfg_path": TEST_CFG})
	return tips


## ===== Static predicates / copy =====

func test_selection_has_regiment() -> void:
	var tray: RegimentTray = auto_free(RegimentTray.new())
	var loose: Node3D = auto_free(Node3D.new())
	assert_bool(Tips.selection_has_regiment([tray])).is_true()
	assert_bool(Tips.selection_has_regiment([loose, tray])).is_true()
	assert_bool(Tips.selection_has_regiment([loose])).is_false()
	assert_bool(Tips.selection_has_regiment([])).is_false()


func test_tip_text_known_and_unknown() -> void:
	for id in [Tips.TIP_MEASURE, Tips.TIP_UNDO, Tips.TIP_DICE, Tips.TIP_RADIAL, Tips.TIP_REGIMENT]:
		assert_str(Tips.tip_text(id)).is_not_empty()
	assert_str(Tips.tip_text("nope")).is_empty()


func test_guest_track_has_three_steps() -> void:
	assert_int(Tips.GUEST_STEPS.size()).is_equal(3)


## ===== Firing policy (can_fire) =====

func test_null_progress_never_fires() -> void:
	var tips := auto_free(Tips.new()) as TutorialTips  # no setup -> progress stays null
	assert_bool(tips.can_fire(Tips.TIP_DICE)).is_false()


func test_fresh_tip_can_fire() -> void:
	assert_bool(_new_tips().can_fire(Tips.TIP_DICE)).is_true()


func test_active_tutorial_suppresses_tips() -> void:
	var tips := _new_tips()
	tips.set_tutorial_active(true)
	assert_bool(tips.can_fire(Tips.TIP_DICE)).is_false()
	tips.set_tutorial_active(false)
	assert_bool(tips.can_fire(Tips.TIP_DICE)).is_true()


func test_one_at_a_time_blocks_while_a_toast_is_up() -> void:
	var tips := _new_tips()
	tips._current_toast = auto_free(TutorialTipToast.new())  # a live toast on screen
	assert_bool(tips.can_fire(Tips.TIP_DICE)).is_false()
	tips._current_toast = null
	assert_bool(tips.can_fire(Tips.TIP_DICE)).is_true()


## ===== Once-ever semantics + persistence =====

func test_record_shown_is_once_ever_within_a_session() -> void:
	var tips := _new_tips()
	assert_bool(tips.can_fire(Tips.TIP_RADIAL)).is_true()
	tips._record_shown(Tips.TIP_RADIAL)
	assert_bool(tips.can_fire(Tips.TIP_RADIAL)).is_false()
	# A different tip is unaffected.
	assert_bool(tips.can_fire(Tips.TIP_MEASURE)).is_true()


func test_shown_tip_persists_across_sessions() -> void:
	_new_tips()._record_shown(Tips.TIP_REGIMENT)
	# A brand-new manager over the same cfg seeds the flag from disk and refuses to re-fire.
	var reloaded := _new_tips()
	assert_bool(reloaded.can_fire(Tips.TIP_REGIMENT)).is_false()
	assert_bool(reloaded.can_fire(Tips.TIP_DICE)).is_true()


func test_guest_intro_is_once_ever() -> void:
	var tips := _new_tips()
	assert_bool(tips.can_fire(Tips.TIP_GUEST_INTRO)).is_true()
	tips._record_shown(Tips.TIP_GUEST_INTRO)
	assert_bool(tips.can_fire(Tips.TIP_GUEST_INTRO)).is_false()
	# Persisted: a fresh manager over the same cfg will not replay the guest track.
	assert_bool(_new_tips().can_fire(Tips.TIP_GUEST_INTRO)).is_false()


func test_record_merges_over_director_lesson_writes() -> void:
	# The director writes a lesson to the same cfg; a later tip write must not drop it
	# (the tips manager reloads before marking + saving).
	var director_side := Progress.new(TEST_CFG)
	director_side.load_from_disk()
	director_side.mark_lesson_completed("W1")
	director_side.save_to_disk()

	var tips := _new_tips()
	tips._record_shown(Tips.TIP_UNDO)

	var check := Progress.new(TEST_CFG)
	check.load_from_disk()
	assert_bool(check.is_lesson_completed("W1")).is_true()   # survived the tip write
	assert_bool(check.is_tip_shown(Tips.TIP_UNDO)).is_true()
