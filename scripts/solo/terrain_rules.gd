class_name TerrainRules
extends RefCounted
## Pure, headless terrain rules for the Solo-AI — the SAME model the real game's terrain_overlay.gd uses:
## a grid of typed cells (Dictionary[Vector2i -> TerrainType], 3" cells). This module is unit-agnostic
## (works in inches for the simulator, metres for the game), has NO scene/mesh/physics dependency, and
## copies terrain_overlay's classification + line-of-sight algorithm verbatim. So both the headless
## simulator (now) and terrain_overlay (at game-integration, P3, by delegating to it) share ONE source of
## truth for LOS + Cover + Difficult + Dangerous — exactly the way AiDecision is shared for the decision
## trees. Do not fork the semantics here from terrain_overlay.gd.
##
## Terrain effects (GF Advanced Rules v3.5.1 p.11-12; mirrors terrain_overlay._terrain_effect_label):
##   RUINS      Cover, Blocks LoS (area — see in/out, not through)  (Height 5)
##   FOREST     Difficult, Cover, Blocks LoS (area — see in/out, not through)  (Height 5)
##   CONTAINER  Impassable, Blocks LoS (solid — hard-block)         (Height 5)
##   DANGEROUS  Dangerous Terrain                                   (Ground)
## RUINS and FOREST are AREA terrain (p.12 "see into and out of forests, but not through them" — the
## maintainer applies the same to ruins); a sight line is only blocked when it passes all the way THROUGH
## the zone to a target beyond. CONTAINERS are solid Impassable+Blocking buildings and hard-block outright.

enum TerrainType { NONE = 0, RUINS = 1, FOREST = 2, CONTAINER = 3, DANGEROUS = 4 }

const CELL_IN := 3.0    # == terrain_overlay.GRID_SIZE_INCHES: one terrain cell is 3"x3"
const BLOCKER_HEIGHT := 5   # Height category of a LOS-blocking zone (terrain_overlay.terrain_height_category)


# === Type predicates (identical to terrain_overlay's classification) ===

static func blocks_los(t: int) -> bool:
	return t == TerrainType.RUINS or t == TerrainType.FOREST or t == TerrainType.CONTAINER


## Asgard Height category of a terrain type (blockers are Height 5; open ground = 0).
static func height_category(t: int) -> int:
	return BLOCKER_HEIGHT if blocks_los(t) else 0


static func gives_cover(t: int) -> bool:
	return t == TerrainType.RUINS or t == TerrainType.FOREST


## AREA terrain (Forests + Ruins): you see INTO and OUT OF it, but not completely THROUGH it (GF/AoF v3.5.1
## p.12). Containers are solid Impassable+Blocking buildings — NOT area terrain, so they hard-block LOS and
## the see-in/out zone exception in has_line_of_sight() does not apply to them.
static func is_area_terrain(t: int) -> bool:
	return t == TerrainType.RUINS or t == TerrainType.FOREST


static func is_difficult(t: int) -> bool:
	return t == TerrainType.FOREST


static func is_dangerous(t: int) -> bool:
	return t == TerrainType.DANGEROUS


static func is_impassable(t: int) -> bool:
	return t == TerrainType.CONTAINER


## Forbidden-to-REST terrain: a model may not END its move standing with any part of its base in impassable
## (CONTAINER — GF/AoF Advanced Rules v3.5.1: a base "may never move through" it) or DANGEROUS terrain, nor in
## RUINS (whose internal walls are impassable to movement). The class selector for the base-containment
## no-rest check (base_in_terrain).
static func is_forbidden_rest(t: int) -> bool:
	# RUINS removed (maintainer 2026-07-16): a model MAY end its move in a ruin — cover terrain you stand
	# in; only the WALL SEGMENTS block (enforced separately, incl. the rest test in _world_forbidden).
	# DANGEROUS removed too (Windows playtest bug 4b): OPR expressly ALLOWS ending a move in dangerous
	# terrain — it only costs the tests (p.12). The hard no-rest made any dangerous field DEEPER than one
	# move band uncrossable: the placement gate shortened every in-field endpoint back to ~start, so units
	# froze at the field edge for the whole game (the diagnosed GATE-COLLAPSE stubs). The planner's 6x
	# soft cost + route-around still prevent thoughtless parking; only truly impassable CONTAINER remains.
	return t == TerrainType.CONTAINER


