extends GdUnitTestSuite
## The bundled low-detail looks of the free solid (maintainer D5: the bundled fallback ships first). Every look stays
## inside the 6x3x2.5" rule box (+-1 mm), reaches the rule height (top 2.4-2.5"), covers most of the footprint at the
## base (no materially empty blocking box), and leaves the collider alone: the rules are the same whatever it looks like.

const IN2M := 0.0254
const TOL := 0.04   # inches, ~1 mm


func _solid(look: String) -> StaticBody3D:
	var p := SandboxSolidProp.new()
	p.configure("blocker_6x3", 3, Vector2(6, 3), look)
	add_child(p)
	return auto_free(p)


func test_every_look_stays_inside_the_rule_box_and_reaches_its_height() -> void:
	assert_int(SandboxSolidProp.LOOKS.size()).is_greater_equal(2)
	for look in SandboxSolidProp.LOOKS:
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		var base_area := 0.0
		for m in _solid(look).find_children("*", "MeshInstance3D", false, false):
			var mi := m as MeshInstance3D
			var s: Vector3 = (mi.mesh as BoxMesh).size / IN2M
			var c: Vector3 = mi.position / IN2M
			lo = lo.min(c - s * 0.5)
			hi = hi.max(c + s * 0.5)
			if c.y - s.y * 0.5 <= 0.001:
				base_area += s.x * s.z
		assert_bool(lo.x >= -3.0 - TOL and hi.x <= 3.0 + TOL and lo.z >= -1.5 - TOL and hi.z <= 1.5 + TOL and lo.y >= -TOL) \
			.override_failure_message("%s leaves the rule box: %s .. %s" % [look, lo, hi]).is_true()
		assert_float(hi.y).override_failure_message("%s top" % look).is_between(2.4, 2.5 + TOL)
		assert_float(base_area / 18.0).override_failure_message("%s base cover" % look).is_greater_equal(0.7)


func test_the_collider_is_the_rule_box_whatever_the_look() -> void:
	for look in SandboxSolidProp.LOOKS:
		var cols := _solid(look).find_children("*", "CollisionShape3D", false, false)
		assert_int(cols.size()).is_equal(1)
		assert_vector((cols[0].shape as BoxShape3D).size).is_equal_approx(Vector3(6, 2.5, 3) * IN2M, Vector3.ONE * 0.001)
