extends GdUnitTestSuite
## Decorative urban material contact and full fragment reach protect rule surfaces.

const Urban = preload("res://scripts/visual/reference_urban.gd")


class ReferenceFixture extends Node3D:
	var _ground := ShaderMaterial.new()
	var _base := ShaderMaterial.new()


class OverlayFixture extends Node3D:
	var _object_instances: Array[Node3D] = []
	var _wall_instances: Array[Node3D] = []

	func get_wall_segments_world() -> Array:
		return [[Vector2(-0.15,-0.15),Vector2(-0.15,0.15)]]


class RuinFixture extends StaticBody3D:
	func wall_segments_world() -> Array:
		var a := global_transform*Vector3(0,0,-0.08)
		var b := global_transform*Vector3(0,0,0.08)
		return [[Vector2(a.x,a.z),Vector2(b.x,b.z)]]


class ObjectsFixture extends Node3D:
	var model := ModelInstance.new()

	func _object_model_instance(_obj: Node3D) -> ModelInstance:
		return model


class MainFixture extends Node3D:
	var terrain_overlay := OverlayFixture.new()
	var object_manager := ObjectsFixture.new()

	func _init() -> void:
		add_child(terrain_overlay)
		add_child(object_manager)


class UrbanProbe extends Urban:
	var placements: Dictionary = {}

	func _multimesh(label: String,mesh: Mesh,transforms: Array[Transform3D],colors: Array[Color],shadow := true) -> void:
		# The headless dummy renderer does not retain MultiMesh transform buffers.
		placements[label] = transforms.duplicate()
		super._multimesh(label,mesh,transforms,colors,shadow)


func test_build_keeps_model_node_and_shares_ground_base_contact() -> void:
	var main: Node3D = auto_free(MainFixture.new())
	add_child(main)
	var miniature := Node3D.new()
	main.object_manager.add_child(miniature)
	miniature.add_to_group("selectable")
	miniature.position = Vector3(-0.10,0,0)
	var original := miniature.transform
	var presentation: Node3D = auto_free(ReferenceFixture.new())
	presentation._ground.shader = preload("res://shaders/visual/reference_ground.gdshader")
	presentation._base.shader = presentation._ground.shader
	var urban: Node3D = auto_free(UrbanProbe.new())
	add_child(urban)
	urban.build(presentation,main,Vector2(0.5,0.4))
	assert_bool(miniature.transform == original).is_true()
	assert_object(presentation._ground.get_shader_parameter("urban_contact_mask")).is_same(presentation._base.get_shader_parameter("urban_contact_mask"))
	var rubble: Array = urban.placements["UrbanMasonry"]
	assert_int(rubble.size()).is_greater(10)
	for placement: Transform3D in rubble:
		var p := Vector2(placement.origin.x,placement.origin.z)
		var radius := placement.basis.get_scale().x*Urban.FRAGMENT_RADIUS
		assert_bool(urban.clear_footprint(p,radius)).is_true()
		# Height is seated by the world-space shader after an owner's transform.
		assert_float(placement.origin.y).is_equal_approx(0.0,0.000001)
	assert_int(urban.find_children("*","CollisionObject3D",true,false).size()).is_equal(0)


