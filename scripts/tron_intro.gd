extends Node3D
class_name TronIntro
## Tron-style intro with individual lines drawn one by one
## Each line is animated from start to end with a visible laser cursor

signal intro_finished
signal intro_skipped

## Animation timing
const GRID_LINE_DRAW_TIME: float = 0.08   # Time to draw one grid line
const TABLE_LINE_DRAW_TIME: float = 0.15  # Time to draw one table edge
const CURSOR_SIZE: float = 0.04
const LINE_WIDTH: float = 0.008

## Colors
const CYAN = Color(0.0, 1.0, 1.0)
const WHITE = Color(1.0, 1.0, 1.0)
const DARK_BG = Color(0.0, 0.01, 0.04)

## Grid configuration
const GRID_EXTENT: float = 8.0  # How far grid extends
const GRID_SPACING: float = 0.5

## References
var main_scene: Node3D
var world_environment: WorldEnvironment
var table: Node3D
var original_camera_pivot: Node3D

## Intro elements
var lines_container: Node3D
var cursor_mesh: MeshInstance3D
var intro_camera: Camera3D
var intro_camera_pivot: Node3D
var canvas_layer: CanvasLayer
var black_overlay: ColorRect
var skip_label: Label

## Line drawing state
var _lines_to_draw: Array = []  # Array of {start: Vector3, end: Vector3, color: Color}
var _current_line_index: int = 0
var _current_line_progress: float = 0.0
var _current_line_mesh: MeshInstance3D = null
var _phase: int = 0  # 0=blackout, 1=grid, 2=table, 3=materialize, 4=done

## Original values
var _original_glow_intensity: float = 1.0
var _original_glow_bloom: float = 0.3

## State
var _is_playing: bool = false
var _total_time: float = 0.0
var _phase_start_time: float = 0.0


func _input(event: InputEvent) -> void:
	if not _is_playing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_skip_intro()
	elif event is InputEventMouseButton and event.pressed:
		_skip_intro()


func _process(delta: float) -> void:
	if not _is_playing:
		return

	_total_time += delta

	match _phase:
		0:
			_update_blackout(delta)
		1:
			_update_line_drawing(delta, GRID_LINE_DRAW_TIME)
		2:
			_update_line_drawing(delta, TABLE_LINE_DRAW_TIME)
		3:
			_update_materialize(delta)
		4:
			_finish_intro()

	_update_camera()


## Start the intro
func play_intro(main: Node3D) -> void:
	main_scene = main
	world_environment = main.get_node("WorldEnvironment")
	table = main.get_node("Table")
	original_camera_pivot = main.get_node("CameraPivot")

	# Store original settings
	if world_environment and world_environment.environment:
		_original_glow_intensity = world_environment.environment.glow_intensity
		_original_glow_bloom = world_environment.environment.glow_bloom

	_is_playing = true
	_phase = 0
	_total_time = 0.0
	_phase_start_time = 0.0

	_hide_main_scene()
	_setup_environment()
	_create_intro_elements()
	_setup_camera()
	_generate_grid_lines()


func _hide_main_scene() -> void:
	if table:
		table.visible = false
	if original_camera_pivot:
		var cam = original_camera_pivot.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.current = false


func _show_main_scene() -> void:
	if table:
		table.visible = true
	if world_environment and world_environment.environment:
		world_environment.environment.background_mode = Environment.BG_SKY
		world_environment.environment.glow_intensity = _original_glow_intensity
		world_environment.environment.glow_bloom = _original_glow_bloom
	if original_camera_pivot:
		var cam = original_camera_pivot.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.current = true


func _setup_environment() -> void:
	if world_environment and world_environment.environment:
		var env = world_environment.environment
		env.background_mode = Environment.BG_COLOR
		env.background_color = DARK_BG
		env.glow_intensity = 0.6
		env.glow_bloom = 0.05


func _setup_camera() -> void:
	intro_camera_pivot = Node3D.new()
	intro_camera_pivot.name = "IntroCameraPivot"
	add_child(intro_camera_pivot)

	intro_camera = Camera3D.new()
	intro_camera.name = "IntroCamera"
	intro_camera.fov = 45.0
	intro_camera.near = 0.01
	intro_camera.far = 100.0
	intro_camera_pivot.add_child(intro_camera)

	# Start: very low angle, looking across grid
	intro_camera_pivot.position = Vector3(0, 0.15, 6)
	intro_camera_pivot.rotation_degrees = Vector3(-3, 0, 0)
	intro_camera.current = true


