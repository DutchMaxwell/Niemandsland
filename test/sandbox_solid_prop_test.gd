extends GdUnitTestSuite
## SandboxSolidProp: the grid Blocker's 6x3x2.5" profile as a draggable piece. Its collider IS the rule
## box, so a mini dropped on it rests on the 2.5" roof. Structure only, no physics scene.

const IN2M := 0.0254
const SOLID_KIND := 3   # ObjectManager.SandboxPropKind.BLOCKER (appended; saves carry the int)


func _solid() -> StaticBody3D:
	var script: Script = load("res://scripts/sandbox_solid_prop.gd")
	assert_object(script).is_not_null()
	var p: StaticBody3D = script.new()
	p.configure("blocker_6x3", SOLID_KIND, Vector2(6, 3))
	add_child(p)
	return auto_free(p)


func test_solid_is_selectable_movable_ground_terrain() -> void:
	var p := _solid()
	for g in ["selectable", "terrain", "sandbox_terrain"]:
		assert_bool(p.is_in_group(g)).is_true()
	assert_int(p.collision_layer).is_equal(1 | 4)   # ground (minis settle on it) + movable terrain
	assert_int(int(p.get_meta("prop_kind"))).is_equal(SOLID_KIND)   # save_manager stores this meta
	assert_vector(Vector2(p.footprint_inches)).is_equal(Vector2(6, 3))   # main._sandbox_terrain_shapes reads it


func test_collider_is_exactly_the_rule_box() -> void:
	var cols := _solid().find_children("*", "CollisionShape3D", false, false)
	assert_int(cols.size()).is_equal(1)
	var col := cols[0] as CollisionShape3D
	var size: Vector3 = (col.shape as BoxShape3D).size
	assert_vector(size).is_equal_approx(Vector3(6, 2.5, 3) * IN2M, Vector3.ONE * 0.001)
	assert_float(col.position.y + size.y * 0.5).is_equal_approx(2.5 * IN2M, 0.001)   # the roof, +-1 mm
	assert_vector(Vector3(col.position.x, 0.0, col.position.z)).is_equal(Vector3.ZERO)
