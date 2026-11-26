extends GdUnitTestSuite
## The product look of a Tiefwerk board (BoardgenMood, AAA step 5b): board-scale SSAO, the dim light and the grade as RenderState / LightingController
## layers that always come off again, a fill light that reaches the models and never the board, and a hand-over that survives a re-attach.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"
const LUMA := "res://tools/boardgen/town_grade_luma.json"   # the measured mean luma of the stills with and without the town's grade (tools/boardgen/luma_rows.py)


func _fixture() -> Dictionary:
	return str_to_var(FileAccess.get_file_as_string(FIXTURE))


## A stand-in for the game's Main: the two members BoardgenMood reads off the table's parent.
func _main_with(state: RenderState, lighting: Node) -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar render_state\nvar lighting_controller\n"
	script.reload()
	var main: Node = auto_free(Node.new())
	main.set_script(script)
	main.set("render_state", state)
	main.set("lighting_controller", lighting)
	add_child(main)
	var table := Node3D.new()
	table.name = "Table"
	main.add_child(table)
	return main


func _board_on(main: Node) -> BoardgenGreybox:
	var board := BoardgenGreybox.new()
	board.build(_fixture())
	main.get_node("Table").add_child(board)
	return board


func _lighting() -> Node:
	var sun: DirectionalLight3D = auto_free(DirectionalLight3D.new())
	var world: WorldEnvironment = auto_free(WorldEnvironment.new())
	world.environment = Environment.new()
	var controller: Node = auto_free(load("res://scripts/lighting_controller.gd").new())
	add_child(sun)
	add_child(world)
	add_child(controller)
	controller.initialize(sun, world)
	controller.set_meta("sun", sun)
	controller.set_meta("env", world.environment)
	return controller


func test_the_ssao_is_board_scale_not_the_presets_eight_tenths_of_a_metre() -> void:
	var values := BoardgenMood.environment_values()
	assert_float(values["ssao_radius"]).is_less(0.15)   # the board is 1.22 m wide; the Medium preset's 0.8 m radius is two thirds of it
	assert_float(values["ssao_radius"]).is_greater(0.02)
	assert_float(values["ssao_intensity"]).is_greater(GraphicsSettings.PRESETS[GraphicsSettings.QualityPreset.MEDIUM]["ssao_intensity"])
	assert_bool(values["adjustment_color_correction"] is GradientTexture1D).is_true()


func test_the_light_is_dimmer_than_the_moods_sun_and_cool() -> void:
	var look := BoardgenMood.light_look()
	assert_float(look["sun_energy"]).is_less(1.0)
	assert_bool((look["sun_color"] as Color).b > (look["sun_color"] as Color).r).is_true()
	assert_bool((look["ambient_color"] as Color).b > (look["ambient_color"] as Color).r).is_true()


func test_the_board_layer_beats_the_biome_grade_and_the_mood_but_not_calm() -> void:
	var env := Environment.new()
	var state := RenderState.new(env)
	state.set_layer("preset", {"ssao_radius": 0.8})
	state.set_layer("light", {"ssao_intensity": 0.4})
	state.set_layer("grading", {"adjustment_saturation": 1.2, "glow_intensity": 0.5})
	state.set_layer("board", BoardgenMood.environment_values())
	assert_float(env.ssao_radius).is_equal_approx(BoardgenMood.SSAO_RADIUS_M, 0.0001)
	assert_float(env.ssao_intensity).is_equal_approx(BoardgenMood.SSAO_INTENSITY, 0.0001)
	assert_float(env.adjustment_saturation).is_equal_approx(0.97, 0.0001)
	state.set_layer("calm", {"glow_intensity": 0.0})
	assert_float(env.glow_intensity).is_equal_approx(0.0, 0.0001)
	state.set_layer("board", {})   # the board leaves: the mood's own values are back
	assert_float(env.ssao_radius).is_equal_approx(0.8, 0.0001)
	assert_float(env.adjustment_saturation).is_equal_approx(1.2, 0.0001)


