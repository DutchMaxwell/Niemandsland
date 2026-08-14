class_name SchoolTerrain
extends RefCounted
## Realism wave (maintainer directive 14.08.): the factory's tables come from
## the GAME'S OWN symmetric map layouter — ONE terrain source for table and
## school, the board_rows principle applied to terrain. The layouter Control
## is instantiated WITHOUT entering the tree (its generation path is pure
## data; the @onready UI never binds), seeded via the global rng exactly like
## the arena does, then converted to plain data through the same
## TerrainPrefabs helpers the real overlay consumes.

const CELL_IN := 3.0   # == map_layout.GRID_SIZE_INCHES / TerrainRules.CELL_IN
const IN2M := 0.0254


## -> {"cells": {Vector2i: TerrainType}, "n": grid_size,
##     "pieces": [[type, centre_x_in, centre_z_in, w_in, h_in, rot]]}
## `pieces` is the judge-bench drawing list; `cells` is the sim's truth.
static func generate(layout_seed: int, table_w_ft := 6.0, table_d_ft := 4.0) -> Dictionary:
	var ml: Control = (load("res://scripts/map_layout.gd") as GDScript).new()
	ml.table_size_feet = Vector2(table_w_ft, table_d_ft)
	ml.point_symmetry_enabled = true
	ml.grid_rotation_degrees = 0.0
	seed(layout_seed)
	ml._generate_terrain_layout()
	var n: int = ml._calculate_grid_dimensions().x
	var cells := {}
	var pieces: Array = []
	for piece in ml.placed_pieces:
		var key: String = piece["prefab_key"]
		var origin: Vector2i = piece["origin"]
		var rot: int = int(piece.get("rotation", 0))
		var flip: bool = bool(piece.get("flip", false))
		var ttype: int = TerrainPrefabs.terrain_type(key)
		for cell in TerrainPrefabs.footprint_cells(key, origin, rot, flip):
			cells[cell] = ttype
		var sz: Vector2i = TerrainPrefabs.footprint_size(key, rot)
		var c0 := cell_centre_in(origin, n)
		pieces.append([ttype,
			snappedf(c0.x + (sz.x - 1) * CELL_IN / 2.0, 0.1),
			snappedf(c0.y + (sz.y - 1) * CELL_IN / 2.0, 0.1),
			sz.x * CELL_IN, sz.y * CELL_IN, rot])
	ml.free()
	return {"cells": cells, "n": n, "pieces": pieces}


## Grid convention (map_layout): cell (x,y) centre sits at
## ((x - n/2 + 0.5) * 3", (y - n/2 + 0.5) * 3") relative to the TABLE CENTRE.
static func cell_centre_in(cell: Vector2i, n: int) -> Vector2:
	return Vector2((cell.x - n / 2.0 + 0.5) * CELL_IN, (cell.y - n / 2.0 + 0.5) * CELL_IN)


static func cell_of(x_in: float, z_in: float, n: int) -> Vector2i:
	return Vector2i(int(floor(x_in / CELL_IN + n / 2.0)), int(floor(z_in / CELL_IN + n / 2.0)))


## World-metres probe — the shape BattleSim's terrain_at seam expects.
static func type_at(world: Dictionary, pos: Vector3) -> int:
	return int((world["cells"] as Dictionary).get(
		cell_of(pos.x / IN2M, pos.z / IN2M, int(world["n"])), TerrainRules.TerrainType.NONE))


## Centre-line LOS block, v0: any RUINS, CONTAINER or FOREST cell strictly
## between the endpoints blocks (1"-step sampling; endpoint cells never block
## — a unit inside a ruin or wood sees out of it and can be seen).
static func los_blocked(world: Dictionary, a: Vector3, b: Vector3) -> bool:
	var cells: Dictionary = world["cells"]
	var n: int = int(world["n"])
	var av := Vector2(a.x / IN2M, a.z / IN2M)
	var bv := Vector2(b.x / IN2M, b.z / IN2M)
	var ca := cell_of(av.x, av.y, n)
	var cb := cell_of(bv.x, bv.y, n)
	var dist := av.distance_to(bv)
	var steps := maxi(int(dist), 1)
	for i in range(1, steps):
		var p := av.lerp(bv, float(i) / float(steps))
		var c := cell_of(p.x, p.y, n)
		if c == ca or c == cb:
			continue
		var t := int(cells.get(c, 0))
		if t == TerrainRules.TerrainType.RUINS or t == TerrainRules.TerrainType.CONTAINER \
				or t == TerrainRules.TerrainType.FOREST:
			return true
	return false