func test_live_placement_rotation_removal_and_unit_clearance() -> void:
	var main: Node3D = auto_free(MainFixture.new())
	add_child(main)
	var presentation: Node3D = auto_free(ReferenceFixture.new())
	presentation._ground.shader = preload("res://shaders/visual/reference_ground.gdshader")
	presentation._base.shader = presentation._ground.shader
	var urban: Node3D = auto_free(Urban.new())
	add_child(urban)
	urban.build(presentation,main,Vector2(1.8,1.2))
	var ruin := RuinFixture.new()
	main.object_manager.add_child(ruin)
	ruin.position.x = 0.25
	await get_tree().create_timer(0.25).timeout
	var id := ruin.get_instance_id()
	assert_bool(urban._owners.has(id)).is_true()
	var original_contact: float = urban.contact_amount(Vector2(0.25,0))
	assert_float(original_contact).is_equal(1.0)
	ruin.position = Vector3(0.5,0,0.2)
	ruin.rotation.y = PI/2
	await get_tree().process_frame
	assert_bool(urban._owners[id].rig.global_transform.is_equal_approx(ruin.global_transform)).is_true()
	await get_tree().create_timer(0.25).timeout
	assert_float(urban.contact_amount(Vector2(0.25,0))).is_equal(0.0)
	assert_float(urban.contact_amount(Vector2(0.5,0.2))).is_equal_approx(1.0,0.001)
	var duplicate := RuinFixture.new()
	main.object_manager.add_child(duplicate)
	duplicate.position = Vector3(0.65,0,-0.2)
	var unit := StaticBody3D.new()
	unit.add_to_group("selectable")
	main.object_manager.add_child(unit)
	unit.position = Vector3(0.45,0,0.2)
	await get_tree().create_timer(0.25).timeout
	assert_bool(urban._owners.has(duplicate.get_instance_id())).is_true()
	assert_bool(urban.clear_footprint(Vector2(0.45,0.2),0.003)).is_false()
	unit.position.x = 0.1
	await get_tree().create_timer(0.25).timeout
	assert_bool(urban.clear_footprint(Vector2(0.1,0.2),0.003)).is_false()
	assert_bool(urban.clear_footprint(Vector2(0.45,0.23),0.003)).is_true()
	ruin.queue_free()
	await get_tree().create_timer(0.25).timeout
	assert_bool(urban._owners.has(id)).is_false()
	assert_float(urban.contact_amount(Vector2(0.5,0.2))).is_equal(0.0)
	assert_int(duplicate.find_children("*","MeshInstance3D",true,false).size()).is_equal(0)


func test_rubble_footprint_keeps_units_hazards_walls_and_edges_clear() -> void:
	var urban: Node3D = auto_free(Urban.new())
	urban._board_size = Vector2(1.8,1.2)
	urban._walls = [[Vector2(-0.5,-0.3),Vector2(-0.5,0.3)]]
	urban._exclusions.append(Vector3(0,0,0.024))
	urban._blockers.append(Vector3(0.3,0,0.035))
	assert_bool(urban.clear_footprint(Vector2(0.030,0),0.006)).is_false()
	assert_bool(urban.clear_footprint(Vector2(0.341,0),0.006)).is_false()
	assert_bool(urban.clear_footprint(Vector2(-0.49,0),0.006)).is_false()
	assert_bool(urban.clear_footprint(Vector2(0.888,0),0.006)).is_false()
	assert_bool(urban.clear_footprint(Vector2(-0.477,0),0.006)).is_true()


func test_contact_follows_finite_wall_and_mask_coordinates() -> void:
	var urban: Node3D = auto_free(Urban.new())
	urban._board_size = Vector2(1.8,1.2)
	urban._walls = [[Vector2(-0.2,-0.25),Vector2(-0.2,0.25)]]
	assert_float(urban.contact_amount(Vector2(-0.2,0))).is_equal(1.0)
	assert_float(urban.contact_amount(Vector2(-0.3,0))).is_equal(0.0)
	assert_float(urban.contact_amount(Vector2(-0.2,0.35))).is_equal(0.0)
	var mask: Image = urban._contact_texture().get_image()
	for p in [Vector2(-0.2,0),Vector2(-0.3,0),Vector2(-0.2,0.35)]:
		var uv: Vector2 = p/urban._board_size+Vector2(0.5,0.5)
		assert_float(mask.get_pixel(int(uv.x*mask.get_width()),int(uv.y*mask.get_height())).r).is_equal_approx(urban.contact_amount(p),0.03)


func test_fragment_mesh_stays_within_clearance_and_faces_up() -> void:
	var urban: Node3D = auto_free(Urban.new())
	var mesh: ArrayMesh = urban._fragment_mesh()
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in vertices.size():
		assert_float(Vector2(vertices[i].x,vertices[i].z).length()).is_less_equal(Urban.FRAGMENT_RADIUS)
		assert_float(vertices[i].y).is_greater_equal(0.0)
		assert_float(vertices[i].y).is_less_equal(1.0)
		if i%9<3:
			assert_float(normals[i].y).is_greater(0.5)