func _update_camera() -> void:
	if not intro_camera_pivot:
		return

	# Camera rises during the animation
	var total_anim_time = 6.0
	var progress = clampf(_total_time / total_anim_time, 0.0, 1.0)
	var eased = progress * progress * (3.0 - 2.0 * progress)

	var start_pos = Vector3(0, 0.15, 6)
	var end_pos = Vector3(0, 5, 5)
	var start_rot = Vector3(-3, 0, 0)
	var end_rot = Vector3(-45, 0, 0)

	intro_camera_pivot.position = start_pos.lerp(end_pos, eased)
	intro_camera_pivot.rotation_degrees = start_rot.lerp(end_rot, eased)


func _create_intro_elements() -> void:
	# Container for all lines
	lines_container = Node3D.new()
	lines_container.name = "LinesContainer"
	add_child(lines_container)

	# Laser cursor (bright glowing sphere)
	cursor_mesh = MeshInstance3D.new()
	cursor_mesh.name = "LaserCursor"
	var sphere = SphereMesh.new()
	sphere.radius = CURSOR_SIZE
	sphere.height = CURSOR_SIZE * 2
	sphere.radial_segments = 16
	sphere.rings = 8
	cursor_mesh.mesh = sphere

	var cursor_mat = StandardMaterial3D.new()
	cursor_mat.albedo_color = WHITE
	cursor_mat.emission_enabled = true
	cursor_mat.emission = WHITE
	cursor_mat.emission_energy_multiplier = 8.0
	cursor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cursor_mesh.material_override = cursor_mat
	cursor_mesh.visible = false
	add_child(cursor_mesh)

	# UI overlay
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100
	add_child(canvas_layer)

	black_overlay = ColorRect.new()
	black_overlay.color = Color.BLACK
	black_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(black_overlay)

	skip_label = Label.new()
	skip_label.text = "Press any key to skip"
	skip_label.add_theme_color_override("font_color", CYAN.darkened(0.4))
	skip_label.add_theme_font_size_override("font_size", 14)
	skip_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip_label.offset_left = -180
	skip_label.offset_top = -30
	skip_label.modulate.a = 0.0
	canvas_layer.add_child(skip_label)


## Generate grid lines radiating from center
func _generate_grid_lines() -> void:
	_lines_to_draw.clear()

	# Generate X lines (parallel to X axis)
	for z in range(-int(GRID_EXTENT / GRID_SPACING), int(GRID_EXTENT / GRID_SPACING) + 1):
		var z_pos = z * GRID_SPACING
		# Draw from center outward in both directions
		_lines_to_draw.append({
			"start": Vector3(0, 0, z_pos),
			"end": Vector3(-GRID_EXTENT, 0, z_pos),
			"color": CYAN
		})
		_lines_to_draw.append({
			"start": Vector3(0, 0, z_pos),
			"end": Vector3(GRID_EXTENT, 0, z_pos),
			"color": CYAN
		})

	# Generate Z lines (parallel to Z axis)
	for x in range(-int(GRID_EXTENT / GRID_SPACING), int(GRID_EXTENT / GRID_SPACING) + 1):
		var x_pos = x * GRID_SPACING
		_lines_to_draw.append({
			"start": Vector3(x_pos, 0, 0),
			"end": Vector3(x_pos, 0, -GRID_EXTENT),
			"color": CYAN
		})
		_lines_to_draw.append({
			"start": Vector3(x_pos, 0, 0),
			"end": Vector3(x_pos, 0, GRID_EXTENT),
			"color": CYAN
		})

	# Sort by distance from center for radial effect
	_lines_to_draw.sort_custom(func(a, b):
		var dist_a = a["start"].length() + a["end"].length()
		var dist_b = b["start"].length() + b["end"].length()
		return dist_a < dist_b
	)


