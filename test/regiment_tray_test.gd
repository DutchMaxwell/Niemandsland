extends GdUnitTestSuite
## RegimentTray: re-parenting models into a rigid block and ranking them. The block
## moves/rotates via the scene graph (tray transform), models keep their local slots.

const CELL := 0.025
const APPROX := Vector3(0.0001, 0.0001, 0.0001)


func _model(pos: Vector3) -> Node3D:
	var m := Node3D.new()
	add_child(m)
	m.global_position = pos
	return auto_free(m)


func _fps(n: int) -> Array:
	var a: Array = []
	for i in range(n):
		a.append(Vector2(CELL, CELL))
	return a


func _tray() -> RegimentTray:
	var t := RegimentTray.new()
	add_child(t)
	return auto_free(t)


func test_form_reparents_models_and_ranks_them() -> void:
	var tray := _tray()
	var models: Array = []
	for i in range(10):
		models.append(_model(Vector3(randf() * 2.0 - 1.0, 0.0, randf() * 2.0 - 1.0)))
	tray.form(models, _fps(10), 5)

	for m in models:
		assert_object(m.get_parent()).is_equal(tray)
		assert_object(m.get_meta("regiment_tray")).is_equal(tray)

	var offs := RegimentFormation.local_offsets(_fps(10), 5)
	assert_vector(models[0].position).is_equal_approx(offs[0], APPROX)
	# World position is the tray transform applied to the local slot.
	assert_vector(models[0].global_position).is_equal_approx(tray.to_global(offs[0]), APPROX)


func test_rotating_tray_moves_models_as_one_block() -> void:
	var tray := _tray()
	var models: Array = []
	for i in range(5):
		models.append(_model(Vector3(i * 0.1, 0.0, 0.0)))
	tray.form(models, _fps(5), 5)
	var before: Vector3 = models[0].global_position

	tray.rotate_y(PI / 2.0)

	var offs := RegimentFormation.local_offsets(_fps(5), 5)
	# Local slot is unchanged; world position rotated about the tray origin.
	assert_vector(models[0].position).is_equal_approx(offs[0], APPROX)
	assert_bool(models[0].global_position.distance_to(before) > 0.001).is_true()
	assert_vector(models[0].global_position).is_equal_approx(tray.to_global(offs[0]), APPROX)


func test_facing_is_local_z() -> void:
	var tray := _tray()
	tray.rotation = Vector3.ZERO
	assert_vector(tray.facing_dir()).is_equal_approx(Vector3(0, 0, 1), APPROX)


func test_reform_with_fewer_models_reranks() -> void:
	var tray := _tray()
	var models: Array = []
	for i in range(10):
		models.append(_model(Vector3(i * 0.05, 0.0, 0.0)))
	tray.form(models, _fps(10), 5)
	# Simulate two casualties: re-lay the remaining 8.
	var survivors := models.slice(0, 8)
	tray.reform(survivors, _fps(8))
	var offs := RegimentFormation.local_offsets(_fps(8), 5)
	assert_vector(survivors[7].position).is_equal_approx(offs[7], APPROX)
	assert_int(tray.frontage).is_equal(5)
