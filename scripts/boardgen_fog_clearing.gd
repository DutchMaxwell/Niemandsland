class_name BoardgenFogClearing
extends RefCounted
## The clearing that keeps a ground fog off the models, as its own piece: one R8 texel per CLEAR_TEXEL_IN of the board,
## 1 within CLEAR_IN of a shown model in MODEL_GROUP (a 1 in base and the ring the readability gate reads round it, out
## to 1.2 in), fading out by CLEAR_FADE_IN. No theme in here: any fog shader that samples `texture` over the board's
## extent (board inches, origin at the board centre) can use it - the ruin town's ground fog today, Tiefwerk's next.

const INCHES_TO_METERS := 0.0254
const MODEL_GROUP := "miniature"
const CLEAR_IN := 1.3
const CLEAR_FADE_IN := 1.7
const CLEAR_TEXEL_IN := 0.25

var image: Image = null
var texture: ImageTexture = null
var _board_in := Vector2.ONE
var _key := PackedVector2Array()


func _init(board_in: Vector2) -> void:
	_board_in = board_in
	var texels := Vector2i((board_in / CLEAR_TEXEL_IN).ceil())
	image = Image.create(texels.x, texels.y, false, Image.FORMAT_R8)
	texture = ImageTexture.create_from_image(image)


## Redraws the clearing round every shown model (board inches) when one has moved.
func update(board: Node3D, tree: SceneTree) -> void:
	var key := PackedVector2Array()
	for m: Node in tree.get_nodes_in_group(MODEL_GROUP):
		if m is Node3D and (m as Node3D).is_visible_in_tree():
			var p := board.to_local((m as Node3D).global_position) / INCHES_TO_METERS
			key.append(Vector2(p.x, p.z).snapped(Vector2.ONE * 0.05))
	if key == _key:
		return
	_key = key
	image.fill(Color.BLACK)
	var r := int(ceil(CLEAR_FADE_IN / CLEAR_TEXEL_IN))
	for p: Vector2 in key:
		var t := Vector2i(((p + _board_in * 0.5) / CLEAR_TEXEL_IN).floor())
		for x in range(t.x - r, t.x + r + 1):
			for z in range(t.y - r, t.y + r + 1):
				if x < 0 or z < 0 or x >= image.get_width() or z >= image.get_height():
					continue
				var d := (Vector2(x, z) + Vector2(0.5, 0.5)) * CLEAR_TEXEL_IN - _board_in * 0.5
				var k := 1.0 - smoothstep(CLEAR_IN, CLEAR_FADE_IN, d.distance_to(p))
				image.set_pixel(x, z, Color(maxf(k, image.get_pixel(x, z).r), 0, 0))
	texture.update(image)


## The clearing at a board point (inches): 1 on a model, 0 in the open.
func at(p_in: Vector2) -> float:
	var t := Vector2i(((p_in + _board_in * 0.5) / CLEAR_TEXEL_IN).floor())
	return image.get_pixel(t.x, t.y).r
