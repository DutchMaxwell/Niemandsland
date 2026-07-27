extends StaticBody3D
## Tabletop surface with configurable size
## Standard wargaming table sizes: 4x4, 4x6, 6x4 feet

## Emitted whenever the table is rebuilt to a new size (in feet). Dependents that must
## track the play-field extent (ground mist, ...) connect here, so EVERY resize path —
## size dialog, save load, network sync — keeps them in sync.
signal table_resized(size_feet: Vector2)
## Wave-3 tutorial seam: the biome switch was silent (set_biome had no signal).
signal biome_changed(biome_name: String)

@export var default_color: Color = Color(0.2, 0.35, 0.2)  # Gaming mat green
@export var show_grid: bool = true
@export var grid_size_inches: float = 1.0
@export var default_texture_path: String = "res://assets/terrain/table_surface_default.png"

var _default_texture: Texture2D = null

## Detail noise is biome-independent — generated ONCE and reused. NoiseTexture2D
## fills in on a background thread; regenerating it per material rebuild (twice per
## biome switch) raced the renderer and produced garbage normals (rainbow speckle).
var _detail_normal_tex: Texture2D = null
var _detail_height_tex: Texture2D = null

## On-demand biome battlemap delivery (R2 + local cache); see BiomeLibrary.
var _biome_library: BiomeLibrary = null

## Area-wide grass tufts (grassland biome only); see GrassField.
var _grass_field: GrassField = null

var table_size: Vector2 = Vector2(4, 4)  # In feet, will be converted to meters

const FEET_TO_METERS: float = 0.3048  # 1 foot = 0.3048 meters
const INCHES_TO_METERS: float = 0.0254  # 1 inch = 0.0254 meters

# One biome battlemap covers the whole table at a FIXED real-world extent
# (REFERENCE_TABLE_FEET); smaller tables show a centred crop, so ground features keep a
# constant real-world scale regardless of table size. A densely-tiled procedural
# micro-relief is layered on top for crisp close-up surface detail.
const GROUND_SHADER: Shader = preload("res://shaders/table_ground.gdshader")
const REFERENCE_TABLE_FEET: Vector2 = Vector2(6, 4)  # battlemaps are authored for 6x4 ft
const DETAIL_TILING: float = 28.0
const DETAIL_NOISE_SIZE: int = 512
## Micro-relief normal-map depth — SHARED by the ground and the base top so a base answers the sun
## identically to the board it sits on (identical texture => identical brightness).
const DETAIL_NORMAL_STRENGTH: float = 0.35
## Base-top rim shading: SHIPPED DEFAULT IS 0.0 — the black beveled rim alone grounds the base, and
## the terrain top must read identical to the board (verified numerically to < 1 %, see
## tools/base_luminance_qa.gd). The uniform is retained only for later taste-tuning: raise the
## strength to reintroduce a thin contact-shadow band toward the rim.
const BASE_TOP_VIGNETTE_STRENGTH: float = 0.0    # max darkening at the very rim (0 = off, shipped)
const BASE_TOP_VIGNETTE_START: float = 0.80      # rim_t where the shading begins (thin outer band)

## Shared terrain-projected material for model base tops (BaseDecor). ONE material for the whole
## table: every base samples the SAME biome texture via world-space XZ (see base_terrain_top.gdshader),
## so a biome/size change here updates every model's base in one place. Parameters are refreshed from
## the SAME source the ground material uses, on the SAME rebuild seam (_build_ground_material).
const BASE_TOP_SHADER: Shader = preload("res://shaders/base_terrain_top.gdshader")
## PlaneMesh maps u = x/size_x + 0.5 and v = z/size_z + 0.5 (both increase with +axis; verified in
## table_ground_projection_test.gd). The base shader reconstructs plane UV from world XZ the same way.
const BASE_UV_AXIS_SIGN: Vector2 = Vector2(1.0, 1.0)
var _base_top_material: ShaderMaterial = null

# Biome battlemaps are delivered on demand from R2 (see docs/ASSET_DELIVERY.md) and cached
# locally; assets/biome_manifest.json maps each key -> { url, sha256 }. This is the canonical
# list of selectable biomes (the standard map is the default); delivery is resolved by
# BiomeLibrary at runtime, with table_surface_default.png as the offline fallback.
const DEFAULT_BIOME: String = "temperate_grassland"
const BIOMES: Array[String] = [
	"temperate_grassland", "arid_desert", "frozen_tundra",
	"volcanic_ash", "alien_jungle", "urban_ruins",
]

## Currently selected biome (key into BIOMES).
var biome: String = DEFAULT_BIOME

@onready var mesh_instance: MeshInstance3D = $TableMesh
@onready var collision_shape: CollisionShape3D = $TableCollision


