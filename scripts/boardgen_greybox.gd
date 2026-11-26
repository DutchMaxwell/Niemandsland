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
## NML_BOARDGEN_THEME=ruintown picks the ruined-town board for the seed above; unset = the original board.
const ENV_THEME := "NML_BOARDGEN_THEME"
## setup_table (load, resize) frees the table's other children; this group keeps the board.
const TABLE_OVERLAY_GROUP := "table_overlay"
## The table's landscape is not dressed round a board in this group (TableBiomePresenter.HIDES_LANDSCAPE_GROUP; spelled out here: a
## board script that names the presenter no longer compiles before the autoloads exist, as in a tool run with -s).
const HIDES_LANDSCAPE_GROUP := "hides_table_landscape"
## No world (hills, groves, world sky; High and Ultra) round a board in this group (TableBiomePresenter.HIDES_WORLD_GROUP): the town's table
## stays dressed, only the land beyond it goes (look plan R19).
const HIDES_WORLD_GROUP := "hides_table_world"
## The table's ground scatter (tufts, leaves, straw) is off on the board AND round it, whatever the table size: no biome dressing
## while a generated board is on the table (a board is the whole playing surface; the rest of the table is its frame).
const SCATTER_OFF_M := 3.0
## The start view over a generated board, as a share of the table diagonal (the table alone: 0.95; decision D-TEX3).
const VIEW_FACTOR := 0.70
## The table's ground relief (mounds, 7 mm ridges along terrain walls) is lifted flat under the board plus this margin (two cells of the relief mesh): the board's skin is 1 mm thick.
const RELIEF_MARGIN_M := 0.03
const INCHES_TO_METERS := 0.0254
const GROUND_COLLISION_LAYER := 1
## Thickness of the level-0 ground skin that covers the biome texture, in inches.
const SKIN_IN := 0.04
## The town greybox draws a landmark as one plain box: the core's solid is the 2.5 in container whatever the piece is, a pool is a film
## over the ground skin, a hall mark a rim line on its block.
const SOLID_IN := 2.5
const POOL_IN := 0.07   # a hair above the 0.04 in ground skin
const RIM_IN := 0.3
## The kit-off fountain (texture plan step 15; the kit's fountain_basin is 5.6 in across its flats): the wall's centre line FOUNTAIN_APOTHEM_IN
## off the centre, 0.3 in thick, 0.6 in high, the water 0.4 in up.
const FOUNTAIN_APOTHEM_IN := 2.4
const FOUNTAIN_WALL_IN := 0.3
const FOUNTAIN_RIM_IN := 0.6
const FOUNTAIN_WATER_IN := 0.4
const LADDER_WIDTH_IN := 1.0
const LADDER_OFFSET_IN := 0.12   # the ladder stands this far off the wall face
const LADDER_RAIL_IN := 0.12
const LADDER_RUNG_GAP_IN := 0.5
## The authored K1 ladder: a 3 in segment per 3 in of rise, the top one carries the grab rails and hoops above the deck (BoardgenKit).
const KIT_LADDERS: Array[String] = ["ladder_3in", "ladder_top"]
const LADDER_SEGMENT_IN := 3.0
const LADDER_TINT := Color(0.60, 0.43, 0.06)   # weathered safety yellow, like the board shader's ladder kind
## Surface kinds in the order the Deepworks board shader knows them (INSTANCE_CUSTOM.x, shaders/tiefwerk_board.gdshader); a theme names its own list (BoardgenTheme).
const KINDS := ["ground", "street", "hazard", "tier1", "tier2", "ladder", "tier3", "kerb"]
## The dressing builders a theme may switch on (BoardgenTheme `dressing`); each is a `build(layout)` Node3D (Props and Rails also take the kit).
const DRESSING := {"Props": preload("res://scripts/boardgen_props.gd"), "Landmarks": preload("res://scripts/boardgen_landmarks.gd"),
		"Debris": preload("res://scripts/boardgen_debris.gd"), "Sumps": preload("res://scripts/boardgen_sumps.gd"), "Rails": preload("res://scripts/boardgen_rails.gd")}

var layout_seed: int = 0
var layout_theme := "Deepworks"   # the layout's own `theme` key; a Deepworks layout has none
var _material: ShaderMaterial
var _kit: BoardgenKit
var _tiefwerk: TiefwerkLibrary = null   # the authored surfaces (R2, on demand); the board is procedural until they are cached
var _decals: BoardgenDecals = null
var _life: BoardgenTownLife = null
var _soil_ok := false   # (LOOK5 S2) the four soil arrays are on the material
var _surfaces: MultiMeshInstance3D   # the board's own surfaces: what the bases' ground bake draws (BoardgenGroundBake)
var _ground_rect := Rect2()   # the board itself in board-local metres (x, z)
var _bake_queued := false
var _footprint := Rect2()   # the ground kept free of the table's scatter, in table-local metres: the board and all round it
var _layout: Dictionary = {}
var _atmosphere: Object = null   # the town re-applies its dusk after every mood change while it is on the table


