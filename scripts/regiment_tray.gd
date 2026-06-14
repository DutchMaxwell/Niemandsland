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

# === Public state ===

var frontage: int = 5

# === Private state ===

var _facing_marker: MeshInstance3D = null   # cyan arrow showing the front (+Z)
var _front_z: float = 0.0                    # local Z of the front edge (for the marker)
var _show_facing: bool = true

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

## The unit's facing as a top-down (XZ) 2D unit vector.
func facing_2d() -> Vector2:
	var z := global_transform.basis.z
	return Vector2(z.x, z.z).normalized()

## True if a world point lies within the regiment's front arc (Regiments LOS aid).
func front_arc_contains(target_world: Vector3) -> bool:
	return LosRules.is_in_front_arc(
		Vector2(global_position.x, global_position.z),
		facing_2d(),
		Vector2(target_world.x, target_world.z))

## Show/hide the front-facing marker (visual aid).
func set_facing_visible(visible_flag: bool) -> void:
	_show_facing = visible_flag
	_refresh_facing_marker()

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
	_front_z = _front_edge_from_children()
	_refresh_facing_marker()


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
	var max_z := 0.0
	for off in offsets:
		max_z = maxf(max_z, off.z)
	var max_d := 0.0
	for fp in footprints:
		max_d = maxf(max_d, fp.y)
	_front_z = max_z + max_d * 0.5
	_refresh_facing_marker()


## Front edge (local +Z) from the current member children, for the facing marker.
func _front_edge_from_children() -> float:
	var fz := 0.0
	for c in get_children():
		if c == _facing_marker:
			continue
		var n := c as Node3D
		if n:
			fz = maxf(fz, n.position.z)
	return fz + 0.02


## Create/update the cyan front-facing arrow (visual aid; tune live).
func _refresh_facing_marker() -> void:
	if not _show_facing:
		if _facing_marker:
			_facing_marker.visible = false
		return
	if _facing_marker == null:
		_facing_marker = MeshInstance3D.new()
		_facing_marker.name = "FacingMarker"
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.012
		cone.height = 0.024
		_facing_marker.mesh = cone
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.9, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.9, 1.0)
		_facing_marker.material_override = mat
		_facing_marker.rotation_degrees = Vector3(90.0, 0.0, 0.0)  # cone tip -> +Z
		add_child(_facing_marker)
	_facing_marker.visible = true
	_facing_marker.position = Vector3(0.0, 0.012, _front_z + 0.015)
