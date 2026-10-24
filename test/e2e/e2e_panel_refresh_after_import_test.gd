extends GdUnitTestSuite
## Bug: the left-panel section holding the "Rules automation" switch never appeared after a real import.
## _on_opr_army_imported refreshed the panel deferred, BEFORE armies[player_id] was stored, so the refresh saw
## an empty dict and hid the section; the remote army stream never refreshed it at all.
##
## Real: scenes/main.tscn, the real import handler _on_opr_army_imported and the real remote-army handlers.

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


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _switch() -> CheckButton:
	for c in _main.rules_panel_box.get_children():
		if c is CheckButton and (c as CheckButton).text == "Rules automation":
			return c
	return null


func _assert_section_with_switch(what: String) -> void:
	assert_bool(_main.rules_panel_box.visible) \
		.override_failure_message("%s: the Rules section is hidden" % what).is_true()
	assert_object(_switch()) \
		.override_failure_message("%s: the Rules automation switch is missing" % what).is_not_null()


func test_one_local_import_shows_the_section_and_the_switch() -> void:
	var army := OPRApiClient.OPRArmy.new()
	army.name = "Test Army"
	await _main._on_opr_army_imported(army, 1, false)
	await E2EBoot.settle(get_tree())
	_assert_section_with_switch("after one local import")


func test_a_remote_army_alone_shows_the_section_and_the_switch() -> void:
	_main._on_remote_army_header(2, "Remote Army", 0)
	await _main._on_remote_army_complete(2, {})
	await E2EBoot.settle(get_tree())
	_assert_section_with_switch("after the remote army stream")
