extends GdUnitTestSuite
## OffboardAudit is the measurement seam for issue #215 (the movement planner routing models off a
## rectangular table). It decides ONE thing: is a settled model centre outside the table, and by how
## much. These pin that rule and the parseable line format, because the A/B verdict for #215 is read
## off this detector — a silently-broken detector would report a comfortable 0 forever.

const OffboardAudit := preload("res://tools/offboard_audit.gd")

## 6x4 ft = 72"x48" — the shipped default table (main.gd DEFAULT_TABLE_SIZE_FEET) and the board the
## A/B legs run on. Half-extents in metres: 36" x 24".
const HALF_6X4 := Vector2(0.9144, 0.6096)
const IN2M := 0.0254


# === Half-extents ===

func test_half_extents_read_the_table_in_feet() -> void:
	# A real table node exposes `table_size` (FEET) as a script property; the audit converts it to
	# metric half-extents. A bare Node cannot carry the property, so the stub needs a script.
	var scr := GDScript.new()
	scr.source_code = "extends Node\nvar table_size := Vector2(6, 4)\n"
	scr.reload()
	var stub := Node.new()
	stub.set_script(scr)
	auto_free(stub)
	var half := OffboardAudit.half_extents_m(stub)
	assert_float(half.x).is_equal_approx(0.9144, 0.0001)
	assert_float(half.y).is_equal_approx(0.6096, 0.0001)


func test_half_extents_fall_back_to_4x4_without_a_table() -> void:
	# Mirrors SoloController._table_half_extents: no table => 4x4 ft, i.e. a SQUARE 24" x 24".
	var half := OffboardAudit.half_extents_m(null)
	assert_float(half.x).is_equal_approx(0.6096, 0.0001)
	assert_float(half.y).is_equal_approx(0.6096, 0.0001)


# === The detection rule ===

func test_centre_well_inside_reports_negative_overhang() -> void:
	# Board centre on a 6x4: 36" clear of the long edge, 24" of the short one.
	assert_float(OffboardAudit.overhang_in(Vector3.ZERO, HALF_6X4)).is_less(-20.0)


func test_short_axis_overhang_is_measured_on_its_own_axis() -> void:
	# THE #215 CASE: x is comfortably on the board, z is 6" past the SHORT edge (24"). Folding both
	# axes into one scalar bound (the old maxf) hid exactly this — the long axis says "still inside".
	var p := Vector3(0.0, 0.0, (24.0 + 6.0) * IN2M)
	assert_float(OffboardAudit.overhang_in(p, HALF_6X4)).is_equal_approx(6.0, 0.001)


func test_long_axis_overhang_is_measured_too() -> void:
	var p := Vector3((36.0 + 2.5) * IN2M, 0.0, 0.0)
	assert_float(OffboardAudit.overhang_in(p, HALF_6X4)).is_equal_approx(2.5, 0.001)


func test_corner_exit_reports_the_worse_axis() -> void:
	# 3" past the long edge, 9" past the short one => the worse side (9") is the honest number.
	var p := Vector3((36.0 + 3.0) * IN2M, 0.0, (24.0 + 9.0) * IN2M)
	assert_float(OffboardAudit.overhang_in(p, HALF_6X4)).is_equal_approx(9.0, 0.001)


func test_negative_side_counts_the_same() -> void:
	# The table is centred on the origin, so -z must be measured exactly like +z.
	var p := Vector3(0.0, 0.0, -(24.0 + 4.0) * IN2M)
	assert_float(OffboardAudit.overhang_in(p, HALF_6X4)).is_equal_approx(4.0, 0.001)


func test_model_parked_at_the_clamped_edge_is_not_flagged() -> void:
	# SoloController._clamp_to_bounds parks models BOUNDS_MARGIN_M (2cm) inside the edge — a legal
	# edge model must stay under the epsilon, or every clamped move would raise a false alarm.
	var p := Vector3(0.0, 0.0, 0.6096 - 0.02)
	assert_float(OffboardAudit.overhang_in(p, HALF_6X4)).is_less(-OffboardAudit.OFFBOARD_EPS_IN)


# === The parseable line (cross-language contract with tools/tactic_audit.py) ===

func test_line_format_is_the_pinned_contract() -> void:
	# Byte-identical to GD_LINE in tools/test_tactic_audit.py, which pins the Python parser (d9).
	# If this string changes, that suite must change with it — otherwise d9 silently reports 0.
	assert_str(OffboardAudit.line("Orc Grunts", 2, 3.4, "after activation")).is_equal(
		"AUDIT off-board: Orc Grunts — 2 model(s), max overhang 3.40\" (after activation)")


func test_line_carries_the_unit_and_the_phase() -> void:
	var s: String = OffboardAudit.line("Wolf Riders", 1, 11.75, "after move")
	assert_str(s).contains("Wolf Riders")
	assert_str(s).contains("after move")
	assert_str(s).contains("11.75\"")


# === Tally over a unit ===

func test_check_unit_without_a_table_or_unit_is_quiet() -> void:
	var empty: Dictionary = OffboardAudit.check_unit(null, null)
	assert_int(int(empty["count"])).is_equal(0)
	assert_float(float(empty["max_overhang_in"])).is_equal_approx(0.0, 0.0001)
