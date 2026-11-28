extends GdUnitTestSuite
## Plan step 29e-2a (D-29 Q3 by the book, 3.6 p.15: "then the opponent must place any other models from the unit within 1"
## of it"): on a hotseat Automatic table (two humans) the attacker pushes, then the DEFENDER is asked. "I place" rings the
## pushed model; the defender drags the others (its drags pass the turn and activation locks and are no move of its own);
## Enter answers. A spot past 1 in is said and asked again; "Place for me" is the core's D14 placer.
## Real: the main scene, NmlCore, the step driver, the owner-choice door, the prompt cards, the drop door.
const INCH := 0.0254
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _lines: Array = []


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC   # hotseat Automatic: both sides human
	SoloHarness.fast(_main)
	SoloHarness.auto_saves(_main)
	_lines = []
	_main.battle_log.entry_added.connect(_tap)


func after_test() -> void:
	_main.battle_log.entry_added.disconnect(_tap)
	CoreActivation.finish_replace_pick(false)
	CoreActivation.skip_push_pick()
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _tap(e: Dictionary) -> void:
	_lines.append(str(e["text"]))


func _unit(player: int, name: String, models: int, quality: int, weapon: Dictionary) -> GameUnit:
	var u := ParityTable._make_unit(_main, {"player": player, "name": name, "models": models, "x_in": 0.0, "z_step_in": 0.0,
		"quality": quality, "defense": 6, "tough": 1, "game_system": "gff", "faction_folder": "robot_legions", "rules": []}, weapon)
	for k in u.models.size():
		(u.models[k] as ModelInstance).node.global_position = Vector3((12.0 if player == 2 else 0.0) * INCH, 0, k * 1.5 * INCH)
		(u.models[k] as ModelInstance).node.set_meta("network_id", 800 + player * 10 + k)
		(u.models[k] as ModelInstance).node.set_meta("model_instance", u.models[k])
	return u


func _drag(n: Node3D, to: Vector3) -> void:
	var from := n.global_position
	n.global_position = to
	await SoloHarness.drop(_main, [{"node": n, "inches": from.distance_to(to) / INCH, "from_raw": from,
		"path": PackedVector2Array([Vector2(from.x, from.z), Vector2(to.x, to.z)])}])


## Two hits kill two of the defender's four models (half strength, the morale test fails: Shaken), the push die is a 5,
## the attacker drags survivor 1 1.9 in east. `place` answers the defender: [] = "Place for me", else gaps (inches, south
## of the pushed model) for survivor 2 in turn - one per ask. Returns [drive answer, defender, locks open while placing].
func _push(place: Array) -> Array:
	var gunner := _unit(1, "Gunner", 1, 2, {"name": "Rifle", "range_in": 24, "attacks": 2, "count": 1, "rules": []})
	var squad := _unit(2, "Squad", 4, 6, {})
	CoreActivation._env = 1
	assert_bool(_main.core_activation_start(gunner)).override_failure_message("no Start").is_true()
	var s: Dictionary = CoreActivation._sessions[gunner.unit_id]
	var t: Array = (s["transcript"] as Array).duplicate()
	t.append_array([{"t": "intent", "kind": 0, "shoot": squad.unit_id}, {"t": "faces", "faces": [6, 6]}, {"t": "faces", "faces": [1, 1]},
		{"t": "faces", "faces": [1]}, {"t": "faces", "faces": [5]}])
	var done := [null]
	var go := func() -> void:
		done[0] = await CoreActivation.drive(_main, int(s["handle"]), gunner, t, false)
	go.call()
	var gaps := place.duplicate()
	var locks_open := [false]
	var spot_given := false
	var until := Time.get_ticks_msec() + 20000   # a time budget: the prompts wait on real-time pacing, not on frames
	while Time.get_ticks_msec() < until:
		if done[0] != null:
			break
		for c in _main.find_children("*", "PromptCard", false, false):
			var title := str((c as PromptCard).title)
			if title == "Push?":
				(c as PromptCard).resolve(true)
			elif title == "Place the rest":
				(c as PromptCard).resolve(not gaps.is_empty())
		if not CoreActivation.push_pick.is_empty() and not spot_given:
			spot_given = true
			var n: Node3D = (squad.get_alive_models()[0] as ModelInstance).node
			await _drag(n, n.global_position + Vector3(1.9 * INCH, 0, 0))
		if not CoreActivation.replace_pick.is_empty() and not gaps.is_empty():
			locks_open[0] = not _main.core_drag_blocked(squad, true) and not _main.hotseat_off_turn_drag(squad)
			var pushed: Vector3 = (squad.get_alive_models()[0] as ModelInstance).node.global_position
			var r := SoloController.model_base_radius_m(squad.get_alive_models()[0] as ModelInstance)
			await _drag((squad.get_alive_models()[1] as ModelInstance).node, pushed + Vector3(0, 0, 2 * r + float(gaps.pop_front()) * INCH))
			CoreActivation.finish_replace_pick(true)
		await get_tree().process_frame
	assert_object(done[0]).override_failure_message("the drive did not end: %s" % [_lines]).is_not_null()
	return [done[0] if done[0] != null else {}, squad, locks_open[0]]


func _gap_in(squad: GameUnit) -> float:
	var a: ModelInstance = squad.get_alive_models()[0]
	var b: ModelInstance = squad.get_alive_models()[1]
	return (Vector2(a.node.global_position.x, a.node.global_position.z).distance_to(Vector2(b.node.global_position.x, b.node.global_position.z))
		- 2 * SoloController.model_base_radius_m(a)) / INCH


@warning_ignore('unused_parameter')
func test_the_defender_places_the_rest_itself(do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	var r := await _push([0.5])
	assert_str(str((r[0] as Dictionary).get("step", ""))).override_failure_message("%s %s" % [r[0], _lines]).is_equal("done")
	assert_bool(r[2]).override_failure_message("its drags pass the activation and turn locks").is_true()
	assert_float(_gap_in(r[1])).override_failure_message("the owner's spot stands: %s" % [_lines]).is_equal_approx(0.5, 0.02)
	assert_bool(_lines.any(func(l: String) -> bool: return l.contains("the owner placed model 2 within 1 in of it"))).override_failure_message("%s" % [_lines]).is_true()


@warning_ignore('unused_parameter')
func test_a_spot_past_1_in_is_said_and_asked_again(do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	var r := await _push([2.5, 0.3])
	assert_str(str((r[0] as Dictionary).get("step", ""))).is_equal("done")
	assert_bool(_lines.has("Push: model 2 stands more than 1 in from the pushed model")).override_failure_message("%s" % [_lines]).is_true()
	assert_float(_gap_in(r[1])).override_failure_message("the second spot stands").is_equal_approx(0.3, 0.02)


@warning_ignore('unused_parameter')
func test_place_for_me_is_the_core_placer(do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	var r := await _push([])
	assert_str(str((r[0] as Dictionary).get("step", ""))).is_equal("done")
	assert_bool(_lines.any(func(l: String) -> bool: return l.contains("model 2 placed within 1 in of it"))).override_failure_message("%s" % [_lines]).is_true()
	assert_float(_gap_in(r[1])).override_failure_message("D14: 1 in").is_less_equal(1.001)
