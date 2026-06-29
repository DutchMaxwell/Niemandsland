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


# ===== project_drag_onto_facing (Shift-drag axis lock) =====


func test_project_drag_aligned_with_facing_passes_through() -> void:
	# Delta straight along +Z facing -> projected = same delta.
	var d := RegimentTray.project_drag_onto_facing(Vector3(0, 0, 1), Vector3(0, 0, 1))
	assert_vector(d).is_equal_approx(Vector3(0, 0, 1), APPROX)


func test_project_drag_perpendicular_to_facing_is_zero() -> void:
	# Delta sideways (X) onto +Z facing -> zero (no forward/back component).
	var d := RegimentTray.project_drag_onto_facing(Vector3(1, 0, 0), Vector3(0, 0, 1))
	assert_vector(d).is_equal_approx(Vector3.ZERO, APPROX)


func test_project_drag_diagonal_keeps_only_facing_component() -> void:
	# Delta (1,0,1) onto +Z facing -> (0,0,1) (the X component is dropped).
	var d := RegimentTray.project_drag_onto_facing(Vector3(1, 0, 1), Vector3(0, 0, 1))
	assert_vector(d).is_equal_approx(Vector3(0, 0, 1), APPROX)


func test_project_drag_negative_delta_goes_backward() -> void:
	# Backward drag (-Z) onto +Z facing -> -Z (allowed: player decides if it's a legal move).
	var d := RegimentTray.project_drag_onto_facing(Vector3(0, 0, -1), Vector3(0, 0, 1))
	assert_vector(d).is_equal_approx(Vector3(0, 0, -1), APPROX)


func test_project_drag_rotated_facing_uses_world_axis() -> void:
	# Facing +X: a +X delta passes, a +Z delta is dropped.
	var d1 := RegimentTray.project_drag_onto_facing(Vector3(1, 0, 0), Vector3(1, 0, 0))
	assert_vector(d1).is_equal_approx(Vector3(1, 0, 0), APPROX)
	var d2 := RegimentTray.project_drag_onto_facing(Vector3(0, 0, 1), Vector3(1, 0, 0))
	assert_vector(d2).is_equal_approx(Vector3.ZERO, APPROX)


func test_project_drag_degenerate_facing_falls_back_to_unconstrained() -> void:
	# A zero facing must not divide by zero — fall back to the original delta.
	var d := RegimentTray.project_drag_onto_facing(Vector3(1, 0, 1), Vector3.ZERO)
	assert_vector(d).is_equal_approx(Vector3(1, 0, 1), APPROX)


func test_project_drag_ignores_y_component_of_facing() -> void:
	# A facing with a Y component still projects on the XZ-plane only.
	var d := RegimentTray.project_drag_onto_facing(Vector3(0, 0, 1), Vector3(0, 5, 1))
	assert_vector(d).is_equal_approx(Vector3(0, 0, 1), APPROX)


# ===== nearest_quarter_turn (Ctrl+R snap) =====


func test_nearest_quarter_turn_zero_stays_zero() -> void:
	assert_float(RegimentTray.nearest_quarter_turn(0.0)).is_equal_approx(0.0, 0.0001)


func test_nearest_quarter_turn_near_zero_snaps_to_zero() -> void:
	# 0.2 rad (~11°) is closer to 0 than to π/2 (~1.57).
	assert_float(RegimentTray.nearest_quarter_turn(0.2)).is_equal_approx(0.0, 0.0001)


func test_nearest_quarter_turn_near_90_snaps_to_90() -> void:
	# 1.4 rad (~80°) is closer to π/2 than to 0.
	assert_float(RegimentTray.nearest_quarter_turn(1.4)).is_equal_approx(PI / 2.0, 0.0001)


func test_nearest_quarter_turn_near_180_snaps_to_180() -> void:
	assert_float(RegimentTray.nearest_quarter_turn(3.0)).is_equal_approx(PI, 0.0001)


func test_nearest_quarter_turn_near_270_snaps_to_270() -> void:
	assert_float(RegimentTray.nearest_quarter_turn(4.8)).is_equal_approx(3.0 * PI / 2.0, 0.0001)


func test_nearest_quarter_turn_full_circle_wraps_to_zero() -> void:
	# 2π + small offset snaps back to 0 (normalised to [0, 2π)).
	assert_float(RegimentTray.nearest_quarter_turn(TAU + 0.1)).is_equal_approx(0.0, 0.0001)


func test_nearest_quarter_turn_negative_angle_normalised() -> void:
	# -0.2 rad normalises to ~TAU-0.2, which is closer to 0 (or 2π) than to 3π/2.
	assert_float(RegimentTray.nearest_quarter_turn(-0.2)).is_equal_approx(0.0, 0.0001)
