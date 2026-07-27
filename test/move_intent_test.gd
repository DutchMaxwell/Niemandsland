extends GdUnitTestSuite
## Solo/AI move-intent planning (Phase 0): anchor centroid, range clamping, rigid delta, and the
## inch distance helper. Pure geometry — no nodes, no rendering.

const MI := preload("res://scripts/solo/move_intent.gd")

const I := 0.0254  # inches -> metres


# === anchor_of ===

func test_anchor_is_centroid() -> void:
	var a := MI.anchor_of([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(1, 0, 2)])
	assert_float(a.x).is_equal_approx(1.0, 0.0001)
	assert_float(a.z).is_equal_approx(2.0 / 3.0, 0.0001)


func test_anchor_empty_is_zero() -> void:
	assert_vector(MI.anchor_of([])).is_equal(Vector3.ZERO)


# === clamp_destination ===

func test_within_range_returns_target() -> void:
	# Target 4" away, move allowance 6" -> reach it exactly (anchor Y preserved).
	var anchor := Vector3(0, 0, 0)
	var target := Vector3(4 * I, 0, 0)
	var dest := MI.clamp_destination(anchor, target, 6.0)
	assert_float(dest.x).is_equal_approx(4 * I, 0.00001)
	assert_float(dest.z).is_equal_approx(0.0, 0.00001)


func test_out_of_range_clamped_to_allowance() -> void:
	# Target 10" away, allowance 6" -> stop at 6" along the line.
	var anchor := Vector3(0, 0, 0)
	var target := Vector3(10 * I, 0, 0)
	var dest := MI.clamp_destination(anchor, target, 6.0)
	assert_float(dest.x).is_equal_approx(6 * I, 0.00001)


func test_clamp_keeps_anchor_height() -> void:
	var dest := MI.clamp_destination(Vector3(0, 0.5, 0), Vector3(10 * I, 9.0, 0), 6.0)
	assert_float(dest.y).is_equal_approx(0.5, 0.00001)


# === move_delta / plan_unit_move ===

func test_move_delta_is_planar() -> void:
	var d := MI.move_delta(Vector3(1, 2, 3), Vector3(4, 9, 7))
	assert_float(d.x).is_equal_approx(3.0, 0.00001)
	assert_float(d.y).is_equal_approx(0.0, 0.00001)  # never changes height
	assert_float(d.z).is_equal_approx(4.0, 0.00001)


func test_plan_unit_move_clamps_and_is_rigid() -> void:
	# Two models 1" apart, anchor between them; target 10" away, allowance 6".
	var models := [Vector3(0, 0, 0), Vector3(1 * I, 0, 0)]   # anchor at 0.5"
	var target := Vector3(10 * I, 0, 0)
	var delta := MI.plan_unit_move(models, target, 6.0)
	# Anchor (0.5") + 6" allowance = 6.5"; delta.x = 6.0" (the allowance), planar.
	assert_float(delta.x).is_equal_approx(6 * I, 0.00001)
	assert_float(delta.y).is_equal_approx(0.0, 0.00001)


func test_plan_unit_move_empty_is_zero() -> void:
	assert_vector(MI.plan_unit_move([], Vector3(5, 0, 5), 6.0)).is_equal(Vector3.ZERO)


# === distance_inches ===

func test_distance_inches_planar() -> void:
	# 3-4-5 in inches on the table plane; Y difference ignored.
	var a := Vector3(0, 5.0, 0)
	var b := Vector3(3 * I, 99.0, 4 * I)
	assert_float(MI.distance_inches(a, b)).is_equal_approx(5.0, 0.0001)
