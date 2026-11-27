extends GdUnitTestSuite
## M-3 (maintainer 16.11.): NmlCore is MANDATORY for NACHTMAHR and Automatic play. Without it every door that
## would seat the AI or switch Automatic on refuses with ONE battle-log line (CoreLoadNotice.ENGINE_OFF_LINE) and
## the Solo panel says why instead of offering the tick. The real main.tscn, the seam standing in for an absent
## core (CoreActivation.offer_override) - so this suite needs no real core. Every refusal has its positive twin:
## with the core stood in as present, the same door works.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const OFF := CoreLoadNotice.ENGINE_OFF_LINE

## Real NetworkManager, transport swapped out: records the commands this client sends.
class FakeNet extends "res://scripts/network_manager.gd":
	var cmds: Array = []
	func is_multiplayer_active() -> bool:
		return true
	func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:
		cmds.append({"t": type, "p": payload, "to": target_peer})
		return true
	func is_server() -> bool:
		return true
	func get_my_peer_id() -> int:
		return 1
	func seed_host_identity() -> void:
		pass

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	RulesAutomation.ui_enabled_override = true
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	CoreActivation.offer_override = -1
	RulesAutomation.ui_enabled_override = false
	RulesAutomation.ui_disabled_override = false
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _off_lines() -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]) == OFF:
			n += 1
	return n


func _cmds(type: String) -> int:
	var n := 0
	for c in (_main.network_manager.cmds as Array):
		if str((c as Dictionary)["t"]) == type:
			n += 1
	return n


func _fake_net() -> void:
	var fake: FakeNet = auto_free(FakeNet.new())
	fake.army_manager = _main.opr_army_manager
	fake.player_names[2] = "Bea"
	_main.network_manager = fake


func _tick_rows() -> Array:
	var out: Array = []
	for c in _main.solo_panel_box.get_children():
		if c is CheckButton and (c as CheckButton).text.begins_with("AI plays "):
			out.append((c as CheckButton).text)
	return out


func _has_why_label() -> bool:
	for c in _main.solo_panel_box.get_children():
		if c is Label and (c as Label).text == OFF:
			return true
	return false


func test_the_ai_tick_is_refused_with_one_line() -> void:
	CoreActivation.offer_override = 0
	_main._on_solo_ai_toggled(true, 2)
	assert_bool(_main.solo_ai_slots.is_empty()).is_true()
	assert_int(_off_lines()).is_equal(1)


func test_the_ai_tick_works_with_the_core() -> void:
	CoreActivation.offer_override = 1
	_main._on_solo_ai_toggled(true, 2)
	assert_bool(_main.solo_ai_slots.has(2)).is_true()
	assert_int(_off_lines()).is_equal(0)


func test_untick_stays_possible_without_the_core() -> void:
	_main.solo_ai_slots = {2: true}   # a seat that was there before (a save, a peer)
	CoreActivation.offer_override = 0
	_main._on_solo_ai_toggled(false, 2)
	assert_bool(_main.solo_ai_slots.is_empty()).is_true()
	assert_int(_off_lines()).is_equal(0)


func test_f11_does_not_run_the_ai_without_the_core() -> void:
	CoreActivation.offer_override = 0
	var phase_before: int = _main.opr_army_manager.game_phase
	await _main._run_solo_ai_turn()   # the refused tick alone would not stop it: it would deploy and flip to PLAYING first
	assert_int(_main.opr_army_manager.game_phase).is_equal(phase_before)
	assert_bool(_main.solo_ai_slots.is_empty()).is_true()
	assert_int(_off_lines()).is_equal(1)


func test_an_import_with_the_ai_box_ticked_imports_a_human_army_without_the_core() -> void:
	CoreActivation.offer_override = 0
	var army := OPRApiClient.OPRArmy.new()
	army.name = "Synthetic"
	await _main._on_opr_army_imported(army, 2, true)
	assert_bool(_main.solo_ai_slots.is_empty()).is_true()
	assert_int(_off_lines()).is_equal(1)


