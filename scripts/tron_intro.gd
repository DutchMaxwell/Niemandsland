extends Node3D
class_name TronIntro
## Tron-style intro animation that builds up the game world
## from a cyberspace grid into the final space table

signal intro_finished
signal intro_skipped

## Animation timing
const PHASE_VOID_DURATION: float = 0.5      # Black void with particles
const PHASE_GRID_DURATION: float = 2.0       # Grid spreads outward
const PHASE_TABLE_BUILD_DURATION: float = 2.0  # Table wireframe builds up
const PHASE_MATERIALIZE_DURATION: float = 1.5  # Wireframe fills with solid
const PHASE_SPACE_FADE_DURATION: float = 1.5   # Stars fade in

## Colors
const CYAN = Color(0.0, 1.0, 1.0)
const MAGENTA = Color(1.0, 0.0, 1.0)
const ORANGE = Color(1.0, 0.5, 0.0)
const DARK_BLUE = Color(0.0, 0.0, 0.2)

## References
var main_scene: Node3D
var world_environment: WorldEnvironment
var table: Node3D
var camera_pivot: Node3D

## Intro elements
var grid_floor: MeshInstance3D
var grid_material: ShaderMaterial
var wireframe_table: MeshInstance3D
var wireframe_material: ShaderMaterial
var particle_system: GPUParticles3D
var intro_camera: Camera3D
var black_overlay: ColorRect

## State
var _is_playing: bool = false
var _current_phase: int = 0
var _phase_timer: float = 0.0
var _can_skip: bool = true

## Skip hint label
var skip_label: Label


func _ready() -> void:
	# Hide main scene elements initially
	visible = true


func _input(event: InputEvent) -> void:
	if not _is_playing or not _can_skip:
		return

	# Skip on any key press or mouse click
	if event is InputEventKey and event.pressed:
		_skip_intro()
	elif event is InputEventMouseButton and event.pressed:
		_skip_intro()


func _process(delta: float) -> void:
	if not _is_playing:
		return

	_phase_timer += delta
	_update_current_phase()


## Start the intro animation
func play_intro(main: Node3D) -> void:
	main_scene = main
	world_environment = main.get_node("WorldEnvironment")
	table = main.get_node("Table")
	camera_pivot = main.get_node("CameraPivot")

	_is_playing = true
	_current_phase = 0
	_phase_timer = 0.0

	# Hide main scene elements
	_hide_main_scene()

	# Create intro elements
	_create_intro_elements()

	# Start phase 0 (void)
	_start_phase(0)


## Hide main scene elements during intro
func _hide_main_scene() -> void:
	if table:
		table.visible = false
	# Dim the environment
	if world_environment and world_environment.environment:
		world_environment.environment.background_mode = Environment.BG_COLOR
		world_environment.environment.background_color = Color.BLACK


## Restore main scene after intro
func _show_main_scene() -> void:
	if table:
		table.visible = true
	# Restore sky environment
	if world_environment and world_environment.environment:
		world_environment.environment.background_mode = Environment.BG_SKY


## Create all intro visual elements
func _create_intro_elements() -> void:
	# Black overlay for fade effects
	var canvas = CanvasLayer.new()
	canvas.name = "IntroCanvas"
	canvas.layer = 100
	add_child(canvas)

	black_overlay = ColorRect.new()
	black_overlay.color = Color.BLACK
	black_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(black_overlay)

	# Skip hint label
	skip_label = Label.new()
	skip_label.text = "Press any key to skip..."
	skip_label.add_theme_color_override("font_color", CYAN.darkened(0.3))
	skip_label.add_theme_font_size_override("font_size", 16)
	skip_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip_label.offset_left = -200
	skip_label.offset_top = -40
	skip_label.modulate.a = 0.0
	canvas.add_child(skip_label)

	# Create grid floor
	_create_grid_floor()

	# Create wireframe table preview
	_create_wireframe_table()

	# Create particle system
	_create_particles()


