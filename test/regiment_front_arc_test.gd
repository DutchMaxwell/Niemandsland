extends GdUnitTestSuite
## Regiments front arc: LosRules.is_in_front_arc (pure) + RegimentTray.front_arc_contains
## (the tray's facing applied). The front arc is the 180° hemisphere ahead of +Z.

const APPROX := 0.0001


# ===== LosRules.is_in_front_arc (pure 2D) =====

func test_target_straight_ahead_is_in_arc() -> void:
	# Facing +Y (2D), target ahead.
	assert_bool(LosRules.is_in_front_arc(Vector2.ZERO, Vector2(0, 1), Vector2(0, 5))).is_true()


func test_target_behind_is_out_of_arc() -> void:
	assert_bool(LosRules.is_in_front_arc(Vector2.ZERO, Vector2(0, 1), Vector2(0, -5))).is_false()


func test_forty_five_degrees_is_in_default_arc() -> void:
	# 45° off the facing is inside the default 90° half-angle (180° front).
	assert_bool(LosRules.is_in_front_arc(Vector2.ZERO, Vector2(0, 1), Vector2(3, 3))).is_true()


func test_one_thirty_five_degrees_is_out() -> void:
	assert_bool(LosRules.is_in_front_arc(Vector2.ZERO, Vector2(0, 1), Vector2(3, -3))).is_false()


func test_narrow_arc_excludes_the_sides() -> void:
	# With a 45° half-angle, a target 60° off-facing is out.
	var target := Vector2(sin(deg_to_rad(60.0)), cos(deg_to_rad(60.0))) * 5.0
	assert_bool(LosRules.is_in_front_arc(Vector2.ZERO, Vector2(0, 1), target, 45.0)).is_false()


func test_degenerate_inputs_return_true() -> void:
	assert_bool(LosRules.is_in_front_arc(Vector2.ZERO, Vector2(0, 1), Vector2.ZERO)).is_true()
	assert_bool(LosRules.is_in_front_arc(Vector2.ZERO, Vector2.ZERO, Vector2(0, 5))).is_true()


# ===== RegimentTray.front_arc_contains (facing applied) =====

func _tray() -> RegimentTray:
	var t := RegimentTray.new()
	add_child(t)
	return auto_free(t)


func test_tray_facing_plus_z_sees_in_front_not_behind() -> void:
	var tray := _tray()
	tray.rotation = Vector3.ZERO  # facing +Z
	assert_vector(tray.facing_2d()).is_equal_approx(Vector2(0, 1), Vector2(APPROX, APPROX))
	assert_bool(tray.front_arc_contains(Vector3(0, 0, 2))).is_true()
	assert_bool(tray.front_arc_contains(Vector3(0, 0, -2))).is_false()


func test_rotating_tray_flips_the_front_arc() -> void:
	var tray := _tray()
	tray.rotation = Vector3.ZERO
	tray.rotate_y(PI)  # now facing -Z
	# A point at +Z is now behind the unit.
	assert_bool(tray.front_arc_contains(Vector3(0, 0, 2))).is_false()
	assert_bool(tray.front_arc_contains(Vector3(0, 0, -2))).is_true()
