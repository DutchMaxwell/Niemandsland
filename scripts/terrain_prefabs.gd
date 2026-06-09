extends RefCounted
class_name TerrainPrefabs
## Canonical OPR tournament terrain pieces (Asgard rulebook, 6x4' table).
##
## Each prefab expands into the existing map-layout data formats — grid_cells
## (footprint), wall_segments (auto-suggested ruin walls) and placed_objects
## (trees / containers / dangerous hazards) — so the existing 3D renderer in
## terrain_overlay.gd handles them unchanged.
##
## Pieces (per rulebook): Ruine 9x9/9x6 (Cover + impassable walls), Wald 9x9
## (Difficult + Cover), Blocker 6x3 (Impassable + Blocking), Dangerous 9x6.

# ==============================================================================
# CONSTANTS
# ==============================================================================

## Terrain type ids — mirror map_layout.gd / terrain_overlay.gd TerrainType enum.
const TYPE_RUINS := 1
const TYPE_FOREST := 2
const TYPE_CONTAINER := 3
const TYPE_DANGEROUS := 4

## Wall key for procedurally-rendered terrain walls (no GLB / theme required).
const PROC_WALL_KEY := "__proc__"

## Edge side ids — mirror map_layout.gd (0=North, 1=East, 2=South, 3=West).
const EDGE_NORTH := 0
const EDGE_EAST := 1
const EDGE_SOUTH := 2
const EDGE_WEST := 3

## Default segment length for an auto-placed ruin wall (one 3" grid edge).
const WALL_SEGMENT_INCHES := 3.0

## Decoration density (objects per 3" footprint cell).
const TREES_PER_CELL := 0.6
const HAZARDS_PER_CELL := 0.5

## Object placement margins within a cell (keeps props off the cell borders).
const OFFSET_MIN := 0.2
const OFFSET_MAX := 0.8

## Canonical pieces keyed by palette id (insertion order = palette display order).
## size = footprint in 3" cells; wall_shape "L" = walls on north + west outer edges.
const PREFABS := {
	"ruine_9x9": {
		"display": "Ruine 9×9",
		"type": TYPE_RUINS,
		"size": Vector2i(3, 3),
		"wall_shape": "L",
		"deco": "",
	},
	"ruine_9x6": {
		"display": "Ruine 9×6",
		"type": TYPE_RUINS,
		"size": Vector2i(3, 2),
		"wall_shape": "L",
		"deco": "",
	},
	"wald_9x9": {
		"display": "Wald 9×9",
		"type": TYPE_FOREST,
		"size": Vector2i(3, 3),
		"wall_shape": "",
		"deco": "trees",
	},
	"blocker_6x3": {
		"display": "Blocker 6×3",
		"type": TYPE_CONTAINER,
		"size": Vector2i(2, 1),
		"wall_shape": "",
		"deco": "containers",
	},
	"dangerous_9x6": {
		"display": "Dangerous 9×6",
		"type": TYPE_DANGEROUS,
		"size": Vector2i(3, 2),
		"wall_shape": "",
		"deco": "dangerous",
	},
}

# ==============================================================================
# PUBLIC
# ==============================================================================

## All palette ids in display order.
static func keys() -> Array[String]:
	var result: Array[String] = []
	for k in PREFABS:
		result.append(k)
	return result

static func has_prefab(prefab_key: String) -> bool:
	return PREFABS.has(prefab_key)

static func display_name(prefab_key: String) -> String:
	var def: Dictionary = PREFABS.get(prefab_key, {})
	return def.get("display", prefab_key)

static func terrain_type(prefab_key: String) -> int:
	var def: Dictionary = PREFABS.get(prefab_key, {})
	return def.get("type", 0)

## Footprint size in cells. At 90°/270° the width/height swap (3×2 → 2×3).
static func footprint_size(prefab_key: String, rotation: int = 0) -> Vector2i:
	var def: Dictionary = PREFABS.get(prefab_key, {})
	var size: Vector2i = def.get("size", Vector2i.ONE)
	if posmod(rotation / 90, 2) == 1:
		return Vector2i(size.y, size.x)
	return size


## Footprint cells of a prefab whose bounding-box top-left cell is `origin`, with the
## piece flipped (mirror X) then rotated clockwise by `rotation` (0/90/180/270).
static func footprint_cells(prefab_key: String, origin: Vector2i, rotation: int = 0, flip: bool = false) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not PREFABS.has(prefab_key):
		return cells
	var size: Vector2i = PREFABS[prefab_key]["size"]
	for dx in range(size.x):
		for dy in range(size.y):
			cells.append(origin + _transform_cell(dx, dy, size.x, size.y, rotation, flip))
	return cells


## Auto-suggested ruin walls: TWO point-symmetric L-corners (per the agreed design — see
## docs/HANDOFF_RUIN_WALLS.md). The NW corner carries the north edge (cols 0..X-2) + west
## edge (rows 0..Y-2); the SE corner carries the south edge (cols 1..X-1) + east edge
## (rows 1..Y-1). So each arm is (size-1) cells and the centre/opposite corners stay open.
## Each segment gets a "role": "full" at the corner, "crumble_*" toward the free end (the
## wall steps down to the open ends). Transformed by the same flip+rotation. Non-ruins: [].
static func wall_segments_for(prefab_key: String, origin: Vector2i, rotation: int = 0, flip: bool = false) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	if not PREFABS.has(prefab_key):
		return segments
	if PREFABS[prefab_key].get("wall_shape", "") != "L":
		return segments
	var size: Vector2i = PREFABS[prefab_key]["size"]
	var sx: int = size.x
	var sy: int = size.y
	# NW corner L (free ends point toward +X / +Z)
	for dx in range(sx - 1):
		var seg := _oriented_wall(Vector2i(dx, 0), EDGE_NORTH, origin, size, rotation, flip)
		seg["role"] = _crumble_role(dx, sx - 1)
		segments.append(seg)
	for dy in range(sy - 1):
		var seg := _oriented_wall(Vector2i(0, dy), EDGE_WEST, origin, size, rotation, flip)
		seg["role"] = _crumble_role(dy, sy - 1)
		segments.append(seg)
	# SE corner L (free ends point toward -X / -Z) — point-symmetric to the NW corner
	for dx in range(1, sx):
		var seg := _oriented_wall(Vector2i(dx, sy - 1), EDGE_SOUTH, origin, size, rotation, flip)
		seg["role"] = _crumble_role((sx - 1) - dx, sx - 1)
		segments.append(seg)
	for dy in range(1, sy):
		var seg := _oriented_wall(Vector2i(sx - 1, dy), EDGE_EAST, origin, size, rotation, flip)
		seg["role"] = _crumble_role((sy - 1) - dy, sy - 1)
		segments.append(seg)
	return segments


