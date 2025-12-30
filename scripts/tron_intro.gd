extends Node3D
class_name TronIntro
## Tron-style intro animation with laser-drawing effect
## Lines are drawn by visible cursor points, camera starts flat and rises

signal intro_finished
signal intro_skipped

## Animation timing (total ~8 seconds)
const PHASE_BLACKOUT_DURATION: float = 0.3
const PHASE_GRID_DRAW_DURATION: float = 3.0      # Grid lines drawn by laser
const PHASE_TABLE_DRAW_DURATION: float = 2.0     # Table edges drawn
const PHASE_MATERIALIZE_DURATION: float = 1.5    # Fill in and reveal
const PHASE_CAMERA_SETTLE_DURATION: float = 1.2  # Camera moves to final position

## Colors
const CYAN = Color(0.0, 1.0, 1.0)
const MAGENTA = Color(1.0, 0.0, 1.0)
const WHITE = Color(1.0, 1.0, 1.0)
const DARK_BLUE = Color(0.0, 0.02, 0.08)

## References
var main_scene: Node3D
var world_environment: WorldEnvironment
var table: Node3D
var original_camera_pivot: Node3D
var original_environment: Environment

## Intro elements
var grid_floor: MeshInstance3D
var grid_material: ShaderMaterial
var wireframe_table: MeshInstance3D
var wireframe_material: ShaderMaterial
var intro_camera: Camera3D
var intro_camera_pivot: Node3D
var black_overlay: ColorRect
var skip_label: Label
var canvas_layer: CanvasLayer

## Original values to restore
var _original_glow_intensity: float = 1.0
var _original_glow_bloom: float = 0.3
var _original_camera_transform: Transform3D

## State
var _is_playing: bool = false
var _current_phase: int = 0
var _phase_timer: float = 0.0
var _total_time: float = 0.0
var _can_skip: bool = true


func _input(event: InputEvent) -> void:
	if not _is_playing or not _can_skip:
		return

	# Skip on any key press or mouse click
	if event is InputEventKey and event.pressed and not event.echo:
		_skip_intro()
	elif event is InputEventMouseButton and event.pressed:
		_skip_intro()


func _process(delta: float) -> void:
	if not _is_playing:
		return

	_phase_timer += delta
	_total_time += delta
	_update_current_phase()
	_update_camera_animation()


## Start the intro animation
func play_intro(main: Node3D) -> void:
	main_scene = main
	world_environment = main.get_node("WorldEnvironment")
	table = main.get_node("Table")
	original_camera_pivot = main.get_node("CameraPivot")

	# Store original environment settings
	if world_environment and world_environment.environment:
		original_environment = world_environment.environment
		_original_glow_intensity = original_environment.glow_intensity
		_original_glow_bloom = original_environment.glow_bloom

	# Store original camera transform
	if original_camera_pivot:
		var cam = original_camera_pivot.get_node_or_null("Camera3D")
		if cam:
			_original_camera_transform = cam.global_transform

	_is_playing = true
	_current_phase = 0
	_phase_timer = 0.0
	_total_time = 0.0

	# Setup
	_hide_main_scene()
	_setup_environment_for_intro()
	_create_intro_elements()
	_setup_intro_camera()

	# Start
	_start_phase(0)


## Hide main scene elements during intro
func _hide_main_scene() -> void:
	if table:
		table.visible = false
	# Disable original camera
	if original_camera_pivot:
		var cam = original_camera_pivot.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.current = false


## Setup environment for sharp, crisp intro visuals
func _setup_environment_for_intro() -> void:
	if not world_environment or not world_environment.environment:
		return

	var env = world_environment.environment

	# Black background
	env.background_mode = Environment.BG_COLOR
	env.background_color = DARK_BLUE

	# Reduce glow for sharper lines
	env.glow_intensity = 0.8
	env.glow_bloom = 0.1
	env.glow_strength = 0.8


