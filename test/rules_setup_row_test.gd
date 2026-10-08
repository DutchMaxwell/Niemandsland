extends GdUnitTestSuite
## Rules-automation plan step 1.2 -- the table-setup "Rules" row. The row is behind
## RulesAutomation.UI_ENABLED (false until plan step 2.10); these tests force it on via the override seam.

const L := RulesAutomation.Level


func before_test() -> void:
	RulesAutomation.ui_enabled_override = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RulesAutomation.MENU_CFG))


func after_test() -> void:
	RulesAutomation.ui_enabled_override = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RulesAutomation.MENU_CFG))


func _dialog(online: bool) -> TableSizeDialog:
	var d := TableSizeDialog.new()
	d.online = online
	add_child(d)
	return auto_free(d)


func _mgr() -> OPRArmyManager:
	var mgr := OPRArmyManager.new()
	add_child(mgr)
	return auto_free(mgr)


func test_local_dialog_defaults_automatic_and_reports_the_pick() -> void:
	var d := _dialog(false)
	assert_int(d.selected_rules).is_equal(L.AUTOMATIC)
	d._select_rules(L.MANUAL)
	assert_int(d.selected_rules).is_equal(L.MANUAL)
	assert_int(d._rules_buttons.size()).is_equal(2)


func test_create_room_dialog_locks_manual() -> void:
	var d := _dialog(true)
	assert_int(d.selected_rules).is_equal(L.MANUAL)
	d._select_rules(L.AUTOMATIC)
	assert_int(d.selected_rules).is_equal(L.MANUAL)
	assert_bool(d._rules_buttons[L.AUTOMATIC].disabled).is_true()


func test_flag_off_hides_the_row_and_reports_manual() -> void:
	RulesAutomation.ui_enabled_override = false
	var d := _dialog(false)
	assert_int(d._rules_buttons.size()).is_equal(0)
	assert_int(d.selected_rules).is_equal(L.MANUAL)


func test_last_pick_is_remembered_and_keeps_the_biome() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("menu", "biome", "urban_ruins")
	cfg.save(RulesAutomation.MENU_CFG)
	RulesAutomation.remember_pick(L.MANUAL)
	assert_int(RulesAutomation.default_pick(false)).is_equal(L.MANUAL)
	assert_int(RulesAutomation.default_pick(true)).is_equal(L.MANUAL)
	cfg.load(RulesAutomation.MENU_CFG)
	assert_str(str(cfg.get_value("menu", "biome", ""))).is_equal("urban_ruins")
	RulesAutomation.remember_pick(L.AUTOMATIC)
	assert_int(RulesAutomation.default_pick(false)).is_equal(L.AUTOMATIC)


func test_pending_rules_value_is_applied_and_logged() -> void:
	var mgr := _mgr()
	var line := RulesAutomation.apply_table_setup({"size": Vector2(6, 4), "rules": L.AUTOMATIC}, mgr)
	assert_int(mgr.rules_automation).is_equal(L.AUTOMATIC)
	assert_str(line).is_equal("Rules automation: Automatic")
	assert_str(RulesAutomation.apply_table_setup({"rules": L.MANUAL}, mgr)).is_equal("Rules automation: Manual")
	assert_int(mgr.rules_automation).is_equal(L.MANUAL)


func test_no_rules_key_changes_nothing() -> void:
	var mgr := _mgr()
	mgr.rules_automation = L.AUTOMATIC
	assert_str(RulesAutomation.apply_table_setup({"size": Vector2(6, 4)}, mgr)).is_equal("")
	assert_int(mgr.rules_automation).is_equal(L.AUTOMATIC)


func test_flag_off_applies_but_logs_nothing() -> void:
	RulesAutomation.ui_enabled_override = false
	var mgr := _mgr()
	assert_str(RulesAutomation.apply_table_setup({"rules": L.AUTOMATIC}, mgr)).is_equal("")
