class_name SeparationVisualizer
extends Node3D
## Non-modal ZONE-WALL warning for the OPR 1" unit-separation rule (GF/AoF Advanced
## Rules v3.5.1, p.7 "General Movement": a model may never be within 1" of models from
## OTHER units — any other unit, friendly included — unless charging). Instead of
## per-model rings, each nearby foreign UNIT is wrapped in a translucent, ground-level
## PROTECTIVE WALL: a band exactly 1" wide hugging the merged outline of that unit's
## bases, showing its no-go area at a glance. RED = enemy unit (contact exempt — that
## is a Charge into melee), ORANGE/AMBER = friendly unit (no legal contact).
##
## PROACTIVE: while a model / regiment is dragged, any foreign unit the dragged base
## could plausibly reach fades its wall IN (proximity, ~3"); an ACTUAL violation
## intensifies and pulses. Walls fade out after a compliant drop and persist on a
## violation. Caller (main.gd) decides which units are in range / violating and hands
## this a ZoneSpec per unit; the band GEOMETRY is SeparationZone, the distance math is
## SeparationChecker. Rendering is strictly LOCAL — no network state, no RPCs.
##
## PERFORMANCE: the band mesh is built once per unit and cached, keyed by a signature of
## its member positions, so a static foreign unit's wall is not rebuilt each frame; only
## its alpha / colour animate. Fades and the violation pulse are driven allocation-free
## in _process (which is disabled whenever no wall is on screen).

# ===== Constants =====

## Enemy red (matches CoherencyVisualizer.COLOR_ERROR — "red = problem").
const COLOR_ENEMY := Color(0.9, 0.2, 0.2)

## Friendly amber (Tactical-HUD warning accent) — a conflict with your OWN line reads
## distinct from one with the enemy's.
const COLOR_FRIENDLY := Color(0.95, 0.65, 0.1)

## Ground height (metres) the band sits at — above the table, below the minis so their
## bases occlude it and the wall reads as hugging the ground.
const BAND_Y := 0.006

## Peak opacity of a merely-nearby (proactive) wall — a soft hint.
const MAX_ALPHA_PROACTIVE := 0.16

## Peak opacity of a violating wall — brighter, and it pulses.
const MAX_ALPHA_VIOLATION := 0.36

## Fraction of peak a violating wall dims to at the bottom of its pulse.
const PULSE_MIN_FACTOR := 0.45

## Emissive glow multiplier at full opacity (additive-like readability on any biome).
const EMISSION_ENERGY := 1.4

## Fade in/out duration (seconds) — how long a wall takes to reach full / zero alpha.
const FADE_DURATION := 0.25

## Violation pulse angular speed (radians/second); ~1 s per breath.
const PULSE_SPEED := TAU / 1.1

## Numerical guard for near-zero lengths (metres).
const EPSILON_M := 0.00001

# --- Retreat ruler (violation only) ---
## When a wall is BLINKING (an active sub-1" violation), a bright measured line is drawn
## between the two offending base EDGES (the nearest pair), labelled with the live edge
## GAP and the 1" target, so the player sees exactly how deep inside the zone they are and
## which way to back out. The line + label are built once and CACHED — a drag frame only
## updates their transform + text. Colour matches the offending wall (red enemy / amber
## friendly). Local render only; driven by main.gd, which finds the nearest violating pair.

## Ruler line height above the table (metres) — just above the 1" band (BAND_Y).
const RULER_LINE_Y := 0.012

## Ruler line vertical thinness / on-table thickness (metres): a flat 1 mm x 3 mm ribbon.
const RULER_LINE_THIN := 0.001
const RULER_LINE_WIDTH := 0.003

## Ruler label height above the table (metres) — above the line, below the minis.
const RULER_LABEL_Y := 0.02

## Ruler label sizing (mirrors the measurement tool's Label3D for a consistent look).
const RULER_LABEL_PIXEL_SIZE := 0.001
const RULER_LABEL_FONT_SIZE := 22
const RULER_LABEL_OUTLINE := 8

## Render priorities: draw the ruler (and its label above it) over the ground band + decals.
const RULER_RENDER_PRIORITY := 20
const RULER_LABEL_PRIORITY := 21


# ===== Zone Spec (input) =====

## One foreign unit to wall off: its member base shapes (for the band geometry), whether
## it is FRIENDLY (amber) or enemy/unknown (red), whether the current drag actually
## VIOLATES the 1" rule against it (brighter + pulsing), and a signature of its member
## positions so the cached mesh rebuilds only when the unit's members move.
class ZoneSpec:
	var unit_id: int = 0
	var shapes: Array = []
	var is_friendly: bool = false
	var is_violation: bool = false
	var signature: float = 0.0

	func _init(p_unit_id: int, p_shapes: Array, p_is_friendly: bool, p_is_violation: bool, p_signature: float) -> void:
		unit_id = p_unit_id
		shapes = p_shapes
		is_friendly = p_is_friendly
		is_violation = p_is_violation
		signature = p_signature


