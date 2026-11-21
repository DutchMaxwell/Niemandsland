extends GdUnitTestSuite
## The product look of a Tiefwerk board (BoardgenMood, AAA step 5b): board-scale SSAO, the dim light and the grade as RenderState / LightingController
## layers that always come off again, a fill light that reaches the models and never the board, and a hand-over that survives a re-attach.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"


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


func test_the_board_layer_beats_the_biome_grade_and_the_mood_but_not_the_intro_or_calm() -> void:
	var env := Environment.new()
	var state := RenderState.new(env)
	state.set_layer("preset", {"ssao_radius": 0.8})
	state.set_layer("light", {"ssao_intensity": 0.4})
	state.set_layer("grading", {"adjustment_saturation": 1.2, "glow_intensity": 0.5})
	state.set_layer("board", BoardgenMood.environment_values())
	assert_float(env.ssao_radius).is_equal_approx(BoardgenMood.SSAO_RADIUS_M, 0.0001)
	assert_float(env.ssao_intensity).is_equal_approx(BoardgenMood.SSAO_INTENSITY, 0.0001)
	assert_float(env.adjustment_saturation).is_equal_approx(0.97, 0.0001)
	state.set_layer("intro", {"glow_intensity": 0.9})
	assert_float(env.glow_intensity).is_equal_approx(0.9, 0.0001)
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


func test_the_ruin_town_gets_only_the_grade_in_the_board_layer_and_no_light_look() -> void:
	var values := BoardgenMood.town_values()
	assert_array(values.keys()).contains_exactly_in_any_order(["tonemap_agx_contrast", "adjustment_enabled", "adjustment_contrast", "adjustment_saturation"])
	var env := Environment.new()
	var state := RenderState.new(env)
	var lc := _lighting()
	var sun: DirectionalLight3D = lc.get_meta("sun")
	lc.apply_preset("Warm Sunset")
	var main := _main_with(state, lc)
	var board := _board_on(main)
	BoardgenMood.apply(board, true, true)
	assert_float(env.tonemap_agx_contrast).is_equal_approx(BoardgenMood.TOWN_AGX_CONTRAST, 0.0001)
	assert_float(env.adjustment_contrast).is_equal_approx(BoardgenMood.TOWN_CONTRAST, 0.0001)
	assert_float(env.adjustment_saturation).is_equal_approx(BoardgenMood.TOWN_SATURATION, 0.0001)
	assert_float(sun.light_energy).override_failure_message("the town took the Tiefwerk light look").is_equal_approx(1.5, 0.0001)   # Warm Sunset's own sun
	BoardgenMood.apply(board, false, true)
	assert_float(env.adjustment_saturation).is_equal_approx(1.0, 0.0001)


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