# === Base-in-terrain containment (THE single predicate — GF/AoF Advanced Rules v3.5.1) ==============
# Terrain-containment rule (core rulebook, terrain guidelines): a model counts as being IN a piece of terrain
# if ANY part of its base overlaps that terrain — a base even slightly inside a piece of terrain is in it (not
# centre-in, not majority-of-base). Every terrain-EFFECT trigger (difficult 6" cap, dangerous test, the
# impassable/dangerous no-rest gate) and the movement/placement collision boundary key on the base's OUTER
# EDGE through this ONE predicate, so no call site re-implements the geometry (field-test round 6, finding 6).
# (Cover is deliberately NOT routed here: OPR cover keys on the majority of a unit being FULLY inside cover,
# not on partial "in terrain" — a different rule, handled by majority_in_cover.)

const BASE_RING_SAMPLES := 16   # perimeter samples around the base edge (terrain features ≫ base → ample)

## True when a base of `radius` centred at `centre` OVERLAPS terrain for which `class_check.call(type)` holds
## — the base is IN that terrain if any part of it is (partial overlap suffices). `sample_type` is a
## Callable(pos) -> int terrain-type lookup at a point (grid cells AND spawned footprints); `centre`/`radius`
## are in the sampler's own units (world metres for the game overlay). Tests the base CENTRE plus a full
## perimeter ring at the base edge: a base whose edge dips in by any amount registers, a base clear by any
## margin does not. Pure + deterministic (given the callables). `centre` is Vector3 (game world) or Vector2.
static func base_in_terrain(centre, radius: float, sample_type: Callable, class_check: Callable) -> bool:
	if not sample_type.is_valid():
		return false
	if class_check.call(int(sample_type.call(centre))):
		return true
	if radius <= 0.0:
		return false
	var is3 := centre is Vector3
	for k in range(BASE_RING_SAMPLES):
		var ang := TAU * float(k) / float(BASE_RING_SAMPLES)
		var edge = (centre + Vector3(cos(ang) * radius, 0.0, sin(ang) * radius)) if is3 \
			else (centre + Vector2(cos(ang) * radius, sin(ang) * radius))
		if class_check.call(int(sample_type.call(edge))):
			return true
	return false


# === Grid lookup ===

## NML-001 (Shelf-Terrain-Welle) — pure OBB-Mathematik für frei platzierte Terrain-Stücke
## (Regal-Ruinen/Wälder/Gefahrenfelder): Punkt-in-Box und Segment-Schnitt gegen eine um `yaw`
## (Node-rotation.y-Konvention: lokal +X -> (cos, -sin) in XZ) gedrehte Box mit Halbausdehnung he.
static func point_in_obb(p: Vector2, c: Vector2, he: Vector2, yaw: float) -> bool:
	var dx := Vector2(cos(yaw), -sin(yaw))
	var dz := Vector2(sin(yaw), cos(yaw))
	var d := p - c
	return absf(d.dot(dx)) <= he.x and absf(d.dot(dz)) <= he.y


static func obb_corners(c: Vector2, he: Vector2, yaw: float) -> Array:
	var dx := Vector2(cos(yaw), -sin(yaw)) * he.x
	var dz := Vector2(sin(yaw), cos(yaw)) * he.y
	return [c + dx + dz, c + dx - dz, c - dx - dz, c - dx + dz]


static func segment_intersects_obb(a: Vector2, b: Vector2, c: Vector2, he: Vector2, yaw: float) -> bool:
	if point_in_obb(a, c, he, yaw) or point_in_obb(b, c, he, yaw):
		return true
	var k := obb_corners(c, he, yaw)
	for i in range(4):
		if Geometry2D.segment_intersects_segment(a, b, k[i], k[(i + 1) % 4]) != null:
			return true
	return false


static func cell_of(p: Vector2, cell_size: float = CELL_IN) -> Vector2i:
	return Vector2i(int(floor(p.x / cell_size)), int(floor(p.y / cell_size)))


static func terrain_at(grid_cells: Dictionary, p: Vector2, cell_size: float = CELL_IN) -> int:
	return int(grid_cells.get(cell_of(p, cell_size), TerrainType.NONE))


