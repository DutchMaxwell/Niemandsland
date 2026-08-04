class_name SightFan
extends RefCounted
## Pure sight+range fan geometry (maintainer sketch 2026-07-16): the region a unit can SEE AND SHOOT,
## computed per model and rendered as the union — the player's "what is a legitimate target" overlay.
## VOLUMETRIC since the elevation program (Phase A): every ray asks the SAME truth the dice ask
## (VolumetricLos over terrain_overlay.los_volumes()), so the yellow overlay and the shooting gate can
## never disagree again. The old raymarch owned its own copy of the see-in/out zone rules and was blind
## to height — a model standing on a container roof got no fan at all (NML-968).
## Pure + headless-testable; the renderer unions the per-model polygons.

const RAYS := 180
const STEP_M := 0.0381   # half a 3" terrain cell — the same granularity the engine's LOS march uses
const REFINE_ITERS := 4  # bisection per stopped ray: 0.0381m / 2^4 ≈ 2.4mm — kills the stair-stepping
                         # at zone boundaries (field-test Bug 15) for 4 extra samples per blocked ray

## The height (INCHES above the table) the fan assumes a TARGET stands at: the fan answers "would a model
## standing here be visible", and 1" is the smallest official model height. A display aid — the real
## shooting query uses each real target's own height.
const TARGET_EYE_IN := 1.0


## One model's fan polygon (closed ring, one vertex per ray). `eye` is the model's EYE in world metres —
## its flat position carrying the height it really looks from (standing y + model height), so a model on
## a container roof looks OVER its box instead of being walled in by it. `volumes` are the terrain volumes
## of terrain_overlay.los_volumes(). `range_m` is measured FROM THE BASE EDGE.
static func fan_polygon(eye: Vector3, base_r: float, range_m: float, volumes: Array,
		rays: int = RAYS) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var origin := Vector2(eye.x, eye.z)
	for k in range(rays):
		var ang := TAU * float(k) / float(rays)
		var dir := Vector2(cos(ang), sin(ang))
		var start := origin + dir * base_r
		poly.append(start + dir * _sight_limited(eye, start, dir, range_m, volumes))
	return poly


## March one ray: how far (metres) along `dir` a target would still be visible from `eye`. The ray stops
## at the FIRST blocked sample — what lies beyond a shadow is dropped, so the polygon keeps the single
## boundary the renderer fills.
static func _sight_limited(eye: Vector3, start: Vector2, dir: Vector2, max_d: float,
		volumes: Array) -> float:
	var d := 0.0
	while d < max_d - 0.0001:
		var next_d := minf(d + STEP_M, max_d)
		if _blocked(eye, start + dir * next_d, volumes):
			return _refine_boundary(eye, start, dir, d, next_d, volumes)
		d = next_d
	return max_d


## The ONE sight truth, asked for a single ray sample: can `eye` see a model standing at the flat point
## `p`? Terrain only — other units' bases are not part of the range overlay.
static func _blocked(eye: Vector3, p: Vector2, volumes: Array) -> bool:
	var target_y := TARGET_EYE_IN * VolumetricLos.INCHES_TO_METERS
	# W4.18 RED STUB: the y-blind fan of today — every ray is fired from table level, whatever height
	# the model really stands at. W4.18 GREEN replaces this with the eye's own height.
	var eye_y := target_y
	return not VolumetricLos.has_los(
		{"c": Vector2(eye.x, eye.z), "r": 0.0, "y0": eye_y, "y1": eye_y},
		{"c": p, "r": 0.0, "y0": 0.0, "y1": target_y}, volumes)


## Bisect the exact stop distance inside (lo, hi]: at `lo` the ray was still running, at `hi` the sight
## was blocked. 4 iterations narrow the STEP_M quantisation to ~2.4mm so adjacent rays stop on the SAME
## terrain edge instead of different march steps (the fuzzy/jagged fan borders, field-test Bug 15).
static func _refine_boundary(eye: Vector3, start: Vector2, dir: Vector2, lo: float, hi: float,
		volumes: Array) -> float:
	for _i in range(REFINE_ITERS):
		var mid := (lo + hi) * 0.5
		if _blocked(eye, start + dir * mid, volumes):
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
