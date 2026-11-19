class_name BoardgenGreybox
extends Node3D
## Greybox 3D of a seeded boardgen layout (NmlCore.boardgen_layout): one raised block per run of same-level cells (flat
## neutral colour per tier; a tier edge is simply the block's plain wall), stairs as stepped boxes, ladders as rails and
## rungs. A dev view only (debug build + NML_BOARDGEN_SEED=<seed>); no menu offers it.
##
## VISUAL ONLY for the rules: the terrain code the sight and move rules read (sandbox shapes, TerrainRules) has no
## per-cell height - a solid is the fixed 2.5 in container - so nothing here is handed to it and the core still sees a
## flat table. The raised blocks and the stair steps do carry colliders on the ground layer, so the drag floor-picker
## and the camera rays land on the tiers.

const ENV_SEED := "NML_BOARDGEN_SEED"
## setup_table (load, resize) frees the table's other children; this group keeps the board.
const TABLE_OVERLAY_GROUP := "table_overlay"
const INCHES_TO_METERS := 0.0254
const GROUND_COLLISION_LAYER := 1
## Thickness of the level-0 ground skin that covers the biome texture, in inches.
const SKIN_IN := 0.04
const STAIR_STEPS := 3
const STAIR_WIDTH_IN := 2.0
const STAIR_RUN_IN := 0.75
const LADDER_WIDTH_IN := 1.0
const LADDER_OFFSET_IN := 0.12   # the ladder stands this far off the wall face
const LADDER_RAIL_IN := 0.12
const LADDER_RUNG_GAP_IN := 0.5
const COLOURS := {
	"street": Color(0.30, 0.30, 0.31), "ground": Color(0.22, 0.22, 0.23), "hazard": Color(0.12, 0.19, 0.24),
	"tier1": Color(0.42, 0.42, 0.44), "tier2": Color(0.62, 0.62, 0.65),
	"stair": Color(0.80, 0.80, 0.83), "ladder": Color(0.90, 0.62, 0.20),
}

var layout_seed: int = 0


## The board of NML_BOARDGEN_SEED on `table`, or null when the flag is off (release build, unset or not an integer).
static func attach_from_env(table: Node) -> BoardgenGreybox:
	var raw := OS.get_environment(ENV_SEED).strip_edges()
	if not OS.is_debug_build() or not raw.is_valid_int() or not ClassDB.class_exists("NmlCore"):
		return null
	var core: Object = ClassDB.instantiate("NmlCore")
	if not core.has_method("boardgen_layout"):
		push_error("BoardgenGreybox: this NmlCore has no boardgen_layout")
		return null
	return attach(table, core.boardgen_layout(int(raw)))


static func attach(table: Node, layout: Dictionary) -> BoardgenGreybox:
	var node := BoardgenGreybox.new()
	node.name = "BoardgenGreybox"
	node.add_to_group(TABLE_OVERLAY_GROUP)
	node.build(layout)
	table.add_child(node)
	return node


## Every box of the board in inches (origin = board centre, y up): {lo, hi, kind, solid}. Pure data.
static func plan(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var level_in: Array = layout["level_in"]
	var cells: Array = layout["cells"]
	var origin := Vector2(nx, nz) * cell_in * -0.5
	# Blocks: runs of same-kind cells along x. Level 0 is a thin skin coloured by what the cell is.
	for z in nz:
		var x := 0
		while x < nx:
			var kind := _cell_kind(cells[z * nx + x])
			var run := 1
			while x + run < nx and _cell_kind(cells[z * nx + x + run]) == kind:
				run += 1
			var level: int = cells[z * nx + x]["level"]
			out.append({"lo": Vector3(origin.x + x * cell_in, 0.0, origin.y + z * cell_in),
				"hi": Vector3(origin.x + (x + run) * cell_in, float(level_in[level]) if level > 0 else SKIN_IN, origin.y + (z + 1) * cell_in),
				"kind": kind, "solid": level > 0})
			x += run
	for c: Dictionary in layout["connectors"]:
		var base: float = level_in[cells[c["low"]]["level"]]
		var rise: float = level_in[cells[c["high"]]["level"]] - base
		var edge := Vector2(c["edge_in"][0], c["edge_in"][1]) + origin
		var away := Vector2(Vector2i(c["low_xz"][0], c["low_xz"][1]) - Vector2i(c["high_xz"][0], c["high_xz"][1]))   # wall -> low cell
		var side := Vector2(away.y, away.x)   # along the edge
		if c["kind"] == "Stair":
			for i in STAIR_STEPS:
				out.append(_slab(edge, away, side, i * STAIR_RUN_IN, (i + 1) * STAIR_RUN_IN, STAIR_WIDTH_IN,
					base, base + rise * (STAIR_STEPS - i) / STAIR_STEPS, "stair", true))
			continue
		for s: float in [-1.0, 1.0]:
			out.append(_slab(edge + side * s * LADDER_WIDTH_IN * 0.5, away, side, LADDER_OFFSET_IN,
				LADDER_OFFSET_IN + LADDER_RAIL_IN, LADDER_RAIL_IN, base, base + rise, "ladder", false))
		for k in range(1, int(rise / LADDER_RUNG_GAP_IN)):
			out.append(_slab(edge, away, side, LADDER_OFFSET_IN, LADDER_OFFSET_IN + LADDER_RAIL_IN, LADDER_WIDTH_IN,
				base + k * LADDER_RUNG_GAP_IN, base + k * LADDER_RUNG_GAP_IN + LADDER_RAIL_IN, "ladder", false))
	return out


static func _cell_kind(cell: Dictionary) -> String:
	if cell["level"] > 0:
		return "tier%d" % cell["level"]
	if cell["lot_kind"] == "Hazard":
		return "hazard"
	return "street" if cell["street"] else "ground"


## A box `from..to` inches off `edge` along `away`, `width` wide along `side`, between heights `y0` and `y1`.
static func _slab(edge: Vector2, away: Vector2, side: Vector2, from: float, to: float, width: float, y0: float, y1: float,
		kind: String, solid: bool) -> Dictionary:
	var p := edge + away * (from + to) * 0.5
	var half := (away.abs() * (to - from) + side.abs() * width) * 0.5
	return {"lo": Vector3(p.x - half.x, y0, p.y - half.y), "hi": Vector3(p.x + half.x, y1, p.y + half.y), "kind": kind, "solid": solid}


## One BoxMesh per box (one shared material per kind) plus a collider per solid box.
func build(layout: Dictionary) -> void:
	layout_seed = int(layout.get("seed", 0))
	var body := StaticBody3D.new()
	body.name = "Colliders"
	body.collision_layer = GROUND_COLLISION_LAYER
	body.collision_mask = 0
	add_child(body)
	var mats := {}
	for b: Dictionary in plan(layout):
		var size: Vector3 = (b["hi"] - b["lo"]) * INCHES_TO_METERS
		var centre: Vector3 = (b["hi"] + b["lo"]) * 0.5 * INCHES_TO_METERS
		if not mats.has(b["kind"]):
			mats[b["kind"]] = StandardMaterial3D.new()
			mats[b["kind"]].albedo_color = COLOURS[b["kind"]]
			mats[b["kind"]].roughness = 0.95
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = mats[b["kind"]]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = centre
		add_child(mi)
		if b["solid"]:
			var shape := BoxShape3D.new()
			shape.size = size
			var col := CollisionShape3D.new()
			col.shape = shape
			col.position = centre
			body.add_child(col)
