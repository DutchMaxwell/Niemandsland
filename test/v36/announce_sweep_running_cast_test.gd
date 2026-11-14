extends GdUnitTestSuite
## `_solo_after_activation` opens with a leak sweep of `_solo_live_announce` (rings an aborted await path
## left behind). A human cast is a DETACHED coroutine (`_run_human_cast` is never awaited), so the AI's
## reply can finish while that cast is still on the table: the sweep then queue_free()d the markers of
## the player's RUNNING cast (the rings and the attack line shown for the cast window). The first case
## fires `_solo_after_activation` from inside a real human cast, at the moment its announce is live, and
## asserts the markers survive the sweep and are still cleaned by the cast's own cleanup. The control
## keeps the original job of the sweep: a set an AI path abandoned is still swept.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	CoreActivation._env = 0   # table path: the doors run without Activate (kill-switch flow); the lifecycle is test/e2e/e2e_one_core_*
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _reg(pid: int, unit_name: String, x_in: float, tokens: int, rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x_in * INCH, 0.0, 0.0)])
	u.unit_properties["special_rules"] = rules
	u.casts_current = tokens
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _wait(cond: Callable) -> void:
	for _i in 300:
		if cond.call():
			return
		await get_tree().process_frame


func _gone_or_queued(n: Variant) -> bool:
	return not is_instance_valid(n) or (n as Node).is_queued_for_deletion()


## Runs a human Bolt, fires the sweep from inside it on the "needs N+" line (logged right after the
## announce markers went live) and returns what it saw: fired, markers, swept, done.
func _cast_with_sweep_mid_flight(seer: GameUnit, target: GameUnit) -> Dictionary:
	var seen := {"markers": [], "swept": [], "fired": false, "done": false}
	_main.battle_log.entry_added.connect(_on_cast_line.bind(seen))
	_run_cast(seer, target, seen)
	await _wait(func() -> bool: return seen["done"])
	return seen


func _run_cast(seer: GameUnit, target: GameUnit, seen: Dictionary) -> void:
	await _main._run_human_cast(seer, seer, {"name": "Bolt", "threshold": 1}, [target])
	seen["done"] = true


func _on_cast_line(entry: Dictionary, seen: Dictionary) -> void:
	if seen["fired"] or not str(entry.get("text", "")).contains("— needs "):
		return
	seen["fired"] = true
	seen["markers"] = (_main._solo_live_announce_human as Array).duplicate()
	_main._solo_after_activation()
	seen["swept"] = (seen["markers"] as Array).filter(_gone_or_queued)


func test_the_sweep_leaves_the_markers_of_a_running_human_cast(timeout := 120000) -> void:
	var seer := _reg(1, "Seer", 0.0, 1, ["Caster(1)"])
	var brutes := _reg(2, "Brutes", 10.0, 0, [])
	var seen := await _cast_with_sweep_mid_flight(seer, brutes)
	assert_bool(seen["done"]).override_failure_message("the cast never resolved").is_true()
	assert_bool(seen["fired"]).override_failure_message("fixture: the cast never reached its announce").is_true()
	assert_int((seen["markers"] as Array).size()).override_failure_message(
		"fixture: the live announce set should hold two rings and the attack line").is_equal(3)
	assert_int((seen["swept"] as Array).size()).override_failure_message(
		"the AI's end-of-activation sweep deleted %d of the %d markers of the player's running cast" % [
			(seen["swept"] as Array).size(), (seen["markers"] as Array).size()]).is_equal(0)
	# The cast's own cleanup still takes the markers off the table when it resolves.
	await E2EBoot.settle(get_tree())
	for m in seen["markers"]:
		assert_bool(_gone_or_queued(m)).override_failure_message(
			"a marker outlived the cast that owned it").is_true()


func test_the_sweep_still_takes_a_set_an_ai_path_abandoned(timeout := 120000) -> void:
	var seer := _reg(1, "Seer", 0.0, 0, [])
	var brutes := _reg(2, "Brutes", 10.0, 0, [])
	var markers: Array = _main._solo_show_attack_announce(brutes, seer, "fires at")
	assert_int(markers.size()).override_failure_message("fixture: no markers were shown").is_equal(3)
	await _main._solo_after_activation()
	for m in markers:
		assert_bool(_gone_or_queued(m)).override_failure_message(
			"the leak sweep no longer clears an abandoned AI announce").is_true()
	await E2EBoot.settle(get_tree())
