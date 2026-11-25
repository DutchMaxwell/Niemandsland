class_name BoardgenGroundFog
extends MeshInstance3D
## The ruin town's ground fog: ONE transparent plane of board size at the fog's top
## (shaders/ruintown_groundfog.gdshader integrates the layer below it along every
## view ray), up to MAX_LAMPS lamp pools glowing in it. VISUAL ONLY: no collider,
## no shadow, nothing the rules or the sight lines read. Its colour follows the
## scene's ambient light every frame, so one rule serves every mood.

const INCHES_TO_METERS := 0.0254
const SHADER := preload("res://shaders/ruintown_groundfog.gdshader")
const MAX_LAMPS := 12
const GROUND_IN := 0.04  # the street's top over the board's origin
const TOP_M := 0.014  # the fog's mean top over the ground (the shader's top_m)
const WAVER_M := 0.005  # how far the top wavers: the plane lies at the highest top
## fog colour = ambient colour x ambient energy x this (Night with the sky fill:
## about (0.10, 0.13, 0.23); the town's dusk: about (0.19, 0.21, 0.26)).
const AMBIENT_GAIN := 0.27
const NOISE_SEED := 7
## The veil stays off the models: no fog within CLEAR_IN of a shown model in the group
## MODEL_GROUP (a 1 in base and the ring the readability gate reads round it, out to
## 1.2 in), fading out by CLEAR_FADE_IN.
const MODEL_GROUP := "miniature"
const CLEAR_IN := 1.3
const CLEAR_FADE_IN := 1.7
const CLEAR_TEXEL_IN := 0.25

var _mat: ShaderMaterial = null
var _lamps := PackedVector3Array()
var _board_in := Vector2.ONE
var _clear: Image = null
var _clear_tex: ImageTexture = null
var _clear_key := PackedVector2Array()


func build(layout: Dictionary) -> void:
	var plane := PlaneMesh.new()
	var board_in := Vector2(layout["nx"], layout["nz"]) * float(layout["cell_in"])
	plane.size = board_in * INCHES_TO_METERS
	mesh = plane
	position = Vector3(0.0, GROUND_IN * INCHES_TO_METERS + TOP_M + WAVER_M, 0.0)
	var fn := FastNoiseLite.new()
	fn.seed = NOISE_SEED
	fn.frequency = 0.02
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	# Made at once from an image: a NoiseTexture2D fills itself on a thread and its
	# first frames are the known pink-table race.
	var img := fn.get_seamless_image(256, 256)
	_mat.set_shader_parameter("noise_tex", ImageTexture.create_from_image(img))
	_board_in = board_in
	var texels := Vector2i((board_in / CLEAR_TEXEL_IN).ceil())
	_clear = Image.create(texels.x, texels.y, false, Image.FORMAT_R8)
	_clear_tex = ImageTexture.create_from_image(_clear)
	_mat.set_shader_parameter("clear_tex", _clear_tex)
	_mat.set_shader_parameter("board_size", board_in * INCHES_TO_METERS)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The lamps whose pools glow in the fog (the first MAX_LAMPS), in the board's own space
## (the fog's parent): the board may be built before it stands on the table.
func set_lamps(points: PackedVector3Array) -> void:
	_lamps = points.slice(0, MAX_LAMPS)
	_mat.set_shader_parameter("lamp_n", _lamps.size())


func lamp_count() -> int:
	return int(_mat.get_shader_parameter("lamp_n")) if _mat != null else 0


func noise() -> Texture2D:
	return _mat.get_shader_parameter("noise_tex") if _mat != null else null


func _process(_delta: float) -> void:
	if _mat == null or not is_inside_tree():
		return
	_mat.set_shader_parameter("ground_y", global_position.y - TOP_M - WAVER_M)
	var board := get_parent_node_3d()
	var world_lamps := PackedVector3Array()
	world_lamps.resize(MAX_LAMPS)
	for i in _lamps.size():
		world_lamps[i] = board.global_transform * _lamps[i] if board != null else _lamps[i]
	_mat.set_shader_parameter("lamps", world_lamps)
	if board != null:
		var c := board.global_position
		_mat.set_shader_parameter("board_center", Vector2(c.x, c.z))
		update_clearing(board)
	var world := get_viewport().find_world_3d()
	var env: Environment = world.environment if world != null else null
	if env != null:
		var c := env.ambient_light_color * env.ambient_light_energy * AMBIENT_GAIN
		_mat.set_shader_parameter("fog_col", Color(c.r, c.g, c.b, 1.0))


## Redraws the clearing round every shown model (board inches) when one has moved.
func update_clearing(board: Node3D) -> void:
	var key := PackedVector2Array()
	for m: Node in get_tree().get_nodes_in_group(MODEL_GROUP):
		if m is Node3D and (m as Node3D).is_visible_in_tree():
			var p := board.to_local((m as Node3D).global_position) / INCHES_TO_METERS
			key.append(Vector2(p.x, p.z).snapped(Vector2.ONE * 0.05))
	if key == _clear_key:
		return
	_clear_key = key
	_clear.fill(Color.BLACK)
	var r := int(ceil(CLEAR_FADE_IN / CLEAR_TEXEL_IN))
	for p: Vector2 in key:
		var t := Vector2i(((p + _board_in * 0.5) / CLEAR_TEXEL_IN).floor())
		for x in range(t.x - r, t.x + r + 1):
			for z in range(t.y - r, t.y + r + 1):
				if x < 0 or z < 0 or x >= _clear.get_width() or z >= _clear.get_height():
					continue
				var d := (Vector2(x, z) + Vector2(0.5, 0.5)) * CLEAR_TEXEL_IN - _board_in * 0.5
				var k := 1.0 - smoothstep(CLEAR_IN, CLEAR_FADE_IN, d.distance_to(p))
				_clear.set_pixel(x, z, Color(maxf(k, _clear.get_pixel(x, z).r), 0, 0))
	_clear_tex.update(_clear)


func clearing_at(p_in: Vector2) -> float:
	var t := Vector2i(((p_in + _board_in * 0.5) / CLEAR_TEXEL_IN).floor())
	return _clear.get_pixel(t.x, t.y).r if _clear != null else 0.0