## The board of NML_BOARDGEN_SEED on `table`, or null when the flag is off (release build, unset or not an integer).
static func attach_from_env(table: Node) -> BoardgenGreybox:
	var raw := OS.get_environment(ENV_SEED).strip_edges()
	if not OS.is_debug_build() or not raw.is_valid_int() or not ClassDB.class_exists("NmlCore"):
		return null
	var core: Object = ClassDB.instantiate("NmlCore")
	if not core.has_method("boardgen_layout"):
		push_error("BoardgenGreybox: this NmlCore has no boardgen_layout")
		return null
	var theme := theme_from_env()
	if theme.is_empty():
		return attach(table, core.boardgen_layout(int(raw)))
	if not core.has_method("boardgen_layout_themed"):
		push_error("BoardgenGreybox: this NmlCore has no boardgen_layout_themed")
		return null
	return attach(table, core.boardgen_layout_themed(int(raw), theme))


## The theme id the dev flag asks for, trimmed and lower-cased; "" = not set (the original board).
static func theme_from_env() -> String:
	return OS.get_environment(ENV_THEME).strip_edges().to_lower()


static func attach(table: Node, layout: Dictionary, dress: BoardgenDress = null) -> BoardgenGreybox:
	var node := BoardgenGreybox.new()
	node.name = "BoardgenGreybox"
	node.add_to_group(TABLE_OVERLAY_GROUP)
	node.build(layout, dress)
	if node.layout_theme == BoardgenTheme.DEEPWORKS:   # an undercity: no meadow round it (the town keeps the landscape as distant land)
		node.add_to_group(HIDES_LANDSCAPE_GROUP)
	if node.layout_theme == BoardgenTheme.RUIN_TOWN:   # the gaming table round the town instead of the void (texture plan step 8)
		node.add_to_group(HIDES_WORLD_GROUP)   # the table round the town, no land beyond it
		var feet: Variant = table.get("table_size")
		var surround := BoardgenSurround.make(layout, feet if feet is Vector2 else Vector2(layout["nx"], layout["nz"]) * float(layout["cell_in"]) / 12.0)
		node.add_child(surround)
		if table.has_signal("table_resized"):
			table.connect("table_resized", surround.fit_table)
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
	var town := str(layout.get("theme", BoardgenTheme.DEEPWORKS)) == BoardgenTheme.RUIN_TOWN
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var own := BoardgenTownSilhouette.drawn_cells(layout) if town else {}   # wall and tower cells the silhouette draws thinner: one collider box each, drawn by it
	# Blocks: runs of same-kind cells along x. Level 0 is a thin skin coloured by what the cell is.
	for z in nz:
		var x := 0
		while x < nx:
			var kind := _cell_kind(cells[z * nx + x], town)
			var run := 1
			while not own.has(z * nx + x) and x + run < nx and not own.has(z * nx + x + run) and _cell_kind(cells[z * nx + x + run], town) == kind:
				run += 1
			var level: int = cells[z * nx + x]["level"]
			var body := kind == "roofed"   # an intact house: level-0 solid ground, as high as the core's solid (2.5 in); its ridge is drawn below
			var tall: bool = cells[z * nx + x]["lot_kind"] == "Tower" and level == 0
			var box := {"lo": Vector3(origin.x + x * cell_in, 0.0, origin.y + z * cell_in),
				"hi": Vector3(origin.x + (x + run) * cell_in, float(level_in[level]) if level > 0 else (float(layout.get("tower_in", 12.0)) if tall else (SOLID_IN if body else SKIN_IN)), origin.y + (z + 1) * cell_in),
				"kind": kind, "solid": level > 0 or body or tall}
			if own.has(z * nx + x):
				box["hidden"] = true
			out.append(box)
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
	if town:
		out.append_array(_town_landmarks(layout, origin))
		out.append_array(BoardgenTownDressing.chimneys(layout))
		out.append_array(BoardgenTownDressing.merlons(layout))
		out.append_array(BoardgenTownDressing.lantern_boxes(layout))
		out.append_array(BoardgenTownDressing.props(layout))
		out.append_array(BoardgenTownDressing.lean_tos(layout))
		out.append_array(BoardgenTownDressing.party_stubs(layout))
		out.append_array(BoardgenTownDressing.breach_rubble(layout))
	else:
		out.append_array(BoardgenSumps.kerbs(layout))   # the low rim round each toxic sump (the town draws its pools as flat boxes)
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


