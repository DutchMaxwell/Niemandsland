extends GdUnitTestSuite
## The terrain overlay's 3D VOLUME REGISTRY (elevation program, Phase A): every piece of terrain the
## overlay knows about — registered container boxes, ruin walls and grid-painted zones — is published as
## one VolumetricLos volume dict in real metres. This is the single feed the volumetric sight truth reads,
## so what the table LOOKS like and what the rules MEASURE can no longer drift apart.
##
## The overlay is created WITHOUT add_child(), exactly like terrain_overlay_test: _ready() never runs, so
## the R2 libraries stay null (every readiness helper is null-safe) and the props fall back to procedural.
## Every lookup below is defensive (missing volume -> empty dict, sentinel defaults) so a missing entry
## fails as an ASSERTION instead of aborting the suite on an out-of-bounds read.

const OverlayScript := preload("res://scripts/terrain_overlay.gd")
const K := OverlayScript.INCHES_TO_METERS
const TABLE := Vector2(6, 4)   # feet
const MID := Vector2i(15, 15)  # a cell near the middle of the 30x30 grid a 6x4 ft table spans
const NONE := -999.0           # sentinel for "the registry did not publish this field at all"


func _overlay() -> Node3D:
	var o: Node3D = auto_free(OverlayScript.new())
	o.table_size_feet = TABLE
	return o


## Flat world centre (metres) of a painted grid cell — the point every footprint assertion probes with.
func _centre(o: Node3D, cell: Vector2i) -> Vector2:
	var dims: Vector2i = o._calculate_grid_dims(TABLE)
	var w: Vector3 = o._cell_to_world(float(cell.x), float(cell.y), dims,
		OverlayScript.GRID_SIZE_INCHES * K, deg_to_rad(o.grid_rotation_degrees))
	return Vector2(w.x, w.z)


func _all_of_kind(o: Node3D, kind: String) -> Array:
	var out: Array = []
	var volumes: Array = o.los_volumes()
	for v: Dictionary in volumes:
		if String(v.get("kind", "box")) == kind:
			out.append(v)
	return out


func _one_of_kind(o: Node3D, kind: String) -> Dictionary:
	var found := _all_of_kind(o, kind)
	return found[0] if found.size() == 1 else {}


## Footprint probe that survives a missing volume (empty dict -> "contains nothing").
func _covers(vol: Dictionary, p: Vector2) -> bool:
	return not vol.is_empty() and VolumetricLos.point_in_footprint(p, vol)


func _paint(o: Node3D, cells: Array, terrain_type: int, rot_deg: float = 0.0) -> void:
	var data := {}
	for c: Vector2i in cells:
		data[c] = terrain_type
	o.update_overlay(data, TABLE, rot_deg)


func _container_at(o: Node3D, cell: Vector2i) -> void:
	o.update_placed_objects([{"object_type": "container", "cell": cell,
		"offset": Vector2(0.5, 0.5), "angle_deg": 0.0}], TABLE, 0.0)


func test_registered_container_box_is_a_solid_volume_two_and_a_half_inches_tall() -> void:
	# A placed container is recorded as an exact 6x3 OBB (container wave). In 3D it is that same
	# rectangle extruded to its real 2.5" height — which is what lets a model on a roof see over it.
	var o := _overlay()
	_container_at(o, MID)
	var b := _one_of_kind(o, "box")
	assert_bool(bool(b.get("solid", false))).is_true()
	assert_float(float(b.get("y0", NONE))).is_equal_approx(0.0, 1e-9)
	assert_float(float(b.get("y1", NONE))).is_equal_approx(OverlayScript.CONTAINER_HEIGHT_INCHES * K, 1e-9)
	var he: Vector2 = b.get("he", Vector2.ZERO)
	assert_float(he.x).is_equal_approx(OverlayScript.CONTAINER_LENGTH_INCHES * K * 0.5, 1e-9)
	assert_float(he.y).is_equal_approx(OverlayScript.CONTAINER_DEPTH_INCHES * K * 0.5, 1e-9)
	assert_bool(_covers(b, _centre(o, MID))).is_true()


func test_wall_segments_stay_out_of_the_los_registry() -> void:
	# NML-1028 (body campaign F4, #312 regression): ruins are AREA terrain —
	# see-in/out-not-through comes from the ZONE volume; the walls are movement
	# blockers, never sight blockers (the documented rules decision this file's
	# own :1666 comment records). A 2.5"-tall solid wall in the LOS feed
	# blinded every model standing inside a ruin. Movement keeps its walls via
	# get_wall_segments_world — only the SIGHT registry must stay clean.
	var o := _overlay()
	o.update_wall_models([{"edge_cell": MID, "edge_side": 0, "wall_key": "w",
		"length_inches": OverlayScript.GRID_SIZE_INCHES, "sub_position": 0}], TABLE, 0.0)
	assert_int(_all_of_kind(o, "box").size()).is_equal(0)
	assert_int(o.get_wall_segments_world().size()).is_greater(0)


func test_painted_forest_zone_is_an_area_cells_volume_of_tree_height() -> void:
	# Forests are AREA terrain (see in/out, not through) — non-solid — and only as tall as the trees,
	# so a model on a 6" ruin roof looks straight over the treetops.
	var o := _overlay()
	_paint(o, [MID, MID + Vector2i(0, 1)], OverlayScript.TerrainType.FOREST)
	var z := _one_of_kind(o, "cells")
	assert_bool(bool(z.get("solid", true))).is_false()
	assert_float(float(z.get("y0", NONE))).is_equal_approx(0.0, 1e-9)
	assert_float(float(z.get("y1", NONE))).is_equal_approx(OverlayScript.TREE_HEIGHT_INCHES * K, 1e-9)
	assert_bool(_covers(z, _centre(o, MID))).is_true()
	assert_bool(_covers(z, _centre(o, MID + Vector2i(0, 1)))).is_true()


