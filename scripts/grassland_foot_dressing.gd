class_name GrasslandFootDressing
extends Decal
## Earth and moss at the foot of a free ruin or solid (S6-1, maintainer 05.10.: the ruins must belong to the picture):
## a noisy dirt/moss patch 3" around the footprint, a child of the piece so it moves, turns and goes with it.
## Decoration only (no collision, rules untouched). S8.3: coloured per table biome (PALETTE: sand, frost, ash, dust...)
## and following biome changes, hidden on a biome without a palette and below Medium; without a table (previews,
## tests) it stays visible in the grassland colours.

const MARGIN_INCHES := 3.0
const HEIGHT_INCHES := 0.4
const GRASSLAND := "temperate_grassland"
const DIRT := Color(0.27, 0.21, 0.13)
const MOSS := Color(0.17, 0.21, 0.09)
## S8.3: [earth, cover] per table biome; grassland is today's dirt and moss.
const PALETTE := {"temperate_grassland": [DIRT, MOSS], "arid_desert": [Color(0.52, 0.42, 0.28), Color(0.62, 0.52, 0.36)],
	"frozen_tundra": [Color(0.45, 0.44, 0.42), Color(0.78, 0.80, 0.84)], "volcanic_ash": [Color(0.10, 0.10, 0.10), Color(0.22, 0.20, 0.19)],
	"urban_ruins": [Color(0.33, 0.31, 0.28), Color(0.45, 0.43, 0.40)], "alien_jungle": [Color(0.16, 0.12, 0.07), Color(0.10, 0.20, 0.06)]}

static var _textures := {}   # [footprint, biome] -> ImageTexture, shared by every piece of that size and biome
var _fp := Vector2.ZERO


func setup(footprint_inches: Vector2) -> GrasslandFootDressing:
	name = "FootDressing"
	_fp = footprint_inches
	texture_albedo = _texture(footprint_inches, GRASSLAND)
	size = Vector3(footprint_inches.x + 2.0 * MARGIN_INCHES, HEIGHT_INCHES,
		footprint_inches.y + 2.0 * MARGIN_INCHES) * 0.0254
	return self


func _ready() -> void:
	var table := get_tree().get_first_node_in_group("table")
	if table == null:
		return
	_show_for(str(table.get("biome")))
	table.biome_changed.connect(_show_for)
	var graphics := get_node_or_null("/root/GraphicsSettings")
	if graphics != null:   # Low / Performance keep the plain battlemap table (plan gate S6)
		graphics.settings_applied.connect(func(_preset: String) -> void: _show_for(str(table.get("biome"))))


func _show_for(biome: String) -> void:
	visible = PALETTE.has(biome) and GrasslandFootDressing.dressed_preset(self)
	if PALETTE.has(biome):
		texture_albedo = _texture(_fp, biome)


## The table is dressed on the current quality preset (TableBiomePresenter: Medium and up). Low and Performance keep
## the plain battlemap table for weak GPUs, so the wall-foot dressing and scatter stay off there. True outside the game.
static func dressed_preset(node: Node) -> bool:
	var graphics := node.get_node_or_null("/root/GraphicsSettings")
	return graphics == null or TableBiomePresenter.PRESET_DENSITY.has(int(graphics.current_preset))


## Opaque at the foot, an organic (noisy) edge fading out MARGIN_INCHES away, dirt and moss mixed; 8 px per inch.
## Fixed seed, so every client draws the same patch.
static func _texture(fp: Vector2, biome: String) -> ImageTexture:
	var key := [fp, biome]
	if _textures.has(key):
		return _textures[key]
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
			var c: Color = PALETTE[biome][0].lerp(PALETTE[biome][1], clampf(0.5 + noise.get_noise_2d(x * 2.0 + 50.0, z * 2.0), 0.0, 1.0))
			img.set_pixel(px, py, Color(c.r, c.g, c.b, a * a * 0.85))
	_textures[key] = ImageTexture.create_from_image(img)
	return _textures[key]