func test_the_lighting_controller_holds_the_board_light_through_mood_changes_and_gives_the_mood_back() -> void:
	var lc := _lighting()
	var sun: DirectionalLight3D = lc.get_meta("sun")
	var env: Environment = lc.get_meta("env")
	lc.apply_preset("Warm Sunset")
	var sunset_sun := sun.light_energy
	var sunset_ambient := env.ambient_light_energy
	lc.set_board_look(BoardgenMood.light_look())
	assert_float(sun.light_energy).is_equal_approx(BoardgenMood.SUN_ENERGY, 0.0001)
	assert_float(env.ambient_light_energy).is_equal_approx(BoardgenMood.AMBIENT_ENERGY, 0.0001)
	assert_float(env.tonemap_exposure).is_equal_approx(BoardgenMood.EXPOSURE, 0.0001)
	lc.apply_preset("Cool Overcast")   # the player picks another mood: the board's light stays
	assert_float(sun.light_energy).is_equal_approx(BoardgenMood.SUN_ENERGY, 0.0001)
	assert_bool(sun.light_color.is_equal_approx(BoardgenMood.SUN_COLOUR)).is_true()
	lc.set_sun_scale(0.5)   # the table world's clouds still dim it
	assert_float(sun.light_energy).is_equal_approx(BoardgenMood.SUN_ENERGY * 0.5, 0.0001)
	lc.set_sun_scale(1.0)
	lc.set_board_look({})
	assert_float(sun.light_energy).is_equal_approx(0.8, 0.0001)   # Cool Overcast's own sun
	lc.apply_preset("Warm Sunset")
	assert_float(sun.light_energy).is_equal_approx(sunset_sun, 0.0001)
	assert_float(env.ambient_light_energy).is_equal_approx(sunset_ambient, 0.0001)


func test_the_fill_light_reaches_the_model_layer_only_and_the_boards_visuals_leave_it() -> void:
	var main := _main_with(null, null)
	var board := _board_on(main)
	await await_idle_frame()   # a builder's late children join the board layer on the next frame
	var fill := board.find_child("ModelFill", false, false) as DirectionalLight3D
	assert_object(fill).is_not_null()
	assert_int(fill.light_cull_mask).is_equal(BoardgenMood.MODEL_LAYER)
	assert_bool(fill.shadow_enabled).is_false()
	var meshes := board.find_children("*", "GeometryInstance3D", true, false)
	assert_bool(meshes.size() > 0).is_true()
	for m in meshes:
		assert_int((m as GeometryInstance3D).layers & BoardgenMood.MODEL_LAYER).override_failure_message("%s is on the model layer: the fill light would wash it" % m.name).is_equal(0)
		assert_int((m as GeometryInstance3D).layers & BoardgenMood.BOARD_LAYER).is_equal(BoardgenMood.BOARD_LAYER)


func test_the_look_goes_on_and_off_with_the_board_and_an_old_board_leaving_late_keeps_the_new_ones_look() -> void:
	var env := Environment.new()
	env.ssao_radius = 0.8
	var state := RenderState.new(env)
	var lc := _lighting()
	var sun: DirectionalLight3D = lc.get_meta("sun")
	lc.apply_preset("Warm Sunset")
	var main := _main_with(state, lc)
	var old := _board_on(main)
	BoardgenMood.apply(old, true)
	assert_float(env.ssao_radius).is_equal_approx(BoardgenMood.SSAO_RADIUS_M, 0.0001)
	assert_float(sun.light_energy).is_equal_approx(BoardgenMood.SUN_ENERGY, 0.0001)
	var fresh := _board_on(main)   # a re-attach: the new board is ready before the old one is freed
	BoardgenMood.apply(fresh, true)
	BoardgenMood.apply(old, false)
	assert_float(env.ssao_radius).override_failure_message("the old board's exit took the new board's look away").is_equal_approx(BoardgenMood.SSAO_RADIUS_M, 0.0001)
	assert_bool(fresh.find_child("ModelFill", false, false).visible).is_true()
	assert_bool(old.find_child("ModelFill", false, false).visible).is_false()
	BoardgenMood.apply(fresh, false)
	assert_float(env.ssao_radius).is_equal_approx(0.8, 0.0001)
	assert_float(sun.light_energy).is_equal_approx(1.5, 0.0001)   # Warm Sunset's own sun


func after_test() -> void:
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.MEDIUM


