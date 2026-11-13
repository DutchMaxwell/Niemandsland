extends GdUnitTestSuite
## A file load holds the restore lock, so the periodic autosave never snapshots a half-rebuilt table. load_game
## used to clear the table and rebuild it over several frames (it yields after every restored object) without the
## lock the other restore paths take, and the autosave gate only reads that lock: a timer tick mid-load wrote the
## partial table into a recovery slot. Through the real load_game and the real AutosaveController timer path.

const ObjectManagerScript = preload("res://scripts/object_manager.gd")
const SAVE_PATH := "user://save_load_restore_lock_test.nml"
const MODELS := 4

var _om: Node3D
var _sm: SaveManager
var _autosave: AutosaveController
var _autosaved: Array = []
var _load_results: Array = []
var _scratch: Array = []


func before_test() -> void:
	_autosaved = []
	_load_results = []
	_scratch = [SAVE_PATH]
	_om = auto_free(ObjectManagerScript.new())
	add_child(_om)
	_sm = auto_free(SaveManager.new())
	add_child(_sm)
	_sm.object_manager = _om
	for i in MODELS:
		_om.spawn_miniature(Vector3(0.1 * i, 0.0, 0.2), false, 10 + i)
	assert_int(_sm.save_game(SAVE_PATH)).is_equal(OK)
	_autosave = auto_free(AutosaveController.new())
	add_child(_autosave)
	_autosave.setup(_sm, null, _om, null)
	_autosave.autosaved.connect(func(path: String) -> void: _autosaved.append(path))


func after_test() -> void:
	for path: String in _scratch + _autosaved:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path) if path.begins_with("user://") else path)


## Start load_game without awaiting it; its result lands in _load_results when it returns.
func _start_load(path: String) -> void:
	var run := func() -> void: _load_results.append(await _sm.load_game(path))
	run.call()


func _await_load(max_frames: int = 120) -> void:
	for _i in max_frames:
		if not _load_results.is_empty():
			return
		await get_tree().process_frame


func _selectables() -> int:
	return _om.get_children().filter(func(c: Node) -> bool:
		return c.is_in_group("selectable") and not c.is_queued_for_deletion()).size()


func test_an_autosave_tick_mid_load_does_not_snapshot_the_partial_table() -> void:
	var lock_at_completed: Array = []
	_sm.load_completed.connect(func(_count: int) -> void: lock_at_completed.append(_sm.is_restore_in_flight()))
	_start_load(SAVE_PATH)
	await get_tree().process_frame   # the old table is freed; the load is between two restored objects
	var restored := _selectables()
	assert_bool(_load_results.is_empty()).override_failure_message("the load finished before the tick").is_true()
	assert_bool(restored > 0 and restored < MODELS) \
		.override_failure_message("not mid-load: %d of %d models on the table" % [restored, MODELS]).is_true()
	_autosave._on_timer_tick()
	assert_array(_autosaved).override_failure_message(
		"the timer autosaved a half-restored table (%d of %d models) into %s" % [restored, MODELS, _autosaved]) \
		.is_empty()
	await _await_load()
	assert_array(_load_results).is_equal([OK])
	assert_bool(_sm.is_restore_in_flight()).override_failure_message("the load kept the restore lock").is_false()
	assert_array(lock_at_completed).override_failure_message("load_completed fired under the lock").is_equal([false])
	# Saving resumes once the load is done, and the snapshot is the whole table.
	_autosave._on_timer_tick()
	assert_int(_autosaved.size()).override_failure_message("autosave did not resume after the load").is_equal(1)
	if _autosaved.size() == 1:
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_autosaved[0]))
		assert_int((saved["objects"] as Array).size()).is_equal(MODELS)


## A refused file never takes the lock: it is refused at once even while another restore holds the lock (it does
## not queue behind it), and it leaves nothing to release.
func test_a_refused_file_never_takes_the_lock() -> void:
	var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	state["table"] = []
	var damaged := "user://save_load_restore_lock_damaged.nml"
	var f := FileAccess.open(damaged, FileAccess.WRITE)
	f.store_string(JSON.stringify(state))
	f.close()
	_scratch.append(damaged)
	var gen: int = await _sm.begin_restore()   # an army arriving from a peer holds the lock
	_start_load(damaged)
	await get_tree().process_frame
	assert_array(_load_results).override_failure_message("the damaged file waited for the lock").is_equal(
		[ERR_INVALID_DATA])
	_sm.end_restore(gen)
	assert_bool(_sm.is_restore_in_flight()).override_failure_message("the refused load kept the lock").is_false()
	_load_results = []
	_start_load(SAVE_PATH)
	await _await_load()
	assert_array(_load_results).override_failure_message("the next load never finished").is_equal([OK])
	assert_bool(_sm.is_restore_in_flight()).is_false()


## A load waits for a restore that is already running (an army arriving from a peer) instead of clearing under it.
func test_a_load_waits_for_a_running_restore() -> void:
	var gen: int = await _sm.begin_restore()
	_start_load(SAVE_PATH)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(_load_results).override_failure_message("the load ran through a held restore lock").is_empty()
	assert_int(_selectables()).override_failure_message("the load cleared the table under a running restore") \
		.is_equal(MODELS)
	_sm.end_restore(gen)
	await _await_load()
	assert_array(_load_results).is_equal([OK])
	assert_bool(_sm.is_restore_in_flight()).is_false()
