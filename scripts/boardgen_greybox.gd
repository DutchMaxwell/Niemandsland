class_name BoardgenGreybox
extends Node3D
## Greybox 3D of a seeded boardgen layout (NmlCore.boardgen_layout): one raised block per run of same-level cells (flat
## neutral colour per tier; a tier edge is simply the block's plain wall) and ladders as rails and rungs - the only way
## up, there are no stairs (models stand on flat whole cells only). A dev view only (debug build +
## NML_BOARDGEN_SEED=<seed>); no menu offers it.
##
## VISUAL ONLY for the rules: the terrain code the sight and move rules read (sandbox shapes, TerrainRules) has no
## per-cell height - a solid is the fixed 2.5 in container - so nothing here is handed to it and the core still sees a
## flat table. The raised blocks do carry colliders on the ground layer, so the drag floor-picker and the camera rays
## land on the tiers.

const ENV_SEED := "NML_BOARDGEN_SEED"
## setup_table (load, resize) frees the table's other children; this group keeps the board.
const TABLE_OVERLAY_GROUP := "table_overlay"
const INCHES_TO_METERS := 0.0254
const GROUND_COLLISION_LAYER := 1
## Thickness of the level-0 ground skin that covers the biome texture, in inches.
const SKIN_IN := 0.04
const LADDER_WIDTH_IN := 1.0
const LADDER_OFFSET_IN := 0.12   # the ladder stands this far off the wall face
const LADDER_RAIL_IN := 0.12
const LADDER_RUNG_GAP_IN := 0.5
## Surface kinds in the order the board shader knows them (INSTANCE_CUSTOM.x, shaders/tiefwerk_board.gdshader).
const KINDS := ["ground", "street", "hazard", "tier1", "tier2", "ladder", "tier3"]
const SHADER := preload("res://shaders/tiefwerk_board.gdshader")

var layout_seed: int = 0
var _material: ShaderMaterial
var _footprint := Rect2()   # the board, in table-local metres


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


## The whole board in ONE MultiMesh (one draw call, one shared procedural material) plus a collider per solid box.
func build(layout: Dictionary) -> void:
	layout_seed = int(layout.get("seed", 0))
	var body := StaticBody3D.new()
	body.name = "Colliders"
	body.collision_layer = GROUND_COLLISION_LAYER
	body.collision_mask = 0
	add_child(body)
	var boxes := plan(layout)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = BoxMesh.new()   # the unit cube; every instance scales it
	mm.instance_count = boxes.size()
	for i in boxes.size():
		var b: Dictionary = boxes[i]
		var size: Vector3 = (b["hi"] - b["lo"]) * INCHES_TO_METERS
		var centre: Vector3 = (b["hi"] + b["lo"]) * 0.5 * INCHES_TO_METERS
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(size), centre))
		mm.set_instance_custom_data(i, Color(KINDS.find(b["kind"]), 0.0, 0.0, 0.0))
		if b["solid"]:
			var shape := BoxShape3D.new()
			shape.size = size
			var col := CollisionShape3D.new()
			col.shape = shape
			col.position = centre
			body.add_child(col)
	var props := BoardgenProps.new()
	props.name = "Props"
	props.build(layout)
	add_child(props)
	var landmarks := BoardgenLandmarks.new()
	landmarks.name = "Landmarks"
	landmarks.build(layout)
	add_child(landmarks)
	var debris := BoardgenDebris.new()
	debris.name = "Debris"
	debris.build(layout)
	add_child(debris)
	var board := Vector2(layout["nx"], layout["nz"]) * float(layout["cell_in"]) * INCHES_TO_METERS
	_footprint = Rect2(board * -0.5, board).grow(0.5 * INCHES_TO_METERS)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Surfaces"
	mmi.multimesh = mm
	_material = _make_material(layout)
	mmi.material_override = _material
	add_child(mmi)
	var rails := BoardgenRails.new()
	rails.name = "Rails"
	rails.build(layout)
	add_child(rails)
	_anchor()


func _ready() -> void:
	_anchor()
	_scatter_off(_footprint)


func _exit_tree() -> void:
	_scatter_off(Rect2())


## The table's own ground scatter (grass tufts, the biome dressing's straw, leaves and puddles) stays off under the board.
func _scatter_off(rect: Rect2) -> void:
	var table := get_parent()
	if table != null:
		table.set_meta("scatter_keepout", rect)
		if table.has_node("GrassField"):
			table.get_node("GrassField").set_keepout(rect)


## The shader reads board inches off the board centre, so it is told where that is in the world.
func _anchor() -> void:
	if _material != null and is_inside_tree():
		_material.set_shader_parameter("board_origin", global_position)


## The board shader with a one-texel-per-cell texture: red = height of the cell's top in inches, green = 255 for a sump.
func _make_material(layout: Dictionary) -> ShaderMaterial:
	var bytes := PackedByteArray()
	for c: Dictionary in layout["cells"]:
		bytes.append_array([int(layout["level_in"][c["level"]]), 255 if c["lot_kind"] == "Hazard" else 0])
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("cells", ImageTexture.create_from_image(Image.create_from_data(layout["nx"], layout["nz"], false, Image.FORMAT_RG8, bytes)))
	mat.set_shader_parameter("board_cells", Vector2(layout["nx"], layout["nz"]))
	mat.set_shader_parameter("cell_in", float(layout["cell_in"]))
	return mat
