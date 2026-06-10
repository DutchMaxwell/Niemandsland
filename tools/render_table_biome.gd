extends Node
## Dev tool: GPU verification of the biome battlemap flow exactly as the game runs it —
## a real table.gd Table (BiomeLibrary + R2 cache + ground shader), set_biome() like the
## table-size dialog does, then a top-down screenshot per requested biome.
## Output: renders/table_biome_<key>.png.
##   godot --path . res://tools/render_table_biome_runner.tscn
## Not shipped with the game.

const BIOME_KEYS: Array[String] = ["volcanic_ash", "urban_ruins"]
const TABLE_FEET := Vector2(4.0, 4.0)
const APPLY_TIMEOUT_FRAMES := 1800  # ~30 s; covers a cold R2 download
const SETTLE_FRAMES := 20


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1400, 1000)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.72)
	env.ambient_light_energy = 1.0
	we.environment = env
	vp.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65.0, -30.0, 0.0)
	sun.light_energy = 1.2
	vp.add_child(sun)

	# A real Table, structured like scenes/main.tscn (TableMesh + TableCollision).
	var table := StaticBody3D.new()
	table.name = "Table"
	var mesh := MeshInstance3D.new()
	mesh.name = "TableMesh"
	table.add_child(mesh)
	var coll := CollisionShape3D.new()
	coll.name = "TableCollision"
	table.add_child(coll)
	table.set_script(load("res://scripts/table.gd"))
	vp.add_child(table)
	table.setup_table(TABLE_FEET)

	var cam := Camera3D.new()
	cam.fov = 50.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 1.6, 0.9), Vector3.ZERO, Vector3.UP)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders"))

	for key in BIOME_KEYS:
		# Wait until the battlemap actually replaced the previous surface (or time out).
		var prev: Texture2D = table._default_texture
		print("PRE %s: biome=%s cached='%s'" % [key, table.biome, table._biome_library.get_cached_path(key)])
		table.set_biome(key)
		print("POST %s: biome=%s changed_sync=%s" % [key, table.biome, table._default_texture != prev])
		var frames := 0
		while frames < APPLY_TIMEOUT_FRAMES and table._default_texture == prev:
			await get_tree().process_frame
			frames += 1
		print("BIOME %s applied after %d frames (tex=%s)" % [key, frames, table._default_texture])
		for _i in range(SETTLE_FRAMES):
			await get_tree().process_frame
		var img := vp.get_texture().get_image()
		var out := "res://renders/table_biome_%s.png" % key
		img.save_png(out)
		print("TABLE_BIOME_RENDERED %s -> %s" % [key, out])

	get_tree().quit()
