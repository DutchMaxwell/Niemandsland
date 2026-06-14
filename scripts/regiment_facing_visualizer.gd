class_name RegimentFacingVisualizer
extends Node3D
## Display-only facing aids for an Age of Fantasy: Regiments movement-tray block.
## Lives as a child of the RegimentTray, so its geometry follows the tray's transform
## rigidly — the tray's local +Z is the unit's facing (RegimentFormation puts the front
## rank toward +Z). Renders:
##   • a flat facing ARROW just ahead of the front rank (always visible), and
##   • a flat front-ARC wedge fanning out from the block centre (toggleable).
##
## No game rule is enforced. The front arc is the forward half-plane (±FRONT_ARC_HALF_DEG
## of facing) — the standard front/flank/rear boundary in rank-and-flank games — exposed
## as a pure helper (front_arc_contains) the measure tool reuses to label a target as
## front or flank/rear. Mesh/material style matches the coherency visualizer (flat,
## unshaded, translucent, no depth test) so the aids read as an overlay.

# === Constants ===

## Forward half-angle of the front arc. 90° => the full forward 180° half-plane, the
## conventional "front" in rank-and-flank games. Display aid only, no rule enforced.
const FRONT_ARC_HALF_DEG := 90.0

## How far the wedge fans out from the block centre (display only).
const ARC_RADIUS_INCHES := 6.0
const INCHES_TO_METERS := 0.0254

## Flat-on-the-table heights (mirrors the coherency visualizer's flat overlays).
const ARC_Y := 0.004    # the wide wedge sits lowest
const ARROW_Y := 0.006  # the arrow rides just above the wedge

## Facing arrow geometry (metres), measured from the front edge it is anchored to.
const ARROW_LENGTH_M := 0.025   # ~1" long chevron
const ARROW_HALF_WIDTH_M := 0.012
const ARROW_GAP_M := 0.004      # clearance between the front rank and the arrow base

## Wedge tessellation: one triangle fan, this many segments across the arc.
const ARC_SEGMENTS := 24

## Overlay colours (Tactical-HUD cyan facing arrow, amber front arc).
const COLOR_ARROW := Color(0.20, 0.85, 0.95, 0.85)
const COLOR_ARC := Color(0.95, 0.70, 0.20, 0.18)

## Cosine tolerance so a target dead-abeam (exactly on the arc boundary) counts as
## front despite float error in cos(half_angle) — ~0.08° at a 90° boundary, negligible.
const ARC_COS_EPSILON := 0.000001

# === Private state ===

var _arrow: MeshInstance3D = null
var _arc: MeshInstance3D = null

# === Public ===

## (Re)build the aids for a block whose front rank sits at local +Z = `front_z`
## (metres, tray-local). Safe to call repeatedly (re-rank, casualties, load).
func rebuild(front_z: float) -> void:
	_clear()
	_arc = _build_arc()
	add_child(_arc)
	_arrow = _build_arrow(front_z)
	add_child(_arrow)


## Show or hide the front-arc wedge. The facing arrow stays visible regardless.
func set_arc_visible(p_visible: bool) -> void:
	if _arc:
		_arc.visible = p_visible


## Whether the front-arc wedge is currently shown.
func is_arc_visible() -> bool:
	return _arc != null and _arc.visible


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

# === Private ===

func _clear() -> void:
	if _arrow and is_instance_valid(_arrow):
		_arrow.queue_free()
	if _arc and is_instance_valid(_arc):
		_arc.queue_free()
	_arrow = null
	_arc = null


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


## Flat triangle fan spanning ±FRONT_ARC_HALF_DEG around +Z, apex at the block centre.
func _build_arc() -> MeshInstance3D:
	var radius := ARC_RADIUS_INCHES * INCHES_TO_METERS
	var half := deg_to_rad(FRONT_ARC_HALF_DEG)
	var apex := Vector3(0.0, ARC_Y, 0.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for seg in range(ARC_SEGMENTS):
		# Sweep from +Z (centre of the arc) symmetrically out to ±half.
		var a0 := -half + (2.0 * half) * (float(seg) / float(ARC_SEGMENTS))
		var a1 := -half + (2.0 * half) * (float(seg + 1) / float(ARC_SEGMENTS))
		var p0 := Vector3(sin(a0) * radius, ARC_Y, cos(a0) * radius)
		var p1 := Vector3(sin(a1) * radius, ARC_Y, cos(a1) * radius)
		st.add_vertex(apex)
		st.add_vertex(p0)
		st.add_vertex(p1)

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _overlay_material(COLOR_ARC)
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
