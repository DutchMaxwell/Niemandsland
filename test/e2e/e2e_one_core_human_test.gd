extends GdUnitTestSuite
## One-core P4.0-7 (D5): a human activation saved mid-way restores from its Start. (The step-39 gate that compared the core's
## human volley with the table's own left with the table's player volley.)
## Real: the main scene, NmlCore, the save manager. Constructed: plain units.

const INCH := 0.0254
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)   # tray faces from the seeded tray RNG, no physics settle
	SoloHarness.auto_saves(_main)
	SoloHarness.fast(_main)
	_main._autosave_controller.set_lesson_paused(true)   # a long run's periodic autosave would add its own log line


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## P4.0-7 (D5): a save taken mid-activation (a model moved, a casualty marked) stores the board from the activation's
## Start, and the load names the restart in ONE line. A save outside an activation carries neither (probe), and the AI
## body marks its start through the same save-manager seam (it opens no session).
func test_mid_activation_save_restores_the_activation_start(timeout := 120000) -> void:
	var att: GameUnit = ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Saver", "models": 2, "x_in": 0.0}), RIFLE)
	var foe: GameUnit = ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Foe", "models": 2, "x_in": 12.0}), RIFLE)
	for u in [att, foe]:
		_main.opr_army_manager.game_units[(u as GameUnit).unit_id] = u
	CoreActivation._env = 1
	assert_bool(_main.core_activation_start(att)).override_failure_message("fixture: no Start").is_true()
	var start: Vector3 = (att.models[0] as ModelInstance).node.global_position
	var path := "user://e2e_p407_mid_activation.nml"
	(att.models[0] as ModelInstance).node.global_position.x += 4.0 * INCH   # mid-step: the move
	(foe.models[0] as ModelInstance).node.set_meta("deleted", true)          # mid-volley: the casualty
	assert_int(_main.save_manager.save_game(path)).is_equal(OK)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var row: Dictionary = (saved["game_units"] as Array).filter(func(u: Dictionary) -> bool: return str(u["unit_id"]) == att.unit_id)[0]
	assert_float(float((row["model_positions"][0] as Dictionary)["position"][0])) \
		.override_failure_message("the save stored the moved model, not the activation start").is_equal_approx(start.x, 0.0001)
	var foe_row: Dictionary = (saved["game_units"] as Array).filter(func(u: Dictionary) -> bool: return str(u["unit_id"]) == foe.unit_id)[0]
	assert_bool((foe_row["model_positions"][0] as Dictionary).has("deleted")) \
		.override_failure_message("the save stored the mid-volley casualty").is_false()
	assert_str(str((saved["game_state"] as Dictionary).get("core_activation_restart", ""))).is_equal("Saver")
	CoreActivation.close_session(_main, att.unit_id)   # the activation ended: later saves are ordinary (probe)
	assert_int(_main.save_manager.save_game(path)).is_equal(OK)
	var plain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_bool((plain["game_state"] as Dictionary).has("core_activation_restart")) \
		.override_failure_message("a save outside an activation carried the restart marker").is_false()
	assert_that(plain["game_units"]).is_equal(JSON.parse_string(JSON.stringify(_main.save_manager._serialize_game_units())))
	_main.save_manager._deserialize_game_state(saved["game_state"])
	_main._on_load_completed(0)
	var restart_lines: int = _main.battle_log.entries().filter(func(e: Dictionary) -> bool:
		return str(e["text"]) == "Saver: the activation restarts from its start.").size()
	assert_int(restart_lines).override_failure_message("the load wrote no (or not exactly one) restart line").is_equal(1)
	assert_bool(CoreActivation.session_open(att.unit_id)).override_failure_message("the loaded activation is still open").is_false()
	_main.save_manager.note_activation_start("AiUnit")   # the AI body's start (no session)
	assert_int(_main.save_manager.save_game(path)).is_equal(OK)
	var ai: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_main.save_manager.note_activation_end()
	assert_str(str((ai["game_state"] as Dictionary).get("core_activation_restart", ""))).is_equal("AiUnit")
