class_name SightFan
extends RefCounted
## Pure sight+range fan geometry (maintainer sketch 2026-07-16): the region a unit can SEE AND SHOOT,
## computed per model and rendered as the union — the player's "what is a legitimate target" overlay.
## Semantics MIRROR the engine's terrain LOS (terrain_overlay.has_line_of_sight + TerrainRules): rays start
## at the BASE EDGE (OPR measures from the closest base point), walls stop a ray exactly at the segment hit,
## solid CONTAINER blocks at entry, and AREA terrain (forest/ruins) is see-INTO-not-THROUGH — a ray may
## traverse its ORIGIN's own contiguous blocking zone (see out), may enter ONE further blocking zone
## (targets inside are visible — "Ziele mit Deckung") and ends at that zone's far edge ("Ziele die nicht
## gesehen werden" beyond). Pure + headless-testable; the renderer unions the per-model polygons.

const RAYS := 180
const STEP_M := 0.0381   # half a 3" terrain cell — the same granularity the engine's LOS march uses
const REFINE_ITERS := 4  # bisection per stopped ray: 0.0381m / 2^4 ≈ 2.4mm — kills the stair-stepping
                         # at zone boundaries (field-test Bug 15) for 4 extra samples per blocked ray

enum Refine { IMPASSABLE, ZONE_START, ZONE_END }


## One model's fan polygon (closed ring, one vertex per ray). `origin`/`base_r`/`range_m` in world metres
## (table XZ); `walls` = [[Vector2 a, Vector2 b], ...]; `terrain_type_at` = Callable(Vector2) -> int
## (TerrainRules.TerrainType). `range_m` is measured FROM THE BASE EDGE.
static func fan_polygon(origin: Vector2, base_r: float, range_m: float, walls: Array,
		terrain_type_at: Callable, rays: int = RAYS) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var origin_blocking := _blocks_area(int(terrain_type_at.call(origin)))
	for k in range(rays):
		var ang := TAU * float(k) / float(rays)
		var dir := Vector2(cos(ang), sin(ang))
		var start := origin + dir * base_r
		var max_d := range_m
		for w in walls:   # exact wall hit — the fan edge lies ON the wall, like the sketch's shadow tangents
			var hit = Geometry2D.segment_intersects_segment(start, start + dir * max_d, w[0] as Vector2, w[1] as Vector2)
			if hit != null:
				max_d = minf(max_d, ((hit as Vector2) - start).length())
		poly.append(start + dir * _terrain_limited(start, dir, max_d, origin_blocking, terrain_type_at))
	return poly


## March one ray against the terrain grid: how far (metres) is visible along `dir` from `start`.
static func _terrain_limited(start: Vector2, dir: Vector2, max_d: float, origin_blocking: bool,
		terrain_type_at: Callable) -> float:
	var in_origin_zone := origin_blocking   # contiguous blocking run the ORIGIN stands in — free to see out of
	var in_foreign := false                 # the ONE foreign blocking zone a ray may see INTO
	var entered_foreign := false
	var d := 0.0
	while d < max_d - 0.0001:
		var next_d := minf(d + STEP_M, max_d)
		var t := int(terrain_type_at.call(start + dir * next_d))
		if TerrainRules.is_impassable(t):
			# solid CONTAINER: blocks at entry, no see-into — refine the entry point (Bug 15)
			return _refine_boundary(start, dir, d, next_d, terrain_type_at, Refine.IMPASSABLE)
		var blocking := _blocks_area(t)
		if in_origin_zone:
			if not blocking:
				in_origin_zone = false   # left the own zone — open ground ahead
		elif in_foreign:
			if not blocking:
				# far edge of the seen-into zone: beyond is "not seen" — refine the exit point
				return _refine_boundary(start, dir, d, next_d, terrain_type_at, Refine.ZONE_END)
		else:
			if blocking:
				if entered_foreign:
					# a SECOND foreign zone would be "through" the first — stop right before it
					return _refine_boundary(start, dir, d, next_d, terrain_type_at, Refine.ZONE_START)
				entered_foreign = true
				in_foreign = true
		d = next_d
	return max_d


## Bisect the exact stop distance inside (lo, hi]: at `lo` the ray was still running, at `hi` the
## stop condition held. 4 iterations narrow the STEP_M quantisation to ~2.4mm so adjacent rays stop
## on the SAME terrain edge instead of different march steps (the fuzzy/jagged fan borders).
## Display-only refinement: the trigger condition is re-tested, not the full zone state machine —
## sub-step slivers of a different terrain class are beyond the overlay's resolution anyway.
static func _refine_boundary(start: Vector2, dir: Vector2, lo: float, hi: float,
		terrain_type_at: Callable, mode: int) -> float:
	for _i in range(REFINE_ITERS):
		var mid := (lo + hi) * 0.5
		var t := int(terrain_type_at.call(start + dir * mid))
		var stopped := false
		match mode:
			Refine.IMPASSABLE:
				stopped = TerrainRules.is_impassable(t)
			Refine.ZONE_START:
				stopped = _blocks_area(t)
			Refine.ZONE_END:
				stopped = not _blocks_area(t)
		if stopped:
			hi = mid
		else:
			lo = mid
	return lo


## Union of per-model fan polygons (Geometry2D.merge_polygons, accumulated). Returns Array[PackedVector2Array]
## — disjoint groups stay separate polygons; holes (rare) are dropped (display overlay, not rules resolution).
static func union_fans(polys: Array) -> Array:
	var acc: Array = []
	for p in polys:
		var poly := p as PackedVector2Array
		if poly.size() < 3:
			continue
		if acc.is_empty():
			acc.append(poly)
			continue
		var merged_any := false
		for i in range(acc.size()):
			var m := Geometry2D.merge_polygons(acc[i], poly)
			var outer: Array = []
			for piece in m:
				if not Geometry2D.is_polygon_clockwise(piece):   # CW = hole in Godot's convention
					outer.append(piece)
			if outer.size() == 1:   # merged into one outline → replace and stop
				acc[i] = outer[0]
				merged_any = true
				break
		if not merged_any:
			acc.append(poly)
	return acc


## AREA terrain that blocks through-sight for the fan (mirrors terrain_overlay.terrain_blocks_los minus the
## solid CONTAINER, which _terrain_limited hard-stops separately).
static func _blocks_area(t: int) -> bool:
	return t == TerrainRules.TerrainType.RUINS or t == TerrainRules.TerrainType.FOREST
