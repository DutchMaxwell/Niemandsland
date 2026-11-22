extends GdUnitTestSuite
## Lane shootfix (containment): the core's Hit & Run step after a volley is the RIGID 3" translation away from an enemy that has not activated
## yet, checked against the board edge only, and the door writes its end spots back with no landing check (`CoreActivation._land_positions`).
## Measured in the gate-12 shoot soak: 3 of 17 replayed Harassing steps ended illegal (bases inside another unit, up to 0.75 in). The deny group
## `hit_and_run_landing` keeps a Hit & Run family SHOOTER on the table at the AI door until PENDING_EPOCH_HIT_AND_RUN_PLAIN goes live.
## Real: the main scene, NmlCore, the AI body, the table's Hit & Run step, the live deny slice. Constructed: a gf Dark Elf Raiders Harassing unit,
## an enemy column to shoot at, and a friendly column (already activated) standing exactly 3" behind the shooter, where the rigid kite lands.
## Each case runs twice: on the LIVE slice (the core does not take the activation, no base ends inside the friendly column) and on the same
## deny file WITHOUT the group (the control: the core takes it and lands the shooter inside the column, so the count can fail).
## RED: drop the group from assets/solo/core_slice_deny.json -> the live leg reads `ai_runs` 1 and overlapping bases.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "dark_elf_raiders", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []}
const GROUP := "hit_and_run_landing"
const WITHOUT := "user://core_hit_and_run_without_group.json"
const SEEDS := [0, 1, 2, 3]
const SHOOTER_X := -10.0
## Where the rigid kite puts the shooter: 3" straight away from the enemy column (on +x, same z), so the friendly column stands right there.
const BLOCK_X := SHOOTER_X - 3.0

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
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_fast = true
	_main._solo_auto_saves = true
	_main._autosave_controller.set_lesson_paused(true)
	CoreActivation._env = 1
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()


func after_test() -> void:
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()
	if FileAccess.file_exists(WITHOUT):
		DirAccess.remove_absolute(WITHOUT)
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## The production deny file without the group, through the test seam (the control leg).
func _without_group() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CoreSlice.DENY_PATH))
	(data["groups"] as Dictionary).erase(GROUP)
	var f := FileAccess.open(WITHOUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	CoreSlice.path_override = WITHOUT
	CoreSlice.reset_cache()


func _free(units: Array) -> void:
	for u in units:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()
	_main.solo_controller._peeked_unit = null


## How many (shooter model, column model) pairs overlap by more than 0.01 in after the activation.
func _overlaps(a: GameUnit, b: GameUnit) -> int:
	var n := 0
	for ma in a.get_alive_models():
		for mb in b.get_alive_models():
			var pa: Vector3 = (ma as ModelInstance).node.global_position
			var pb: Vector3 = (mb as ModelInstance).node.global_position
			var gap := Vector2(pa.x - pb.x, pa.z - pb.z).length() - SoloController.model_base_radius_m(ma) - SoloController.model_base_radius_m(mb)
			if gap < -0.01 * ParityTable.INCH:
				n += 1
	return n


## One AI activation of the Harassing shooter per seed. Returns per-seed rows [ai_runs, overlapping pairs, shooter centre x in inches].
func _ai_runs() -> Array:
	var rows: Array = []
	for s in SEEDS:
		CoreActivation.ai_runs = 0
		var ai := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Raiders%d" % s, "models": 5, "x_in": SHOOTER_X,
			"rules": ["Harassing"]}, true), RIFLE)
		var block := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Column%d" % s, "models": 5, "x_in": BLOCK_X}), {})
		block.is_activated = true
		var hu := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Humans%d" % s, "models": 5, "x_in": 8.0}), RIFLE)
		_main.opr_army_manager.current_round = 1
		_main.seed_tray_rng(s)
		await _main._solo_activate_one_ai()
		rows.append([CoreActivation.ai_runs, _overlaps(ai, block), _main.solo_controller.unit_centre(ai).x / ParityTable.INCH])
		_free([ai, block, hu])
	return rows


@warning_ignore('unused_parameter')
func test_the_ai_door_leaves_a_harassing_shooter_on_the_table(timeout := 600000, do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "no NmlCore") -> void:
	var live := await _ai_runs()
	for s in live.size():
		assert_int(int(live[s][0])).override_failure_message("seed %d: the core does not take a Harassing shooter (rows %s)" % [s, live]).is_equal(0)
		assert_int(int(live[s][1])).override_failure_message("seed %d: no base ends inside the friendly column (rows %s)" % [s, live]).is_equal(0)
	_without_group()
	var control := await _ai_runs()
	for s in control.size():
		assert_int(int(control[s][0])).override_failure_message("control seed %d: the core took the activation (rows %s)" % [s, control]).is_equal(1)
	# The first activation of the scene advances before it shoots (its kite then lands clear of the column); every later one holds and shoots.
	var inside := control.filter(func(r: Array) -> bool: return int(r[1]) > 0).size()
	assert_int(inside).override_failure_message("control: the rigid kite lands inside the column (rows %s)" % [control]).is_greater_equal(SEEDS.size() - 1)
