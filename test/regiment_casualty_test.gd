extends GdUnitTestSuite
## Regiment casualties: collect_members skips the dead, reform_from_unit closes the
## rear rank on a kill and re-opens it on a revive. Pure node math, no network.

const CELL := 0.025
const APPROX := Vector3(0.0001, 0.0001, 0.0001)


func _fps(n: int) -> Array:
	var a: Array = []
	for i in range(n):
		a.append(Vector2(CELL, CELL))
	return a


func _game_unit(n: int) -> GameUnit:
	var gu := GameUnit.new()
	gu.unit_id = "test_regiment"
	gu.unit_properties = {"base_width_mm": 25, "base_depth_mm": 25, "regiment_mode": true}
	for i in range(n):
		var mi := ModelInstance.new()
		var node := Node3D.new()
		add_child(node)
		auto_free(node)
		mi.node = node
		mi.is_alive = true
		mi.unit = gu
		gu.models.append(mi)
	return gu


func _tray() -> RegimentTray:
	var t := RegimentTray.new()
	add_child(t)
	return auto_free(t)


func test_collect_members_skips_dead() -> void:
	var gu := _game_unit(10)
	gu.models[9].is_alive = false
	var m := RegimentTray.collect_members(gu)
	assert_int(m.nodes.size()).is_equal(9)
	assert_int(m.footprints.size()).is_equal(9)


func test_reform_from_unit_closes_rank_on_casualty() -> void:
	var gu := _game_unit(10)
	var tray := _tray()
	var m0 := RegimentTray.collect_members(gu)
	tray.form(m0.nodes, m0.footprints, 5)
	gu.models[8].is_alive = false
	gu.models[9].is_alive = false
	tray.reform_from_unit(gu)

	var alive: Array = gu.get_alive_models()
	assert_int(alive.size()).is_equal(8)
	var offs := RegimentFormation.local_offsets(_fps(8), 5)
	assert_vector((alive[7].node as Node3D).position).is_equal_approx(offs[7], APPROX)


func test_revive_reopens_rank() -> void:
	var gu := _game_unit(10)
	var tray := _tray()
	var m0 := RegimentTray.collect_members(gu)
	tray.form(m0.nodes, m0.footprints, 5)
	gu.models[9].is_alive = false
	tray.reform_from_unit(gu)
	assert_int(gu.get_alive_models().size()).is_equal(9)

	gu.models[9].is_alive = true
	tray.reform_from_unit(gu)
	assert_int(gu.get_alive_models().size()).is_equal(10)
	var offs := RegimentFormation.local_offsets(_fps(10), 5)
	assert_vector((gu.models[9].node as Node3D).position).is_equal_approx(offs[9], APPROX)