func test_the_ruin_town_gets_the_grade_in_the_board_layer_and_its_own_dusk_as_the_light_look() -> void:
	var values := BoardgenMood.town_values()
	assert_array(values.keys()).contains_exactly_in_any_order(["tonemap_agx_contrast", "adjustment_enabled", "adjustment_contrast", "adjustment_saturation", "sky", "reflected_light_source"])
	var env := Environment.new()
	var state := RenderState.new(env)
	var lc := _lighting()
	var sun: DirectionalLight3D = lc.get_meta("sun")
	lc.apply_preset("Warm Sunset")
	var lit: Environment = lc.get_meta("env")
	var mood_exposure := lit.tonemap_exposure
	var main := _main_with(state, lc)
	var board := _board_on(main)
	BoardgenMood.apply(board, true, true)
	assert_float(lit.tonemap_exposure).override_failure_message("the exposure gain that cancels the grade's darkening did not arrive").is_equal_approx(BoardgenTownDressing.EXPOSURE * BoardgenMood.TOWN_EXPOSURE_GAIN, 0.0001)
	assert_float(env.tonemap_agx_contrast).is_equal_approx(BoardgenMood.TOWN_AGX_CONTRAST, 0.0001)
	assert_float(env.adjustment_contrast).is_equal_approx(BoardgenMood.TOWN_CONTRAST, 0.0001)
	assert_float(env.adjustment_saturation).is_equal_approx(BoardgenMood.TOWN_SATURATION, 0.0001)
	assert_float(sun.light_energy).override_failure_message("the town did not keep its dusk's moon (decision D-N3)").is_equal_approx(BoardgenTownDressing.MOON_ENERGY, 0.0001)   # was Warm Sunset's own 1.5 (re-pinned by plan N4)
	BoardgenMood.apply(board, false, true)
	assert_float(env.adjustment_saturation).is_equal_approx(1.0, 0.0001)
	assert_float(lit.tonemap_exposure).is_equal_approx(mood_exposure, 0.0001)


func test_a_ruin_town_board_shows_the_town_sky_as_a_backdrop_only_and_gives_the_scenes_own_sky_and_reflection_back() -> void:
	var env := Environment.new()
	var star_field := Sky.new()   # the scene's own sky (the game's star field)
	env.sky = star_field
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY   # what the table's reference layer sets
	var main := _main_with(RenderState.new(env), null)
	var board := _board_on(main)
	BoardgenMood.apply(board, true, true)
	assert_object(env.sky).override_failure_message("the town board did not bring its sky").is_same(BoardgenMood.town_sky())
	assert_bool(env.sky.sky_material is ShaderMaterial and (env.sky.sky_material as ShaderMaterial).shader == BoardgenMood.TOWN_SKY_SHADER).is_true()
	assert_int(env.ambient_light_source).override_failure_message("the town sky must not light the board").is_equal(Environment.AMBIENT_SOURCE_COLOR)
	assert_int(env.reflected_light_source).override_failure_message("the town sky must not be reflected (it would light the ground)").is_equal(Environment.REFLECTION_SOURCE_DISABLED)
	BoardgenMood.apply(board, false, true)
	assert_object(env.sky).override_failure_message("the scene's own sky did not come back").is_same(star_field)
	assert_int(env.ambient_light_source).is_equal(Environment.AMBIENT_SOURCE_COLOR)
	assert_int(env.reflected_light_source).override_failure_message("the table's sky reflection did not come back").is_equal(Environment.REFLECTION_SOURCE_SKY)


func test_a_ruin_town_board_puts_the_grade_on_with_the_finer_look_and_takes_it_off_on_low() -> void:
	var core: Object = ClassDB.instantiate("NmlCore") if ClassDB.class_exists("NmlCore") else null
	if core == null or not core.has_method("boardgen_layout_themed"):
		return   # (no NmlCore binding in this run)
	var env := Environment.new()   # (its own AgX contrast is already 1.25: contrast and saturation carry the check)
	var main := _main_with(RenderState.new(env), null)
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.MEDIUM
	var board := BoardgenGreybox.attach(main.get_node("Table"), core.boardgen_layout_themed(7, "ruintown"))
	assert_float(env.adjustment_contrast).is_equal_approx(BoardgenMood.TOWN_CONTRAST, 0.0001)
	assert_float(env.adjustment_saturation).is_equal_approx(BoardgenMood.TOWN_SATURATION, 0.0001)
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.LOW
	board._apply_detail()   # the player switched down: the finer look goes, the table keeps the mood the player chose
	assert_float(env.adjustment_contrast).is_equal_approx(1.0, 0.0001)
	assert_float(env.adjustment_saturation).is_equal_approx(1.0, 0.0001)