## Restore main scene after intro
func _show_main_scene() -> void:
	if table:
		table.visible = true

	# Restore sky
	if world_environment and world_environment.environment:
		world_environment.environment.background_mode = Environment.BG_SKY
		world_environment.environment.glow_intensity = _original_glow_intensity
		world_environment.environment.glow_bloom = _original_glow_bloom

	# Re-enable original camera
	if original_camera_pivot:
		var cam = original_camera_pivot.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.current = true


## Setup camera starting from a flat, dramatic angle
func _setup_intro_camera() -> void:
	# Create our own camera for the intro
	intro_camera_pivot = Node3D.new()
	intro_camera_pivot.name = "IntroCameraPivot"
	add_child(intro_camera_pivot)

	intro_camera = Camera3D.new()
	intro_camera.name = "IntroCamera"
	intro_camera.fov = 50.0
	intro_camera.near = 0.05
	intro_camera.far = 100.0
	intro_camera_pivot.add_child(intro_camera)

	# Start position: low angle, looking across the grid
	# Camera at edge of grid, low height, looking toward center
	intro_camera_pivot.position = Vector3(0, 0.3, 12)  # Low, far back
	intro_camera_pivot.rotation_degrees = Vector3(-5, 0, 0)  # Slight look down

	intro_camera.position = Vector3.ZERO
	intro_camera.rotation_degrees = Vector3.ZERO

	intro_camera.current = true


## Animate camera from flat angle to normal overhead view
func _update_camera_animation() -> void:
	if not intro_camera_pivot or not intro_camera:
		return

	# Total camera animation time spans most of the intro
	var camera_duration = PHASE_GRID_DRAW_DURATION + PHASE_TABLE_DRAW_DURATION + PHASE_MATERIALIZE_DURATION
	var camera_progress = clampf(_total_time / camera_duration, 0.0, 1.0)

	# Ease in-out for smooth camera movement
	var eased = camera_progress * camera_progress * (3.0 - 2.0 * camera_progress)

	# Start: low angle from edge (Y=0.3, Z=12, rotX=-5)
	# End: higher angle, closer, more overhead (Y=6, Z=6, rotX=-45)
	var start_pos = Vector3(0, 0.3, 12)
	var end_pos = Vector3(0, 6, 6)
	var start_rot = Vector3(-5, 0, 0)
	var end_rot = Vector3(-45, 0, 0)

	intro_camera_pivot.position = start_pos.lerp(end_pos, eased)
	intro_camera_pivot.rotation_degrees = start_rot.lerp(end_rot, eased)


## Create all intro visual elements
func _create_intro_elements() -> void:
	# Canvas layer for overlay
	canvas_layer = CanvasLayer.new()
	canvas_layer.name = "IntroCanvas"
	canvas_layer.layer = 100
	add_child(canvas_layer)

	# Black overlay
	black_overlay = ColorRect.new()
	black_overlay.color = Color.BLACK
	black_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(black_overlay)

	# Skip hint
	skip_label = Label.new()
	skip_label.text = "Press any key to skip"
	skip_label.add_theme_color_override("font_color", CYAN.darkened(0.5))
	skip_label.add_theme_font_size_override("font_size", 14)
	skip_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip_label.offset_left = -180
	skip_label.offset_top = -30
	skip_label.modulate.a = 0.0
	canvas_layer.add_child(skip_label)

	# Create grid
	_create_grid_floor()

	# Create wireframe table
	_create_wireframe_table()


## Create the Tron grid floor
func _create_grid_floor() -> void:
	grid_floor = MeshInstance3D.new()
	grid_floor.name = "TronGrid"

	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(60, 60)
	plane_mesh.subdivide_width = 2
	plane_mesh.subdivide_depth = 2
	grid_floor.mesh = plane_mesh

	# Load shader
	grid_material = ShaderMaterial.new()
	var shader = load("res://shaders/tron_grid.gdshader")
	if shader:
		grid_material.shader = shader
		grid_material.set_shader_parameter("grid_color", Vector3(CYAN.r, CYAN.g, CYAN.b))
		grid_material.set_shader_parameter("cursor_color", Vector3(WHITE.r, WHITE.g, WHITE.b))
		grid_material.set_shader_parameter("cursor_progress", 0.0)
		grid_material.set_shader_parameter("grid_spacing", 0.5)
		grid_material.set_shader_parameter("line_width", 0.006)
		grid_material.set_shader_parameter("glow_intensity", 1.2)
		grid_material.set_shader_parameter("grid_size", 25.0)
		grid_material.set_shader_parameter("cursor_size", 0.2)

	grid_floor.material_override = grid_material
	grid_floor.position.y = -0.01

	add_child(grid_floor)
	grid_floor.visible = false


