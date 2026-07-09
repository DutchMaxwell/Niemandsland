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


# Rider-constant mount fit (contract v1.2, QA r3 HARD RULE): a composed mount carries the RIDER as the
# `body` node. The scale makes the rider EXACTLY as tall as a standard 25mm foot trooper (28mm target),
# independent of the mount's base and Tough; GROUNDING is on the MOUNT's feet (the combined min-y,
# below the rider), so the mount stands on its base instead of the rider being buried down onto it.
func test_mount_scales_by_rider_but_grounds_on_mount_feet() -> void:
	var mgr := _mgr()
	# Combined y in [-2.0, 3.0]: the mount's feet at -2.0, the rider's head at 3.0. Rider `body` node y in
	# [1.0, 2.0] (it sits on the mount).
	var combined := AABB(Vector3(-0.0005, -2.0, -0.0005), Vector3(0.001, 5.0, 0.001))
	var rider := AABB(Vector3(-0.0005, 1.0, -0.0005), Vector3(0.001, 1.0, 0.001))
	var fit: Dictionary = mgr._compute_model_fit(combined, 40, 0, 0.0, -1, false, rider, true)
	var scale: float = float(fit["scale"])
	# The RIDER (1.0u) lands at the standard 25mm-trooper height target (28mm), NOT the 40mm base target.
	assert_float(rider.size.y * scale).is_equal_approx(0.028, 0.0005)
	# GROUNDING on the MOUNT's feet (combined min-y -2.0), NOT the rider body min-y (1.0): the whole
	# model's lowest point sits on the base top (0.003). Grounding on the rider would bury the mount.
	assert_float(float(fit["y_offset"]) + combined.position.y * scale).is_equal_approx(0.003, 0.0005)
	# The rider does NOT touch the base (its min-y sits well above the base top).
	assert_bool(float(fit["y_offset"]) + rider.position.y * scale > 0.003).is_true()


# QA r3 HARD RULE: the rider-constant scale is independent of the mount's BASE SIZE and of TOUGH, and
# equals the scale a foot trooper body of the same raw height gets — so rider world height == foot
# trooper world height, for every mount from the 60x35 steed to the 160x122 flying beast.
func test_rider_scale_is_base_and_tough_invariant_and_matches_foot_trooper() -> void:
	var mgr := _mgr()
	var raw_rider_h: float = 1.5
	var combined := AABB(Vector3(-1.0, -1.0, -1.5), Vector3(2.0, 4.0, 3.0))
	var rider := AABB(Vector3(-0.1, 1.5, -0.1), Vector3(0.2, raw_rider_h, 0.2))
	# Same fit for steed-sized (60x35, Tough 3) and flyingbeast-sized (160x122, Tough 18) mounts.
	var fit_steed: Dictionary = mgr._compute_model_fit(combined, 60, 3, 0.0, 35, false, rider, true)
	var fit_beast: Dictionary = mgr._compute_model_fit(combined, 160, 18, 0.0, 122, false, rider, true)
	assert_float(float(fit_beast["scale"])).is_equal_approx(float(fit_steed["scale"]), 0.00001)
	# And Tough alone changes nothing either (Tough 0 vs 18 on the same mount).
	var fit_t0: Dictionary = mgr._compute_model_fit(combined, 160, 0, 0.0, 122, false, rider, true)
	assert_float(float(fit_t0["scale"])).is_equal_approx(float(fit_beast["scale"]), 0.00001)
	# The rider's world height equals a foot trooper's: a 25mm-based, Tough-0 body of the SAME raw height
	# (tall/thin so its height binds) fits to the identical world height.
	var foot_body := AABB(Vector3(-0.0005, 0.0, -0.0005), Vector3(0.001, raw_rider_h, 0.001))
	var fit_foot: Dictionary = mgr._compute_model_fit(foot_body, 25, 0, 0.0, -1, false, AABB(), false)
	var rider_world_h: float = raw_rider_h * float(fit_steed["scale"])
	var foot_world_h: float = raw_rider_h * float(fit_foot["scale"])
	assert_float(rider_world_h).is_equal_approx(foot_world_h, 0.0005)


# QA r3: the rider-constant scale is EXACT — the footprint cap must NOT shrink it (a wide mount follows
# the model's own proportions; the defensive warning is the only footprint guard).
func test_rider_scale_not_footprint_capped() -> void:
	var mgr := _mgr()
	# A very WIDE mount (10u footprint) on a small 60x35 base: the old min(height, footprint) would crush
	# the scale far below rider-constant; rider mode must keep the exact rider-height scale.
	var combined := AABB(Vector3(-5.0, -1.0, -2.0), Vector3(10.0, 4.0, 4.0))
	var rider := AABB(Vector3(-0.1, 1.5, -0.1), Vector3(0.2, 1.5, 0.2))
	var fit: Dictionary = mgr._compute_model_fit(combined, 60, 3, 0.0, 35, false, rider, true)
	assert_float(rider.size.y * float(fit["scale"])).is_equal_approx(0.028, 0.0005)


# A fuzzy legacy mount GLB (is_mount but NO rider `body` node — e.g. a GF combat bike) keeps the
# base-driven fit: height target from the mount base (with Tough), min'd with the footprint cap.
func test_fuzzy_mount_without_body_keeps_base_driven_fit() -> void:
	var mgr := _mgr()
	# Tall/thin so height binds: a 2.0u bike on a 60x35 base, Tough 3 → target 60mm * 1.05 = 63mm.
	var combined := AABB(Vector3(-0.0005, 0.0, -0.0005), Vector3(0.001, 2.0, 0.001))
	var fit: Dictionary = mgr._compute_model_fit(combined, 60, 3, 0.0, 35, false, AABB(), true)
	assert_float(combined.size.y * float(fit["scale"])).is_equal_approx(0.063, 0.001)


# Contrast: the SAME combined+rider as INFANTRY (is_mount=false) grounds on the body's feet (rider min-y),
# so a mount flag is what flips grounding from body-feet to mount-feet.
func test_infantry_body_grounding_differs_from_mount() -> void:
	var mgr := _mgr()
	var combined := AABB(Vector3(-0.0005, -2.0, -0.0005), Vector3(0.001, 5.0, 0.001))
	var body := AABB(Vector3(-0.0005, 1.0, -0.0005), Vector3(0.001, 1.0, 0.001))
	var fit: Dictionary = mgr._compute_model_fit(combined, 40, 0, 0.0, -1, false, body, false)
	var scale: float = float(fit["scale"])
	# Infantry grounds on the BODY min-y (1.0) → the body's feet sit on the base top.
	assert_float(float(fit["y_offset"]) + body.position.y * scale).is_equal_approx(0.003, 0.0005)


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