# ===== Per-Unit Wall (state) =====

class Wall:
	var node: MeshInstance3D = null
	var material: StandardMaterial3D = null
	var color: Color = COLOR_ENEMY
	var is_violation: bool = false
	var retiring: bool = false      # not in the latest zone set -> fading out to free
	var signature: float = 0.0      # member-position hash the current mesh was built from
	var alpha: float = 0.0          # current animated alpha (0..MAX_ALPHA_VIOLATION)
	var target_alpha: float = 0.0   # steady-state target (pulse rides on top for violations)


# ===== Private State =====

var _walls: Dictionary = {}     # unit_id -> Wall
var _pulse_phase: float = 0.0

# Cached retreat-ruler nodes (built lazily on the first violation; only transform + text
# update afterwards).
var _ruler_line: MeshInstance3D = null
var _ruler_line_mesh: BoxMesh = null
var _ruler_material: StandardMaterial3D = null
var _ruler_label: Label3D = null
var _ruler_last_text: String = ""


func _ready() -> void:
	visible = false
	set_process(false)


# ===== Public Methods =====

## Show/refresh walls for the given foreign units (ZoneSpec array). Units absent from
## the array fade out and free; present units fade in (and pulse if violating). An empty
## array fades everything out. Cheap to call every drag frame — a static unit's mesh is
## reused via its signature.
func show_zones(zones: Array) -> void:
	var present: Dictionary = {}
	for z in zones:
		var spec := z as ZoneSpec
		if spec == null:
			continue
		present[spec.unit_id] = true
		var wall: Wall = _walls.get(spec.unit_id)
		if wall == null:
			wall = Wall.new()
			_walls[spec.unit_id] = wall
			_rebuild_mesh(wall, spec)
		elif not is_equal_approx(wall.signature, spec.signature):
			_rebuild_mesh(wall, spec)
		wall.color = COLOR_FRIENDLY if spec.is_friendly else COLOR_ENEMY
		wall.is_violation = spec.is_violation
		wall.retiring = false
		wall.target_alpha = MAX_ALPHA_VIOLATION if spec.is_violation else MAX_ALPHA_PROACTIVE

	for unit_id in _walls:
		if not present.has(unit_id):
			var wall: Wall = _walls[unit_id]
			wall.retiring = true
			wall.target_alpha = 0.0

	if not _walls.is_empty():
		visible = true
		set_process(true)


## Show the retreat ruler between two base-edge witness points (world XZ, metres),
## labelled with the current edge GAP (inches) and the 1" target. Colour matches the
## offending wall — red enemy / amber friendly. Lazily builds the cached line + label; a
## repeat call only updates their transform + text. `gap_inches` is clamped to 0 for
## display (a mid-drag overlap reads as touching, 0.0"), while the target stays 1.0".
func set_retreat_ruler(from_xz: Vector2, to_xz: Vector2, gap_inches: float, is_friendly: bool) -> void:
	if _ruler_line == null:
		_build_ruler()
	var from3 := Vector3(from_xz.x, RULER_LINE_Y, from_xz.y)
	var to3 := Vector3(to_xz.x, RULER_LINE_Y, to_xz.y)
	var flat := Vector2(to3.x - from3.x, to3.z - from3.z)
	var length := flat.length()
	if length < EPSILON_M:
		clear_retreat_ruler()  # degenerate (concentric bases) -> nothing to draw
		return

	_ruler_line.visible = true
	_ruler_label.visible = true
	visible = true  # a violation always co-occurs with a wall, but be explicit

	_ruler_line_mesh.size = Vector3(length, RULER_LINE_THIN, RULER_LINE_WIDTH)
	var mid := (from3 + to3) * 0.5
	_ruler_line.global_position = mid
	var angle := atan2(flat.x, flat.y)
	_ruler_line.rotation = Vector3(0.0, angle + PI * 0.5, 0.0)

	var col := COLOR_FRIENDLY if is_friendly else COLOR_ENEMY
	_ruler_material.albedo_color = Color(col.r, col.g, col.b, 1.0)
	_ruler_material.emission = col

	var shown := maxf(gap_inches, 0.0)
	var text := "%.1f\" / %.1f\"" % [shown, SeparationChecker.SEPARATION_DISTANCE_INCHES]
	if text != _ruler_last_text:
		_ruler_label.text = text
		_ruler_last_text = text
	_ruler_label.global_position = Vector3(mid.x, RULER_LABEL_Y, mid.z)
	_ruler_label.rotation = Vector3(-PI * 0.5, angle, 0.0)


