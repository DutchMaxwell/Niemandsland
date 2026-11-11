extends GdUnitTestSuite
## Rules 3.6 wave, row UX-13: from EPOCH_73_V36 on a Scout spot must end more than 9" (base edge to
## base edge) from every enemy unit that is not a Scout. Below 73 nothing changes. The AI twin, the
## human's scout-phase words and the scout-phase order are all pinned here.

const NINE_IN := 9.0 * 0.0254


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


## The AI's only unit is a scout; the human's single non-scout model stands 8" beyond the objective
## spot. The objective inside both bands holds the scout on the same row at either epoch.
func _scout_gap_at_epoch(epoch: int) -> float:
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = epoch
	var human := _unit(1, [Vector3(0.0, 0.0, 0.1416)])
	var sc := _unit(2, [Vector3(0.0, 0.0, -0.5)])
	sc.unit_id = "sc"
	sc.unit_properties["name"] = "Pathfinders"
	sc.unit_properties["special_rules"] = ["Scout"]
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {human.unit_id: human, sc.unit_id: sc}
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	var zone := Rect2(Vector2(-0.55, -0.6), Vector2(1.1, 0.3))
	solo.deploy_begin(zone, [Vector2(0.0, -0.09)], Callable(), Callable(), 777)
	var placed: GameUnit = solo.deploy_next_scout()
	AiActRecorder.rules_epoch = epoch0
	assert_object(placed).is_equal(sc)
	var here: Vector3 = solo.unit_centre(sc)
	var there: Vector3 = solo.unit_centre(human)
	var r_sc: float = SoloController.model_base_radius_m(sc.models[0] as ModelInstance)
	var r_hu: float = SoloController.model_base_radius_m(human.models[0] as ModelInstance)
	return (Vector2(here.x, here.z).distance_to(Vector2(there.x, there.z)) - r_sc - r_hu) / 0.0254


func test_ai_scout_keeps_an_eight_inch_enemy_spot_at_epoch_72() -> void:
	var gap := _scout_gap_at_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	assert_float(gap).override_failure_message("below 3.6 the 8\" spot is legal, got %.2f\"" % gap) \
		.is_less_equal(9.0)


func test_ai_scout_refuses_an_eight_inch_enemy_spot_at_epoch_73() -> void:
	var gap := _scout_gap_at_epoch(AiActRecorder.EPOCH_73_V36)
	assert_float(gap).override_failure_message("a 3.6 scout must end more than 9\" from a non-Scout enemy, got %.2f\"" % gap) \
		.is_greater(9.0)


func test_human_scout_words_name_the_nine_inch_gap_at_epoch_73_only() -> void:
	var main_script: Script = load("res://scripts/main.gd")
	var names: Array = main_script.get_script_method_list().map(func(m: Dictionary) -> String: return str(m["name"]))
	assert_bool(names.has("solo_scout_band_words")).override_failure_message("main.gd has no scout words").is_true()
	if not names.has("solo_scout_band_words"):
		return
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var words73 := str(main_script.call("solo_scout_band_words"))
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var words72 := str(main_script.call("solo_scout_band_words"))
	AiActRecorder.rules_epoch = epoch0
	assert_str(words73).override_failure_message("the 3.6 scout words must name the 9\" gap, got: %s" % words73) \
		.contains("not Scouts")
	assert_str(words72).override_failure_message("below 3.6 there is no gap text, got: %s" % words72) \
		.not_contains("not Scouts")


func test_the_scout_phase_starts_with_the_round_one_first_turn() -> void:
	var main_script: Script = load("res://scripts/main.gd")
	var names: Array = main_script.get_script_method_list().map(func(m: Dictionary) -> String: return str(m["name"]))
	assert_bool(names.has("solo_scout_starts_with_first_turn")) \
		.override_failure_message("main.gd has no solo_scout_starts_with_first_turn() to pin the scout order") \
		.is_true()
	if not names.has("solo_scout_starts_with_first_turn"):
		return
	assert_bool(bool(main_script.call("solo_scout_starts_with_first_turn", true, true))).is_true()
	assert_bool(bool(main_script.call("solo_scout_starts_with_first_turn", false, true))).is_false()
	assert_bool(bool(main_script.call("solo_scout_starts_with_first_turn", false, false))).is_true()