func _ready() -> void:
	# Add to table group for raycasting
	add_to_group("table")
	# Ensure collision layer is set
	collision_layer = 1
	collision_mask = 1

	# Physics material for table surface (stable values)
	var table_physics = PhysicsMaterial.new()
	table_physics.friction = 0.9  # High friction for stability
	table_physics.bounce = 0.1  # Very low bounce
	physics_material_override = table_physics

	# Biome battlemaps load on demand from R2 (BiomeLibrary). Start with the bundled
	# fallback surface so the table always renders, then swap in the biome once cached.
	_biome_library = BiomeLibrary.new()
	_biome_library.name = "BiomeLibrary"
	add_child(_biome_library)
	_grass_field = GrassField.new()
	_grass_field.name = "GrassField"
	add_child(_grass_field)
	_grass_field.set_biome(biome)
	_load_fallback_texture()
	_apply_biome(biome)


## Setup table with given size in feet
func setup_table(size_feet: Vector2) -> void:
	table_size = size_feet
	var size_meters = size_feet * FEET_TO_METERS

	# Remove old borders if any, but preserve overlay nodes
	for child in get_children():
		if child != mesh_instance and child != collision_shape:
			# Preserve terrain overlay and other overlay nodes
			if child.name == "TerrainOverlay" or child.is_in_group("table_overlay"):
				continue
			# Preserve the biome delivery service (it owns the HTTPRequest): freeing it
			# here killed the battlemap download started by the table-size dialog, so
			# the chosen biome never replaced the fallback surface. The grass field
			# resizes itself instead of being rebuilt.
			if child == _biome_library or child == _grass_field:
				continue
			child.queue_free()

	# Create table mesh
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = size_meters
	plane_mesh.subdivide_width = int(size_feet.x * 12 / grid_size_inches) if show_grid else 1
	plane_mesh.subdivide_depth = int(size_feet.y * 12 / grid_size_inches) if show_grid else 1

	mesh_instance.mesh = plane_mesh

	mesh_instance.material_override = _build_ground_material()

	# Create collision shape - MUCH larger to catch falling dice
	# Top surface at y=0 (same as visual mesh)
	var box_shape = BoxShape3D.new()
	# Extend collision 1 meter beyond table edges on all sides
	box_shape.size = Vector3(size_meters.x + 2.0, 0.5, size_meters.y + 2.0)  # 50cm thick, extended
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0, -0.25, 0)  # Top at y=0 (aligned with visual)

	# Add table edge/border
	_create_table_border(size_meters)

	if _grass_field != null:
		_grass_field.set_table_size(size_meters)
	table_resized.emit(size_feet)


## Build the play-surface material: macro battlefield mat + tiled procedural micro-relief
## (anisotropic mipmaps + a seamless detail normal/height so it stays crisp up close).
func _build_ground_material() -> Material:
	# Detail noise is shared with the base-top material (same relief), so generate it BEFORE the
	# base top is refreshed below — otherwise the base would miss the normal map on the first build.
	if _detail_normal_tex == null:
		_detail_normal_tex = _make_detail_noise(true)
		_detail_height_tex = _make_detail_noise(false)

	# Keep the shared base-top material in lock-step with the displayed ground: same rebuild seam,
	# same source texture / uv_scale / detail, so a biome or table-size change updates every base.
	_update_base_top_material()
	if not _default_texture:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = default_color
		fallback.roughness = 0.9
		fallback.metallic = 0.0
		return fallback

	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("albedo_tex", _default_texture)
	mat.set_shader_parameter("uv_scale", _biome_uv_scale())
	mat.set_shader_parameter("detail_normal", _detail_normal_tex)
	mat.set_shader_parameter("detail_height", _detail_height_tex)
	mat.set_shader_parameter("detail_tiling", DETAIL_TILING)
	mat.set_shader_parameter("detail_normal_strength", DETAIL_NORMAL_STRENGTH)
	mat.set_shader_parameter("detail_albedo_strength", 0.12)
	mat.set_shader_parameter("roughness_value", 0.9)
	return mat


## Load the bundled fallback surface into _default_texture (used until/unless a biome
## battlemap is cached from R2).
func _load_fallback_texture() -> void:
	_default_texture = load(default_texture_path) if ResourceLoader.exists(default_texture_path) else null


## Switch the play-surface biome and resolve its battlemap (async, from R2 + cache).
## Also re-themes the terrain props (ruin walls, trees) to the biome's set.
func set_biome(biome_name: String) -> void:
	if not BIOMES.has(biome_name):
		push_warning("Unknown biome '%s' (known: %s)" % [biome_name, ", ".join(BIOMES)])
		return
	biome = biome_name
	_apply_biome(biome_name)
	biome_changed.emit(biome_name)
	if _grass_field != null:
		_grass_field.set_biome(biome_name)
	var overlay := get_node_or_null("TerrainOverlay")
	if overlay != null and overlay.has_method("set_biome"):
		overlay.set_biome(biome_name)


