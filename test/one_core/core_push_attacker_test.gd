extends GdUnitTestSuite
## Plan step 29e-1 (D-29 Q2/R2): the attacker decides the push after the dice. A human gff shot that shakes an enemy unit
## asks "Push?"; on yes (and a 4+) the attacker drags one of the target's models inside its 2 in ring - the drop is the
## core's push_to answer, the core moves the model. A spot the core refuses is said and asked again; Esc skips; "No" is
## no push. The dice ride in the transcript (one hit, a failed save, a failed morale test, the push die).
## Real: the main scene, NmlCore, the step driver, the owner-choice door, the prompt card, the drop door.
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
	SoloHarness.start(_main, [2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main, false)   # the attacker's prompts are asked off the headless batch
	SoloHarness.fast(_main)
	SoloHarness.auto_saves(_main)
	_lines = []
	_main.battle_log.entry_added.connect(_tap)


func after_test() -> void:
	_main.battle_log.entry_added.disconnect(_tap)
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _tap(e: Dictionary) -> void:
	_lines.append(str(e["text"]))


func _unit(player: int, name: String, x_in: float, quality: int, weapon: Dictionary) -> GameUnit:
	var models := 1 if player == 1 else 2
	var u := ParityTable._make_unit(_main, {"player": player, "name": name, "models": models, "x_in": 0.0, "z_step_in": 0.0,
		"quality": quality, "defense": 6, "tough": 1, "game_system": "gff", "faction_folder": "robot_legions", "rules": []}, weapon)
	for k in u.models.size():
		(u.models[k] as ModelInstance).node.global_position = Vector3(x_in * INCH, 0, k * 1.5 * INCH)
		(u.models[k] as ModelInstance).node.set_meta("network_id", 700 + player * 10 + k)
		(u.models[k] as ModelInstance).node.set_meta("model_instance", u.models[k])
	return u


## The shot with every die given: `push_face` is the push die. `answer` drives the prompts: "push" / "no" for Push?, then
## each entry of `drags` (inches east of the survivor's start; "esc" = Esc) for the spot. Returns [the drive's answer,
## the target]. The target's first model dies (the failed save), the second is the survivor at z = 1.5 in.
func _shot(answer: String, drags: Array, push_face := 5, tag := "") -> Array:
	var gunner := _unit(1, "Gunner" + tag, 0.0, 2, {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 1, "rules": []})
	var squad := _unit(2, "Squad" + tag, 12.0, 6, {})
	CoreActivation._env = 1
	var h := CoreActivation.capture(_main)
	var t := [{"t": "begin"}, {"t": "intent", "kind": 0, "shoot": squad.unit_id},
		{"t": "faces", "faces": [6]}, {"t": "faces", "faces": [1]}, {"t": "faces", "faces": [1]}, {"t": "faces", "faces": [push_face]}]
	var done := [null]
	var go := func() -> void:
		done[0] = await CoreActivation.drive(_main, h, gunner, t, false)
	go.call()
	var left := drags.duplicate()
	var until := Time.get_ticks_msec() + 20000   # a time budget: the prompts wait on real-time pacing, not on frames
	while Time.get_ticks_msec() < until:
		if done[0] != null:
			break
		for c in _main.find_children("*", "PromptCard", false, false):
			if str((c as PromptCard).title) == "Push?":
				(c as PromptCard).resolve(answer == "push")
		if not CoreActivation.push_pick.is_empty() and not left.is_empty():
			var d: Variant = left.pop_front()
			if str(d) == "esc":
				CoreActivation.skip_push_pick()
			else:
				var n: Node3D = (squad.get_alive_models()[0] as ModelInstance).node
				var from := n.global_position
				n.global_position = from + Vector3(float(d) * INCH, 0, 0)
				await SoloHarness.drop(_main, [{"node": n, "inches": float(d), "from_raw": from,
					"path": PackedVector2Array([Vector2(from.x, from.z), Vector2(n.global_position.x, n.global_position.z)])}])
		await get_tree().process_frame
	assert_object(done[0]).override_failure_message("the drive did not end (a prompt or the spot still waits): %s" % [_lines]).is_not_null()
	CoreActivation.skip_push_pick()   # a spot still asked ends here, so no coroutine outlives the test
	return [done[0] if done[0] != null else {}, squad]


@warning_ignore('unused_parameter')
func test_a_yes_and_a_drag_push_the_dragged_model(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	var r := await _shot("push", [1.5])
	assert_str(str((r[0] as Dictionary).get("step", ""))).override_failure_message("%s %s" % [r[0], _lines]).is_equal("done")
	var survivor: Node3D = ((r[1] as GameUnit).get_alive_models()[0] as ModelInstance).node
	assert_float(survivor.global_position.x / INCH).override_failure_message("pushed 1.5 in east: %s" % [_lines]).is_equal_approx(13.5, 0.01)
	assert_bool(_lines.any(func(l: String) -> bool: return l.begins_with("Push: Gunner rolls 5 and pushes Squad model 1 1.5 in"))) \
		.override_failure_message("%s" % [_lines]).is_true()


@warning_ignore('unused_parameter')
func test_a_spot_past_2_in_is_said_and_asked_again(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	var r := await _shot("push", [3.0, 1.0])
	assert_str(str((r[0] as Dictionary).get("step", ""))).is_equal("done")
	assert_bool(_lines.has("Push: 3.0 in is over the 2 in")).override_failure_message("the refusal said: %s" % [_lines]).is_true()
	var survivor: Node3D = ((r[1] as GameUnit).get_alive_models()[0] as ModelInstance).node
	assert_float(survivor.global_position.x / INCH).override_failure_message("the second spot stands").is_equal_approx(13.0, 0.01)


@warning_ignore('unused_parameter')
func test_no_or_esc_moves_nothing(do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	var r := await _shot("no", [])
	assert_bool(_lines.has("Push: Gunner does not push Squad")).override_failure_message("%s" % [_lines]).is_true()
	assert_float(((r[1] as GameUnit).get_alive_models()[0] as ModelInstance).node.global_position.x / INCH).is_equal_approx(12.0, 0.01)


@warning_ignore('unused_parameter')
func test_esc_skips_the_spot(do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	var r := await _shot("push", ["esc"])
	assert_bool(_lines.any(func(l: String) -> bool: return l.ends_with("no spot named, nothing moves"))).override_failure_message("%s %s" % [r[0], _lines]).is_true()
	assert_float(((r[1] as GameUnit).get_alive_models()[0] as ModelInstance).node.global_position.x / INCH).is_equal_approx(12.0, 0.01)
