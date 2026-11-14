extends GdUnitTestSuite
## One-core P3 step 38b: the core's human volley shows what the table's shows. One plain human volley through
## `_run_human_shooting` (the table) and through `CoreActivation.human_shoot` (flag on, the activation started), seed for
## seed: a recording combat stage sees the same calls in the same order - the stage's headline, each beat's title with
## the lines it closes, the toast on screen, the live announce markers and the tracer cues drawn so far, and the close.
## Real: the main scene, NmlCore, the table's volley, tracer, strip and stage code. Constructed: plain units (10 or 1
## rifles vs 5), a human attacker against the AI's unit (no save card waits), the stage forced on with no hold.

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
		# The Declaration beat's lines are step 39's: the table's human volley prints its models-in-sight line there, the
		# core says "<Unit> fires at <Target>" (the AI table's announce line). Every other beat's lines must be equal.
		calls.append("phase %s | announce %d+%d | cues %d | toast %s | lines %s" % [title,
			(main._solo_live_announce as Array).size(), (main._solo_live_announce_human as Array).size(),
			int(main._vfx_seq) - cues0, toast, "-" if title == "Declaration" else " / ".join(_pending)])
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
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	_main._solo_auto_saves = true
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


## One human volley of seed `s` on fresh units; `core` = through the core (the activation started first). Returns the calls.
func _volley(s: int, core: bool) -> Array:
	var n := 10 if s % 2 == 0 else 1   # one rifle misses now and then: a weapon beat with no saves
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Att", "models": n, "x_in": 0.0}),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": n, "rules": []})
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Def", "models": 5, "x_in": 12.0}),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []})   # a plain target carries a profile
	if core:
		assert_bool(CoreActivation.open_session(_main, att)).is_true()
	_main.seed_tray_rng(s)
	_rec.calls.clear()
	if core:
		assert_bool(await CoreActivation.human_shoot(_main, att, foe)).is_true()
		CoreActivation.close_session(_main, att.unit_id)
	else:
		await _main._run_human_shooting(att, foe)
	for u in [att, foe]:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			(m as ModelInstance).node.free()
	return _rec.calls.duplicate()


## RED: the core path without the tracers (`_present_human` skips `_vfx_player_volley`) -> its beats count no cues.
func test_the_core_human_volley_shows_what_the_table_shows(timeout := 300000) -> void:
	var bad: Array = []
	var morale := 0
	var misses := 0
	for s in 12:
		var table := await _volley(s, false)
		var core := await _volley(s, true)
		morale += 1 if table.any(func(c: String) -> bool: return c.begins_with("phase Morale")) else 0
		misses += 1 if table.any(func(c: String) -> bool: return c.contains("— 0 hits")) else 0
		if table != core:
			bad.append("seed %d\n table %s\n core  %s" % [s, "\n       ".join(table), "\n       ".join(core)])
	print("ONE_CORE_HUMAN_SHOW seeds=12 morale=%d misses=%d mismatches=%d" % [morale, misses, bad.size()])
	assert_int(morale).override_failure_message("no seed reached a Morale beat").is_greater(0)
	assert_int(misses).override_failure_message("no seed missed (a weapon beat without saves)").is_greater(0)
	assert_array(bad).override_failure_message("\n".join(bad.slice(0, 3))).is_empty()