## Create wireframe preview of the table
func _create_wireframe_table() -> void:
	wireframe_table = MeshInstance3D.new()
	wireframe_table.name = "WireframeTable"

	# Get table size
	var table_size = Vector2(6, 4)  # Default 6x4 feet
	if table and table.get("table_size"):
		table_size = table.table_size

	var size_m = table_size * 0.3048  # feet to meters
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(size_m.x, 0.05, size_m.y)
	wireframe_table.mesh = box_mesh

	# Load wireframe shader
	wireframe_material = ShaderMaterial.new()
	var shader = load("res://shaders/tron_wireframe.gdshader")
	if shader:
		wireframe_material.shader = shader
		wireframe_material.set_shader_parameter("wire_color", Vector3(CYAN.r, CYAN.g, CYAN.b))
		wireframe_material.set_shader_parameter("cursor_color", Vector3(WHITE.r, WHITE.g, WHITE.b))
		wireframe_material.set_shader_parameter("draw_progress", 0.0)
		wireframe_material.set_shader_parameter("glow_intensity", 1.5)
		wireframe_material.set_shader_parameter("box_size", box_mesh.size)
		wireframe_material.set_shader_parameter("wire_width", 0.012)

	wireframe_table.material_override = wireframe_material
	wireframe_table.position.y = 0.025

	add_child(wireframe_table)
	wireframe_table.visible = false


## Start a specific phase
func _start_phase(phase: int) -> void:
	_current_phase = phase
	_phase_timer = 0.0

	match phase:
		0:  # Blackout
			_start_blackout_phase()
		1:  # Grid drawing
			_start_grid_draw_phase()
		2:  # Table drawing
			_start_table_draw_phase()
		3:  # Materialize
			_start_materialize_phase()
		4:  # Camera settle
			_start_camera_settle_phase()
		5:  # Done
			_finish_intro()


## Update current phase
func _update_current_phase() -> void:
	var phase_duration = _get_phase_duration(_current_phase)

	match _current_phase:
		0:
			_update_blackout_phase()
		1:
			_update_grid_draw_phase()
		2:
			_update_table_draw_phase()
		3:
			_update_materialize_phase()
		4:
			_update_camera_settle_phase()

	if _phase_timer >= phase_duration:
		_start_phase(_current_phase + 1)


func _get_phase_duration(phase: int) -> float:
	match phase:
		0: return PHASE_BLACKOUT_DURATION
		1: return PHASE_GRID_DRAW_DURATION
		2: return PHASE_TABLE_DRAW_DURATION
		3: return PHASE_MATERIALIZE_DURATION
		4: return PHASE_CAMERA_SETTLE_DURATION
		_: return 0.0


## Phase 0: Quick blackout
func _start_blackout_phase() -> void:
	black_overlay.modulate.a = 1.0
	grid_floor.visible = false
	wireframe_table.visible = false


func _update_blackout_phase() -> void:
	var progress = _phase_timer / PHASE_BLACKOUT_DURATION
	black_overlay.modulate.a = 1.0 - progress

	# Fade in skip hint
	skip_label.modulate.a = progress * 0.6


## Phase 1: Grid lines drawn by laser cursor
func _start_grid_draw_phase() -> void:
	grid_floor.visible = true
	grid_material.set_shader_parameter("cursor_progress", 0.0)


func _update_grid_draw_phase() -> void:
	var progress = _phase_timer / PHASE_GRID_DRAW_DURATION
	# Ease out for natural deceleration as it spreads
	var eased = 1.0 - pow(1.0 - progress, 2.0)
	grid_material.set_shader_parameter("cursor_progress", eased)


