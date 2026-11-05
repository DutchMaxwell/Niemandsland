extends GdUnitTestSuite
## AIG-L6b (rules epoch 73): a model never ends its move with its base on a container block. A charging hero
## climbed onto a 6"x3" container, came down its west edge and the gate's push-out (away from the block) was
## reverted by the wall clamp, so it ended 0.3 mm outside the edge with a 52 mm base overlapping the block.
## Fixture = the captured act 26 of an AI-G1 game (a ten-model charger with its joined hero, the board embedded):
## the live `execute_intent` path, the real planner, the real gate. "Just drop the clamp" would stand the push
## but break the charge band (the trail grows past 13"), so the band is asserted too.

const IN2M := 0.0254
const BAND_IN := 13.0
const HERO_R_M := 0.052

## The four containers (world metres: min x, min z, max x, max z) - the table paints each as CONTAINER ground and
## the planner sees their edges as 2.5" ledges.
const CONTAINERS := [[-0.2286, -0.1524, -0.0762, -0.0762], [0.0762, 0.0762, 0.2286, 0.1524],
	[0.0762, 0.4572, 0.2286, 0.5334], [-0.2286, -0.5334, -0.0762, -0.4572]]
## The ruin walls of the board, flat [ax, az, bx, bz] per segment (world metres).
const RUIN_WALLS := [
	[-0.6858, -0.5334, -0.6858, -0.6096], [-0.6858, -0.4572, -0.6858, -0.5334], [-0.5334, -0.381, -0.6096, -0.381],
	[-0.4572, -0.381, -0.5334, -0.381], [-0.4572, -0.5334, -0.4572, -0.4572], [-0.4572, -0.4572, -0.4572, -0.381],
	[0.6858, 0.5334, 0.6858, 0.6096], [0.6858, 0.4572, 0.6858, 0.5334], [0.5334, 0.381, 0.6096, 0.381],
	[0.4572, 0.381, 0.5334, 0.381], [0.4572, 0.5334, 0.4572, 0.4572], [0.4572, 0.4572, 0.4572, 0.381],
	[0.0762, -0.5334, 0.1524, -0.5334], [0.1524, -0.5334, 0.2286, -0.5334], [0.0762, -0.4572, 0.0762, -0.5334],
	[0.0762, -0.381, 0.0762, -0.4572], [0.2286, -0.3048, 0.1524, -0.3048], [0.3048, -0.3048, 0.2286, -0.3048],
	[0.3048, -0.4572, 0.3048, -0.381], [0.3048, -0.381, 0.3048, -0.3048],
	[-0.0762, 0.5334, -0.1524, 0.5334], [-0.1524, 0.5334, -0.2286, 0.5334], [-0.0762, 0.4572, -0.0762, 0.5334],
	[-0.0762, 0.381, -0.0762, 0.4572], [-0.2286, 0.3048, -0.1524, 0.3048], [-0.3048, 0.3048, -0.2286, 0.3048],
	[-0.3048, 0.4572, -0.3048, 0.381], [-0.3048, 0.381, -0.3048, 0.3048],
	[0.5334, -0.1524, 0.6096, -0.1524], [0.6096, -0.1524, 0.6858, -0.1524], [0.5334, -0.0762, 0.5334, -0.1524],
	[0.6858, 0.0, 0.6096, 0.0], [0.762, 0.0, 0.6858, 0.0], [0.762, -0.0762, 0.762, 0.0],
	[-0.5334, 0.1524, -0.6096, 0.1524], [-0.6096, 0.1524, -0.6858, 0.1524], [-0.5334, 0.0762, -0.5334, 0.1524],
	[-0.6858, 0.0, -0.6096, 0.0], [-0.762, 0.0, -0.6858, 0.0], [-0.762, 0.0762, -0.762, 0.0]]
## The charger's ten 32 mm models and the joined hero (104 mm base) at the start of the act, world metres (x, z).
const CHARGER_M := [[0.0703, 0.1878], [0.0773, 0.219], [0.1118, 0.2047], [0.0758, 0.2524], [0.1554, 0.1914],
	[0.0464, 0.2938], [0.1872, 0.2317], [0.1995, 0.2022], [0.2305, 0.1722], [0.2313, 0.2224]]
const HERO_M := [0.1554, 0.2721]
const TARGET_M := [-0.0776, 0.1157]

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	MovementPlanner.fast_planner = false
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests - restore


