extends GdUnitTestSuite
## The theme table of a generated board (BoardgenTheme) and the ruin-town greybox: the town draws none of the Deepworks dressing (no pipe,
## lamp or tank), knows its own surface kinds and colours, and marks the level-0 rest of a half-collapsed house as a yard. The town layout
## is the recorded seed-42 one with its `theme` key set, so this suite stands on its own (no live core needed).

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"
const DEEPWORKS_DRESSING := ["Props", "Landmarks", "Debris", "Sumps", "Rails"]


func _fixture() -> Dictionary:
	return str_to_var(FileAccess.get_file_as_string(FIXTURE))


func _town() -> Dictionary:
	var layout := _fixture()
	layout["theme"] = "RuinTown"
	return layout


func _built(layout: Dictionary) -> BoardgenGreybox:
	var node: BoardgenGreybox = auto_free(BoardgenGreybox.new())
	add_child(node)
	node.build(layout)
	return node


func test_a_town_board_draws_no_pipe_lamp_or_tank() -> void:
	var node := _built(_town())
	for dressing in DEEPWORKS_DRESSING:
		assert_object(node.find_child(dressing, false, false)).override_failure_message("a town board built %s" % dressing).is_null()
	assert_object(node.find_child("Surfaces", false, false)).is_not_null()
	assert_object(node.find_child("Colliders", false, false)).is_not_null()
	assert_str(node.layout_theme).is_equal("RuinTown")


func test_a_deepworks_board_keeps_all_its_dressing() -> void:
	var node := _built(_fixture())
	for dressing in DEEPWORKS_DRESSING:
		assert_object(node.find_child(dressing, false, false)).override_failure_message("a Deepworks board lost %s" % dressing).is_not_null()


func test_the_theme_table_names_shader_kinds_and_one_colour_per_kind() -> void:
	var town := BoardgenTheme.of(_town())
	assert_str(town["id"]).is_equal("RuinTown")
	assert_str((town["shader"] as Shader).resource_path).is_equal("res://shaders/ruintown_board.gdshader")
	assert_int(town["palette"].size()).is_equal(town["kinds"].size())
	assert_array(town["kinds"].slice(0, BoardgenGreybox.KINDS.size())).is_equal(BoardgenGreybox.KINDS)   # the town extends the Deepworks seven
	assert_array(town["dressing"]).is_empty()
	for layout in [_fixture(), {"theme": "Nowhere"}]:   # no key, or an id the table does not know = Deepworks
		var deep := BoardgenTheme.of(layout)
		assert_str(deep["id"]).is_equal("Deepworks")
		assert_array(deep["kinds"]).is_equal(BoardgenGreybox.KINDS)
		assert_array(deep["dressing"]).is_equal(DEEPWORKS_DRESSING)
		assert_str((deep["shader"] as Shader).resource_path).is_equal("res://shaders/tiefwerk_board.gdshader")


func test_a_town_marks_the_level_0_rest_of_a_terrace_as_a_yard() -> void:
	var town := _town()
	var want := 0
	for c: Dictionary in town["cells"]:
		want += int(c["level"] == 0 and c["lot_kind"] == "Terrace" and not c["street"])
	assert_int(want).is_greater(0)
	var area := 0.0
	for b in BoardgenGreybox.plan(town):
		assert_bool(BoardgenTheme.TOWN_KINDS.has(b["kind"])).override_failure_message("the town plan has a kind its shader lacks: %s" % b["kind"]).is_true()
		if b["kind"] == "yard":
			area += (b["hi"].x - b["lo"].x) * (b["hi"].z - b["lo"].z)
	assert_float(area).is_equal(want * 9.0)
	for b in BoardgenGreybox.plan(_fixture()):
		assert_str(b["kind"]).is_not_equal("yard")


