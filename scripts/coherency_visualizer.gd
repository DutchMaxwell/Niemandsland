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

## Line height above ground
const LINE_HEIGHT := 0.03

## Animation duration
const FADE_DURATION := 0.3
const PULSE_DURATION := 1.0

## Current visualization elements
var _lines: Array[MeshInstance3D] = []
var _highlights: Array[Node3D] = []
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
func show_coherency(game_unit: GameUnit, is_skirmish: bool = false) -> CoherencyChecker.CoherencyResult:
	_clear_visualization()
	_current_unit = game_unit

	# Check coherency
	var result = CoherencyChecker.check_unit_coherency(game_unit, is_skirmish)

	# Get alive models
	var models = game_unit.get_alive_models()
	if models.size() <= 1:
		visible = false
		visualization_completed.emit(result)
		return result

	# Only highlight isolated models (no lines between all models)
	if not result.valid:
		for issue in result.issues:
			if issue.type == CoherencyChecker.IssueType.ISOLATED and issue.model:
				_highlight_model(issue.model, COLOR_ERROR)
		# Animate in only if there are issues
		visible = true
		_animate_fade_in()
	else:
		visible = false

	visualization_completed.emit(result)
	return result


## Hides the coherency visualization.
func hide_coherency() -> void:
	if _tween:
		_tween.kill()

	_tween = create_tween()
	_tween.tween_property(self, "_visualization_alpha", 0.0, FADE_DURATION)
	_tween.tween_callback(_clear_visualization)


## Creates lines between models showing coherency status.
func _create_coherency_lines(models: Array[ModelInstance]) -> void:
	for i in range(models.size()):
		for j in range(i + 1, models.size()):
			var model_a = models[i]
			var model_b = models[j]

			if not model_a.node or not model_b.node:
				continue
			if not model_a.node.is_inside_tree() or not model_b.node.is_inside_tree():
				continue

			var dist = CoherencyChecker._distance_between_models(model_a, model_b)

			# Determine coherency distance
			var coherency_dist = CoherencyChecker.COHERENCY_DISTANCE_INCHES
			if CoherencyChecker._is_elevated_different(model_a, model_b):
				coherency_dist = CoherencyChecker.ELEVATED_COHERENCY_INCHES

			# Only draw lines for models within reasonable distance
			if dist > coherency_dist * 3:
				continue

			# Determine line color
			var color: Color
			if dist <= coherency_dist:
				color = COLOR_OK
			elif dist <= coherency_dist * 1.5:
				color = COLOR_WARNING
			else:
				color = COLOR_ERROR

			var line = _create_line_mesh(
				model_a.node.global_position,
				model_b.node.global_position,
				color
			)
			add_child(line)
			_lines.append(line)


## Creates a line mesh between two points.
func _create_line_mesh(from: Vector3, to: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	# Adjust height
	var from_adj = from + Vector3(0, LINE_HEIGHT, 0)
	var to_adj = to + Vector3(0, LINE_HEIGHT, 0)

	# Create cylinder as line
	var direction = to_adj - from_adj
	var length = direction.length()

	if length < 0.001:
		return mesh_instance

	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.003
	cylinder.bottom_radius = 0.003
	cylinder.height = length

	mesh_instance.mesh = cylinder

	# Calculate position and rotation WITHOUT needing to be in tree
	# Position at midpoint (use position, not global_position since not in tree yet)
	var midpoint = (from_adj + to_adj) / 2
	mesh_instance.position = midpoint

	# Calculate rotation to align cylinder with direction
	var forward = direction.normalized()
	var up = Vector3.UP
	if abs(forward.dot(up)) > 0.999:
		up = Vector3.FORWARD

	# Build rotation basis manually instead of using look_at
	var right = up.cross(forward).normalized()
	var actual_up = forward.cross(right).normalized()
	var basis = Basis(right, forward, actual_up)
	mesh_instance.basis = basis

	# Material
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material

	return mesh_instance


## Highlights a model with a colored ring.
func _highlight_model(model: ModelInstance, color: Color) -> void:
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
	highlight.name = "Highlight_%d" % model.model_index

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
