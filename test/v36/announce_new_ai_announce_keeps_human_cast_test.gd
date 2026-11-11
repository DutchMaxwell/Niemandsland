extends GdUnitTestSuite
## `_solo_show_attack_announce` used to clear the one live announce set at its top, so an announce that
## STARTS while a human cast is on the table (the human cast is a detached coroutine) deleted the rings and
## the attack line of the player's running cast. The human's set is now held apart from the AI's: a new AI
## announce leaves it alone, the human resolver's own cleanup frees it, and the AI's stray-set rule (a new AI
## announce replaces an abandoned AI set) stays. The first case starts an AI announce from inside a real
## `_run_human_cast` and checks both sets and both cleanups; the others are the controls and the mirror image.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
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


func _alive(n: Variant) -> bool:
	return not _gone_or_queued(n)


## Runs a human Bolt; on the "needs N+" line (logged right after its announce markers went live) an AI
## announce starts. Returns what was seen at that moment and once the cast is done.
func _cast_with_ai_announce_mid_flight(seer: GameUnit, ai_shooter: GameUnit) -> Dictionary:
	var seen := {"human": [], "ai": [], "fired": false, "done": false, "ai_shooter": ai_shooter,
		"human_hit": [], "ai_alive_at_start": false, "ai_alive_after_cast": false}
	_main.battle_log.entry_added.connect(_on_cast_line.bind(seen, seer))
	_run_cast(seer, ai_shooter, seen)
	await _wait(func() -> bool: return seen["done"])
	return seen


func _run_cast(seer: GameUnit, target: GameUnit, seen: Dictionary) -> void:
	await _main._run_human_cast(seer, seer, {"name": "Bolt", "threshold": 1}, [target])
	seen["ai_alive_after_cast"] = (seen["ai"] as Array).all(_alive) and not (seen["ai"] as Array).is_empty()
	seen["done"] = true


func _on_cast_line(entry: Dictionary, seen: Dictionary, seer: GameUnit) -> void:
	if seen["fired"] or not str(entry.get("text", "")).contains("— needs "):
		return
	seen["fired"] = true
	seen["human"] = (_main._solo_live_announce_human as Array).duplicate()
	seen["ai"] = _main._solo_show_attack_announce(seen["ai_shooter"], seer, "fires at")
	seen["human_hit"] = (seen["human"] as Array).filter(_gone_or_queued)
	seen["ai_alive_at_start"] = (seen["ai"] as Array).all(_alive) and not (seen["ai"] as Array).is_empty()


func test_an_ai_announce_leaves_the_markers_of_a_running_human_cast(timeout := 120000) -> void:
	var seer := _reg(1, "Seer", 0.0, 1, ["Caster(1)"])
	var brutes := _reg(2, "Brutes", 10.0, 0, [])
	var seen := await _cast_with_ai_announce_mid_flight(seer, brutes)
	assert_bool(seen["done"]).override_failure_message("the cast never resolved").is_true()
	assert_bool(seen["fired"]).override_failure_message("fixture: the cast never reached its announce").is_true()
	assert_int((seen["human"] as Array).size()).override_failure_message(
		"fixture: the human set should hold two rings and the attack line").is_equal(3)
	assert_int((seen["ai"] as Array).size()).override_failure_message(
		"fixture: the AI set should hold two rings and the attack line").is_equal(3)
	assert_int((seen["human_hit"] as Array).size()).override_failure_message(
		"the AI's new announce deleted %d of the %d markers of the player's running cast" % [
			(seen["human_hit"] as Array).size(), (seen["human"] as Array).size()]).is_equal(0)
	assert_bool(seen["ai_alive_at_start"]).override_failure_message("the AI's own markers were not shown").is_true()
	# The cast resolved: its own cleanup freed ITS markers and left the AI's alone.
	for m in seen["human"]:
		assert_bool(_gone_or_queued(m)).override_failure_message("a human marker outlived its cast").is_true()
	assert_bool(seen["ai_alive_after_cast"]).override_failure_message(
		"the human cast's cleanup deleted the AI's markers").is_true()
	# The AI's resolver cleans its own set: nothing is left on the table or in either sweep list.
	_main._solo_clear_announce(seen["ai"])
	for m in seen["ai"]:
		assert_bool(_gone_or_queued(m)).override_failure_message("an AI marker was never cleaned").is_true()
	assert_int((_main._solo_live_announce as Array).size()).override_failure_message(
		"the AI sweep list still names a set after its cleanup").is_equal(0)
	assert_int((_main._solo_live_announce_human as Array).size()).override_failure_message(
		"the human sweep list still names a set after its cleanup").is_equal(0)
	await E2EBoot.settle(get_tree())


func test_a_second_ai_announce_still_replaces_an_abandoned_ai_set(timeout := 120000) -> void:
	var seer := _reg(1, "Seer", 0.0, 0, [])
	var brutes := _reg(2, "Brutes", 10.0, 0, [])
	var first: Array = _main._solo_show_attack_announce(brutes, seer, "fires at")
	assert_int(first.size()).override_failure_message("fixture: no markers were shown").is_equal(3)
	var second: Array = _main._solo_show_attack_announce(brutes, seer, "fires at")
	for m in first:
		assert_bool(_gone_or_queued(m)).override_failure_message(
			"the stray-set rule no longer replaces an abandoned AI set").is_true()
	for m in second:
		assert_bool(_alive(m)).override_failure_message("the new AI announce was swept at once").is_true()
	_main._solo_clear_announce(second)
	await E2EBoot.settle(get_tree())


func test_a_second_human_announce_still_replaces_an_abandoned_human_set(timeout := 120000) -> void:
	var seer := _reg(1, "Seer", 0.0, 0, [])
	var brutes := _reg(2, "Brutes", 10.0, 0, [])
	var first: Array = _main._solo_show_attack_announce(seer, brutes, "fires at")
	assert_int(first.size()).override_failure_message("fixture: no markers were shown").is_equal(3)
	var second: Array = _main._solo_show_attack_announce(seer, brutes, "fires at")
	for m in first:
		assert_bool(_gone_or_queued(m)).override_failure_message(
			"a human set an aborted path abandoned survives the next human announce").is_true()
	for m in second:
		assert_bool(_alive(m)).override_failure_message("the new human announce was swept at once").is_true()
	_main._solo_clear_announce(second)
	await E2EBoot.settle(get_tree())


func test_a_human_announce_leaves_the_markers_of_a_running_ai_attack(timeout := 120000) -> void:
	var seer := _reg(1, "Seer", 0.0, 0, [])
	var brutes := _reg(2, "Brutes", 10.0, 0, [])
	var ai_set: Array = _main._solo_show_attack_announce(brutes, seer, "fires at")
	var human_set: Array = _main._solo_show_attack_announce(seer, brutes, "fires at")
	for m in ai_set:
		assert_bool(_alive(m)).override_failure_message(
			"a human announce deleted the markers of the AI's running attack").is_true()
	_main._solo_clear_announce(human_set)
	for m in ai_set:
		assert_bool(_alive(m)).override_failure_message(
			"the human cleanup deleted the markers of the AI's running attack").is_true()
	_main._solo_clear_announce(ai_set)
	for m in ai_set + human_set:
		assert_bool(_gone_or_queued(m)).override_failure_message("a marker was never cleaned").is_true()
	await E2EBoot.settle(get_tree())
