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
