extends GdUnitTestSuite
## One-core P3 step 42c: the AI's placement carries its walked routes, and the core path writes the table's shot row.
## (1) A one-model AI unit Advances 5" past the corner of a container (x 3..6", z 0..3", walled): its route around the
## corner walks 5.0" and is accepted; the same drop with no route is checked on its chord, which climbs the corner, and
## is refused (Enforce Movement Limit on). (2) With the env-gated shot dump open, one plain AI volley writes the same row
## on the core path as on the table path.
## Real: the main scene, NmlCore, the game header's terrain, the table's volley and its shot recorder. Constructed:
## plain units, the header's board (a school world), the planner's route (`last_move_paths`), both seats AI.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const INCH := 0.0254
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 1, "rules": []}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _enforce_before: bool


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
	_enforce_before = GraphicsSettings.enforce_movement_limit
	GraphicsSettings.enforce_movement_limit = true
	CoreActivation._env = 1


func after_test() -> void:
	AiShotRecorder.close()
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	GraphicsSettings.enforce_movement_limit = _enforce_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _at(x_in: float, z_in: float) -> Vector3:
	return Vector3(x_in, 0.0, z_in) * INCH


## The AI unit at S Advances to E (and shoots "Def"); `route` = the planner's walked path, or [] for none. The board is
## captured with the unit at S, as the AI body does. Returns run_ai's answer and the refusal count it added.
func _advance(att: GameUnit, def: GameUnit, route: Array) -> Array:
	var m: ModelInstance = att.models[0]
	m.node.global_position = _at(2.0, 1.4)
	var h := CoreActivation.capture(_main)
	m.node.global_position = _at(5.4, -2.0)
	_main.solo_controller.last_move_paths = [] if route.is_empty() else [{"model": m, "path": route, "radius_m": 0.0125}]
	var refused := CoreActivation.ai_refusals
	var ok: bool = await CoreActivation.run_ai(_main, att, {"action": AiDecision.Action.ADVANCE, "moved": true}, def, h)
	_main.solo_controller._core_node_ready().release(h)
	return [ok, CoreActivation.ai_refusals - refused]


## RED: `run_ai` without the routes -> the walked case is checked on its chord too and refused.
func test_a_route_around_a_container_is_accepted_and_its_chord_refused() -> void:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 1, "x_in": 2.0}), RIFLE)
	var def := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 1, "x_in": 25.0}), RIFLE)
	var sc: SoloController = _main.solo_controller
	var state := BattleSim.capture(_main.opr_army_manager, sc.objectives_provider, sc.objective_owner_of, 1, 4,
		sc.majority_in_cover, sc._has_los, sc.terrain_type_at, int(sc.ai_slot))
	var walls: Array = [[3, 0, 6, 0], [6, 0, 6, 3], [6, 3, 3, 3], [3, 3, 3, 0]].map(func(w: Array) -> Array:
		return [[w[0] * INCH, w[1] * INCH], [w[2] * INCH, w[3] * INCH]])
	var board := {"cells": {Vector2i(16, 15): TerrainRules.TerrainType.CONTAINER}, "walls": walls}
	assert_bool(sc._core_node_ready().set_game_header(AiActRecorder._header_line(state, Callable(), board))).is_true()
	sc._core_header_done = true
	var chord := await _advance(att, def, [])   # first: a refusal throws no die, so the walked case shoots the same board
	var walked := await _advance(att, def, [_at(2.0, 1.4), _at(2.8, -0.2), _at(5.4, -2.0)])
	assert_array(walked).override_failure_message("the route around the corner: %s" % [walked]).is_equal([true, 0])
	assert_array(chord).override_failure_message("the chord over the corner: %s" % [chord]).is_equal([false, 1])


## RED: the core path without its `_solo_record_shot` call -> one row, the table's only.
func test_the_core_path_writes_the_tables_shot_row() -> void:
	var path := OS.get_user_data_dir().path_join("one_core_42c_shots.jsonl")
	AiShotRecorder._checked = true
	AiShotRecorder._stream = FileAccess.open(path, FileAccess.WRITE)
	for core in [false, true]:
		var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 5, "x_in": 0.0}),
			RIFLE.merged({"count": 5}, true))
		var def := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 5, "x_in": 12.0}),
			RIFLE.merged({"count": 5}, true))
		_main.seed_tray_rng(3)
		_main._solo_core_ai_h = CoreActivation.capture(_main) if core else 0
		await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
		CoreActivation.reset_all(_main)   # releases the capture (step 42c)
		for u in [att, def]:
			_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
			for m in (u as GameUnit).models:
				(m as ModelInstance).node.free()
	AiShotRecorder.close()
	var rows: Array = FileAccess.get_file_as_string(path).split("\n", false)
	DirAccess.remove_absolute(path)
	assert_int(rows.size()).override_failure_message("rows: %s" % [rows]).is_equal(2)
	if rows.size() == 2:
		assert_str(rows[1]).override_failure_message("table %s\ncore  %s" % rows).is_equal(rows[0])