## Available biome keys (for a selection UI).
func get_biomes() -> Array:
	return BIOMES


## Resolve the biome's battlemap from R2 (cached locally), then swap it onto the table.
## The bundled fallback stays visible while the download runs / if the biome is
## unavailable (e.g. before the first R2 publish).
func _apply_biome(biome_name: String) -> void:
	mesh_instance.material_override = _build_ground_material()  # show fallback immediately
	if not is_instance_valid(_biome_library):
		return
	var path: String = await _biome_library.ensure_biome(biome_name)
	if biome != biome_name:
		return  # selection changed during the download; drop this stale result
	if path.is_empty():
		return  # not available yet — keep the fallback surface
	var tex: Texture2D = _texture_from_file(path)
	if tex == null:
		return
	_default_texture = tex
	mesh_instance.material_override = _build_ground_material()


## Battlemaps are delivered very large (up to ~7.5k px); cap the GPU texture at this
## width. Plenty for a 6 ft table on a 4K screen, cuts the upload from ~200 MB to
## ~45 MB — full-size single-shot uploads triggered sporadic texture corruption
## (magenta/rainbow battlemap) on 8 GB laptop GPUs.
const BATTLEMAP_MAX_WIDTH := 4096


## Build a Texture2D (with mipmaps) from a cached image file on disk (user://).
func _texture_from_file(path: String) -> Texture2D:
	var img := Image.new()
	if img.load(path) != OK:
		push_warning("Table: failed to load biome image %s" % path)
		return null
	if img.get_width() > BATTLEMAP_MAX_WIDTH:
		var scaled_height := int(round(img.get_height() * float(BATTLEMAP_MAX_WIDTH) / float(img.get_width())))
		img.resize(BATTLEMAP_MAX_WIDTH, scaled_height, Image.INTERPOLATE_LANCZOS)
	# WebP decodes to RGB8 (3-byte stride) — a niche GPU upload path that corrupted
	# into rainbow/magenta hues on NVIDIA here. RGBA8 is the well-trodden 4-byte-
	# aligned path; convert before upload.
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## UV scale mapping the fixed 6x4 ft battlemap onto the current table, centred. A 6x4
## table shows the whole image (scale 1); smaller tables show a centred crop (<1).
func _biome_uv_scale() -> Vector2:
	return Vector2(table_size.x / REFERENCE_TABLE_FEET.x, table_size.y / REFERENCE_TABLE_FEET.y)


## Pure world-XZ -> plane-UV parameters for a table size (feet), shared by the ground and base
## projections. Returns { uv_scale, inv_size_m } so a model base can reconstruct the plane UV the
## table's PlaneMesh carries (see base_terrain_top.gdshader). Kept static + pure for testing.
static func plane_uv_params(size_feet: Vector2) -> Dictionary:
	var size_m := Vector2(size_feet.x * FEET_TO_METERS, size_feet.y * FEET_TO_METERS)
	var inv_size := Vector2(
		1.0 / size_m.x if size_m.x > 0.0 else 0.0,
		1.0 / size_m.y if size_m.y > 0.0 else 0.0)
	return {
		"uv_scale": Vector2(size_feet.x / REFERENCE_TABLE_FEET.x, size_feet.y / REFERENCE_TABLE_FEET.y),
		"inv_size_m": inv_size,
	}


## The shared terrain-projected material for model base tops. Created on first use; kept current by
## _update_base_top_material() on every ground rebuild. BaseDecor bases reference this one instance.
func get_base_top_material() -> ShaderMaterial:
	if _base_top_material == null:
		_base_top_material = ShaderMaterial.new()
		_base_top_material.shader = BASE_TOP_SHADER
		_update_base_top_material()
	return _base_top_material


