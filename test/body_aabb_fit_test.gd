extends GdUnitTestSuite
## 025 (contract v1.2): model fit must measure the named `body` node for HEIGHT, GROUNDING **and the
## footprint cap**, so attached parts (a banner pole above, a downward-held bow below the feet, a
## protruding weapon) neither shrink/inflate the body nor float it — weapon VARIANTS of one unit render
## at identical size. Legacy single-mesh models (no body node) keep the old combined-AABB behavior.


func _mgr() -> OPRArmyManager:
	return auto_free(OPRArmyManager.new())


func test_body_aabb_drives_height_and_grounding() -> void:
	var mgr := _mgr()
	# Combined spans y in [-0.2, 2.3] (a below-feet bow tip to -0.2 + a banner to 2.3); body spans
	# [0, 1.0] — the bow offset is 0.2 of the body height, BELOW the rider-elevation threshold (0.25),
	# so this stays an infantry (self-body) fit. Tiny x/z so the base-fit cap never binds.
	var combined := AABB(Vector3(-0.0005, -0.2, -0.0005), Vector3(0.001, 2.5, 0.001))
	var body := AABB(Vector3(-0.0005, 0.0, -0.0005), Vector3(0.001, 1.0, 0.001))

	var fit_body: Dictionary = mgr._compute_model_fit(combined, 25, 1, 0.0, -1, false, body)
	var fit_legacy: Dictionary = mgr._compute_model_fit(combined, 25, 1, 0.0, -1, false, AABB())

	# Height from the BODY (1.0), not the combined (2.5) → a taller part no longer shrinks the body.
	# body height 1.0 vs combined 2.5 → 2.5x larger scale.
	assert_float(fit_body["scale"]).is_equal_approx(fit_legacy["scale"] * 2.5, fit_legacy["scale"] * 0.02)
	assert_bool(fit_body["scale"] > fit_legacy["scale"]).is_true()

	# Grounding on the BODY min-y (0) → y_offset == base-top 0.003, no float. Legacy grounds on the
	# below-feet part (-0.2) and floats (y_offset above 0.003).
	assert_float(fit_body["y_offset"]).is_equal_approx(0.003, 0.0005)
	assert_bool(fit_legacy["y_offset"] > fit_body["y_offset"]).is_true()


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


# QA r6 (Skeleton Chariot): a clearly ELEVATED body is a RIDER/CREW geometrically — the rider-anatomy
# fit engages WITHOUT is_mount (a mounted-by-default UNIT has no mount_name). Same geometry as the
# is_mount case above: identical result by construction.
func test_elevated_body_rider_fit_engages_without_is_mount() -> void:
	var mgr := _mgr()
	var combined := AABB(Vector3(-0.0005, -2.0, -0.0005), Vector3(0.001, 5.0, 0.001))
	var body := AABB(Vector3(-0.0005, 1.0, -0.0005), Vector3(0.001, 1.0, 0.001))
	var fit: Dictionary = mgr._compute_model_fit(combined, 40, 0, 0.0, -1, false, body, false)
	var scale: float = float(fit["scale"])
	# Rider-anatomy scale (28mm target on the body), NOT the 40mm base target.
	assert_float(body.size.y * scale).is_equal_approx(0.028, 0.0005)
	# Grounds on the COMBINED min-y (the wheels/steed), not the crew's feet.
	assert_float(float(fit["y_offset"]) + combined.position.y * scale).is_equal_approx(0.003, 0.0005)


# QA r6: the REAL champion-chariot-comp geometry (crew `body` at elevation ratio 0.387) run through the
# UNIT resolution path (is_mount=false, the unit's own 120x92 oval, Tough 6) — the stand-in for a
# correctly-baked Skeleton Chariot unit blob. The crew must land at trooper height, wheels on the base.
func test_chariot_unit_path_scales_crew_to_trooper_height() -> void:
	var mgr := _mgr()
	var combined := AABB(Vector3(-1.054, 0.0, -1.479), Vector3(2.098, 2.619, 3.880))
	var crew := AABB(Vector3(-0.662, 0.685, -0.904), Vector3(1.3038, 1.7712, 0.7816))
	var fit: Dictionary = mgr._compute_model_fit(combined, 120, 6, 0.0, 92, false, crew, false)
	var scale: float = float(fit["scale"])
	# Crew at the standard trooper height — independent of the 120mm base and Tough(6).
	assert_float(crew.size.y * scale * 1000.0).is_equal_approx(28.0, 0.5)
	# Wheels (combined min-y = 0) on the base top.
	assert_float(float(fit["y_offset"])).is_equal_approx(0.003, 0.0005)


