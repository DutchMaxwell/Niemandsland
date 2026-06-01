extends GdUnitTestSuite
## Tests HoverGlow: it overlays a glow material on the target's meshes and
## restores them on clear, and never touches the selection-ring meshes.


func _make_target() -> Node3D:
	var body := StaticBody3D.new()
	add_child(body)
	auto_free(body)
	var m1 := MeshInstance3D.new()
	m1.mesh = BoxMesh.new()
	body.add_child(m1)
	var m2 := MeshInstance3D.new()
	m2.mesh = BoxMesh.new()
	body.add_child(m2)
	return body


func _meshes(body: Node) -> Array:
	var result: Array = []
	for child: Node in body.get_children():
		if child is MeshInstance3D:
			result.append(child)
	return result


func test_set_target_applies_overlay_to_meshes() -> void:
	var glow := HoverGlow.new()
	var body := _make_target()
	glow.set_target(body)
	for mesh: MeshInstance3D in _meshes(body):
		assert_bool(mesh.material_overlay != null).is_true()
	assert_bool(glow.get_target() == body).is_true()


func test_clear_removes_overlay_and_target() -> void:
	var glow := HoverGlow.new()
	var body := _make_target()
	glow.set_target(body)
	glow.clear()
	for mesh: MeshInstance3D in _meshes(body):
		assert_bool(mesh.material_overlay == null).is_true()
	assert_bool(glow.get_target() == null).is_true()


func test_clear_restores_pre_existing_overlay() -> void:
	var glow := HoverGlow.new()
	var body := _make_target()
	var original := StandardMaterial3D.new()
	var first: MeshInstance3D = _meshes(body)[0]
	first.material_overlay = original
	glow.set_target(body)
	assert_bool(first.material_overlay != original).is_true()  # glow took over
	glow.clear()
	assert_bool(first.material_overlay == original).is_true()  # restored


func test_set_target_null_clears() -> void:
	var glow := HoverGlow.new()
	var body := _make_target()
	glow.set_target(body)
	glow.set_target(null)
	for mesh: MeshInstance3D in _meshes(body):
		assert_bool(mesh.material_overlay == null).is_true()


func test_skips_selection_highlight_meshes() -> void:
	var body := _make_target()
	var highlight := Node3D.new()
	highlight.name = "SelectionHighlight"
	body.add_child(highlight)
	var ring := MeshInstance3D.new()
	ring.mesh = TorusMesh.new()
	highlight.add_child(ring)

	var glow := HoverGlow.new()
	glow.set_target(body)
	assert_bool(ring.material_overlay == null).is_true()  # ring never glows
