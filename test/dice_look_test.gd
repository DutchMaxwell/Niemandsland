extends GdUnitTestSuite
## uidice2 — the dice looks are visual only and one switch.
##
## FAIRNESS: for every look and all six resting orientations, the pips MODELLED on the up-facing
## face (the mesh's up-facing vertices -> their UVs -> the pip atlas the shader paints -> counted
## blobs) equal the value the face reader reports. The look may not touch the physics body.
## The seeded roll batch before / after the restyle is proven by a harness run (UIDICE_REPORT.md).

const LOOKS: Array[StringName] = [&"classic", &"house", &"brass"]


func after_test() -> void:
	DiceLook.set_override(&"")


func _die() -> DiceD6:
	var d := DiceD6.new()
	d.size = DiceTray.DIE_SIZE
	add_child(d)
	return auto_free(d)


## Connected pip blobs (mask > 0.5) whose pixels all lie inside `rect` (atlas pixels).
static func _count_pips(atlas: Image, rect: Rect2i) -> int:
	var seen := {}
	var blobs := 0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var key := Vector2i(x, y)
			if seen.has(key) or atlas.get_pixel(x, y).r <= 0.5:
				continue
			blobs += 1
			var stack: Array[Vector2i] = [key]
			seen[key] = true
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q := p + step
					if not rect.has_point(q) or seen.has(q) or atlas.get_pixel(q.x, q.y).r <= 0.5:
						continue
					seen[q] = true
					stack.append(q)
	return blobs


## The pips modelled on the face that points up: every vertex whose world normal is straight up
## gives its UV; their bounding box is that face's flat part in the atlas; its blobs are counted.
func _pips_on_top(d: DiceD6) -> int:
	var arrays := d.visual_instance().mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var basis := d.global_transform.basis
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i: int in normals.size():
		if (basis * normals[i]).normalized().dot(Vector3.UP) > 0.999:
			lo = lo.min(uvs[i])
			hi = hi.max(uvs[i])
	var atlas := DiceVisual.pip_atlas_image()
	var px := Vector2(atlas.get_width(), atlas.get_height())
	return _count_pips(atlas, Rect2i(Vector2i((lo * px).floor()), Vector2i(((hi - lo) * px).ceil())))


func test_every_face_of_the_atlas_carries_its_number_of_pips() -> void:
	var atlas := DiceVisual.pip_atlas_image()
	var cell := DiceVisual.CELL_PX
	for value: int in range(1, 7):
		var c := DiceVisual.cell_of(value)
		assert_int(_count_pips(atlas, Rect2i(c * cell, Vector2i(cell, cell)))) \
			.override_failure_message("atlas cell of face %d" % value).is_equal(value)


func test_the_top_face_shows_the_value_the_reader_reports_in_all_six_orientations() -> void:
	for look: StringName in LOOKS:
		DiceLook.set_override(look)
		var d := _die()
		for value: int in range(1, 7):
			d.settle_to_face(value)   # a resting orientation, exactly as after a physics roll
			assert_int(d.top_face()).is_equal(value)
			assert_int(_pips_on_top(d)).override_failure_message(
				"%s: reader says %d, the up face shows %d pips" % [look, value, _pips_on_top(d)]).is_equal(value)
			d.set_top_face(value)     # quick-roll / remote path (random yaw)
			assert_int(_pips_on_top(d)).is_equal(d.top_face())


func test_opposite_modelled_faces_sum_to_seven() -> void:
	var d := _die()
	for value: int in range(1, 7):
		d.settle_to_face(value)
		var up := _pips_on_top(d)
		d.global_transform = Transform3D(Basis(Vector3.RIGHT, PI) * d.global_transform.basis, d.global_position)
		assert_int(up + _pips_on_top(d)).is_equal(7)


func test_the_look_never_touches_the_physics_body() -> void:
	var reference: Dictionary = {}
	for look: StringName in LOOKS:
		DiceLook.set_override(look)
		var d := _die()
		var shape := (d.get_child(0) as CollisionShape3D).shape as BoxShape3D
		var physics := {
			"mass": d.mass, "gravity_scale": d.gravity_scale, "linear_damp": d.linear_damp,
			"angular_damp": d.angular_damp, "ccd": d.continuous_cd, "box": shape.size,
			"friction": d.physics_material_override.friction, "bounce": d.physics_material_override.bounce,
			"shapes": d.find_children("*", "CollisionShape3D", true, false).size(),
		}
		if reference.is_empty():
			reference = physics
		assert_dict(physics).override_failure_message("%s changed the physics body" % look).is_equal(reference)
		# The visible body is a plain mesh: no collider, no body of its own.
		assert_int(d.visual_instance().find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)


