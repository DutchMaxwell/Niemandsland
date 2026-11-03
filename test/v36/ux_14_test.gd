extends GdUnitTestSuite
## Rules 3.6 wave, row UX-14: from EPOCH_73_V36 on a Vanguard re-placement must end more than 9"
## (base edge to base edge) from every enemy unit that does not itself have Vanguard. Below 73
## nothing changes. The AI twin and its decision record are pinned here.

const NINE_IN := 9.0 * 0.0254

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0


func _unit(pid: int, positions: Array, rules: Array = []) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "p%d_%d" % [pid, positions.size()]
	u.unit_properties = {"player_id": pid, "name": "U%d" % pid, "quality": 4, "defense": 4,
		"special_rules": rules}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


## Deploy one AI Vanguard toward the objective with a single human model 6" short of that spot.
## Returns [gap_in, decisions].
func _vanguard_gap_at_epoch(epoch: int) -> Array:
	AiActRecorder.rules_epoch = epoch
	var human := _unit(1, [Vector3(0.0, 0.0, 0.02)])
	var van := _unit(2, [Vector3(0.0, 0.0, -0.5)], ["Vanguard"])
	van.unit_id = "van"
	van.unit_properties["name"] = "Drakesworn"
	van.unit_properties["game_system"] = "gf"
	van.unit_properties["faction_folder"] = "dark_elf_raiders"   # a book that fields Vanguard (registry gate)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {human.unit_id: human, van.unit_id: van}
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	var zone := Rect2(Vector2(-0.55, -0.6), Vector2(1.1, 0.3))
	solo.deploy_begin(zone, [Vector2(0.0, 0.10)], Callable(), Callable(), 777)
	var placed: GameUnit = solo.deploy_next_one()
	assert_object(placed).is_equal(van)
	var here: Vector3 = solo.unit_centre(van)
	var there: Vector3 = solo.unit_centre(human)
	var r_van: float = SoloController.model_base_radius_m(van.models[0] as ModelInstance)
	var r_hu: float = SoloController.model_base_radius_m(human.models[0] as ModelInstance)
	var gap := (Vector2(here.x, here.z).distance_to(Vector2(there.x, there.z)) - r_van - r_hu) / 0.0254
	return [gap, solo.decision_log.duplicate(true)]


func _vanguard_rule(decisions: Array) -> String:
	for rec in decisions:
		if str((rec as Dictionary).get("why", "")) == "vanguard free placement":
			return str((rec as Dictionary).get("rule", ""))
	return ""


func test_vanguard_keeps_a_six_inch_enemy_spot_at_epoch_72() -> void:
	var out := _vanguard_gap_at_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var gap := float(out[0])
	assert_float(gap).override_failure_message("below 3.6 the 6\" spot is legal, got %.2f\"" % gap) \
		.is_less(7.5)


func test_vanguard_refuses_a_six_inch_enemy_spot_at_epoch_73() -> void:
	var out := _vanguard_gap_at_epoch(AiActRecorder.EPOCH_73_V36)
	var gap := float(out[0])
	assert_float(gap).override_failure_message("a 3.6 Vanguard must end more than 9\" from a non-Vanguard enemy, got %.2f\"" % gap) \
		.is_greater(9.0)


func test_vanguard_decision_names_the_nine_inch_gap_at_epoch_73() -> void:
	var out := _vanguard_gap_at_epoch(AiActRecorder.EPOCH_73_V36)
	var rule := _vanguard_rule(out[1])
	assert_str(rule).override_failure_message("the 3.6 Vanguard line must name the gap, got: %s" % rule) \
		.contains("do not have Vanguard")


func test_vanguard_decision_keeps_the_free_placement_words_at_epoch_72() -> void:
	var out := _vanguard_gap_at_epoch(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var rule := _vanguard_rule(out[1])
	assert_str(rule).override_failure_message("below 3.6 the old words stay, got: %s" % rule) \
		.not_contains("do not have Vanguard")