func test_the_town_material_gets_its_shader_and_a_palette_and_each_box_its_town_kind() -> void:
	var town := _town()
	var mat := (_built(town).find_child("Surfaces", false, false) as MultiMeshInstance3D).material_override as ShaderMaterial
	assert_str(mat.shader.resource_path).is_equal("res://shaders/ruintown_board.gdshader")
	assert_int((mat.get_shader_parameter("palette") as PackedColorArray).size()).is_equal(BoardgenTheme.TOWN_KINDS.size())
	for b in BoardgenGreybox.plan(town):
		assert_float(BoardgenGreybox.custom_data(b, BoardgenTheme.TOWN_KINDS).r).is_equal(float(BoardgenTheme.TOWN_KINDS.find(b["kind"])))


## The recorded layout with one landmark of every kind (a fountain, a statue plinth, a pool, a hall mark) standing on the board's cells.
func _town_with_every_landmark() -> Dictionary:
	var layout := _town()
	layout["landmarks"] = [{"kind": "TankCluster", "x": 2, "z": 6, "w": 2, "h": 2, "turn": 0, "terrain": 2, "solid": true},
		{"kind": "Crane", "x": 6, "z": 6, "w": 1, "h": 1, "turn": 0, "terrain": 2, "solid": true},
		{"kind": "Sump", "x": 9, "z": 6, "w": 2, "h": 2, "turn": 0, "terrain": 1, "solid": false},
		{"kind": "PumpHouse", "x": 12, "z": 6, "w": 2, "h": 2, "turn": 0, "terrain": 0, "solid": false}]
	return layout


func test_a_town_draws_each_landmark_as_plain_boxes_inside_its_footprint() -> void:
	var layout := _town_with_every_landmark()
	var by_landmark := {}
	for b in BoardgenGreybox.plan(layout):
		if b.has("landmark"):
			by_landmark[b["landmark"]] = by_landmark.get(b["landmark"], []) + [b]
	assert_int(by_landmark.size()).is_equal(4)
	if by_landmark.size() != 4:
		return
	for i in 4:
		var lm: Dictionary = layout["landmarks"][i]
		var lo := Vector2(lm["x"], lm["z"]) * 3.0 - Vector2(24.0, 24.0)
		var hi := lo + Vector2(lm["w"], lm["h"]) * 3.0
		for b: Dictionary in by_landmark[i]:
			assert_bool(b["lo"].x >= lo.x - 0.001 and b["lo"].z >= lo.y - 0.001 and b["hi"].x <= hi.x + 0.001 and b["hi"].z <= hi.y + 0.001).override_failure_message("%s draws outside its footprint" % lm["kind"]).is_true()
			match lm["kind"]:
				"TankCluster", "Crane":
					assert_array([b["kind"], b["solid"], b["hi"].y]).is_equal(["stone", true, 2.5])
					assert_vector(b["hi"] - b["lo"]).is_equal_approx(Vector3(lm["w"] * 3.0, 2.5, lm["h"] * 3.0), Vector3.ONE * 0.001)   # the whole footprint, no taller than the core's container
				"Sump":
					assert_array([b["kind"], b["solid"]]).is_equal(["hazard", false])
					assert_float(b["hi"].y).is_less(0.08)
				"PumpHouse":
					assert_array([b["kind"], b["solid"]]).is_equal(["rim", false])
					assert_float(b["hi"].y - b["lo"].y).is_equal_approx(0.3, 0.001)
	assert_int(by_landmark[3].size()).is_equal(4)   # the rim is four slabs
	var rim_area := 0.0
	for b: Dictionary in by_landmark[3]:
		rim_area += (b["hi"].x - b["lo"].x) * (b["hi"].z - b["lo"].z)
	assert_float(rim_area).is_equal_approx(6.0 * 6.0 - 5.4 * 5.4, 0.001)   # a 0.3 in line round the 6 x 6 in footprint, no overlap, no gap


