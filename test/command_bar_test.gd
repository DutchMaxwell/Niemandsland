extends GdUnitTestSuite
## In-game HUD top bar (UI handoff 22.09., step 1): the enemy chip counts NACHTMAHR's units still on
## the table, and the bar's Battle Log button replaces the battle-log panel's collapsed top-centre tab.
## Display only — a stand-in Main carries just the state the bar reads.

const CommandBarScript := preload("res://scripts/hud/command_bar.gd")


class FakeUnit extends RefCounted:
	var alive := 0
	func _init(n: int) -> void:
		alive = n
	func get_alive_count() -> int:
		return alive


class FakeArmyManager extends RefCounted:
	var current_round := 2
	var game_phase: int = OPRArmyManager.GamePhase.PLAYING
	var units := {}   # player_id -> Array of FakeUnit
	func get_game_units_for_player(player_id: int) -> Array:
		return units.get(player_id, [])


class FakeMain extends Node:
	var solo_ai_slots := {}
	var opr_army_manager := FakeArmyManager.new()
	var solo_controller = null
	var network_manager = null
	var battle_log_panel: BattleLogPanel = null
	func _solo_ai_slot() -> int:
		return 2
	func _solo_final_round_active() -> bool:
		return false
	func next_round_button_label(_round_n: int, _final_round: bool) -> String:
		return "Next Round"


func _bar_for(main: FakeMain) -> Control:
	var bar: Control = auto_free(CommandBarScript.new())
	add_child(bar)
	bar.setup(main)
	return bar


func test_enemy_chip_counts_nachtmahr_units_still_on_the_table() -> void:
	var main: FakeMain = auto_free(FakeMain.new())
	main.solo_ai_slots = {2: true}
	main.opr_army_manager.units = {1: [FakeUnit.new(3)], 2: [FakeUnit.new(5), FakeUnit.new(0), FakeUnit.new(1)]}
	var bar := _bar_for(main)
	var chip := bar.find_child("EnemyChip", true, false) as Control
	assert_object(chip).is_not_null()
	if chip == null:
		return
	assert_bool(chip.visible).is_true()
	assert_str(bar.get("_enemy_chip_label").text).is_equal("NACHTMAHR · 2 UNITS LEFT")
	assert_str(bar.get("_turn").text).is_equal("SOLO")   # AI designated, controller not up yet

	main.opr_army_manager.units[2][2].alive = 0   # the last model of the second unit falls
	bar.refresh()
	assert_str(bar.get("_enemy_chip_label").text).is_equal("NACHTMAHR · 1 UNIT LEFT")


func test_enemy_chip_hidden_without_a_solo_opponent() -> void:
	var main: FakeMain = auto_free(FakeMain.new())   # hotseat / multiplayer: no AI slots
	main.opr_army_manager.units = {2: [FakeUnit.new(5)]}
	var bar := _bar_for(main)
	var chip := bar.find_child("EnemyChip", true, false) as Control
	assert_object(chip).is_not_null()
	if chip == null:
		return
	assert_bool(chip.visible).is_false()
	assert_str(bar.get("_turn").text).is_equal("HOTSEAT")


func test_battle_log_button_replaces_the_collapsed_tab() -> void:
	var main: FakeMain = auto_free(FakeMain.new())
	var panel: BattleLogPanel = auto_free(BattleLogPanel.new())
	add_child(panel)
	main.battle_log_panel = panel
	assert_bool(panel.visible).is_true()   # before the bar: the collapsed header tab shows
	var bar := _bar_for(main)
	assert_bool(panel.visible).is_false()  # the bar's button is the tab now

	var btn := bar.find_child("BattleLogBtn", true, false) as Button
	assert_object(btn).is_not_null()
	if btn == null:
		return
	btn.pressed.emit()
	assert_bool(panel.visible).is_true()   # open: header + body
	btn.pressed.emit()
	assert_bool(panel.visible).is_false()  # closed: no tab left behind
