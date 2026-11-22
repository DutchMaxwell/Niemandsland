extends GdUnitTestSuite
## Lane shootfix (#3394 follow-up): the table breaks an EXACT casualty-rank tie by the model's index in `unit.models`, the core by its slot
## (a stable sort). That is one order only while the core lists the LIVING models in the table's model order. Three foes of 20 models on a
## 5 x 4 grid of 0.0625 m steps (exact in f32, so the four corners tie exactly), each shot by the same plain AI volley on the table path and
## through the core door, seed for seed, the foe's slots compared:
##   grid    - all 20 alive (the soak's case);
##   revived - the four corners dead, then 0 and 19 brought back as Reanimation does it (`is_alive` and wounds restored in place, the index
##             kept): 18 living with gaps in the list, the two revived corners tying exactly (the formation stays point-symmetric);
##   joined  - a hero joined to the grid (its own unit; the volley's casualties land on the host's bodies first).
## RED (before #3394): the grid and the joined case differ on 6 of 8 seeds, the revived case on 3 of 8.
## Real: the main scene, NmlCore, the table's volley, the capture and the door's landing. Constructed: plain units.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const STEP_M := 0.0625
const SEEDS := 8

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	CoreActivation._env = 1


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## The 20-model foe on the exact grid, centred 0.4572 m (18") from the shooter line.
func _grid_foe(kind: String) -> Array:
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Grid", "models": 20, "x_in": 18.0}), {})
	for r in range(4):
		for c in range(5):
			(foe.models[r * 5 + c] as ModelInstance).node.global_position = Vector3(0.5 + (c - 2) * STEP_M, 0.0, (r - 1.5) * STEP_M)
	var extra: Array = []
	if kind == "revived":
		for i in [0, 4, 15, 19]:
			(foe.models[i] as ModelInstance).is_alive = false
			(foe.models[i] as ModelInstance).wounds_current = 0
		for i in [0, 19]:   # Reanimation's restore: the same ModelInstance, its index kept
			(foe.models[i] as ModelInstance).is_alive = true
			(foe.models[i] as ModelInstance).wounds_current = (foe.models[i] as ModelInstance).wounds_max
	elif kind == "joined":
		var hero := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Hero", "models": 1, "x_in": 21.0, "rules": ["Hero"]}, true), {})
		(hero.models[0] as ModelInstance).node.global_position = Vector3(0.5 + 3 * STEP_M, 0.0, 0.0)
		EquipmentDistributor.attach_hero_to_unit(hero, foe)
		extra.append(hero)
	return [foe] + extra


## One volley of seed `s` (`core` = through the core door): the foe's (and hero's) slots.
func _volley(s: int, core: bool, kind: String) -> Array:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 10, "x_in": 0.0}),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []})
	var foes := _grid_foe(kind)
	_main.seed_tray_rng(s)
	_main._solo_core_ai_h = CoreActivation.capture(_main) if core else 0
	await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
	if _main._solo_core_ai_h != 0:
		_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
	_main._solo_core_ai_h = 0
	var slots: Array = Harness._final(foes).map(func(d: Dictionary) -> Array: return d["slots"])
	Harness._free_units(_main, [att] + foes)
	await _main.get_tree().process_frame
	return slots


func _case(kind: String) -> void:
	var bad: Array = []
	var picks := 0
	var took := 0
	for s in SEEDS:
		var runs := CoreActivation.ai_runs
		var table := await _volley(s, false, kind)
		var door := await _volley(s, true, kind)
		took += CoreActivation.ai_runs - runs
		var dead := (table[0] as Array).filter(func(e: Array) -> bool: return not bool(e[1])).size() - (2 if kind == "revived" else 0)   # 4 and 15 stood dead before the volley
		picks += 1 if dead > 0 else 0
		if table != door:
			bad.append("%s seed %d\n table %s\n door  %s" % [kind, s, str(table), str(door)])
	print("CASUALTY_TIE_ORDER %s seeds=%d took=%d seeds_with_casualties=%d differ=%d" % [kind, SEEDS, took, picks, bad.size()])
	assert_int(took).override_failure_message("%s: the door took no volley - nothing compared" % kind).is_equal(SEEDS)
	assert_int(picks).override_failure_message("%s: no seed removed a model - the tie was never reached" % kind).is_greater(0)
	assert_array(bad).override_failure_message("\n".join(bad.slice(0, 2))).is_empty()


func test_a_full_twenty_model_grid_loses_the_same_models_through_the_door(timeout := 600000) -> void:
	await _case("grid")


func test_a_grid_with_a_revived_model_loses_the_same_models_through_the_door(timeout := 600000) -> void:
	await _case("revived")


func test_a_grid_with_a_joined_hero_loses_the_same_models_through_the_door(timeout := 600000) -> void:
	await _case("joined")
