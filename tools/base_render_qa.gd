extends SceneTree
## QA render for the "perfectly based" miniature bases (feat/terrain-bases). Builds the REAL table
## (table.gd + biome battlemap) and spawns three player-owned groups through the REAL base pipeline
## (OPRArmyManager.create_model_from_properties -> _build_model_base -> BaseDecor):
##   * a 5-model infantry unit  (blue, round 25 mm) — multi-model: CLEAN BLACK RIM, no ring, its
##     affiliation is the boundary rubberband (drawn by the real UnitBoundaryVisualizer);
##   * a lone hero              (blue, round 40 mm) — SOLO: black rim + a player-coloured ring (the
##     one-model equivalent of the rubberband);
##   * a 6-model regiment block (red, square 25 mm) — multi-model: terrain top + black rim, no ring.
##
## It captures BEFORE (BaseDecor.legacy_solid_disc = the old solid disc) and AFTER (the new base) on
## two biomes (grassland + desert), each from a table-level 3/4 angle and a top-down angle, so the
## maintainer sees: the terrain cutout, that it ADAPTS per biome, and the full affiliation picture
## (ringed solo model beside a ring-less unit that carries its rubberband).
##
## Usage (needs a REAL renderer — a headless Wayland compositor; NOT Godot's --headless):
##   gamescope --backend headless -W 2560 -H 1440 -- \
##     flatpak run --filesystem=home --socket=wayland --share=network org.godotengine.Godot \
##       --path <project> --rendering-driver vulkan -s res://tools/base_render_qa.gd -- <out_dir>

const IMAGE_SIZE := Vector2i(2560, 1440)
const BIOMES := ["temperate_grassland", "arid_desert"]
const SETTLE_FRAMES := 10
const BIOME_LOAD_FRAMES := 150
## An isolated bare base on open ground (no ring, no rubberband) for the close brightness
## comparison: framed tight so the terrain top sits directly beside untouched board.
const CLOSE_BASE_POS := Vector3(0.42, 0.0, 0.16)

var _table: Node = null
var _manager: OPRArmyManager = null
var _viz = null                    # UnitBoundaryVisualizer
var _camera: Camera3D = null
var _label: Label = null
var _wrappers: Array[Node3D] = []
var _units: Array = []             # GameUnit list (registered in _manager.game_units)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else OS.get_environment("HOME").path_join("basing_out")
	# Optional filename suffix (e.g. "_v2" for a re-render). When set, only the AFTER pass runs
	# (the BEFORE/legacy look was captured in the first round) plus a close brightness comparison.
	var suffix: String = args[1] if args.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(out_dir)

	get_root().size = IMAGE_SIZE
	_build_world()
	await _frames(5)

	var passes: Array = [false] if suffix != "" else [true, false]
	for legacy in passes:
		BaseDecor.legacy_solid_disc = legacy
		_spawn_groups()
		await _frames(5)
		_viz.update_all_boundaries()
		var tag := "before" if legacy else "after"
		for biome in BIOMES:
			await _apply_biome(biome)
			_viz.update_all_boundaries()
			await _frames(SETTLE_FRAMES)
			var short := "grass" if biome == "temperate_grassland" else "desert"
			await _capture_34("%s/%s_%s_34%s.png" % [out_dir, tag, short, suffix], "%s  ·  %s  ·  3/4 view" % [tag.to_upper(), short])
			await _frames(SETTLE_FRAMES)
			await _capture_top("%s/%s_%s_top%s.png" % [out_dir, tag, short, suffix], "%s  ·  %s  ·  top-down" % [tag.to_upper(), short])
			await _frames(SETTLE_FRAMES)
			# Close brightness comparison (AFTER only): a bare base beside untouched board.
			if not legacy:
				await _capture_close("%s/%s_%s_close%s.png" % [out_dir, tag, short, suffix], "%s  ·  %s  ·  base vs board (close)" % [tag.to_upper(), short])
			await _frames(2)
		_clear_groups()

	print("BASE_RENDER_QA_DONE %s" % out_dir)
	quit(0)


# === World ===

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.87, 0.92)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	get_root().add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	get_root().add_child(sun)

	_table = load("res://scripts/table.gd").new()
	_table.name = "Table"
	# table.gd's @onready mesh_instance/collision expect child nodes named TableMesh/TableCollision.
	var tmesh := MeshInstance3D.new()
	tmesh.name = "TableMesh"
	_table.add_child(tmesh)
	var tcol := CollisionShape3D.new()
	tcol.name = "TableCollision"
	_table.add_child(tcol)
	get_root().add_child(_table)          # _ready() adds BiomeLibrary + GrassField
	_table.setup_table(Vector2(6, 4))

	_manager = OPRArmyManager.new()       # methods only; NOT added to the tree (no autoloads needed)
	_manager.table = _table

	_viz = load("res://scripts/unit_boundary_visualizer.gd").new()
	_viz.army_manager = _manager
	_viz.set_process(false)               # we poll update_all_boundaries() ourselves, deterministically
	get_root().add_child(_viz)

	_camera = Camera3D.new()
	_camera.fov = 40.0
	get_root().add_child(_camera)
	_camera.current = true

	var layer := CanvasLayer.new()
	get_root().add_child(layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 46)
	_label.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 8)
	_label.position = Vector2(40, 28)
	layer.add_child(_label)