func test_a_deepworks_plan_has_no_landmark_boxes_and_the_town_gets_the_solid_ones_a_collider() -> void:
	var deep := _fixture()
	deep["landmarks"] = _town_with_every_landmark()["landmarks"]
	assert_bool(BoardgenGreybox.plan(deep).any(func(b: Dictionary) -> bool: return b.has("landmark"))).is_false()   # Deepworks draws its landmarks as meshes
	var layout := _town_with_every_landmark()
	var solids := BoardgenGreybox.plan(layout).filter(func(b: Dictionary) -> bool: return b.has("landmark") and b["solid"])
	assert_int(solids.size()).is_equal(2)
	var body := _built(layout).find_child("Colliders", false, false) as StaticBody3D
	assert_int(body.get_child_count()).is_equal(BoardgenGreybox.plan(layout).filter(func(b: Dictionary) -> bool: return b["solid"]).size())


func _put(layout: Dictionary, x: int, z: int, level: int, kind: String) -> void:
	var c: Dictionary = layout["cells"][z * 16 + x]
	c["level"] = level
	c["lot_kind"] = kind
	c["street"] = false


## The recorded town with an intact house (2 x 2, lot 99), a wall run (stair 3 in, ridge 6 in, tower 9 in, breach at ground) and a garden plot.
func _town_with_wall_house_and_plot() -> Dictionary:
	var layout := _town()
	for dz in 2:
		for dx in 2:
			_put(layout, dx, dz, 0, "Roofed")
	layout["lots"].append({"id": 99, "x": 0, "z": 0, "w": 2, "h": 2, "sector": [0, 0], "kind": "Roofed"})
	for spec in [[5, 5, 1], [5, 6, 2], [5, 7, 3], [5, 8, 0]]:
		_put(layout, spec[0], spec[1], spec[2], "Wall")
	_put(layout, 8, 5, 0, "Rough")
	return layout


func test_a_town_draws_its_wall_its_plots_and_its_intact_houses_with_kinds_of_their_own() -> void:
	var boxes := BoardgenGreybox.plan(_town_with_wall_house_and_plot())
	var of := func(kind: String) -> Array: return boxes.filter(func(b: Dictionary) -> bool: return b["kind"] == kind)
	var roofed: Array = of.call("roofed")
	assert_int(roofed.size()).is_greater(0)
	for b: Dictionary in roofed:
		assert_array([b["solid"], b["hi"].y]).is_equal([true, 2.5])   # the body is as high as the core's solid
	var chimneys: Array = of.call("brick")
	assert_int(chimneys.size()).is_equal(1)   # one chimney on lot 99's roof
	for b: Dictionary in chimneys:
		assert_array([b["solid"], b["lo"].y, b["hi"].y > 2.5]).is_equal([false, 2.5, true])   # it rises from the body, visual only
	var wall_tops: Array = of.call("wall").filter(func(b: Dictionary) -> bool: return not b.has("merlon")).map(func(b: Dictionary) -> float: return b["hi"].y)
	wall_tops.sort()
	assert_array(wall_tops).is_equal([3.0, 6.0, 9.0])
	assert_int(of.call("rubble").filter(func(b: Dictionary) -> bool: return not b.has("prop")).size()).is_equal(1)   # the breach cell itself (its stones are props)
	assert_int(of.call("rough").size()).is_equal(1)


func test_a_deepworks_plan_never_uses_the_town_kinds() -> void:
	var layout := _town_with_wall_house_and_plot()
	layout.erase("theme")
	for b in BoardgenGreybox.plan(layout):
		assert_bool(BoardgenGreybox.KINDS.has(b["kind"])).override_failure_message("a Deepworks box of kind %s" % b["kind"]).is_true()


