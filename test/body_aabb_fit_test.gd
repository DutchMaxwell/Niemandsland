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


# 117: the mount-scaling bug. A composed / re-exported GLB (e.g. the mummified "skeleton beast" mount)
# can carry its scale + translation on an ANCESTOR node instead of the mesh node. _get_model_aabb must
# compose the FULL ancestor chain, not just the mesh's own transform, or it under-measures the model and
# the base-fit scales it grossly too large (table-filling) and grounds it wrong.
func test_get_model_aabb_composes_ancestor_scale_and_translation() -> void:
	var mgr := _mgr()
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	# Intermediate node carries a 5x scale + a downward shift — the mesh node itself is identity.
	var scaler := Node3D.new()
	scaler.scale = Vector3(5.0, 5.0, 5.0)
	scaler.position = Vector3(0.0, -2.0, 0.0)
	root.add_child(scaler)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()            # 1x1x1 → local AABB (-0.5..0.5)
	scaler.add_child(mesh)

	var aabb: AABB = mgr._get_model_aabb(root)
	# 1u box under a 5x ancestor → 5u, NOT the mesh-local 1u the old code returned.
	assert_float(aabb.size.x).is_equal_approx(5.0, 0.001)
	assert_float(aabb.size.y).is_equal_approx(5.0, 0.001)
	# Ancestor translation carried too: y in [5*(-0.5) - 2, 5*(0.5) - 2] = [-4.5, 2.5] → miny -4.5.
	assert_float(aabb.position.y).is_equal_approx(-4.5, 0.001)


# A flat single-mesh model (mesh is a direct child of the root) is UNAFFECTED by the fix: the composed
# transform equals the mesh's own transform, so legacy 1014 models keep byte-identical fits.
func test_get_model_aabb_flat_model_unchanged() -> void:
	var mgr := _mgr()
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.transform = Transform3D.IDENTITY.scaled(Vector3(2.0, 3.0, 2.0))
	root.add_child(mesh)

	var aabb: AABB = mgr._get_model_aabb(root)
	assert_float(aabb.size.x).is_equal_approx(2.0, 0.001)
	assert_float(aabb.size.y).is_equal_approx(3.0, 0.001)


# Pure fit math: an OVERSIZED mount (5.8u, like the skeleton beast) is scaled DOWN to fit its oval base
# exactly (tighter/short axis binds at OVAL_FOOTPRINT_RATIO), and its feet are grounded on the base top.
func test_oversized_mount_fits_base_and_is_grounded() -> void:
	var mgr := _mgr()
	# base 160x122 oval; footprint ~5.8u wide, feet ~2u below origin.
	var aabb := AABB(Vector3(-2.368, -1.953, -2.918), Vector3(4.736, 4.457, 5.837))
	var fit: Dictionary = mgr._compute_model_fit(aabb, 160, 18, 0.0, 122, false, AABB())
	var scale: float = float(fit["scale"])
	# Short axis (4.736) fits the base short side (122mm) exactly → source-scale-independent fit-to-base.
	assert_float(4.736 * scale).is_equal_approx(0.122, 0.001)
	# Long axis never overhangs the long side (160mm).
	assert_bool(5.837 * scale <= 0.160 + 0.0005).is_true()
	# Grounding invariant: the model's lowest point sits on the base top (y = 0.003).
	assert_float(float(fit["y_offset"]) + aabb.position.y * scale).is_equal_approx(0.003, 0.0005)


# Pure fit math: the fit-to-base result is INVARIANT to the source GLB scale — the same model exported 3x
# larger lands at the same rendered footprint. This is the defensive guarantee behind the _get_model_aabb
# fix: however a producer scales/composes a mount, the game fits it to its base.
func test_fit_is_invariant_to_source_scale() -> void:
	var mgr := _mgr()
	# A footprint-bound case (wide + short) on a 120x92 oval base.
	var small := AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 0.6, 1.0))
	var big := AABB(small.position * 3.0, small.size * 3.0)   # same model, exported 3x larger
	var fit_small: Dictionary = mgr._compute_model_fit(small, 120, 3, 0.0, 92, false, AABB())
	var fit_big: Dictionary = mgr._compute_model_fit(big, 120, 3, 0.0, 92, false, AABB())
	# 3x source → 1/3 scale, so the RENDERED footprint is identical either way.
	assert_float(float(fit_big["scale"])).is_equal_approx(float(fit_small["scale"]) / 3.0, float(fit_small["scale"]) * 0.01)
	var rendered_small: float = maxf(small.size.x, small.size.z) * float(fit_small["scale"])
	var rendered_big: float = maxf(big.size.x, big.size.z) * float(fit_big["scale"])
	assert_float(rendered_big).is_equal_approx(rendered_small, 0.001)
