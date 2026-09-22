extends GdUnitTestSuite
## In-game HUD tool rail (UI handoff 22.09.): whichever tool is open, its panel must end left of the
## rail. The rail buttons grow with their labels; a fixed slot offset let the open panel cover their
## left edge ("easure", "errain" in the 22.09. captures).

const ToolRailScript := preload("res://scripts/hud/tool_rail.gd")


## A stand-in Main with the one node the rail reads: UI/HUD/DiceRollerPanel, sized like the real one.
func _fake_main() -> Node:
	var main: Node = auto_free(Node.new())
	var ui := Node.new()
	ui.name = "UI"
	main.add_child(ui)
	var hud := Control.new()
	hud.name = "HUD"
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(hud)
	var dice := PanelContainer.new()
	dice.name = "DiceRollerPanel"
	dice.custom_minimum_size = Vector2(320, 400)
	hud.add_child(dice)
	add_child(main)
	return main


func test_open_tool_panel_never_covers_the_rail() -> void:
	var main := _fake_main()
	var hud := main.get_node("UI/HUD") as Control
	var rail: Control = ToolRailScript.new()
	hud.add_child(rail)
	rail.setup(main)
	var dice := main.get_node("UI/HUD/DiceRollerPanel") as Control
	var host := rail.find_child("ToolPanelHost", true, false) as Control
	assert_object(host).is_not_null()
	if host == null:
		return
	for tool in ["dice", "measure", "terrain", "view"]:
		rail.call("_select", tool)
		await get_tree().process_frame
		await get_tree().process_frame
		var panel := dice if tool == "dice" else host
		assert_bool(panel.visible).is_true()
		var panel_rect := panel.get_global_rect()
		for key in ["dice", "measure", "terrain", "view"]:
			var btn := rail.find_child("Tool_" + key, true, false) as Control
			assert_object(btn).is_not_null()
			if btn == null:
				continue
			assert_bool(panel_rect.intersects(btn.get_global_rect())) \
				.override_failure_message("the open %s panel %s covers the %s rail button %s" % [tool, panel_rect, key, btn.get_global_rect()]) \
				.is_false()
