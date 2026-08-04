extends GdUnitTestSuite
## VolumetricLos is the ONE volumetric sight truth (elevation program, Phase A): model heights come from
## the official base-size table and every piece of terrain is an upright 3D volume. These prove the height
## table and the slab-clip-then-2D geometry every later sight query rides on. Everything is built in
## INCHES here and converted with K — the module itself only ever sees metres.

const K := VolumetricLos.INCHES_TO_METERS


func _p(x_in: float, y_in: float, z_in: float) -> Vector3:
	return Vector3(x_in, y_in, z_in) * K


func _box(cx_in: float, cz_in: float, hx_in: float, hz_in: float, y0_in: float, y1_in: float) -> Dictionary:
	return {"kind": "box", "c": Vector2(cx_in, cz_in) * K, "he": Vector2(hx_in, hz_in) * K,
		"yaw": 0.0, "y0": y0_in * K, "y1": y1_in * K, "solid": true}


func _cyl(cx_in: float, cz_in: float, r_in: float, y0_in: float, y1_in: float) -> Dictionary:
	return {"kind": "cyl", "c": Vector2(cx_in, cz_in) * K, "r": r_in * K,
		"y0": y0_in * K, "y1": y1_in * K, "solid": true}


func _area(box_or_cells: Dictionary) -> Dictionary:
	box_or_cells["solid"] = false
	return box_or_cells


func _cells(ids: Array, y0_in: float, y1_in: float) -> Dictionary:
	var cells := {}
	for id: Vector2i in ids:
		cells[id] = true
	return {"kind": "cells", "cells": cells, "cell_size": TerrainRules.CELL_IN * K,
		"y0": y0_in * K, "y1": y1_in * K, "solid": true}


## A model as the module sees it: base footprint extruded from where it stands to its own height.
func _model(x_in: float, z_in: float, stand_y_in: float, base_mm: float) -> Dictionary:
	var h := VolumetricLos.height_in_for_base_mm(base_mm)
	return {"c": Vector2(x_in, z_in) * K, "r": base_mm * 0.5 * 0.001,
		"y0": stand_y_in * K, "y1": (stand_y_in + h) * K}


func test_base_height_table_matches_the_official_volumetric_sizes() -> void:
	# P1: the height of a model is a function of its BASE, never of its mesh (meshes are optional
	# per-client content — a mesh-derived height would desync multiplayer).
	assert_float(VolumetricLos.height_in_for_base_mm(25.0)).is_equal_approx(1.0, 0.0001)
	assert_float(VolumetricLos.height_in_for_base_mm(32.0)).is_equal_approx(1.25, 0.0001)
	assert_float(VolumetricLos.height_in_for_base_mm(40.0)).is_equal_approx(1.5, 0.0001)
	assert_float(VolumetricLos.height_in_for_base_mm(50.0)).is_equal_approx(2.0, 0.0001)
	assert_float(VolumetricLos.height_in_for_base_mm(60.0)).is_equal_approx(3.0, 0.0001)
	assert_float(VolumetricLos.height_in_for_base_mm(100.0)).is_equal_approx(4.0, 0.0001)


func test_base_height_interpolates_clamps_and_averages_ovals() -> void:
	# Between two rows: LINEAR. 28 mm sits 3/7 of the way from 25 mm (1") to 32 mm (1.25").
	assert_float(VolumetricLos.height_in_for_base_mm(28.0)).is_equal_approx(1.1071, 0.0001)
	# Outside the table: clamp to the first / last row (no negative or giant models).
	assert_float(VolumetricLos.height_in_for_base_mm(20.0)).is_equal_approx(1.0, 0.0001)
	assert_float(VolumetricLos.height_in_for_base_mm(120.0)).is_equal_approx(4.0, 0.0001)
	# Oval bases enter the table through their MEAN axis: 60x35 counts as 47.5 mm -> 1.875".
	assert_float(VolumetricLos.oval_effective_mm(60.0, 35.0)).is_equal_approx(47.5, 0.0001)
	assert_float(VolumetricLos.height_in_for_base_mm(47.5)).is_equal_approx(1.875, 0.0001)


func test_box_volume_is_clipped_by_its_y_slab_before_the_2d_test() -> void:
	var box := _box(0.0, 0.0, 1.5, 1.5, 0.0, 2.0)   # 3x3", 2" tall, standing on the table
	# Straight through at 1": hit.
	assert_bool(VolumetricLos.segment_hits_box(_p(-6, 1, 0), _p(6, 1, 0), box)).is_true()
	# Straight over the top at 3": miss — this is the elevation win.
	assert_bool(VolumetricLos.segment_hits_box(_p(-6, 3, 0), _p(6, 3, 0), box)).is_false()
	# Steep climb: the UNCLIPPED XZ projection crosses the footprint, but the part inside the slab
	# (t <= 1/6, x <= -4") does not — so slab-clip FIRST, 2D test second.
	assert_bool(VolumetricLos.segment_hits_box(_p(-6, 0, 0), _p(6, 12, 0), box)).is_false()