## Generate table wireframe lines
func _generate_table_lines() -> void:
	_lines_to_draw.clear()

	var table_size = Vector2(6, 4)  # feet
	if table and table.get("table_size"):
		table_size = table.table_size

	var size_m = table_size * 0.3048
	var hx = size_m.x / 2
	var hz = size_m.y / 2
	var h = 0.025  # Table height

	# Bottom rectangle
	_lines_to_draw.append({"start": Vector3(-hx, 0, -hz), "end": Vector3(hx, 0, -hz), "color": CYAN})
	_lines_to_draw.append({"start": Vector3(hx, 0, -hz), "end": Vector3(hx, 0, hz), "color": CYAN})
	_lines_to_draw.append({"start": Vector3(hx, 0, hz), "end": Vector3(-hx, 0, hz), "color": CYAN})
	_lines_to_draw.append({"start": Vector3(-hx, 0, hz), "end": Vector3(-hx, 0, -hz), "color": CYAN})

	# Vertical edges
	_lines_to_draw.append({"start": Vector3(-hx, 0, -hz), "end": Vector3(-hx, h, -hz), "color": CYAN})
	_lines_to_draw.append({"start": Vector3(hx, 0, -hz), "end": Vector3(hx, h, -hz), "color": CYAN})
	_lines_to_draw.append({"start": Vector3(hx, 0, hz), "end": Vector3(hx, h, hz), "color": CYAN})
	_lines_to_draw.append({"start": Vector3(-hx, 0, hz), "end": Vector3(-hx, h, hz), "color": CYAN})

	# Top rectangle
	_lines_to_draw.append({"start": Vector3(-hx, h, -hz), "end": Vector3(hx, h, -hz), "color": CYAN})
	_lines_to_draw.append({"start": Vector3(hx, h, -hz), "end": Vector3(hx, h, hz), "color": CYAN})
	_lines_to_draw.append({"start": Vector3(hx, h, hz), "end": Vector3(-hx, h, hz), "color": CYAN})
	_lines_to_draw.append({"start": Vector3(-hx, h, hz), "end": Vector3(-hx, h, -hz), "color": CYAN})


func _update_blackout(delta: float) -> void:
	var phase_time = _total_time - _phase_start_time
	var fade_duration = 0.3

	if phase_time < fade_duration:
		black_overlay.modulate.a = 1.0 - (phase_time / fade_duration)
		skip_label.modulate.a = phase_time / fade_duration * 0.5
	else:
		black_overlay.modulate.a = 0.0
		skip_label.modulate.a = 0.5
		# Start grid drawing
		_phase = 1
		_phase_start_time = _total_time
		_current_line_index = 0
		_current_line_progress = 0.0
		cursor_mesh.visible = true


func _update_line_drawing(delta: float, line_time: float) -> void:
	if _current_line_index >= _lines_to_draw.size():
		# Done with current phase
		if _phase == 1:
			# Move to table drawing
			_phase = 2
			_phase_start_time = _total_time
			_generate_table_lines()
			_current_line_index = 0
			_current_line_progress = 0.0
		else:
			# Move to materialize
			_phase = 3
			_phase_start_time = _total_time
			cursor_mesh.visible = false
		return

	var line_data = _lines_to_draw[_current_line_index]
	_current_line_progress += delta / line_time

	if _current_line_progress >= 1.0:
		# Finish current line
		_finish_current_line(line_data)
		_current_line_index += 1
		_current_line_progress = 0.0
		_current_line_mesh = null
	else:
		# Update current line
		_update_current_line(line_data)


func _update_current_line(line_data: Dictionary) -> void:
	var start = line_data["start"]
	var end = line_data["end"]
	var color = line_data["color"]

	# Calculate current endpoint
	var current_end = start.lerp(end, _current_line_progress)

	# Update cursor position
	cursor_mesh.global_position = current_end
	cursor_mesh.global_position.y += 0.01  # Slightly above

	# Pulse cursor
	var pulse = sin(_total_time * 20.0) * 0.3 + 0.7
	cursor_mesh.scale = Vector3.ONE * pulse

	# Create or update line mesh
	if not _current_line_mesh:
		_current_line_mesh = _create_line_mesh(start, current_end, color)
		lines_container.add_child(_current_line_mesh)
	else:
		_update_line_mesh(_current_line_mesh, start, current_end, color)


