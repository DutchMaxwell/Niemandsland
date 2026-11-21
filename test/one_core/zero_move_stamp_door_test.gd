extends GdUnitTestSuite
## PENDING_EPOCH_ZERO_MOVE_STAMP (94, soak game 23): an AI Advance the planner clamped to zero (`last_move_paths` empty) is no executed move on the table, so
## `moved_round` stays unset. The door hands the core the chain where it stands; the step API calls a placement HOLD only when it matches the HOST's models
## (`effective_kind`), so a unit with a joined hero kept its Advance and the core stamped it: `land_delta` splits ("table -1, core 1"; the soak's Skeleton
## Archers + Leader, "table 3, core 4"). One Advance volley per reading (`CoreActivation.stamp_splits`): a split at 93 (RED), none from 94; the host alone never split.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf", "faction_folder": "dark_elf_raiders", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []}
const HERO := {"player": 2, "name": "AttHero", "models": 1, "x_in": -3.0, "z_step_in": 1.2, "game_system": "gf", "faction_folder": "dark_elf_raiders", "rules": ["Hero"]}
const PENDING := 94   # acts.rs PENDING_EPOCH_ZERO_MOVE_STAMP

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main._solo_batch = true
	_main._solo_auto_saves = true
	_main._autosave_controller.set_lesson_paused(true)
	CoreActivation._env = 1
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One Advance volley of a unit that stands still (with a joined hero if `hero`), through the door at `epoch`.
func _advance(epoch: int, hero: bool) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	CoreActivation.reset_all(_main)
	CoreActivation._env = 1
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 5, "x_in": 0.0}, true), RIFLE)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 10, "x_in": 12.0, "defense": 2}, true), {})
	if hero:
		var lord := ParityTable._make_unit(_main, SIDE.merged(HERO, true), {"name": "Blade", "range_in": 0, "attacks": 2, "count": 1, "rules": []})
		lord.unit_properties["attached_to"] = att
		att.unit_properties["attached_heroes"] = [lord]
	_main.seed_tray_rng(3)
	_main._solo_core_ai_h = CoreActivation.capture(_main)   # the board before the move, as the body captures it
	_main.solo_controller.last_move_paths = []
	var dbg_h := int(_main._solo_core_ai_h)
	var runs := CoreActivation.ai_runs
	var splits := CoreActivation.stamp_splits
	await _main._run_ai_shooting({"unit": att, "moved": true, "action": AiDecision.Action.ADVANCE, "can_shoot": true})
	var plain: Dictionary = _main.solo_controller._core_node_ready().plain_of(dbg_h) if dbg_h != 0 else {}
	for k in (plain.get("units", {}) as Dictionary):
		var e := (plain["units"][k] as Dictionary)
		if str((e.get("profile", {}) as Dictionary).get("name", "")) == "Att":
			print("DBGZ core unit keys=", e.keys(), " moved_round=", e.get("moved_round"), " round=", plain.get("round"))
	var out := {"took": CoreActivation.ai_runs - runs, "splits": CoreActivation.stamp_splits - splits, "moved_round": int(att.unit_properties.get("moved_round", -1))}
	if int(_main._solo_core_ai_h) != 0:
		_main.solo_controller._core_node_ready().release(int(_main._solo_core_ai_h))
		_main._solo_core_ai_h = 0
	for u in [att, foe] + (att.unit_properties.get("attached_heroes", []) as Array):
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()
	_main.solo_controller._peeked_unit = null
	await _main.get_tree().process_frame
	return out


func test_an_advance_that_moved_nobody_leaves_no_stamp_split_from_the_pending_epoch() -> void:
	var old := await _advance(PENDING - 1, true)
	assert_int(int(old["took"])).override_failure_message("the door takes the volley: %s" % str(old)).is_equal(1)
	assert_int(int(old["splits"])).override_failure_message("epoch 93 must split (the red leg): %s" % str(old)).is_greater(0)
	var now := await _advance(PENDING, true)
	assert_int(int(now["took"])).is_equal(1)
	assert_int(int(now["splits"])).override_failure_message("epoch 94: the core stamps nothing, as the table: %s" % str(now)).is_equal(0)
	assert_int(int(now["moved_round"])).override_failure_message("and the unit is not moved").is_equal(-1)


func test_the_host_alone_never_split() -> void:
	for epoch in [PENDING - 1, PENDING]:
		var r := await _advance(epoch, false)
		assert_int(int(r["took"])).is_equal(1)
		assert_int(int(r["splits"])).override_failure_message("epoch %d: %s" % [epoch, str(r)]).is_equal(0)