## The town's landmarks as plain boxes (greybox), each inside its footprint: fountain (TankCluster) and statue plinth (Crane) are the solid
## 2.5 in piece, a Sump (pool, well yard) a flat film, a PumpHouse (hall) a rim line on top of its block. `landmark` = its index in the layout.
static func _town_landmarks(layout: Dictionary, origin: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cell_in := float(layout["cell_in"])
	var nx: int = layout["nx"]
	var i := 0
	for lm: Dictionary in layout["landmarks"]:
		var lo := origin + Vector2(lm["x"], lm["z"]) * cell_in
		var hi := lo + Vector2(lm["w"], lm["h"]) * cell_in
		var boxes: Array[Dictionary] = []
		match lm["kind"]:
			"TankCluster":   # the core's solid stays the whole footprint (a collider only); drawn: an octagonal basin, water, a column
				var solid := _box(lo, hi, 0.0, SOLID_IN, "stone", true)
				solid["collider_only"] = true
				boxes.append_array([solid] + _fountain((lo + hi) * 0.5))
			"Crane":
				boxes.append(_box(lo, hi, 0.0, SOLID_IN, "stone", true))
			"Sump":
				boxes.append(_box(lo, hi, 0.0, POOL_IN, "hazard", false))
			"PumpHouse":
				var top := 0.0
				for dz in int(lm["h"]):
					for dx in int(lm["w"]):
						top = maxf(top, float(layout["level_in"][layout["cells"][(int(lm["z"]) + dz) * nx + int(lm["x"]) + dx]["level"]]))
				boxes.append_array([_box(lo, Vector2(hi.x, lo.y + RIM_IN), top, top + RIM_IN, "rim", false),
					_box(Vector2(lo.x, hi.y - RIM_IN), hi, top, top + RIM_IN, "rim", false),
					_box(lo + Vector2(0.0, RIM_IN), Vector2(lo.x + RIM_IN, hi.y - RIM_IN), top, top + RIM_IN, "rim", false),
					_box(Vector2(hi.x - RIM_IN, lo.y + RIM_IN), hi - Vector2(0.0, RIM_IN), top, top + RIM_IN, "rim", false)])
		for b in boxes:
			b["landmark"] = i
			b["lm"] = lm["kind"]
		out.append_array(boxes)
		i += 1
	return out


## The fountain round `c` (kit off): eight wall segments on an octagon FOUNTAIN_APOTHEM_IN out (axis-aligned boxes yawed about their centre),
## and a column; the water is BoardgenTownWater's octagon. Nothing here is solid: the collider is the footprint box.
static func _fountain(c: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var a := FOUNTAIN_APOTHEM_IN
	var t := FOUNTAIN_WALL_IN
	var side := 2.0 * (a + t * 0.5) * tan(PI / 8.0)   # the outer corners meet
	for i in 8:
		var yaw := i * PI / 4.0
		var m := c + Vector2(sin(yaw), cos(yaw)) * a
		out.append(_yawed(m, Vector2(side, t) * 0.5, i, FOUNTAIN_RIM_IN, "wall"))
	out.append(_box(c - Vector2.ONE * 0.2, c + Vector2.ONE * 0.2, 0.0, 1.3, "stone", false))
	return out


## A non-solid box of half size `half` (x along the turn's tangent) turned by `eighth` eighth-turns: a quarter turn swaps x and z, so lo / hi
## stay the true extent of an unturned box and only an odd eighth carries a 45 degree `yaw`.
static func _yawed(c: Vector2, half: Vector2, eighth: int, y1: float, kind: String) -> Dictionary:
	var h := half if (eighth / 2) % 2 == 0 else Vector2(half.y, half.x)
	var b := _box(c - h, c + h, 0.0, y1, kind, false)
	b["yaw"] = (eighth % 2) * PI / 4.0
	return b


static func _box(lo: Vector2, hi: Vector2, y0: float, y1: float, kind: String, solid: bool) -> Dictionary:
	return {"lo": Vector3(lo.x, y0, lo.y), "hi": Vector3(hi.x, y1, hi.y), "kind": kind, "solid": solid}


static func _cell_kind(cell: Dictionary, town := false) -> String:
	if town and cell["lot_kind"] == "Roofed":
		return "roofed"   # an intact house
	if town and cell["lot_kind"] == "Tower":
		return "tier3"   # a tall scenery tower (towers plan L1): drawn by BoardgenTownSilhouette, its box keeps a `tower_in` collider
	if town and cell["lot_kind"] == "Wall":
		return "wall" if cell["level"] > 0 else "rubble"   # the city wall (ridge, tower, buttress) or the rubble of its breach
	if cell["level"] > 0:
		return "tier%d" % cell["level"]
	if cell["lot_kind"] == "Hazard":
		return "hazard"
	if town and cell["lot_kind"] == "Rough":
		return "rough"   # a garden plot
	if town and cell["lot_kind"] == "Terrace" and not cell["street"]:
		return "yard"   # the level-0 rest of a half-collapsed house: ruin ground
	return "street" if cell["street"] else "ground"


## A box `from..to` inches off `edge` along `away`, `width` wide along `side`, between heights `y0` and `y1`.
static func _slab(edge: Vector2, away: Vector2, side: Vector2, from: float, to: float, width: float, y0: float, y1: float,
		kind: String, solid: bool) -> Dictionary:
	var p := edge + away * (from + to) * 0.5
	var half := (away.abs() * (to - from) + side.abs() * width) * 0.5
	return {"lo": Vector3(p.x - half.x, y0, p.y - half.y), "hi": Vector3(p.x + half.x, y1, p.y + half.y), "kind": kind, "solid": solid}


## INSTANCE_CUSTOM of a box: x = its surface kind, gba = its size in inches (the shader's edge wear needs to know where the box ends).
static func custom_data(b: Dictionary, kinds: Array = KINDS) -> Color:
	var size: Vector3 = b["hi"] - b["lo"]
	return Color(kinds.find(b["kind"]), size.x, size.y, size.z)


## Does a plan box draw itself? An intact house does not (BoardgenTownDressing draws its inset, yawed body), nor a wall or tower cell (BoardgenTownSilhouette draws it thinner), nor a box of a class the dressing
## draws (`skip`, BoardgenDress.classes()): the box only keeps the collider.
static func draws_itself(b: Dictionary, skip := {}) -> bool:
	return b["kind"] != "roofed" and not b.get("hidden", false) and not b.get("collider_only", false) and not skip.has(BoardgenDress.box_class(b))


## The whole board in ONE MultiMesh (one draw call, one shared procedural material) plus a collider per solid box.
func build(layout: Dictionary, dress: BoardgenDress = null) -> void:
	layout_seed = int(layout.get("seed", 0))
	layout_theme = str(layout.get("theme", "Deepworks"))
	_layout = layout
	var body := StaticBody3D.new()
	body.name = "Colliders"
	body.collision_layer = GROUND_COLLISION_LAYER
	body.collision_mask = 0
	add_child(body)
	var theme := BoardgenTheme.of(layout)
	var kit := BoardgenKit.new()
	kit.name = "Kit"
	add_child(kit)
	_kit = kit
	var ladders := ladder_kit_plan(layout)
	var kit_ladders: bool = theme["id"] == BoardgenTheme.DEEPWORKS and not ladders.is_empty() and kit.usable(ladders.keys())   # the town keeps its timber box ladders
	var town_kit: BoardgenTownKit = BoardgenTownKit.new() if theme["id"] == BoardgenTheme.RUIN_TOWN else null
	var kit_town := town_kit != null and town_kit.active()   # the authored roofs, chimneys and merlons (else the boxes below)
	if dress == null and theme["id"] == BoardgenTheme.RUIN_TOWN:
		dress = BoardgenDress.new()   # the dressing: the classes it draws as modules skip the old look
	var skip := dress.classes() if dress != null and dress.setup(layout) else {}
	var boxes := plan(layout).filter(func(b: Dictionary) -> bool: return not (kit_ladders and b["kind"] == "ladder") and not (kit_town and (BoardgenTownKit.replaces(b) or town_kit.replaces_clutter(b))))
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
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, b.get("yaw", 0.0)) * Basis.from_scale(size if draws_itself(b, skip) and not (kit_town and town_kit.draws_landmark(b)) else Vector3.ZERO), centre))   # (a solid box the kit draws keeps its collider)
		mm.set_instance_custom_data(i, custom_data(b, theme["kinds"]))
		if b["solid"]:
			var shape := BoxShape3D.new()
			shape.size = size
			var col := CollisionShape3D.new()
			col.shape = shape
			col.position = centre
			body.add_child(col)
	_dress(layout, theme, ["Props", "Landmarks", "Debris", "Sumps"], kit)
	var board := Vector2(layout["nx"], layout["nz"]) * float(layout["cell_in"]) * INCHES_TO_METERS
	_ground_rect = Rect2(board * -0.5, board)
	_footprint = _ground_rect.grow(SCATTER_OFF_M)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Surfaces"
	mmi.layers |= BoardgenDecals.RENDER_LAYER   # the only mesh the board's decals project onto
	mmi.multimesh = mm
	_surfaces = mmi
	_material = _make_material(layout, theme)
	mmi.material_override = _material
	add_child(mmi)
	_dress(layout, theme, ["Rails"], kit)
	if theme["id"] == BoardgenTheme.RUIN_TOWN:
		var town := BoardgenTownDressing.new()   # the gable roofs of the intact houses
		town.name = "TownDressing"
		var frames: bool = kit_town and town_kit.kit.usable(BoardgenTownFrames.MODULES)   # (train 3) the half-timber shells as geometry: the paint keeps the infill only
		if skip.has("props"):
			town.lamp_glass = dress.lamp_glass(layout)   # the lantern lights follow the dressed lamps
		town.build(layout, _material, not kit_town and not skip.has("houses"), BoardgenTownFrames.timber_lots(layout) if frames else {}, skip)
		_material.set_shader_parameter("real_frames", frames)
		add_child(town)
		if skip.is_empty():
			dress.free()
		else:
			dress.name = "Dress"
			dress.build(layout)
			add_child(dress)
		var water := BoardgenTownWater.build(layout, skip.has("props"))   # the fountain's water (look plan R18)
		if water != null:
			add_child(water)
		if kit_town:
			town_kit.name = "TownKit"
			town_kit.build(layout)
			add_child(town_kit)
		else:
			town_kit.free()
		var town_lib := get_node_or_null("TownLibrary") as TiefwerkLibrary   # the town's decals when the T-R2 atlas is cached
		if town_lib != null and town_lib.decals_cached():
			_decals = BoardgenDecals.new()
			_decals.name = "Decals"
			_decals.build(layout, town_lib)
			add_child(_decals)
		_life = BoardgenTownLife.new()   # flicker, smoke, crows, rats
		_life.name = "Life"
		add_child(_life)
		_life.build(layout, self)
	if theme["id"] == BoardgenTheme.DEEPWORKS:
		add_child(BoardgenMood.make_fill_light())   # lights the models only (render layer), shown with the finer look
	elif theme["id"] == BoardgenTheme.RUIN_TOWN:   # (look review 3) under the one side moon the models get a soft fill from straight above (model layer only): both player sides alike
		var fill := BoardgenMood.make_fill_light()
		fill.light_energy = BoardgenTownDressing.MODEL_FILL_ENERGY
		fill.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		add_child(fill)
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
	var air: Array = BoardgenTheme.of(_layout)["atmosphere"]
	for part: Array in [["Mist", BoardgenMist], ["Steam", BoardgenSteam], ["GroundFog", BoardgenGroundFog]]:
		var node: Node = get_node_or_null(part[0])
		if not air.has(part[0]):
			continue   # the theme has no such air (the town)
		if want and node == null:
			node = part[1].new()
			node.name = part[0]
			node.call("build", _layout)
			if node is BoardgenGroundFog:   # the town's lanterns glow in its fog
				node.call("set_lamps", _lantern_points())
			add_child(node)
		elif not want and node != null:
			remove_child(node)
			node.free()


