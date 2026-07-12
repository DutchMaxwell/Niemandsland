extends GdUnitTestSuite
## Orienting a GLB on its OVAL base — MARKER-ONLY contract. The lengthwise (vehicle/mount) path
## rotates ONLY on an explicit per-entry manifest `long_axis` marker ("x"/"z", authoring truth);
## without a marker the legacy +Z convention holds (no turn on the standard depth-long oval),
## REGARDLESS of the AABB. Geometry never drives rotation: an XZ footprint cannot distinguish body
## LENGTH from WINGSPAN (a 43-faction sweep found live wide/winged models — avatars, greater
## mutated — that an aspect gate would have turned sideways). Walkers sit CROSSWISE ("quer"),
## deterministically. Round/square bases never rotate. Pure logic on a throwaway Node3D — Y-only
## rotation, so scale/y-offset are unaffected.

const OPRMgrScript := preload("res://scripts/opr_army_manager.gd")

## Decisively X-long footprint (a truck / laid-along-X vehicle blob shape).
const AABB_X_LONG := AABB(Vector3.ZERO, Vector3(2, 1, 1))
## Decisively Z-long footprint (a steed / hunting-beast blob shape).
const AABB_Z_LONG := AABB(Vector3.ZERO, Vector3(1, 1, 2))
## Near-square footprint (a biped hull, e.g. 0.672 x 0.642).
const AABB_SQUARE := AABB(Vector3.ZERO, Vector3(0.672, 0.5, 0.642))


func _mgr() -> Object:
	return auto_free(OPRMgrScript.new())


func _glb() -> Node3D:
	return auto_free(Node3D.new())


# ===== Vehicles/mounts, NO marker: legacy deterministic mapping — the AABB never matters =====
# Without a `long_axis` marker the model's long axis is assumed +Z, so the orientation depends ONLY
# on the base geometry; identical units are always consistent and live models stay byte-identical.

func test_no_marker_no_rotation_on_depth_long_oval_any_aabb() -> void:
	# Depth-long oval (depth 0.06 >= width 0.035, the AF standard): +Z already runs ALONG the long
	# axis → no turn, for an X-long, a Z-long and a near-square footprint alike.
	for aabb: AABB in [AABB_X_LONG, AABB_Z_LONG, AABB_SQUARE]:
		var g := _glb()
		_mgr()._align_to_oval_long_axis(g, aabb, true, 0.035, 0.06)
		assert_float(g.rotation.y).is_equal_approx(0.0, 0.001)


func test_no_marker_rotates_on_width_long_oval_any_aabb() -> void:
	# Width-long oval (width 0.06 > depth 0.035): turn 90° so +Z runs ALONG the long X axis — the
	# AABB shape is irrelevant here too.
	for aabb: AABB in [AABB_X_LONG, AABB_Z_LONG, AABB_SQUARE]:
		var g := _glb()
		_mgr()._align_to_oval_long_axis(g, aabb, true, 0.06, 0.035)
		assert_float(absf(g.rotation.y)).is_equal_approx(PI / 2.0, 0.001)


# ===== `long_axis` marker: authoring truth, beats any AABB =====

func test_marker_x_rotates_on_depth_long_oval_any_aabb() -> void:
	# "x" declares the model's length runs along X → on the standard depth-long oval it must turn
	# 90° to lie lengthwise — even when the AABB reads Z-long or near-square.
	for aabb: AABB in [AABB_X_LONG, AABB_Z_LONG, AABB_SQUARE]:
		var g := _glb()
		_mgr()._align_to_oval_long_axis(g, aabb, true, 0.035, 0.06, false, "x")
		assert_float(absf(g.rotation.y)).is_equal_approx(PI / 2.0, 0.001)


func test_marker_z_no_rotation_on_depth_long_oval_any_aabb() -> void:
	# "z" pins the legacy facing explicitly (the great-snakes coil: X-wide but +Z-facing) → no turn
	# on the depth-long oval, even for an X-long AABB.
	for aabb: AABB in [AABB_X_LONG, AABB_Z_LONG, AABB_SQUARE]:
		var g := _glb()
		_mgr()._align_to_oval_long_axis(g, aabb, true, 0.035, 0.06, false, "z")
		assert_float(g.rotation.y).is_equal_approx(0.0, 0.001)


func test_marker_z_rotates_on_width_long_oval() -> void:
	# "z" on a width-long oval: the declared Z-length must land on the long X axis → 90° turn
	# (the marker declares the MODEL's axis; the base geometry still picks the turn).
	var g := _glb()
	_mgr()._align_to_oval_long_axis(g, AABB_Z_LONG, true, 0.06, 0.035, false, "z")
	assert_float(absf(g.rotation.y)).is_equal_approx(PI / 2.0, 0.001)


# ===== Round bases and walkers =====

func test_round_base_never_rotates() -> void:
	var g := _glb()
	_mgr()._align_to_oval_long_axis(g, AABB_X_LONG, false, 0.032, 0.032)
	assert_float(g.rotation.y).is_equal_approx(0.0, 0.001)


func test_walker_quer_is_deterministic_on_depth_long_oval() -> void:
	# Depth-long oval (depth > width): rotate 90° to sit quer — same for ANY AABB, and the marker
	# does not apply to the crosswise path.
	for aabb: AABB in [AABB_X_LONG, AABB_Z_LONG]:
		var g := _glb()
		_mgr()._align_to_oval_long_axis(g, aabb, true, 0.035, 0.06, true)
		assert_float(absf(g.rotation.y)).is_equal_approx(PI / 2.0, 0.001)


func test_walker_no_rotation_on_width_long_oval() -> void:
	# Width-long oval (width > depth): model +Z already faces the short axis → no rotation, any AABB.
	for aabb: AABB in [AABB_X_LONG, AABB_Z_LONG]:
		var g := _glb()
		_mgr()._align_to_oval_long_axis(g, aabb, true, 0.06, 0.035, true)
		assert_float(g.rotation.y).is_equal_approx(0.0, 0.001)


func test_is_walker_name_heuristic() -> void:
	var mgr := _mgr()
	assert_bool(mgr._is_walker("Combat Walker")).is_true()
	assert_bool(mgr._is_walker("GREAT WALKER")).is_true()
	assert_bool(mgr._is_walker("Battle Tank")).is_false()
	assert_bool(mgr._is_walker("Heavy Gunship")).is_false()
