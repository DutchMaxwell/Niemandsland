extends GdUnitTestSuite
## EXIT FREEZE (maintainer field-test 20:07): pressing End Battle while a solo/hotseat prompt is
## pending used to wedge the whole process — the window ignored everything, SIGTERM did nothing, only
## SIGKILL died, and the log filled with `Parameter "data.tree" is null / at: get_tree` at ~9.5k
## lines/s.
##
## THE MECHANISM. `_on_end_battle_confirmed` calls `change_scene_to_file`, which detaches Main. Every
## prompt is a `while <cond>: await get_tree().process_frame` loop. Once Main has left the tree,
## `get_tree()` returns null and `await null` does NOT yield — so the loop resumes, spins, and never
## returns, eating the SceneTree's process_frame emission. The main loop is frozen; no Timer (not
## even gdUnit's own test timeout) can fire again.
##
## THIS SUITE proves the loop RETURNS and the engine keeps processing after the table leaves the tree.
## A WATCHDOG THREAD bounds a regression: a frozen main loop cannot enforce gdUnit's Timer-based
## timeout, so if no process frame arrives for STALL_MS the watchdog kills this process — CI then
## fails fast (gdUnit never prints its summary) instead of hanging the shard for hours. On the fixed
## build the watchdog never fires. Mirrors the in-house precedent: prompt_card.gd:83 already guards
## `while _outcome.is_empty() and is_inside_tree()`.
##
## Real: scenes/main.tscn, the real `_solo_board_prompt` raise + wait loop, the real detach a scene
## change performs.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
## No process frame for this long while a prompt is pending == the busy-loop freeze (a healthy build
## advances hundreds of frames per second).
const STALL_MS := 30000

var _runner: GdUnitSceneRunner
var _main: Node
var _parent: Node
var _root_before: Array
var _alive: Array = [false]
var _watchdog: Thread


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = false   # _solo_board_prompt answers 0 immediately in batch mode


func after_test() -> void:
	_stop_watchdog()
	if _main != null and is_instance_valid(_main) and not _main.is_inside_tree() and is_instance_valid(_parent):
		_parent.add_child(_main)   # hand it back so the runner's teardown frees it normally
	_main = null
	_parent = null
	_runner = null
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


func _start_watchdog() -> void:
	_alive = [true]
	_watchdog = Thread.new()
	_watchdog.start(_watchdog_body)


func _stop_watchdog() -> void:
	if _watchdog == null:
		return
	_alive[0] = false
	if _watchdog.is_started():
		_watchdog.wait_to_finish()
	_watchdog = null


## Runs on its own OS thread, so it keeps ticking while the main loop is wedged. A pure frame-stall
## (the process_frame emission never completing) is the freeze signature.
func _watchdog_body() -> void:
	var last := Engine.get_process_frames()
	var frozen_ms := 0
	while _alive[0]:
		OS.delay_msec(50)
		var now := Engine.get_process_frames()
		if now == last:
			frozen_ms += 50
			if frozen_ms >= STALL_MS:
				printerr("EXIT-FREEZE: main loop wedged for %d ms with a prompt pending — the wait loop is spinning after detach" % frozen_ms)
				OS.kill(OS.get_process_id())
				return
		else:
			frozen_ms = 0
			last = now


func test_a_pending_prompt_loop_returns_when_the_table_leaves_the_tree(timeout := 120000) -> void:
	var out: Array = []
	(func() -> void: out.append(await _main._solo_board_prompt("Waiting…", "Yes", "No"))).call()
	await _runner.simulate_frames(2)
	assert_array(out).override_failure_message("the board prompt must still be pending before the leave").is_empty()

	_start_watchdog()
	var frames_before: int = Engine.get_process_frames()
	# What `change_scene_to_file` does to Main this frame: drop it from the tree. Its pending wait
	# loop resumes on the next process_frame with get_tree() == null.
	_parent = _main.get_parent()
	_parent.remove_child(_main)
	assert_bool(_main.is_inside_tree()).override_failure_message("the leave did not detach Main").is_false()

	# Nobody can answer a prompt on a table that has left the tree: the loop must give up and the
	# engine must keep ticking. Bounded so a pathological hang is caught by the watchdog, not this loop.
	for _i in 240:
		if not out.is_empty():
			break
		await get_tree().process_frame
	_stop_watchdog()

	assert_int(Engine.get_process_frames() - frames_before) \
		.override_failure_message("the engine froze — no process frames advanced after the table left the tree") \
		.is_greater(0)
	assert_array(out) \
		.override_failure_message("the prompt loop did not return after the table left the tree") \
		.is_not_empty()
