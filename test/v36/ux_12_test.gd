extends GdUnitTestSuite
## Rules 3.6 wave, row UX-12: a Scout unit sets up at most 9" ahead of its own deployment zone from the
## rules 3.6 epoch on (73, EPOCH_73_V36); below it the band stays 12" (the _at_epoch_72 legs live in
## solo_controller_test.gd). The AI's band, its battle-log line and the human's scout-phase texts all
## read the same depth.

const NINE_IN := 9.0 * 0.0254
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")


func _unit(pid: int, positions: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "p%d_%d" % [pid, positions.size()]
	u.unit_properties = {"player_id": pid, "name": "U%d" % pid, "quality": 4, "defense": 4}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


func test_scout_band_reaches_nine_inches_toward_the_centre_at_epoch_73() -> void:
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	# Zone at the -Z edge (forward edge = end.y) and at the +Z edge (forward edge = position.y).
	var zone := Rect2(Vector2(-0.5, -0.6), Vector2(1.0, 0.3))
	var ext := SoloController.scout_extended_zone(zone, zone.end.y)
	var zone2 := Rect2(Vector2(-0.5, 0.3), Vector2(1.0, 0.3))
	var ext2 := SoloController.scout_extended_zone(zone2, zone2.position.y)
	AiActRecorder.rules_epoch = epoch0   # statics leak across gdUnit tests — restore before asserting
	assert_float(ext.end.y).is_equal_approx(zone.end.y + NINE_IN, 0.001)
	assert_float(ext.position.y).is_equal_approx(zone.position.y, 0.001)
	assert_float(ext2.position.y).is_equal_approx(zone2.position.y - NINE_IN, 0.001)
	assert_float(ext2.end.y).is_equal_approx(zone2.end.y, 0.001)


func test_ai_scout_lands_within_nine_inches_and_logs_its_band_at_epoch_73() -> void:
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var human := _unit(1, [Vector3(0, 0, 0.5)])
	var a := _unit(2, [Vector3(0, 0, -0.5)])
	a.unit_id = "a"
	var sc := _unit(2, [Vector3(0.2, 0, -0.5)])
	sc.unit_id = "sc"
	sc.unit_properties["name"] = "Pathfinders"
	sc.unit_properties["special_rules"] = ["Scout"]
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {human.unit_id: human, a.unit_id: a, sc.unit_id: sc}
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	# The objective sits 12" ahead of the zone: only the band, not the objective, holds the scout back.
	var zone := Rect2(Vector2(-0.55, -0.6), Vector2(1.1, 0.3))
	solo.deploy_begin(zone, [Vector2(0, 0)], Callable(), Callable(), 777)
	solo.deploy_next_one()
	var placed: GameUnit = solo.deploy_next_scout()
	AiActRecorder.rules_epoch = epoch0
	assert_object(placed).is_equal(sc)
	var c := solo.unit_centre(sc)
	assert_float(c.z).is_less_equal(zone.end.y + NINE_IN)
	var rule := ""
	for r in solo.decision_log:
		var d := r as Dictionary
		if str(d.get("kind", "")) == "deploy" and str(d.get("unit", "")) == "Pathfinders":
			rule = str(d.get("rule", ""))
	assert_str(rule).contains("Scout")
	assert_str(rule).contains("9\"")


func test_human_scout_phase_texts_name_nine_inches_at_epoch_73() -> void:
	var main_script: Script = load("res://scripts/main.gd")
	var names: Array = main_script.get_script_method_list().map(func(m: Dictionary) -> String: return str(m["name"]))
	assert_bool(names.has("solo_scout_band_words")) \
		.override_failure_message("main.gd has no solo_scout_band_words() for the scout-phase texts") \
		.is_true()
	if not names.has("solo_scout_band_words"):
		return
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var words73 := str(main_script.call("solo_scout_band_words"))
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var words72 := str(main_script.call("solo_scout_band_words"))
	AiActRecorder.rules_epoch = epoch0
	assert_str(words73).contains("9\"")
	assert_str(words72).contains("12\"")


## AIG-G2-L3: the Scout rule's whole effect is its DEPLOYMENT ORDER (scouts deploy after all other
## units), so the battle log never named it. At the start of play exactly ONE entry names the rule and
## the units it moved — no per-unit spam, and nothing when no unit carries it.
func test_scout_deployment_is_named_once_when_the_battle_starts(timeout := 120000) -> void:
	E2EBoot.arm_harness_mode()
	var root_before: Array = E2EBoot.root_children(get_tree())
	var runner: GdUnitSceneRunner = scene_runner(E2EBoot.MAIN_SCENE)
	var main: Node = runner.scene()
	await runner.simulate_frames(4)
	main.solo_ai_slots = {2: true}
	main._ensure_solo_controller()
	main._solo_batch = true
	var human_scout := E2EBoot.make_unit(main, 1, "Pathfinders", [Vector3(0, 0, 0.5)])
	human_scout.unit_properties["special_rules"] = ["Scout"]
	main.opr_army_manager.game_units[human_scout.unit_id] = human_scout
	var ai_scout := E2EBoot.make_unit(main, 2, "Outriders", [Vector3(0, 0, -0.5)])
	ai_scout.unit_properties["special_rules"] = ["Scout"]
	main.opr_army_manager.game_units[ai_scout.unit_id] = ai_scout
	var plain := E2EBoot.make_unit(main, 1, "Line Infantry", [Vector3(0, 0, 0.2)])
	main.opr_army_manager.game_units[plain.unit_id] = plain
	main._solo_deploy_fsm = {"phase": "scout", "human_out": true, "winner_is_ai": false}
	main._solo_deploy_phase_advance()
	var hits: Array = []
	for e in main.battle_log.entries():
		var text := str((e as Dictionary)["text"])
		if text.contains("Scout") and text.contains("Pathfinders") and text.contains("Outriders"):
			hits.append(text)
	E2EBoot.free_stray_root_nodes(get_tree(), root_before)
	assert_int(hits.size()) \
		.override_failure_message("the Scout deployment effect must be named exactly once in the battle log, got: %s" % str(hits)) \
		.is_equal(1)