## The board's shown town lanterns (`Lantern*` lights) in the board's own space: the pools of the ground fog.
func _lantern_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for light: Node in find_children("Lantern*", "SpotLight3D", true, false):
		var t := Transform3D()
		var n: Node = light
		while n != self and n is Node3D:
			t = (n as Node3D).transform * t
			n = n.get_parent()
		if (light as Node3D).visible:
			out.append(t.origin)
	return out


## The dressing builders of `names` that the theme switches on (the ruin town draws none of the Deepworks ones: no pipe, lamp or tank).
func _dress(layout: Dictionary, theme: Dictionary, names: Array, kit: BoardgenKit) -> void:
	for dressing: String in names:
		if theme["dressing"].has(dressing):
			var node: Node3D = DRESSING[dressing].new()
			node.name = dressing
			if dressing == "Props" or dressing == "Rails":
				node.build(layout, kit)
			else:
				node.build(layout)
			add_child(node)


func _ready() -> void:
	_anchor()
	if layout_theme == BoardgenTheme.RUIN_TOWN and is_inside_tree():   # the town is lit at dusk (a dev view: not restored)
		var scene := get_tree().current_scene
		var lighting: Variant = scene.get("lighting_controller") if scene != null else null
		BoardgenTownDressing.dusk(lighting)
		# the table's biome presenter restores the table mood one frame after a board arrives (atmosphere + table mood): that overwrote the dusk of the FIRST town board
		# (sun 0.8, exposure 1.0 - the "too dark" board, 21.11.). Every mood change is followed by the dusk again, at the end of that frame.
		var atmosphere: Variant = scene.get("atmosphere_controller") if scene != null else null
		if atmosphere != null and atmosphere.has_signal("atmosphere_changed"):
			atmosphere.atmosphere_changed.connect(func(_name: String) -> void: _dusk_again.call_deferred(lighting))
			_atmosphere = atmosphere
	if _kit != null and layout_theme == BoardgenTheme.DEEPWORKS:   # a module missing now is cached for the next board (the town uses no kit)
		_kit.prefetch(KIT_LADDERS + BoardgenRails.KIT_MODULES + BoardgenProps.KIT_MODULES)
	if layout_theme == BoardgenTheme.RUIN_TOWN:
		_fetch_town_kit()
	_scatter_off(_footprint)
	_assign_layers()
	visibility_changed.connect(_queue_ground_bake)
	child_entered_tree.connect(func(_child: Node) -> void: _assign_layers.call_deferred())   # whatever a builder adds later joins the board layer too
	var graphics := get_node_or_null("/root/GraphicsSettings")
	if graphics != null:
		graphics.settings_applied.connect(_on_settings_applied)
	_apply_detail()
	_attach_surfaces()
	_frame_view(true)


