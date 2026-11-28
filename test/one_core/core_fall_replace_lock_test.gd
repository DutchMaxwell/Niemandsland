extends GdUnitTestSuite
## Plan step 27c-2a (D-27c Q2): after a core fall the owner places the unit's other models within 1 in of the model that
## fell before the activation ends. The jump is rolled inside the step that the End (or the shot) drives, so the table holds
## the activation open itself: the End door refuses with one line while the core says a model stands more than 1 in off,
## never drives the core again (one jump roll), and ends once the models stand close. An AI seat never enters the state.
## Real: the main scene, NmlCore, the drawn generated board, the drop door, the radial activation door, End, the shot door.
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


## Leaper (Tough 3: the seed-0 fall wound leaves model 1 alive) on the high cell: model 1 at the edge side, models 2-3 at the
## cell's back, so after the fall they stand more than 1 in from it. Model 1 is dropped off the ledge (seed 0: it misses the
## jump). Returns the unit; `foe` adds an enemy on the low ground in rifle range.
func _fallen_leaper(foe := false) -> Array:
	AiActRecorder.rules_epoch = AiActRecorder.PENDING_EPOCH_CORE_TIERS
	var core: Object = ClassDB.instantiate("NmlCore")
	var layout: Dictionary = core.boardgen_layout_themed(7, "")
	SoloHarness.generated_board(_main, 7, "")
	var ledge := _ledge(layout)
	var att := ParityTable._make_unit(_main, {"player": 1, "name": "Leaper", "models": 3, "x_in": 0.0, "z_step_in": 0.0,
		"quality": 4, "defense": 4, "tough": 3, "game_system": "gff", "faction_folder": "robot_legions", "rules": []},
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 3, "rules": []})
	var target: GameUnit = null
	if foe:
		target = ParityTable._make_unit(_main, {"player": 2, "name": "Mark", "models": 1, "x_in": 0.0, "z_step_in": 0.0,
			"quality": 4, "defense": 4, "tough": 1, "game_system": "gff", "faction_folder": "robot_legions", "rules": []},
			{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 1, "rules": []})
		(target.models[0] as ModelInstance).node.global_position = ledge[1] + Vector3(6 * INCH, 0, 0)
	var ms: Array = att.models
	var spots := [Vector3(0, 0, 0), Vector3(-1.1 * INCH, 0, -0.6 * INCH), Vector3(-1.1 * INCH, 0, 0.6 * INCH)]
	for k in ms.size():
		(ms[k] as ModelInstance).node.global_position = ledge[0] + spots[k]
		(ms[k] as ModelInstance).node.set_meta("network_id", 901 + k)
		(ms[k] as ModelInstance).node.set_meta("model_instance", ms[k])
	CoreActivation._env = 1
	assert_bool(_main.core_activation_start(att)).override_failure_message("no Start").is_true()
	_main.seed_tray_rng(0)
	var n0: Node3D = (ms[0] as ModelInstance).node
	var from: Vector3 = n0.global_position
	n0.global_position = ledge[1]
	att.unit_properties["moved_round"] = 1
	assert_bool(_main.attacked_unit_drag_refused(att, 3.0)).override_failure_message("the drop was refused").is_false()
	await SoloHarness.drop(_main, [{"node": n0, "inches": 3.0, "from_raw": from,
		"path": PackedVector2Array([Vector2(from.x, from.z), Vector2(ledge[1].x, ledge[1].z)])}])
	return [att, target]


## The radial activation door (the card's End, the chip and the toggle all go through it).
func _press_end(att: GameUnit) -> void:
	await _main.radial_menu_controller._toggle_activation({"game_unit": att})


## Models 2-3 put by hand beside model 1 (0.2 in gaps), as the owner would drag them.
func _close_up(att: GameUnit) -> void:
	var ms: Array = att.models
	var at: Vector3 = (ms[0] as ModelInstance).node.global_position
	var step := 2.0 * SoloController.model_base_radius_m(ms[0] as ModelInstance) + 0.2 * INCH
	for k in [1, 2]:
		(ms[k] as ModelInstance).node.global_position = at + Vector3(0, 0, step * (1 if k == 1 else -1))


