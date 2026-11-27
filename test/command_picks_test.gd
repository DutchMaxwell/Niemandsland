extends GdUnitTestSuite
## PICK-CHOICE (D-PICK): the owner of an AoF: Skirmish command group picks up to two friendly units during deployment,
## each pick (or take-back) is one log line and lands in `command_picks`; battle start locks the picks and fills only
## the units the owner left without any (CR3). Real: the main scene, its deployment phase, the unit-property sync door.
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _lines: Array = []


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [2], 1)
	_main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.DEPLOYMENT)
	_lines = []
	_main.battle_log.entry_added.connect(_tap)


func after_test() -> void:
	CommandPicks.finish(_main)
	_main.battle_log.entry_added.disconnect(_tap)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _tap(e: Dictionary) -> void:
	_lines.append(str(e["text"]))


func _unit(player: int, name: String, x_in: float, rules: Array) -> GameUnit:
	return ParityTable._make_unit(_main, {"player": player, "name": name, "models": 2, "x_in": x_in, "z_step_in": 0.0,
		"quality": 4, "defense": 4, "tough": 1, "game_system": "aofs", "faction_folder": "beastmen", "rules": rules},
		{"name": "Spear", "range_in": 0, "attacks": 1, "count": 2, "rules": []})


func _picks(u: GameUnit) -> Array:
	return u.unit_properties.get("command_picks", [])


func test_the_owner_picks_two_takes_one_back_and_a_third_is_refused() -> void:
	var cmd := _unit(1, "Herd", 0.0, ["Banner"])
	var a := _unit(1, "Alpha", 3.0, [])
	var b := _unit(1, "Beta", 30.0, [])
	var c := _unit(1, "Gamma", 6.0, [])
	var foe := _unit(2, "Raider", 9.0, [])
	CommandPicks.toggle(_main, cmd, a)
	CommandPicks.toggle(_main, cmd, b)
	assert_array(_picks(cmd)).is_equal([a.unit_id, b.unit_id])
	assert_array(_lines).contains(["Command group: Herd's command will reach Alpha and Beta (chosen)"])
	assert_str(CommandPicks.toggle(_main, cmd, c)).override_failure_message("a third pick").is_equal("Herd already reaches two units - take one back first")
	assert_array(_picks(cmd)).is_equal([a.unit_id, b.unit_id])
	CommandPicks.toggle(_main, cmd, a)
	assert_array(_picks(cmd)).override_failure_message("taken back").is_equal([b.unit_id])
	for bad in [foe, cmd]:
		assert_str(CommandPicks.toggle(_main, cmd, bad)).is_equal("Herd's command reaches only another living friendly unit")
	assert_array(_picks(cmd)).is_equal([b.unit_id])
	CommandPicks.toggle(_main, cmd, b)
	assert_bool(cmd.unit_properties.has("command_picks")).override_failure_message("cleared = no key, CR3 fills it").is_false()
	assert_array(_lines).contains(["Command group: Herd's picks cleared - the two nearest at battle start"])


func test_only_the_owner_picks_and_only_at_deployment() -> void:
	var cmd := _unit(1, "Herd", 0.0, ["Banner"])
	var a := _unit(1, "Alpha", 3.0, [])
	var plain := _unit(1, "Plain", 6.0, [])
	var ai_cmd := _unit(2, "Warband", 20.0, ["Musician"])
	var ai_friend := _unit(2, "Raider", 23.0, [])
	assert_str(CommandPicks.toggle(_main, ai_cmd, ai_friend)).override_failure_message("the AI's unit").is_equal("only Warband's owner picks its command")
	assert_str(CommandPicks.toggle(_main, plain, a)).is_equal("only an AoF: Skirmish command group picks the units its command reaches")
	CommandPicks.toggle(_main, cmd, a)
	_main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.PLAYING)
	assert_array(_picks(cmd)).override_failure_message("battle start keeps the owner's pick, adds the nearest") \
		.is_equal([a.unit_id, plain.unit_id])
	assert_bool(_picks(ai_cmd).is_empty()).override_failure_message("CR3 fills the AI's").is_false()
	assert_str(CommandPicks.toggle(_main, cmd, plain)).override_failure_message("locked in play") \
		.is_equal("command picks are chosen at deployment and stay for the battle")
	assert_array(_picks(cmd)).is_equal([a.unit_id, plain.unit_id])


func test_a_single_pick_stands_and_battle_start_adds_the_nearest() -> void:
	var cmd := _unit(1, "Herd", 0.0, ["Banner"])
	var far := _unit(1, "Far", 30.0, [])
	var near := _unit(1, "Near", 4.0, [])
	_unit(1, "Next", 8.0, [])
	CommandPicks.toggle(_main, cmd, far)
	_main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.PLAYING)
	assert_array(_picks(cmd)).override_failure_message("exactly two: the pick + the nearest").is_equal([far.unit_id, near.unit_id])
	assert_array(_lines).contains(["Command group: Herd's Banner reaches Far (chosen) and Near (nearest)"])


## The presented card's visible button with `text`, or null.
func _card_button(gu: GameUnit, text: String) -> Button:
	_main.unit_dock.present_unit(gu)
	for b in _main.unit_dock.find_children("*", "Button", true, false):
		if (b as Button).text == text and (b as Button).is_visible_in_tree() and not b.is_queued_for_deletion():
			return b
	return null


func _click(gu: GameUnit) -> void:
	_main.object_manager.select_objects([(gu.models[0] as ModelInstance).node])


func test_the_card_arms_a_table_pick_and_clicks_pick_until_done() -> void:
	var cmd := _unit(1, "Herd", 0.0, ["Banner"])
	var a := _unit(1, "Alpha", 3.0, [])
	var b := _unit(1, "Beta", 30.0, [])
	var foe := _unit(2, "Raider", 9.0, [])
	assert_object(_card_button(a, "Command picks")).override_failure_message("no button off a command group").is_null()
	var arm := _card_button(cmd, "Command picks")
	assert_object(arm).override_failure_message("the command group's card offers it at deployment").is_not_null()
	if arm == null:
		return
	arm.pressed.emit()
	assert_object(CommandPicks.picking).is_same(cmd)
	assert_int(CommandPicks._rings.size()).override_failure_message("a ring on each friendly candidate").is_equal(2)
	_click(a)
	_click(b)
	assert_array(_picks(cmd)).override_failure_message("two clicks, two picks").is_equal([a.unit_id, b.unit_id])
	assert_object(_main.unit_dock._presented_unit).override_failure_message("the card stays on the owner").is_same(cmd)
	_click(foe)
	assert_object(CommandPicks.picking).override_failure_message("a foe's click ends the pick").is_null()
	assert_int(CommandPicks._rings.size()).is_equal(0)
	assert_array(_picks(cmd)).is_equal([a.unit_id, b.unit_id])
	_card_button(cmd, "Command picks").pressed.emit()
	_card_button(cmd, "Done picking").pressed.emit()
	assert_object(CommandPicks.picking).override_failure_message("Done picking ends it").is_null()
	_card_button(cmd, "Command picks").pressed.emit()
	_main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.PLAYING)
	assert_object(CommandPicks.picking).override_failure_message("battle start ends it").is_null()
	assert_str(CommandPicks.refusal(_main, cmd)).override_failure_message("no button in play (the card reads the refusal)").is_not_empty()
