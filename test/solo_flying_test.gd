extends GdUnitTestSuite
## Flying (GF/AoF Core Rules 3.6.0 p.2): the unit may move through other units. The AI planner used to
## route a Flying unit around every other unit's spacing zone like a walker, so a wall of bases in its
## lane stopped it short. From EPOCH_75_TABLE_FIXES the zones only bind where it ends (like Traversal).

const IN_M := 0.0254

var _epoch0 := 0


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0


func _unit(id: String, rules: Array, base_mm: int, pid: int) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = id
	u.unit_properties = {"player_id": pid, "name": id, "quality": 4, "defense": 4, "base_size_round": base_mm,
		"special_rules": rules, "game_system": "gf"}
	return u


func _model(u: GameUnit, pos: Vector3) -> void:
	var m := ModelInstance.new()
	m.unit = u
	m.is_alive = true
	m.properties = {"tough": 1}
	m.node = auto_free(Node3D.new())
	add_child(m.node)
	m.node.global_position = pos
	u.models.append(m)


## A 10" move along +x; a wall of nine 160 mm enemy bases stands 5" ahead across the whole lane, the
## landing spot at 10" is clear of every base and its 1" spacing. Returns where the planner ends (inches).
func _plan_end_x(rules: Array) -> float:
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	var mover := _unit("mover", rules, 25, 1)
	_model(mover, Vector3.ZERO)
	var wall := _unit("wall", [], 160, 2)
	for i in range(9):
		_model(wall, Vector3(5.0 * IN_M, 0, (float(i) - 4.0) * 3.2 * IN_M))
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"mover": mover, "wall": wall}
	solo.army_manager = army
	var models: Array = solo._moving_models(mover)
	var out: Array = solo._plan_positions(mover, models, solo._positions_of(models), Vector3(10.0 * IN_M, 0, 0), false)
	return (out[0] as Vector3).x / IN_M


func test_flying_unit_moves_through_a_wall_of_units() -> void:
	assert_float(_plan_end_x(["Flying"])).is_greater(8.0)


func test_control_a_walker_stays_behind_the_wall() -> void:
	assert_float(_plan_end_x([])).is_less(2.0)


func test_at_epoch_72_a_flying_unit_stays_behind_the_wall() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_75_TABLE_FIXES - 1
	assert_float(_plan_end_x(["Flying"])).is_less(2.0)
