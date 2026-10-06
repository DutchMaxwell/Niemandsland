class_name GrasslandFootScatter
extends Node3D
## Stones and grass at the foot of a free ruin or solid (S6-2, maintainer 05.10.: the ruins must belong to the
## picture): a stone and a grass MultiMesh in a ring up to 2.5" outside the footprint, the grass also reaching a little
## under the walls. A child of the piece, so it moves, turns and goes with it. Decoration only (no collision, rules
## untouched). Uses the grassland dressing's own tuft and stone meshes. S8.3: coloured per table biome (PALETTE) and
## following biome changes, hidden on a biome without a palette and below Medium; without a table it stays visible.

const RING_INCHES := 2.5
const GRASSLAND := "temperate_grassland"
const UNDERSTORY := preload("res://scripts/visual/reference_understory.gd")

## S8.3 (maintainer 06.10.: the terrain should match the biome): sRGB [from, to] per layer and table biome. Grassland
## is today's look; desert, tundra and volcanic come from the reference understory (pebbles, stones and stalks,
## cinders). A biome without "grass" gets no tufts.
const PALETTE := {
	"temperate_grassland": {"stone": [Color(0.36, 0.34, 0.28), Color(0.65, 0.61, 0.50)], "grass": [Color(0.22, 0.28, 0.07), Color(0.51, 0.46, 0.24)]},
	"arid_desert": {"stone": [Color(0.42, 0.36, 0.27), Color(0.74, 0.67, 0.53)], "grass": [Color(0.45, 0.38, 0.20), Color(0.66, 0.56, 0.34)]},
	"frozen_tundra": {"stone": [Color(0.29, 0.31, 0.33), Color(0.61, 0.63, 0.65)], "grass": [Color(0.38, 0.34, 0.25), Color(0.65, 0.60, 0.46)]},
	"volcanic_ash": {"stone": [Color(0.12, 0.13, 0.15), Color(0.40, 0.38, 0.35)]},
	"urban_ruins": {"stone": [Color(0.38, 0.37, 0.35), Color(0.62, 0.60, 0.56)], "grass": [Color(0.25, 0.30, 0.12), Color(0.45, 0.42, 0.25)]},
	"alien_jungle": {"stone": [Color(0.25, 0.27, 0.20), Color(0.45, 0.47, 0.36)], "grass": [Color(0.10, 0.30, 0.08), Color(0.25, 0.50, 0.15)]},
}

var colours := {}   # layer -> the sRGB colours written for the current biome (headless cannot read a MultiMesh back)
var _t := {}   # layer -> each instance's place between the palette's two colours
var _layers := {}   # layer -> MultiMeshInstance3D
static var _meshes := {}   # "stone" / "grass" -> Mesh, built once from the grassland dressing's builders


func setup(footprint_inches: Vector2, is_ruin: bool) -> GrasslandFootScatter:
	name = "FootScatter"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([footprint_inches, is_ruin])   # same scatter on every client
	_add_layer("stone", 50 if is_ruin else 22, footprint_inches, rng, 0.0)
	_add_layer("grass", 40 if is_ruin else 24, footprint_inches, rng, -0.3)
	_paint(GRASSLAND)
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
		_paint(biome)


func _paint(biome: String) -> void:
	for kind: String in _layers:
		var pair: Array = PALETTE[biome].get(kind, [])
		_layers[kind].visible = not pair.is_empty()
		colours[kind] = []
		if pair.is_empty():
			continue
		for i in _t[kind].size():
			var c: Color = pair[0].lerp(pair[1], _t[kind][i])
			colours[kind].append(c)
			_layers[kind].multimesh.set_instance_color(i, c.srgb_to_linear())


func _add_layer(kind: String, count: int, fp: Vector2, rng: RandomNumberGenerator, min_out: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _mesh(kind)
	mm.instance_count = count
	_t[kind] = PackedFloat32Array()
	for i in count:
		var p := _ring_point(fp, rng, min_out) * 0.0254
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		if kind == "stone":
			var s := rng.randf_range(0.0015, 0.0045)
			basis = basis.scaled(Vector3(s * rng.randf_range(0.8, 1.5), s * rng.randf_range(0.45, 0.8), s))
			_t[kind].append(rng.randf())   # same draw order as before: the transforms stay where they were
		else:
			basis = basis.scaled(Vector3.ONE * rng.randf_range(0.9, 1.6))
			_t[kind].append(rng.randf())
		mm.set_instance_transform(i, Transform3D(basis, Vector3(p.x, 0.0, p.y)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	_layers[kind] = mmi


## A point (inches, piece-local x/z) min_out..RING_INCHES outside the footprint edge, biased towards the edge.
static func _ring_point(fp: Vector2, rng: RandomNumberGenerator, min_out: float) -> Vector2:
	var d := min_out + (RING_INCHES - min_out) * pow(rng.randf(), 2.0)
	var t := rng.randf() * (fp.x + fp.y) * 2.0
	var hx := fp.x * 0.5
	var hz := fp.y * 0.5
	if t < fp.x:
		return Vector2(-hx + t, -hz - d)
	if t < 2.0 * fp.x:
		return Vector2(-hx + t - fp.x, hz + d)
	if t < 2.0 * fp.x + fp.y:
		return Vector2(-hx - d, -hz + t - 2.0 * fp.x)
	return Vector2(hx + d, -hz + t - 2.0 * fp.x - fp.y)


static func _mesh(kind: String) -> Mesh:
	if not _meshes.has(kind):
		var builder: Node3D = UNDERSTORY.new()
		_meshes[kind] = builder._stone_mesh() if kind == "stone" else builder._tuft_mesh()
		builder.free()
	return _meshes[kind]
