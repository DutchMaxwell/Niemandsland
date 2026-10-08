extends GdUnitTestSuite
## Plan 2.8: in an Automatic game each manual correction (wounds dialog, revive, radial Shaken toggle)
## writes ONE "Manual: ..." battle-log line through the parent's _log_rule_event. Manual games write
## nothing (today's behaviour). Rules-driven clears of Shaken (card_toggle_shaken from main) stay silent.

const OPRArmyManagerScript = preload("res://scripts/opr_army_manager.gd")


## Stands in for main: records every line the controller routes through _log_rule_event.
class LogHost:
	extends Node
	var lines: Array = []

	func _log_rule_event(_category: int, text: String, _ai: bool = false, _detail: String = "") -> void:
		lines.append(text)


## Records the wounds dialog open call; builds no UI.
class SpyWoundsDialog:
	extends WoundsDialog

	func open(_model: ModelInstance) -> void:
		pass


func _game_unit(n: int, tough: int, unit_id: String = "corr_reg") -> GameUnit:
	var gu := GameUnit.new()
	gu.unit_id = unit_id
	gu.unit_properties = {"base_width_mm": 25, "base_depth_mm": 25, "regiment_mode": true, "player_id": 2}
	for i in range(n):
		var mi := ModelInstance.new()
		var node := Node3D.new()
		add_child(node)
		auto_free(node)
		mi.node = node
		mi.is_alive = true
		mi.wounds_max = tough
		mi.wounds_current = tough
		mi.properties["tough"] = tough
		mi.unit = gu
		gu.models.append(mi)
	return gu


func _army_manager() -> OPRArmyManager:
	var om: Node3D = auto_free(Node3D.new())
	om.name = "ObjectManager"
	add_child(om)
	var am: OPRArmyManager = auto_free(OPRArmyManagerScript.new())
	am.name = "OPRArmyManager"
	om.add_child(am)
	am.object_manager = om
	return am


func _formed_regiment(am: OPRArmyManager, gu: GameUnit, frontage: int) -> void:
	var members := RegimentTray.collect_members(gu)
	var tray: RegimentTray = auto_free(RegimentTray.new())
	add_child(tray)
	tray.form(members.nodes, members.footprints, frontage)
	var regiment := Regiment.new(gu, tray, frontage)
	tray.set_meta("regiment", regiment)
	gu.unit_properties["frontage"] = frontage
	am.regiments[gu.unit_id] = regiment


## Controller parented under a LogHost (the climb in _log_manual_correction finds it there).
## Returns [controller, host]; the host frees the controller with it.
func _setup(am: OPRArmyManager) -> Array:
	var host: LogHost = auto_free(LogHost.new())
	add_child(host)
	var rc := RadialMenuController.new()
	rc.army_manager = am
	rc.wounds_dialog = auto_free(SpyWoundsDialog.new())
	host.add_child(rc)
	return [rc, host]


func test_wounds_edit_in_automatic_logs_exactly_one_line() -> void:
	var am := _army_manager()
	am.rules_automation = RulesAutomation.Level.AUTOMATIC
	var gu := _game_unit(2, 3)
	_formed_regiment(am, gu, 2)
	var parts := _setup(am)
	var rc: RadialMenuController = parts[0]
	var host: LogHost = parts[1]

	rc._open_wounds_dialog({"model_instance": gu.models[0]})
	gu.models[0].wounds_current = 2  # what the dialog's "-" button does before it emits
	rc._on_wounds_changed(gu.models[0], 2)

	assert_array(host.lines).is_equal(["Manual: P2 sets %s wounds 3 → 2" % gu.get_name()])


func test_wounds_edit_in_manual_logs_nothing() -> void:
	var am := _army_manager()
	am.rules_automation = RulesAutomation.Level.MANUAL
	var gu := _game_unit(2, 3)
	_formed_regiment(am, gu, 2)
	var parts := _setup(am)
	var rc: RadialMenuController = parts[0]
	var host: LogHost = parts[1]

	rc._open_wounds_dialog({"model_instance": gu.models[0]})
	gu.models[0].wounds_current = 2
	rc._on_wounds_changed(gu.models[0], 2)

	assert_array(host.lines).is_empty()


func test_shaken_toggle_in_automatic_logs_one_line() -> void:
	var am := _army_manager()
	am.rules_automation = RulesAutomation.Level.AUTOMATIC
	var gu := _game_unit(2, 3)
	_formed_regiment(am, gu, 2)
	var parts := _setup(am)
	var rc: RadialMenuController = parts[0]
	var host: LogHost = parts[1]

	rc._on_action_selected("toggle_shaken", {"game_unit": gu})
	assert_array(host.lines).is_equal(["Manual: P2 marks %s Shaken" % gu.get_name()])

	rc._on_action_selected("toggle_shaken", {"game_unit": gu})
	assert_array(host.lines).is_equal([
		"Manual: P2 marks %s Shaken" % gu.get_name(),
		"Manual: P2 clears %s Shaken" % gu.get_name(),
	])


func test_shaken_toggle_in_manual_logs_nothing() -> void:
	var am := _army_manager()
	am.rules_automation = RulesAutomation.Level.MANUAL
	var gu := _game_unit(2, 3)
	_formed_regiment(am, gu, 2)
	var parts := _setup(am)
	var rc: RadialMenuController = parts[0]
	var host: LogHost = parts[1]

	rc._on_action_selected("toggle_shaken", {"game_unit": gu})

	assert_array(host.lines).is_empty()


func test_rules_driven_shaken_clear_stays_silent_in_automatic() -> void:
	var am := _army_manager()
	am.rules_automation = RulesAutomation.Level.AUTOMATIC
	var gu := _game_unit(2, 3)
	_formed_regiment(am, gu, 2)
	gu.is_shaken = true
	var parts := _setup(am)
	var rc: RadialMenuController = parts[0]
	var host: LogHost = parts[1]

	rc.card_toggle_shaken(gu)  # main's round-start recovery path, not a manual tool

	assert_bool(gu.is_shaken).is_false()
	assert_array(host.lines).is_empty()


func test_revive_in_automatic_logs_one_line() -> void:
	var am := _army_manager()
	am.rules_automation = RulesAutomation.Level.AUTOMATIC
	var gu := _game_unit(2, 3)
	_formed_regiment(am, gu, 2)
	gu.models[1].is_alive = false
	gu.models[1].wounds_current = 0
	var parts := _setup(am)
	var rc: RadialMenuController = parts[0]
	var host: LogHost = parts[1]

	rc._revive_unit_models(gu)

	assert_bool(gu.models[1].is_alive).is_true()
	assert_array(host.lines).is_equal(["Manual: P2 revives %s" % gu.get_name()])
