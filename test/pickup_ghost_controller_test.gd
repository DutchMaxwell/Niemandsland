extends GdUnitTestSuite
## Measure-on-pickup ghost (UX polish): the origin-silhouette rebuild. Proves the ghost is a bare
## visual copy (meshes only — no groups, no physics, no scripts), sits at the source's WORLD
## transform, dies on end()/re-begin(), and respects the mesh budget cap.


func _controller() -> PickupGhostController:
	var c: PickupGhostController = auto_free(PickupGhostController.new())
	add_child(c)
	return c


## A draggable-shaped object: a RigidBody3D root in "selectable" with a mesh child.
func _object_with_mesh(pos: Vector3) -> RigidBody3D:
	var body: RigidBody3D = auto_free(RigidBody3D.new())
	body.add_to_group("selectable")
	add_child(body)
	body.global_position = pos
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	body.add_child(mi)
	return body


func _ghost_meshes(c: PickupGhostController) -> Array:
	var out: Array = []
	for root in c.get_children():
		for g in (root as Node).get_children():
			out.append(g)
	return out


func test_begin_builds_bare_mesh_ghosts_at_the_origin_pose() -> void:
	var c := _controller()
	var obj := _object_with_mesh(Vector3(0.4, 0.0, 0.2))
	c.begin([obj])
	assert_bool(c.has_ghosts()).is_true()
	var ghosts := _ghost_meshes(c)
	assert_int(ghosts.size()).is_equal(1)
	var g := ghosts[0] as MeshInstance3D
	# World pose matches the source mesh at begin() time (the pre-lift origin).
	assert_float(g.global_position.distance_to(Vector3(0.4, 0.0, 0.2))).is_less(0.001)
	# Bare visual: never selectable, never a physics body, shadows off, shared override material.
	assert_bool(g.is_in_group("selectable")).is_false()
	assert_bool((g as Node) is PhysicsBody3D).is_false()
	assert_int(g.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_object(g.material_override).is_not_null()


func test_ghost_stays_at_origin_while_the_source_moves() -> void:
	var c := _controller()
	var obj := _object_with_mesh(Vector3.ZERO)
	c.begin([obj])
	obj.global_position = Vector3(1.0, 0.05, 1.0)   # the drag moves the real object
	var g := _ghost_meshes(c)[0] as MeshInstance3D
	assert_float(g.global_position.length()).is_less(0.001)


func test_end_and_rebegin_never_stack_ghosts() -> void:
	var c := _controller()
	var obj := _object_with_mesh(Vector3.ZERO)
	c.begin([obj])
	c.begin([obj])   # re-begin replaces, never stacks
	assert_int(_ghost_meshes(c).size()).is_equal(1)
	c.end()
	await get_tree().process_frame   # queue_free
	assert_bool(c.has_ghosts()).is_false()


func test_mesh_budget_caps_huge_selections() -> void:
	var c := _controller()
	var objs: Array = []
	for i in range(PickupGhostController.MAX_GHOST_MESHES + 20):
		objs.append(_object_with_mesh(Vector3(float(i) * 0.01, 0, 0)))
	c.begin(objs)
	assert_int(_ghost_meshes(c).size()).is_equal(PickupGhostController.MAX_GHOST_MESHES)