func test_an_intact_house_gets_a_roof_over_its_body_and_the_halves_vary_the_pitch() -> void:
	var layout := _town_with_wall_house_and_plot()
	var roofs := BoardgenTownDressing.roofs(layout)
	var mains := roofs.filter(func(r: Dictionary) -> bool: return not r["annex"])
	assert_int(mains.size()).is_equal(1)   # one main roof per intact lot (an annex, if the lot has one, comes on top)
	var r: Dictionary = mains[0]
	assert_int(r["lot"]).is_equal(99)
	assert_float(r["length"]).is_equal_approx(6.6 if roofs.size() == 1 else 3.6, 0.001)   # the 6 in lot and an overhang each side; an annex takes one 3 in cell off the main roof
	assert_float(r["height"]).is_between(1.5, 2.7)
	assert_int(BoardgenTownDressing.prism_mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()).is_equal(18)   # two slopes and two gable ends
	var node: BoardgenTownDressing = auto_free(BoardgenTownDressing.new())
	add_child(node)
	node.build(layout, ShaderMaterial.new())
	var drawn := 0
	for n in ["Roofs", "RoofsHip", "RoofsCatslide"]:
		drawn += (node.find_child(n, false, false) as MultiMeshInstance3D).multimesh.instance_count
	var pieces := 0   # (L1 / L2) every planned roof is in one of the three type meshes: one prism per ridge strip, a broken strip as its pieces
	var boxes := 0
	for rf: Dictionary in roofs:
		for st: Dictionary in BoardgenTownDressing.ridge_strips(rf):
			pieces += BoardgenTownDressing.roof_parts(st)[0].size()
			boxes += BoardgenTownDressing.roof_parts(st)[1].size()
	assert_int(drawn).is_equal(pieces)
	assert_int((node.find_child("RoofDamage", false, false) as MultiMeshInstance3D).multimesh.instance_count).is_equal(boxes)
	assert_int(node.find_children("*", "CollisionShape3D", true, false).size()).is_equal(0)   # nobody stands on a roof
	var differing := 0
	for id in range(1, 40):
		differing += int(not is_equal_approx(BoardgenTownDressing._hash(id, 0, 2), BoardgenTownDressing._hash(id, 1, 2)))
	assert_int(differing).is_greater(30)   # the two halves pick other pitches for the same lot id


func test_the_wall_and_the_towers_are_crowned_with_merlons_inside_the_edge_strip_and_the_south_loses_more() -> void:
	var layout := _town_with_wall_house_and_plot()   # a 6 in wall cell (5,6) and a 9 in one (5,7) on the recorded board
	var merlons := BoardgenTownDressing.merlons(layout).filter(func(b: Dictionary) -> bool: return b.has("merlon"))
	assert_int(merlons.size()).is_greater(0)
	for b: Dictionary in merlons:
		var size: Vector3 = b["hi"] - b["lo"]
		assert_bool(b["solid"]).is_false()
		assert_bool(minf(size.x, size.z) <= 0.4001 and maxf(size.x, size.z) <= 0.7001 and size.y <= 0.7001).override_failure_message("a merlon outside the edge strip: %s" % size).is_true()
		assert_bool(b["lo"].y == 6.0 or b["lo"].y == 9.0).is_true()   # on the 6 in ridge or the 9 in crown only
	# a wall of 8 cells in a row has merlons on both sides: far more in the south half than missing ones in the north (hash rates 0.28 / 0.10)
	var big := _town()
	for z in range(0, 16):
		_put(big, 4, z, 2, "Wall")
		_put(big, 11, z, 2, "Wall")
	var count := func(north: bool) -> int:
		return BoardgenTownDressing.merlons(big).filter(func(b: Dictionary) -> bool: return (b["lo"].z < 0.0) == north and b.has("merlon")).size()
	assert_int(count.call(true)).is_greater(count.call(false))   # the north half keeps more of its battlements


func test_the_town_has_no_tiefwerk_mist_or_steam_and_a_deepworks_board_keeps_both() -> void:
	assert_array(BoardgenTheme.of(_town())["atmosphere"]).is_empty()
	assert_array(BoardgenTheme.of(_fixture())["atmosphere"]).is_equal(["Mist", "Steam"])
	var node := _built(_town())
	node.refresh_atmosphere()
	assert_object(node.get_node_or_null("Mist")).is_null()
	assert_object(node.get_node_or_null("Steam")).is_null()