## A generated board is the whole battlefield: the start view comes closer, 0.70 x the table diagonal instead of 0.95 (texture plan step 10, decision D-TEX3), and is
## centred on the board, when it arrives and after every reset of the view while it stays (the camera keeps factor and tilt); the table's own view comes back when it leaves.
func _frame_view(on: bool) -> void:
	var table := get_parent()
	var main := table.get_parent() if table != null else null   # (the scene, as BoardgenMood finds it)
	var pivot: Variant = main.get("camera_pivot") if main != null else null
	if not (pivot is Node3D) or not ("table_view_factor" in pivot):
		return
	pivot.table_view_factor = VIEW_FACTOR if on else pivot.TABLE_VIEW_FACTOR
	pivot.table_view_tilt = 0.0
	var feet: Variant = table.get("table_size")
	var cam := (pivot as Node3D).get_node_or_null("Camera3D") as Camera3D
	if on and feet is Vector2 and cam != null:   # centred: the start view tilts down until the near rim and the tallest piece sit evenly in the picture
		pivot.reset_view()
		pivot.adjust_for_table_size(feet)
		pivot.table_view_tilt = view_tilt(_layout, feet, pivot.get_zoom(), -float(pivot._pitch), cam.fov)
		pivot.reset_view()
		pivot.adjust_for_table_size(feet)


## Degrees to tilt a start view (pitch `pitch_deg` below the horizon, `dist` m from the board centre, vertical `fov`) down about the camera, so the near
## rim's foot and the highest projected top (boxes, roofs, the far rim) sit equally far from the picture's edges. A pinhole model at yaw 0; the board is
## a half-turn mirror, so it holds from the other side too. Pure.
static func view_tilt(layout: Dictionary, table_feet: Vector2, dist: float, pitch_deg: float, fov: float) -> float:
	var rim := table_feet.y * 0.1524 + 0.015   # metres off the centre to the rim's outer face (scripts/table.gd)
	var tops: Array[Vector2] = [Vector2(0.05, -rim)]   # (height, z) in metres, +z toward the camera: the far rim's top edge, then every far top edge
	for b: Dictionary in plan(layout):
		tops.append(Vector2(b["hi"].y, b["lo"].z) * INCHES_TO_METERS)
	for r: Dictionary in (BoardgenTownDressing.roofs(layout) if str(layout.get("theme", "")) == BoardgenTheme.RUIN_TOWN else []):
		tops.append(Vector2(float(r["eaves"]) + float(r["height"]), r["centre"].y - (0.0 if r["along_x"] else float(r["length"]) * 0.5)) * INCHES_TO_METERS)
	var eye := Vector2(sin(deg_to_rad(pitch_deg)), cos(deg_to_rad(pitch_deg))) * dist
	var lo := -10.0
	var hi := 30.0
	for _i in 24:   # the picture moves up as the tilt grows: bisect to equal margins
		var a := deg_to_rad(pitch_deg + (lo + hi) * 0.5)
		var ndc := func(p: Vector2) -> float: return ((p.x - eye.x) * cos(a) - (p.y - eye.y) * sin(a)) / ((-(p.x - eye.x) * sin(a) - (p.y - eye.y) * cos(a)) * tan(deg_to_rad(fov * 0.5)))
		var top := -9.0
		for p in tops:
			top = maxf(top, ndc.call(p))
		if top + ndc.call(Vector2(0.0, rim)) < 0.0:
			lo = (lo + hi) * 0.5
		else:
			hi = (lo + hi) * 0.5
	return (lo + hi) * 0.5


