extends GdUnitTestSuite
## Rules-automation plan step 1.3 -- the chip beside the round button and the in-game toggle (local games).
## Both sit behind RulesAutomation.ui_enabled(); the setter works regardless of the flag.

const MainScript := preload("res://scripts/main.gd")
const L := RulesAutomation.Level


func before_test() -> void:
	RulesAutomation.ui_enabled_override = true


func after_test() -> void:
	RulesAutomation.ui_enabled_override = false


func _main() -> Node:
	var m: Node = MainScript.new()
	m.opr_army_manager = auto_free(OPRArmyManager.new())
	m.battle_log = auto_free(BattleLog.new())
	m.next_round_btn = Button.new()
	var box := VBoxContainer.new()
	box.add_child(m.next_round_btn)
	m.solo_panel_box = VBoxContainer.new()
	box.add_child(m.solo_panel_box)
	auto_free(box)
	add_child(box)
	auto_free(m)
	return m


func _log_texts(m: Node) -> Array:
	return m.battle_log._entries.map(func(e: Dictionary) -> String: return str(e["text"]))


func test_change_is_applied_and_logged() -> void:
	var m := _main()
	assert_bool(m.set_rules_automation(L.AUTOMATIC, "P1")).is_true()
	assert_int(m.opr_army_manager.rules_automation).is_equal(L.AUTOMATIC)
	assert_array(_log_texts(m)).contains(["Rules automation: Automatic (changed by P1)"])


func test_refused_while_the_tray_is_busy() -> void:
	var m := _main()
	m._solo_tray_busy = true
	assert_bool(m.set_rules_automation(L.AUTOMATIC, "P1")).is_false()
	assert_int(m.opr_army_manager.rules_automation).is_equal(L.MANUAL)
	assert_int(m.battle_log._entries.size()).is_equal(0)


func test_locked_to_automatic_while_an_ai_slot_is_ticked() -> void:
	var m := _main()
	m.opr_army_manager.rules_automation = L.AUTOMATIC
	m.solo_ai_slots = {2: true}
	assert_bool(m.set_rules_automation(L.MANUAL, "P1")).is_false()
	assert_int(m.opr_army_manager.rules_automation).is_equal(L.AUTOMATIC)


func test_chip_text_follows_the_level_and_the_ai_slot() -> void:
	var m := _main()
	m._update_rules_chip()
	assert_str(m._rules_chip.text).is_equal("RULES: MANUAL")
	m.set_rules_automation(L.AUTOMATIC, "P1")
	assert_str(m._rules_chip.text).is_equal("RULES: AUTOMATIC")
	m.solo_ai_slots = {2: true}
	m._update_rules_chip()
	assert_str(m._rules_chip.text).is_equal("RULES: AUTOMATIC (NACHTMAHR)")
	assert_bool(m._rules_chip.visible).is_true()


func test_flag_off_hides_chip_and_toggle() -> void:
	RulesAutomation.ui_enabled_override = false
	var m := _main()
	m._update_rules_chip()
	m._add_rules_toggle()
	assert_bool(m._rules_chip == null or not m._rules_chip.visible).is_true()
	assert_int(m.solo_panel_box.get_child_count()).is_equal(0)


func test_toggle_is_added_and_locked_by_an_ai_slot() -> void:
	var m := _main()
	m._add_rules_toggle()
	var cb: CheckButton = m.solo_panel_box.get_child(0)
	assert_bool(cb.disabled).is_false()
	cb.button_pressed = true
	assert_int(m.opr_army_manager.rules_automation).is_equal(L.AUTOMATIC)
	m.solo_ai_slots = {2: true}
	m._add_rules_toggle()
	assert_bool((m.solo_panel_box.get_child(1) as CheckButton).disabled).is_true()