func test_cylinder_volume_is_clipped_by_its_y_slab_before_the_2d_test() -> void:
	var cyl := _cyl(0.0, 0.0, 1.5, 0.0, 2.0)   # r = 1.5", 2" tall
	assert_bool(VolumetricLos.segment_hits_cyl(_p(-6, 1, 0), _p(6, 1, 0), cyl)).is_true()
	assert_bool(VolumetricLos.segment_hits_cyl(_p(-6, 3, 0), _p(6, 3, 0), cyl)).is_false()
	assert_bool(VolumetricLos.segment_hits_cyl(_p(-6, 0, 0), _p(6, 12, 0), cyl)).is_false()


func test_the_eye_is_the_cylinder_top_centre() -> void:
	# Standing on a 2" ledge on a 32 mm base (1.25" tall) -> the eye sits at 3.25".
	var m := _model(4.0, 6.0, 2.0, 32.0)
	assert_vector(VolumetricLos.eye(m)).is_equal_approx(Vector3(4.0, 3.25, 6.0) * K, Vector3.ONE * 0.0001)


func test_solid_container_blocks_the_ground_line_but_not_the_line_over_it() -> void:
	var container := [_box(0.0, 0.0, 3.0, 1.5, 0.0, 2.5)]   # 6x3", 2.5" tall
	var ground_a := _model(-10.0, 0.0, 0.0, 25.0)           # eye 1"
	var ground_b := _model(10.0, 0.0, 0.0, 25.0)
	assert_bool(VolumetricLos.has_los(ground_a, ground_b, container)).is_false()
	# The same target seen from a 6" tower: the line clears the 2.5" roof -> no more phantom block.
	var tower := _model(-10.0, 0.0, 6.0, 25.0)              # eye 7"
	assert_bool(VolumetricLos.has_los(tower, ground_b, container)).is_true()


func test_a_floor_slab_between_two_storeys_blocks() -> void:
	# The second storey's floor is a thin solid plate at 3" — it hides the ground floor beyond it.
	var slab := [_box(0.0, 0.0, 6.0, 6.0, 2.75, 3.0)]
	var upstairs := _model(0.0, 0.0, 3.0, 25.0)             # eye 4"
	var downstairs := _model(10.0, 0.0, 0.0, 25.0)          # eye 1"
	assert_bool(VolumetricLos.has_los(upstairs, downstairs, slab)).is_false()


func test_area_volume_is_seen_over_into_and_out_of_but_not_through() -> void:
	# P4: forests/ruins are AREA terrain — see in and out, not through. 3.4" tall.
	var forest := [_area(_box(0.0, 0.0, 3.0, 3.0, 0.0, 3.4))]
	var ground_a := _model(-10.0, 0.0, 0.0, 25.0)
	var ground_b := _model(10.0, 0.0, 0.0, 25.0)
	assert_bool(VolumetricLos.has_los(ground_a, ground_b, forest)).is_false()      # through: blocked
	var inside := _model(0.0, 0.0, 0.0, 25.0)
	assert_bool(VolumetricLos.has_los(ground_a, inside, forest)).is_true()         # into: clear
	assert_bool(VolumetricLos.has_los(inside, ground_b, forest)).is_true()         # out of: clear
	# A 6" tower shooting a ground target past a NEARBY forest: the line stays above 3.4" over the trees.
	var near_forest := [_area(_box(-6.0, 0.0, 1.5, 3.0, 0.0, 3.4))]
	assert_bool(VolumetricLos.has_los(_model(-10.0, 0.0, 6.0, 25.0), ground_b, near_forest)).is_true()


func test_painted_cell_zones_block_solid_and_area_the_same_way() -> void:
	# Grid-painted zones are one cells-volume per zone; cell (0,0) covers 0..3" in x and z.
	var solid_zone := [_cells([Vector2i(0, 0)], 0.0, 2.5)]
	var a := _model(-5.0, 1.5, 0.0, 25.0)
	var b := _model(8.0, 1.5, 0.0, 25.0)
	assert_bool(VolumetricLos.has_los(a, b, solid_zone)).is_false()
	assert_bool(VolumetricLos.has_los(_model(-5.0, 1.5, 6.0, 25.0), b, solid_zone)).is_true()   # over it
	var area_zone := [_area(_cells([Vector2i(0, 0)], 0.0, 3.4))]
	assert_bool(VolumetricLos.has_los(a, b, area_zone)).is_false()                              # through
	assert_bool(VolumetricLos.has_los(a, _model(1.5, 1.5, 0.0, 25.0), area_zone)).is_true()     # into


