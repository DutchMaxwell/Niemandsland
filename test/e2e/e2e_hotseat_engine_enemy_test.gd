extends GdUnitTestSuite
## RULES_AUTOMATION_PLAN step 2.3 "Enemy under the engine": on a local table with the switch on
## Automatic, each human army is an enemy the engine may resolve against — so BOTH players get the
## Shoot/Fight/Cast/Pass entries (availability only; the resolution needs a controller without an AI
## side, step 2.4). Manual (or no switch) keeps today's manual-only table. Solo vs NACHTMAHR is
## unchanged: an AI-designated slot always counts as an enemy under the engine.
##
## Real: scenes/main.tscn, the real radial gate solo_combat_available / solo_auto_available.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _register(pid: int, unit_name: String, at: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [at, at + Vector3(0.03, 0.0, 0.0)])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _set_level(level: int) -> void:
	_main.opr_army_manager.rules_automation = level


func test_automatic_gives_both_human_armies_the_combat_entries(timeout := 120000) -> void:
	var p1 := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p2 := _register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	assert_bool(_main.solo_ai_slots.is_empty()) \
		.override_failure_message("fixture: a plain local table carries no designation").is_true()
	_set_level(RulesAutomation.Level.AUTOMATIC)
	assert_bool(_main._engine_enemy(p1, p2)) \
		.override_failure_message("step 2.3 — the other human is not an enemy under the engine yet") \
		.is_true()
	assert_bool(_main._engine_enemy(p2, p1)).is_true()
	assert_bool(_main.solo_combat_available(p1)).is_true()
	assert_bool(_main.solo_combat_available(p2)).is_true()
	# The engine-executed MOVE verbs still need a controller without an AI side (step 2.4).
	assert_bool(_main.solo_auto_available(p1)).is_false()
	# Offline the hover line follows the same predicate (its online disjunct is pinned by
	# e2e_mp_los_line_test).
	assert_bool(_main._solo_hover_enemy(p1, p2)).is_true()


func test_manual_gives_neither_army_a_combat_entry(timeout := 120000) -> void:
	var p1 := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p2 := _register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	_set_level(RulesAutomation.Level.MANUAL)
	assert_bool(_main._engine_enemy(p1, p2)).is_false()
	assert_bool(_main.solo_combat_available(p1)).is_false()
	assert_bool(_main.solo_combat_available(p2)).is_false()
	assert_bool(_main._solo_hover_enemy(p1, p2)).is_false()


func test_solo_with_an_ai_slot_is_unchanged(timeout := 120000) -> void:
	var p1 := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p2 := _register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	_main.solo_ai_slots = {2: true}
	_set_level(RulesAutomation.Level.MANUAL)   # solo is always Automatic via effective()
	assert_bool(_main._engine_enemy(p1, p2)).is_true()
	assert_bool(_main.solo_combat_available(p1)).is_true()
	# The AI's own units are engine-controlled: the human gets no combat entry ON them.
	assert_bool(_main.solo_combat_available(p2)).is_false()


func test_an_own_slot_is_never_an_engine_enemy(timeout := 120000) -> void:
	var p1 := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	_set_level(RulesAutomation.Level.AUTOMATIC)
	assert_bool(_main._engine_enemy(p1, p1)).is_false()