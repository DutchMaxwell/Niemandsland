extends GdUnitTestSuite
## The "Rules automation" switch lives in a left-panel section of its own ("Rules"), visible on every table
## with an army (local, online host and guest), not under the "NACHTMAHR:" heading. The multiplayer texts
## follow the REAL level instead of always saying "manual (no automation)".
##
## Real: scenes/main.tscn, the real import handler and remote-army handlers, the real status-line builder.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")


class FakeNet extends "res://scripts/network_manager.gd":
	func is_multiplayer_active() -> bool:
		return true

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _switch_in(box: Control) -> CheckButton:
	if box == null:
		return null
	for c in box.get_children():
		if c is CheckButton and (c as CheckButton).text == "Rules automation" and not c.is_queued_for_deletion():
			return c
	return null


func _rules_box() -> VBoxContainer:
	return _main.get_node_or_null("UI/HUD/LeftPanelScroll/LeftPanelVBox/RulesPanel") as VBoxContainer


func _assert_rules_section(what: String) -> void:
	var box := _rules_box()
	assert_object(box).override_failure_message("%s: there is no Rules section" % what).is_not_null()
	if box == null:
		return
	assert_bool(box.visible).override_failure_message("%s: the Rules section is hidden" % what).is_true()
	assert_object(_switch_in(box)).override_failure_message("%s: the switch is not in the Rules section" % what).is_not_null()
	assert_object(_switch_in(_main.solo_panel_box)).override_failure_message("%s: the switch is still under NACHTMAHR:" % what).is_null()


func test_a_local_import_puts_the_switch_in_the_rules_section() -> void:
	var army := OPRApiClient.OPRArmy.new()
	army.name = "Test Army"
	await _main._on_opr_army_imported(army, 1, false)
	await E2EBoot.settle(get_tree())
	_assert_rules_section("after a local import")


func test_a_remote_army_puts_the_switch_in_the_rules_section() -> void:
	_main._on_remote_army_header(2, "Remote Army", 0)
	await _main._on_remote_army_complete(2, {})
	await E2EBoot.settle(get_tree())
	_assert_rules_section("after the remote army stream")


func test_no_army_no_rules_section() -> void:
	_main._refresh_solo_panel()
	await E2EBoot.settle(get_tree())
	assert_object(_rules_box()).is_not_null()
	if _rules_box() != null:
		assert_bool(_rules_box().visible).is_false()


func test_online_deployment_text_follows_the_real_level() -> void:
	_main.network_manager = auto_free(FakeNet.new())
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_main._update_game_phase_ui()
	var text: String = _main._game_phase_status_label.text
	assert_str(text).override_failure_message("online Automatic still says: %s" % text).not_contains("no automation")
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.MANUAL
	_main._update_game_phase_ui()
	assert_str(_main._game_phase_status_label.text).contains("no automation")
