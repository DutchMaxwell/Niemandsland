extends GdUnitTestSuite
## E2E — D22 (NML-984): a human bearer spends its once-per-game Speed Feat from the radial wheel.
## Before this the ONLY spender was NACHTMAHR (solo_controller.gd, flag `speed_feat_used_<rule>`):
## the permanent bands skip every `uses_per_game` entry, so a human's +2"/+4" had no path at all.
##
## Real: scenes/main.tscn, the radial controller's dispatch (`_on_action_selected`), the move-band
## reader (move_bands_for_props via the rings), the battle log, the NetworkManager receive path.
## Constructed: the bearer (orcs, AoF — the registry's "Speed Feat": Quick, +2"/+4", once per game).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const NetworkManagerScript := preload("res://scripts/network_manager.gd")
const INCH := 0.0254
const FLAG := "speed_feat_used_speed_feat"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _bearer(rules: Array = ["Speed Feat"]) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Boyz", [Vector3.ZERO, Vector3(1.0 * INCH, 0, 0)])
	u.unit_properties["special_rules"] = rules
	u.unit_properties["game_system"] = "aof"
	u.unit_properties["faction_folder"] = "orcs"
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _feat_lines() -> Array:
	var out: Array = []
	for e in _main.battle_log.entries():
		var t := str((e as Dictionary)["text"])
		if t.contains("Speed Feat"):
			out.append(t)
	return out


func _offered(u: GameUnit) -> RadialMenu.RadialMenuItem:
	for it in RadialMenu.solo_combat_items(u):
		if (it as RadialMenu.RadialMenuItem).id == "solo_speed_feat":
			return it
	return null


func _bands(u: GameUnit) -> Dictionary:
	return _main.movement_range_controller.bands_for_model(u.models[0].node)


func _advance_label(u: GameUnit) -> String:
	var root: Node = _main.movement_range_controller._active.get(u.models[0].node)
	var label := root.get_node_or_null("AdvanceLabel") as Label3D if root != null else null
	return label.text if label != null else "<no rings>"


func test_the_wheel_offers_the_feat_only_to_an_unspent_bearer() -> void:
	var u := _bearer()
	var it := _offered(u)
	assert_object(it).override_failure_message("no Speed Feat entry on the bearer's wheel").is_not_null()
	if it != null:
		assert_str(it.label).is_equal("Speed Feat (once per game)")
	assert_object(_offered(_bearer(["Fearless"]))).override_failure_message("offered to a unit without the feat").is_null()
	u.unit_properties[FLAG] = true
	assert_object(_offered(u)).override_failure_message("still offered after the feat was spent").is_null()


func test_one_click_spends_it_grows_the_rings_and_logs_the_ai_words() -> void:
	var u := _bearer()
	_main.movement_range_controller.toggle([u.models[0].node])   # the rings are up before the click
	assert_dict(_bands(u)).contains_key_value("advance", 6).contains_key_value("rush", 12)
	assert_str(_advance_label(u)).is_equal("Advance 6\"")
	_main.radial_menu_controller._on_action_selected("solo_speed_feat", {"game_unit": u})
	await E2EBoot.settle(get_tree())
	assert_bool(bool(u.unit_properties.get(FLAG, false))).override_failure_message("the once-per-game flag was not stamped").is_true()
	assert_dict(_bands(u)).contains_key_value("advance", 8).contains_key_value("rush", 16).contains_key_value("charge", 16)
	assert_str(_advance_label(u)).override_failure_message("the shown rings did not grow at once").is_equal("Advance 8\"")
	assert_array(_feat_lines()).contains_exactly(["Speed Feat: Boyz spends its once-per-game move bonus (+2\"/+4\")"])
	# A second click spends nothing more: once per game.
	_main.radial_menu_controller._on_action_selected("solo_speed_feat", {"game_unit": u})
	await E2EBoot.settle(get_tree())
	assert_dict(_bands(u)).contains_key_value("advance", 8).contains_key_value("rush", 16)
	assert_int(_feat_lines().size()).is_equal(1)


func test_an_activated_bearer_keeps_its_feat_and_is_told_why() -> void:
	var u := _bearer()
	u.activate(1)
	_main.radial_menu_controller._on_action_selected("solo_speed_feat", {"game_unit": u})
	await E2EBoot.settle(get_tree())
	assert_bool(bool(u.unit_properties.get(FLAG, false))).override_failure_message("an activated unit burned its feat").is_false()
	assert_dict(_bands(u)).contains_key_value("advance", 6)
	assert_array(_feat_lines()).contains_exactly(["Speed Feat: Boyz has already activated this round — the feat stays unspent"])


func test_the_spent_flag_travels_to_the_other_table() -> void:
	var u := _bearer()
	assert_bool(NetworkManagerScript.SYNCABLE_UNIT_PROPERTIES.has(FLAG)).override_failure_message("the flag may not cross the wire").is_true()
	assert_bool(NetworkManagerScript.SYNCABLE_UNIT_PROPERTIES.has("speed_feat_used_speed_feat_aura")).is_true()
	_main.network_manager.sync_unit_property(u.unit_id, FLAG, true)   # the peer's spend arrives
	assert_bool(bool(u.unit_properties.get(FLAG, false))).is_true()
	assert_object(_offered(u)).override_failure_message("the peer's spent feat is offered again here").is_null()
