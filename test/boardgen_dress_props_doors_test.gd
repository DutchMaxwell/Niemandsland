extends GdUnitTestSuite
## R12 on a synthetic door (maintainer 25.11.: a lamp never stands in front of a door): the props
## planner's place_lamp moves a lamp in a doorway along the face past the zone, or drops it when no
## spot within MAX_SHIFT_IN fits.

const IN := 0.0254


func _layout(board_seed: int) -> Dictionary:
	return (ClassDB.instantiate("NmlCore") as Object).boardgen_layout_themed(board_seed, "ruintown")


func _ctx(layout: Dictionary) -> DressContext:
	var kit := BoardgenKit.new("ruintown")
	add_child(kit)
	auto_free(kit)
	var dress := BoardgenDressKit.new(kit, true)
	return DressContext.new(layout, dress, BoardgenDressStory.of(layout), int(layout["seed"]))


## A synthetic door: a face along +x looking +z just behind a real post point, door opening
## 1.1-1.85 in. The post in front of it moves along the face past the zone; with two more doors
## covering both ends it is dropped.
func test_a_lamp_in_a_doorway_moves_along_the_face_or_is_dropped() -> void:
	var layout := _layout(41)
	var ctx := _ctx(layout)
	var props := BoardgenDressProps.new()
	var moved := 0
	for l: Dictionary in BoardgenTownDressing.lanterns(layout):
		var at: Vector2 = l["at"]
		if props.place_lamp(ctx, at, []).module != "dr_lamp_post":
			continue
		var z := {
			"p": at + Vector2(-1.45, -0.5),
			"a": Vector2.RIGHT,
			"o": Vector2(0, 1),
			"s0": 0.6,
			"s1": 2.35
		}
		assert_bool(BoardgenDressProps._in_door(z, at, 0.0)).is_true()  # the post stands in the doorway
		var doors: Array[Dictionary] = [z]
		var lamp := props.place_lamp(ctx, at, doors)
		if lamp == null:
			continue  # no ground to move to here: try the next point
		var to := Vector2(lamp.transform.origin.x, lamp.transform.origin.z) / IN
		(
			assert_bool(BoardgenDressProps._in_door(z, to, BoardgenDressProps.LAMP_RADIUS_IN))
			. is_false()
		)
		if lamp.module == "dr_lamp_post":
			assert_float(to.y).is_equal_approx(at.y, 0.001)  # moved along the face only
		var wide := z.duplicate()
		wide["s0"] = -3.0
		wide["s1"] = 6.0
		assert_object(props.place_lamp(ctx, at, [wide] as Array[Dictionary])).is_null()  # no spot fits
		moved += 1
	assert_int(moved).is_greater(0)


## The light follows its lamp: on seeds 41, 25 and 1-20 every lantern SpotLight and its fill stand
## over the glass of a dressed lamp (xz within 0.01 in), and a dropped lamp has no light.
func test_every_lantern_light_stands_at_its_lamp_glass() -> void:
	var seeds: Array[int] = [41, 25]
	for s in range(1, 21):
		seeds.append(s)
	var moved := 0
	for board_seed in seeds:
		var layout := _layout(board_seed)
		var glass: Dictionary = BoardgenDressProps.new().glass(_ctx(layout))
		var kept: Array[Vector2] = []
		for at: Vector2 in glass:
			if glass[at] == null or (glass[at] as Vector2).distance_to(at) > 0.01:
				moved += 1
			if glass[at] != null:
				kept.append(glass[at])
		var kit := BoardgenKit.new("ruintown")
		add_child(kit)
		auto_free(kit)
		var dress := BoardgenDress.new(BoardgenDressKit.new(kit, true))
		var table: Node3D = auto_free(Node3D.new())
		add_child(table)
		var board := BoardgenGreybox.attach(table, layout, dress)
		var lights := board.find_children("Lantern*", "Light3D", true, false)
		# one spot per lamp (look review 2: no warm omni fill beside it)
		assert_int(lights.size()).is_equal(mini(kept.size(), BoardgenTownDressing.MAX_LIGHTS))
		for light: Light3D in lights:
			var xz := Vector2(light.position.x, light.position.z) / IN
			(
				assert_bool(kept.any(func(g: Vector2) -> bool: return g.distance_to(xz) < 0.01))
				. override_failure_message(
					"seed %d: %s at %s has no lamp glass" % [board_seed, light.name, xz]
				)
				. is_true()
			)
		board.free()
	print("R12 lamps moved or dropped over 22 seeds: ", moved)
	assert_int(moved).is_greater(0)
