extends GdUnitTestSuite
## Solo/AI M1: the walking-skeleton controller. Pure logic (nearest-target selection, table-edge move
## clamp) is unit-tested directly; a light integration proves an AI unit advances toward the nearest
## human unit by its Advance distance and is marked activated.


func test_nearest_index_picks_the_closest_table_plane() -> void:
	var from := Vector3.ZERO
	assert_int(SoloController.nearest_index(from, [Vector3(10, 0, 0), Vector3(1, 0, 0), Vector3(5, 0, 0)])).is_equal(1)
	assert_int(SoloController.nearest_index(from, [])).is_equal(-1)
	# Y is ignored (table plane): the x=0.5 point is nearer than the tall x=0,z=2 one.
	assert_int(SoloController.nearest_index(from, [Vector3(0, 100, 2), Vector3(0.5, 0, 0)])).is_equal(1)


func test_axis_scale_clamps_a_move_at_the_table_edge() -> void:
	assert_float(SoloController._axis_scale(0.0, 0.3, 0.6)).is_equal_approx(1.0, 0.001)   # within → full
	assert_float(SoloController._axis_scale(0.0, 1.0, 0.6)).is_equal_approx(0.6, 0.001)   # overshoot → onto edge
	assert_float(SoloController._axis_scale(0.5, 0.0, 0.6)).is_equal_approx(1.0, 0.001)   # no move → full
	assert_float(SoloController._axis_scale(0.0, -1.0, 0.6)).is_equal_approx(0.6, 0.001)  # negative dir


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


func test_ai_unit_advances_toward_nearest_human_and_activates() -> void:
	var human := _unit(1, [Vector3(0, 0, 0)])
	var ai := _unit(2, [Vector3(0.5, 0, 0)])   # 0.5 m east of the human, inside a 4 ft table
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {human.unit_id: human, ai.unit_id: ai}
	army.current_round = 1

	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)

	var moved := solo.activate_next_ai_unit()
	assert_object(moved).is_equal(ai)
	assert_bool(ai.is_activated).is_true()
	# A weaponless unit counts as MELEE; at 0.5 m (~19.7") the enemy is beyond charge range (12") — the
	# official v3.5.0 tree RUSHES 12" = 0.3048 m toward the human at x=0 → x drops from 0.5 to ~0.1952.
	assert_float(ai.models[0].node.global_position.x).is_equal_approx(0.1952, 0.004)
	assert_int(int(solo.last_report["action"])).is_equal(AiDecision.Action.RUSH)
	# A second call finds no more eligible AI units.
	assert_object(solo.activate_next_ai_unit()).is_null()


func test_targeting_prefers_a_not_yet_activated_human_over_a_nearer_activated_one() -> void:
	# OPR Solo v3.5.0: nearest valid enemy, but prefer not-yet-activated.
	var near_active := _unit(1, [Vector3(0.35, 0, 0)])   # closer, but already acted
	near_active.is_activated = true
	near_active.unit_id = "human_active"
	var far_fresh := _unit(1, [Vector3(0.1, 0, 0)])      # farther from the AI, not yet activated
	far_fresh.unit_id = "human_fresh"
	var ai := _unit(2, [Vector3(0.5, 0, 0)])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {near_active.unit_id: near_active, far_fresh.unit_id: far_fresh, ai.unit_id: ai}
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	assert_object(solo.nearest_human_unit(ai)).is_equal(far_fresh)
	# If ALL humans are activated, fall back to the nearest.
	far_fresh.is_activated = true
	assert_object(solo.nearest_human_unit(ai)).is_equal(near_active)


func test_run_ai_turn_activates_every_eligible_ai_unit() -> void:
	var human := _unit(1, [Vector3(0, 0, 0)])
	var ai1 := _unit(2, [Vector3(0.4, 0, 0)])
	var ai2 := _unit(2, [Vector3(0, 0, 0.4)])
	ai2.unit_id = "ai2"
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {human.unit_id: human, ai1.unit_id: ai1, ai2.unit_id: ai2}
	army.current_round = 1

	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)

	assert_int(solo.run_ai_turn()).is_equal(2)
	assert_bool(ai1.is_activated).is_true()
	assert_bool(ai2.is_activated).is_true()