func test_an_import_with_the_ai_box_ticked_seats_the_ai_with_the_core() -> void:
	CoreActivation.offer_override = 1
	var army := OPRApiClient.OPRArmy.new()
	army.name = "Synthetic"
	await _main._on_opr_army_imported(army, 2, true)
	assert_bool(_main.solo_ai_slots.has(2)).is_true()
	assert_int(_off_lines()).is_equal(0)


func test_the_solo_panel_says_why_instead_of_offering_the_tick() -> void:
	_main.opr_army_manager.armies = {1: null, 2: null}
	CoreActivation.offer_override = 0
	_main._refresh_solo_panel()
	assert_array(_tick_rows()).is_empty()
	assert_bool(_has_why_label()).is_true()
	CoreActivation.offer_override = 1
	_main._refresh_solo_panel()
	await _runner.simulate_frames(1)   # the old rows were queue_free'd
	assert_int(_tick_rows().size()).is_equal(2)
	assert_bool(_has_why_label()).is_false()


func test_a_seat_already_there_keeps_its_row_without_the_core() -> void:
	_main.opr_army_manager.armies = {1: null, 2: null}
	_main.solo_ai_slots = {2: true}
	CoreActivation.offer_override = 0
	_main._refresh_solo_panel()
	assert_int(_tick_rows().size()).is_equal(1)
	assert_bool(_has_why_label()).is_true()


func test_a_saved_ai_seat_is_not_brought_back_without_the_core() -> void:
	CoreActivation.offer_override = 0
	_main._adopt_saved_ai_slots([2])
	assert_bool(_main.solo_ai_slots.is_empty()).is_true()
	assert_int(_off_lines()).is_equal(1)
	CoreActivation.offer_override = 1
	_main._adopt_saved_ai_slots([2])
	assert_bool(_main.solo_ai_slots.has(2)).is_true()


func test_a_saved_automatic_game_opens_manual_without_the_core() -> void:
	var state := {RulesAutomation.SAVE_KEY: RulesAutomation.Level.AUTOMATIC}
	CoreActivation.offer_override = 0
	assert_int(RulesAutomation.playable(RulesAutomation.from_game_state(state))).is_equal(RulesAutomation.Level.MANUAL)
	var path := "user://e2e_core_mandatory_%d.nml" % Time.get_ticks_usec()
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	CoreActivation.offer_override = 1
	assert_int(_main.save_manager.save_game(path)).is_equal(OK)
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.MANUAL
	CoreActivation.offer_override = 0
	await _main.save_manager.load_game(path)
	DirAccess.remove_absolute(path)
	assert_int(_main.opr_army_manager.rules_automation).is_equal(RulesAutomation.Level.MANUAL)


func test_a_peers_automatic_proposal_is_declined_without_asking_the_player() -> void:
	_fake_net()
	CoreActivation.offer_override = 0
	_main._on_rules_proposal(2)
	assert_int(_cmds("decline_rules_automation")).is_equal(1)
	assert_object(_main._rules_agreement_card).is_null()
	assert_int(_off_lines()).is_equal(1)


func test_a_peers_automatic_proposal_asks_the_player_with_the_core() -> void:
	_fake_net()
	CoreActivation.offer_override = 1
	_main._on_rules_proposal(2)   # awaits the card; the call returns at once
	assert_int(_cmds("decline_rules_automation")).is_equal(0)
	assert_object(_main._rules_agreement_card).is_not_null()


func test_the_start_question_is_not_asked_without_the_core() -> void:
	_fake_net()
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.MANUAL
	CoreActivation.offer_override = 1
	assert_bool(_main._rules_start_question_due()).is_true()
	CoreActivation.offer_override = 0
	assert_bool(_main._rules_start_question_due()).is_false()
