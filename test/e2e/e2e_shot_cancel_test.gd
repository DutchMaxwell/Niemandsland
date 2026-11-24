extends GdUnitTestSuite
## E2E — Cancel aborts a player's shot. A live test found Cancel during target selection fired the weapons anyway.
## Every way out of the shot's target steps must leave the shot undone: no die thrown (the activation can still be
## cancelled), no volley line in the battle log, the unit not activated, its activation still open.
##   (1) the split-fire prompt: its × and Esc used to mean "All at <first target>", which fired at once;
##   (2) right-click / Esc while picking the split's second target used to fire everything at the first target;
##   (3) the unit card's Cancel while picking a target used to leave the pick open, so the next click fired.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const PROMPT_LAYER := 90

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _armed(pid: int, unit_name: String, pos: Vector3, weapon_names: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	for wn in weapon_names:
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(wn)
		w.range_value = 24
		w.attacks = 2
		ws.append(w)
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The shot did not happen: nothing thrown, nothing written, the activation open and unspent.
func _assert_nothing_fired(shooter: GameUnit, how: String) -> void:
	var text := _log_text()
	assert_bool(text.contains("fires")) \
		.override_failure_message("%s: a volley line was written:\n%s" % [how, text]).is_false()
	assert_bool(shooter.is_activated).override_failure_message("%s: the activation was spent" % how).is_false()
	assert_bool(CoreActivation.session_open(shooter.unit_id)) \
		.override_failure_message("%s: the activation closed" % how).is_true()
	assert_bool(CoreActivation.can_cancel(shooter.unit_id)) \
		.override_failure_message("%s: a die was thrown" % how).is_true()
	assert_bool(_main._solo_target_mode.is_empty()) \
		.override_failure_message("%s: the target pick is still open" % how).is_true()


func _prompt() -> CanvasLayer:
	for n: Node in get_tree().root.find_children("*", "PromptCard", true, false):
		if not n.is_queued_for_deletion() and (n as PromptCard).title == "Split fire?":
			return n as CanvasLayer
	return null


func _await_prompt() -> PromptCard:
	for _i in 120:
		var p := _prompt()
		if p != null:
			await _runner.simulate_frames(2)
			return p as PromptCard
		await get_tree().process_frame
	fail("the split-fire prompt never opened")
	return null


func _answer(out: Array) -> Variant:
	for _i in 300:
		if not out.is_empty():
			return out[0]
		await get_tree().process_frame
	fail("the split-fire prompt never answered")
	return null


## (1) The split-fire prompt's way out cancels the shot; it is not the same answer as "All at <target>".
func test_the_split_prompt_close_and_esc_cancel_the_shot(timeout := 120000) -> void:
	var foe := _armed(2, "FoeA", Vector3(8.0 * INCH, 0, 0), [])
	var names := ["Rifle", "Cannon"]
	for how in ["close", "esc"]:
		var out: Array = []
		(func() -> void: out.append(await _main._solo_ask_split_fire(foe, names))).call()
		var p := await _await_prompt()
		if how == "close":
			(p.find_child("CloseButton", true, false) as Button).pressed.emit()
		else:
			var ev := InputEventKey.new()
			ev.keycode = KEY_ESCAPE
			ev.physical_keycode = KEY_ESCAPE
			ev.pressed = true
			Input.parse_input_event(ev)
		var got: Variant = await _answer(out)
		assert_bool(got == null).override_failure_message(
			"the prompt's %s must cancel the shot (null), got %s - the same answer as 'All at'" % [how, got]).is_true()
	var all_out: Array = []
	(func() -> void: all_out.append(await _main._solo_ask_split_fire(foe, names))).call()
	var p2 := await _await_prompt()
	for b: Node in p2.find_children("*", "Button", true, false):
		if (b as Button).text == "All at FoeA":
			(b as Button).pressed.emit()
	var all_got: Variant = await _answer(all_out)
	assert_bool(all_got is Array and (all_got as Array).is_empty()) \
		.override_failure_message("'All at' keeps one target, got %s" % [all_got]).is_true()


## (1b) A cancelled split prompt ends the attack: nothing rolled, the activation open.
func test_a_cancelled_split_prompt_fires_nothing(timeout := 120000) -> void:
	var shooter := _armed(1, "Tank", Vector3.ZERO, ["Rifle", "Cannon"])
	var foe := _armed(2, "FoeA", Vector3(8.0 * INCH, 0, 0), [])
	await E2EBoot.start_activation(_main, shooter)
	await _main._solo_attack_after_split_choice(shooter, foe, false, {"cancel": true})
	await E2EBoot.settle(get_tree())
	_assert_nothing_fired(shooter, "the split prompt's Cancel")


## (2) Right-click and Esc while picking the second target cancel the whole attack.
func test_cancel_at_the_second_pick_fires_nothing(timeout := 240000) -> void:
	for how in ["right-click", "esc"]:
		var shooter := _armed(1, "Tank" + how, Vector3.ZERO, ["Rifle", "Cannon"])
		var foe_a := _armed(2, "FoeA" + how, Vector3(8.0 * INCH, 0, 0), [])
		await E2EBoot.start_activation(_main, shooter)
		_main._solo_target_mode = {"unit": shooter, "melee": false, "split_first": foe_a,
			"split_b_names": ["Cannon"], "split_rest_names": ["Rifle"], "split_visuals": []}
		var ev: InputEvent
		if how == "esc":
			var k := InputEventKey.new()
			k.keycode = KEY_ESCAPE
			k.pressed = true
			ev = k
		else:
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_RIGHT
			mb.pressed = true
			ev = mb
		assert_bool(await _main._solo_targeting_input(ev)).is_true()
		await E2EBoot.settle(get_tree(), 30)
		_assert_nothing_fired(shooter, how + " at the second pick")
		CoreActivation.cancel(_main, shooter)


## (3) The unit card's Cancel during a target pick closes the pick: the next click on an enemy shoots nothing.
func test_the_card_cancel_closes_the_target_pick(timeout := 120000) -> void:
	var shooter := _armed(1, "Tank", Vector3.ZERO, ["Rifle"])
	_armed(2, "FoeA", Vector3(8.0 * INCH, 0, 0), [])
	await E2EBoot.start_activation(_main, shooter)
	_main._solo_target_mode = {"unit": shooter, "melee": false}
	_main.core_activation_cancel(shooter)
	await E2EBoot.settle(get_tree())
	assert_bool(_main._solo_target_mode.is_empty()) \
		.override_failure_message("the card's Cancel left the target pick open: the next click would fire").is_true()
	assert_bool(shooter.is_activated).is_false()
	assert_bool(_log_text().contains("fires")).is_false()