## Create the Tron grid floor
func _create_grid_floor() -> void:
	grid_floor = MeshInstance3D.new()
	grid_floor.name = "TronGrid"

	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(50, 50)
	plane_mesh.subdivide_width = 1
	plane_mesh.subdivide_depth = 1
	grid_floor.mesh = plane_mesh

	# Load and setup shader material
	grid_material = ShaderMaterial.new()
	var shader = load("res://shaders/tron_grid.gdshader")
	grid_material.shader = shader
	grid_material.set_shader_parameter("grid_color", Vector3(CYAN.r, CYAN.g, CYAN.b))
	grid_material.set_shader_parameter("accent_color", Vector3(MAGENTA.r, MAGENTA.g, MAGENTA.b))
	grid_material.set_shader_parameter("animation_progress", 0.0)
	grid_material.set_shader_parameter("grid_spacing", 0.5)
	grid_material.set_shader_parameter("glow_intensity", 2.0)
	grid_material.set_shader_parameter("fade_distance", 25.0)

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

	# Create wireframe material
	wireframe_material = ShaderMaterial.new()
	var shader = load("res://shaders/tron_wireframe.gdshader")
	wireframe_material.shader = shader
	wireframe_material.set_shader_parameter("wire_color", Vector3(CYAN.r, CYAN.g, CYAN.b))
	wireframe_material.set_shader_parameter("build_progress", 0.0)
	wireframe_material.set_shader_parameter("glow_intensity", 2.0)

	wireframe_table.material_override = wireframe_material
	wireframe_table.position.y = 0.025

	add_child(wireframe_table)
	wireframe_table.visible = false


## Create floating particles for the void phase
func _create_particles() -> void:
	particle_system = GPUParticles3D.new()
	particle_system.name = "TronParticles"
	particle_system.amount = 200
	particle_system.lifetime = 3.0
	particle_system.explosiveness = 0.0
	particle_system.randomness = 1.0

	# Simple particle material
	var particle_material = ParticleProcessMaterial.new()
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	particle_material.emission_box_extents = Vector3(15, 10, 15)
	particle_material.direction = Vector3(0, 1, 0)
	particle_material.spread = 180.0
	particle_material.initial_velocity_min = 0.1
	particle_material.initial_velocity_max = 0.5
	particle_material.gravity = Vector3(0, 0.1, 0)
	particle_material.scale_min = 0.02
	particle_material.scale_max = 0.05
	particle_material.color = CYAN

	particle_system.process_material = particle_material

	# Particle mesh (small sphere)
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.02
	sphere_mesh.height = 0.04
	particle_system.draw_pass_1 = sphere_mesh

	# Emissive material for glow
	var draw_material = StandardMaterial3D.new()
	draw_material.albedo_color = CYAN
	draw_material.emission_enabled = true
	draw_material.emission = CYAN
	draw_material.emission_energy_multiplier = 3.0
	sphere_mesh.material = draw_material

	add_child(particle_system)
	particle_system.emitting = true


## Start a specific phase
func _start_phase(phase: int) -> void:
	_current_phase = phase
	_phase_timer = 0.0

	match phase:
		0:  # Void - black with particles
			_start_void_phase()
		1:  # Grid appears
			_start_grid_phase()
		2:  # Table wireframe builds
			_start_table_build_phase()
		3:  # Materialize
			_start_materialize_phase()
		4:  # Space fade in
			_start_space_fade_phase()
		5:  # Done
			_finish_intro()


## Update the current phase
func _update_current_phase() -> void:
	var phase_duration = _get_phase_duration(_current_phase)

	match _current_phase:
		0:  # Void
			_update_void_phase()
		1:  # Grid
			_update_grid_phase()
		2:  # Table build
			_update_table_build_phase()
		3:  # Materialize
			_update_materialize_phase()
		4:  # Space fade
			_update_space_fade_phase()

	# Check for phase transition
	if _phase_timer >= phase_duration:
		_start_phase(_current_phase + 1)


func _get_phase_duration(phase: int) -> float:
	match phase:
		0: return PHASE_VOID_DURATION
		1: return PHASE_GRID_DURATION
		2: return PHASE_TABLE_BUILD_DURATION
		3: return PHASE_MATERIALIZE_DURATION
		4: return PHASE_SPACE_FADE_DURATION
		_: return 0.0


## Phase 0: Void with particles
func _start_void_phase() -> void:
	black_overlay.color = Color.BLACK
	black_overlay.modulate.a = 1.0
	grid_floor.visible = false
	wireframe_table.visible = false

	# Fade in skip hint
	var tween = create_tween()
	tween.tween_property(skip_label, "modulate:a", 0.5, 0.3)


func _update_void_phase() -> void:
	# Fade out black overlay slightly
	var progress = _phase_timer / PHASE_VOID_DURATION
	black_overlay.modulate.a = lerp(1.0, 0.0, progress)


