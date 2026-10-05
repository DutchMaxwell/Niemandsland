extends GdUnitTestSuite
## Every shelf solid carries a soft contact shadow (maintainer 05.10.: yes): one Decal child over the footprint plus
## 0.8" all round, 0.4" tall, opaque under the piece and fading to nothing outside. As a child it moves, turns and goes
## with the piece in the same frame, and it stays when a detailed model replaces the bundled look.

const IN2M := 0.0254


func _solid() -> SandboxSolidProp:
	var p := SandboxSolidProp.new()
	p.configure("blocker_6x3", 3, Vector2(6, 3))
	add_child(p)
	return p


func _skirt(p: Node) -> Decal:
	var found := p.find_children("ContactSkirt", "Decal", false, false)   # the foot dressing (S6-1) is a Decal too
	return found[0] as Decal if found.size() == 1 else null


func test_a_solid_has_one_soft_skirt_around_its_footprint() -> void:
	var p: SandboxSolidProp = auto_free(_solid())
	var skirt := _skirt(p)
	assert_object(skirt).is_not_null()
	if skirt == null:
		return
	assert_vector(skirt.size).is_equal_approx(Vector3(7.6, 0.4, 4.6) * IN2M, Vector3.ONE * 0.0001)
	var img := skirt.texture_albedo.get_image()
	assert_float(img.get_pixel(img.get_width() / 2, img.get_height() / 2).a).is_greater(0.99)   # under the piece
	assert_float(img.get_pixel(0, 0).a).is_less(0.01)                                             # beyond 0.8": nothing


func test_the_skirt_moves_turns_stays_and_goes_with_the_piece() -> void:
	var p := _solid()
	var skirt := _skirt(p)
	assert_object(skirt).is_not_null()
	if skirt == null:
		p.free()
		return
	p.global_position = Vector3(0.3, 0.0, -0.2)
	p.rotation.y = 0.7
	assert_vector(skirt.global_position).is_equal_approx(p.global_position, Vector3.ONE * 0.0001)
	assert_float(skirt.global_rotation.y).is_equal_approx(0.7, 0.0001)
	p.use_model(Node3D.new())
	assert_bool(skirt.visible).is_true()
	p.free()
	assert_bool(is_instance_valid(skirt)).is_false()
