class_name SeparationZone
extends RefCounted
## Pure geometry for the 1" unit-separation ZONE WALL: the single merged contour of a
## unit's member bases, grown outward by 1" into a translucent ground band that shows
## the no-go area around that unit (GF/AoF Advanced Rules v3.5.1, p.7 "General
## Movement": models may never be within 1" of models from OTHER units). This module
## builds the band GEOMETRY (a triangle soup in world XZ metres); SeparationVisualizer
## turns it into a mesh, and SeparationChecker does the per-pair distance math.
##
## UNION, NOT OVERLAPPING RINGS: a unit's footprint is the UNION of its members' base
## polygons (round infantry, oval cavalry/vehicles, rectangular regiment trays) merged
## into ONE contour per connected cluster (Geometry2D / Clipper `merge_polygons`), so
## the band hugs the outside of the whole block rather than drawing overlapping
## per-model circles. The band is that contour grown outward by 1" (`offset_polygon`,
## round joins) with the interior left hollow — an annulus / oval band / rounded-rect
## band depending on the shapes, exactly 1" wide everywhere.
##
## MESHING: the band between the inner (union) contour and the outer (offset) contour
## is triangulated by a greedy two-loop STITCH (like the side wall of a tube with
## mismatched ring resolutions) rather than a holed-polygon triangulation — robust for
## any round/oval/rect mix and any vertex-count mismatch the round-join offset
## introduces, with no self-intersection assumptions. Rendered double-sided, so
## triangle winding is irrelevant.
##
## PURE + STATIC + TESTABLE: every function is static and free of scene state, so the
## contour/band geometry is unit-tested directly (round/oval/rect + merged-union
## cases). The heavy Clipper calls only run when a unit's members actually move (the
## visualizer caches the mesh per unit), never per frame.

# ===== Constants =====

## Inches -> metres (shared with SeparationChecker / CoherencyChecker).
const INCHES_TO_METERS := 0.0254

## The OPR separation band width: 1" (GF/AoF v3.5.1 p.7). The band is the unit contour
## grown outward by exactly this — the region a model of another unit may not enter.
const BAND_WIDTH_INCHES := 1.0

## Tessellation of a full circle / ellipse into a polygon. 20 reads as smooth at table
## scale while keeping the Clipper union cheap; rectangles use their 4 corners.
const ARC_SEGMENTS := 20

## Numerical guard for near-zero lengths / areas (metres).
const EPSILON_M := 0.00001


# ===== Public API =====

## Triangle soup (world XZ, metres) of the 1"-band wall around a unit, from its member
## base shapes. Each three consecutive Vector2 are one triangle. Empty when there are
## no usable shapes. band_width_m defaults to 1"; segments tessellates round/oval bases.
static func unit_band_triangles(shapes: Array, band_width_m: float = BAND_WIDTH_INCHES * INCHES_TO_METERS, segments: int = ARC_SEGMENTS) -> PackedVector2Array:
	var polys: Array = []
	for s in shapes:
		var p := polygon_for_shape(s, segments)
		if p.size() >= 3:
			polys.append(p)
	var out := PackedVector2Array()
	if polys.is_empty():
		return out
	for inner in union_solid_loops(polys):
		var outer := _largest_solid(offset_outward(inner, band_width_m))
		if outer.size() < 3:
			continue
		out.append_array(stitch_ring(inner, outer))
	return out


## A base shape's outline as a CCW-normalised ("solid") polygon in world XZ (metres).
## Round -> `segments`-gon; oval -> `segments`-gon on its half-axes, rotated by yaw;
## rect -> its 4 rotated corners. Winding is normalised so Clipper treats it as solid.
static func polygon_for_shape(shape: SeparationChecker.BaseShape, segments: int = ARC_SEGMENTS) -> PackedVector2Array:
	var poly := PackedVector2Array()
	if shape == null:
		return poly
	match shape.kind:
		SeparationChecker.BaseShape.Kind.ROUND:
			for i in range(segments):
				var a := TAU * i / float(segments)
				poly.append(shape.center + Vector2(cos(a), sin(a)) * shape.radius)
		SeparationChecker.BaseShape.Kind.OVAL:
			for i in range(segments):
				var a := TAU * i / float(segments)
				poly.append(shape.center + Vector2(cos(a) * shape.semi_x, sin(a) * shape.semi_z).rotated(shape.yaw))
		SeparationChecker.BaseShape.Kind.RECT:
			var sx := shape.semi_x
			var sz := shape.semi_z
			poly.append(shape.center + Vector2(sx, sz).rotated(shape.yaw))
			poly.append(shape.center + Vector2(-sx, sz).rotated(shape.yaw))
			poly.append(shape.center + Vector2(-sx, -sz).rotated(shape.yaw))
			poly.append(shape.center + Vector2(sx, -sz).rotated(shape.yaw))
	return _as_solid(poly)