func test_painted_ruins_zone_is_an_area_cells_volume_six_inches_tall() -> void:
	# Ruins are two-storey (the shelf ruins' 6" top floor) — the tallest painted zone there is.
	var o := _overlay()
	_paint(o, [MID], OverlayScript.TerrainType.RUINS)
	var z := _one_of_kind(o, "cells")
	assert_bool(bool(z.get("solid", true))).is_false()
	assert_float(float(z.get("y1", NONE))).is_equal_approx(OverlayScript.RUIN_ZONE_HEIGHT_INCHES * K, 1e-9)


func test_painted_dangerous_ground_publishes_no_volume() -> void:
	# Dangerous terrain is Open ground: it never blocks sight, so it is not in the registry at all.
	var o := _overlay()
	_paint(o, [MID], OverlayScript.TerrainType.DANGEROUS)
	assert_int((o.los_volumes() as Array).size()).is_equal(0)


func test_painted_container_cells_without_a_registered_box_are_solid_cells() -> void:
	# A map layout can paint CONTAINER ground without any object being placed on it; that ground still
	# hard-blocks, at the container's own 2.5" height.
	var o := _overlay()
	_paint(o, [MID], OverlayScript.TerrainType.CONTAINER)
	var z := _one_of_kind(o, "cells")
	assert_bool(bool(z.get("solid", false))).is_true()
	assert_float(float(z.get("y1", NONE))).is_equal_approx(OverlayScript.CONTAINER_HEIGHT_INCHES * K, 1e-9)


func test_container_cells_under_a_registered_box_are_excluded() -> void:
	# NML-965 double-block trap: a placed container paints its cells AND registers its OBB. Publishing
	# both would wall the box in twice — and the cell version has no roof, so a model standing on the
	# container would be blocked by the very box it stands on. The OBB is the truth; its cells drop out.
	var o := _overlay()
	_paint(o, [MID, MID + Vector2i(0, 1), MID + Vector2i(0, 2)], OverlayScript.TerrainType.CONTAINER)
	_container_at(o, MID)
	var b := _one_of_kind(o, "box")
	var z := _one_of_kind(o, "cells")
	assert_bool(_covers(b, _centre(o, MID))).is_true()
	assert_bool(_covers(z, _centre(o, MID))).is_false()
	assert_bool(_covers(z, _centre(o, MID + Vector2i(0, 1)))).is_true()
	assert_bool(_covers(z, _centre(o, MID + Vector2i(0, 2)))).is_true()


func test_re_registration_invalidates_the_cached_registry() -> void:
	# The registry is cached (it is read on every sight query); every registration site must drop it,
	# or the table would keep blocking sight with terrain that has already been cleared away.
	var o := _overlay()
	assert_int((o.los_volumes() as Array).size()).is_equal(0)
	_container_at(o, MID)
	assert_int(_all_of_kind(o, "box").size()).is_equal(1)
	o.update_placed_objects([], TABLE, 0.0)
	assert_int((o.los_volumes() as Array).size()).is_equal(0)
	_paint(o, [MID], OverlayScript.TerrainType.FOREST)
	assert_int(_all_of_kind(o, "cells").size()).is_equal(1)


func test_surface_y_at_reports_the_container_roof() -> void:
	# The AI and the ruler place hypothetical models with this: on the container roof they stand 2.5"
	# up, two cells away they stand on the table.
	var o := _overlay()
	_container_at(o, MID)
	assert_float(o.surface_y_at(_centre(o, MID))) \
		.is_equal_approx(OverlayScript.CONTAINER_HEIGHT_INCHES * K, 1e-9)
	assert_float(o.surface_y_at(_centre(o, MID + Vector2i(0, 2)))).is_equal_approx(0.0, 1e-9)


func test_a_rotated_painted_grid_keeps_its_own_cell_frame() -> void:
	# The map layout's rotation slider turns the painted grid against the world, so a zone's cells are
	# keyed in the GRID's frame and the volume carries its yaw. Probed on a cell 5 rows out from the
	# table centre: 30 degrees moves it ~8.6", far more than one cell diagonal, so the two frames
	# cannot be confused. Without the yaw the sight truth would look terrain up in the wrong place.
	var o := _overlay()
	var far_cell := MID + Vector2i(0, 5)
	_paint(o, [MID + Vector2i(0, 4), far_cell], OverlayScript.TerrainType.FOREST, 30.0)
	var z := _one_of_kind(o, "cells")
	assert_float(float(z.get("yaw", NONE))).is_equal_approx(deg_to_rad(30.0), 1e-9)
	assert_bool(_covers(z, _centre(o, far_cell))).is_true()
	# The SAME cell's un-rotated position is now bare table — the zone travelled with the grid.
	var dims: Vector2i = o._calculate_grid_dims(TABLE)
	var flat: Vector3 = o._cell_to_world(float(far_cell.x), float(far_cell.y), dims,
		OverlayScript.GRID_SIZE_INCHES * K, 0.0)
	assert_bool(_covers(z, Vector2(flat.x, flat.z))).is_false()
