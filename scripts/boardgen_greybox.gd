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
## The table's ground scatter (tufts, leaves, straw) is off on the board AND round it, whatever the table size: no biome dressing
## while a generated board is on the table (a board is the whole playing surface; the rest of the table is its frame).
const SCATTER_OFF_M := 3.0
const INCHES_TO_METERS := 0.0254
const GROUND_COLLISION_LAYER := 1
## Thickness of the level-0 ground skin that covers the biome texture, in inches.
const SKIN_IN := 0.04
const LADDER_WIDTH_IN := 1.0
const LADDER_OFFSET_IN := 0.12   # the ladder stands this far off the wall face
const LADDER_RAIL_IN := 0.12
const LADDER_RUNG_GAP_IN := 0.5
## The authored K1 ladder: a 3 in segment per 3 in of rise, the top one carries the grab rails and hoops above the deck (BoardgenKit).
const KIT_LADDERS: Array[String] = ["ladder_3in", "ladder_top"]
const LADDER_SEGMENT_IN := 3.0
const LADDER_TINT := Color(0.60, 0.43, 0.06)   # weathered safety yellow, like the board shader's ladder kind
## Surface kinds in the order the board shader knows them (INSTANCE_CUSTOM.x, shaders/tiefwerk_board.gdshader).
const KINDS := ["ground", "street", "hazard", "tier1", "tier2", "ladder", "tier3", "kerb"]
const SHADER := preload("res://shaders/tiefwerk_board.gdshader")

var layout_seed: int = 0
var _material: ShaderMaterial
var _kit: BoardgenKit
var _tiefwerk: TiefwerkLibrary = null   # the authored surfaces (R2, on demand); the board is procedural until they are cached
var _footprint := Rect2()   # the ground kept free of the table's scatter, in table-local metres: the board and all round it
var _layout: Dictionary = {}


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
	out.append_array(BoardgenSumps.kerbs(layout))   # the low rim round each toxic sump
	return out


## The kit ladders: {ladder_3in | ladder_top: [{xf, colour}]} (a key only when used), metres off the board centre. A ladder is rise / 3 in
## segments (the core's are all 3 in: one ladder_top each), the topmost one a ladder_top; its origin is on the wall face at the edge point, local +z points away from the wall (over the lower cell).
static func ladder_kit_plan(layout: Dictionary) -> Dictionary:
	var out := {}
	var origin := Vector2(layout["nx"], layout["nz"]) * float(layout["cell_in"]) * -0.5
	for c: Dictionary in layout["connectors"]:
		var base: float = layout["level_in"][layout["cells"][c["low"]]["level"]]
		var rise: float = layout["level_in"][layout["cells"][c["high"]]["level"]] - base
		var edge := Vector2(c["edge_in"][0], c["edge_in"][1]) + origin
		var away := Vector2(Vector2i(c["low_xz"][0], c["low_xz"][1]) - Vector2i(c["high_xz"][0], c["high_xz"][1]))
		var yaw := Basis(Vector3.UP, atan2(away.x, away.y))
		for k in int(rise / LADDER_SEGMENT_IN):
			var top_piece := k == int(rise / LADDER_SEGMENT_IN) - 1
			(out.get_or_add("ladder_top" if top_piece else "ladder_3in", []) as Array).append(
				{"xf": Transform3D(yaw, Vector3(edge.x, base + k * LADDER_SEGMENT_IN, edge.y) * INCHES_TO_METERS), "colour": LADDER_TINT})
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


## INSTANCE_CUSTOM of a box: x = its surface kind, gba = its size in inches (the shader's edge wear needs to know where the box ends).
static func custom_data(b: Dictionary) -> Color:
	var size: Vector3 = b["hi"] - b["lo"]
	return Color(KINDS.find(b["kind"]), size.x, size.y, size.z)


