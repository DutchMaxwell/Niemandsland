extends GdUnitTestSuite
## BoardgenTownWater (look plan R18): the fountain holds water - one surface per fountain, inside the basin wall, above the kit's own
## water plane, drawn only (no collider, no shadow).

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"


## The recorded layout as a town with one fountain (2 x 2 cells at (2, 6): centre (-15, -3) in on the 48 in board).
func _town() -> Dictionary:
	var layout: Dictionary = str_to_var(FileAccess.get_file_as_string(FIXTURE))
	layout["theme"] = "RuinTown"
	layout["landmarks"] = [{"kind": "TankCluster", "x": 2, "z": 6, "w": 2, "h": 2, "turn": 0, "terrain": 2, "solid": true},
		{"kind": "Sump", "x": 9, "z": 6, "w": 2, "h": 2, "turn": 0, "terrain": 1, "solid": false}]
	return layout


func test_one_octagon_of_water_per_fountain_inside_the_basin_wall() -> void:
	var inner_off := BoardgenGreybox.FOUNTAIN_APOTHEM_IN - BoardgenGreybox.FOUNTAIN_WALL_IN * 0.5   # the kit-off wall's inner face
	var inner_kit := BoardgenTownWater.KIT_WALL_CORNER_IN * cos(PI / 8.0)   # the kit basin's inner face (apothem)
	for kit_props: bool in [false, true]:
		var list := BoardgenTownWater.surfaces(_town(), kit_props)
		assert_int(list.size()).override_failure_message("a fountain without water (kit %s)" % kit_props).is_equal(1)
		if list.size() != 1:
			continue
		var s: Dictionary = list[0]
		assert_bool(s["octagon"]).is_true()
		assert_vector(s["centre_in"]).is_equal_approx(Vector2(-15.0, -3.0), Vector2.ONE * 0.001)
		assert_float(s["half_in"].x).is_less(inner_kit if kit_props else inner_off)
		assert_float(s["half_in"].x).is_greater(1.5)
		if kit_props:
			assert_float(s["y_in"]).override_failure_message("under the kit's own water plane").is_greater(BoardgenTownWater.KIT_WATER_IN)
		else:
			assert_float(s["y_in"]).is_between(BoardgenGreybox.FOUNTAIN_WATER_IN, BoardgenGreybox.FOUNTAIN_RIM_IN)


func test_the_water_is_drawn_only() -> void:
	var water: Node3D = auto_free(BoardgenTownWater.build(_town(), false))
	assert_object(water).is_not_null()
	if water == null:
		return
	var planes := water.find_children("*", "MeshInstance3D", true, false)
	assert_int(planes.size()).is_equal(1)
	assert_array(water.find_children("*", "CollisionObject3D", true, false)).is_empty()
	for mi: MeshInstance3D in planes:
		assert_int(mi.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_str((mi.material_override as ShaderMaterial).shader.resource_path).is_equal("res://shaders/ruintown_water.gdshader")


func test_the_kit_off_fountain_draws_no_hazard_strips_and_a_town_builds_its_water() -> void:
	var parts := BoardgenGreybox.plan(_town()).filter(func(b: Dictionary) -> bool: return b.get("lm", "") == "TankCluster")
	assert_bool(parts.any(func(b: Dictionary) -> bool: return b["kind"] == "hazard")).override_failure_message("the black hazard strips are back in the basin").is_false()
	var board: BoardgenGreybox = auto_free(BoardgenGreybox.new())
	add_child(board)
	board.build(_town())
	assert_object(board.get_node_or_null("TownWater")).override_failure_message("the town builds no water").is_not_null()


func test_ultra_gets_less_sheen_and_the_preset_reaches_every_surface() -> void:
	assert_float(BoardgenTownWater.sheen_for(GraphicsSettings.QualityPreset.ULTRA)).is_less(BoardgenTownWater.sheen_for(GraphicsSettings.QualityPreset.MEDIUM))
	assert_float(BoardgenTownWater.sheen_for(GraphicsSettings.QualityPreset.HIGH)).is_equal(BoardgenTownWater.sheen_for(GraphicsSettings.QualityPreset.MEDIUM))
	var water: Node3D = auto_free(BoardgenTownWater.build(_town(), true))
	BoardgenTownWater.apply_preset(water, GraphicsSettings.QualityPreset.ULTRA)
	for mi: MeshInstance3D in water.find_children("*", "MeshInstance3D", false, false):
		assert_float(float((mi.material_override as ShaderMaterial).get_shader_parameter("sheen"))).is_equal(BoardgenTownWater.SHEEN_ULTRA)
