class_name RegimentTray
extends StaticBody3D
## A persistent movement-tray block for Age of Fantasy: Regiments. It parents the
## unit's model nodes and lays them out in ranks-and-files (RegimentFormation), so
## the whole regiment moves and rotates as ONE rigid object — the tray's local +Z is
## the unit's facing. This is representation/handling only; no game rules are enforced.
##
## Member model nodes keep their own colliders and stay in the "miniature"/"opr_unit"
## groups (measure tool, unit card, casualties still work); each gets a "regiment_tray"
## meta back-pointer so a click on a model can resolve to its tray for selection.

# === Constants ===

const GROUP := "regiment_tray"
const MEMBER_META := "regiment_tray"

## Clearance (metres) added past the front-most model slot so the facing arrow anchors
## just ahead of the front rank's base edge (~half a 25 mm base).
const FRONT_EDGE_MARGIN_M := 0.0125

# === Public state ===

var frontage: int = 5

# === Private state ===

## Display-only facing aids (arrow + toggleable arc quadrants); rebuilt on layout.
var _facing_viz: RegimentFacingVisualizer = null

# === Godot ===

func _ready() -> void:
	add_to_group(GROUP)
	add_to_group("selectable")

# === Public ===

## Adopt `models` into this tray and rank them at `new_frontage`. The tray is placed
## at the models' current XZ centroid so the block forms in place; each model is
## reparented and snapped to its rank-and-file slot, facing the tray's +Z.
func form(models: Array, footprints: Array, new_frontage: int) -> void:
	frontage = maxi(new_frontage, 1)
	if models.is_empty():
		return
	var centroid := Vector3.ZERO
	for m in models:
		centroid += (m as Node3D).global_position
	centroid /= float(models.size())
	centroid.y = 0.0
	global_position = centroid
	_layout(models, footprints)

## Re-rank the (possibly reduced) member set in place — used after casualties or a
## frontage change. Keeps the tray's transform (facing/position) untouched.
func reform(models: Array, footprints: Array, new_frontage: int = -1) -> void:
	if new_frontage > 0:
		frontage = new_frontage
	_layout(models, footprints)

## The unit's facing direction in world space (local +Z).
func facing_dir() -> Vector3:
	return global_transform.basis.z.normalized()


## Project a horizontal drag delta onto a regiment's facing axis (XZ-plane), so the
## block moves only forward/backward along its facing when the player holds Shift
## during a drag. AoF:R v3.5.1 p.8: Rush/Charge are forward-only, Advance allows
## sideways/backward by up to half move — the Shift-lock gives the player the
## forward/backward-only axis; whether the move is legal is the player's call
## (sandbox, "show, don't decide"). `facing_xz` is the world-space facing (any
## non-zero vector); the Y component is ignored.
static func project_drag_onto_facing(delta_xz: Vector3, facing_xz: Vector3) -> Vector3:
	var f := Vector3(facing_xz.x, 0.0, facing_xz.z)
	if f.length_squared() < 0.0000001:
		return delta_xz  # degenerate facing — fall back to unconstrained drag
	f = f.normalized()
	return f * delta_xz.dot(f)


## The nearest quarter-turn (0, 90, 180, 270 degrees) to `rotation_y` (radians).
## AoF:R v3.5.1 p.8 "Pivoting": a Hold action may pivot up to 180°, a Move action
## up to 90° — the four cardinal facings are the natural snap targets. Used by the
## Ctrl+R snap-to-90° shortcut so the player can quickly align a regiment to a
## cardinal facing. Returns the snap angle in radians, in [0, 2*PI).
static func nearest_quarter_turn(rotation_y: float) -> float:
	const QUARTER := PI / 2.0
	# Normalise to [0, 2*PI) before snapping so the result is deterministic.
	var normalized := fmod(rotation_y, TAU)
	if normalized < 0.0:
		normalized += TAU
	var snapped: float = round(normalized / QUARTER) * QUARTER
	# A snap to 2*PI (e.g. -0.2 -> 6.08 -> 2*PI) is equivalent to 0; normalise the
	# result back into [0, 2*PI) so the canonical representative is returned.
	return fmod(snapped, TAU)

## Show or hide the front-arc wedge on this block (display only; the facing arrow
## stays visible). No-op until the block has been laid out at least once.
func set_arc_visible(p_visible: bool) -> void:
	if _facing_viz:
		_facing_viz.set_arc_visible(p_visible)


## Whether the 45° arc quadrants are currently shown on this block.
func is_arc_visible() -> bool:
	return _facing_viz != null and _facing_viz.is_arc_visible()