## The whole board in ONE MultiMesh (one draw call, one shared procedural material) plus a collider per solid box.
func build(layout: Dictionary) -> void:
	layout_seed = int(layout.get("seed", 0))
	var body := StaticBody3D.new()
	body.name = "Colliders"
	body.collision_layer = GROUND_COLLISION_LAYER
	body.collision_mask = 0
	add_child(body)
	var kit := BoardgenKit.new()
	kit.name = "Kit"
	add_child(kit)
	_kit = kit
	var ladders := ladder_kit_plan(layout)
	var kit_ladders: bool = not ladders.is_empty() and kit.usable(ladders.keys())
	var boxes := plan(layout).filter(func(b: Dictionary) -> bool: return not (kit_ladders and b["kind"] == "ladder"))
	if kit_ladders:   # the authored ladders replace the box ladders
		for module: String in ladders:
			BoardgenKit.add_multimesh(self, module, kit.mesh_or(module), ladders[module], false)
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
		mm.set_instance_custom_data(i, custom_data(b))
		if b["solid"]:
			var shape := BoxShape3D.new()
			shape.size = size
			var col := CollisionShape3D.new()
			col.shape = shape
			col.position = centre
			body.add_child(col)
	var props := BoardgenProps.new()
	props.name = "Props"
	props.build(layout, kit)
	add_child(props)
	var landmarks := BoardgenLandmarks.new()
	landmarks.name = "Landmarks"
	landmarks.build(layout)
	add_child(landmarks)
	var debris := BoardgenDebris.new()
	debris.name = "Debris"
	debris.build(layout)
	add_child(debris)
	var sumps := BoardgenSumps.new()
	sumps.name = "Sumps"
	sumps.build(layout)
	add_child(sumps)
	var board := Vector2(layout["nx"], layout["nz"]) * float(layout["cell_in"]) * INCHES_TO_METERS
	_footprint = Rect2(board * -0.5, board).grow(SCATTER_OFF_M)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Surfaces"
	mmi.multimesh = mm
	_material = _make_material(layout)
	mmi.material_override = _material
	add_child(mmi)
	var rails := BoardgenRails.new()
	rails.name = "Rails"
	rails.build(layout, kit)
	add_child(rails)
	add_child(BoardgenMood.make_fill_light())   # lights the models only (render layer), shown with the finer look
	_anchor()
	_layout = layout
	var settings := _settings()
	if settings != null:
		settings.board_mist_changed.connect(refresh_atmosphere)
	refresh_atmosphere()


## The GraphicsSettings autoload by path (a script compiled before the autoloads exist cannot name it).
static func _settings() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GraphicsSettings")


## The low ground mist and the vent steam (GraphicsSettings.board_mist_enabled): built while the setting is on, freed at once when it goes off.
func refresh_atmosphere() -> void:
	var settings := _settings()
	var want: bool = settings == null or settings.board_mist_enabled()
	for part: Array in [["Mist", BoardgenMist], ["Steam", BoardgenSteam]]:
		var node: Node = get_node_or_null(part[0])
		if want and node == null:
			node = part[1].new()
			node.name = part[0]
			node.call("build", _layout)
			add_child(node)
		elif not want and node != null:
			remove_child(node)
			node.free()


func _ready() -> void:
	_anchor()
	if _kit != null:   # a module missing now is cached for the next board
		_kit.prefetch(KIT_LADDERS + BoardgenRails.KIT_MODULES + BoardgenProps.KIT_MODULES)
	_scatter_off(_footprint)
	_assign_layers()
	child_entered_tree.connect(func(_child: Node) -> void: _assign_layers.call_deferred())   # whatever a builder adds later joins the board layer too
	var graphics := get_node_or_null("/root/GraphicsSettings")
	if graphics != null:
		graphics.settings_applied.connect(_on_settings_applied)
	_apply_detail()
	_attach_surfaces()


func _exit_tree() -> void:
	_scatter_off(Rect2())
	var graphics := get_node_or_null("/root/GraphicsSettings")
	if graphics != null and graphics.settings_applied.is_connected(_on_settings_applied):
		graphics.settings_applied.disconnect(_on_settings_applied)
	BoardgenMood.apply(self, false)


