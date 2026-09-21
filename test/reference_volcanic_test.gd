extends GdUnitTestSuite
## Visual lava treatment must not change shared source materials or hazard geometry.

const Volcanic = preload("res://scripts/visual/reference_volcanic.gd")


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
