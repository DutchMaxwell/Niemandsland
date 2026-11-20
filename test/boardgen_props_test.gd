extends GdUnitTestSuite
## The look pass's dressing of a boardgen layout (BoardgenProps): one seed dresses the same board every time and another seed
## another, no prop takes standing room (only the wall strip, or flat), the foot of a ladder stays bare,
## at most 8 lights, and the kit is five MultiMeshes with nothing physical. Stands on the recorded seed 42 layout.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"
const CELL_IN := 3.0


func _fixture() -> Dictionary:
	return str_to_var(FileAccess.get_file_as_string(FIXTURE))


## The cell (x, z) a prop's centre is in, from its board-metre transform.
func _cell_of(layout: Dictionary, prop: Dictionary) -> Vector2i:
	var p: Vector3 = prop["xf"].origin / BoardgenProps.INCHES_TO_METERS
	return Vector2i(floori(p.x / CELL_IN + layout["nx"] * 0.5), floori(p.z / CELL_IN + layout["nz"] * 0.5))


func _level(layout: Dictionary, c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= layout["nx"] or c.y >= layout["nz"]:
		return 0
	return layout["cells"][c.y * layout["nx"] + c.x]["level"]


func test_one_seed_dresses_the_same_board_and_another_seed_another() -> void:
	var layout := _fixture()
	var first := BoardgenProps.plan(layout)
	assert_int(first.size()).is_greater(40)
	randomize()   # the global generator must not matter
	assert_array(BoardgenProps.plan(layout)).is_equal(first)
	assert_array(BoardgenProps.plan(_fixture())).is_equal(first)
	var other := _fixture()
	other["seed"] = int(layout["seed"]) + 1
	assert_bool(BoardgenProps.plan(other) == first).is_false()


func test_a_landmark_footprint_stays_bare() -> void:
	var layout := _fixture()
	assert_int(BoardgenProps.plan(layout).size()).is_greater(40)
	layout["landmarks"] = [{"kind": "TankCluster", "x": 0, "z": 0, "w": 16, "h": 16, "turn": 0}]   # every cell is some landmark's
	assert_int(BoardgenProps.plan(layout).size()).is_equal(0)


## True when `corner` (inches off the board centre) is not standing room: inside a tier block, within STRIP_IN of a tier wall in its level-0 cell.
func _outside_standing_room(layout: Dictionary, corner: Vector3) -> bool:
	var half := Vector2(layout["nx"], layout["nz"]) * CELL_IN * 0.5
	var g := (Vector2(corner.x, corner.z) + half) / CELL_IN
	var c := Vector2i(floori(g.x), floori(g.y))
	var level := _level(layout, c)
	if level > 0:
		return corner.y <= float(layout["level_in"][level]) + 0.01
	var f := (g - Vector2(c)) * CELL_IN
	for d in BoardgenProps.DIRS:
		var dist := CELL_IN - f.x if d.x > 0 else f.x if d.x < 0 else CELL_IN - f.y if d.y > 0 else f.y
		if _level(layout, c + d) > 0 and dist <= BoardgenProps.STRIP_IN + 0.01:
			return true
	return false


func test_no_prop_takes_standing_room_it_stays_in_the_wall_strip_or_lies_flat() -> void:
	var layout := _fixture()
	var shapes := {}
	for prop in BoardgenProps.plan(layout):
		shapes[prop["shape"]] = true
		if prop["shape"] == "light":
			continue
		var top := -INF
		var corners: Array[Vector3] = []
		for sx in [-0.5, 0.5]:
			for sy in [-0.5, 0.5]:
				for sz in [-0.5, 0.5]:
					corners.append(prop["xf"] * Vector3(sx, sy, sz) / BoardgenProps.INCHES_TO_METERS)
					top = maxf(top, corners[-1].y)
		if top <= BoardgenProps.FLAT_IN:
			continue   # paper-thin: a base can stand on it
		for corner in corners:
			assert_bool(_outside_standing_room(layout, corner)).override_failure_message("%s (scale %s, origin %s) reaches into standing room at %s" % [prop["shape"], prop["xf"].basis.get_scale() / BoardgenProps.INCHES_TO_METERS, prop["xf"].origin / BoardgenProps.INCHES_TO_METERS, corner]).is_true()
	assert_array(shapes.keys()).contains_exactly_in_any_order(["box", "cyl", "bulb", "ball", "ring", "light"])


func test_the_foot_of_a_ladder_stays_bare() -> void:
	var layout := _fixture()
	var feet: Array = layout["connectors"].map(func(c: Dictionary) -> Vector2i: return Vector2i(c["low_xz"][0], c["low_xz"][1]))
	assert_int(feet.size()).is_greater(10)
	for prop in BoardgenProps.plan(layout):
		assert_bool(feet.has(_cell_of(layout, prop))).is_false()


func test_at_most_eight_lights_and_no_two_lamps_cluster() -> void:
	var lights := BoardgenProps.plan(_fixture()).filter(func(p: Dictionary) -> bool: return p["shape"] == "light")
	assert_int(lights.size()).is_between(1, BoardgenProps.MAX_LIGHTS)
	for i in lights.size():
		for j in range(i + 1, lights.size()):
			var gap: float = lights[i]["xf"].origin.distance_to(lights[j]["xf"].origin) / BoardgenProps.INCHES_TO_METERS
			assert_float(gap).is_greater(BoardgenProps.LAMP_GAP_IN - 2.0)


func test_build_makes_three_multimeshes_and_the_lights_and_nothing_physical() -> void:
	var layout := _fixture()
	var node: BoardgenProps = auto_free(BoardgenProps.new())
	add_child(node)
	node.build(layout)
	var props := BoardgenProps.plan(layout)
	var meshes := node.find_children("*", "MultiMeshInstance3D", false, false)
	assert_int(meshes.size()).is_equal(5)
	for m: MultiMeshInstance3D in meshes:
		assert_int(m.multimesh.instance_count).is_equal(props.filter(func(p: Dictionary) -> bool: return p["shape"] == m.name).size())
	assert_int(node.find_children("*", "OmniLight3D", false, false).size()).is_equal(props.filter(func(p: Dictionary) -> bool: return p["shape"] == "light").size())
	assert_int(node.find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)


func _lamp_props(layout: Dictionary) -> Array:
	return BoardgenProps.plan(layout).filter(func(p: Dictionary) -> bool: return p["shape"] == "light")


func test_a_lamp_cone_points_down_and_leans_away_from_its_wall() -> void:
	for out: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var fwd := -BoardgenProps.spot_basis(out).z   # a spot light shines along -Z
		assert_float(fwd.y).is_less(-0.9)
		assert_float(fwd.x * out.x + fwd.z * out.y).is_greater(0.2)   # leans out of the wall, never into it
	for lamp in _lamp_props(_fixture()):
		assert_bool(lamp.has("out") and absf(lamp["out"].length() - 1.0) < 0.001).is_true()


func test_the_shadow_goes_to_the_four_lamps_nearest_the_board_centre() -> void:
	var lamps := _lamp_props(_fixture())
	var chosen := BoardgenProps.shadow_lamps(lamps, BoardgenProps.SHADOW_LAMPS)
	assert_int(chosen.size()).is_equal(mini(BoardgenProps.SHADOW_LAMPS, lamps.size()))
	var far_of_chosen := 0.0
	for i in chosen:
		far_of_chosen = maxf(far_of_chosen, Vector2(lamps[i]["xf"].origin.x, lamps[i]["xf"].origin.z).length())
	for i in lamps.size():
		if not chosen.has(i):
			assert_float(Vector2(lamps[i]["xf"].origin.x, lamps[i]["xf"].origin.z).length()).is_greater_equal(far_of_chosen)


func test_the_finer_look_shows_the_cones_with_four_shadows_and_low_keeps_the_plain_omni_lamps() -> void:
	var node: BoardgenProps = auto_free(BoardgenProps.new())
	node.build(_fixture())
	var omnis := node.find_children("*", "OmniLight3D", false, false)
	var spots := node.find_children("*", "SpotLight3D", false, false)
	assert_int(spots.size()).is_equal(omnis.size())
	node.apply_detail(true)
	assert_int(spots.filter(func(l: Light3D) -> bool: return l.visible).size()).is_equal(spots.size())
	assert_int(omnis.filter(func(l: Light3D) -> bool: return l.visible).size()).is_equal(0)
	assert_int(spots.filter(func(l: Light3D) -> bool: return l.shadow_enabled).size()).is_equal(mini(BoardgenProps.SHADOW_LAMPS, spots.size()))
	assert_int(spots.filter(func(l: Light3D) -> bool: return not is_equal_approx(l.spot_attenuation, 2.0)).size()).is_equal(0)   # inverse square
	node.apply_detail(false)   # Low: exactly the old lamps
	assert_int(omnis.filter(func(l: Light3D) -> bool: return l.visible).size()).is_equal(omnis.size())
	assert_int(spots.filter(func(l: Light3D) -> bool: return l.visible or l.shadow_enabled).size()).is_equal(0)
	assert_int(omnis.filter(func(l: Light3D) -> bool: return l.shadow_enabled or l.light_color != BoardgenProps.SODIUM or not is_equal_approx(l.light_energy, 0.6)).size()).is_equal(0)