## All cells of the contiguous same-type terrain zone containing `start_cell` (4-connected). Empty set if
## start_cell holds no terrain. Copied from terrain_overlay._flood_fill_zone.
static func flood_fill_zone(grid_cells: Dictionary, start_cell: Vector2i) -> Dictionary:
	var result := {}
	var ttype: int = int(grid_cells.get(start_cell, TerrainType.NONE))
	if ttype == TerrainType.NONE:
		return result
	var stack: Array[Vector2i] = [start_cell]
	result[start_cell] = true
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for nb in [Vector2i(c.x + 1, c.y), Vector2i(c.x - 1, c.y), Vector2i(c.x, c.y + 1), Vector2i(c.x, c.y - 1)]:
			if not result.has(nb) and int(grid_cells.get(nb, TerrainType.NONE)) == ttype:
				result[nb] = true
				stack.append(nb)
	return result


# === Line of sight (top-down; copied from terrain_overlay.has_line_of_sight, 2D) ===

## True if `from_pt` can see `to_pt`. A blocking zone the line crosses blocks LOS only when (a) for AREA
## terrain (Forests + Ruins) neither endpoint stands inside that same zone ("see in/out of your own zone,
## not through someone else's"); solid CONTAINERS skip this exception and hard-block. AND (b) the zone's
## Height >= BOTH endpoints' Height categories. Points and cell_size share one unit (inches in the sim,
## metres in the game).
static func has_line_of_sight(grid_cells: Dictionary, from_pt: Vector2, to_pt: Vector2,
		from_h: int, to_h: int, cell_size: float = CELL_IN) -> bool:
	if grid_cells.is_empty():
		return true
	var from_zone := flood_fill_zone(grid_cells, cell_of(from_pt, cell_size))
	var to_zone := flood_fill_zone(grid_cells, cell_of(to_pt, cell_size))
	var span := from_pt.distance_to(to_pt)
	# Quarter-cell sampling with a guaranteed midpoint (container wave — mirrors the overlay
	# copy): the old half-cell walk skipped corners and granted every span under one cell.
	var steps := maxi(int(ceil(span / (cell_size * 0.25))), 4)
	if span < 0.02:
		return true
	for i in range(1, steps):   # skip the exact endpoints
		var cell := cell_of(from_pt.lerp(to_pt, float(i) / float(steps)), cell_size)
		var ttype: int = int(grid_cells.get(cell, TerrainType.NONE))
		if not blocks_los(ttype):
			continue
		if is_area_terrain(ttype) and (from_zone.has(cell) or to_zone.has(cell)):
			continue   # area terrain: you see IN/OUT of your own zone — just not through someone else's
		var th := height_category(ttype)
		if th >= from_h and th >= to_h:
			return false
	return true


# === Cover & movement helpers (built on the same grid) ===

## OPR Cover (p.11): a unit gets +1 Defense when the MAJORITY of its models sit in cover terrain.
static func majority_in_cover(model_positions: Array, grid_cells: Dictionary, cell_size: float = CELL_IN) -> bool:
	if model_positions.is_empty() or grid_cells.is_empty():
		return false
	var n_cover := 0
	for m in model_positions:
		if gives_cover(terrain_at(grid_cells, m as Vector2, cell_size)):
			n_cover += 1
	return n_cover * 2 > model_positions.size()   # strict majority


## True if the straight path a->b touches any cell for which `check` holds. `check` is one of the
## predicate ids below (avoids Callable overhead in the hot movement path).
enum PathCheck { DIFFICULT, DANGEROUS, IMPASSABLE }


static func path_crosses(grid_cells: Dictionary, a: Vector2, b: Vector2, check: int,
		cell_size: float = CELL_IN) -> bool:
	if grid_cells.is_empty():
		return false
	var span := a.distance_to(b)
	var steps := maxi(1, int(ceil(span / (cell_size * 0.5))))
	for i in range(steps + 1):
		var t: int = int(grid_cells.get(cell_of(a.lerp(b, float(i) / float(steps)), cell_size), TerrainType.NONE))
		match check:
			PathCheck.DIFFICULT:
				if is_difficult(t):
					return true
			PathCheck.DANGEROUS:
				if is_dangerous(t):
					return true
			PathCheck.IMPASSABLE:
				if is_impassable(t):
					return true
	return false
