extends GdUnitTestSuite
## 025 (contract v1.2): model fit must measure the named `body` node for HEIGHT + GROUNDING, so attached
## parts (a banner pole above, a downward-held bow below the feet) neither shrink the body nor float it.
## The combined AABB still drives the horizontal footprint. Legacy single-mesh models (no body node)
## keep the old combined-AABB behavior.


func _mgr() -> OPRArmyManager:
	return auto_free(OPRArmyManager.new())


func test_body_aabb_drives_height_and_grounding_combined_drives_footprint() -> void:
	var mgr := _mgr()
	# Combined spans y in [-0.5, 2.0] (a below-feet bow to -0.5 + a banner to 2.0); body spans [0, 1.0].
	# Small x/z footprint so the height scale wins (not footprint-capped) for both cases.
	# Tiny x/z footprint so the base-fit cap never binds and the HEIGHT scale decides both cases.
	var combined := AABB(Vector3(-0.0005, -0.5, -0.0005), Vector3(0.001, 2.5, 0.001))
	var body := AABB(Vector3(-0.0005, 0.0, -0.0005), Vector3(0.001, 1.0, 0.001))

	var fit_body: Dictionary = mgr._compute_model_fit(combined, 25, 1, 0.0, -1, false, body)
	var fit_legacy: Dictionary = mgr._compute_model_fit(combined, 25, 1, 0.0, -1, false, AABB())

	# Height from the BODY (1.0), not the combined (2.5) → a taller part no longer shrinks the body.
	# body height 1.0 vs combined 2.5 → 2.5x larger scale.
	assert_float(fit_body["scale"]).is_equal_approx(fit_legacy["scale"] * 2.5, fit_legacy["scale"] * 0.02)
	assert_bool(fit_body["scale"] > fit_legacy["scale"]).is_true()

	# Grounding on the BODY min-y (0) → y_offset == base-top 0.003, no float. Legacy grounds on the
	# below-feet part (-0.5) and floats (y_offset well above 0.003).
	assert_float(fit_body["y_offset"]).is_equal_approx(0.003, 0.0005)
	assert_bool(fit_legacy["y_offset"] > fit_body["y_offset"] + 0.003).is_true()


func test_get_body_aabb_measures_only_the_body_node() -> void:
	var mgr := _mgr()
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var body := MeshInstance3D.new()
	body.name = "body"
	body.mesh = BoxMesh.new()           # default 1x1x1 → AABB (-0.5,-0.5,-0.5)..(0.5,0.5,0.5)
	root.add_child(body)
	var banner := MeshInstance3D.new()
	banner.name = "banner"
	banner.mesh = BoxMesh.new()
	banner.position = Vector3(0, 2.0, 0)   # far above → must NOT be in the body AABB
	root.add_child(banner)

	var aabb: AABB = mgr._get_body_aabb(root)
	assert_float(aabb.size.y).is_equal_approx(1.0, 0.001)     # body only, not up to the banner
	assert_float(aabb.position.y).is_equal_approx(-0.5, 0.001)


func test_get_body_aabb_empty_when_no_body_node() -> void:
	var mgr := _mgr()
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var mesh := MeshInstance3D.new()
	mesh.name = "mesh0"                  # legacy single-mesh model, no `body` node
	mesh.mesh = BoxMesh.new()
	root.add_child(mesh)
	var aabb: AABB = mgr._get_body_aabb(root)
	assert_float(aabb.size.y).is_equal(0.0)   # empty → caller falls back to the combined aabb