func _dusk_again(lighting: Object) -> void:
	if is_inside_tree() and is_instance_valid(lighting):
		BoardgenTownDressing.dusk(lighting)


func _exit_tree() -> void:
	_scatter_off(Rect2())
	var table := get_parent()
	if table != null and table.has_method("set_board_ground"):
		table.set_board_ground(null, Rect2())   # the bases show the biome again
	_frame_view(false)
	if _atmosphere != null and is_instance_valid(_atmosphere):
		for c: Dictionary in _atmosphere.atmosphere_changed.get_connections():
			if (c["callable"] as Callable).get_object() == self:
				_atmosphere.atmosphere_changed.disconnect(c["callable"])
	_atmosphere = null
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
		_material.set_shader_parameter("soil_on", 1.0 if on and _soil_ok else 0.0)   # (LOOK5 S2) Medium and up, not Compatibility, all four soil sets cached
		_material.set_shader_parameter("soil_tier", clampf(float(int(graphics.current_preset)) - 1.0, 1.0, 3.0))   # (LOOK5 S6) 1 Medium, 2 High, 3 Ultra
		BoardgenTownWater.apply_preset(get_node_or_null("TownWater"), int(graphics.current_preset))
		if _decals != null:
			_decals.visible = on   # no decals on Low, Performance and in the Compatibility renderer
		if _life != null:
			_life.apply_settings()
		if on:
			_attach_surfaces()   # a later switch up to Medium fetches them then
	_queue_ground_bake()   # the detail changes the board's look: the bases follow
	BoardgenMood.apply(self, on and (layout_theme == BoardgenTheme.DEEPWORKS or layout_theme == BoardgenTheme.RUIN_TOWN), layout_theme == BoardgenTheme.RUIN_TOWN)   # the dim industrial light, board-scale SSAO, the grade and the model fill come with the finer look; the ruin town has its own dusk and only the grade


## The ruin town's kit modules and texture sets (assets/ruintown_manifest.json, R2): fetched in the background, so the NEXT town board
## is dressed (offline or refused: the procedural look stays). Like _attach_surfaces: never headless, never below Medium or on Compatibility;
## with NML_RUINTOWN_KIT_DIR / _LIB_DIR set everything is already local and nothing is fetched.
func _fetch_town_kit() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var kit := BoardgenKit.new(BoardgenTheme.TOWN_LIBRARY)
	kit.name = "TownKitFetch"
	add_child(kit)
	if not kit.usable([]):   # (no names: only the preset / renderer question)
		return
	kit.prefetch(kit.module_names())
	var lib := get_node_or_null("TownLibrary") as TiefwerkLibrary
	if lib != null and not lib.sets_cached():
		lib.ensure_sets()


## The board's visuals sit on their own render layer: the models' fill light (BoardgenMood) never reaches them.
func _assign_layers() -> void:
	BoardgenMood.assign_layers(self)


## The four authored PBR sets under the procedural look (AAA step 10): wired as soon as they are cached, fetched in the background the
## first time (offline or refused: the board stays procedural). Not in a headless run, so no test or tool touches the network.
const T1_SETS: Array[String] = ["painted_steel", "rusted_plate", "concrete", "roof_slab"]
const T1_MAPS := {"alb": "albedo", "nrm": "normal", "orm": "orm"}


func _attach_surfaces() -> void:
	if _material == null or layout_theme != BoardgenTheme.DEEPWORKS or DisplayServer.get_name() == "headless" or _tiefwerk != null or float(_material.get_shader_parameter("detail")) < 0.5:
		return   # (Low, Performance and the Compatibility renderer never download them)
	_tiefwerk = TiefwerkLibrary.new()
	_tiefwerk.name = "Tiefwerk"
	add_child(_tiefwerk)
	if not _tiefwerk.sets_cached():
		await _tiefwerk.ensure_sets()
	if wire_surfaces(_material, _tiefwerk):
		_queue_ground_bake()
	if not _tiefwerk.decals_cached():
		await _tiefwerk.ensure_decals()
	if is_inside_tree() and _decals == null and _tiefwerk.decals_cached():
		_decals = BoardgenDecals.new()
		_decals.name = "Decals"
		_decals.build(_layout, _tiefwerk)
		add_child(_decals)
		_apply_detail()


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


## The bases' ground: the board's surfaces baked from above, handed to the table's shared base-top material. Once per
## frame at most; a later look change (detail, the Tiefwerk sets) bakes again.
func _queue_ground_bake() -> void:
	if not _bake_queued and _surfaces != null:
		_bake_queued = true
		_bake_ground.call_deferred()


