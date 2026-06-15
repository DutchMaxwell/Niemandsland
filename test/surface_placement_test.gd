extends GdUnitTestSuite
## Surface-aware placement: models rest on the highest GROUND surface beneath their base
## (table top or a terrain prop like a container), never on other miniatures. Covers the
## pure decision (_pick_surface_y) and the live raycast (_surface_y_under) including the
## layer split (terrain on layer 1, miniatures on layer 2). Placement aid; no rule.

const ObjectManagerScript = preload("res://scripts/object_manager.gd")


# ===== _pick_surface_y (pure) =====


func test_pick_surface_y_returns_hit_height() -> void:
	var hit := {"position": Vector3(1.0, 0.063, 2.0)}
	assert_float(ObjectManagerScript._pick_surface_y(hit, 0.0)).is_equal_approx(0.063, 0.0001)


func test_pick_surface_y_falls_back_on_miss() -> void:
	assert_float(ObjectManagerScript._pick_surface_y({}, 0.0)).is_equal(0.0)


func test_pick_surface_y_falls_back_when_position_missing() -> void:
	# A malformed hit (collider but no position) must not crash — use the fallback.
	assert_float(ObjectManagerScript._pick_surface_y({"collider": null}, -1.0)).is_equal(-1.0)


# ===== _surface_y_under (live physics raycast) =====


func _ground_box(size: Vector3, pos: Vector3, layer: int) -> StaticBody3D:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	body.collision_layer = layer
	body.collision_mask = layer
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	return body


func _om_in_tree() -> Node3D:
	var om: Node3D = auto_free(ObjectManagerScript.new())
	add_child(om)
	return om


func test_rests_on_table_when_nothing_is_above() -> void:
	var om := _om_in_tree()
	# Table: a thin ground box on layer 1 with its top face at y = 0.
	add_child(_ground_box(Vector3(2, 0.5, 2), Vector3(0, -0.25, 0), 1))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_float(om._surface_y_under(Vector3(0.4, 0, -0.4))).is_equal_approx(0.0, 0.002)


func test_rests_on_a_terrain_box_top() -> void:
	var om := _om_in_tree()
	add_child(_ground_box(Vector3(2, 0.5, 2), Vector3(0, -0.25, 0), 1))  # table top at 0
	# Container-like prop on layer 1: 6x3" footprint-ish, 0.06 m tall, top at 0.06.
	add_child(_ground_box(Vector3(0.15, 0.06, 0.08), Vector3(0.5, 0.03, 0.5), 1))
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Over the box -> rest on its top; off to the side -> back on the table.
	assert_float(om._surface_y_under(Vector3(0.5, 0, 0.5))).is_equal_approx(0.06, 0.002)
	assert_float(om._surface_y_under(Vector3(-0.5, 0, -0.5))).is_equal_approx(0.0, 0.002)


func test_ignores_miniatures_on_layer_2() -> void:
	var om := _om_in_tree()
	add_child(_ground_box(Vector3(2, 0.5, 2), Vector3(0, -0.25, 0), 1))  # table top at 0
	# A "miniature" on layer 2 right under the probe must NOT be treated as ground —
	# models rest on terrain, never on each other.
	add_child(_ground_box(Vector3(0.03, 0.2, 0.03), Vector3(0.5, 0.1, 0.5), 2))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_float(om._surface_y_under(Vector3(0.5, 0, 0.5))).is_equal_approx(0.0, 0.002)
