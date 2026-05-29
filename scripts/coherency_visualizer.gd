extends Node3D
class_name CoherencyVisualizer
## Visual feedback system for unit coherency.
## Shows lines between models, highlights issues, and provides fix suggestions.

signal visualization_completed(result: CoherencyChecker.CoherencyResult)

## Colors for visualization
const COLOR_OK := Color(0.2, 0.9, 0.2, 0.8)        # Green
const COLOR_WARNING := Color(0.9, 0.9, 0.2, 0.8)   # Yellow
const COLOR_ERROR := Color(0.9, 0.2, 0.2, 0.8)     # Red
const COLOR_CHAIN := Color(0.2, 0.5, 0.9, 0.5)     # Blue (max chain)

## Table-surface heights (kept flat on the table, like the measurement tool).
const LINE_Y := 0.005   # Flat line just above the table
const EDGE_Y := 0.02    # Base-edge endpoints / labels above the table

## Visual line thickness (flat strip on the XZ plane).
const LINE_WIDTH := 0.004

## Animation duration
const FADE_DURATION := 0.3
const PULSE_DURATION := 1.0

## Current visualization elements
var _lines: Array[MeshInstance3D] = []
var _highlights: Array[Node3D] = []
var _labels: Array[Label3D] = []
var _current_unit: GameUnit = null
var _tween: Tween = null

## Custom alpha for 3D fade (Node3D doesn't have modulate)
var _visualization_alpha: float = 1.0:
	set(value):
		_visualization_alpha = value
		_update_materials_alpha(value)


func _ready() -> void:
	# Start invisible
	visible = false


## Shows coherency visualization for a unit.
## animate: fade/pulse in (for one-off checks). Set false for live updates while
## dragging - re-running the fade every frame makes the lines flicker badly.
func show_coherency(game_unit: GameUnit, is_skirmish: bool = false, animate: bool = true) -> CoherencyChecker.CoherencyResult:
	_clear_visualization()
	_current_unit = game_unit

	# Check coherency
	var result = CoherencyChecker.check_unit_coherency(game_unit, is_skirmish)

	# Get alive models (joined Heroes included - they belong to the unit)
	var models = game_unit.get_alive_models_with_attached()
	if models.size() <= 1:
		visible = false
		visualization_completed.emit(result)
		return result

	# Nothing to show for a coherent unit.
	if result.valid:
		visible = false
		visualization_completed.emit(result)
		return result

	# Show the existing 1" chain in green so the connected part is visible...
	_draw_chain_edges(models)

	# ...then highlight every problem with a red ring and a labelled line to the
	# nearest unit model (so it's clear which model breaks coherency to which).
	for issue in result.issues:
		match issue.type:
			CoherencyChecker.IssueType.ISOLATED:
				if issue.model:
					_highlight_model(issue.model, COLOR_ERROR, animate)
					var nearest = issue.get("nearest_model")
					if nearest:
						_draw_problem_line(
							issue.model, nearest, issue.get("nearest_distance", 0.0), COLOR_ERROR
						)
			CoherencyChecker.IssueType.CHAIN_TOO_LONG:
				var model_a = issue.get("model_a")
				var model_b = issue.get("model_b")
				if model_a and model_b:
					_draw_problem_line(
						model_a, model_b, issue.get("chain_distance", 0.0), COLOR_CHAIN
					)

	visible = true
	if animate:
		_animate_fade_in()
	else:
		# Live update: show at full opacity without re-running the fade each frame.
		if _tween:
			_tween.kill()
			_tween = null
		_visualization_alpha = 1.0

	visualization_completed.emit(result)
	return result


## Draws green lines for every pair of models that are within 1" coherency
## (3" across elevation), visualizing the connected chain. Lines run base-edge
## to base-edge, flat on the table.
func _draw_chain_edges(models: Array[ModelInstance]) -> void:
	for i in range(models.size()):
		for j in range(i + 1, models.size()):
			var model_a = models[i]
			var model_b = models[j]
			if not _models_drawable(model_a, model_b):
				continue
			if not CoherencyChecker._are_linked(model_a, model_b):
				continue
			_add_surface_line(model_a, model_b, COLOR_OK)


