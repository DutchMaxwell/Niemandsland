extends GdUnitTestSuite
## NML-1010 D7a (controller half) — deployment phases: the share arithmetic, the points-first queue
## (R5a), and a phase's own zone for the AI's next placements.

const IN2M := 0.0254
const BAND := Rect2(Vector2(-36.0 * IN2M, -24.0 * IN2M), Vector2(72.0 * IN2M, 12.0 * IN2M))
const DISC := Rect2(Vector2(-12.0 * IN2M, -12.0 * IN2M), Vector2(24.0 * IN2M, 24.0 * IN2M))


func _unit(pid: int, uid: String, cost: int) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4, "special_rules": []}
	for _i in range(2):
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		m.node = n
		u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	opr.cost = cost
	u.source_type = "opr"
	u.source_data = opr
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


func test_the_share_arithmetic() -> void:
	assert_int(SoloController.phase_quota("half", 5, 0)).is_equal(2)   # floor(5 / 2), R5a
	assert_int(SoloController.phase_quota("half", 4, 0)).is_equal(2)
	assert_int(SoloController.phase_quota("all", 5, 0)).is_equal(5)
	assert_int(SoloController.phase_quota("rest", 5, 2)).is_equal(3)
	assert_int(SoloController.phase_quota("rest", 2, 5)).is_equal(0)
	assert_that(SoloController.deploy_phases_of({})).is_equal([])
	assert_that(SoloController.deploy_phases_of({"deploy_phases": [["defender", "half", "centre_disc_12"]]})).is_equal([["defender", "half", "centre_disc_12"]])


func test_a_half_phase_places_the_highest_points_first_and_a_later_phase_keeps_its_own_zone() -> void:
	var units: Array = []
	for i in range(5):
		units.append(_unit(2, "U%d" % i, [30, 90, 10, 70, 50][i]))
	var sc := _controller(units)
	sc.deploy_begin(BAND, [Vector2.ZERO], Callable(), Callable(), 11)
	assert_int(sc.deploy_main_total()).is_equal(5)
	sc.deploy_prioritise_by_points()
	sc.deploy_set_zone(DISC, DeploymentCatalog.zone_test("centre_disc_12", 2))
	var half := sc.deploy_place_n(SoloController.phase_quota("half", sc.deploy_main_total(), 0))
	var names: Array = []
	for u in half:
		names.append((u as GameUnit).unit_id)
	assert_that(names).is_equal(["U1", "U3"])   # 90 and 70 points
	for u in half:
		for m in (u as GameUnit).models:
			var p: Vector3 = (m as ModelInstance).node.global_position
			assert_float(Vector2(p.x, p.z).length()).is_less(12.0 * IN2M + 0.001)
	assert_int(sc.deploy_pending()).is_equal(3)