## Refresh the shared base-top material from the CURRENT ground state (texture, uv_scale, detail).
## Mirrors _build_ground_material's parameters so a base reads as a seamless window onto the ground.
func _update_base_top_material() -> void:
	if _base_top_material == null:
		_base_top_material = ShaderMaterial.new()
		_base_top_material.shader = BASE_TOP_SHADER
	var params := plane_uv_params(table_size)
	# The table is at world origin; read global_position only when in-tree (avoids a benign
	# "!is_inside_tree()" engine error in pure-parameter tests that never add the table to the tree).
	var center: Vector3 = global_position if is_inside_tree() else position
	_base_top_material.set_shader_parameter("uv_scale", params["uv_scale"])
	_base_top_material.set_shader_parameter("inv_table_size", params["inv_size_m"])
	_base_top_material.set_shader_parameter("table_center_xz", Vector2(center.x, center.z))
	_base_top_material.set_shader_parameter("uv_axis_sign", BASE_UV_AXIS_SIGN)
	_base_top_material.set_shader_parameter("detail_tiling", DETAIL_TILING)
	_base_top_material.set_shader_parameter("detail_normal_strength", DETAIL_NORMAL_STRENGTH)
	_base_top_material.set_shader_parameter("detail_albedo_strength", 0.12)
	_base_top_material.set_shader_parameter("roughness_value", 0.9)
	# Contact-shadow hint only (subtle rim shading) — the centre reads identical to the board.
	_base_top_material.set_shader_parameter("vignette_strength", BASE_TOP_VIGNETTE_STRENGTH)
	_base_top_material.set_shader_parameter("vignette_start", BASE_TOP_VIGNETTE_START)
	_base_top_material.set_shader_parameter("fallback_color", Vector3(default_color.r, default_color.g, default_color.b))
	if _default_texture != null:
		_base_top_material.set_shader_parameter("albedo_tex", _default_texture)
		_base_top_material.set_shader_parameter("has_texture", true)
	else:
		_base_top_material.set_shader_parameter("has_texture", false)
	# Match the ground's detail relief so the base catches the same sun glints (guarded so the
	# pure-parameter tests, which never build the ground, don't force noise generation).
	if _detail_normal_tex != null:
		_base_top_material.set_shader_parameter("detail_normal", _detail_normal_tex)
	if _detail_height_tex != null:
		_base_top_material.set_shader_parameter("detail_height", _detail_height_tex)


## Generate a seamless tiling noise texture for ground micro-detail. As a normal map
## when `as_normal` is true (surface relief), otherwise a height field (albedo variation).
func _make_detail_noise(as_normal: bool) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05 if as_normal else 0.035
	noise.fractal_octaves = 4

	var tex := NoiseTexture2D.new()
	tex.width = DETAIL_NOISE_SIZE
	tex.height = DETAIL_NOISE_SIZE
	tex.seamless = true
	tex.noise = noise
	if as_normal:
		tex.as_normal_map = true
		tex.bump_strength = 6.0
	return tex


func _create_table_border(size_meters: Vector2) -> void:
	var border_height = 0.05
	var border_width = 0.015  # thin rim (halved from 0.03)
	var wall_height = 0.15  # Invisible wall height to catch dice
	var border_material = StandardMaterial3D.new()
	border_material.albedo_color = Color(0.3, 0.2, 0.1)  # Wood color
	border_material.roughness = 0.7

	var positions = [
		Vector3(0, border_height / 2, -size_meters.y / 2 - border_width / 2),  # Front
		Vector3(0, border_height / 2, size_meters.y / 2 + border_width / 2),   # Back
		Vector3(-size_meters.x / 2 - border_width / 2, border_height / 2, 0),  # Left
		Vector3(size_meters.x / 2 + border_width / 2, border_height / 2, 0),   # Right
	]

	var sizes = [
		Vector3(size_meters.x + border_width * 2, border_height, border_width),
		Vector3(size_meters.x + border_width * 2, border_height, border_width),
		Vector3(border_width, border_height, size_meters.y),
		Vector3(border_width, border_height, size_meters.y),
	]

	# Wall collision positions (taller invisible walls)
	var wall_positions = [
		Vector3(0, wall_height / 2, -size_meters.y / 2 - border_width / 2),
		Vector3(0, wall_height / 2, size_meters.y / 2 + border_width / 2),
		Vector3(-size_meters.x / 2 - border_width / 2, wall_height / 2, 0),
		Vector3(size_meters.x / 2 + border_width / 2, wall_height / 2, 0),
	]

	var wall_sizes = [
		Vector3(size_meters.x + border_width * 2, wall_height, border_width),
		Vector3(size_meters.x + border_width * 2, wall_height, border_width),
		Vector3(border_width, wall_height, size_meters.y),
		Vector3(border_width, wall_height, size_meters.y),
	]

	for i in range(4):
		# Visual border
		var border_mesh = BoxMesh.new()
		border_mesh.size = sizes[i]

		var border_instance = MeshInstance3D.new()
		border_instance.mesh = border_mesh
		border_instance.material_override = border_material
		border_instance.position = positions[i]
		add_child(border_instance)

		# Invisible collision wall
		var wall = StaticBody3D.new()
		wall.name = "Wall_%d" % i
		wall.collision_layer = 1
		wall.collision_mask = 1

		var wall_collision = CollisionShape3D.new()
		var wall_shape = BoxShape3D.new()
		wall_shape.size = wall_sizes[i]
		wall_collision.shape = wall_shape
		wall.add_child(wall_collision)

		wall.position = wall_positions[i]
		add_child(wall)


