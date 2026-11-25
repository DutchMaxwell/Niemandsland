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

var _mat: ShaderMaterial = null
var _lamps := PackedVector3Array()


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
	var world := get_viewport().find_world_3d()
	var env: Environment = world.environment if world != null else null
	if env != null:
		var c := env.ambient_light_color * env.ambient_light_energy * AMBIENT_GAIN
		_mat.set_shader_parameter("fog_col", Color(c.r, c.g, c.b, 1.0))
