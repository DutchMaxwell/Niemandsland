extends Node
## Dev tool: GPU verification of the in-game ruin shell walls. Exercises the REAL
## renderer path — terrain_overlay.gd builds the walls, RuinsLibrary fetches the masonry
## panels from R2 (or finds them cached), and the triplanar fallback upgrades to shells
## in place — for an unrotated 9x9" ruin, an unrotated 9x6" and a 90°-rotated 9x6", so
## the crumble taper direction can be eyeballed (HANDOFF_RUIN_WALLS.md §6 gotcha #1).
## Output: renders/overlay_ruins_ingame.png + renders/overlay_ruins_closeup.png.
##   godot --path . res://tools/render_overlay_ruins_runner.tscn
## Not shipped with the game.

const OUT_OVERVIEW := "res://renders/overlay_ruins_ingame.png"
const OUT_CLOSEUP := "res://renders/overlay_ruins_closeup.png"
const TABLE_FEET := Vector2(4.0, 4.0)
const FETCH_TIMEOUT_FRAMES := 1800  # ~30 s; R2 set is ~2 MB
const SETTLE_FRAMES := 30


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1700, 1000)
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
	pm.size = Vector2(1.4, 1.4)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.32, 0.42, 0.24)
	gmat.roughness = 0.97
	ground.material_override = gmat
	vp.add_child(ground)

	var overlay: Node3D = load("res://scripts/terrain_overlay.gd").new()
	vp.add_child(overlay)

	# Grassland grass field under everything (one MultiMesh draw call).
	var grass := GrassField.new()
	grass.set_table_size(Vector2(1.22, 1.22))
	grass.set_biome("temperate_grassland")
	vp.add_child(grass)

	# Three ruins on a 4x4 ft table grid (24x24 cells, centre 12): plain 3x3, plain 3x2,
	# and a 90°-rotated 3x2 so the transformed taper_dir is visually checked too.
	var segments: Array = []
	segments.append_array(TerrainPrefabs.wall_segments_for("ruine_9x9", Vector2i(7, 10)))
	segments.append_array(TerrainPrefabs.wall_segments_for("ruine_9x6", Vector2i(13, 10)))
	segments.append_array(TerrainPrefabs.wall_segments_for("ruine_9x6", Vector2i(10, 14), 1))
	# One free-standing wall whose deterministic pick is the gothic window, so the
	# window reveal can be eyeballed every run. Scan cells south of the ruins (still on
	# the 24x24 grid) until the seeded pick lands on "window".
	var window_cell := Vector2i(-1, -1)
	for y in range(18, 20):  # rows south of the ruins, still inside the 4x4 ft table
		for x in range(4, 20):
			var probe := {"edge_cell": Vector2i(x, y), "edge_side": 0, "role": "full",
					"wall_key": "window_probe", "length_inches": 3.0, "sub_position": 0}
			if overlay._panel_for_segment(probe) == "window":
				segments.append(probe)
				window_cell = Vector2i(x, y)
				break
		if window_cell.x >= 0:
			break
	overlay.update_wall_models(segments, TABLE_FEET, 0.0)

	# A forest + two blockers, so the textured trees (variants, sizes, margins) and the
	# shipping containers (both colourways, rotation) can be eyeballed with the ruins.
	var objects: Array = []
	objects.append_array(TerrainPrefabs.decoration_for("wald_9x9", Vector2i(16, 12)))
	objects.append_array(TerrainPrefabs.decoration_for("blocker_6x3", Vector2i(5, 17)))
	var rotated_blocker := TerrainPrefabs.decoration_for("blocker_6x3", Vector2i(8, 16), null, 90)
	objects.append_array(rotated_blocker)
	# A minefield (15 anti-tank mines + 2 warning signs) west of the ruins.
	objects.append_array(TerrainPrefabs.decoration_for("dangerous_9x6", Vector2i(4, 5)))
	overlay.update_placed_objects(objects, TABLE_FEET, 0.0)

	# Wait for the R2 fetches + the in-place upgrades (real production flow), including
	# the volumetric tree GLBs (the slowest tier of the progressive enhancement).
	var frames := 0
	while (not overlay._ruin_panels_ready() or not overlay._tree_panels_ready()
			or not overlay._tree_models_ready() or not overlay._container_panels_ready()
			or not overlay._hazard_panels_ready()) and frames < FETCH_TIMEOUT_FRAMES:
		await get_tree().process_frame
		frames += 1
	print("PANELS_READY=%s TREES_READY=%s TREE_MODELS_READY=%s CONTAINERS_READY=%s HAZARDS_READY=%s after %d frames" % [
			overlay._ruin_panels_ready(), overlay._tree_panels_ready(),
			overlay._tree_models_ready(), overlay._container_panels_ready(),
			overlay._hazard_panels_ready(), frames])
	for _i in range(SETTLE_FRAMES):
		await get_tree().process_frame

	var cam := Camera3D.new()
	cam.fov = 45.0
	vp.add_child(cam)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders"))

	# Ruins sit around cells 7..16 -> local x/z roughly -0.38..+0.34 m.
	cam.look_at_from_position(Vector3(0.05, 0.42, 0.62), Vector3(-0.02, 0.0, -0.05), Vector3.UP)
	await _snap(vp, OUT_OVERVIEW)

	cam.look_at_from_position(Vector3(-0.05, 0.16, 0.42), Vector3(-0.12, 0.02, 0.12), Vector3.UP)
	await _snap(vp, OUT_CLOSEUP)

	# Per-ruin orbit shots (centre, label) from two opposite high angles each, so every
	# arm's taper direction and both shell faces can be eyeballed.
	var ruins := [
		[Vector3(-0.27, 0.02, -0.04), "9x9"],
		[Vector3(0.19, 0.02, -0.08), "9x6"],
		[Vector3(-0.08, 0.02, 0.27), "9x6rot"],
	]
	for ruin in ruins:
		var center: Vector3 = ruin[0]
		var label: String = ruin[1]
		cam.look_at_from_position(center + Vector3(0.22, 0.18, 0.26), center, Vector3.UP)
		await _snap(vp, "res://renders/overlay_ruin_%s_se.png" % label)
		cam.look_at_from_position(center + Vector3(-0.22, 0.18, -0.26), center, Vector3.UP)
		await _snap(vp, "res://renders/overlay_ruin_%s_nw.png" % label)

	if window_cell.x >= 0:
		var cell_m := 3.0 * 0.0254
		var wall_pos := Vector3((window_cell.x - 12 + 0.5) * cell_m, 0.03,
				(window_cell.y - 12 + 0.5) * cell_m - cell_m / 2.0)
		cam.look_at_from_position(wall_pos + Vector3(0.06, 0.07, 0.16), wall_pos, Vector3.UP)
		await _snap(vp, "res://renders/overlay_ruin_window.png")

	# Forest at cells (16,12)-(18,14): centre of the 9x9" area in local metres.
	var forest_center := Vector3((17.0 - 12 + 0.5) * 3.0 * 0.0254, 0.03, (13.0 - 12 + 0.5) * 3.0 * 0.0254)
	cam.look_at_from_position(forest_center + Vector3(0.16, 0.14, 0.24), forest_center, Vector3.UP)
	await _snap(vp, "res://renders/overlay_forest_se.png")
	cam.look_at_from_position(forest_center + Vector3(0.02, 0.32, 0.04), forest_center, Vector3.UP)
	await _snap(vp, "res://renders/overlay_forest_top.png")

	# Blockers at cells (5,17) + rotated at (8,16) — both in one shot from the NE.
	var blocker_center := Vector3((6.8 - 12) * 3.0 * 0.0254, 0.0, (17.2 - 12) * 3.0 * 0.0254)
	cam.look_at_from_position(blocker_center + Vector3(0.30, 0.22, -0.18), blocker_center, Vector3.UP)
	await _snap(vp, "res://renders/overlay_containers.png")

	# Minefield at cells (4,5)-(6,6): low closeup + top-down.
	var mines_center := Vector3((5.0 - 12 + 0.5) * 3.0 * 0.0254, 0.0, (5.5 - 12 + 0.5) * 3.0 * 0.0254)
	cam.look_at_from_position(mines_center + Vector3(0.1, 0.08, 0.18), mines_center, Vector3.UP)
	await _snap(vp, "res://renders/overlay_minefield.png")
	cam.look_at_from_position(mines_center + Vector3(0.01, 0.3, 0.02), mines_center, Vector3.UP)
	await _snap(vp, "res://renders/overlay_minefield_top.png")

	# Desert theme pass: switch the biome, wait for the adobe/cacti set, re-shoot.
	overlay.set_biome("arid_desert")
	frames = 0
	while (not overlay._ruin_panels_ready() or not overlay._tree_panels_ready()
			or not overlay._tree_models_ready()) and frames < FETCH_TIMEOUT_FRAMES:
		await get_tree().process_frame
		frames += 1
	print("DESERT_READY=%s/%s/%s after %d frames" % [overlay._ruin_panels_ready(),
			overlay._tree_panels_ready(), overlay._tree_models_ready(), frames])
	for _i in range(SETTLE_FRAMES):
		await get_tree().process_frame

	var ruin_a: Vector3 = ruins[0][0]
	cam.look_at_from_position(ruin_a + Vector3(0.22, 0.18, 0.26), ruin_a, Vector3.UP)
	await _snap(vp, "res://renders/overlay_desert_ruin.png")
	cam.look_at_from_position(forest_center + Vector3(0.16, 0.14, 0.24), forest_center, Vector3.UP)
	await _snap(vp, "res://renders/overlay_desert_cacti.png")
	cam.look_at_from_position(Vector3(0.05, 0.42, 0.62), Vector3(-0.02, 0.0, -0.05), Vector3.UP)
	await _snap(vp, "res://renders/overlay_desert_overview.png")

	# Tundra theme pass: snowed stone, snow-laden conifers, snowed containers.
	overlay.set_biome("frozen_tundra")
	frames = 0
	while (not overlay._ruin_panels_ready() or not overlay._tree_panels_ready()
			or not overlay._tree_models_ready() or not overlay._container_panels_ready()) \
			and frames < FETCH_TIMEOUT_FRAMES:
		await get_tree().process_frame
		frames += 1
	print("TUNDRA_READY=%s/%s/%s/%s after %d frames" % [overlay._ruin_panels_ready(),
			overlay._tree_panels_ready(), overlay._tree_models_ready(),
			overlay._container_panels_ready(), frames])
	for _i in range(SETTLE_FRAMES):
		await get_tree().process_frame

	cam.look_at_from_position(ruin_a + Vector3(0.22, 0.18, 0.26), ruin_a, Vector3.UP)
	await _snap(vp, "res://renders/overlay_tundra_ruin.png")
	cam.look_at_from_position(forest_center + Vector3(0.16, 0.14, 0.24), forest_center, Vector3.UP)
	await _snap(vp, "res://renders/overlay_tundra_trees.png")
	cam.look_at_from_position(blocker_center + Vector3(0.30, 0.22, -0.18), blocker_center, Vector3.UP)
	await _snap(vp, "res://renders/overlay_tundra_containers.png")
	cam.look_at_from_position(Vector3(0.05, 0.42, 0.62), Vector3(-0.02, 0.0, -0.05), Vector3.UP)
	await _snap(vp, "res://renders/overlay_tundra_overview.png")

	get_tree().quit()


func _snap(vp: SubViewport, path: String) -> void:
	for _i in range(10):
		await get_tree().process_frame
	var img := vp.get_texture().get_image()
	img.save_png(path)
	print("OVERLAY_RUINS_RENDERED %dx%d -> %s" % [img.get_width(), img.get_height(), path])