## Phase 1: Grid spreads outward
func _start_grid_phase() -> void:
	grid_floor.visible = true
	grid_material.set_shader_parameter("animation_progress", 0.0)


func _update_grid_phase() -> void:
	var progress = _phase_timer / PHASE_GRID_DURATION
	# Ease out for smooth spread
	var eased = 1.0 - pow(1.0 - progress, 3.0)
	grid_material.set_shader_parameter("animation_progress", eased)


## Phase 2: Table wireframe builds up
func _start_table_build_phase() -> void:
	wireframe_table.visible = true
	wireframe_material.set_shader_parameter("build_progress", 0.0)


func _update_table_build_phase() -> void:
	var progress = _phase_timer / PHASE_TABLE_BUILD_DURATION
	# Smooth ease in-out
	var eased = progress * progress * (3.0 - 2.0 * progress)
	wireframe_material.set_shader_parameter("build_progress", eased)
	wireframe_material.set_shader_parameter("scan_height", eased)


## Phase 3: Materialize - wireframe fills in, real table fades in
func _start_materialize_phase() -> void:
	# Show real table but transparent
	if table:
		table.visible = true
		_set_table_transparency(0.0)


func _update_materialize_phase() -> void:
	var progress = _phase_timer / PHASE_MATERIALIZE_DURATION

	# Fade out wireframe, fade in real table
	var wireframe_alpha = 1.0 - progress
	wireframe_material.set_shader_parameter("glow_intensity", wireframe_alpha * 2.0)

	# Fade in real table
	_set_table_transparency(progress)

	# Fade out grid
	grid_material.set_shader_parameter("glow_intensity", (1.0 - progress) * 2.0)


## Phase 4: Space environment fades in
func _start_space_fade_phase() -> void:
	# Start transitioning to sky background
	wireframe_table.visible = false
	grid_floor.visible = false


func _update_space_fade_phase() -> void:
	var progress = _phase_timer / PHASE_SPACE_FADE_DURATION

	# Crossfade from black to sky
	if world_environment and world_environment.environment:
		# Switch to sky mode partway through
		if progress > 0.3:
			world_environment.environment.background_mode = Environment.BG_SKY

	# Fade particles
	if particle_system:
		var particle_mat = particle_system.process_material as ParticleProcessMaterial
		if particle_mat:
			particle_mat.color = CYAN * (1.0 - progress)

	# Ensure table is fully visible
	_set_table_transparency(1.0)


## Finish the intro and clean up
func _finish_intro() -> void:
	_is_playing = false

	# Ensure everything is visible
	_show_main_scene()
	_set_table_transparency(1.0)

	# Fade out skip label
	var tween = create_tween()
	tween.tween_property(skip_label, "modulate:a", 0.0, 0.3)

	# Stop particles
	if particle_system:
		particle_system.emitting = false

	# Clean up after a short delay
	tween.tween_callback(_cleanup)

	intro_finished.emit()


## Skip the intro immediately
func _skip_intro() -> void:
	if not _is_playing:
		return

	_is_playing = false

	# Immediately show final state
	_show_main_scene()
	_set_table_transparency(1.0)

	# Quick fade
	var tween = create_tween()
	tween.set_parallel(true)

	if black_overlay:
		tween.tween_property(black_overlay, "modulate:a", 0.0, 0.2)
	if grid_floor:
		grid_floor.visible = false
	if wireframe_table:
		wireframe_table.visible = false
	if particle_system:
		particle_system.emitting = false

	tween.tween_callback(_cleanup).set_delay(0.3)

	intro_skipped.emit()


## Clean up intro elements
func _cleanup() -> void:
	# Remove all intro elements
	if grid_floor:
		grid_floor.queue_free()
	if wireframe_table:
		wireframe_table.queue_free()
	if particle_system:
		particle_system.queue_free()

	# Remove canvas layer with overlay and label
	for child in get_children():
		if child is CanvasLayer:
			child.queue_free()


## Set table transparency (for fade in effect)
func _set_table_transparency(alpha: float) -> void:
	if not table:
		return

	# Find table mesh and set transparency
	var table_mesh = table.get_node_or_null("TableMesh") as MeshInstance3D
	if table_mesh and table_mesh.mesh:
		var mat = table_mesh.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
			mat.albedo_color.a = alpha
