extends GdUnitTestSuite
## Missions wave M2b — the deploy machinery accepts an ARBITRARY deployment
## zone as a probe callable (DeploymentCatalog.zone_test): outside the
## polygon counts as blocked ground for the spot search. An invalid callable
## is today's rect-only path — the parity fixture pins byte-identical
## placement; the half-zone fixture pins the constraint actually binding.

const IN2M := 0.0254
## 72" x 12" band on negative z — today's front-line AI zone in world metres.
const ZONE := Rect2(Vector2(-36.0 * IN2M, -24.0 * IN2M), Vector2(72.0 * IN2M, 12.0 * IN2M))


func _unit(pid: int, count: int, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	for _i in range(count):
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = Vector3.ZERO
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


## Deploy a fresh 2-unit AI army under `ztest` and return every model position.
func _deployed_positions(ztest: Callable, tag: String) -> Array:
	var units: Array = [_unit(2, 3, "A_" + tag), _unit(2, 3, "B_" + tag)]
	var sc := _controller(units)
	sc.deploy_army(ZONE, [Vector2(0.0, 0.0)], Callable(), Callable(), 11, ztest)
	var out: Array = []
	for u in units:
		for m in (u as GameUnit).models:
			out.append((m as ModelInstance).node.global_position)
	return out


## Parity: an always-true probe must reproduce the rect-only path EXACTLY —
## the wrapper may not perturb a single position when the zone never binds.
func test_always_true_probe_is_byte_identical_to_rect_path() -> void:
	var plain := _deployed_positions(Callable(), "plain")
	var probed := _deployed_positions(func(_p: Vector2) -> bool: return true, "probed")
	assert_int(probed.size()).is_equal(plain.size())
	for i in range(plain.size()):
		assert_that(probed[i]).is_equal(plain[i])


## The probe BINDS: a zone cut to the x>0 half must keep every deployed
## base out of the left half (spot search treats outside as blocked).
func test_probe_confines_deployment_to_the_allowed_half() -> void:
	var right_half := func(p: Vector2) -> bool: return p.x > 0.0
	var positions := _deployed_positions(right_half, "half")
	assert_int(positions.size()).is_equal(6)
	for p in positions:
		assert_float((p as Vector3).x).is_greater(0.0)


## DeploymentCatalog.zone_test speaks WORLD METRES: a point 18" inside
## player 1's front-line band passes, the mirror point in the enemy band
## fails (the inches conversion happens inside the closure).
func test_catalog_zone_test_probes_world_metres() -> void:
	var probe := DeploymentCatalog.zone_test("front_line", 1)
	assert_bool(probe.call(Vector2(0.0, -18.0 * IN2M))).is_true()
	assert_bool(probe.call(Vector2(0.0, 18.0 * IN2M))).is_false()