func _bake_ground() -> void:
	_bake_queued = false
	var table := get_parent()
	if table == null or not table.has_method("set_board_ground") or not is_inside_tree():
		return
	if not is_visible_in_tree():   # a hidden board (a capture's bare-table baseline) leaves the bases on the biome
		table.set_board_ground(null, Rect2())
		return
	var rect := Rect2(_ground_rect.position + Vector2(global_position.x, global_position.z), _ground_rect.size)
	var tex: ImageTexture = await BoardgenGroundBake.bake(self, _surfaces, rect)
	if tex != null and is_inside_tree() and is_visible_in_tree():
		table.set_board_ground(tex, rect)


## The table's own ground scatter (grass tufts, the biome dressing's straw, leaves and puddles) stays off under the board, and so does its ground relief.
func _scatter_off(rect: Rect2) -> void:
	var table := get_parent()
	if table != null:
		table.set_meta("scatter_keepout", rect)
		if table.has_method("set_flat_rect"):
			table.set_flat_rect(rect.grow(RELIEF_MARGIN_M - SCATTER_OFF_M))   # the board itself (an empty rect shrinks to none)
		if table.has_node("GrassField"):
			table.get_node("GrassField").set_keepout(rect)


## The shader reads board inches off the board centre, so it is told where that is in the world.
func _anchor() -> void:
	if _material != null and is_inside_tree():
		_material.set_shader_parameter("board_origin", global_position)


## The authored surface sets of the town as shader parameters (plan R9 hook, T-R1): for coursed stone, plaster, timber and earth the albedo and normal textures when BOTH are cached, and `t_on`
## (x stone, y plaster, z timber, w earth) = 1 for each set that is complete. A missing set stays 0 and the shader keeps its procedural surface. Pure but for the library's cache.
## The yards' soil (LOOK5 S2): the four BoardgenTheme.TOWN_SOIL sets as three Texture2DArray (albedo, normal, ORH) with their tile and means, or {} unless
## every map of every set is cached and the arrays build (then the shader's soil_on stays 0: today's ground).
static func town_soil(lib: TiefwerkLibrary) -> Dictionary:
	var layers := {"albedo": [], "normal": [], "orm": []}
	for set_name: String in BoardgenTheme.TOWN_SOIL:
		for map: String in layers:
			var t := lib.set_texture(set_name, map)
			var img := t.get_image() if t != null else null
			if img == null:
				return {}
			(layers[map] as Array).append(img)
	var out := {"soil_tile": lib.tile_in(BoardgenTheme.TOWN_SOIL[0]), "soil_mean": PackedVector3Array(BoardgenTheme.TOWN_SOIL_MEANS)}
	for map: String in layers:
		var arr := Texture2DArray.new()
		if arr.create_from_images(Array(layers[map], TYPE_OBJECT, "Image", null)) != OK:
			return {}
		out[{"albedo": "soil_alb", "normal": "soil_nrm", "orm": "soil_orh"}[map]] = arr
	return out


static func town_sets(lib: TiefwerkLibrary) -> Dictionary:
	var out := {"t_on": Vector4.ZERO}
	var on := [0.0, 0.0, 0.0, 0.0]
	var tile := [1.3, 3.0, 3.0, 3.0]
	for i in 4:   # the four sets the shader samples today (t_on); the rest of TOWN_SETS waits for the shader's set arrays
		var names: Array = BoardgenTheme.TOWN_SETS[i]   # [library set, shader suffix]
		var a := lib.set_texture(names[0], "albedo")
		var n := lib.set_texture(names[0], "normal")
		if a != null and n != null:
			on[i] = 1.0
			out["t_" + names[1]] = a
			out["n_" + names[1]] = n
			tile[i] = lib.tile_in(names[0])
	out["t_on"] = Vector4(on[0], on[1], on[2], on[3])
	out["t_tile"] = Vector4(tile[0], tile[1], tile[2], tile[3])
	return out


