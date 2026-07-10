class_name SeparationVisualizer
extends Node3D
## Non-modal visual warning for the OPR 1" unit-separation rule (GF/AoF Advanced
## Rules v3.5.1, p.7 "General Movement": a model may never be within 1" of models
## from OTHER units — any other unit, friendly included — unless charging). While a
## model / regiment tray is dragged, and on drop, any of its bases violating that
## rule is flagged with a pulsing ring on BOTH bases plus a base-edge-to-base-edge
## line and the gap in inches. Two tints tell the player at a glance whose line the
## conflict is with: RED = enemy unit (contact exempt — that is melee), AMBER =
## friendly other unit (no legal contact; sub-1" including contact warns).
##
## This mirrors CoherencyVisualizer: same highlight / surface-line / flat-label
## visual language, the same "show at full opacity without re-running the fade each
## frame" live-update model, and the same self-hiding when there is nothing to warn
## about. Rendering is strictly LOCAL — no network state, no RPCs. It reuses
## CoherencyChecker.get_ground_edge_point() for base-edge endpoints so the warning
## line matches the in-game measurement tool exactly.
##
## The 1" measurement itself lives in SeparationChecker (pure, tested); this class
## only renders results the caller hands it.

# ===== Constants =====

## Enemy-violation red (matches CoherencyVisualizer.COLOR_ERROR — "red = problem").
const COLOR_WARN_ENEMY := Color(0.9, 0.2, 0.2, 0.9)

## Friendly-violation amber (matches the Tactical-HUD amber warning accent), so a
## conflict with your OWN line is visually distinct from one with the enemy's.
const COLOR_WARN_FRIENDLY := Color(0.95, 0.65, 0.1, 0.9)

## Table-surface heights (flat on the table, like the measurement tool / coherency).
const LINE_Y := 0.005
const EDGE_Y := 0.02

## Flat line thickness on the XZ plane.
const LINE_WIDTH := 0.002

## Ring sizing relative to the base radius (metres): gap outside the base, then thickness.
const RING_GAP_M := 0.003
const RING_THICKNESS_M := 0.005

## Height (metres) at which rings sit on the table.
const RING_Y := 0.004

## Max opacity of the whole warning so it stays a hint, not a wall of red.
const MAX_ALPHA := 0.35

## Animation timings (seconds).
const FADE_DURATION := 0.3
const PULSE_DURATION := 1.0

## Default fallback base radius (metres) — 32 mm diameter, matches CoherencyChecker.
const DEFAULT_BASE_RADIUS_M := 0.016

# ===== Result Object =====

## One flagged model pair: a moved model violating the 1" separation against a model
## of ANOTHER unit, the measured edge gap in inches, and whether the other unit is
## FRIENDLY (same army -> amber; enemy/unknown -> red). Typed object over a loose
## dictionary per CODING_STANDARDS §5.2.
class ViolationPair:
	var moved: ModelInstance = null
	var other: ModelInstance = null
	var distance_inches: float = 0.0
	var is_friendly: bool = false

	func _init(p_moved: ModelInstance, p_other: ModelInstance, p_distance: float, p_is_friendly: bool = false) -> void:
		moved = p_moved
		other = p_other
		distance_inches = p_distance
		is_friendly = p_is_friendly

# ===== Private State =====

var _lines: Array[MeshInstance3D] = []
var _rings: Array[Node3D] = []
var _labels: Array[Label3D] = []
var _tween: Tween = null

## Custom alpha for the 3D fade (Node3D has no modulate).
var _alpha: float = 1.0:
	set(value):
		_alpha = value
		_update_materials_alpha(value)


func _ready() -> void:
	visible = false


# ===== Public Methods =====