func test_the_recorded_luma_measurement_was_taken_with_the_towns_grade_constants() -> void:
	var c: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(LUMA)) as Dictionary)["constants"]
	for pair: Array in [["agx", BoardgenMood.TOWN_AGX_CONTRAST], ["contrast", BoardgenMood.TOWN_CONTRAST], ["saturation", BoardgenMood.TOWN_SATURATION], ["exposure_gain", BoardgenMood.TOWN_EXPOSURE_GAIN]]:
		assert_float(float(c[pair[0]])).override_failure_message("a grade constant changed (%s): measure the stills again with tools/boardgen/luma_rows.py and update town_grade_luma.json" % pair[0]).is_equal_approx(pair[1], 0.0001)


func test_the_graded_play_and_overview_stills_are_not_darker_than_the_ungraded_ones() -> void:
	var luma: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LUMA))
	assert_int((luma["ungraded"] as Dictionary).size()).is_equal(6)   # three boards x overview and play
	for key: String in luma["ungraded"]:
		assert_float(float(luma["graded"][key])).override_failure_message("%s: the grade darkens the town (%s -> %s of 255); the exposure gain has to bring it back" % [key, luma["ungraded"][key], luma["graded"][key]]).is_greater_equal(float(luma["ungraded"][key]))


## Night on a town board (plan N1, decision D-N1): a stand-in for the atmosphere controller (its mood name and its signal) and a lighting controller with a fill light.
func _town_night_main() -> Node:
	var atm_script := GDScript.new()
	atm_script.source_code = "extends Node\nsignal atmosphere_changed(preset_name: String)\nvar current := \"Night\"\nfunc get_current_atmosphere() -> String:\n\treturn current\n"
	atm_script.reload()
	var atmosphere: Node = auto_free(Node.new())
	atmosphere.set_script(atm_script)
	add_child(atmosphere)
	var sun: DirectionalLight3D = auto_free(DirectionalLight3D.new())
	var fill: DirectionalLight3D = auto_free(DirectionalLight3D.new())
	var world: WorldEnvironment = auto_free(WorldEnvironment.new())
	world.environment = Environment.new()
	var lc: Node = auto_free(load("res://scripts/lighting_controller.gd").new())
	for n: Node in [sun, fill, world, lc]:
		add_child(n)
	lc.initialize(sun, world, fill)
	lc.set_meta("sun", sun)
	lc.set_meta("fill", fill)
	lc.set_meta("env", world.environment)
	var script := GDScript.new()
	script.source_code = "extends Node\nvar render_state\nvar lighting_controller\nvar atmosphere_controller\n"
	script.reload()
	var main: Node = auto_free(Node.new())
	main.set_script(script)
	main.set("render_state", RenderState.new(Environment.new()))
	main.set("lighting_controller", lc)
	main.set("atmosphere_controller", atmosphere)
	add_child(main)
	var table := Node3D.new()
	table.name = "Table"
	main.add_child(table)
	return main


func test_under_night_at_medium_the_town_keeps_the_dusks_sky_fill_and_the_presets_moon() -> void:
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.MEDIUM
	var main := _town_night_main()
	var lc: Node = main.get("lighting_controller")
	BoardgenMood.apply(_board_on(main), true, true)
	lc.apply_preset("Night")
	var env: Environment = lc.get_meta("env")
	assert_float(env.ambient_light_energy).override_failure_message("Night at Medium crushed the town's sky fill: %.2f" % env.ambient_light_energy).is_greater_equal(BoardgenTownDressing.AMBIENT_ENERGY)
	assert_float((lc.get_meta("fill") as DirectionalLight3D).light_energy).is_greater_equal(BoardgenTownDressing.MOON2_ENERGY)
	assert_float((lc.get_meta("sun") as DirectionalLight3D).light_energy).is_equal_approx(1.6, 0.0001)   # the Night preset's own moon key
	assert_float(float(lc.current_preset["ambient_energy"])).is_equal_approx(0.3, 0.0001)   # the mood keeps its own value for when the board leaves


func test_another_mood_takes_the_night_floor_away_and_gives_the_towns_dusk() -> void:
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.MEDIUM
	var main := _town_night_main()
	var lc: Node = main.get("lighting_controller")
	BoardgenMood.apply(_board_on(main), true, true)
	var atmosphere: Node = main.get("atmosphere_controller")
	atmosphere.set("current", "Sunset")
	atmosphere.emit_signal("atmosphere_changed", "Sunset")
	assert_bool(lc.get("_board_look").has("ambient_energy_min")).is_false()
	assert_bool(lc.get("_board_look").has("fill_light_energy_min")).is_false()
	lc.apply_preset("Warm Sunset")
	assert_float((lc.get_meta("env") as Environment).ambient_light_energy).is_equal_approx(BoardgenTownDressing.AMBIENT_ENERGY, 0.0001)   # the dusk's sky fill (was Warm Sunset's own 0.7 before plan N4)


