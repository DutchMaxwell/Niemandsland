extends GdUnitTestSuite
## Visual lava treatment must not change shared source materials or hazard geometry.

const Volcanic = preload("res://scripts/visual/reference_volcanic.gd")
const Deposits = preload("res://scripts/visual/reference_ash_deposits.gd")


func test_lava_treatment_is_local_and_keeps_hazard_geometry() -> void:
	var source := StandardMaterial3D.new()
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.ORANGE)
	source.albedo_texture = ImageTexture.create_from_image(image)
	var mesh := BoxMesh.new()
	mesh.material = source
	var original: Node3D = auto_free(Node3D.new())
	var visible := MeshInstance3D.new()
	visible.mesh = mesh
	original.add_child(visible)
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	original.add_child(body)
	original.transform = Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.3, 0.02, -0.1))
	var before := original.transform
	var body_before := body.transform
	var collider_before := collider.transform
	var untouched: MeshInstance3D = auto_free(MeshInstance3D.new())
	untouched.mesh = mesh
	var effects: Node3D = auto_free(Volcanic.new())
	effects._shade_lava(original)
	assert_object(visible.mesh).is_same(mesh)
	assert_object(mesh.material).is_same(source)
	assert_object(untouched.get_active_material(0)).is_same(source)
	assert_object(untouched.get_surface_override_material(0)).is_null()
	assert_bool(visible.get_surface_override_material(0) is ShaderMaterial).is_true()
	assert_bool(original.transform == before).is_true()
	assert_bool(body.transform == body_before).is_true()
	assert_bool(collider.transform == collider_before).is_true()
	assert_object(collider.shape).is_same(shape)
	assert_int(body.collision_layer).is_equal(1)


func test_ash_keeps_pool_center_clear_and_follows_movable_parent() -> void:
	var group: Node3D = auto_free(Node3D.new())
	add_child(group)
	group.add_to_group("terrain_group_base")
	group.position = Vector3(0.2,0.01,-0.1)
	group.rotation.y = 0.7
	var anchor := Node3D.new()
	anchor.position = Vector3(0.03,0.0,0.02)
	group.add_child(anchor)
	var original := anchor.transform
	var deposits: Node3D = auto_free(Deposits.new())
	deposits._size = Vector2(1.8288,1.2192)
	deposits.add_deposit(anchor,0.03048,true,0)
	assert_bool(anchor.transform == original).is_true()
	assert_int(group.find_children("*","CollisionObject3D",true,false).size()).is_equal(0)
	var ash := group.get_node("PoolAshDeposit") as MeshInstance3D
	var vertices: PackedVector3Array = ash.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		var delta: Vector3 = group.to_global(vertex)-anchor.global_position
		assert_float(Vector2(delta.x,delta.z).length()).is_greater_equal(0.0289)
	var ash_transform := ash.transform
	var flow := group.get_node("GroundAshFlow") as MeshInstance3D
	var flow_transform := flow.transform
	group.position += Vector3(0.1,0.0,0.15)
	group.rotation.y += 0.4
	assert_bool(ash.global_transform.is_equal_approx(group.global_transform*ash_transform)).is_true()
	assert_bool(flow.global_transform.is_equal_approx(group.global_transform*flow_transform)).is_true()
	assert_bool(anchor.transform == original).is_true()
