extends GdUnitTestSuite
## One core C-22 (EPOCH_87_WALKED_DANGEROUS, lane S1's soak, 17.11.): `SoloController._execute_move` counts a move's Dangerous test per model, on the
## route (`_dangerous_trail_flags`) or standing in the field at the start. It used to count on the PLANNED route, before the gate retraced each trail
## to its gated end. S1's soak had a Mega-Giant held at its start by a container (the published trail 0.002" long, no Dangerous cell on it) and the
## table still rolled 15 Dangerous dice, which the core, reading the walked trail, never asked for (a table over-count: the model never entered the
## field). From EPOCH_87_WALKED_DANGEROUS the count is redone on the walked route. The count itself moved into `_dangerous_count` (no change of rule):
## this suite pins that an ordinary crossing and a start inside the field still cost their test, at both epochs, and that the helper reads the flags it
## is given; the gate-held move is the soak volley itself (a Giant seed-12 game replays the same volley, once at 86, none at 87: see the PR).
## Real: SoloController and the planner's `execute_intent`, the move gate. Constructed: the unit, the board and its Dangerous band.

const IN2M := 0.0254

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	MovementPlanner.fast_planner = false
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0


func _giant(x: float, pid := 2, uid := "giant", tough := 15) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_id = uid
	unit.unit_properties = {"player_id": pid, "name": uid.capitalize(), "quality": 4, "defense": 3, "special_rules": [], "base_size_round": 100,
		"base_width_mm": 100, "base_depth_mm": 100}
	var model := ModelInstance.new()
	model.is_alive = true
	model.unit = unit
	model.wounds_current = tough
	model.wounds_max = tough
	model.properties = {"tough": tough}
	model.node = auto_free(Node3D.new())
	add_child(model.node)
	model.node.global_position = Vector3(x, 0.0, 0.0)
	unit.models.append(model)
	return unit


## `execute_intent` of an ADVANCE toward x = 10" for a unit standing at `start_in`, over a Dangerous band at x = 2"..4" that spans the lane (so there
## is no way around). Returns the Dangerous dice the move reported.
func _advance(start_in: float, band_lo_in: float, band_hi_in: float) -> int:
	var unit := _giant(start_in * IN2M)
	var foe := _giant(40.0 * IN2M, 1, "foe", 1)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {unit.unit_id: unit, foe.unit_id: foe}
	army.current_round = 2
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	solo.prewarm_enabled = false
	solo.terrain_type_at = func(p: Vector3) -> int:
		var x_in: float = p.x / IN2M
		return int(TerrainRules.TerrainType.DANGEROUS) if x_in >= band_lo_in and x_in <= band_hi_in and absf(p.z / IN2M) <= 40.0 \
			else int(TerrainRules.TerrainType.NONE)
	var intent := ActIntent.make(unit, AiDecision.Action.ADVANCE, foe, Vector3(10.0 * IN2M, 0.0, 0.0), 6.0, false, {"source": "ai", "enemy_dist_in": 40.0})
	var report := {}
	solo.execute_intent(intent, report)
	print("WALKED_DANGEROUS start=%s band=%s..%s last=%s report=%s paths=%s" % [start_in, band_lo_in, band_hi_in, solo.last_dangerous_dice,
		report.get("dangerous_dice", "-"), solo.last_move_paths.size()])
	return int(report.get("dangerous_dice", 0))


func test_a_crossing_costs_its_test_at_both_epochs() -> void:
	for epoch in [86, 87]:
		AiActRecorder.rules_epoch = epoch
		assert_int(await _advance(0.0, 2.0, 4.0)).override_failure_message("epoch %d: the walked route crosses the band" % epoch).is_equal(15)


func test_a_start_inside_the_field_costs_its_test_at_both_epochs() -> void:
	for epoch in [86, 87]:
		AiActRecorder.rules_epoch = epoch
		assert_int(await _advance(0.0, -1.0, 1.0)).override_failure_message("epoch %d: the model starts in the band" % epoch).is_equal(15)


func test_a_move_that_meets_no_band_costs_nothing_at_both_epochs() -> void:
	for epoch in [86, 87]:
		AiActRecorder.rules_epoch = epoch
		assert_int(await _advance(0.0, 30.0, 34.0)).override_failure_message("epoch %d: no band on the route" % epoch).is_equal(0)


## The helper reads the flags it is given: a flagged model costs its test, an unflagged one nothing, a start inside the field costs it anyway.
func test_the_count_reads_the_flags_it_is_given() -> void:
	AiActRecorder.rules_epoch = 87
	var unit := _giant(0.0)
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.terrain_type_at = func(_p: Vector3) -> int: return int(TerrainRules.TerrainType.NONE)
	var positions: Array = [unit.models[0].node.global_position]
	assert_int(int(solo._dangerous_count(unit, unit.models, positions, [true], false)["dice"])).is_equal(15)
	assert_int(int(solo._dangerous_count(unit, unit.models, positions, [false], false)["models"])).is_equal(0)
