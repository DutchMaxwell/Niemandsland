class_name RegimentFacingVisualizer
extends Node3D
## Display-only facing aids for an Age of Fantasy: Regiments movement-tray block.
## Lives as a child of the RegimentTray, so its geometry follows the tray's transform
## rigidly — the tray's local +Z is the unit's facing (RegimentFormation puts the front
## rank toward +Z). Renders:
##   • a flat facing ARROW just ahead of the front rank (always visible), and
##   • four flat ARC quadrants fanning out from the block centre (toggleable, KEY_F):
##     front, flank-left, rear, flank-right — each a 90° quadrant (±45°), per
##     AoF:R v3.5.1 p.5 "Unit Facing": each arc extends at 45°, forming four 90°
##     quadrants.
##
## No game rule is enforced. The pure helper (classify_arc) returns which quadrant a
## point lies in, so the measure tool can label a target as Front / Flank / Rear.
## Mesh/material style matches the coherency visualizer (flat, unshaded, translucent,
## no depth test) so the aids read as an overlay.

# === Constants ===

## Forward half-angle of the front arc. AoF:R v3.5.1 p.5 "Unit Facing": each of the
## four arcs (front/flank/rear) extends at 45° from its centre, forming four 90°
## quadrants. Display aid only, no rule enforced.
const FRONT_ARC_HALF_DEG := 45.0

## Arc quadrant classification (returned by classify_arc). Matches the four 90°
## quadrants around a unit's facing.
enum ArcQuadrant { FRONT, FLANK_RIGHT, REAR, FLANK_LEFT }

## How far the wedges fan out from the block centre (display only). 18″ = 3× the
## previous 6″, so the quadrants read clearly even on a 6×4 ft table.
const ARC_RADIUS_INCHES := 18.0
const INCHES_TO_METERS := 0.0254

## Flat-on-the-table heights (mirrors the coherency visualizer's flat overlays).
const ARC_Y := 0.004    # the wide wedges sit lowest
const ARROW_Y := 0.006  # the arrow rides just above the wedges

## Facing arrow geometry (metres), measured from the front edge it is anchored to.
const ARROW_LENGTH_M := 0.025   # ~1" long chevron
const ARROW_HALF_WIDTH_M := 0.012
const ARROW_GAP_M := 0.004      # clearance between the front rank and the arrow base

## Wedge tessellation: one triangle fan per quadrant, this many segments across it.
const ARC_SEGMENTS := 16

## Overlay colours (front = cyan to match the facing arrow; flanks = amber; rear = red).
const COLOR_ARROW := Color(0.20, 0.85, 0.95, 0.85)
const COLOR_FRONT := Color(0.20, 0.85, 0.95, 0.16)
const COLOR_FLANK := Color(0.95, 0.70, 0.20, 0.14)
const COLOR_REAR := Color(0.90, 0.25, 0.25, 0.16)

## Cosine tolerance so a target dead-on a quadrant boundary counts as the nearer arc
## despite float error in cos(half_angle) — ~0.08° at a 45° boundary, negligible.
const ARC_COS_EPSILON := 0.000001

# === Private state ===

var _arrow: MeshInstance3D = null
var _arcs: Array[MeshInstance3D] = []

# === Public ===

## (Re)build the aids for a block whose front rank sits at local +Z = `front_z`
## (metres, tray-local). Safe to call repeatedly (re-rank, casualties, load).
func rebuild(front_z: float) -> void:
	_clear()
	# Four quadrants in clockwise order from +Z (front): front, flank-right, rear, flank-left.
	# Each spans 90° (FRONT_ARC_HALF_DEG on either side of its centre).
	var half := deg_to_rad(FRONT_ARC_HALF_DEG)
	var centres := [0.0, PI / 2.0, PI, -PI / 2.0]
	var colors := [COLOR_FRONT, COLOR_FLANK, COLOR_REAR, COLOR_FLANK]
	for i in range(4):
		var wedge := _build_wedge(centres[i] - half, centres[i] + half, colors[i])
		_arcs.append(wedge)
		add_child(wedge)
	_arrow = _build_arrow(front_z)
	add_child(_arrow)


## Show or hide the four arc quadrants. The facing arrow stays visible regardless.
func set_arc_visible(p_visible: bool) -> void:
	for arc in _arcs:
		if arc:
			arc.visible = p_visible


## Whether the arc quadrants are currently shown.
func is_arc_visible() -> bool:
	return not _arcs.is_empty() and _arcs[0].visible


