extends GdUnitTestSuite

const IN2M := 0.0254


func _unit(id: String, pid: int, z_in: float, rules: Array = []) -> GameUnit:
	var unit: GameUnit = auto_free(GameUnit.new())
	unit.unit_id = id
	unit.unit_properties = {"player_id": pid, "name": id, "quality": 4, "defense": 4,
		"game_system": "gf",
		"special_rules": rules}
	var model := ModelInstance.new()
	model.unit = unit
	model.is_alive = true
	model.wounds_max = 3
	model.node = auto_free(Node3D.new())
	add_child(model.node)
	model.node.global_position = Vector3(0, 0, z_in * IN2M)
	unit.models.append(model)
	return unit


func _controller(ai: GameUnit, human: GameUnit) -> SoloController:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {ai.unit_id: ai, human.unit_id: human}
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	solo.terrain_type_at = func(p: Vector3) -> int:
		return TerrainRules.TerrainType.DANGEROUS if absf(p.z) < 2.0 * IN2M \
			else TerrainRules.TerrainType.NONE
	return solo


func test_hold_does_not_inherit_previous_units_dangerous_dice() -> void:
	var ai := _unit("Holder", 2, 12.0, ["Immobile"])
	var human := _unit("Human", 1, 24.0)
	var solo := _controller(ai, human)
	solo.last_dangerous_dice = 3
	assert_object(solo.activate_next_ai_unit()).is_equal(ai)
	var report := solo.last_report
	assert_int(int(report["action"])).is_equal(AiDecision.Action.HOLD)
	assert_int(int(report.get("dangerous_dice", -1))).is_equal(0)


func test_hold_in_dangerous_terrain_rolls_tough_dice_once() -> void:
	var ai := _unit("Holder", 2, 0.0, ["Immobile"])
	var human := _unit("Human", 1, 24.0)
	var solo := _controller(ai, human)
	assert_object(solo.activate_next_ai_unit()).is_equal(ai)
	var report := solo.last_report
	assert_int(int(report["action"])).is_equal(AiDecision.Action.HOLD)
	assert_int(int(report.get("dangerous_models", -1))).is_equal(1)
	assert_int(int(report.get("dangerous_dice", -1))).is_equal(3)


func test_shaken_idle_in_dangerous_terrain_still_reports_test() -> void:
	var ai := _unit("Shaken", 2, 0.0)
	ai.is_shaken = true
	var human := _unit("Human", 1, 24.0)
	var solo := _controller(ai, human)
	assert_object(solo.activate_next_ai_unit()).is_equal(ai)
	assert_bool(bool(solo.last_report.get("idle_shaken", false))).is_true()
	assert_int(int(solo.last_report.get("dangerous_dice", -1))).is_equal(3)


func test_flying_hold_uses_the_same_dangerous_exemption_as_a_move() -> void:
	var ai := _unit("Flier", 2, 0.0, ["Immobile", "Flying", "Dangerous Terrain"])
	var human := _unit("Human", 1, 24.0)
	var solo := _controller(ai, human)
	assert_object(solo.activate_next_ai_unit()).is_equal(ai)
	assert_int(int(solo.last_report.get("dangerous_dice", -1))).is_equal(0)