## Hide the retreat ruler (no active violation). Cheap; keeps the cached nodes for reuse.
func clear_retreat_ruler() -> void:
	_ruler_last_text = ""
	if _ruler_line != null:
		_ruler_line.visible = false
	if _ruler_label != null:
		_ruler_label.visible = false


# ===== Private Methods =====


## Builds the cached retreat-ruler line + label (once, on the first violation).
func _build_ruler() -> void:
	_ruler_material = StandardMaterial3D.new()
	_ruler_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ruler_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ruler_material.no_depth_test = true
	_ruler_material.emission_enabled = true
	_ruler_material.render_priority = RULER_RENDER_PRIORITY

	_ruler_line_mesh = BoxMesh.new()
	_ruler_line = MeshInstance3D.new()
	_ruler_line.name = "SeparationRetreatRuler"
	_ruler_line.mesh = _ruler_line_mesh
	_ruler_line.material_override = _ruler_material
	_ruler_line.visible = false
	add_child(_ruler_line)

	_ruler_label = Label3D.new()
	_ruler_label.name = "SeparationRetreatRulerLabel"
	_ruler_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_ruler_label.no_depth_test = true
	_ruler_label.render_priority = RULER_LABEL_PRIORITY
	_ruler_label.pixel_size = RULER_LABEL_PIXEL_SIZE
	_ruler_label.font_size = RULER_LABEL_FONT_SIZE
	_ruler_label.outline_size = RULER_LABEL_OUTLINE
	_ruler_label.modulate = Color.WHITE
	_ruler_label.outline_modulate = Color.BLACK
	_ruler_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ruler_label.visible = false
	add_child(_ruler_label)

func _process(delta: float) -> void:
	_pulse_phase = fmod(_pulse_phase + delta * PULSE_SPEED, TAU)
	var pulse := 0.5 + 0.5 * sin(_pulse_phase)  # 0..1
	var fade_step := (MAX_ALPHA_VIOLATION / FADE_DURATION) * delta
	var to_free: Array = []

	for unit_id in _walls:
		var wall: Wall = _walls[unit_id]
		var target := wall.target_alpha
		if wall.is_violation and not wall.retiring:
			# Pulse between the min factor and full violation alpha.
			target = lerpf(MAX_ALPHA_VIOLATION * PULSE_MIN_FACTOR, MAX_ALPHA_VIOLATION, pulse)
		wall.alpha = move_toward(wall.alpha, target, fade_step)
		_apply(wall)
		if wall.retiring and wall.alpha <= 0.001:
			to_free.append(unit_id)

	for unit_id in to_free:
		var wall: Wall = _walls[unit_id]
		if is_instance_valid(wall.node):
			wall.node.queue_free()
		_walls.erase(unit_id)

	if _walls.is_empty():
		visible = false
		set_process(false)


## Applies a wall's current colour + animated alpha to its material.
func _apply(wall: Wall) -> void:
	if wall.material == null:
		return
	wall.material.albedo_color = Color(wall.color.r, wall.color.g, wall.color.b, wall.alpha)
	wall.material.emission = wall.color
	wall.material.emission_energy_multiplier = EMISSION_ENERGY * (wall.alpha / MAX_ALPHA_VIOLATION)


## Builds (or rebuilds) a wall's band mesh from the unit's member shapes.
func _rebuild_mesh(wall: Wall, spec: ZoneSpec) -> void:
	var tris := SeparationZone.unit_band_triangles(spec.shapes)
	if wall.node == null:
		wall.node = MeshInstance3D.new()
		wall.node.name = "SeparationWall_%d" % spec.unit_id
		wall.material = _make_material()
		wall.node.material_override = wall.material
		add_child(wall.node)
	wall.node.mesh = _mesh_from_triangles(tris)
	wall.signature = spec.signature


## A flat, unshaded, emissive, double-sided translucent material for the ground band.
func _make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.albedo_color = Color(1, 1, 1, 0)
	return mat


## Non-indexed ArrayMesh from a world-XZ triangle soup, laid flat at BAND_Y.
func _mesh_from_triangles(tris: PackedVector2Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if tris.size() < 3:
		return mesh
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(tris.size())
	normals.resize(tris.size())
	for i in range(tris.size()):
		verts[i] = Vector3(tris[i].x, BAND_Y, tris[i].y)
		normals[i] = Vector3.UP
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