func _unit(pid: int, unit_name: String, positions: Array, base_mm: int) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_id = unit_name.to_lower().replace(" ", "_")
	unit.unit_properties = {"player_id": pid, "name": unit_name, "quality": 4, "defense": 4, "special_rules": [],
		"base_size_round": base_mm, "base_width_mm": base_mm, "base_depth_mm": base_mm}
	for p in positions:
		var model := ModelInstance.new()
		model.is_alive = true
		model.unit = unit
		model.wounds_current = 1
		model.wounds_max = 1
		model.properties = {"tough": 1}
		model.node = auto_free(Node3D.new())
		add_child(model.node)
		model.node.global_position = Vector3(float(p[0]), 0.0, float(p[1]))
		unit.models.append(model)
	return unit


## The board as the table's providers hand it out: walls (container edges + ruin walls), ledges, ground type.
func _board() -> Dictionary:
	var walls: Array = []
	var ledges: Array = []
	for r in CONTAINERS:
		var c: Array = [Vector2(r[0], r[1]), Vector2(r[0], r[3]), Vector2(r[2], r[3]), Vector2(r[2], r[1])]
		for k in range(4):
			var a: Vector2 = c[k]
			var b: Vector2 = c[(k + 1) % 4]
			walls.append([a, b])
			ledges.append({"a": a, "b": b, "dy_in": 2.5})
	for w in RUIN_WALLS:
		walls.append([Vector2(w[0], w[1]), Vector2(w[2], w[3])])
	return {"walls": walls, "ledges": ledges}


## Run the captured charge through the one executor; returns [solo, hero].
func _charge() -> Array:
	var board := _board()
	var charger := _unit(2, "Saurian Guardians", CHARGER_M, 32)
	var hero := _unit(2, "Great Mage Satloxatle", [HERO_M], 104)
	charger.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = charger
	var target := _unit(1, "Great Fire Elemental", [TARGET_M], 60)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {charger.unit_id: charger, hero.unit_id: hero, target.unit_id: target}
	army.current_round = 3
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	solo.prewarm_enabled = false
	solo.walls_provider = func() -> Array: return board["walls"]
	solo.ledges_provider = func() -> Array: return board["ledges"]
	solo.terrain_type_at = func(p: Vector3) -> int:
		for r in CONTAINERS:
			if Rect2(r[0], r[1], r[2] - r[0], r[3] - r[1]).has_point(Vector2(p.x, p.z)):
				return int(TerrainRules.TerrainType.CONTAINER)
		return int(TerrainRules.TerrainType.NONE)
	var gap_in: float = float(solo.nearest_charge_vector(charger, target).get("gap", 0.0))
	var intent := ActIntent.make(charger, AiDecision.Action.CHARGE, target, solo.unit_centre(target), 0.0, false,
		{"charge_band_in": BAND_IN, "enemy_dist_in": gap_in, "source": "ai"})
	solo.execute_intent(intent, {})
	return [solo, hero.models[0]]


func _hero_end(run: Array) -> Vector3:
	return (run[1] as ModelInstance).node.global_position


## The hero's published trail measured as the table measures a move: ground plus the climb it paid.
func _hero_arc_in(run: Array) -> float:
	var solo := run[0] as SoloController
	for mp in solo.last_move_paths:
		if (mp as Dictionary)["model"] == run[1]:
			var path: Array = (mp as Dictionary)["path"]
			return MovementPlanner.polyline_length(path) / IN2M + SoloController._trail_climb_in(path, _board()["ledges"])
	return INF


func test_hero_never_ends_with_its_base_on_a_container_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var run := _charge()
	var end := _hero_end(run)
	assert_bool((run[0] as SoloController)._world_forbidden(end, HERO_R_M)) \
		.override_failure_message("the hero ends with its 52 mm base on a container (%s) - AIG-L6b" % str(end)) \
		.is_false()


## Guards the shortcut: letting the gate's push-out stand also frees the base, but the trail then runs 15.4" for a
## 13" band. The pulled-back end must keep the arc (ground + climb) inside the charge band.
func test_the_pulled_back_hero_stays_inside_the_charge_band() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var arc := _hero_arc_in(_charge())
	assert_float(arc) \
		.override_failure_message("the hero's trail (ground + climb) is %.2f in, past the %.1f in charge band" % [arc, BAND_IN]) \
		.is_less_equal(BAND_IN + 0.01)


## rules-must-log: the model pulled back from the container says which book rule held it.
func test_a_model_pulled_back_from_a_container_is_named_in_the_battle_log() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var notes := str((_charge()[0] as SoloController).board_clamp_notes)
	assert_str(notes).contains("container")
	assert_str(notes).contains("Terrain height")


## Control: below 73 the recorded rules play on byte for byte - the same board still ends on the container.
func test_a_charge_below_epoch_73_is_untouched() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var run := _charge()
	assert_bool((run[0] as SoloController)._world_forbidden(_hero_end(run), HERO_R_M)).is_true()
	assert_str(str((run[0] as SoloController).board_clamp_notes)).not_contains("container")