# QA r6 threshold guard: a SELF-body with a below-feet part (the REAL giant#bow: bow tip 0.11 body
# heights below the feet) must NOT flip to the rider fit — it keeps the base-driven monster scale.
func test_self_body_with_below_feet_part_stays_base_driven() -> void:
	var mgr := _mgr()
	var combined := AABB(Vector3(-0.817, -0.154, -0.977), Vector3(1.508, 1.558, 1.872))
	var body := AABB(Vector3(-0.526, 0.0, -0.332), Vector3(1.0100, 1.4035, 0.7085))
	var fit: Dictionary = mgr._compute_model_fit(combined, 60, 12, 0.0, -1, false, body, false)
	var scale: float = float(fit["scale"])
	# Base-driven monster fit: 60mm x Tough(12) factor on the body → ~72.9mm, NOT the 28mm rider target.
	assert_float(body.size.y * scale * 1000.0).is_equal_approx(72.9, 1.0)
	# Infantry grounding: the BODY's feet (min-y 0) sit on the base top.
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


# QA r5 (producer forensics): weapon VARIANTS with IDENTICAL bodies must render at IDENTICAL scale.
# The cap used to measure the COMBINED box, so a protruding weapon changed the scale: snakemen
# #greatweapon (narrower combined X) rendered 1.15x LARGER; giant #bow/#royalbow (wider combined)
# rendered SMALLER. Real measured pilot AABBs; the body box drives the cap now.
func test_weapon_variants_with_same_body_get_identical_scale() -> void:
	var mgr := _mgr()
	# Snakemen on their 75x46 oval (Tough 3): base blob vs #greatweapon blob — same body.
	var snake_body := AABB(Vector3.ZERO, Vector3(1.0265, 1.7284, 1.0427))
	var snake_base: Dictionary = mgr._compute_model_fit(
		AABB(Vector3.ZERO, Vector3(1.2774, 1.7284, 1.7293)), 75, 3, 0.0, 46, false, snake_body)
	var snake_gw: Dictionary = mgr._compute_model_fit(
		AABB(Vector3.ZERO, Vector3(1.1140, 1.7674, 1.7060)), 75, 3, 0.0, 46, false, snake_body)
	assert_float(float(snake_gw["scale"])).is_equal_approx(float(snake_base["scale"]), 0.00001)
	# Skeleton Giant on a 60mm round base (Tough 12): #bow (wide combined) vs #heavy — same body.
	var giant_body := AABB(Vector3.ZERO, Vector3(1.0100, 1.4035, 0.7085))
	var giant_bow: Dictionary = mgr._compute_model_fit(
		AABB(Vector3.ZERO, Vector3(1.5079, 1.5577, 1.8720)), 60, 12, 0.0, -1, false, giant_body)
	var giant_heavy: Dictionary = mgr._compute_model_fit(
		AABB(Vector3.ZERO, Vector3(1.1777, 1.4035, 1.0594)), 60, 12, 0.0, -1, false, giant_body)
	assert_float(float(giant_bow["scale"])).is_equal_approx(float(giant_heavy["scale"]), 0.00001)


# Synthetic tall/wide-weapon-outside-body case: the weapon widens the combined box massively; the
# scale must not move (body-driven), only legacy no-body models react to the combined box.
func test_protruding_weapon_does_not_change_scale() -> void:
	var mgr := _mgr()
	var body := AABB(Vector3(-0.3, 0.0, -0.3), Vector3(0.6, 1.5, 0.6))
	var slim := AABB(Vector3(-0.3, 0.0, -0.3), Vector3(0.6, 1.5, 0.6))          # no weapon
	var wide := AABB(Vector3(-1.5, 0.0, -0.3), Vector3(3.0, 2.2, 0.6))          # long pike + banner
	var fit_slim: Dictionary = mgr._compute_model_fit(slim, 25, 0, 0.0, -1, false, body)
	var fit_wide: Dictionary = mgr._compute_model_fit(wide, 25, 0, 0.0, -1, false, body)
	assert_float(float(fit_wide["scale"])).is_equal_approx(float(fit_slim["scale"]), 0.00001)


# ===== fit_scale: optional per-entry manifest multiplier (scarab swarms at 0.5) =====

func test_fit_scale_is_multiplicative_and_regrounds() -> void:
	var mgr := _mgr()
	var aabb := AABB(Vector3(-0.5, -0.2, -0.5), Vector3(1.0, 1.2, 1.0))
	var normal: Dictionary = mgr._compute_model_fit(aabb, 40, 0, 0.0, -1, false, AABB(), false, 1.0)
	var halved: Dictionary = mgr._compute_model_fit(aabb, 40, 0, 0.0, -1, false, AABB(), false, 0.5)
	# Applied multiplicatively to the computed scale...
	assert_float(float(halved["scale"])).is_equal_approx(float(normal["scale"]) * 0.5, 0.00001)
	# ...and grounding is recomputed AFTER: the model's lowest point still sits on the base top.
	assert_float(float(halved["y_offset"]) + aabb.position.y * float(halved["scale"])) \
		.is_equal_approx(0.003, 0.0005)
	# Default 1.0 (and the omitted parameter) are byte-identical to the normal fit.
	var omitted: Dictionary = mgr._compute_model_fit(aabb, 40, 0, 0.0, -1, false, AABB(), false)
	assert_float(float(omitted["scale"])).is_equal(float(normal["scale"]))
	assert_float(float(omitted["y_offset"])).is_equal(float(normal["y_offset"]))


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
