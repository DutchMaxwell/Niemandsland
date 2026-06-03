extends Node
## Dev tool: GPU preview of the 3D table Environment (sky / fog / lighting) ->
## renders/scene_preview.png — for the AAA 3D overhaul, so the look can be checked without a
## full in-game session. It pulls the WorldEnvironment + the two lights out of main.tscn
## (instantiate() does NOT run Main._ready since Main is never added to the tree), then
## replicates the runtime LightingController "Default" preset, and drops them over a ground
## plane + a few stand-in minis + a 3/4 camera. Run on a real GPU (software-GL won't show
## SDFGI/SSR/volumetric fog faithfully):
##   flatpak run --filesystem=home org.godotengine.Godot --path . tools/render_scene_runner.tscn
## Not shipped with the game.

const OUT := "res://renders/scene_preview.png"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(vp)

	# Pull the Environment + lights + the real Table out of main.tscn without running
	# Main._ready() (instantiate() does not run _ready; only tree-entry does).
	var main: Node = load("res://scenes/main.tscn").instantiate()
	var world_env := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := main.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	var fill := main.get_node_or_null("FillLight") as DirectionalLight3D
	var table := main.get_node_or_null("Table")
	if world_env:
		main.remove_child(world_env)
		vp.add_child(world_env)
	if sun:
		main.remove_child(sun)
		vp.add_child(sun)
	if fill:
		main.remove_child(fill)
		vp.add_child(fill)
	if table:
		main.remove_child(table)
		vp.add_child(table)  # Table._ready runs here -> loads the mat texture
		table.setup_table(Vector2(4, 4))  # real ground material (Phase 2)
	main.free()

	# Replicate the runtime lighting (LightingController "Default" overrides ambient/exposure/
	# glow/sun angle at startup).
	if world_env and sun:
		var lc: Node = load("res://scripts/lighting_controller.gd").new()
		add_child(lc)
		lc.initialize(sun, world_env, fill)
		lc.apply_preset("Default")

	# Stand-in minis for scale / contrast (a small cluster near the centre so they read).
	# Two get "selected" (green emissive overlay + a real green SelectionSpillLight) so
	# the spill onto the ground + the neighbouring unlit minis can be judged (Phase 3 v2).
	var cells := [Vector2(-0.18, -0.1), Vector2(-0.06, 0.04), Vector2(0.06, -0.04), Vector2(0.18, 0.1)]
	var selected := {1: true}
	for i in range(cells.size()):
		var cell: Vector2 = cells[i]
		var m := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.013  # ~26 mm — realistic mini footprint
		cap.height = 0.032  # ~32 mm tall, so the light sits inside it, not above
		m.mesh = cap
		m.position = Vector3(cell.x, 0.016, cell.y)
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.5, 0.32, 0.26)
		mm.roughness = 0.7
		m.material_override = mm
		vp.add_child(m)
		if selected.has(i):
			# Green emissive overlay (mimics _get_selection_glow_material).
			var ov := StandardMaterial3D.new()
			ov.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ov.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ov.albedo_color = Color(0.25, 1.0, 0.4, 0.4)
			ov.emission_enabled = true
			ov.emission = SelectionSpillLight.GREEN_SELECTION
			ov.emission_energy_multiplier = 2.0
			m.material_overlay = ov
			# Spill light at ground level under the mini (in-game it parents to the
			# ground-origin wrapper; these stand-ins are centred, so place it directly).
			var light := SelectionSpillLight.new()
			vp.add_child(light)
			light.setup(0.02)
			light.position = Vector3(cell.x, SelectionSpillLight.Y_OFFSET, cell.y)

	# Drifting volumetric mist (Phase 4) — renders because the Environment has
	# volumetric fog enabled at the baseline.
	var mist := Node3D.new()
	mist.set_script(load("res://scripts/atmospheric_clouds.gd"))
	vp.add_child(mist)

	# 3/4 tabletop camera — steep enough that the surface fills the frame with a strip of sky.
	var cam := Camera3D.new()
	cam.fov = 50.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 0.22, 0.42), Vector3(0.0, 0.0, -0.1), Vector3.UP)

	for _i in range(60):
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders"))
	var img := vp.get_texture().get_image()
	img.save_png(OUT)
	print("SCENE_RENDERED %dx%d" % [img.get_width(), img.get_height()])
	get_tree().quit()