## Decoration objects (trees / containers / dangerous hazards) for a prefab footprint.
## Returns placed_object dicts in the existing map_layout format. Pass an `rng` for
## deterministic placement (tests); otherwise a fresh randomized generator is used.
static func decoration_for(prefab_key: String, origin: Vector2i, rng: RandomNumberGenerator = null, rotation: int = 0, flip: bool = false) -> Array[Dictionary]:
	var objects: Array[Dictionary] = []
	if not PREFABS.has(prefab_key):
		return objects
	var deco: String = PREFABS[prefab_key].get("deco", "")
	if deco.is_empty():
		return objects

	var cells := footprint_cells(prefab_key, origin, rotation, flip)
	if cells.is_empty():
		return objects
	var r := rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()

	match deco:
		"trees":
			var count := int(ceil(float(cells.size()) * TREES_PER_CELL))
			for i in range(count):
				var cell: Vector2i = cells[r.randi() % cells.size()]
				objects.append(_object(cell, "tree", _random_offset(r)))
		"containers":
			# One container centered on the footprint, aligned to its (rotated) long axis.
			var sum := Vector2.ZERO
			for c in cells:
				sum += Vector2(c.x - origin.x + 0.5, c.y - origin.y + 0.5)
			var center := sum / float(cells.size())
			var entry := _object(origin, "container", center)
			entry["angle_deg"] = rotation
			objects.append(entry)
		"dangerous":
			var count := int(ceil(float(cells.size()) * HAZARDS_PER_CELL))
			for i in range(count):
				var cell: Vector2i = cells[r.randi() % cells.size()]
				var kind := "mine" if i % 2 == 0 else "puddle"
				objects.append(_object(cell, kind, _random_offset(r)))
	return objects

# ==============================================================================
# PRIVATE
# ==============================================================================

static func _wall(edge_cell: Vector2i, edge_side: int) -> Dictionary:
	return {
		"edge_cell": edge_cell,
		"edge_side": edge_side,
		"wall_key": PROC_WALL_KEY,
		"length_inches": WALL_SEGMENT_INCHES,
		"sub_position": 0,
	}


## Wall role by distance from its corner along an arm of `arm_len` cells. The corner cell
## is "full"; cells toward the free end crumble down (so the ruin descends to open ends).
## A renderer maps the role to a texture/height; see docs/HANDOFF_RUIN_WALLS.md.
static func _crumble_role(dist_from_corner: int, arm_len: int) -> String:
	if arm_len <= 1 or dist_from_corner == 0:
		return "full"
	if arm_len == 2:
		return "crumble_steep"
	if dist_from_corner == arm_len - 1:
		return "crumble_b"
	if dist_from_corner == arm_len - 2:
		return "crumble_a"
	return "full"


static func _object(cell: Vector2i, object_type: String, offset: Vector2) -> Dictionary:
	return {
		"object_key": object_type,
		"cell": cell,
		"offset": offset,
		"object_type": object_type,
	}


static func _random_offset(r: RandomNumberGenerator) -> Vector2:
	return Vector2(r.randf_range(OFFSET_MIN, OFFSET_MAX), r.randf_range(OFFSET_MIN, OFFSET_MAX))


## Build a wall segment for a local cell+side, transformed by flip+rotation onto origin.
static func _oriented_wall(local_cell: Vector2i, side: int, origin: Vector2i, size: Vector2i, rotation: int, flip: bool) -> Dictionary:
	var cell := origin + _transform_cell(local_cell.x, local_cell.y, size.x, size.y, rotation, flip)
	return _wall(cell, _transform_edge(side, rotation, flip))


## Transform a local cell (lx,ly) in a w×h footprint: flip (mirror X) then rotate CW.
## The result is anchored so the bounding-box top-left is (0,0).
static func _transform_cell(lx: int, ly: int, w: int, h: int, rotation: int, flip: bool) -> Vector2i:
	var x := lx
	var y := ly
	var cw := w
	var ch := h
	if flip:
		x = cw - 1 - x
	var steps := posmod(rotation / 90, 4)
	for _i in range(steps):
		# 90° clockwise: (x,y) in cw×ch -> (ch-1-y, x) in ch×cw
		var nx := ch - 1 - y
		var ny := x
		x = nx
		y = ny
		var tmp := cw
		cw = ch
		ch = tmp
	return Vector2i(x, y)


## Transform an edge side by flip (E<->W) then rotation (each 90° CW: N->E->S->W).
static func _transform_edge(side: int, rotation: int, flip: bool) -> int:
	var s := side
	if flip:
		if s == EDGE_EAST:
			s = EDGE_WEST
		elif s == EDGE_WEST:
			s = EDGE_EAST
	return posmod(s + rotation / 90, 4)