## The finer look of the surfaces (edge wear, later the relief of walls and floors) is on from Medium up; Performance / Low and the
## Compatibility renderer (web) keep the plain procedural look and its cost.
static func detail_for(preset: int, compatibility: bool) -> bool:
	return preset >= GraphicsSettings.QualityPreset.MEDIUM and not compatibility


func _on_settings_applied(_preset_name: String) -> void:
	_apply_detail()


func _apply_detail() -> void:
	var graphics := get_node_or_null("/root/GraphicsSettings")
	var on: bool = graphics != null and detail_for(int(graphics.current_preset), RenderingServer.get_current_rendering_method() == "gl_compatibility")
	if _material != null and graphics != null:
		_material.set_shader_parameter("detail", 1.0 if on else 0.0)
		if on:
			_attach_surfaces()   # a later switch up to Medium fetches them then
	BoardgenMood.apply(self, on)   # the dim industrial light, board-scale SSAO, the grade and the model fill come with the finer look


## The board's visuals sit on their own render layer: the models' fill light (BoardgenMood) never reaches them.
func _assign_layers() -> void:
	BoardgenMood.assign_layers(self)


## The four authored PBR sets under the procedural look (AAA step 10): wired as soon as they are cached, fetched in the background the
## first time (offline or refused: the board stays procedural). Not in a headless run, so no test or tool touches the network.
const T1_SETS: Array[String] = ["painted_steel", "rusted_plate", "concrete", "roof_slab"]
const T1_MAPS := {"alb": "albedo", "nrm": "normal", "orm": "orm"}


func _attach_surfaces() -> void:
	if _material == null or DisplayServer.get_name() == "headless" or _tiefwerk != null or float(_material.get_shader_parameter("detail")) < 0.5:
		return   # (Low, Performance and the Compatibility renderer never download them)
	_tiefwerk = TiefwerkLibrary.new()
	_tiefwerk.name = "Tiefwerk"
	add_child(_tiefwerk)
	if not _tiefwerk.sets_cached():
		await _tiefwerk.ensure_sets()
	wire_surfaces(_material, _tiefwerk)


## Hands the cached sets to the board shader and switches them on; false (and the shader stays procedural) while any texture is missing.
static func wire_surfaces(material: ShaderMaterial, lib: TiefwerkLibrary) -> bool:
	if material == null or not is_instance_valid(lib) or not lib.is_inside_tree():
		return false
	var found := {}
	for i in T1_SETS.size():
		for short: String in T1_MAPS:
			var tex := lib.set_texture(T1_SETS[i], T1_MAPS[short])
			if tex == null:
				return false
			found["t1_%s_%d" % [short, i]] = tex
	for uniform: String in found:
		material.set_shader_parameter(uniform, found[uniform])
	material.set_shader_parameter("t1_on", 1.0)
	return true


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


## The board shader with a one-texel-per-cell texture: red = height of the cell's top in inches, green = 255 for a sump, blue = the lot id
## (mod 256: a roof has one look per lot), alpha = 255 for the floor cell at the foot of a ladder.
func _make_material(layout: Dictionary) -> ShaderMaterial:
	var bytes := PackedByteArray()
	var feet := {}   # the floor cell at the foot of a ladder: the board shader puts no door on the wall there
	for conn: Dictionary in layout["connectors"]:
		feet[int(conn["low_xz"][1]) * int(layout["nx"]) + int(conn["low_xz"][0])] = true
	for i in layout["cells"].size():
		var c: Dictionary = layout["cells"][i]
		bytes.append_array([int(layout["level_in"][c["level"]]), 255 if c["lot_kind"] == "Hazard" else 0, int(c["lot_id"]) % 256, 255 if feet.has(i) else 0])
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("cells", ImageTexture.create_from_image(Image.create_from_data(layout["nx"], layout["nz"], false, Image.FORMAT_RGBA8, bytes)))
	mat.set_shader_parameter("board_cells", Vector2(layout["nx"], layout["nz"]))
	mat.set_shader_parameter("cell_in", float(layout["cell_in"]))
	return mat
