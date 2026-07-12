class_name SeparationResolver
extends RefCounted
## Drop-time position resolution for the unit-separation feature: minis must never
## interpenetrate, and a Charge must be able to reach clean base contact.
##
## Two behaviours, both computed as ONE translation applied to the dropped item before
## the move is recorded for undo / broadcast (so the resolved position travels the
## normal move path — MoveAction + MP sync carry it):
##
##  1. ANTI-STACKING PUSH-BACK — if a dropped base OVERLAPS a base of ANOTHER unit
##     (edge_distance < 0), slide the item outward along the centres axis until the gap
##     is ~0 (clean base contact). Applies to enemies (a legal Charge contact) AND
##     friendlies alike (the contact stays a violation the wall still marks amber, but
##     the minis never overlap). Resolved iteratively so a drop wedged between several
##     bases clears them all with the minimal moves.
##
##  2. MAGNETIC ENEMY CONTACT SNAP — a drop landing within SNAP_ENEMY_INCHES of an
##     ENEMY base edge (but not overlapping) snaps INWARD to kissing contact, so a
##     charge is easy to place and testable. No snap toward friendly bases (there is no
##     legal friendly contact to snap to).
##
## SCOPE: candidates are bases of OTHER units only (the rule binds BETWEEN units;
## SeparationChecker.effective_unit folds a joined Hero into its host). Same-unit
## spacing is coherency / formation, deliberately left alone here.
##
## PURE + STATIC: resolve_translation is scene-free (operates on BaseShapes + affiliation
## ints), so push-back direction, contact target and snap thresholds are unit-tested
## directly. The game (object_manager) builds the shapes, calls this on drop, and
## applies the returned translation to the node.

# ===== Constants =====

## Inches -> metres (shared with SeparationChecker).
const INCHES_TO_METERS := 0.0254

## A drop whose nearest ENEMY base edge is within this (and not overlapping) snaps to
## kissing contact. Kept small so only a deliberate near-miss charge snaps, never a
## model parked a comfortable inch away.
const SNAP_ENEMY_INCHES := 0.5

## Target edge gap (inches) both push-back and snap resolve to: clean base contact.
const CONTACT_TARGET_INCHES := 0.0

## Overlaps / snap offsets shallower than this (inches, ~0.25 mm) are float noise and
## left alone, so a resting drop does not jitter.
const RESOLVE_EPSILON_INCHES := 0.01

## Cap on push-back passes (a drop wedged between bases converges well within this).
const MAX_ITERATIONS := 8


# ===== Public API =====

## The world-XZ translation (metres) to apply to a dropped item so its member bases no
## longer overlap any candidate base, and — if eligible — it snaps to enemy contact.
## Pure: `item_shapes` are the item's freshly-built BaseShapes (their centres are
## mutated in place while solving); `candidates` is an Array of {shape, player_id}
## covering every OTHER unit's alive base. `item_player` is the item's army slot.
static func resolve_translation(item_shapes: Array, candidates: Array, item_player: int) -> Vector2:
	if item_shapes.is_empty() or candidates.is_empty():
		return Vector2.ZERO

	var applied := Vector2.ZERO
	applied += _resolve_overlaps(item_shapes, candidates)

	var snap := _snap_to_enemy(item_shapes, candidates, item_player)
	if snap != Vector2.ZERO:
		_translate_shapes(item_shapes, snap)
		applied += snap
		# A snap can nudge the item into a third base — clear any overlap it introduced.
		applied += _resolve_overlaps(item_shapes, candidates)

	return applied


# ===== Private =====

## Iteratively pushes the item out of its DEEPEST overlap (along the centres axis to
## the offending base) until nothing overlaps by more than the epsilon. Mutates the
## shapes' centres and returns the total translation applied.
static func _resolve_overlaps(item_shapes: Array, candidates: Array) -> Vector2:
	var applied := Vector2.ZERO
	for _iter in range(MAX_ITERATIONS):
		var deepest := RESOLVE_EPSILON_INCHES
		var push_dir := Vector2.ZERO
		var push_inches := 0.0
		for s: SeparationChecker.BaseShape in item_shapes:
			for c in candidates:
				var other: SeparationChecker.BaseShape = c["shape"]
				var gap := SeparationChecker.edge_distance(s, other)
				var overlap := -gap  # positive when overlapping
				if overlap > deepest:
					var axis := s.center - other.center
					if axis.length_squared() < SeparationZone.EPSILON_M * SeparationZone.EPSILON_M:
						axis = Vector2.RIGHT  # concentric: pick a stable arbitrary axis
					deepest = overlap
					push_dir = axis.normalized()
					push_inches = overlap
		if push_inches <= RESOLVE_EPSILON_INCHES:
			break
		var step := push_dir * push_inches * INCHES_TO_METERS
		_translate_shapes(item_shapes, step)
		applied += step
	return applied


## The inward translation to kiss the NEAREST enemy base within SNAP_ENEMY_INCHES, or
## zero. Does not mutate the shapes (the caller applies + re-checks overlaps).
static func _snap_to_enemy(item_shapes: Array, candidates: Array, item_player: int) -> Vector2:
	var best_gap := SNAP_ENEMY_INCHES
	var snap := Vector2.ZERO
	for s: SeparationChecker.BaseShape in item_shapes:
		for c in candidates:
			if not SeparationChecker.are_enemy_players(item_player, int(c["player_id"])):
				continue
			var other: SeparationChecker.BaseShape = c["shape"]
			var gap := SeparationChecker.edge_distance(s, other)
			if gap <= CONTACT_TARGET_INCHES + RESOLVE_EPSILON_INCHES:
				continue  # already touching / overlapping -> push-back's job, not snap
			if gap <= best_gap:
				var axis := other.center - s.center  # pull the item TOWARD the enemy
				if axis.length_squared() < SeparationZone.EPSILON_M * SeparationZone.EPSILON_M:
					continue
				best_gap = gap
				snap = axis.normalized() * gap * INCHES_TO_METERS
	return snap


## Shifts every shape's centre by delta (world XZ, metres).
static func _translate_shapes(item_shapes: Array, delta: Vector2) -> void:
	for s: SeparationChecker.BaseShape in item_shapes:
		s.center += delta
