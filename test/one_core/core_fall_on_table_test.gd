extends GdUnitTestSuite
## Plan step 27b: a core fall plays on the table. On a generated board (the core sees its ledges) a player's skirmish model
## that misses its jump falls - in the core: it lands at the foot of the drop and takes its fall wounds. The table plays
## that answer: the core lands the fall's move before its wounds (H-8, as the push), so the model stands at the foot the
## core's "Falling:" line names and the wound finds it there. Before it the table found no model at the foot and landed
## nothing (the fallen model stayed where the player dropped it, unhurt).
## Real: the main scene, NmlCore, the drawn generated board (main's test-only door), the drop door, the drop signal, End.
const INCH := 0.0254
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

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
	SoloHarness.start(_main, [2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	SoloHarness.fast(_main)
	SoloHarness.lesson_paused(_main)


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	AiActRecorder.rules_epoch = _epoch_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A 6 in ledge with no ladder: a level-2 cell (high) whose +x neighbour is level 0 (low), as [high, low] cell centres in
## world metres (the board is centred on the table), or [] when the layout has none.
func _ledge(layout: Dictionary) -> Array:
	var nx := int(layout["nx"])
	var cell := float(layout["cell_in"])
	var cells: Array = layout["cells"]
	var ladders := {}
	for c in layout["connectors"]:
		ladders[[int(c["low"]), int(c["high"])]] = true
	for i in cells.size():
		var x := i % nx
		if x + 1 >= nx or int(cells[i]["level"]) != 2 or int(cells[i + 1]["level"]) != 0 or ladders.has([i + 1, i]):
			continue
		var centre := func(k: int) -> Vector3:
			return Vector3(((k % nx) + 0.5 - nx / 2.0) * cell * INCH, 0.0, ((k / nx) + 0.5 - int(layout["nz"]) / 2.0) * cell * INCH)
		return [centre.call(i) + Vector3(0, float(layout["level_in"][2]) * INCH, 0), centre.call(i + 1)]
	return []


@warning_ignore('unused_parameter')
func test_a_core_fall_lands_at_the_foot_with_its_wounds(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_106_CORE_TIERS
	var core: Object = ClassDB.instantiate("NmlCore")
	var layout: Dictionary = core.boardgen_layout_themed(7, "")
	SoloHarness.generated_board(_main, 7, "")
	var ledge := _ledge(layout)
	var att := ParityTable._make_unit(_main, {"player": 1, "name": "Leaper", "models": 3, "x_in": 0.0, "z_step_in": 0.0,
		"quality": 4, "defense": 4, "tough": 1, "game_system": "gff", "faction_folder": "robot_legions", "rules": []},
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 3, "rules": []})
	var ms: Array = att.models
	for k in ms.size():   # three models on the high cell; the ids the core's landings name models by
		(ms[k] as ModelInstance).node.global_position = ledge[0] + Vector3(0, 0, (k - 1) * 1.2 * INCH)
		(ms[k] as ModelInstance).node.set_meta("network_id", 901 + k)
		(ms[k] as ModelInstance).node.set_meta("model_instance", ms[k])
	CoreActivation._env = 1
	assert_bool(_main.core_activation_start(att)).override_failure_message("no Start").is_true()
	_main.seed_tray_rng(0)   # seed 0: the jump misses, the fall wounds the model once - it dies (Tough 1)
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	var n0: Node3D = (ms[0] as ModelInstance).node
	var from: Vector3 = n0.global_position
	n0.global_position = ledge[1]
	att.unit_properties["moved_round"] = 1
	assert_bool(_main.attacked_unit_drag_refused(att, 3.0)).override_failure_message("the drop was refused").is_false()
	await SoloHarness.drop(_main, [{"node": n0, "inches": 3.0, "from_raw": from,
		"path": PackedVector2Array([Vector2(from.x, from.z), Vector2(ledge[1].x, ledge[1].z)])}])
	await CoreActivation.end(_main, att)
	_main.battle_log.entry_added.disconnect(tap)
	var fell: Array = lines.filter(func(l: String) -> bool: return l.begins_with("Falling: Leaper model 1 falls"))
	assert_array(fell).override_failure_message("the core's fall: %s" % [lines]).has_size(1)
	var m := RegEx.create_from_string("foot of the drop \\((-?[0-9.]+) in, (-?[0-9.]+) in\\)").search(str(fell[0]))
	assert_object(m).is_not_null()
	assert_float(n0.global_position.x / INCH).override_failure_message("at the core's foot").is_equal_approx(float(m.get_string(1)), 0.06)
	assert_float(n0.global_position.z / INCH).is_equal_approx(float(m.get_string(2)), 0.06)
	assert_bool((ms[0] as ModelInstance).is_alive).override_failure_message("its fall wound killed it").is_false()
	assert_int(att.get_alive_count()).is_equal(2)
