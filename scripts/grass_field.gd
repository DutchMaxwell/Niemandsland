class_name GrassField
extends MultiMeshInstance3D
## Area-wide grass tufts for the grassland biome: one MultiMesh of small crossed
## alpha-scissor quads (5-10 mm tall, colour-jittered greens) scattered over the
## whole table — a single draw call, so it costs next to nothing. Owned by table.gd;
## rebuilt on table resize / biome change / quality change (PERFORMANCE: no grass).

# === Constants ===

const GRASS_BIOME := "temperate_grassland"
## Tufts per square metre per quality tier (PERFORMANCE..ULTRA).
const TUFTS_PER_M2: Array[int] = [0, 2000, 4500, 8000, 12000]
const TUFT_HEIGHT_MIN_M := 0.008
const TUFT_HEIGHT_MAX_M := 0.016
const TUFT_WIDTH_M := 0.009
const BASE_COLOR := Color(0.32, 0.45, 0.2)
const COLOR_JITTER_MIN := 0.75
const COLOR_JITTER_MAX := 1.25
const BLADE_TEXTURE_SIZE := 128
const RNG_SEED := 71823  # deterministic scatter (purely cosmetic, but stable)

# === Private variables ===

var _table_size := Vector2(1.22, 1.22)
var _biome := ""

# === Lifecycle ===

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	GraphicsSettings.settings_applied.connect(_on_quality_changed)
	_rebuild()

# === Public ===

func set_table_size(size_m: Vector2) -> void:
	if size_m.is_equal_approx(_table_size):
		return
	_table_size = size_m
	_rebuild()


## Grass only grows on the grassland biome; other biomes clear the field.
func set_biome(biome_name: String) -> void:
	if biome_name == _biome:
		return
	_biome = biome_name
	_rebuild()

# === Private ===

func _rebuild() -> void:
	var tier: int = clampi(GraphicsSettings.current_preset, 0, TUFTS_PER_M2.size() - 1)
	var per_m2: int = TUFTS_PER_M2[tier]
	if _biome != GRASS_BIOME or per_m2 <= 0:
		multimesh = null
		return

	var count := int(_table_size.x * _table_size.y * per_m2)
	var rng := RandomNumberGenerator.new()
	rng.seed = RNG_SEED

	var mesh := _tuft_mesh()
	var grass := MultiMesh.new()
	grass.transform_format = MultiMesh.TRANSFORM_3D
	grass.use_colors = true
	grass.mesh = mesh
	grass.instance_count = count
	var half := _table_size / 2.0
	for i in count:
		var height := rng.randf_range(TUFT_HEIGHT_MIN_M, TUFT_HEIGHT_MAX_M)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		basis = basis.scaled(Vector3(rng.randf_range(0.8, 1.2), height / TUFT_HEIGHT_MAX_M, rng.randf_range(0.8, 1.2)))
		var origin := Vector3(rng.randf_range(-half.x, half.x), 0.0, rng.randf_range(-half.y, half.y))
		grass.set_instance_transform(i, Transform3D(basis, origin))
		grass.set_instance_color(i, BASE_COLOR * rng.randf_range(COLOR_JITTER_MIN, COLOR_JITTER_MAX))
	multimesh = grass


## One tuft: two crossed quads (4 triangles) carrying a procedural blade texture,
## anchored at the ground, TUFT_HEIGHT_MAX_M tall at scale 1.
func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := TUFT_WIDTH_M / 2.0
	var h := TUFT_HEIGHT_MAX_M
	for angle in [0.0, PI / 2.0]:
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var a := -dir * w
		var b := dir * w
		st.set_uv(Vector2(0, 1)); st.add_vertex(a)
		st.set_uv(Vector2(1, 1)); st.add_vertex(b)
		st.set_uv(Vector2(1, 0)); st.add_vertex(b + Vector3.UP * h)
		st.set_uv(Vector2(0, 1)); st.add_vertex(a)
		st.set_uv(Vector2(1, 0)); st.add_vertex(b + Vector3.UP * h)
		st.set_uv(Vector2(0, 0)); st.add_vertex(a + Vector3.UP * h)
	st.generate_normals()
	var mesh := st.commit()

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _blade_texture()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.texture_repeat = false
	mesh.surface_set_material(0, mat)
	return mesh


## Procedural blade alpha texture: slender curved blades with anti-aliased edges,
## white (the instance colour tints them), transparent background. Mipmapped so
## distant minification doesn't shimmer into a sawtooth.
func _blade_texture() -> ImageTexture:
	var size := BLADE_TEXTURE_SIZE
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = RNG_SEED
	for blade in 6:
		var base_x := rng.randf_range(0.1, 0.9)
		var lean := rng.randf_range(-0.22, 0.22)
		var blade_height := rng.randf_range(0.55, 1.0)
		for row in size:
			var t := float(row) / float(size - 1)        # 0 = top, 1 = ground
			if 1.0 - t > blade_height:
				continue
			var grow := (1.0 - t) / blade_height          # 0 at ground, 1 at tip
			# Curved lean (quadratic) so blades bow over instead of leaning straight.
			var x := base_x + lean * grow * grow
			var half_w := lerpf(2.2, 0.5, grow)           # slender taper (in px @128)
			var center := x * size
			var shade := 1.0 - grow * 0.3                 # tips slightly darker
			for px in range(int(floor(center - half_w - 1.0)), int(ceil(center + half_w + 1.0)) + 1):
				if px < 0 or px >= size:
					continue
				# Anti-aliased edge: alpha falls off across the last pixel.
				var edge_dist := half_w - absf(float(px) - center)
				var alpha := clampf(edge_dist + 0.5, 0.0, 1.0)
				if alpha <= 0.0:
					continue
				var existing := img.get_pixel(px, row)
				if alpha > existing.a:
					img.set_pixel(px, row, Color(shade, shade, shade, alpha))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _on_quality_changed(_preset_name: String) -> void:
	_rebuild()
