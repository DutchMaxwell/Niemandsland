extends GdUnitTestSuite
## Deletion blocker (fd-tests -> fd-door, before PLAN_FIRST_DELETION step 35): the AI door draws the volley's tracer like the
## table does. Indirect fire tests no sight line (its LOS is waived), so the table draws NO chalk tracer for it
## (e2e_volley_cue_test::test_indirect_fire_draws_no_tracer on `_solo_resolve_ai_volley`); the door drew one, because its show
## (`CoreActivation._present`) handed `_vfx_volley` a fixed `los_waived = false`.
## Real: the main scene, NmlCore, the AI body's `_run_ai_shooting` with a board captured before the activation, the live slice,
## the volley cue. Constructed: a one-model shooter 10" from a one-model target, a rifle with or without Indirect.
## RED (on main): the Indirect leg counts 1 tracer. The plain leg proves the count can be non-zero on the same path.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.5, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _preset_before: int


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [1, 2], 2)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	SoloHarness.instant(_main)
	_main.volley_cue.force_for_tests = true
	_main.volley_cue.enabled = true
	_preset_before = GraphicsSettings.current_preset
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.LOW   # still form: one line per tracer
	CoreActivation._env = 1
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()


func after_test() -> void:
	GraphicsSettings.current_preset = _preset_before
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One AI HOLD volley of a one-model rifle (`rules` on the weapon) through the door. Returns [door runs, tracers drawn].
func _volley(rules: Array) -> Array:
	CoreActivation.reset_all(_main)
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Mortars", "models": 1, "x_in": 0.0}, true),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 1, "rules": rules})
	var tgt := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Mark", "models": 1, "x_in": 10.0}, true), {})
	for c in _main.volley_cue.get_children():
		c.free()
	var runs := CoreActivation.ai_runs
	_main._solo_core_ai_h = CoreActivation.capture(_main)
	await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
	var drawn: int = _main.volley_cue.get_child_count()
	if int(_main._solo_core_ai_h) != 0:
		_main.solo_controller._core_node_ready().release(int(_main._solo_core_ai_h))
	_main._solo_core_ai_h = 0
	for u in [att, tgt]:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()
	await _main.get_tree().process_frame
	return [CoreActivation.ai_runs - runs, drawn]


@warning_ignore('unused_parameter')
func test_the_door_draws_no_tracer_for_indirect_fire(timeout := 300000, do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "no NmlCore") -> void:
	var plain := await _volley([])
	assert_int(int(plain[0])).override_failure_message("the door took the plain volley: %s" % [plain]).is_equal(1)
	assert_int(int(plain[1])).override_failure_message("a plain rifle draws its tracer on the door: %s" % [plain]).is_equal(1)
	var lobbed := await _volley(["Indirect"])
	assert_int(int(lobbed[0])).override_failure_message("the door took the Indirect volley: %s" % [lobbed]).is_equal(1)
	assert_int(int(lobbed[1])).override_failure_message("Indirect fire tests no sight line: no tracer (%s)" % [lobbed]).is_equal(0)