func test_the_town_has_lanterns_at_the_square_and_the_gates_inside_the_edge_strip_and_at_most_eight_lights() -> void:
	var layout := _town_with_wall_house_and_plot()
	var lanterns := BoardgenTownDressing.lanterns(layout)
	assert_int(lanterns.size()).is_greater_equal(4)   # the four corners of the square, plus a post at a gate where a street crosses the wall
	var boxes := BoardgenTownDressing.lantern_boxes(layout)
	assert_int(boxes.size()).is_equal(lanterns.size() * 2)   # a post and a lantern each
	for b: Dictionary in boxes:
		assert_bool(b["solid"]).is_false()   # nothing here takes standing room or a collider
		assert_float(minf((b["hi"] - b["lo"]).x, (b["hi"] - b["lo"]).z)).is_less(0.41)
	var node: BoardgenTownDressing = auto_free(BoardgenTownDressing.new())
	add_child(node)
	node.build(layout, ShaderMaterial.new())
	var lights := node.find_children("*", "SpotLight3D", false, false)
	assert_int(lights.size()).is_equal(mini(lanterns.size(), BoardgenTownDressing.MAX_LIGHTS))
	assert_int(lights.filter(func(l: Light3D) -> bool: return l.shadow_enabled).size()).is_less_equal(4)
	for l: SpotLight3D in lights:
		assert_float((l.global_transform.basis * Vector3.FORWARD).y).override_failure_message("a lantern cone points down").is_less(-0.99)   # SpotLight3D shines along -Z; rotated -90 deg about x it looks down
		assert_object(l.light_projector).is_not_null()
		assert_float(l.light_energy).is_less_equal(5.0)   # lit plaster must not clip (measured at 3.5: <= 0.2 % of pixels above 0.95)
	var fills := node.find_children("LanternFill*", "OmniLight3D", false, false)   # a weak wide fill inside each pool: no hard black rim
	assert_int(fills.size()).is_equal(lights.size())
	for f: OmniLight3D in fills:
		assert_float(f.light_energy).is_less_equal(0.1)
		assert_bool(f.shadow_enabled).is_false()
		assert_float(f.light_specular).is_equal(0.0)
	assert_int(BoardgenTheme.TOWN_PALETTE.size()).is_equal(BoardgenTheme.TOWN_KINDS.size())


func test_dusk_is_a_blue_hour_two_pale_moons_a_half_turn_apart_and_a_cool_sky() -> void:
	var seen := {}
	var lc := RefCounted.new()
	lc.set_script(preload("res://test/fixtures/boardgen/lighting_stub.gd"))
	var fill := DirectionalLight3D.new()
	add_child(fill)
	var keylight := DirectionalLight3D.new()
	add_child(keylight)
	lc._directional_light = keylight
	lc._fill_light = fill
	BoardgenTownDressing.dusk(lc)
	var sun: Color = lc.calls["set_sun_color"]
	assert_float(sun.b).is_greater(sun.r)   # the key is a cool pale moon
	assert_float(lc.calls["set_sun_angles"][1]).is_greater_equal(40.0)   # high
	# the second moon (the scene's fill light): the same colour, nearly the same energy, the half turn of the key - the board is a half-turn mirror, so its light is too (gate at both players' sides)
	assert_object(lc.calls["set_fill_light_color"]).is_equal(sun)
	assert_float(lc.calls["set_fill_light_energy"]).is_between(0.85 * lc.calls["set_sun_energy"], 1.15 * lc.calls["set_sun_energy"])
	var h: float = deg_to_rad(lc.calls["set_sun_angles"][0])
	var v: float = deg_to_rad(lc.calls["set_sun_angles"][1])
	var key := Vector3(cos(v) * sin(h), sin(v), cos(v) * cos(h))
	var other := fill.position.normalized()
	assert_float(Vector2(key.x, key.z).normalized().dot(Vector2(other.x, other.z).normalized())).override_failure_message("the second moon must stand opposite the first").is_less(-0.99)
	assert_float(other.y).is_equal_approx(key.y, 0.001)   # at the same height
	assert_float(BoardgenTownDressing.MOON_SPECULAR).override_failure_message("a strong pale light with full specular washes the glossy pawns' colours white").is_less_equal(0.3)
	assert_float(fill.light_specular).is_less_equal(0.3)
	assert_float(keylight.light_specular).is_less_equal(0.3)
	assert_float((lc.calls["set_ambient_color"] as Color).b).is_greater((lc.calls["set_ambient_color"] as Color).r)   # cool sky
	assert_float(BoardgenTownDressing.LANTERN_COLOUR.r).is_greater(BoardgenTownDressing.LANTERN_COLOUR.b)   # the lanterns are the only strong warm source
	BoardgenTownDressing.dusk(null)   # no lighting controller (a table without one): nothing happens
	assert_bool(seen.is_empty()).is_true()
	fill.free()
	keylight.free()


