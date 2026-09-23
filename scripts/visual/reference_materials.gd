extends RefCounted
## Reference-only texture preparation. Custom shader samplers need mipmaps too;
## the project's default image import does not generate them for these assets.
static var _textures: Dictionary = {}
## The ground ground_height() mirrors (the ground shader's vertex relief). The reference look: the small-scale
## noise only, as accepted. The game table: no noise (props and miniatures stand at y = 0) but the mounds and ridges
## of drift_height(), so the dressing and the placed props sit on the surface the table shows.
static var noise_relief := true
const _MOUND_CELL := 0.1
static var _mound_cells: Dictionary = {}   # Vector2i cell -> [wall segments, sand piles] that reach into it


## Every reference build calls this before it places anything (grassland_reference.apply); mounds start empty.
static func set_tier(table: bool) -> void:
	noise_relief = not table
	_mound_cells.clear()


## Game table: the mounds the ground material draws — wall/container segments (a.xy, b.xy) and sand piles
## (xy + radius), the same lists and counts the shader loops over. Indexed by cell: the scatter asks per instance.
static func set_mounds(walls: PackedVector4Array, drifts: PackedVector4Array) -> void:
	_mound_cells.clear()
	for w in walls:
		_index_mound(Rect2(Vector2(minf(w.x, w.z), minf(w.y, w.w)), Vector2(absf(w.z - w.x), absf(w.w - w.y))).grow(0.030), w, 0)
	for d in drifts:
		_index_mound(Rect2(Vector2(d.x, d.y) - Vector2.ONE * d.z, Vector2.ONE * d.z * 2.0), d, 1)


static func _index_mound(area: Rect2, source: Vector4, kind: int) -> void:
	for x in range(floori(area.position.x / _MOUND_CELL), floori(area.end.x / _MOUND_CELL) + 1):
		for y in range(floori(area.position.y / _MOUND_CELL), floori(area.end.y / _MOUND_CELL) + 1):
			if not _mound_cells.has(Vector2i(x, y)):
				_mound_cells[Vector2i(x, y)] = [[], []]
			_mound_cells[Vector2i(x, y)][kind].append(source)


## Mirrors drift_height() in reference_ground.gdshaderinc. A source outside its cell's list adds exactly 0 there.
static func _mound_height(p: Vector2) -> float:
	var cell = _mound_cells.get(Vector2i(floori(p.x / _MOUND_CELL), floori(p.y / _MOUND_CELL)))
	if cell == null:
		return 0.0
	var h := 0.0
	for w: Vector4 in cell[0]:
		var m := 1.0 - smoothstep(0.0, 0.030, p.distance_to(Geometry2D.get_closest_point_to_segment(p, Vector2(w.x, w.y), Vector2(w.z, w.w))))
		h += m * m * 0.007
	for d: Vector4 in cell[1]:
		var r := maxf(d.z, 0.0001)
		var m := 1.0 - smoothstep(0.0, 1.0, p.distance_to(Vector2(d.x, d.y)) / r)
		h += m * m * r * 0.20
	return h


static func texture(path: String) -> Texture2D:
	var key := path
	if _textures.has(key):
		return _textures[key]
	var source: Texture2D = load(path)
	if source == null:
		return null
	var image := source.get_image()
	if image.is_compressed():
		image.decompress()
	image.generate_mipmaps()
	var result := ImageTexture.create_from_image(image)
	_textures[key] = result
	return result


## Mirrors surface_hash in reference_ground.gdshaderinc so scattered dressing can
## sit on the shader-displaced ground instead of the flat plane at y = 0.
static func _hash2(ix: int, iy: int) -> float:
	var qx := ix & 0xFFFFFFFF
	var qy := iy & 0xFFFFFFFF
	var h := ((qx * 16777619) ^ (qy * 1103515245)) & 0xFFFFFFFF
	h = (((h >> 16) ^ h) * 16777619) & 0xFFFFFFFF
	h = ((h >> 13) ^ h) & 0xFFFFFFFF
	return float(h & 0xFFFF) / 65535.0


static func _noise2(p: Vector2) -> float:
	var ix := int(floor(p.x))
	var iy := int(floor(p.y))
	var fx := p.x - float(ix)
	var fy := p.y - float(iy)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	return lerpf(lerpf(_hash2(ix, iy), _hash2(ix + 1, iy), fx),
		lerpf(_hash2(ix, iy + 1), _hash2(ix + 1, iy + 1), fx), fy)


## Same two octaves the ground shader uses for relief(). Keep the constants in
## sync with relief() in reference_ground.gdshader.
static func ground_height(p: Vector2) -> float:
	var noise := (_noise2(p * 2.6) - 0.5) * 0.008 + (_noise2(p * 7.5) - 0.5) * 0.003 if noise_relief else 0.0
	return noise + _mound_height(p)


## Shared with tundra_snow in reference_ground.gdshaderinc.
static func tundra_snow(p: Vector2) -> float:
	return smoothstep(0.40,0.53,_noise2(p * 5.2) * 0.60 + _noise2(p * 21.0) * 0.25 + _noise2(p * 67.0) * 0.15)


## Shared with jungle_growth in the ground shader; connects moss and live plants.
static func jungle_growth(p: Vector2) -> float:
	return smoothstep(0.28,0.60,_noise2(p*5.3)*0.65+_noise2(p*18.0)*0.35)
