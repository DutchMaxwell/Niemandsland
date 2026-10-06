class_name TablePaths
extends Node3D
## Worn dirt paths on the table (S5, lead D14 = a): a table-level setting, saved with the table and sent with the
## table settings, so a reload or the other player sees the same paths. Each path is a polyline of [x, z] points in
## inches from the table centre (the frame of the theme pieces); every segment is one soft-edged dirt decal.
## Decoration only: no collision, rules untouched. S8.4: the strip takes the table biome's colour (PALETTE).

const WIDTH_INCHES := 2.2
const END_INCHES := 1.5   # the segment overlaps its neighbours by this much, so bends have no gaps
const HEIGHT_INCHES := 0.4
const IN2M := 0.0254

## S8.4 (maintainer 06.10.: the terrain should match the biome): [edge, centre] per table biome; grassland is today's
## dusty earth, a biome not listed keeps it too.
const PALETTE := {"temperate_grassland": [Color(0.40, 0.33, 0.22), Color(0.33, 0.29, 0.20)],
	"arid_desert": [Color(0.62, 0.50, 0.34), Color(0.54, 0.43, 0.29)], "frozen_tundra": [Color(0.52, 0.52, 0.52), Color(0.40, 0.39, 0.37)],
	"volcanic_ash": [Color(0.20, 0.18, 0.17), Color(0.12, 0.11, 0.11)], "urban_ruins": [Color(0.30, 0.29, 0.27), Color(0.24, 0.23, 0.22)],
	"alien_jungle": [Color(0.26, 0.19, 0.11), Color(0.20, 0.15, 0.09)]}

static var _textures := {}   # biome -> strip texture

var paths: Array = []
var _biome := "temperate_grassland"


## The table's paths node, created on first use.
static func of(table: Node) -> TablePaths:
	var node := table.get_node_or_null("TablePaths") as TablePaths
	if node == null:
		node = TablePaths.new()
		node.name = "TablePaths"
		node.add_to_group("table_overlay")   # setup_table (load, resize) frees the table's other children
		if table.has_signal("biome_changed"):   # S8.4: the strips follow the table's biome
			node._biome = str(table.get("biome"))
			table.biome_changed.connect(node._recolour)
		table.add_child(node)
	return node


func set_paths(new_paths: Array) -> void:
	paths = new_paths.duplicate(true)
	for child in get_children():
		child.queue_free()
		remove_child(child)
	for line: Array in paths:
		for i in range(line.size() - 1):
			var a := Vector3(float(line[i][0]), 0.0, float(line[i][1])) * IN2M
			var b := Vector3(float(line[i + 1][0]), 0.0, float(line[i + 1][1])) * IN2M
			var d := Decal.new()
			d.texture_albedo = _strip_texture(_biome)
			d.size = Vector3(a.distance_to(b) + END_INCHES * IN2M, HEIGHT_INCHES * IN2M, WIDTH_INCHES * IN2M)
			d.position = (a + b) * 0.5
			d.rotation.y = -atan2(b.z - a.z, b.x - a.x)
			add_child(d)
	sync_surface()


func _recolour(biome: String) -> void:
	_biome = biome
	for child in get_children():
		if child is Decal:
			child.texture_albedo = _strip_texture(biome)


## A worn strip in the biome's colours: soft, noisy edges across, faded ends along; built once per biome.
static func _strip_texture(biome: String) -> ImageTexture:
	if _textures.has(biome):
		return _textures[biome]
	var pair: Array = PALETTE.get(biome, PALETTE["temperate_grassland"])
	var img := Image.create(64, 16, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.15
	for py in 16:
		for px in 64:
			var across := absf((py + 0.5) / 16.0 - 0.5) * 2.0
			var along := minf((px + 0.5) / 64.0, 1.0 - (px + 0.5) / 64.0) * 2.0
			var nv := noise.get_noise_2d(px, py)
			var a := clampf((1.0 - across - nv * 0.35) * 1.6, 0.0, 1.0) * clampf(along * 4.0, 0.0, 1.0)
			var c: Color = pair[0].lerp(pair[1], 0.5 + nv * 0.5)
			img.set_pixel(px, py, Color(c.r, c.g, c.b, a * 0.42))
	_textures[biome] = ImageTexture.create_from_image(img)
	return _textures[biome]


## Bounded segments shared by the soil shader and surface dressing, in metres.
func surface_segments() -> PackedVector4Array:
	var result := PackedVector4Array()
	for line: Array in paths:
		for i in range(line.size() - 1):
			var a := Vector2(line[i][0], line[i][1]) * IN2M
			var b := Vector2(line[i+1][0], line[i+1][1]) * IN2M
			if a.distance_squared_to(b) > 0.000001 and result.size() < 64:
				result.append(Vector4(a.x,a.y,b.x,b.y))
	return result

static func surface_amount(p: Vector2, segments: PackedVector4Array) -> float:
	var amount := 0.0
	for edge in segments:
		var a := Vector2(edge.x,edge.y)
		var delta := Vector2(edge.z,edge.w) - a
		var t := clampf((p-a).dot(delta) / maxf(delta.length_squared(),0.000001),0,1)
		amount = maxf(amount,1.0-smoothstep(0.026,0.062,p.distance_to(a+delta*t)))
	return amount

func sync_surface() -> void:
	var table := get_parent()
	if table == null or not table.has_method("get_base_top_material"):
		return
	var segments := surface_segments()
	var count := segments.size()
	segments.resize(64)
	for mat in [table.get_node("TableMesh").material_override, table.get_base_top_material()]:
		if mat is ShaderMaterial:
			mat.set_shader_parameter("path_segments", segments)
			mat.set_shader_parameter("path_count", count)