## Draws a coloured base-edge-to-base-edge line on the table between two models,
## with a flat distance label - mirroring the in-game measurement tool.
func _draw_problem_line(model_a: ModelInstance, model_b: ModelInstance, dist_inches: float, color: Color) -> void:
	if not _models_drawable(model_a, model_b):
		return

	var from_edge := CoherencyChecker.get_ground_edge_point(model_a, model_b.node.global_position, EDGE_Y)
	var to_edge := CoherencyChecker.get_ground_edge_point(model_b, model_a.node.global_position, EDGE_Y)

	_add_surface_line(model_a, model_b, color)

	var midpoint = (from_edge + to_edge) / 2.0
	_create_distance_label(midpoint, from_edge, to_edge, "%.1f\"" % dist_inches, color)


## Returns true if both models have valid nodes that are in the scene tree.
func _models_drawable(model_a: ModelInstance, model_b: ModelInstance) -> bool:
	if not model_a.node or not model_b.node:
		return false
	if not is_instance_valid(model_a.node) or not is_instance_valid(model_b.node):
		return false
	return model_a.node.is_inside_tree() and model_b.node.is_inside_tree()


## Adds a flat surface line between two models' base edges.
func _add_surface_line(model_a: ModelInstance, model_b: ModelInstance, color: Color) -> void:
	var from_edge := CoherencyChecker.get_ground_edge_point(model_a, model_b.node.global_position, EDGE_Y)
	var to_edge := CoherencyChecker.get_ground_edge_point(model_b, model_a.node.global_position, EDGE_Y)
	var line = _create_surface_line(from_edge, to_edge, color)
	if line:
		add_child(line)
		_lines.append(line)


## Creates a distance label lying flat on the table, aligned with the line
## (same style as the in-game measurement tool).
func _create_distance_label(midpoint: Vector3, from_edge: Vector3, to_edge: Vector3, text: String, color: Color) -> void:
	var label = Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = true
	label.render_priority = 1
	label.pixel_size = 0.001
	label.font_size = 24
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 1)
	label.outline_size = 8
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	add_child(label)
	label.global_position = Vector3(midpoint.x, EDGE_Y, midpoint.z)

	# Lay flat on the table, aligned with the line direction.
	var direction = to_edge - from_edge
	var angle = atan2(direction.x, direction.z)
	label.rotation = Vector3(-PI / 2.0, angle, 0)

	_labels.append(label)


## Hides the coherency visualization.
func hide_coherency() -> void:
	if _tween:
		_tween.kill()

	_tween = create_tween()
	_tween.tween_property(self, "_visualization_alpha", 0.0, FADE_DURATION)
	_tween.tween_callback(_clear_visualization)


## Creates a thin flat line strip lying on the table between two points
## (same look as the in-game measurement tool).
func _create_surface_line(from_edge: Vector3, to_edge: Vector3, color: Color) -> MeshInstance3D:
	var direction = Vector3(to_edge.x - from_edge.x, 0, to_edge.z - from_edge.z)
	var length = direction.length()
	if length < 0.001:
		return null

	var mesh_instance = MeshInstance3D.new()

	var line_mesh = BoxMesh.new()
	line_mesh.size = Vector3(length, 0.001, LINE_WIDTH)
	mesh_instance.mesh = line_mesh

	# Lie flat on the table at the midpoint, aligned with the direction.
	var midpoint = (from_edge + to_edge) / 2.0
	midpoint.y = LINE_Y
	mesh_instance.position = midpoint
	mesh_instance.rotation = Vector3(0, atan2(direction.x, direction.z) + PI / 2.0, 0)

	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	mesh_instance.material_override = material

	return mesh_instance


