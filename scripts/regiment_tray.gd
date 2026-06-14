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
