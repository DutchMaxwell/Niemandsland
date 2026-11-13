extends GdUnitTestSuite
## One-core P3 step 42b: the core's AI volley shows what the table's shows. One plain AI volley through
## `_run_ai_shooting`, seed for seed on the table path and on the core path (flag on, a board capture as the AI body takes
## it): a recording combat stage sees the same calls in the same order - the stage's headline, each beat's title with
## the lines it closes, the toast on screen, the live announce markers and the tracer cues drawn so far, and the close.
## Real: the main scene, NmlCore, the table's volley, announce, tracer, toast and stage code. Constructed: plain units
## (10 or 1 rifles vs 5), both seats AI (no save card waits), the stage forced on with no hold.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}


## The recording stub: the real stage, every call written down with what the table shows at that moment.
class StageRec extends CombatStage:
	var main: Node
	var calls: Array = []
	var cues0 := 0

	func activation_begin(headline: String) -> void:
		cues0 = int(main._vfx_seq)
		calls.append("begin %s" % headline)
		super.activation_begin(headline)

	func phase(title: String) -> void:
		var toast: String = main._solo_toast.text if is_instance_valid(main._solo_toast) else ""
		calls.append("phase %s | announce %d | cues %d | toast %s | lines %s" % [title,
			(main._solo_live_announce as Array).size(), int(main._vfx_seq) - cues0, toast, " / ".join(_pending)])
		await super.phase(title)

	func activation_end() -> void:
		calls.append("end")
		super.activation_end()


var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _rec: StageRec


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2   # the volley's target pick scans the other seat
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	GraphicsSettings.combat_stage_hold_s = 0.0
	_rec = StageRec.new()
	_rec.main = _main
	_rec.force_for_tests = true
	_main.add_child(_rec)
	_main.combat_stage = _rec
	CoreActivation._env = 1


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	GraphicsSettings.combat_stage_hold_s = 2.5
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One volley of seed `s` on fresh units; `core` = through the core (a capture of the board first). Returns the calls.
func _volley(s: int, core: bool) -> Array:
	var n := 10 if s % 2 == 0 else 1   # one rifle misses now and then: a weapon beat with no saves
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": n, "x_in": 0.0}),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": n, "rules": []})
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 5, "x_in": 12.0}),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []})   # a plain target carries a profile
	_main.seed_tray_rng(s)
	_rec.calls.clear()
	_main._solo_core_ai_h = CoreActivation.capture(_main) if core else 0
	await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
	if _main._solo_core_ai_h != 0:
		_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
	_main._solo_core_ai_h = 0
	for u in [att, foe]:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			(m as ModelInstance).node.free()
	return _rec.calls.duplicate()


## RED: the core path without the announce (`_present` skips `_solo_show_attack_announce`) -> its Declaration beat
## shows no markers and no "Att fires at Def" toast.
func test_the_core_volley_shows_what_the_table_shows(timeout := 300000) -> void:
	var bad: Array = []
	var core_runs := CoreActivation.ai_runs
	var morale := 0
	var misses := 0
	for s in 12:
		var table := await _volley(s, false)
		var core := await _volley(s, true)
		morale += 1 if table.any(func(c: String) -> bool: return c.begins_with("phase Morale")) else 0
		misses += 1 if table.any(func(c: String) -> bool: return c.contains("— 0 hits")) else 0
		if table != core:
			bad.append("seed %d\n table %s\n core  %s" % [s, "\n       ".join(table), "\n       ".join(core)])
	print("ONE_CORE_AI_SHOW seeds=12 core=%d morale=%d misses=%d mismatches=%d" % [CoreActivation.ai_runs - core_runs,
		morale, misses, bad.size()])
	assert_int(CoreActivation.ai_runs - core_runs).override_failure_message("the core path was not taken").is_equal(12)
	assert_int(morale).override_failure_message("no seed reached a Morale beat").is_greater(0)
	assert_int(misses).override_failure_message("no seed missed (a weapon beat without saves)").is_greater(0)
	assert_array(bad).override_failure_message("\n".join(bad.slice(0, 3))).is_empty()
