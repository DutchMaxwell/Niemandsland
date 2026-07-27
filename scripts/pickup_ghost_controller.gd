class_name PickupGhostController
extends Node3D
## Measure-on-pickup ghost (ROADMAP "Next" / UX polish): while a drag is live, a translucent
## SILHOUETTE of every picked-up object stays at its origin — the player sees exactly where the
## move started (what ESC snaps back to, and where the measured arc begins). Display-only and
## local (never synced), like the range rings / movement bands.
##
## The ghost is a lightweight visual REBUILD, never a node duplicate: for each MeshInstance3D
## under a dragged object a bare MeshInstance3D with the same mesh + world transform is created
## under this controller — no physics bodies, no scripts, no groups (a duplicate() ghost would
## join "selectable" and could be picked up itself). One shared translucent unshaded material,
## shadows off. begin() is called BEFORE the drag lift, so transforms are the true origin pose.

## Safety cap: a huge multi-select must not rebuild hundreds of meshes every pickup.
const MAX_GHOST_MESHES := 240
const GHOST_COLOR := Color(0.55, 0.75, 1.0, 0.28)

var _ghost_root: Node3D = null
var _material: StandardMaterial3D = null


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = GHOST_COLOR
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.no_depth_test = false
	_material.cull_mode = BaseMaterial3D.CULL_BACK


## Show origin ghosts for the objects about to be dragged (call BEFORE the drag lift).
func begin(objects: Array) -> void:
	end()
	_ghost_root = Node3D.new()
	_ghost_root.name = "PickupGhosts"
	add_child(_ghost_root)
	var budget := MAX_GHOST_MESHES
	for o in objects:
		var obj := o as Node3D
		if obj == null or not is_instance_valid(obj):
			continue
		budget = _ghost_meshes_of(obj, budget)
		if budget <= 0:
			break


## Remove all ghosts (drop AND cancel both end the preview). The root is detached IMMEDIATELY —
## a re-begin in the same frame must never show two ghost sets for one frame.
func end() -> void:
	if _ghost_root != null and is_instance_valid(_ghost_root):
		remove_child(_ghost_root)
		_ghost_root.queue_free()
	_ghost_root = null


func has_ghosts() -> bool:
	return _ghost_root != null and is_instance_valid(_ghost_root) and _ghost_root.get_child_count() > 0


## Rebuild every visible MeshInstance3D under `node` as a bare ghost mesh; returns the remaining budget.
func _ghost_meshes_of(node: Node, budget: int) -> int:
	if budget <= 0:
		return 0
	if node is MeshInstance3D:
		var src := node as MeshInstance3D
		if src.visible and src.mesh != null:
			var ghost := MeshInstance3D.new()
			ghost.mesh = src.mesh
			ghost.material_override = _material
			ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_ghost_root.add_child(ghost)
			ghost.global_transform = src.global_transform
			budget -= 1
	for child in node.get_children():
		budget = _ghost_meshes_of(child, budget)
		if budget <= 0:
			break
	return budget
