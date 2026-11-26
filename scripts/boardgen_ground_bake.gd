class_name BoardgenGroundBake
extends RefCounted
## The ground a model's base shows on a generated board (ticket BASE-GROUND): the board's own surfaces drawn ONCE from straight above
## (orthographic, unshaded = albedo only) into a texture that the shared base-top material samples by world xz (Table.set_board_ground,
## shaders/base_board_ground.gdshaderinc). The top-most surface is what a base stands on: the street, the earth, a wall walk, a tier top.

const TEXEL_M := 0.0006   # 0.6 mm per texel: a 25 mm base gets ~40 texels across
const MAX_PX := 4096
const CAMERA_ABOVE_M := 3.0   # above the board's origin: over the tallest tower
const TOWN_FILL := 2.4   # = GRIT_FILL in shaders/ruintown_grit.gdshaderinc: the town's open ground glows faintly at night, so does a base on it


## The emission floor a base on this board gets: the town's grit fill when its grit map is on, else none. Pure.
static func fill_for(board_material: Material) -> float:
	var on: Variant = board_material.get_shader_parameter("grit_on") if board_material is ShaderMaterial else null
	return TOWN_FILL if on is float and on > 0.5 else 0.0


## The bake's size in pixels for `size_m` metres of board, aspect kept, the longer side capped at MAX_PX. Pure.
static func pixels(size_m: Vector2) -> Vector2i:
	var px := Vector2(ceilf(size_m.x / TEXEL_M - 0.001), ceilf(size_m.y / TEXEL_M - 0.001))   # (the epsilon: 1.2192 / 0.0006 is 2032.0000001 in floats)
	var scale := minf(1.0, float(MAX_PX) / maxf(maxf(px.x, px.y), 1.0))
	return Vector2i(maxi(1, int(px.x * scale)), maxi(1, int(px.y * scale)))


## Draws `surfaces` (the board's MultiMeshInstance3D: its multimesh and material, in a world of their own) from above over `rect` (world xz,
## metres) and returns the albedo with mipmaps. Null headless (the dummy renderer draws nothing) or without surfaces.
static func bake(host: Node, surfaces: GeometryInstance3D, rect: Rect2) -> ImageTexture:
	if DisplayServer.get_name() == "headless" or not surfaces is MultiMeshInstance3D or not rect.has_area() or not host.is_inside_tree():
		return null
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = pixels(rect.size)
	vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var copy := MultiMeshInstance3D.new()
	copy.multimesh = (surfaces as MultiMeshInstance3D).multimesh
	copy.material_override = surfaces.material_override
	copy.transform = surfaces.global_transform
	var cam := Camera3D.new()   # sized before it enters the tree: an orthographic camera resized later in a SubViewport keeps its old size
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = rect.size.y
	cam.near = 0.05
	cam.far = CAMERA_ABOVE_M * 2.0
	var centre := rect.get_center()
	cam.transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)), Vector3(centre.x, surfaces.global_position.y + CAMERA_ABOVE_M, centre.y))   # image up = world -z
	var env := Environment.new()   # no fog, glow or grade of the table: the plain albedo
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = env
	vp.add_child(copy)
	vp.add_child(cam)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(vp):   # the board left while it was drawn
		return null
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
