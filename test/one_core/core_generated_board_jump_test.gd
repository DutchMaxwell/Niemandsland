extends GdUnitTestSuite
## Plan step 27-pre P3: on a generated board (from EPOCH_106_CORE_TIERS the core sees its ledges), a player's skirmish
## model that drops off a ledge in its open activation is rolled ONCE - by the core, when the activation resolves. Its drop
## check lists the jump (the session's `core_jump`), so the table's own jump branch stands aside. One run observes both
## halves: the table's line ("<unit> jumps ...") and the core's ("Jump: <unit> model 1 jumps down ...").
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
func test_a_jump_the_core_sees_is_rolled_once(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_106_CORE_TIERS
	var core: Object = ClassDB.instantiate("NmlCore")
	var layout: Dictionary = core.boardgen_layout_themed(7, "")
	SoloHarness.generated_board(_main, 7, "")   # main's test-only door: the drawn board, the class never named here
	var ledge := _ledge(layout)
	assert_array(ledge).override_failure_message("seed 7 has a 6 in ledge without a ladder").is_not_empty()
	var att := ParityTable._make_unit(_main, {"player": 1, "name": "Leaper", "models": 1, "x_in": 0.0, "z_step_in": 1.0,
		"quality": 4, "defense": 4, "tough": 1, "game_system": "gff", "faction_folder": "robot_legions", "rules": []},
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 1, "rules": []})   # a weapon = an OPR profile: the core move path
	var node: Node3D = (att.models[0] as ModelInstance).node
	node.global_position = ledge[0]
	CoreActivation._env = 1
	assert_bool(_main.core_activation_start(att)).override_failure_message("no Start").is_true()
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	var from: Vector3 = node.global_position
	node.global_position = ledge[1]
	att.unit_properties["moved_round"] = 1
	assert_bool(_main.attacked_unit_drag_refused(att, 3.0)).override_failure_message("the drop was refused").is_false()
	assert_bool(CoreActivation.core_sees_jump(att.unit_id)).override_failure_message("the core lists the jump").is_true()
	await SoloHarness.drop(_main, [{"node": node, "inches": 3.0, "from_raw": from,
		"path": PackedVector2Array([Vector2(from.x, from.z), Vector2(ledge[1].x, ledge[1].z)])}])
	await CoreActivation.end(_main, att)
	_main.battle_log.entry_added.disconnect(tap)
	var table := lines.filter(func(l: String) -> bool: return l.begins_with("Leaper jumps "))
	var by_core := lines.filter(func(l: String) -> bool: return l.begins_with("Jump: Leaper model 1 jumps down"))
	assert_array(by_core).override_failure_message("the core rolls the jump: %s" % [lines]).has_size(1)
	assert_array(table).override_failure_message("the table rolled it too: %s" % [lines]).is_empty()