## Whether `world_point` lies within this block's forward arc (front vs flank/rear).
## Display aid for the measure tool — no rule is enforced.
func arc_contains(world_point: Vector3) -> bool:
	var facing := facing_dir()
	return RegimentFacingVisualizer.front_arc_contains(
		Vector2(facing.x, facing.z),
		Vector2(global_position.x, global_position.z),
		Vector2(world_point.x, world_point.z),
		deg_to_rad(RegimentFacingVisualizer.FRONT_ARC_HALF_DEG))


## Which of the four arcs (front/flank-left/rear/flank-right) `world_point` lies in,
## relative to this block's facing. AoF:R v3.5.1 p.5 "Unit Facing" — four 90° quadrants.
## Display aid for the measure tool; no rule is enforced.
func classify_arc(world_point: Vector3) -> RegimentFacingVisualizer.ArcQuadrant:
	var facing := facing_dir()
	return RegimentFacingVisualizer.classify_arc(
		Vector2(facing.x, facing.z),
		Vector2(global_position.x, global_position.z),
		Vector2(world_point.x, world_point.z))

## Re-rank the regiment from its game unit's currently-alive models (used after a
## casualty or revive — the rear rank closes/opens). Keeps the tray transform.
func reform_from_unit(game_unit) -> void:
	var members := collect_members(game_unit)
	if members.nodes.is_empty():
		return
	reform(members.nodes, members.footprints)

## Adopt already-positioned model nodes WITHOUT re-laying them out — each keeps its
## current world transform, the tray just becomes their rigid parent. Used on load to
## reproduce the exact saved block (including any casualty gaps); the tray transform
## should already be set to the saved value before calling.
func adopt_existing(models: Array) -> void:
	for m in models:
		var n := m as Node3D
		if n == null or not is_instance_valid(n):
			continue
		var gx := n.global_transform
		if n.get_parent() != self:
			if n.get_parent():
				n.get_parent().remove_child(n)
			add_child(n)
			n.set_meta(MEMBER_META, self)
		n.global_transform = gx
	_rebuild_facing_visualizer(_front_local_z_from_children())


## Collect a unit's live model nodes and per-model base footprints (metres) from its
## unit_properties. Shared by initial forming and re-ranking. Returns
## {nodes: Array, footprints: Array}.
static func collect_members(game_unit) -> Dictionary:
	var props: Dictionary = game_unit.unit_properties
	var w: float = float(props.get("base_width_mm", 25)) * 0.001
	var d: float = float(props.get("base_depth_mm", 25)) * 0.001
	var nodes: Array = []
	var footprints: Array = []
	for m in game_unit.get_alive_models():
		if m.node and is_instance_valid(m.node):
			nodes.append(m.node)
			footprints.append(Vector2(w, d))
	return {"nodes": nodes, "footprints": footprints}

# === Private ===

func _layout(models: Array, footprints: Array) -> void:
	var offsets := RegimentFormation.local_offsets(footprints, frontage)
	for i in range(models.size()):
		var m := models[i] as Node3D
		if m == null or not is_instance_valid(m):
			continue
		if m.get_parent() != self:
			if m.get_parent():
				m.get_parent().remove_child(m)
			add_child(m)
			m.set_meta(MEMBER_META, self)
		# Local slot relative to the tray → world transform follows the tray rigidly.
		m.position = offsets[i] if i < offsets.size() else Vector3.ZERO
		m.rotation = Vector3.ZERO

	# Front edge = the front-most slot (max local +Z) plus half its base depth.
	var front_z := 0.0
	var max_depth := 0.0
	for off in offsets:
		front_z = maxf(front_z, (off as Vector3).z)
	for fp in footprints:
		max_depth = maxf(max_depth, (fp as Vector2).y)
	_rebuild_facing_visualizer(front_z + max_depth * 0.5)


## Front-most local +Z across the member model nodes (used by the load path, which has
## no footprint data), plus a base-edge margin. Excludes the visualizer child itself.
func _front_local_z_from_children() -> float:
	var front_z := 0.0
	var found := false
	for c in get_children():
		if c == _facing_viz:
			continue
		var n := c as Node3D
		if n == null:
			continue
		front_z = maxf(front_z, n.position.z) if found else n.position.z
		found = true
	return front_z + FRONT_EDGE_MARGIN_M


## Create the facing visualizer on first use and (re)build it for the given front edge.
func _rebuild_facing_visualizer(front_z: float) -> void:
	if _facing_viz == null:
		_facing_viz = RegimentFacingVisualizer.new()
		add_child(_facing_viz)
	_facing_viz.rebuild(front_z)