func test_props_stand_in_the_strip_beside_a_wall_face_and_never_on_a_street_a_plot_or_a_ladder_foot() -> void:
	var layout := _town()   # the recorded board with the town theme
	var props := BoardgenTownDressing.props(layout)
	assert_int(props.size()).is_greater(0)
	var feet := {}
	for c: Dictionary in layout["connectors"]:
		feet[int(c["low"])] = true
		feet[int(c["high"])] = true
	for b: Dictionary in props:
		var size: Vector3 = b["hi"] - b["lo"]
		assert_bool(b["solid"]).is_false()
		assert_float(minf(size.x, size.z)).is_less(0.71)   # inside the 0.75 in strip
		var centre: Vector3 = (b["hi"] + b["lo"]) * 0.5
		var cx := int(floor(centre.x / 3.0 + 8.0))
		var cz := int(floor(centre.z / 3.0 + 8.0))
		var cd: Dictionary = layout["cells"][cz * 16 + cx]
		assert_bool(cd["street"] or cd["level"] != 0 or feet.has(cz * 16 + cx) or ["Hazard", "Rough", "Wall", "Roofed"].has(cd["lot_kind"])).override_failure_message("a prop on %s" % cd).is_false()
	# both halves get props, and the same cell decides differently in the north and the south (the half is part of the hash)
	var north := props.filter(func(b: Dictionary) -> bool: return b["lo"].z < 0.0).size()
	assert_bool(north > 0 and north < props.size()).is_true()
	var differing := 0
	for i in range(1, 60):
		differing += int(not is_equal_approx(BoardgenTownDressing._hash(i, 0, 40), BoardgenTownDressing._hash(i, 1, 40)))
	assert_int(differing).is_greater(50)


func test_a_breach_is_strewn_with_flat_stones() -> void:
	var layout := _town_with_wall_house_and_plot()   # a breach at (5, 8)
	var rubble := BoardgenTownDressing.breach_rubble(layout)
	assert_int(rubble.size()).is_equal(8)
	for b: Dictionary in rubble:
		assert_float(b["hi"].y).is_less(0.26)   # flat enough to stand on


## Silhouette round (21.11.): a wall ridge carries its parapet on the field side only (x < 8: west, else east); the town side of the walk stays open.
func test_a_wall_ridge_has_merlons_on_its_field_side_only() -> void:
	var big := _town()
	for z in range(0, 16):
		_put(big, 4, z, 2, "Wall")
		_put(big, 11, z, 2, "Wall")
	var merlons := BoardgenTownDressing.merlons(big)
	assert_int(merlons.size()).is_greater(20)
	for b: Dictionary in merlons:
		var x: float = (b["lo"].x + b["hi"].x) * 0.5
		assert_bool(x < -24.0 + 4.0 * 3.0 + 0.5 or x > -24.0 + 12.0 * 3.0 - 0.5).override_failure_message("a merlon on the town side at x = %f" % x).is_true()


