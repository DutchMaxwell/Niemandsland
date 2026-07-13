class_name SeparationResolver
extends RefCounted
## Absolute anti-stacking resolution: two model bases may NEVER overlap (GF/AoF Advanced Rules v3.5.1
## p.7: models "may never move through other models or units, friendly or enemy"). This is the HARD
## physical no-stack rule, distinct from the 1" unit-spacing rule (which binds only BETWEEN units and has
## a Charge exception). Ported from the proximity-hint feature's drop-time resolver and reused, unchanged
## in spirit, by the Solo-AI movement gate: after the formation solver runs, every placed base is pushed
## out until it clears every other base by >= 0 gap — the invariant "ZERO overlapping bases after every AI
## move/deploy" (field-test finding 3: the solver reduced but did not eliminate overlap).
##
## PURE + STATIC: operates on SeparationChecker.BaseShapes (exact round / oval / rect geometry) + flat
## obstacle arrays, so the push direction, contact target and escape fallback are unit-tested directly.
## The caller builds the shapes, calls resolve_overlaps, and applies the returned world-XZ translation.
##
## The escape-scan fallback GUARANTEES termination with zero overlap for any FINITE obstacle set: if the
## resultant-vector relaxation stalls (a symmetric wedge cancels while overlap remains), the item is moved
## to the NEAREST fully-clear position instead (a finite set always has one).

# ===== Constants =====

## Inches -> metres (shared with SeparationChecker).
const INCHES_TO_METERS := 0.0254

## Numerical guard for near-zero lengths (metres); mirrors SeparationChecker.EPSILON_M.
const EPSILON_M := 0.00001

## Overlaps shallower than this (inches, ~0.25 mm) are float noise and left alone, so a resting placement
## does not jitter.
const RESOLVE_EPSILON_INCHES := 0.01

## Cap on ABSOLUTE anti-stacking relaxation passes: this pass must clear a base against EVERY other base
## (same unit included) and can need several relaxation steps to walk a wedged base out through a gap;
## still a hard bound before the directional escape fallback takes over.
const MAX_OVERLAP_ITERATIONS := 24

## Directions sampled by the escape scan (the fallback that guarantees a fully-surrounded placement still
## ends overlap-free): more = a tighter, shorter escape.
const ESCAPE_SCAN_DIRECTIONS := 24


# ===== Public API =====

## ABSOLUTE anti-stacking: no base in `item_shapes` may overlap (edge_distance < 0) any base in
## `obstacle_shapes` — for ANY pair (same unit, own other unit, enemy). Given the item's freshly-built
## BaseShapes (mutated in place) and a flat Array of obstacle BaseShapes (EVERY other alive base,
## unit-agnostic), relaxes the item out until it clears every obstacle by >= 0 gap, then returns the total
## world-XZ translation (metres). Base CONTACT (gap ~0) is left untouched — only true overlap is pushed.
## Uses a resultant-vector relaxation (naturally walks toward the least-crowded side). If a pathological
## FULLY-SURROUNDED placement still overlaps after the relaxation cap (e.g. a symmetric wedge the resultant
## cancels in), a directional escape scan moves the item to the NEAREST fully-clear position instead.
static func resolve_overlaps(item_shapes: Array, obstacle_shapes: Array) -> Vector2:
	if item_shapes.is_empty() or obstacle_shapes.is_empty():
		return Vector2.ZERO
	var applied := Vector2.ZERO
	for _iter in range(MAX_OVERLAP_ITERATIONS):
		var resultant := Vector2.ZERO       # summed penetration vectors (inches)
		var deepest := 0.0
		for s: SeparationChecker.BaseShape in item_shapes:
			for o: SeparationChecker.BaseShape in obstacle_shapes:
				var overlap := -SeparationChecker.edge_distance(s, o)  # positive when overlapping
				if overlap <= RESOLVE_EPSILON_INCHES:
					continue
				var axis := s.center - o.center
				if axis.length_squared() < EPSILON_M * EPSILON_M:
					axis = Vector2.RIGHT  # concentric: pick a stable arbitrary escape axis
				resultant += axis.normalized() * overlap
				deepest = maxf(deepest, overlap)
		if deepest <= RESOLVE_EPSILON_INCHES:
			return applied  # cleared
		if resultant.length() < RESOLVE_EPSILON_INCHES:
			# Symmetric wedge: the resultant cancels while overlap remains. Jump straight to the escape scan
			# rather than spend iterations oscillating in place.
			break
		var step := resultant * INCHES_TO_METERS
		_translate_shapes(item_shapes, step)
		applied += step

	# Still overlapping after the relaxation cap -> escape to the nearest clear spot.
	applied += _escape_to_clear(item_shapes, obstacle_shapes)
	return applied


# ===== Private =====

## Directional escape (fallback): moves item_shapes (mutated) to the NEAREST position that clears every
## obstacle, and returns that translation. Uses conservative bounding circles (a base is contained by its
## bounding circle, so bounding-circle clearance implies base clearance), scanning ESCAPE_SCAN_DIRECTIONS
## rays for the one needing the least travel. No-op when already clear. Guarantees termination with zero
## overlap for any finite set.
static func _escape_to_clear(item_shapes: Array, obstacle_shapes: Array) -> Vector2:
	var best_dir := Vector2.ZERO
	var best_travel := INF
	for k in range(ESCAPE_SCAN_DIRECTIONS):
		var ang := TAU * k / float(ESCAPE_SCAN_DIRECTIONS)
		var u := Vector2(cos(ang), sin(ang))
		var travel := _travel_to_clear_along(item_shapes, obstacle_shapes, u)
		if travel < best_travel:
			best_travel = travel
			best_dir = u
	if best_travel <= 0.0 or best_travel == INF:
		return Vector2.ZERO
	var step := best_dir * best_travel
	_translate_shapes(item_shapes, step)
	return step


## Smallest distance (metres) to slide item_shapes along unit direction `u` so every item-base bounding
## circle clears every obstacle bounding circle. Solves, per pair, the quadratic |e + t*u| >= Rsum for its
## upper root, and takes the max across all pairs.
static func _travel_to_clear_along(item_shapes: Array, obstacle_shapes: Array, u: Vector2) -> float:
	var travel := 0.0
	for s: SeparationChecker.BaseShape in item_shapes:
		for o: SeparationChecker.BaseShape in obstacle_shapes:
			var r_sum := s.bounding_radius() + o.bounding_radius()
			var e := s.center - o.center
			var e_len_sq := e.length_squared()
			if e_len_sq >= r_sum * r_sum:
				continue  # this pair already clear along any direction
			var e_dot_u := e.dot(u)
			# t^2 + 2(e.u) t + (|e|^2 - Rsum^2) = 0 ; upper root clears the pair.
			var disc := e_dot_u * e_dot_u - e_len_sq + r_sum * r_sum
			var t_pair := -e_dot_u + sqrt(maxf(disc, 0.0))
			travel = maxf(travel, t_pair)
	return travel


## Shifts every shape's centre by delta (world XZ, metres).
static func _translate_shapes(item_shapes: Array, delta: Vector2) -> void:
	for s: SeparationChecker.BaseShape in item_shapes:
		s.center += delta
