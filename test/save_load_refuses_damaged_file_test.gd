extends GdUnitTestSuite
## A damaged save is refused BEFORE the table is touched, through the public load_game path. load_game used to
## clear the table (on a host: broadcast that clear to every guest) and only then hand the file's sections to the
## typed restore steps, so a current-version file with a wrongly shaped section destroyed the battle it was meant
## to replace. Every case below starts from a REAL save of a populated table and damages one section of it.

const ObjectManagerScript = preload("res://scripts/object_manager.gd")
const SAVE_PATH := "user://save_load_refuses_damaged_file_test.nml"


## A host in a live session: every clear the ObjectManager broadcasts is counted.
class NetStub extends Node:
	var is_host: bool = true
	var clears: int = 0

	func is_multiplayer_active() -> bool:
		return true

	func is_any_remote_peer_busy() -> bool:
		return false

	func get_my_peer_id() -> int:
		return 1

	func broadcast_clear() -> void:
		clears += 1


var _om: Node3D
var _net: NetStub
var _sm: SaveManager
var _minis: Array = []
var _failures: Array = []
var _completed: int = 0


func before_test() -> void:
	_failures = []
	_completed = 0
	_om = auto_free(ObjectManagerScript.new())
	add_child(_om)
	_net = auto_free(NetStub.new())
	_om._network_manager = _net
	_sm = auto_free(SaveManager.new())
	add_child(_sm)
	_sm.object_manager = _om
	_sm.network_manager = _net
	_sm.load_failed.connect(func(msg: String) -> void: _failures.append(msg))
	_sm.load_completed.connect(func(_count: int) -> void: _completed += 1)
	_minis = [_om.spawn_miniature(Vector3(0.10, 0.0, 0.20), false, 7),
		_om.spawn_miniature(Vector3(-0.30, 0.0, 0.10), false, 8)]
	assert_int(_sm.save_game(SAVE_PATH)).is_equal(OK)


func after_test() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## Rewrite the real save with one section damaged by `damage` (state: Dictionary) -> void.
func _damage_save(damage: Callable) -> void:
	var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	damage.call(state)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(state))
	f.close()


func _assert_refused_and_untouched(what: String, damage: Callable) -> void:
	_damage_save(damage)
	var err: Variant = await _sm.load_game(SAVE_PATH)
	await get_tree().process_frame   # a clear frees the old table with queue_free: let it land
	assert_that(err).override_failure_message("%s: load_game returned %s, not ERR_INVALID_DATA" % [what, err]) \
		.is_equal(ERR_INVALID_DATA)
	assert_int(_net.clears).override_failure_message("%s: the host broadcast a table clear" % what).is_equal(0)
	assert_int(_failures.size()).override_failure_message("%s: no load_failed message" % what).is_equal(1)
	assert_int(_completed).override_failure_message("%s: reported a completed load" % what).is_equal(0)
	for i in _minis.size():
		var model: Variant = _minis[i]
		assert_bool(is_instance_valid(model) and not (model as Node3D).is_queued_for_deletion()) \
			.override_failure_message("%s: the table's model %d was cleared" % [what, i]).is_true()
	if is_instance_valid(_minis[0]) and is_instance_valid(_minis[1]):
		assert_vector((_minis[0] as Node3D).global_position).is_equal(Vector3(0.10, 0.0, 0.20))
		assert_vector((_minis[1] as Node3D).global_position).is_equal(Vector3(-0.30, 0.0, 0.10))


func test_a_table_that_is_a_list_is_refused_before_the_clear() -> void:
	await _assert_refused_and_untouched("table = []", func(s: Dictionary) -> void: s["table"] = [])


func test_objects_that_are_a_record_are_refused_before_the_clear() -> void:
	await _assert_refused_and_untouched("objects = {}", func(s: Dictionary) -> void: s["objects"] = {})


func test_game_units_that_are_text_are_refused_before_the_clear() -> void:
	await _assert_refused_and_untouched("game_units = text", func(s: Dictionary) -> void: s["game_units"] = "units")


func test_a_save_without_its_objects_section_is_refused_before_the_clear() -> void:
	await _assert_refused_and_untouched("no objects", func(s: Dictionary) -> void: s.erase("objects"))


func test_an_object_position_that_is_text_is_refused_before_the_clear() -> void:
	await _assert_refused_and_untouched("position = text", func(s: Dictionary) -> void:
		(s["objects"][0] as Dictionary)["position"] = "0.1, 0, 0.2")


func test_an_object_position_of_words_is_refused_before_the_clear() -> void:
	await _assert_refused_and_untouched("position = words", func(s: Dictionary) -> void:
		(s["objects"][1] as Dictionary)["position"] = ["x", "y", "z"])


func test_an_object_position_with_too_few_entries_is_refused_before_the_clear() -> void:
	await _assert_refused_and_untouched("position = two numbers", func(s: Dictionary) -> void:
		(s["objects"][0] as Dictionary)["position"] = [0.1, 0.2])


func test_an_object_counter_that_is_not_a_number_is_refused_before_the_clear() -> void:
	# int(null) aborts the restore AFTER the table was rebuilt, and load_game still returned OK.
	await _assert_refused_and_untouched("object_counter = null", func(s: Dictionary) -> void:
		s["object_counter"] = null)


func test_a_unit_whose_model_positions_are_a_record_is_refused_before_the_clear() -> void:
	await _assert_refused_and_untouched("model_positions = {}", func(s: Dictionary) -> void:
		(s["game_units"] as Array).append({"unit_id": "u1", "models": [], "model_positions": {"0": [0, 0, 0]}}))


## CONTROL: the undamaged save of the same table still loads, and the host's clear still reaches the guests.
func test_the_undamaged_save_still_loads_and_broadcasts_its_clear() -> void:
	var err: Variant = await _sm.load_game(SAVE_PATH)
	assert_that(err).override_failure_message("the undamaged save was refused: %s" % [_failures]).is_equal(OK)
	assert_int(_net.clears).is_equal(1)
	assert_int(_completed).is_equal(1)
	assert_array(_failures).is_empty()


## CONTROL: the check is not stricter than the real files: every save the game ships passes it.
func test_every_bundled_save_passes_the_payload_check() -> void:
	var paths: Array = ["res://assets/tutorial/tutorial_board.nml"]
	for name in DirAccess.get_files_at("res://assets/tutorial/scenarios"):
		if name.ends_with(".nml"):
			paths.append("res://assets/tutorial/scenarios/" + name)
	assert_int(paths.size()).is_greater(5)
	for path: String in paths:
		var state: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_bool(state is Dictionary).override_failure_message("%s does not parse" % path).is_true()
		if state is Dictionary:
			assert_str(SaveMigrations.payload_error(state)).override_failure_message(
				"%s is refused: %s" % [path, SaveMigrations.payload_error(state)]).is_empty()