## Pure facing test: is `point_xz` within the forward arc of a block at `apex_xz`
## facing `facing_xz` (any non-zero vector), with the given half-angle? Points at the
## apex count as inside. XZ-plane only — the measure tool and tray reuse this.
static func front_arc_contains(facing_xz: Vector2, apex_xz: Vector2,
		point_xz: Vector2, half_angle_rad: float) -> bool:
	var to_point := point_xz - apex_xz
	if to_point.length_squared() < 0.0000001:
		return true
	if facing_xz.length_squared() < 0.0000001:
		return false
	var cos_to := facing_xz.normalized().dot(to_point.normalized())
	return cos_to >= cos(half_angle_rad) - ARC_COS_EPSILON


## Classify which of the four arcs `point_xz` lies in, relative to a block at
## `apex_xz` facing `facing_xz`. AoF:R v3.5.1 p.5 — front/flank/rear are 90° quadrants
## (±45°). Points at the apex count as FRONT. Returns ArcQuadrant. XZ-plane only.
static func classify_arc(facing_xz: Vector2, apex_xz: Vector2, point_xz: Vector2) -> ArcQuadrant:
	var to_point := point_xz - apex_xz
	if to_point.length_squared() < 0.0000001:
		return ArcQuadrant.FRONT
	if facing_xz.length_squared() < 0.0000001:
		return ArcQuadrant.FRONT
	# Signed angle from facing to (apex->point), in (-PI, PI].
	var facing := facing_xz.normalized()
	var dir := to_point.normalized()
	var angle := atan2(dir.x * facing.y - dir.y * facing.x, dir.dot(facing))
	# atan2(cross, dot): cross = dir.x*facing.y - dir.y*facing.x. Positive = clockwise
	# (right) when facing is +Z and dir is +X (right). Map to quadrants:
	#   FRONT       : |angle| <= 45°
	#   FLANK_RIGHT : 45° < angle <= 135°
	#   REAR        : |angle| > 135°
	#   FLANK_LEFT  : -135° <= angle < -45°
	var half := deg_to_rad(FRONT_ARC_HALF_DEG)
	if angle >= -half - ARC_COS_EPSILON and angle <= half + ARC_COS_EPSILON:
		return ArcQuadrant.FRONT
	if angle > half and angle <= PI - half + ARC_COS_EPSILON:
		return ArcQuadrant.FLANK_RIGHT
	if angle < -half and angle >= -PI + half - ARC_COS_EPSILON:
		return ArcQuadrant.FLANK_LEFT
	return ArcQuadrant.REAR


## Human-readable label for a quadrant (used by the measure tool).
static func quadrant_label(q: ArcQuadrant) -> String:
	match q:
		ArcQuadrant.FRONT:
			return "Front"
		ArcQuadrant.FLANK_RIGHT:
			return "Right Flank"
		ArcQuadrant.FLANK_LEFT:
			return "Left Flank"
		ArcQuadrant.REAR:
			return "Rear"
		_:
			return "?"

# === Private ===

func _clear() -> void:
	if _arrow and is_instance_valid(_arrow):
		_arrow.queue_free()
	for arc in _arcs:
		if arc and is_instance_valid(arc):
			arc.queue_free()
	_arrow = null
	_arcs.clear()


## Flat chevron arrowhead pointing +Z, its base anchored just ahead of the front rank.
func _build_arrow(front_z: float) -> MeshInstance3D:
	var base_z := front_z + ARROW_GAP_M
	var tip := Vector3(0.0, ARROW_Y, base_z + ARROW_LENGTH_M)
	var left := Vector3(-ARROW_HALF_WIDTH_M, ARROW_Y, base_z)
	var right := Vector3(ARROW_HALF_WIDTH_M, ARROW_Y, base_z)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_vertex(left)
	st.add_vertex(tip)
	st.add_vertex(right)

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _overlay_material(COLOR_ARROW)
	return mi


## Flat triangle fan spanning [from_rad, to_rad] around +Z, apex at the block centre.
func _build_wedge(from_rad: float, to_rad: float, color: Color) -> MeshInstance3D:
	var radius := ARC_RADIUS_INCHES * INCHES_TO_METERS
	var apex := Vector3(0.0, ARC_Y, 0.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for seg in range(ARC_SEGMENTS):
		var a0 := from_rad + (to_rad - from_rad) * (float(seg) / float(ARC_SEGMENTS))
		var a1 := from_rad + (to_rad - from_rad) * (float(seg + 1) / float(ARC_SEGMENTS))
		var p0 := Vector3(sin(a0) * radius, ARC_Y, cos(a0) * radius)
		var p1 := Vector3(sin(a1) * radius, ARC_Y, cos(a1) * radius)
		st.add_vertex(apex)
		st.add_vertex(p0)
		st.add_vertex(p1)

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _overlay_material(color)
	mi.visible = false  # toggled on with KEY_F
	return mi


func _overlay_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	return material
