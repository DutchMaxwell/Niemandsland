extends GdUnitTestSuite
## EPOCH_94_PARITY_BATCH (94): WHICH models a volley kills, not only how many, through the core door. One plain AI volley
## through `_run_ai_shooting`, seed for seed through the core path (a board capture as the AI body takes it): the foe's
## surviving slots are pinned to the values read on main. The foe stands in a symmetric line (the shape of a rank-and-file unit in miniature),
## where mirror models tie by rounding only: the table measures the distance to the centroid as an f32 `Vector2.length()` and
## sorts stably, the core's old f64 hypot parted the pairs the other way, so the door left another model standing when a volley
## killed all but one or two (cast door probe, 20.11.: a spell, then this volley case). The shadow and the soaks compared counts
## and a wounds multiset, so they never saw it. The gate: the epoch is a header knob (`AiActRecorder.rules_epoch`).
## Real: the main scene, NmlCore, the table's volley and landing code. Constructed: plain units (14 rifles vs a line of six).
## PLAN_FIRST_DELETION 34 FT-C1: the table arm left before step 31 (the AI table resolver retires); door values are pinned as literals read on main af5c83610.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
## The door's slots per seed at epoch 94, read on main (where the table still shoots and equals the door).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_SLOTS_94 := [[[0, false, 0], [1, false, 0], [2, false, 0], [3, false, 0], [4, false, 0], [5, false, 0]],
	[[0, false, 0], [1, false, 0], [2, true, 1], [3, true, 1], [4, false, 0], [5, false, 0]],
	[[0, false, 0], [1, false, 0], [2, true, 1], [3, true, 1], [4, false, 0], [5, false, 0]],
	[[0, false, 0], [1, false, 0], [2, true, 1], [3, true, 1], [4, false, 0], [5, false, 0]],
	[[0, false, 0], [1, true, 1], [2, true, 1], [3, true, 1], [4, true, 1], [5, false, 0]],
	[[0, false, 0], [1, false, 0], [2, true, 1], [3, true, 1], [4, false, 0], [5, false, 0]],
	[[0, false, 0], [1, false, 0], [2, false, 0], [3, false, 0], [4, false, 0], [5, false, 0]],
	[[0, false, 0], [1, false, 0], [2, false, 0], [3, true, 1], [4, false, 0], [5, false, 0]],
	[[0, false, 0], [1, true, 1], [2, true, 1], [3, true, 1], [4, true, 1], [5, true, 1]],
	[[0, false, 0], [1, true, 1], [2, true, 1], [3, true, 1], [4, true, 1], [5, false, 0]],
	[[0, false, 0], [1, false, 0], [2, true, 1], [3, true, 1], [4, true, 1], [5, false, 0]],
	[[0, false, 0], [1, true, 1], [2, true, 1], [3, true, 1], [4, true, 1], [5, false, 0]],
	[[0, false, 0], [1, false, 0], [2, true, 1], [3, true, 1], [4, false, 0], [5, false, 0]],
	[[0, false, 0], [1, false, 0], [2, false, 0], [3, true, 1], [4, false, 0], [5, false, 0]],
	[[0, false, 0], [1, false, 0], [2, false, 0], [3, false, 0], [4, false, 0], [5, false, 0]],
	[[0, false, 0], [1, false, 0], [2, false, 0], [3, true, 1], [4, false, 0], [5, false, 0]]]

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
	SoloHarness.start(_main, [1, 2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	CoreActivation._env = 1


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One volley of seed `s` on fresh units (`core` = through the core): the foe's slots as [alive, wounds] per slot.
func _volley(s: int, core: bool, epoch: int) -> Array:
	AiActRecorder.rules_epoch = epoch
	_main.solo_controller._core_header_done = false   # the header carries the epoch
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 14, "x_in": 0.0}),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 14, "rules": []})
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 6, "x_in": 12.0, "z_step_in": 1.3}),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 6, "rules": []})
	_main.seed_tray_rng(s)
	_main._solo_core_ai_h = CoreActivation.capture(_main) if core else 0
	await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
	if _main._solo_core_ai_h != 0:
		_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
	_main._solo_core_ai_h = 0
	var slots: Array = (Harness._final([foe])[0] as Dictionary)["slots"]
	Harness._free_units(_main, [att, foe])
	await _main.get_tree().process_frame
	return slots


## The volley's casualties stand in the same slots through the door at 94. `kills` = seeds that left 1 or 2 of six standing
## (casualty orders beyond the first picks), so the grid is shown to reach the tie.
func test_a_volley_kills_the_same_models_through_the_door(timeout := 600000) -> void:
	var deep := 0
	var bad: Array = []
	for s in 16:
		var door := await _volley(s, true, 94)
		deep += 1 if door.filter(func(e: Array) -> bool: return bool(e[1])).size() <= 2 else 0
		if door != WANT_SLOTS_94[s]:
			bad.append("seed %d\n want %s\n door %s" % [s, str(WANT_SLOTS_94[s]), str(door)])
	print("CASUALTY_SLOTS seeds=16 deep_kills=%d" % deep)
	# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
	assert_int(deep).override_failure_message("no seed killed four or five of six: the test proved nothing").is_equal(11)
	assert_array(bad).override_failure_message("\n".join(bad.slice(0, 3))).is_empty()