func test_one_switch_drives_the_dice_and_the_tally_icons() -> void:
	for look: StringName in LOOKS:
		DiceLook.set_override(look)
		var l := DiceLook.current()
		assert_that(l.id).is_equal(look)
		var d := _die()
		assert_object(d.visual_instance().material_override).is_same(DiceVisual.body_material(l))
		assert_that(d.visual_instance().get_instance_shader_parameter(&"body_color")).is_equal(l.body_color)
		assert_that(d.visual_instance().get_instance_shader_parameter(&"pip_color")).is_equal(l.pip_color)
		var icon: DieFaceIcon = auto_free(DieFaceIcon.new())
		assert_that(icon.body_color).is_equal(l.body_color)
		assert_that(icon.pip_color).is_equal(l.pip_color)
		assert_that(DiceD6.body_color_for_tag(0)).is_equal(l.body_color)
	DiceLook.set_override(&"")
	assert_that(DiceLook.current().id).is_equal(HouseStyle.DICE_LOOK)


## The dice resting BEFORE a throw (and a shown result) keep a clear, even margin to the rim on every
## side (maintainer 23.09.: they sat squeezed against the rim) — for 1, 6, 10 and 30 dice. The margin is
## measured from a die's half-diagonal, since resting dice turn to a random yaw.
func test_resting_dice_keep_an_even_margin_from_the_rim() -> void:
	for n: int in [1, 6, 10, 30]:
		var t := DiceTray.new()
		t.dice_count = n
		add_child(t)
		auto_free(t)
		var f := sqrt(n / 6.0)
		t.roller_size = Vector3(maxf(12.0, 18.0 * f), 15.0, maxf(8.0, 12.0 * f))   # as main._update_dice_set
		await get_tree().process_frame
		var in_x := t.roller_size.x * 0.5 - DiceTray.WALL_THICKNESS * 0.5
		var in_z := t.roller_size.z * 0.5 - DiceTray.WALL_THICKNESS * 0.5
		var reach := DiceTray.DIE_SIZE * 0.5 * sqrt(2.0)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for d: DiceD6 in t._dice:
			lo = lo.min(Vector2(d.position.x, d.position.z))
			hi = hi.max(Vector2(d.position.x, d.position.z))
		var gaps := [lo.x - reach + in_x, in_x - hi.x - reach, lo.y - reach + in_z, in_z - hi.y - reach]
		for g: float in gaps:
			assert_float(g).override_failure_message("%d dice: a resting die %.2f from the rim %s" % [n, g, str(gaps)]) \
				.is_greater_equal(DiceTray.DIE_SIZE * 0.5 - 0.001)   # positions are float32
		if n > 1:
			assert_float(absf(gaps[0] - gaps[1]) + absf(gaps[2] - gaps[3]) + absf(gaps[0] - gaps[2])) \
				.override_failure_message("%d dice: uneven margins %s" % [n, str(gaps)]).is_less(0.01)


## WCAG relative luminance / contrast ratio.
static func _contrast(a: Color, b: Color) -> float:
	var la := a.srgb_to_linear().get_luminance()
	var lb := b.srgb_to_linear().get_luminance()
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func test_pips_read_on_every_look_and_every_colour_tag() -> void:
	for look: StringName in LOOKS:
		DiceLook.set_override(look)
		for tag: int in range(0, DiceD6.TAG_COLORS.size() + 1):
			var ratio := _contrast(DiceD6.body_color_for_tag(tag), DiceD6.pip_color_for_tag(tag))
			assert_float(ratio).override_failure_message("%s tag %d: pip contrast %.2f" % [look, tag, ratio]) \
				.is_greater_equal(3.0)
		# A tagged die keeps its tag colour on every look (the tag is the information).
		var d := _die()
		d.set_color_tag(1)
		assert_that(d.visual_instance().get_instance_shader_parameter(&"body_color")).is_equal(DiceD6.TAG_COLORS[0])
