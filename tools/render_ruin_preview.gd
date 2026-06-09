extends Node
## Dev tool: software-GL preview of a textured ruine_9x6 (9x6") on grassland ->
## renders/ruin_preview.png. Mirrors the in-game ruins wall material (lit, world-triplanar
## stone) so the look can be judged without a GPU session. Not shipped with the game.
##   xvfb-run -a godot --display-driver x11 --rendering-driver opengl3 \
##     --path . res://tools/render_ruin_runner.tscn

const OUT := "res://renders/ruin_preview.png"
const I := 0.0254  # inches -> metres
const WALL_TEX := "res://assets/terrain/props/ruins_wall.webp"
const GRASS_TEX := "res://assets/terrain/biomes/temperate_grassland.png"
const STONE_TILE_METERS := 0.085  # matches terrain_overlay.gd
const WALL_H := 2.5     # inches
const WALL_THICK := 0.25  # inches


func _ready() -> void:
	_run.call_deferred()


func _stone_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tex := load(WALL_TEX) as Texture2D
	if tex != null:
		mat.albedo_texture = tex
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	var tile_scale := 1.0 / STONE_TILE_METERS
	mat.uv1_scale = Vector3(tile_scale, tile_scale, tile_scale)
	mat.roughness = 0.95
	mat.metallic = 0.0
	return mat


func _wall(mat: StandardMaterial3D, length_in: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(length_in * I, WALL_H * I, WALL_THICK * I)
	mi.mesh = box
	mi.material_override = mat
	return mi


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 800)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.6, 0.75)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.ambient_light_energy = 1.0
	we.environment = env
	vp.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	vp.add_child(sun)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.55, 0.55)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	var gtex := load(GRASS_TEX) as Texture2D
	if gtex != null:
		gmat.albedo_texture = gtex
	gmat.roughness = 0.97
	ground.material_override = gmat
	vp.add_child(ground)

	var stone := _stone_material()
	# ruine_9x6 footprint: 9" (X) x 6" (Z); L-walls on the north (-Z) + west (-X) edges.
	var north := _wall(stone, 9.0)
	north.position = Vector3(0.0, WALL_H * I / 2.0, -3.0 * I)
	vp.add_child(north)
	var west := _wall(stone, 6.0)
	west.rotation.y = PI / 2.0
	west.position = Vector3(-4.5 * I, WALL_H * I / 2.0, 0.0)
	vp.add_child(west)
	var corner := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(WALL_THICK * I, WALL_H * I, WALL_THICK * I)
	corner.mesh = cbox
	corner.material_override = stone
	corner.position = Vector3(-4.5 * I, WALL_H * I / 2.0, -3.0 * I)
	vp.add_child(corner)

	var cam := Camera3D.new()
	cam.fov = 48.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.17, 0.13, 0.2), Vector3(-0.02, 0.015, -0.02), Vector3.UP)

	for _i in range(30):
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders"))
	var img := vp.get_texture().get_image()
	img.save_png(OUT)
	print("RUIN_RENDERED %dx%d" % [img.get_width(), img.get_height()])
	get_tree().quit()