func test_an_empty_table_and_touching_models_are_always_clear() -> void:
	assert_bool(VolumetricLos.has_los(_model(-10.0, 0.0, 0.0, 25.0), _model(10.0, 0.0, 0.0, 25.0))).is_true()
	# Span under 2 cm: two models all but on top of each other see each other even inside a solid volume.
	var container := [_box(0.0, 0.0, 3.0, 1.5, 0.0, 2.5)]
	assert_bool(VolumetricLos.has_los(_model(0.0, 0.0, 0.0, 25.0), _model(0.2, 0.0, 0.0, 25.0), container)).is_true()


## A model as a LOS blocker: its cylinder plus the unit it belongs to and the aircraft flag.
func _blocker(x_in: float, z_in: float, base_mm: float, unit_key: int, aircraft := false) -> Dictionary:
	var d := _model(x_in, z_in, 0.0, base_mm)
	d["unit_key"] = unit_key
	d["is_aircraft"] = aircraft
	return d


func test_a_model_in_the_lane_blocks_and_is_named() -> void:
	var blockers := [_blocker(0.0, 0.0, 50.0, 7)]          # 50 mm base -> 2" tall
	var a := _model(-10.0, 0.0, 0.0, 25.0)                 # eye 1"
	var b := _model(10.0, 0.0, 0.0, 25.0)
	assert_bool(VolumetricLos.has_los(a, b, [], blockers)).is_false()
	assert_int(VolumetricLos.first_blocking_unit_key(VolumetricLos.eye(a), VolumetricLos.eye(b),
		blockers, [])).is_equal(7)
	# The shooter's and the target's own unit never block their line.
	assert_bool(VolumetricLos.has_los(a, b, [], blockers, [7])).is_true()


func test_geometry_decides_who_sees_over_whom_no_height_ladder() -> void:
	var blockers := [_blocker(0.0, 0.0, 25.0, 7)]          # 25 mm base -> 1" tall
	var target := _model(10.0, 0.0, 0.0, 25.0)
	# A 60 mm model (3" tall) looks straight over the 1" model in between.
	assert_bool(VolumetricLos.has_los(_model(-10.0, 0.0, 0.0, 60.0), target, [], blockers)).is_true()
	# Another 1" model does not: eye and blocker top are the same height, so the line is blocked.
	assert_bool(VolumetricLos.has_los(_model(-10.0, 0.0, 0.0, 25.0), target, [], blockers)).is_false()


func test_a_closed_gap_in_a_unit_is_a_wall_a_tall_eye_still_clears() -> void:
	# Two 50 mm models of ONE unit, 0.43" of air between their bases: under 1" counts as closed, so the
	# line is blocked even though it threads BETWEEN the two bases.
	var pair := [_blocker(0.0, -1.2, 50.0, 7), _blocker(0.0, 1.2, 50.0, 7)]
	assert_bool(VolumetricLos.has_los(_model(-10.0, 0.0, 0.0, 25.0), _model(10.0, 0.0, 0.0, 25.0),
		[], pair)).is_false()
	# The wall is only as tall as the shorter of the pair (2"): two 3" models see over it.
	assert_bool(VolumetricLos.has_los(_model(-10.0, 0.0, 0.0, 60.0), _model(10.0, 0.0, 0.0, 60.0),
		[], pair)).is_true()


func test_aircraft_are_transparent_and_always_visible() -> void:
	# P6 (GF p.13): an aircraft's base is abstract — it never blocks...
	var flyers := [_blocker(0.0, 0.0, 50.0, 7, true)]
	var a := _model(-10.0, 0.0, 0.0, 25.0)
	assert_bool(VolumetricLos.has_los(a, _model(10.0, 0.0, 0.0, 25.0), [], flyers)).is_true()
	# ...and it is always visible itself, even behind a solid container.
	var flyer := _model(10.0, 0.0, 0.0, 25.0)
	flyer["is_aircraft"] = true
	assert_bool(VolumetricLos.has_los(a, flyer, [_box(0.0, 0.0, 3.0, 1.5, 0.0, 2.5)])).is_true()


func test_surface_y_at_reports_the_tallest_solid_footprint() -> void:
	var vols := [_box(0.0, 0.0, 3.0, 1.5, 0.0, 2.5),          # container roof at 2.5"
		_box(0.0, 20.0, 6.0, 6.0, 2.75, 3.0),                 # second-storey floor slab at 3"
		_area(_box(20.0, 0.0, 3.0, 3.0, 0.0, 3.4))]           # forest: standable ground, not a floor
	assert_float(VolumetricLos.surface_y_at(Vector2(0.0, 0.0), vols)).is_equal_approx(2.5 * K, 0.0001)
	assert_float(VolumetricLos.surface_y_at(Vector2(0.0, 20.0) * K, vols)).is_equal_approx(3.0 * K, 0.0001)
	assert_float(VolumetricLos.surface_y_at(Vector2(20.0, 0.0) * K, vols)).is_equal_approx(0.0, 0.0001)
	assert_float(VolumetricLos.surface_y_at(Vector2(50.0, 50.0) * K, vols)).is_equal_approx(0.0, 0.0001)