@warning_ignore('unused_parameter')
func test_end_locks_until_the_others_stand_within_1_in_and_never_rolls_again(
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	var att: GameUnit = (await _fallen_leaper())[0]
	var activated := [0]
	var on_act := func(_gu) -> void: activated[0] += 1
	_main.radial_menu_controller.unit_activated.connect(on_act)
	await _press_end(att)
	assert_int(_count("Falling: Leaper model 1 falls")).override_failure_message("the core's fall: %s" % [_lines]).is_equal(1)
	assert_bool((att.models[0] as ModelInstance).is_alive).override_failure_message("Tough 3 survives the fall").is_true()
	assert_int(_count(LOCK)).override_failure_message("the lock line: %s" % [_lines]).is_equal(1)
	assert_bool(att.is_activated).override_failure_message("locked: the activation is not over").is_false()
	await _press_end(att)
	assert_int(_count(LOCK)).override_failure_message("re-asked on the next End").is_equal(2)
	assert_int(_count("Jump: Leaper model 1 jumps")).override_failure_message("(1) one jump roll only: %s" % [_lines]).is_equal(1)
	assert_int(activated[0]).override_failure_message("(3) no activation goes out while locked").is_equal(0)
	_close_up(att)
	await _press_end(att)
	assert_int(_count(LOCK)).override_failure_message("lifted: no new lock line").is_equal(2)
	assert_int(activated[0]).override_failure_message("(3) the End ends it now: one activation, after the lock").is_equal(1)
	assert_int(_count("Jump: Leaper model 1 jumps")).override_failure_message("(1) still one jump roll").is_equal(1)
	_main.radial_menu_controller.unit_activated.disconnect(on_act)


## #3872: the owner DRAGS models 2-3 beside the fallen model through the real drop door - a placement within 1 in, not a
## move of the activation: no jump, no move allowance; the positions stand and the End lifts the lock.
@warning_ignore('unused_parameter')
func test_placing_the_others_by_hand_is_no_move(
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	var att: GameUnit = (await _fallen_leaper())[0]
	await _press_end(att)
	assert_int(_count(LOCK)).override_failure_message("the lock line: %s" % [_lines]).is_equal(1)
	var ms: Array = att.models
	var at: Vector3 = (ms[0] as ModelInstance).node.global_position
	var step := 2.0 * SoloController.model_base_radius_m(ms[0] as ModelInstance) + 0.2 * INCH
	for k in [1, 2]:
		var n: Node3D = (ms[k] as ModelInstance).node
		var from := n.global_position
		var to := at + Vector3(0, 0, step * (1 if k == 1 else -1))
		n.global_position = to
		assert_bool(_main.attacked_unit_drag_refused(att, from.distance_to(to) / INCH)).override_failure_message("model %d's drag refused: %s" % [k + 1, _lines]).is_false()
		await SoloHarness.drop(_main, [{"node": n, "inches": from.distance_to(to) / INCH, "from_raw": from,
			"path": PackedVector2Array([Vector2(from.x, from.z), Vector2(to.x, to.z)])}])
		assert_float(n.global_position.distance_to(to)).override_failure_message("model %d's spot stands: %s" % [k + 1, _lines]).is_less(0.001)
	assert_int(_count("Leaper: model 2 jumps") + _count("Leaper: model 3 jumps")).override_failure_message("no jump: %s" % [_lines]).is_equal(0)
	assert_bool(_lines.any(func(l: String) -> bool: return l.contains("Advance allowance"))).override_failure_message("no allowance: %s" % [_lines]).is_false()
	await _press_end(att)
	assert_int(_count(LOCK)).override_failure_message("lifted by the hand placement: %s" % [_lines]).is_equal(1)
	assert_int(_count("Leaper activated")).override_failure_message("the End ends the activation: %s" % [_lines]).is_equal(1)


@warning_ignore('unused_parameter')
func test_an_ai_drive_never_enters_the_state(
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	var att: GameUnit = (await _fallen_leaper())[0]
	var s: Dictionary = CoreActivation._sessions[att.unit_id]
	var t: Array = (s["transcript"] as Array).duplicate()
	t.append({"t": "intent", "kind": CoreActivation.declared_mode(_main), "shoot": ""})
	var r: Dictionary = await CoreActivation.drive(_main, int(s["handle"]), att, t, true)
	assert_str(str(r["step"])).is_equal("done")
	assert_int(_count("Falling: Leaper model 1 falls")).override_failure_message("the core's fall: %s" % [_lines]).is_equal(1)
	assert_bool(s.has("fall_replace")).override_failure_message("(2) an AI seat takes the core placer, never the lock").is_false()


@warning_ignore('unused_parameter')
func test_a_shot_that_made_a_model_fall_locks_the_end_the_same(
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	var both: Array = await _fallen_leaper(true)
	var att: GameUnit = both[0]
	var activated := [0]
	var on_act := func(_gu) -> void: activated[0] += 1
	_main.radial_menu_controller.unit_activated.connect(on_act)
	await CoreActivation.human_shoot(_main, att, both[1])
	assert_int(_count("Falling: Leaper model 1 falls")).override_failure_message("the shot's fall: %s" % [_lines]).is_equal(1)
	await _press_end(att)
	assert_int(_count(LOCK)).override_failure_message("(4) the shot path locks the same: %s" % [_lines]).is_equal(1)
	assert_int(activated[0]).override_failure_message("(3) no activation goes out while locked").is_equal(0)
	_close_up(att)
	await _press_end(att)
	assert_int(activated[0]).override_failure_message("(4) lifted after the shot").is_equal(1)
	assert_int(_count("Jump: Leaper model 1 jumps")).override_failure_message("(1) one jump roll on the shot path").is_equal(1)
	_main.radial_menu_controller.unit_activated.disconnect(on_act)


@warning_ignore('unused_parameter')
func test_a_1_in_ring_marks_the_fallen_model_while_locked(
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	var att: GameUnit = (await _fallen_leaper())[0]
	await _press_end(att)
	var s: Dictionary = CoreActivation._sessions[att.unit_id]
	var ring: Variant = s.get("fall_ring")
	assert_bool(is_instance_valid(ring) and ring is MeshInstance3D).override_failure_message("(Q1) a ring while locked").is_true()
	if not (is_instance_valid(ring) and ring is MeshInstance3D):
		return
	var fell: ModelInstance = att.models[0]
	var at: Vector3 = (ring as MeshInstance3D).global_position
	assert_float(Vector2(at.x, at.z).distance_to(Vector2(fell.node.global_position.x, fell.node.global_position.z))) \
		.override_failure_message("round the model that fell").is_less(0.001)
	var want := SoloController.model_base_radius_m(fell) + INCH
	var torus := (ring as MeshInstance3D).mesh as TorusMesh
	assert_float((torus.inner_radius + torus.outer_radius) / 2.0).override_failure_message("base + 1 in").is_equal_approx(want, 0.001)
	_close_up(att)
	await _press_end(att)
	assert_bool(s.has("fall_ring")).override_failure_message("lifted: the ring goes").is_false()
	assert_bool(not is_instance_valid(ring) or (ring as Node).is_queued_for_deletion()).override_failure_message("freed").is_true()


## The presented card's button with `text`, or null.
func _card_button(att: GameUnit, text: String) -> Button:
	_main.unit_dock.present_unit(att)
	for b in _main.unit_dock.find_children("*", "Button", true, false):
		if (b as Button).text == text and (b as Button).is_visible_in_tree():
			return b
	return null


@warning_ignore('unused_parameter')
func test_place_for_me_on_the_card_lands_the_core_placer_and_lifts_the_lock(
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	var att: GameUnit = (await _fallen_leaper())[0]
	var activated := [0]
	var on_act := func(_gu) -> void: activated[0] += 1
	_main.radial_menu_controller.unit_activated.connect(on_act)
	await _press_end(att)
	assert_int(_count(LOCK)).is_equal(1)
	var button: Button = _card_button(att, "Place for me")
	assert_object(button).override_failure_message("(Q2) the card offers Place for me while locked").is_not_null()
	if button == null:
		return
	button.pressed.emit()
	assert_int(_count("Leaper: Fall: model 1 fell; model 2, model 3 placed within 1 in of it")) \
		.override_failure_message("the core's line: %s" % [_lines]).is_equal(1)
	assert_bool(CoreActivation.fall_replace_needed(_main, att, att.models[0])).override_failure_message("all within 1 in").is_false()
	await _press_end(att)
	assert_int(activated[0]).override_failure_message("the End ends it after the placer").is_equal(1)
	assert_int(_count("Jump: Leaper model 1 jumps")).override_failure_message("one jump roll").is_equal(1)
	assert_bool(CoreActivation.fall_pending(att.unit_id)).override_failure_message("no button once ended (the card reads fall_pending)").is_false()
	_main.radial_menu_controller.unit_activated.disconnect(on_act)


@warning_ignore('unused_parameter')
func test_an_ai_unit_takes_the_core_placer_at_once(
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	var att: GameUnit = (await _fallen_leaper())[0]
	var s: Dictionary = CoreActivation._sessions[att.unit_id]
	var t: Array = (s["transcript"] as Array).duplicate()
	t.append({"t": "intent", "kind": CoreActivation.declared_mode(_main), "shoot": ""})
	await CoreActivation.drive(_main, int(s["handle"]), att, t, true)
	assert_int(_count("Leaper: Fall: model 1 fell; model 2, model 3 placed within 1 in of it")) \
		.override_failure_message("(Q3) the core placer, logged: %s" % [_lines]).is_equal(1)
	assert_bool(CoreActivation.fall_replace_needed(_main, att, att.models[0])).override_failure_message("all within 1 in").is_false()
	assert_bool(s.has("fall_replace")).override_failure_message("never the lock").is_false()
