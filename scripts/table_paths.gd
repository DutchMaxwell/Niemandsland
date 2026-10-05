class_name TablePaths
extends Node3D
## Worn dirt paths on the table (S5, lead D14 = a): a table-level setting, saved with the table and sent with the
## table settings, so a reload or the other player sees the same paths. Each path is a polyline of [x, z] points in
## inches from the table centre (the frame of the theme pieces); every segment is one soft-edged dirt decal.
## Decoration only: no collision, rules untouched.

const WIDTH_INCHES := 2.2
const END_INCHES := 1.5   # the segment overlaps its neighbours by this much, so bends have no gaps
const HEIGHT_INCHES := 0.4
const IN2M := 0.0254

static var _texture: ImageTexture = null

var paths: Array = []


## The table's paths node, created on first use.
static func of(table: Node) -> TablePaths:
	var node := table.get_node_or_null("TablePaths") as TablePaths
	if node == null:
		node = TablePaths.new()
		node.name = "TablePaths"
		node.add_to_group("table_overlay")   # setup_table (load, resize) frees the table's other children
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
			d.texture_albedo = _strip_texture()
			d.size = Vector3(a.distance_to(b) + END_INCHES * IN2M, HEIGHT_INCHES * IN2M, WIDTH_INCHES * IN2M)
			d.position = (a + b) * 0.5
			d.rotation.y = -atan2(b.z - a.z, b.x - a.x)
			add_child(d)


## A worn dusty strip: soft, noisy edges across, faded ends along; built once.
static func _strip_texture() -> ImageTexture:
	if _texture != null:
		return _texture
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
			var c := Color(0.40, 0.33, 0.22).lerp(Color(0.33, 0.29, 0.20), 0.5 + nv * 0.5)
			img.set_pixel(px, py, Color(c.r, c.g, c.b, a * 0.42))
	_texture = ImageTexture.create_from_image(img)
	return _texture