func test_with_bounce_light_night_gets_no_floor() -> void:
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.ULTRA
	var main := _town_night_main()
	var lc: Node = main.get("lighting_controller")
	BoardgenMood.apply(_board_on(main), true, true)
	assert_bool(lc.get("_board_look").has("ambient_energy_min")).override_failure_message("High / Ultra have SDFGI and SSIL: no Night floor there").is_false()
	assert_bool(BoardgenMood.town_look(true, true).has("ambient_energy_min") or BoardgenMood.town_look(true, true).has("fill_light_energy_min")).is_false()


## D-G5 (both player sides see the same board under Night): after a blended pick the table rig turns the scene's fill light to (-42, 20), from one
## player's side. A town board keeps it across the axis between the deployment zones, where the dusk put it, under every mood.
func test_the_table_rig_leaves_the_town_fill_across_the_axis() -> void:
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.MEDIUM
	var main := _town_night_main()
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	main.add_child(fill)
	BoardgenMood.apply(_board_on(main), true, true)
	var rig := load("res://scripts/visual/table_lighting.gd")
	var biomes := load("res://scripts/visual/reference_biomes.gd")
	rig.apply(main, biomes.GRASSLAND, "Night")
	var across := Vector3(-BoardgenTownDressing.MOON_ELEVATION, BoardgenTownDressing.MOON_AZIMUTH - 180.0, 0.0)
	assert_bool(fill.rotation_degrees.is_equal_approx(across)).override_failure_message("the fill came from one side: %s" % fill.rotation_degrees).is_true()
	var atmosphere: Node = main.get("atmosphere_controller")
	atmosphere.set("current", "Sunset")
	atmosphere.emit_signal("atmosphere_changed", "Sunset")
	rig.apply(main, biomes.GRASSLAND, "Sunset")
	assert_bool(fill.rotation_degrees.is_equal_approx(across)).is_true()   # (was the rig's own (-42, 20) before plan N4: then Sunset was the biome's light)


## Decision D-N3 (plan N4): a mood picked in the lighting panel ends in the town's own light - the dusk for every mood but Night, Night's moon under Night -
## not in the table biome's light (audit X7: the blend ends with the table rig writing the biome's sunset through these setters).
func test_a_picked_mood_ends_in_the_towns_dusk_and_night_in_the_presets_moon() -> void:
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.MEDIUM
	var main := _town_night_main()
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	main.add_child(fill)
	var lc: Node = main.get("lighting_controller")
	var sun: DirectionalLight3D = lc.get_meta("sun")
	var env: Environment = lc.get_meta("env")
	var atmosphere: Node = main.get("atmosphere_controller")
	BoardgenMood.apply(_board_on(main), true, true)
	var rig := load("res://scripts/visual/table_lighting.gd")
	var biomes := load("res://scripts/visual/reference_biomes.gd")
	atmosphere.set("current", "Sunset")
	atmosphere.emit_signal("atmosphere_changed", "Sunset")
	lc.apply_preset("Warm Sunset")   # the blend's end ...
	rig.apply(main, biomes.GRASSLAND, "Sunset")   # ... and the table rig after it
	assert_float(sun.light_energy).override_failure_message("a picked Sunset ended in the biome's sun %.2f" % sun.light_energy).is_equal_approx(BoardgenTownDressing.MOON_ENERGY, 0.0001)
	assert_float(env.ambient_light_energy).is_equal_approx(BoardgenTownDressing.AMBIENT_ENERGY, 0.0001)
	assert_float(sun.position.normalized().y).is_equal_approx(sin(deg_to_rad(BoardgenTownDressing.MOON_ELEVATION)), 0.001)   # the moon's height, not the biome's sunset
	atmosphere.set("current", "Night")
	atmosphere.emit_signal("atmosphere_changed", "Night")
	lc.apply_preset("Night")
	rig.apply(main, biomes.GRASSLAND, "Night")
	assert_float(sun.light_energy).is_equal_approx(1.6, 0.0001)   # Night's own moon key
