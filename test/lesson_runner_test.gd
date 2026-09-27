extends GdUnitTestSuite

const Runner := preload("res://scripts/lesson_runner.gd")
const TEST_CFG := "user://test_lesson_runner.cfg"

class FakeFacts extends RefCounted:
	var yaw := 0.0
	var counters := {"measure": 0}
	func snapshot() -> Dictionary:
		return {"yaw": yaw, "cam_dist": 10.0, "pivot": Vector3.ZERO,
			"tags": {}, "counters": counters.duplicate()}


func before_test() -> void:
	_delete_cfg()


func after_test() -> void:
	_delete_cfg()


func _delete_cfg() -> void:
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))


func test_waits_for_state_then_advances_and_skips() -> void:
	var facts := FakeFacts.new()
	var progress := SpielschuleProgress.new(TEST_CFG)
	var runner: LessonRunner = auto_free(Runner.new())
	var shown: Array[int] = []
	runner.step_changed.connect(func(index: int, _total: int, _step: Dictionary) -> void: shown.append(index))
	runner.setup("S-01", facts, progress)
	runner.begin()
	assert_int(runner.current_index()).is_equal(0)
	assert_int(runner.total()).is_equal(6)
	runner._process(0.21)
	assert_int(runner.current_index()).is_equal(0)
	facts.yaw += 0.5
	runner._process(0.21)
	assert_int(runner.current_index()).is_equal(1)
	runner._process(0.21)
	assert_int(runner.current_index()).is_equal(1)
	runner.skip_step()
	assert_int(runner.current_index()).is_equal(2)
	assert_array(shown).is_equal([0, 1, 2])
	assert_bool(progress.is_completed("S-01")).is_false()


func test_last_step_completes_and_emits_once() -> void:
	var facts := FakeFacts.new()
	var progress := SpielschuleProgress.new(TEST_CFG)
	var runner: LessonRunner = auto_free(Runner.new())
	var finished: Array[String] = []
	runner.chapter_completed.connect(func(id: String) -> void: finished.append(id))
	runner.setup("S-01", facts, progress)
	runner.begin()
	for i in 5:
		runner.skip_step()
	assert_int(runner.current_index()).is_equal(5)
	facts.counters.measure += 1
	runner._process(0.21)
	runner._process(1.0)
	runner.skip_step()
	assert_array(finished).is_equal(["S-01"])
	assert_bool(progress.is_completed("S-01")).is_true()
	var reloaded := SpielschuleProgress.new(TEST_CFG)
	reloaded.load_from_disk()
	assert_bool(reloaded.is_completed("S-01")).is_true()


func test_empty_chapter_never_completes() -> void:
	var facts := FakeFacts.new()
	var progress := SpielschuleProgress.new(TEST_CFG)
	var runner: LessonRunner = auto_free(Runner.new())
	var finished: Array[String] = []
	runner.chapter_completed.connect(func(id: String) -> void: finished.append(id))
	runner.setup("S-99", facts, progress)
	runner.begin()
	runner._process(1.0)
	runner.skip_step()
	assert_int(runner.total()).is_equal(0)
	assert_array(finished).is_empty()
	assert_bool(progress.is_completed("S-99")).is_false()
