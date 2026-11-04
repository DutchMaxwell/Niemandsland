extends GdUnitTestSuite
## AIG-L6 (rules epoch 73): a charging model must never end across a wall. The gate pulls a straggler back
## toward its unit (charge coherency), and the retraced trail then closed on that spot with a straight leg
## from a trimmed point of the route - straight through the ruin wall the route had gone around. Fixture =
## the captured act of a gate game: a five-model charger standing in the corner of an L-shaped ruin, the
## target north of the wall, one model whose only legal route bends east around the wall end.
## Both feeders run the ONE executor (`execute_intent`): the AI's act and the player's Auto charge.

const IN2M := 0.0254
const BAND_IN := 9.0

## Ruin walls (table inches, 72x48 frame): west side, then the north side in two pieces.
const RUIN_WALLS_IN := [[[24.0, 36.0], [24.0, 33.0]], [[24.0, 33.0], [27.0, 33.0]], [[27.0, 33.0], [30.0, 33.0]]]
const CHARGER_IN := [[18.7986, 33.1899], [20.2375, 32.9685], [21.8079, 32.9816], [22.8573, 33.7419], [25.0947, 34.0595]]
const TARGET_IN := [23.0680, 30.4999]

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	MovementPlanner.fast_planner = false
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests - restore


func _world(p_in: Array) -> Vector3:
	return Vector3((float(p_in[0]) - 36.0) * IN2M, 0.0, (float(p_in[1]) - 24.0) * IN2M)


func _unit(pid: int, unit_name: String, positions_in: Array, base_mm: int) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_id = unit_name.to_lower().replace(" ", "_")
	unit.unit_properties = {"player_id": pid, "name": unit_name, "quality": 4, "defense": 4, "special_rules": [],
		"base_size_round": base_mm, "base_width_mm": base_mm, "base_depth_mm": base_mm}
	for p in positions_in:
		var model := ModelInstance.new()
		model.is_alive = true
		model.unit = unit
		model.wounds_current = 1
		model.wounds_max = 1
		model.properties = {"tough": 1}
		model.node = auto_free(Node3D.new())
		add_child(model.node)
		model.node.global_position = _world(p)
		unit.models.append(model)
	return unit


func _walls_world() -> Array:
	var walls: Array = []
	for w in RUIN_WALLS_IN:
		walls.append([Vector2(_world(w[0]).x, _world(w[0]).z), Vector2(_world(w[1]).x, _world(w[1]).z)])
	return walls


## Run the real charge through the one executor; returns [solo, charger, report].
func _charge(source: String) -> Array:
	var charger := _unit(2, "Berserker Throwers", CHARGER_IN, 32)
	var target := _unit(1, "Drained Leader", [TARGET_IN], 40)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {charger.unit_id: charger, target.unit_id: target}
	army.current_round = 4
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	solo.prewarm_enabled = false
	var walls := _walls_world()
	solo.walls_provider = func() -> Array: return walls
	var gap_in: float = float(solo.nearest_charge_vector(charger, target).get("gap", 0.0))
	var intent := ActIntent.make(charger, AiDecision.Action.CHARGE, target, solo.unit_centre(target), 0.0, false,
		{"charge_band_in": BAND_IN, "enemy_dist_in": gap_in, "source": source})
	var report: Dictionary = solo.execute_intent(intent, {})
	return [solo, charger, report]


## How many model paths of the last move cut across a wall (the L6 detector's own test: a leg that crosses).
func _wall_cuts(solo: SoloController) -> int:
	var cuts := 0
	var walls := _walls_world()
	for mp in solo.last_move_paths:
		var path: Array = (mp as Dictionary).get("path", [])
		var hit := false
		for i in range(1, path.size()):
			var a := Vector2((path[i - 1] as Vector3).x, (path[i - 1] as Vector3).z)
			var b := Vector2((path[i] as Vector3).x, (path[i] as Vector3).z)
			for w in walls:
				if MovementPlanner.segments_cross(a, b, w[0], w[1]):
					hit = true
		if hit:
			cuts += 1
	return cuts


func test_ai_charge_never_ends_a_model_across_a_wall_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var run := _charge("ai")
	assert_int(_wall_cuts(run[0] as SoloController)) \
		.override_failure_message("a charging model's path cuts across the ruin wall (AIG-L6)") \
		.is_equal(0)


func test_player_auto_charge_never_ends_a_model_across_a_wall_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var run := _charge("player")
	assert_int(_wall_cuts(run[0] as SoloController)) \
		.override_failure_message("the player's Auto charge path cuts across the ruin wall (AIG-L6)") \
		.is_equal(0)


## Control: below 73 the recorded rules play on byte for byte - the same board still cuts the wall.
func test_charge_below_epoch_73_is_untouched() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var run := _charge("ai")
	assert_int(_wall_cuts(run[0] as SoloController)).is_greater(0)