## Renders the warning for the given flagged pairs. Pass an empty array to clear /
## fade out (a compliant drop). animate=false for live drag updates so the ring's
## pulse and the fade don't restart every frame (mirrors CoherencyVisualizer).
func show_violations(pairs: Array, animate: bool = false) -> void:
	_clear()

	if pairs.is_empty():
		# Nothing to warn about: fade out if we were showing, else stay hidden.
		if visible:
			hide_warning()
		return

	# Pass 1: draw the gap lines and resolve one ring colour per distinct base (a
	# base can be flagged against several units; an ENEMY conflict outranks a
	# friendly one, so red dominates amber on a shared ring).
	var ring_colors: Dictionary = {}  # instance_id -> Color
	var ring_models: Dictionary = {}  # instance_id -> ModelInstance
	for pair in pairs:
		var vp := pair as ViolationPair
		if vp == null or vp.moved == null or vp.other == null:
			continue
		if not _models_drawable(vp.moved, vp.other):
			continue
		var color := COLOR_WARN_FRIENDLY if vp.is_friendly else COLOR_WARN_ENEMY
		_register_ring(vp.moved, color, ring_colors, ring_models)
		_register_ring(vp.other, color, ring_colors, ring_models)
		_draw_gap_line(vp.moved, vp.other, vp.distance_inches, color)

	# Pass 2: one ring per flagged base, in its resolved colour.
	for key in ring_models:
		_highlight_model(ring_models[key], ring_colors[key], animate)

	visible = true
	if animate:
		_animate_fade_in()
	else:
		# Live update: full opacity without re-running the fade each frame.
		if _tween:
			_tween.kill()
			_tween = null
		_alpha = 1.0


## Fades the warning out and clears it (used after a compliant drop / deselection).
func hide_warning() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_alpha", 0.0, FADE_DURATION)
	_tween.tween_callback(_clear)


# ===== Private Methods =====

## Records a model's ring colour (dedup across pairs; enemy red outranks amber).
func _register_ring(model: ModelInstance, color: Color, ring_colors: Dictionary, ring_models: Dictionary) -> void:
	var key := model.get_instance_id()
	if ring_colors.has(key) and ring_colors[key] == COLOR_WARN_ENEMY:
		return  # already red — an enemy conflict outranks a friendly one
	ring_colors[key] = color
	ring_models[key] = model


## Returns true if both models have valid nodes inside the scene tree.
func _models_drawable(model_a: ModelInstance, model_b: ModelInstance) -> bool:
	if not model_a.node or not model_b.node:
		return false
	if not is_instance_valid(model_a.node) or not is_instance_valid(model_b.node):
		return false
	return model_a.node.is_inside_tree() and model_b.node.is_inside_tree()


## Draws a tinted base-edge-to-base-edge line with the gap label between two models.
func _draw_gap_line(model_a: ModelInstance, model_b: ModelInstance, dist_inches: float, color: Color) -> void:
	var from_edge := CoherencyChecker.get_ground_edge_point(model_a, model_b.node.global_position, EDGE_Y)
	var to_edge := CoherencyChecker.get_ground_edge_point(model_b, model_a.node.global_position, EDGE_Y)

	var line := _create_surface_line(from_edge, to_edge, color)
	if line:
		add_child(line)
		_lines.append(line)

	var midpoint := (from_edge + to_edge) / 2.0
	_create_distance_label(midpoint, from_edge, to_edge, "%.1f\"" % dist_inches, color)


## A thin flat line strip lying on the table between two base-edge points.
func _create_surface_line(from_edge: Vector3, to_edge: Vector3, color: Color) -> MeshInstance3D:
	var direction := Vector3(to_edge.x - from_edge.x, 0, to_edge.z - from_edge.z)
	var length := direction.length()
	if length < 0.001:
		return null

	var mesh_instance := MeshInstance3D.new()
	var line_mesh := BoxMesh.new()
	line_mesh.size = Vector3(length, 0.001, LINE_WIDTH)
	mesh_instance.mesh = line_mesh

	var midpoint := (from_edge + to_edge) / 2.0
	midpoint.y = LINE_Y
	mesh_instance.position = midpoint
	mesh_instance.rotation = Vector3(0, atan2(direction.x, direction.z) + PI / 2.0, 0)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	mesh_instance.material_override = material
	return mesh_instance


