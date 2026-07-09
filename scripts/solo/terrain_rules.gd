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
##   RUINS      Cover, Blocks LoS             (Height 5)
##   FOREST     Difficult, Cover, Blocks LoS  (Height 5)
##   CONTAINER  Impassable, Blocks LoS        (Height 5)
##   DANGEROUS  Dangerous Terrain             (Ground)

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


static func is_difficult(t: int) -> bool:
	return t == TerrainType.FOREST


static func is_dangerous(t: int) -> bool:
	return t == TerrainType.DANGEROUS


static func is_impassable(t: int) -> bool:
	return t == TerrainType.CONTAINER


# === Grid lookup ===

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

## True if `from_pt` can see `to_pt`. A blocking zone the line crosses blocks LOS only when (a) neither
## endpoint stands inside that same zone ("see in/out of your own zone, not through someone else's") AND
## (b) the zone's Height >= BOTH endpoints' Height categories. Points and cell_size share one unit
## (inches in the sim, metres in the game).
static func has_line_of_sight(grid_cells: Dictionary, from_pt: Vector2, to_pt: Vector2,
		from_h: int, to_h: int, cell_size: float = CELL_IN) -> bool:
	if grid_cells.is_empty():
		return true
	var from_zone := flood_fill_zone(grid_cells, cell_of(from_pt, cell_size))
	var to_zone := flood_fill_zone(grid_cells, cell_of(to_pt, cell_size))
	var span := from_pt.distance_to(to_pt)
	var steps := int(ceil(span / (cell_size * 0.5)))
	if steps < 2:
		return true
	for i in range(1, steps):   # skip the exact endpoints
		var cell := cell_of(from_pt.lerp(to_pt, float(i) / float(steps)), cell_size)
		var ttype: int = int(grid_cells.get(cell, TerrainType.NONE))
		if not blocks_los(ttype):
			continue
		if from_zone.has(cell) or to_zone.has(cell):
			continue   # own zone: you see in/out of it
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
