extends RefCounted
## Reference-only texture preparation. Custom shader samplers need mipmaps too;
## the project's default image import does not generate them for these assets.
static var _textures: Dictionary = {}


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
	return (_noise2(p * 2.6) - 0.5) * 0.008 + (_noise2(p * 7.5) - 0.5) * 0.003