## A distance label lying flat on the table, aligned with the line (measurement-tool style).
func _create_distance_label(midpoint: Vector3, from_edge: Vector3, to_edge: Vector3, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = true
	label.render_priority = 1
	label.pixel_size = 0.0005
	label.font_size = 24
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 1)
	label.outline_size = 4
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	add_child(label)
	label.global_position = Vector3(midpoint.x, EDGE_Y, midpoint.z)

	var direction := to_edge - from_edge
	var angle := atan2(direction.x, direction.z)
	label.rotation = Vector3(-PI / 2.0, angle, 0)
	_labels.append(label)


## Draws a coloured ring around a model's base (mirrors CoherencyVisualizer._highlight_model).
func _highlight_model(model: ModelInstance, color: Color, pulse: bool) -> void:
	if not model.node or not is_instance_valid(model.node):
		return
	if not model.node.is_inside_tree():
		return

	var base_radius_m := DEFAULT_BASE_RADIUS_M
	if model.unit:
		var game_unit := model.unit as GameUnit
		if game_unit and game_unit.unit_properties:
			var model_tough: int = int(model.properties.get("tough", 0)) if model.properties else 0
			var base_mm: int = OPRArmyManager.model_base_long_mm(int(game_unit.unit_properties.get("base_size_round", 32)), model_tough)
			base_radius_m = (base_mm / 2.0) * 0.001

	var ring := Node3D.new()
	ring.name = "SeparationRing_%d" % model.get_instance_id()

	var torus := TorusMesh.new()
	torus.inner_radius = base_radius_m + RING_GAP_M
	torus.outer_radius = base_radius_m + RING_GAP_M + RING_THICKNESS_M

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = torus

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material
	ring.add_child(mesh_instance)

	add_child(ring)
	var model_pos := model.node.global_position
	ring.global_position = Vector3(model_pos.x, RING_Y, model_pos.z)
	_rings.append(ring)

	if pulse:
		mesh_instance.ready.connect(func(): _animate_pulse(mesh_instance), CONNECT_ONE_SHOT)


## Pulses a ring mesh (finite loops to avoid the Godot infinite-loop tween error).
func _animate_pulse(mesh: MeshInstance3D) -> void:
	if not mesh or not is_instance_valid(mesh):
		return
	if not mesh.is_inside_tree():
		return
	var tween := mesh.create_tween()
	tween.set_loops(100)
	tween.tween_property(mesh, "scale", Vector3(1.2, 1.2, 1.2), PULSE_DURATION / 2)
	tween.tween_property(mesh, "scale", Vector3(1.0, 1.0, 1.0), PULSE_DURATION / 2)


## Fades the whole warning in.
func _animate_fade_in() -> void:
	_alpha = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_alpha", 1.0, FADE_DURATION)


## Applies alpha (capped at MAX_ALPHA) to every element's material.
func _update_materials_alpha(alpha: float) -> void:
	var a := alpha * MAX_ALPHA
	for line in _lines:
		if is_instance_valid(line) and line.material_override:
			var mat := line.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = a
	for ring in _rings:
		if is_instance_valid(ring):
			for child in ring.get_children():
				if child is MeshInstance3D and child.material_override:
					var mat := child.material_override as StandardMaterial3D
					if mat:
						mat.albedo_color.a = a
	for label in _labels:
		if is_instance_valid(label):
			label.modulate.a = a


## Frees all rendered elements.
func _clear() -> void:
	for line in _lines:
		if is_instance_valid(line):
			line.queue_free()
	_lines.clear()

	for ring in _rings:
		if is_instance_valid(ring):
			ring.queue_free()
	_rings.clear()

	for label in _labels:
		if is_instance_valid(label):
			label.queue_free()
	_labels.clear()

	visible = false
