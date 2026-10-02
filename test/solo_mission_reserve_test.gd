extends GdUnitTestSuite
## NML-1010 D8a-1 — mission reserves on the controller: the queue leftover is set aside, each held
## unit rolls once per round from the mission's first round, arrives only on the winning die, and an
## ordinary Ambush unit's gate is untouched.

const IN2M := 0.0254
const BAND := Rect2(Vector2(-36.0 * IN2M, -24.0 * IN2M), Vector2(72.0 * IN2M, 12.0 * IN2M))


func _unit(pid: int, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4, "special_rules": []}
	var m := ModelInstance.new()
	m.is_alive = true
	m.unit = u
	var n := Node3D.new()
	add_child(n)
	m.node = n
	u.models.append(m)
	return u


func _controller(units: Array) -> SoloController:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	army.current_round = 1
	var sc: SoloController = auto_free(SoloController.new())
	add_child(sc)
	sc.setup(army, null, null, 1, 2)
	return sc


func test_the_queue_leftover_is_set_aside_and_arrives_only_on_the_winning_die() -> void:
	var units: Array = []
	for i in range(4):
		units.append(_unit(2, "R%d" % i))
	var sc := _controller(units)
	sc.deploy_begin(BAND, [Vector2.ZERO], Callable(), Callable(), 7)
	sc.deploy_place_n(2)   # the phase's half is down
	var left := sc.deploy_take_queue()
	assert_int(left.size()).is_equal(2)
	assert_int(sc.deploy_pending()).is_equal(0)
	sc.mission_reserve_set(left)
	for u in left:
		assert_bool(SoloController.unit_in_reserve(u)).is_true()
		assert_bool(SoloController.may_arrive_this_round(u, 2)).is_false()   # no roll yet
	var dice: Array = [3, 4]
	var die := func() -> int: return int(dice.pop_front())
	assert_that(sc.mission_arrival_rolls(2, 1, 2, 4, die)).is_equal([])   # before from_round: nobody rolls
	var rolled := sc.mission_arrival_rolls(2, 2, 2, 4, die)
	assert_int(rolled.size()).is_equal(2)
	assert_bool(bool(rolled[0]["arrives"])).is_false()   # a 3 on a 4+
	assert_bool(bool(rolled[1]["arrives"])).is_true()
	assert_bool(SoloController.may_arrive_this_round(rolled[0]["unit"], 2)).is_false()
	assert_bool(SoloController.may_arrive_this_round(rolled[1]["unit"], 2)).is_true()
	assert_bool(SoloController.may_arrive_this_round(rolled[1]["unit"], 3)).override_failure_message("the win is for round 2 only").is_false()


func test_an_ordinary_ambush_unit_keeps_its_own_gate() -> void:
	var u := _unit(2, "Amb")
	u.unit_properties["special_rules"] = ["Ambush"]
	assert_bool(SoloController.may_arrive_this_round(u, 1)).is_false()
	assert_bool(SoloController.may_arrive_this_round(u, 2)).is_true()


## D8a-2: where a winning mission reserve lands — wholly inside the arrival zone (the 12" frame),
## more than the enemy gate from enemy bases and more than the marker gate from the marker.
func test_a_mission_reserve_lands_in_the_zone_clear_of_the_enemy_and_the_marker() -> void:
	var u := _unit(2, "Res")
	u.unit_properties["ambush_reserve"] = true
	u.unit_properties["mission_reserve"] = true
	u.unit_properties["mission_arrival_round"] = 2
	var sc := _controller([u])
	sc.ambush_reserve = [u]
	var marker := Vector2(0.0, 22.0 * IN2M)   # in the frame's top strip
	sc._deploy_objectives = [marker]
	var enemy := [{"pos": Vector2(6.0 * IN2M, 22.0 * IN2M), "min_dist_m": 0.0, "pad_m": 0.016}]
	var frame := DeploymentCatalog.zone_test("edge_band_12", 2)
	sc.mission_arrival_set(frame, {"min_from_enemy_in": 12, "min_from_marker_in": 12})
	var zone := Rect2(Vector2(-36.0 * IN2M, -24.0 * IN2M), Vector2(72.0 * IN2M, 48.0 * IN2M))
	var arrived := sc.arrive_one_ambush_unit(zone, enemy, [], 2, [])
	assert_object(arrived).is_equal(u)
	var c := sc.unit_centre(u)
	var at := Vector2(c.x, c.z)
	assert_bool(bool(frame.call(at))).override_failure_message("inside the 12\" frame").is_true()
	assert_float(at.distance_to(enemy[0]["pos"]) / IN2M).is_greater(12.0)
	assert_float(at.distance_to(marker) / IN2M).is_greater(12.0)
	assert_bool(bool(u.unit_properties.get("mission_reserve", false))).override_failure_message("an ordinary unit now").is_false()
