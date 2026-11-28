extends GdUnitTestSuite
## Plan step 27c-4 (D-27c): a skirmish fall plays to its end through the card. On a generated board a 3-model gff unit
## drops a model off a 6 in ledge with the others standing more than 1 in away; tray seed 0 misses the jump and the
## model falls. The card's End activation refuses with one line, "Place for me" lands the core's 1 in placer, and the
## card's End then ends the activation for real: the unit is activated and the round goes on.
## Real: the main scene, NmlCore, the drawn generated board, the drop door, the unit card and its doors, the solo alternation.
const INCH := 0.0254
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const LOCK := "Place the other models within 1 in of Leaper's model that fell"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int
var _lines: Array = []


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
	_lines = []
	_main.battle_log.entry_added.connect(_tap)


func after_test() -> void:
	_main.battle_log.entry_added.disconnect(_tap)
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	AiActRecorder.rules_epoch = _epoch_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _tap(e: Dictionary) -> void:
	_lines.append(str(e["text"]))


func _count(prefix: String) -> int:
	return _lines.filter(func(l: String) -> bool: return l.begins_with(prefix)).size()


## A 6 in ledge with no ladder: [high, low] cell centres in world metres, or [] (as core_fall_on_table_test).
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


func _unit(player: int, name: String, models: int, tough: int) -> GameUnit:
	return ParityTable._make_unit(_main, {"player": player, "name": name, "models": models, "x_in": 0.0, "z_step_in": 0.0,
		"quality": 4, "defense": 4, "tough": tough, "game_system": "gff", "faction_folder": "robot_legions", "rules": []},
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": models, "rules": []})


## The presented card's visible button with `text`, or null.
func _card_button(gu: GameUnit, text: String) -> Button:
	_main.unit_dock.present_unit(gu)
	for b in _main.unit_dock.find_children("*", "Button", true, false):
		if (b as Button).text == text and (b as Button).is_visible_in_tree() and not b.is_queued_for_deletion():
			return b
	return null


## The card shows `text`, then its controller door runs (the button's own path card_face -> unit_dock._card_action -> this
## door is card_action_dispatch_test's): awaited, so no frame loop runs while the board's look rebuilds.
func _press(gu: GameUnit, text: String) -> void:
	assert_object(_card_button(gu, text)).override_failure_message("the card shows %s" % text).is_not_null()
	var radial: Node = _main.radial_menu_controller
	if text == "End activation":
		await radial.card_end_activation(gu)
	else:
		radial.card_place_for_me(gu)


@warning_ignore('unused_parameter')
func test_a_fall_is_placed_for_me_and_ends_through_the_card(
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_106_CORE_TIERS
	var core: Object = ClassDB.instantiate("NmlCore")
	SoloHarness.generated_board(_main, 7, "")
	var ledge := _ledge(core.boardgen_layout_themed(7, ""))
	var att := _unit(1, "Leaper", 3, 3)
	var idle := _unit(1, "Reserve", 1, 1)   # a second own unit keeps the round open after Leaper's End
	var foe := _unit(2, "Mark", 1, 1)
	(idle.models[0] as ModelInstance).node.global_position = ledge[1] + Vector3(-20 * INCH, 0, 0)
	(foe.models[0] as ModelInstance).node.global_position = ledge[1] + Vector3(-20 * INCH, 0, 20 * INCH)
	var ms: Array = att.models
	var spots := [Vector3(0, 0, 0), Vector3(-1.1 * INCH, 0, -0.6 * INCH), Vector3(-1.1 * INCH, 0, 0.6 * INCH)]
	for k in ms.size():
		(ms[k] as ModelInstance).node.global_position = ledge[0] + spots[k]
		(ms[k] as ModelInstance).node.set_meta("network_id", 901 + k)
		(ms[k] as ModelInstance).node.set_meta("model_instance", ms[k])
	CoreActivation._env = 1
	assert_bool(_main.core_activation_start(att)).override_failure_message("no Start").is_true()
	_main.seed_tray_rng(0)   # seed 0: model 1 misses its jump; Tough 3 lives through the fall
	var n0: Node3D = (ms[0] as ModelInstance).node
	var from: Vector3 = n0.global_position
	n0.global_position = ledge[1]
	att.unit_properties["moved_round"] = 1
	assert_bool(_main.attacked_unit_drag_refused(att, 3.0)).override_failure_message("the drop was refused").is_false()
	await SoloHarness.drop(_main, [{"node": n0, "inches": 3.0, "from_raw": from,
		"path": PackedVector2Array([Vector2(from.x, from.z), Vector2(ledge[1].x, ledge[1].z)])}])
	await _press(att, "End activation")
	assert_int(_count("Falling: Leaper model 1 falls")).override_failure_message("the core's fall: %s" % [_lines]).is_equal(1)
	assert_int(_count(LOCK)).override_failure_message("the End refuses with the line: %s" % [_lines]).is_equal(1)
	assert_bool(att.is_activated).override_failure_message("locked").is_false()
	await _press(att, "Place for me")
	assert_int(_count("Leaper: Fall: model 1 fell; model 2, model 3 placed within 1 in of it")) \
		.override_failure_message("the core's placer line: %s" % [_lines]).is_equal(1)
	var at: Vector3 = n0.global_position
	var r := SoloController.model_base_radius_m(ms[0] as ModelInstance)
	for k in [1, 2]:
		var q: Vector3 = (ms[k] as ModelInstance).node.global_position
		assert_float((Vector2(q.x, q.z).distance_to(Vector2(at.x, at.z)) - 2.0 * r) / INCH) \
			.override_failure_message("model %d within 1 in" % (k + 1)).is_less_equal(1.0 + 1e-3)
	await _press(att, "End activation")
	assert_bool(att.is_activated).override_failure_message("the card's End ends it: %s" % [_lines]).is_true()
	assert_int(_count(LOCK)).override_failure_message("no second lock").is_equal(1)
	assert_int(_count("Jump: Leaper model 1 jumps")).override_failure_message("one jump roll").is_equal(1)
	assert_int(_main.opr_army_manager.current_round).override_failure_message("the round goes on").is_equal(1)