## Phase 2: Table edges drawn by laser
func _start_table_draw_phase() -> void:
	wireframe_table.visible = true
	wireframe_material.set_shader_parameter("draw_progress", 0.0)


func _update_table_draw_phase() -> void:
	var progress = _phase_timer / PHASE_TABLE_DRAW_DURATION
	wireframe_material.set_shader_parameter("draw_progress", progress)


## Phase 3: Materialize - transition to real table
func _start_materialize_phase() -> void:
	if table:
		table.visible = true
		_set_table_transparency(0.0)


func _update_materialize_phase() -> void:
	var progress = _phase_timer / PHASE_MATERIALIZE_DURATION

	# Fade out wireframe and grid
	var fade = 1.0 - progress
	grid_material.set_shader_parameter("glow_intensity", fade * 1.2)
	wireframe_material.set_shader_parameter("glow_intensity", fade * 1.5)

	# Fade in real table
	_set_table_transparency(progress)

	# Transition to sky background
	if progress > 0.4 and world_environment and world_environment.environment:
		world_environment.environment.background_mode = Environment.BG_SKY


## Phase 4: Camera settles to final position
func _start_camera_settle_phase() -> void:
	# Hide intro elements
	grid_floor.visible = false
	wireframe_table.visible = false

	# Ensure table fully visible
	_set_table_transparency(1.0)

	# Restore original glow settings
	if world_environment and world_environment.environment:
		world_environment.environment.glow_intensity = _original_glow_intensity
		world_environment.environment.glow_bloom = _original_glow_bloom


func _update_camera_settle_phase() -> void:
	var progress = _phase_timer / PHASE_CAMERA_SETTLE_DURATION

	# Fade out skip hint
	skip_label.modulate.a = (1.0 - progress) * 0.6


## Finish intro
func _finish_intro() -> void:
	_is_playing = false

	_show_main_scene()

	# Switch back to original camera
	if intro_camera:
		intro_camera.current = false
	if original_camera_pivot:
		var cam = original_camera_pivot.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.current = true

	# Cleanup after delay
	var tween = create_tween()
	tween.tween_interval(0.5)
	tween.tween_callback(_cleanup)

	intro_finished.emit()


## Skip intro
func _skip_intro() -> void:
	if not _is_playing:
		return

	_is_playing = false

	# Immediately show final state
	_show_main_scene()
	_set_table_transparency(1.0)

	# Hide intro elements
	if grid_floor:
		grid_floor.visible = false
	if wireframe_table:
		wireframe_table.visible = false

	# Switch camera
	if intro_camera:
		intro_camera.current = false
	if original_camera_pivot:
		var cam = original_camera_pivot.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.current = true

	# Quick fade out overlay
	var tween = create_tween()
	if black_overlay:
		tween.tween_property(black_overlay, "modulate:a", 0.0, 0.15)
	tween.tween_callback(_cleanup)

	intro_skipped.emit()


## Cleanup
func _cleanup() -> void:
	if grid_floor:
		grid_floor.queue_free()
		grid_floor = null
	if wireframe_table:
		wireframe_table.queue_free()
		wireframe_table = null
	if intro_camera_pivot:
		intro_camera_pivot.queue_free()
		intro_camera_pivot = null
	if canvas_layer:
		canvas_layer.queue_free()
		canvas_layer = null


## Set table transparency
func _set_table_transparency(alpha: float) -> void:
	if not table:
		return

	var table_mesh = table.get_node_or_null("TableMesh") as MeshInstance3D
	if not table_mesh:
		return

	# Get or create material
	var mat = table_mesh.get_surface_override_material(0)
	if not mat and table_mesh.mesh:
		mat = table_mesh.mesh.surface_get_material(0)

	if mat is StandardMaterial3D:
		var std_mat = mat as StandardMaterial3D
		if alpha < 0.99:
			std_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			std_mat.albedo_color.a = alpha
		else:
			std_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			std_mat.albedo_color.a = 1.0
