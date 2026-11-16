extends GdUnitTestSuite
## M-3 (maintainer 16.11.): the rules core (NmlCore) is MANDATORY for NACHTMAHR and Automatic play. The pure
## half: the one predicate with its test seam, the level this build can run, the remembered pick, the
## texts, and the Automatic switch of a bare main. The doors of the real scene are in
## test/e2e/e2e_core_mandatory_test.gd. The seam stands in for an absent core, so this suite needs no
## real core and runs the same with or without one.

const MainScript := preload("res://scripts/main.gd")
const L := RulesAutomation.Level
const CFG := "user://core_mandatory_test.cfg"


func before_test() -> void:
	RulesAutomation.ui_enabled_override = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func after_test() -> void:
	CoreActivation.offer_override = -1
	RulesAutomation.ui_enabled_override = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func _main() -> Node:
	var m: Node = MainScript.new()
	m.opr_army_manager = auto_free(OPRArmyManager.new())
	m.battle_log = auto_free(BattleLog.new())
	m.next_round_btn = Button.new()
	var box := VBoxContainer.new()
	box.add_child(m.next_round_btn)
	m.rules_panel_box = VBoxContainer.new()
	box.add_child(m.rules_panel_box)
	auto_free(box)
	add_child(box)
	auto_free(m)
	return m


func _lines(m: Node, needle: String) -> int:
	var n := 0
	for e in m.battle_log.entries():
		if str((e as Dictionary)["text"]).contains(needle):
			n += 1
	return n


func test_the_offer_follows_the_class_table_unless_the_seam_stands_in() -> void:
	assert_bool(CoreActivation.engine_offered()).is_equal(ClassDB.class_exists("NmlCore"))
	CoreActivation.offer_override = 0
	assert_bool(CoreActivation.engine_offered()).is_false()
	CoreActivation.offer_override = 1
	assert_bool(CoreActivation.engine_offered()).is_true()


func test_a_build_without_the_core_can_only_run_manual() -> void:
	CoreActivation.offer_override = 0
	assert_int(RulesAutomation.playable(L.AUTOMATIC)).is_equal(L.MANUAL)
	assert_int(RulesAutomation.playable(L.MANUAL)).is_equal(L.MANUAL)
	CoreActivation.offer_override = 1
	assert_int(RulesAutomation.playable(L.AUTOMATIC)).is_equal(L.AUTOMATIC)


func test_a_fresh_local_table_starts_manual_without_the_core() -> void:
	CoreActivation.offer_override = 1
	assert_int(RulesAutomation.default_pick(false, CFG)).is_equal(L.AUTOMATIC)
	RulesAutomation.remember_pick(L.AUTOMATIC, CFG)   # a pick made while the core was there
	CoreActivation.offer_override = 0
	assert_int(RulesAutomation.default_pick(false, CFG)).is_equal(L.MANUAL)


func test_the_forced_manual_is_not_remembered_as_the_players_choice() -> void:
	CoreActivation.offer_override = 0
	RulesAutomation.remember_pick(L.MANUAL, CFG)
	assert_bool(FileAccess.file_exists(CFG)).is_false()
	CoreActivation.offer_override = 1
	RulesAutomation.remember_pick(L.MANUAL, CFG)
	assert_bool(FileAccess.file_exists(CFG)).is_true()


func test_the_texts_say_what_is_off_and_what_still_works() -> void:
	assert_str(CoreLoadNotice.ENGINE_OFF_LINE).contains("NACHTMAHR")
	assert_str(CoreLoadNotice.ENGINE_OFF_LINE).contains("Automatic")
	assert_str(CoreLoadNotice.ENGINE_OFF_LINE).contains("Manual play only")
	assert_str(CoreLoadNotice.TEXT).contains("Manual play still works")
	# The MP driver and a support log match this mark; the wording after it may change, the mark may not.
	assert_str(CoreLoadNotice.boot_line(false)).contains("NmlCore NOT loaded")


func test_the_automatic_switch_is_refused_with_one_line_without_the_core() -> void:
	CoreActivation.offer_override = 0
	var m := _main()
	assert_bool(m.set_rules_automation(L.AUTOMATIC, "P1")).is_false()
	assert_int(m.opr_army_manager.rules_automation).is_equal(L.MANUAL)
	assert_int(_lines(m, CoreLoadNotice.ENGINE_OFF_LINE)).is_equal(1)
	assert_int(m.battle_log.entries().size()).is_equal(1)


func test_manual_stays_available_without_the_core() -> void:
	CoreActivation.offer_override = 0
	var m := _main()
	assert_bool(m.set_rules_automation(L.MANUAL, "P1")).is_true()
	assert_int(_lines(m, CoreLoadNotice.ENGINE_OFF_LINE)).is_equal(0)


func test_the_automatic_switch_works_with_the_core() -> void:
	CoreActivation.offer_override = 1
	var m := _main()
	assert_bool(m.set_rules_automation(L.AUTOMATIC, "P1")).is_true()
	assert_int(m.opr_army_manager.rules_automation).is_equal(L.AUTOMATIC)
	assert_int(_lines(m, CoreLoadNotice.ENGINE_OFF_LINE)).is_equal(0)
