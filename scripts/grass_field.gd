class_name GrassField
extends MultiMeshInstance3D
## Area-wide grass tufts for the grassland biome: one MultiMesh of small crossed
## alpha-scissor quads (4-12 mm tall, colour-jittered greens) clustered over the
## whole table — a single draw call, so it costs next to nothing. Owned by table.gd;
## rebuilt on table resize / biome change / quality change (PERFORMANCE: no grass).

# === Constants ===

const GRASS_BIOME := "temperate_grassland"
## Tufts per square metre per quality tier (PERFORMANCE..ULTRA).
const TUFTS_PER_M2: Array[int] = [0, 2000, 4500, 8000, 12000]
const TUFT_HEIGHT_MIN_M := 0.004
const TUFT_HEIGHT_MAX_M := 0.012
const TUFT_WIDTH_M := 0.016
const BASE_COLOR := Color(0.32, 0.40, 0.18)
const COLOR_JITTER_MIN := 0.75
const COLOR_JITTER_MAX := 1.25
const BLADE_TEXTURE_SIZE := 128
const RNG_SEED := 71823  # deterministic scatter (purely cosmetic, but stable)
const COVERAGE_EXTENT_M := 4.0
const COVERAGE_SIZE := 256
static var _coverage_image: Image
static var _coverage_texture: ImageTexture

# === Private variables ===

var _table_size := Vector2(1.22, 1.22)
var _biome := ""
## The tuft mesh (geometry + blade texture + material) is identical for every rebuild,
## but _blade_texture() does per-pixel CPU work; build it once and reuse so quality
## switches and table resizes only re-scatter instances, never regenerate the texture.
var _tuft_mesh_cache: ArrayMesh = null

# === Lifecycle ===

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	GraphicsSettings.settings_applied.connect(_on_quality_changed)
	_rebuild()

# === Public ===

## A synchronous, cached mask shared by ground shading and tuft placement.
## World scale stays fixed when resizing the board; no background noise race.
static func coverage_texture() -> ImageTexture:
	if _coverage_texture == null:
		var noise := FastNoiseLite.new()
		noise.seed = RNG_SEED
		noise.frequency = 5.0
		_coverage_image = Image.create(COVERAGE_SIZE, COVERAGE_SIZE, false, Image.FORMAT_R8)
		for y in COVERAGE_SIZE:
			for x in COVERAGE_SIZE:
				var p := ((Vector2(x, y) + Vector2(0.5, 0.5)) / COVERAGE_SIZE - Vector2(0.5, 0.5)) * COVERAGE_EXTENT_M
				var amount := clampf(0.5 + noise.get_noise_2d(p.x, p.y) * 1.8, 0.0, 1.0)
				_coverage_image.set_pixel(x, y, Color(amount, 0, 0))
		_coverage_image.generate_mipmaps()
		_coverage_texture = ImageTexture.create_from_image(_coverage_image)
	return _coverage_texture


static func coverage_at(world_xz: Vector2) -> float:
	coverage_texture()
	var uv := world_xz / COVERAGE_EXTENT_M + Vector2(0.5, 0.5)
	var pixel := (uv * COVERAGE_SIZE).clamp(Vector2.ZERO, Vector2.ONE * (COVERAGE_SIZE - 1))
	return _coverage_image.get_pixel(int(pixel.x), int(pixel.y)).r


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

	if _tuft_mesh_cache == null:
		_tuft_mesh_cache = _tuft_mesh()
	var mesh := _tuft_mesh_cache
	var grass := MultiMesh.new()
	grass.transform_format = MultiMesh.TRANSFORM_3D
	grass.use_colors = true
	grass.mesh = mesh
	grass.instance_count = count
	var half := _table_size / 2.0
	var placed := 0
	for i in count:
		var height := rng.randf_range(TUFT_HEIGHT_MIN_M, TUFT_HEIGHT_MAX_M)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		basis = basis.scaled(Vector3(rng.randf_range(0.8, 1.2), height / TUFT_HEIGHT_MAX_M, rng.randf_range(0.8, 1.2)))
		var origin := Vector3(rng.randf_range(-half.x, half.x), 0.0, rng.randf_range(-half.y, half.y))
		var color := BASE_COLOR * rng.randf_range(COLOR_JITTER_MIN, COLOR_JITTER_MAX)
		var coverage := coverage_at(Vector2(origin.x, origin.z))
		if coverage < 0.48:
			continue
		color = color.lerp(Color(0.42, 0.38, 0.22), (1.0 - coverage) * 0.65)
		grass.set_instance_transform(placed, Transform3D(basis, origin))
		grass.set_instance_color(placed, color)
		placed += 1
	grass.visible_instance_count = placed
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
		st.set_normal(Vector3.UP)
		var a := -dir * w
		var b := dir * w
		st.set_uv(Vector2(0, 1)); st.add_vertex(a)
		st.set_uv(Vector2(1, 1)); st.add_vertex(b)
		st.set_uv(Vector2(1, 0)); st.add_vertex(b + Vector3.UP * h)
		st.set_uv(Vector2(0, 1)); st.add_vertex(a)
		st.set_uv(Vector2(1, 0)); st.add_vertex(b + Vector3.UP * h)
		st.set_uv(Vector2(0, 0)); st.add_vertex(a + Vector3.UP * h)
	var mesh := st.commit()

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/grass_tuft.gdshader")
	mat.set_shader_parameter("blade_texture", _blade_texture())
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
	for blade in 9:
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
			var shade := lerpf(0.45, 1.0, sqrt(grow))     # dark roots, sunlit tips
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