## Merges member polygons into the union footprint: an Array of disjoint SOLID (CCW)
## loops, one per connected cluster (overlapping members fuse; far-apart members stay
## separate). Interior holes (rare ring formations) are dropped. Incremental union
## (O(n^2) Clipper merges) — n = members, and this only runs on a member move.
static func union_solid_loops(polys: Array) -> Array:
	var loops: Array = []
	for poly in polys:
		loops = _union_into(loops, poly)
	return loops


## Outward offset of a loop by delta metres with round joins (Clipper). Returns the
## grown loop(s); positive delta grows a solid polygon outward.
static func offset_outward(loop: PackedVector2Array, delta_m: float) -> Array:
	if loop.size() < 3 or delta_m <= 0.0:
		return []
	return Geometry2D.offset_polygon(loop, delta_m, Geometry2D.JOIN_ROUND)


## Triangulates the ring between an inner and an outer loop (outer surrounds inner) as
## a triangle soup, by a greedy stitch that advances whichever loop keeps the next
## diagonal shortest. Robust to mismatched vertex counts; no winding guarantee (the
## band is rendered double-sided).
static func stitch_ring(inner: PackedVector2Array, outer: PackedVector2Array) -> PackedVector2Array:
	var tris := PackedVector2Array()
	var n := inner.size()
	var m := outer.size()
	if n < 3 or m < 3:
		return tris

	# Start the outer walk at the outer vertex nearest inner[0] so the first stitch is tight.
	var co := 0
	var best := INF
	for k in range(m):
		var d := inner[0].distance_squared_to(outer[k])
		if d < best:
			best = d
			co = k

	var ci := 0
	var steps_i := 0
	var steps_o := 0
	while steps_i < n or steps_o < m:
		var advance_inner: bool
		if steps_i >= n:
			advance_inner = false
		elif steps_o >= m:
			advance_inner = true
		else:
			var ni := (ci + 1) % n
			var no := (co + 1) % m
			var diag_inner := inner[ni].distance_squared_to(outer[co])
			var diag_outer := inner[ci].distance_squared_to(outer[no])
			advance_inner = diag_inner <= diag_outer
		if advance_inner:
			var ni := (ci + 1) % n
			tris.append(inner[ci])
			tris.append(outer[co])
			tris.append(inner[ni])
			ci = ni
			steps_i += 1
		else:
			var no := (co + 1) % m
			tris.append(inner[ci])
			tris.append(outer[co])
			tris.append(outer[no])
			co = no
			steps_o += 1
	return tris


## Test / query helper: is world-XZ point `p` inside the triangle soup `tris`?
static func triangles_contain_point(tris: PackedVector2Array, p: Vector2) -> bool:
	var count := tris.size() / 3
	for t in range(count):
		if _point_in_triangle(p, tris[t * 3], tris[t * 3 + 1], tris[t * 3 + 2]):
			return true
	return false


# ===== Private =====

## Folds one polygon into a set of mutually-disjoint solid loops, fusing every loop it
## overlaps (so a member bridging two clusters merges them). Holes are discarded.
static func _union_into(loops: Array, poly: PackedVector2Array) -> Array:
	var fused := poly
	var untouched: Array = []
	for loop in loops:
		var merged := Geometry2D.merge_polygons(fused, loop)
		var solids := _solids(merged)
		if solids.size() == 1:
			fused = solids[0]  # overlapped -> fused into one contour
		else:
			untouched.append(loop)  # disjoint -> keep loop, fused unchanged
	untouched.append(fused)
	return untouched


## Solid (non-clockwise) loops of a Clipper result — its holes are wound clockwise.
static func _solids(result: Array) -> Array:
	var out: Array = []
	for loop in result:
		if not Geometry2D.is_polygon_clockwise(loop):
			out.append(loop)
	return out


## The largest-area solid loop of an offset result (guards the rare multi-loop case).
static func _largest_solid(result: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := -1.0
	for loop in _solids(result):
		var area := absf(_signed_area(loop))
		if area > best_area:
			best_area = area
			best = loop
	return best


## Normalises a polygon to Clipper's "solid" winding (non-clockwise).
static func _as_solid(poly: PackedVector2Array) -> PackedVector2Array:
	if poly.size() >= 3 and Geometry2D.is_polygon_clockwise(poly):
		poly.reverse()
	return poly


## Twice the signed area of a polygon (shoelace).
static func _signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in range(n):
		var p := poly[i]
		var q := poly[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## Point-in-triangle via barycentric sign test.
static func _point_in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := _sign(p, a, b)
	var d2 := _sign(p, b, c)
	var d3 := _sign(p, c, a)
	var has_neg := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var has_pos := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (has_neg and has_pos)


static func _sign(p: Vector2, a: Vector2, b: Vector2) -> float:
	return (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