## R7a: the cookie is a 128 px picture with a hot core, a fall-off to the rim and thin dark frame bars across the pool.
func test_the_lantern_cookie_has_a_hot_core_a_falloff_and_frame_bars() -> void:
	var img := BoardgenTownDressing.lantern_projector().get_image()
	assert_int(img.get_width()).is_equal(128)
	var core := img.get_pixel(64, 64).r
	var off_axis := img.get_pixel(64 + 24, 64 + 24).r   # diagonal, clear of the bars
	var on_bar := img.get_pixel(64 + 24, 64).r   # along the x axis: a frame bar
	var rim := img.get_pixel(127, 64).r
	assert_float(core).is_greater(off_axis)
	assert_float(on_bar).override_failure_message("no bar shadow: %f vs %f" % [on_bar, off_axis]).is_less(off_axis * 0.7)
	assert_float(rim).is_less(0.05)   # the pool fades out inside the cone


## R7a: a lantern without a shadow map must not reach the far side of a wall - its pool on the ground stays inside a 3 in cell; only the shadowed ones may throw a wide pool.
func test_an_unshadowed_lantern_throws_no_pool_wider_than_a_cell() -> void:
	for i in BoardgenTownDressing.MAX_LIGHTS:
		var radius := BoardgenTownDressing.LANTERN_HEIGHT_IN * tan(deg_to_rad(BoardgenTownDressing.lantern_cone_deg(i)))
		if i >= BoardgenTownDressing.SHADOWED_LANTERNS:
			assert_float(radius).override_failure_message("lantern %d (no shadow) throws a %.1f in pool: light through a wall" % [i, radius]).is_less_equal(3.0)
		else:
			assert_float(radius).is_greater(3.0)   # the wide ones are the point of the cone


## R7b: board-scale occlusion, one probe rendered once, and one window in eight lit.
func test_the_blue_hour_sets_board_scale_occlusion_and_the_board_has_one_probe_rendered_once() -> void:
	var lc := RefCounted.new()
	lc.set_script(preload("res://test/fixtures/boardgen/lighting_stub.gd"))
	BoardgenTownDressing.dusk(lc)
	assert_float(lc.calls["set_ssao_radius"]).override_failure_message("the preset's SSAO radius (0.8 - 1.2 m) is wider than the whole board").is_less_equal(0.1)
	assert_float(lc.calls["set_ssao_intensity"]).is_greater(1.0)
	assert_float(lc.calls["set_sdfgi_energy"]).override_failure_message("the Ultra bounce light (1.1) lifted the lit walls round the models: the blue hour turns it down").is_less_equal(0.6)
	assert_float(lc.calls["set_ssil_intensity"]).is_less_equal(0.6)
	assert_float(lc.calls["set_sun_angles"][0]).override_failure_message("the key comes from the play camera's side (azimuth near -20)").is_between(-30.0, -10.0)
	var node: BoardgenTownDressing = auto_free(BoardgenTownDressing.new())
	add_child(node)
	node.build(_town_with_wall_house_and_plot(), ShaderMaterial.new())
	var probes := node.find_children("*", "ReflectionProbe", false, false)
	assert_int(probes.size()).is_equal(1)
	assert_int((probes[0] as ReflectionProbe).update_mode).is_equal(ReflectionProbe.UPDATE_ONCE)
	assert_float((probes[0] as ReflectionProbe).size.x).is_greater(0.8)   # it covers the board
	var src := FileAccess.get_file_as_string("res://shaders/ruintown_board.gdshader")
	assert_bool(src.contains("float glow = step(0.875, h21(vec2(cell, seed + 5.0)));")).override_failure_message("one window in eight").is_true()
