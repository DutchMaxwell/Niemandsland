extends GdUnitTestSuite
## Automodus 0.3.15 step 1.4: LandingPreview is a display-only node that shows one ghost disc per
## landing entry and one line per shooting pair. A second show() replaces the first; no physics.


func _landings(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"model": null, "pos": Vector3(i * 0.1, 0.0, 0.0), "radius_m": 0.0125})
	return out


func _lines(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"from": Vector3(i * 0.1, 0.0, 0.0), "to": Vector3(0.0, 0.0, 1.0)})
	return out


func _has_collision(node: Node) -> bool:
	if node is CollisionObject3D:
		return true
	for c in node.get_children():
		if _has_collision(c):
			return true
	return false


func test_landing_preview_shows_and_clears() -> void:
	var lp := LandingPreview.new()
	add_child(lp)
	auto_free(lp)
	lp.show_preview(_landings(3), _lines(2))
	assert_int(lp.ghost_count()).is_equal(3)
	assert_int(lp.line_count()).is_equal(2)
	lp.show_preview(_landings(1), _lines(0))
	assert_int(lp.ghost_count()).is_equal(1)
	assert_int(lp.line_count()).is_equal(0)
	lp.show_preview(_landings(3), _lines(2))
	assert_bool(_has_collision(lp)).is_false()
	lp.clear()
	assert_int(lp.ghost_count()).is_equal(0)
	assert_int(lp.line_count()).is_equal(0)