func _finish_current_line(line_data: Dictionary) -> void:
	var start = line_data["start"]
	var end = line_data["end"]
	var color = line_data["color"]

	if _current_line_mesh:
		_update_line_mesh(_current_line_mesh, start, end, color)
	else:
		var mesh = _create_line_mesh(start, end, color)
		lines_container.add_child(mesh)


func _create_line_mesh(start: Vector3, end: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	var immediate_mesh = ImmediateMesh.new()
	mesh_instance.mesh = immediate_mesh

	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = material

	_draw_line_geometry(immediate_mesh, start, end)

	return mesh_instance


func _update_line_mesh(mesh_instance: MeshInstance3D, start: Vector3, end: Vector3, _color: Color) -> void:
	var immediate_mesh = mesh_instance.mesh as ImmediateMesh
	if immediate_mesh:
		immediate_mesh.clear_surfaces()
		_draw_line_geometry(immediate_mesh, start, end)


func _draw_line_geometry(immediate_mesh: ImmediateMesh, start: Vector3, end: Vector3) -> void:
	# Draw a thin box/cylinder as a line
	var direction = (end - start).normalized()
	var length = start.distance_to(end)

	if length < 0.001:
		return

	# Create perpendicular vectors for line width
	var up = Vector3.UP
	if abs(direction.dot(up)) > 0.9:
		up = Vector3.RIGHT

	var right = direction.cross(up).normalized() * LINE_WIDTH
	var forward = direction.cross(right).normalized() * LINE_WIDTH

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	# Create quad strip along the line
	var p1 = start + right
	var p2 = start - right
	var p3 = end + right
	var p4 = end - right

	# Top face
	immediate_mesh.surface_add_vertex(p1)
	immediate_mesh.surface_add_vertex(p2)
	immediate_mesh.surface_add_vertex(p3)

	immediate_mesh.surface_add_vertex(p2)
	immediate_mesh.surface_add_vertex(p4)
	immediate_mesh.surface_add_vertex(p3)

	# Bottom face
	var p1b = start + forward
	var p2b = start - forward
	var p3b = end + forward
	var p4b = end - forward

	immediate_mesh.surface_add_vertex(p1b)
	immediate_mesh.surface_add_vertex(p3b)
	immediate_mesh.surface_add_vertex(p2b)

	immediate_mesh.surface_add_vertex(p2b)
	immediate_mesh.surface_add_vertex(p3b)
	immediate_mesh.surface_add_vertex(p4b)

	immediate_mesh.surface_end()


func _update_materialize(delta: float) -> void:
	var phase_time = _total_time - _phase_start_time
	var duration = 1.5

	if phase_time < 0.3:
		# Show table
		if table and not table.visible:
			table.visible = true
	elif phase_time < duration:
		# Fade out lines
		var fade = 1.0 - ((phase_time - 0.3) / (duration - 0.3))
		for child in lines_container.get_children():
			if child is MeshInstance3D:
				child.transparency = 1.0 - fade

		# Transition to sky
		if phase_time > 0.5 and world_environment and world_environment.environment:
			world_environment.environment.background_mode = Environment.BG_SKY
	else:
		_phase = 4


func _finish_intro() -> void:
	_is_playing = false
	_show_main_scene()

	if intro_camera:
		intro_camera.current = false
	if original_camera_pivot:
		var cam = original_camera_pivot.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.current = true

	# Fade out skip label
	var tween = create_tween()
	tween.tween_property(skip_label, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_cleanup)

	intro_finished.emit()


func _skip_intro() -> void:
	if not _is_playing:
		return

	_is_playing = false
	_show_main_scene()

	if intro_camera:
		intro_camera.current = false
	if original_camera_pivot:
		var cam = original_camera_pivot.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.current = true

	var tween = create_tween()
	if black_overlay:
		tween.tween_property(black_overlay, "modulate:a", 0.0, 0.1)
	tween.tween_callback(_cleanup)

	intro_skipped.emit()


func _cleanup() -> void:
	if lines_container:
		lines_container.queue_free()
	if cursor_mesh:
		cursor_mesh.queue_free()
	if intro_camera_pivot:
		intro_camera_pivot.queue_free()
	if canvas_layer:
		canvas_layer.queue_free()
