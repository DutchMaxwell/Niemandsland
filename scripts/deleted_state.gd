class_name DeletedState
## Delete hides a plain object (terrain, props, tokens) instead of freeing it, so it stays undoable. A deleted object
## must also leave the physics world: a hidden free solid kept its collider and models set down there stood on its
## invisible top (measured 05.10.). The live collision layer is parked in a meta and restored on undo.


static func apply(node: Node3D, deleted: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.visible = not deleted
	node.set_meta("deleted", deleted)
	var body := node as CollisionObject3D
	if body == null:
		return
	if deleted and not body.has_meta("live_collision_layer"):
		body.set_meta("live_collision_layer", body.collision_layer)
		body.collision_layer = 0
	elif not deleted and body.has_meta("live_collision_layer"):
		body.collision_layer = int(body.get_meta("live_collision_layer"))
		body.remove_meta("live_collision_layer")