## Highlights a model with a colored ring. pulse adds a pulsing animation; pass
## false for live updates so the ring doesn't restart its pulse every frame.
func _highlight_model(model: ModelInstance, color: Color, pulse: bool = true) -> void:
	if not model.node or not is_instance_valid(model.node):
		return
	if not model.node.is_inside_tree():
		return

	# Get base size from the unit
	var base_radius_m = 0.016  # Default 32mm
	if model.unit:
		var game_unit = model.unit as GameUnit
		if game_unit and game_unit.unit_properties:
			var base_mm = game_unit.unit_properties.get("base_size_round", 32)
			base_radius_m = (base_mm / 2.0) * 0.001

	var highlight = Node3D.new()
	# Use the ModelInstance id (unique) so a host model and a joined hero model
	# that share model_index 0 do not collide into the same node name.
	highlight.name = "Highlight_%d" % model.get_instance_id()

	# Create ring mesh sized to base
	var torus = TorusMesh.new()
	torus.inner_radius = base_radius_m + 0.003  # 3mm outside base
	torus.outer_radius = base_radius_m + 0.008  # 5mm ring thickness

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = torus
	# TorusMesh defaults to flat (hole up), no rotation needed

	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material

	highlight.add_child(mesh_instance)

	# Add to tree FIRST, then set global position at base level (always on ground)
	add_child(highlight)
	# Use model's X/Z but always place ring at ground level (y=0.004)
	var model_pos = model.node.global_position
	highlight.global_position = Vector3(model_pos.x, 0.004, model_pos.z)
	_highlights.append(highlight)

	# Add pulsing animation (deferred to ensure node is ready)
	if pulse:
		mesh_instance.ready.connect(func(): _animate_pulse(mesh_instance), CONNECT_ONE_SHOT)


## Animates a pulse effect on a mesh.
func _animate_pulse(mesh: MeshInstance3D) -> void:
	if not mesh or not is_instance_valid(mesh):
		return
	if not mesh.is_inside_tree():
		return
	# Use finite loops to avoid Godot 4.5 infinite loop error
	var tween = mesh.create_tween()
	tween.set_loops(100)  # Plenty of loops for visualization duration
	tween.tween_property(mesh, "scale", Vector3(1.2, 1.2, 1.2), PULSE_DURATION / 2)
	tween.tween_property(mesh, "scale", Vector3(1.0, 1.0, 1.0), PULSE_DURATION / 2)


## Animates fade in.
func _animate_fade_in() -> void:
	_visualization_alpha = 0.0

	if _tween:
		_tween.kill()

	_tween = create_tween()
	_tween.tween_property(self, "_visualization_alpha", 1.0, FADE_DURATION)


## Updates alpha on all materials (for 3D fade effect).
func _update_materials_alpha(alpha: float) -> void:
	for line in _lines:
		if is_instance_valid(line) and line.material_override:
			var mat = line.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = alpha

	for highlight in _highlights:
		if is_instance_valid(highlight):
			for child in highlight.get_children():
				if child is MeshInstance3D and child.material_override:
					var mat = child.material_override as StandardMaterial3D
					if mat:
						mat.albedo_color.a = alpha

	for label in _labels:
		if is_instance_valid(label):
			label.modulate.a = alpha


## Clears all visualization elements.
func _clear_visualization() -> void:
	for line in _lines:
		if is_instance_valid(line):
			line.queue_free()
	_lines.clear()

	for highlight in _highlights:
		if is_instance_valid(highlight):
			highlight.queue_free()
	_highlights.clear()

	for label in _labels:
		if is_instance_valid(label):
			label.queue_free()
	_labels.clear()

	_current_unit = null
	visible = false


## Shows a quick coherency check with auto-hide.
func flash_coherency(game_unit: GameUnit, duration: float = 3.0, is_skirmish: bool = false) -> CoherencyChecker.CoherencyResult:
	var result = show_coherency(game_unit, is_skirmish)

	# Auto-hide after duration
	await get_tree().create_timer(duration).timeout
	hide_coherency()

	return result


## Updates visualization for current unit (call when models move).
func update() -> void:
	if _current_unit:
		show_coherency(_current_unit)