func _apply_biome(biome: String) -> void:
	_table.set_biome(biome)
	# set_biome resolves the (cached) battlemap asynchronously; wait for it to swap in.
	await _frames(BIOME_LOAD_FRAMES)


# === Groups ===

func _spawn_groups() -> void:
	# Blue 5-model infantry (round 25 mm) — rubberband, no rings.
	var infantry_props := {"name": "Riflemen", "base_size_round": 25, "size": 5, "player_id": 1}
	var inf_nodes: Array[Node3D] = []
	var xs := [-0.17, -0.13, -0.09, -0.05, -0.01]
	for x in xs:
		inf_nodes.append(_spawn(infantry_props, Vector3(x, 0.0, -0.12)))
	_register_unit("infantry", infantry_props, inf_nodes)

	# Blue lone hero (round 40 mm) — SOLO ring, no rubberband.
	var hero_props := {"name": "Warlord", "base_size_round": 40, "size": 1, "player_id": 1}
	var hero_node := _spawn(hero_props, Vector3(0.17, 0.0, -0.12))
	_register_unit("hero", hero_props, [hero_node])

	# Red 6-model regiment (square 25 mm, 3x2) — terrain top + black rim, no rings.
	var reg_props := {"name": "Phalanx", "base_is_square": true, "base_width_mm": 25, "base_depth_mm": 25,
		"base_size_round": 25, "size": 6, "player_id": 2}
	var reg_nodes: Array[Node3D] = []
	for row in range(2):
		for col in range(3):
			var pos := Vector3(-0.03 + col * 0.03, 0.0, 0.10 + row * 0.03)
			reg_nodes.append(_spawn(reg_props, pos))
	_register_unit("regiment", reg_props, reg_nodes)

	# Lone base on open ground for the close brightness comparison. size 2 => no affiliation ring;
	# deliberately NOT registered as a unit => the boundary visualizer leaves it alone, so it is a
	# bare terrain-top base sitting directly beside untouched board (the seam the maintainer judges).
	_spawn({"name": "Trooper", "base_size_round": 32, "size": 2, "player_id": 1}, CLOSE_BASE_POS)


func _spawn(props: Dictionary, pos: Vector3) -> Node3D:
	var wrapper: Node3D = _manager.create_model_from_properties(props)
	get_root().add_child(wrapper)
	wrapper.position = pos
	_wrappers.append(wrapper)
	return wrapper


func _register_unit(unit_id: String, props: Dictionary, nodes: Array[Node3D]) -> void:
	var gu := GameUnit.new()
	gu.unit_id = unit_id
	gu.unit_properties = props.duplicate(true)
	for n in nodes:
		var mi := ModelInstance.new()
		mi.node = n
		mi.is_alive = true
		mi.properties = {"tough": 1}
		mi.unit = gu
		gu.models.append(mi)
	_manager.game_units[unit_id] = gu
	_units.append(gu)


func _clear_groups() -> void:
	_viz.clear_all()
	for w in _wrappers:
		if is_instance_valid(w):
			w.queue_free()
	_wrappers.clear()
	_manager.game_units.clear()
	_units.clear()


# === Capture ===

func _capture_34(path: String, caption: String) -> void:
	_label.text = caption
	_camera.look_at_from_position(Vector3(0.0, 0.34, 0.60), Vector3(0.0, 0.0, 0.0), Vector3.UP)
	await _grab(path)


func _capture_top(path: String, caption: String) -> void:
	_label.text = caption
	_camera.look_at_from_position(Vector3(0.0, 0.80, 0.02), Vector3(0.0, 0.0, 0.02), Vector3(0, 0, -1))
	await _grab(path)


func _capture_close(path: String, caption: String) -> void:
	# Tight 3/4 close-up on the isolated open-ground base: base + surrounding board fill the frame so
	# a brightness seam between the terrain top and the board would be obvious side-by-side.
	_label.text = caption
	_camera.look_at_from_position(CLOSE_BASE_POS + Vector3(0.035, 0.075, 0.075), CLOSE_BASE_POS, Vector3.UP)
	await _grab(path)


func _grab(path: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		push_error("base_render_qa: save_png failed (%d) for %s" % [err, path])
	else:
		print("WROTE %s (%dx%d)" % [path, img.get_width(), img.get_height()])


func _frames(n: int) -> void:
	for _i in range(n):
		await process_frame
