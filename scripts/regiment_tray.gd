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
