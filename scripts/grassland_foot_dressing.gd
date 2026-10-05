class_name GrasslandFootDressing
extends Decal
## Earth and moss at the foot of a free ruin or solid (S6-1, maintainer 05.10.: the ruins must belong to the picture):
## a noisy dirt/moss patch 3" around the footprint, a child of the piece so it moves, turns and goes with it.
## Decoration only (no collision, rules untouched). Grassland only for now (lead D12): it shows while the table is
## "temperate_grassland" and follows biome changes; without a table (previews, tests) it stays visible.

const MARGIN_INCHES := 3.0
const HEIGHT_INCHES := 0.4
const GRASSLAND := "temperate_grassland"
const DIRT := Color(0.27, 0.21, 0.13)
const MOSS := Color(0.17, 0.21, 0.09)

static var _textures := {}   # footprint -> ImageTexture, shared by every piece of that size


func setup(footprint_inches: Vector2) -> GrasslandFootDressing:
	name = "FootDressing"
	texture_albedo = _texture(footprint_inches)
	size = Vector3(footprint_inches.x + 2.0 * MARGIN_INCHES, HEIGHT_INCHES,
		footprint_inches.y + 2.0 * MARGIN_INCHES) * 0.0254
	return self


func _ready() -> void:
	var table := get_tree().get_first_node_in_group("table")
	if table == null:
		return
	_show_for(str(table.get("biome")))
	table.biome_changed.connect(_show_for)


func _show_for(biome: String) -> void:
	visible = biome == GRASSLAND


## Opaque at the foot, an organic (noisy) edge fading out MARGIN_INCHES away, dirt and moss mixed; 8 px per inch.
## Fixed seed, so every client draws the same patch.
static func _texture(fp: Vector2) -> ImageTexture:
	if _textures.has(fp):
		return _textures[fp]
	var w := fp.x + 2.0 * MARGIN_INCHES
	var h := fp.y + 2.0 * MARGIN_INCHES
	var img := Image.create(int(w * 8.0), int(h * 8.0), false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 20261005
	noise.frequency = 0.25
	for py in img.get_height():
		for px in img.get_width():
			var x := (px + 0.5) / 8.0 - w * 0.5
			var z := (py + 0.5) / 8.0 - h * 0.5
			var dx := maxf(absf(x) - fp.x * 0.5, 0.0)
			var dz := maxf(absf(z) - fp.y * 0.5, 0.0)
			var a := clampf(1.0 - (sqrt(dx * dx + dz * dz) + noise.get_noise_2d(x, z) * 1.2) / MARGIN_INCHES, 0.0, 1.0)
			var c := DIRT.lerp(MOSS, clampf(0.5 + noise.get_noise_2d(x * 2.0 + 50.0, z * 2.0), 0.0, 1.0))
			img.set_pixel(px, py, Color(c.r, c.g, c.b, a * a * 0.85))
	_textures[fp] = ImageTexture.create_from_image(img)
	return _textures[fp]
