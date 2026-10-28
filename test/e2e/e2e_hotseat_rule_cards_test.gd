extends GdUnitTestSuite
## Maintainer test 4 (26.10.): the start-of-game "apply by hand" list must be VISIBLE, not only a line
## in the collapsed battle log. On a hotseat Automatic table each human army gets one PromptCard with
## the rules the engine leaves to the player; OK moves on to the next seat. A Manual table shows none.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.DEPLOYMENT
	_main.opr_army_manager.current_round = 1
	_main._solo_game_finished = false
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _register(pid: int, unit_name: String, rules: Array = []) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3.ZERO])
	if not rules.is_empty():
		u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _card_for(pid: int) -> PromptCard:
	for c in _main.get_children():
		var card := c as PromptCard
		if card != null and card.is_inside_tree() and card.title == "Rules you apply by hand (P%d)" % pid:
			return card
	return null


func _card_text(card: PromptCard) -> String:
	var text := card.title
	for n in card.find_children("*", "Label", true, false):
		text += "\n" + (n as Label).text
	return text


func test_manual_table_shows_no_card(timeout := 120000) -> void:
	_register(1, "P1 Squad", ["Hit & Run"])
	_register(2, "P2 Squad", ["Hit & Run"])
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.MANUAL
	_main.opr_army_manager.start_game()
	await _runner.simulate_frames(6)
	assert_object(_card_for(1)).override_failure_message("test 4 - a Manual table showed the by-hand card").is_null()
	assert_object(_card_for(2)).is_null()
	await E2EBoot.settle(get_tree())


func test_hotseat_automatic_shows_the_by_hand_card_per_human_seat(timeout := 120000) -> void:
	_register(1, "P1 Squad", ["Hit & Run"])
	_register(2, "P2 Squad", ["Hit & Run"])
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_main.opr_army_manager.start_game()
	await _runner.simulate_frames(4)
	var p1 := _card_for(1)
	assert_object(p1).override_failure_message("test 4 - no visible 'apply by hand' card for P1").is_not_null()
	if p1 == null:
		return
	assert_str(_card_text(p1)).override_failure_message("test 4 - the P1 card does not name the by-hand rule") \
		.contains("Hit & Run")
	assert_str(_card_text(p1)).contains("apply by hand")
	p1.ok_button.pressed.emit()
	await _runner.simulate_frames(4)
	var p2 := _card_for(2)
	assert_object(p2).override_failure_message("test 4 - OK on P1 did not move on to P2").is_not_null()
	if p2 == null:
		return
	assert_str(_card_text(p2)).contains("Hit & Run")
	p2.ok_button.pressed.emit()
	await E2EBoot.settle(get_tree())