## The town's ground map, one RGBA8 texel per cell (row by row): R = the cell's surface kind (its index in `kinds`), G = how a street runs through it (0 along x, 255 along z: the
## street is at least 3 cells long that way and at most 2 across; 128 a junction or a square: anything else), BA = where the middle of its junction is, as an offset from the
## cell's centre (in half cells, 128 = none); on a HOUSE cell B is instead its lot's hash (1..254): the shader picks the lot's plaster and timber from it (plan R4b).
## The shader looks the ground up through a noise-bent point, so the cobble / earth border wanders off the 3 in grid; pure data, the rules never read it.
static func ground_map(layout: Dictionary, kinds: Array) -> PackedByteArray:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cells: Array = layout["cells"]
	var street := func(x: int, z: int) -> bool: return x >= 0 and z >= 0 and x < nx and z < nz and cells[z * nx + x]["street"]
	var reach := func(x: int, z: int, dx: int, dz: int) -> int:   # street cells in a straight line from (x, z) in one direction, not counting (x, z)
		var n := 0
		while street.call(x + (n + 1) * dx, z + (n + 1) * dz):
			n += 1
		return n
	var run_of := func(x: int, z: int) -> int:
		if not street.call(x, z):
			return 128
		var h: int = 1 + reach.call(x, z, 1, 0) + reach.call(x, z, -1, 0)
		var v: int = 1 + reach.call(x, z, 0, 1) + reach.call(x, z, 0, -1)
		return 0 if h >= 3 and v <= 2 else (255 if v >= 3 and h <= 2 else 128)
	var junction := func(x: int, z: int) -> bool: return street.call(x, z) and run_of.call(x, z) == 128
	var centre := {}   # junction cell -> the mean of its 4-connected junction blob, in cells
	for i in nx * nz:
		if centre.has(i) or not junction.call(i % nx, i / nx):
			continue
		var blob: Array[int] = [i]
		var at := 0
		while at < blob.size():
			var c := blob[at]
			at += 1
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := (c / nx + d.y) * nx + c % nx + d.x
				if junction.call(c % nx + d.x, c / nx + d.y) and not blob.has(n):
					blob.append(n)
		var mean := Vector2.ZERO
		for c in blob:
			mean += Vector2(c % nx, c / nx)
		mean = (mean / blob.size() * 2.0).round() * 0.5   # (SETT-SEAM, lane townC4) the blob's middle on the half-cell grid, so every cell of it encodes the SAME point exactly
		for c in blob:
			centre[c] = mean - Vector2(c % nx, c / nx)
	var bytes := PackedByteArray()
	var cell_in := float(layout["cell_in"])
	var tiers := BoardgenTownDressing.tier_parts(layout)
	for i in nx * nz:
		var x := i % nx
		var z := i / nx
		var run: int = run_of.call(x, z)
		if tiers["cells"].has(i):
			run = 1 + int(float(tiers["shade"]["%d/%d" % [cells[i]["lot_id"], tiers["cells"][i]]]) * 253.0)   # a ruined tier: the tone of its part (the shader reads it on tier faces)
		var off := (centre.get(i, Vector2.ZERO) as Vector2) * 2.0   # in half cells: 128 = none, +-127 half cells reach across any board (was 6 in = 0..255: a square wider than 2 cells was clamped, so its cells fanned round different middles and met on a straight seam)
		var bx := clampi(128 + roundi(off.x), 1, 255)
		if cells[i]["lot_id"] != 0 and not cells[i]["street"] and ["Block", "Terrace", "Deck", "Roofed"].has(cells[i]["lot_kind"]):
			bx = 1 + int(BoardgenTownDressing._hash(int(cells[i]["lot_id"]), 1 if z >= nz / 2 else 0, 200) * 253.0)   # a house cell: its lot's hash (junction offsets are for street cells only)
		bytes.append_array([kinds.find(_cell_kind(cells[i], true)), run, bx, clampi(128 + roundi(off.y), 1, 255)])
	return bytes


## The theme's board shader. Deepworks: a one-texel-per-cell texture, red = height of the cell's top in inches, green = 255 for a sump, blue = the lot id
## (mod 256: a roof has one look per lot), alpha = 255 for the floor cell at the foot of a ladder (the board shader puts no door on the wall there).
## A town greybox reads its colours from the theme's palette.
func _make_material(layout: Dictionary, theme: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = theme["shader"]
	mat.set_shader_parameter("cell_in", float(layout["cell_in"]))
	if theme["id"] == BoardgenTheme.RUIN_TOWN:
		mat.set_shader_parameter("palette", PackedColorArray(theme["palette"]))
		mat.set_shader_parameter("ground_map", ImageTexture.create_from_image(Image.create_from_data(layout["nx"], layout["nz"], false, Image.FORMAT_RGBA8, ground_map(layout, theme["kinds"]))))
		mat.set_shader_parameter("board_cells", Vector2(layout["nx"], layout["nz"]))
		var tale := BoardgenTownDressing.story(int(layout.get("seed", 0)))
		mat.set_shader_parameter("story", Vector4(tale.r, tale.g, tale.b, tale.a))
		BoardgenTownGrit.apply(mat, layout)   # why the ground is dirty where it is
		BoardgenTownGreen.apply(mat, layout)   # (LOOK5 S6) where the yards grow, wear and meet the street: the soil blend reads it
		var lib := TiefwerkLibrary.new(BoardgenTheme.TOWN_LIBRARY)   # the authored T-R1 surfaces when they are cached (NML_RUINTOWN_LIB_DIR in dev); the shader keeps its procedural look otherwise
		lib.name = "TownLibrary"
		add_child(lib)
		var sets := town_sets(lib)
		for key: String in sets:
			mat.set_shader_parameter(key, sets[key])
		var soil := town_soil(lib)   # (LOOK5 S2) the yards' four soil sets as texture arrays, when all are cached
		for key: String in soil:
			mat.set_shader_parameter(key, soil[key])
		_soil_ok = not soil.is_empty()
		return mat
	var bytes := PackedByteArray()
	var feet := {}
	for conn: Dictionary in layout["connectors"]:
		feet[int(conn["low_xz"][1]) * int(layout["nx"]) + int(conn["low_xz"][0])] = true
	for i in layout["cells"].size():
		var c: Dictionary = layout["cells"][i]
		bytes.append_array([int(layout["level_in"][c["level"]]), 255 if c["lot_kind"] == "Hazard" else 0, int(c["lot_id"]) % 256, 255 if feet.has(i) else 0])
	mat.set_shader_parameter("cells", ImageTexture.create_from_image(Image.create_from_data(layout["nx"], layout["nz"], false, Image.FORMAT_RGBA8, bytes)))
	mat.set_shader_parameter("board_cells", Vector2(layout["nx"], layout["nz"]))
	return mat
