extends GdUnitTestSuite
## Nightly soak "Fault — blip" (state not converged: host minis=10, guest minis=15/16). A guest joins, the
## host's join state (10 minis) is still being applied — _deserialize_objects yields a frame per object —
## when the relay link drops. main._on_relay_connection_lost calls save_manager.reset_restore_lock() so an
## ABANDONED restore cannot deadlock the re-sync. But that restore is not abandoned: it only awaits frames
## and resumes, while the post-reconnect state sync takes the released lock, clears the table and loads
## its own 10. Both keep spawning -> duplicate minis the host never had.
## Drives the REAL main._rpc_sync_game_state twice with the lock reset in between (what the drop does),
## over main.tscn, and counts the "miniature" group — the soak harness's own count.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const MINIS := 10

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _done := 0


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_done = 0


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _state() -> Dictionary:
	var objects: Array = []
	for i in MINIS:
		objects.append({"type": "miniature", "position": [-0.4 + 0.08 * i, 0.0, 0.0], "rotation": [0, 0, 0],
			"network_id": 5000 + i})
	return {"_host_version": _main.network_manager.get_game_version(), "objects": objects, "game_units": [],
		"table": {}, "object_counter": MINIS, "game_state": {}}


func _apply(state: Dictionary) -> void:
	await _main._rpc_sync_game_state(state)
	_done += 1


func _minis() -> int:
	var n := 0
	for m in get_tree().get_nodes_in_group("miniature"):
		if is_instance_valid(m) and not (m as Node).is_queued_for_deletion():
			n += 1
	return n


func test_a_drop_mid_join_load_leaves_the_host_s_minis_exactly_once(timeout := 120000) -> void:
	_apply(_state())                        # the join sync, still yielding per object
	await _runner.simulate_frames(3)
	assert_int(_done).override_failure_message("fixture: the first sync must still be in flight").is_equal(0)
	_main.save_manager.reset_restore_lock()   # what _on_relay_connection_lost does on the blip
	_apply(_state())                        # the post-reconnect re-sync
	for _i in 200:
		if _done >= 2:
			break
		await _runner.simulate_frames(1)
	await _runner.simulate_frames(3)          # let queue_free land
	assert_int(_minis()) \
		.override_failure_message("blip mid-join: the guest holds %d minis for the host's %d — the superseded join sync kept spawning after the re-sync cleared the table" % [_minis(), MINIS]) \
		.is_equal(MINIS)


func test_without_a_drop_two_syncs_still_converge(timeout := 120000) -> void:
	# CONTROL: the host's double state push per join, no drop — the lock serializes them (green before and after).
	_apply(_state())
	_apply(_state())
	for _i in 200:
		if _done >= 2:
			break
		await _runner.simulate_frames(1)
	await _runner.simulate_frames(3)
	assert_int(_minis()).is_equal(MINIS)
