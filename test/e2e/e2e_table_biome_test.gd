extends GdUnitTestSuite
## E2E — TableBiomePresenter on the REAL scenes/main.tscn (display only).
##
## The presenter dresses the game table with the accepted reference biome (table tier). These suites pin what
## must hold on the live table: the biome light profile stays on top of the atmosphere controller (maintainer
## decision D1, including the restore_saved() the intro runs), the dressing adds no collider and changes no
## line-of-sight geometry, and teardown gives the table back. Headless CI skips the dressing by default;
## allow_headless opts these suites in.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Biomes := preload("res://scripts/visual/reference_biomes.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(10)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Dress the table with `table_biome` (the table's own id). The biome is set on the property, not through
## table.set_biome, so no battlemap download starts in CI.
func _dress(table_biome: String) -> TableBiomePresenter:
	var presenter: TableBiomePresenter = _main._table_biome_presenter
	presenter.allow_headless = true
	_main.table.biome = table_biome
	await presenter.rebuild()
	await _runner.simulate_frames(2)
	return presenter


func _sun() -> DirectionalLight3D:
	return _main.get_node("DirectionalLight3D") as DirectionalLight3D


## Paint ruins (zone + wall models), a forest and a container onto the live overlay, as the map layout
## editor does (the same calls los_volumes_test uses).
func _paint_terrain() -> void:
	var overlay: Node3D = _main.terrain_overlay
	var table := Vector2(6, 4)
	var cells := {}
	for x in range(10, 14):
		cells[Vector2i(x, 12)] = 1          # TerrainType.RUINS
	for x in range(18, 21):
		for y in range(16, 19):
			cells[Vector2i(x, y)] = 2       # TerrainType.FOREST
	overlay.update_overlay(cells, table, 0.0)
	var walls: Array = []
	for x in range(10, 14):
		walls.append({"edge_cell": Vector2i(x, 12), "edge_side": 0, "wall_key": "w",
			"length_inches": overlay.GRID_SIZE_INCHES, "sub_position": 0})
	overlay.update_wall_models(walls, table, 0.0)
	overlay.update_placed_objects([{"object_type": "container", "cell": Vector2i(15, 15),
		"offset": Vector2(0.5, 0.5), "angle_deg": 0.0}], table, 0.0)
	await _runner.simulate_frames(3)


func _colliders() -> int:
	return _main.find_children("*", "CollisionObject3D", true, false).size()


func test_dressing_adds_no_collider_and_keeps_line_of_sight_geometry(timeout := 180000) -> void:
	await _paint_terrain()
	var volumes: Array = _main.terrain_overlay.los_volumes().duplicate(true)
	var walls: Array = _main.terrain_overlay.get_wall_segments_world().duplicate(true)
	var colliders := _colliders()
	assert_int(walls.size()).override_failure_message("the painted ruins produced no wall segment — the LOS check below would be empty").is_greater(0)
	for biome in ["temperate_grassland", "urban_ruins"]:
		var presenter := await _dress(biome)
		assert_bool(presenter.is_dressed()).is_true()
		assert_int(presenter.current_presentation().find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)
		assert_int(_colliders()).override_failure_message("dressing %s changed the collider count" % biome).is_equal(colliders)
		assert_bool(_main.terrain_overlay.los_volumes() == volumes) \
			.override_failure_message("dressing %s changed the LOS volumes" % biome).is_true()
		assert_bool(_main.terrain_overlay.get_wall_segments_world() == walls) \
			.override_failure_message("dressing %s changed the wall segments" % biome).is_true()


func test_teardown_gives_the_table_back(timeout := 120000) -> void:
	var table: Node3D = _main.table
	var surface := table.get_node("TableMesh") as MeshInstance3D
	var mesh_before := surface.mesh
	var shadow_before := surface.cast_shadow
	var base_shader_before: Shader = table.get_base_top_material().shader
	var env: Environment = _main.get_node("WorldEnvironment").environment
	var ssr_before := env.ssr_enabled
	var ambient_source_before := env.ambient_light_source
	var mist: Node3D = _main.atmospheric_clouds
	var mist_before := mist.visible
	var presenter := await _dress("volcanic_ash")
	assert_bool(presenter.is_dressed()).is_true()
	# D4: the game's ground mist is off while a biome is dressed (the accepted look had none).
	assert_bool(mist.visible).override_failure_message("the ground mist stayed on over a dressed table").is_false()
	assert_object((surface.material_override as ShaderMaterial).shader).is_same(preload("res://shaders/visual/reference_ground_table.gdshader"))
	assert_bool(table.get_node("GrassField").visible).is_false()
	presenter.enabled = false
	await presenter.rebuild()
	assert_bool(presenter.is_dressed()).is_false()
	assert_object(surface.mesh).is_same(mesh_before)
	assert_int(surface.cast_shadow).is_equal(shadow_before)
	assert_bool(surface.material_override is ShaderMaterial and (surface.material_override as ShaderMaterial).shader == preload("res://shaders/visual/reference_ground_table.gdshader")).is_false()
	assert_object(table.get_base_top_material().shader).is_same(base_shader_before)
	assert_bool(table.get_node("GrassField").visible).is_true()
	assert_bool(env.ssr_enabled == ssr_before).is_true()
	assert_int(env.ambient_light_source).is_equal(ambient_source_before)
	assert_bool(mist.visible).is_equal(mist_before)
	assert_int(presenter.get_child_count()).is_equal(0)


func test_low_presets_keep_the_battlemap_table(timeout := 120000) -> void:
	var presenter := await _dress("arid_desert")
	assert_bool(presenter.is_dressed()).is_true()
	var graphics := get_tree().root.get_node("GraphicsSettings")
	var previous: int = graphics.current_preset
	graphics.current_preset = 1   # LOW, set directly: apply_preset() would persist the player's settings
	presenter._on_graphics_settings_applied("Low")
	await get_tree().create_timer(TableBiomePresenter.REBUILD_DELAY_S + 0.3).timeout
	await _runner.simulate_frames(2)
	var dressed_on_low := presenter.is_dressed()
	graphics.current_preset = previous
	assert_bool(dressed_on_low).override_failure_message("the table stayed dressed on the Low preset").is_false()


func test_layout_events_during_play_do_not_rebuild(timeout := 120000) -> void:
	var presenter := await _dress("frozen_tundra")
	var builds := [0]
	presenter.presentation_built.connect(func(_b: String) -> void: builds[0] += 1)
	var manager = _main.opr_army_manager
	manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	presenter.request_rebuild("layout")
	await get_tree().create_timer(TableBiomePresenter.REBUILD_DELAY_S + 0.3).timeout
	assert_int(builds[0]).override_failure_message("a layout event during play rebuilt the dressing (a mid-game freeze)").is_equal(0)
	# The start of play is the one layout-final rebuild.
	manager.game_phase = OPRArmyManager.GamePhase.DEPLOYMENT
	presenter._on_game_phase_changed(OPRArmyManager.GamePhase.PLAYING)
	await get_tree().create_timer(TableBiomePresenter.REBUILD_DELAY_S + 0.3).timeout
	await _runner.simulate_frames(2)
	assert_int(builds[0]).is_equal(1)


func test_biome_light_profile_stays_on_top_of_the_atmosphere(timeout := 120000) -> void:
	var presenter := await _dress("arid_desert")
	assert_bool(presenter.is_dressed()).is_true()
	var profile: Dictionary = Biomes.get_profile("arid_desert")
	var atmosphere = _main.atmosphere_controller

	# The intro ends with restore_saved() — an INSTANT re-apply of the saved mood (default Sunset). The profile's
	# own sunset values must win (D1), not the game's "Warm Sunset" lighting.
	atmosphere.apply_atmosphere("Sunset", true)
	await _runner.simulate_frames(2)
	assert_float(_sun().light_energy).is_equal_approx(float(profile["sun_energy"]), 0.0001)
	assert_bool(_sun().light_color.is_equal_approx(profile["sun_color_sunset"])) \
		.override_failure_message("after the atmosphere re-applied Sunset the sun is %s, not the profile's sunset %s" % [_sun().light_color, profile["sun_color_sunset"]]) \
		.is_true()

	# Night uses the profile's sunset values too (D1).
	atmosphere.apply_atmosphere("Night", true)
	await _runner.simulate_frames(2)
	assert_bool(_sun().light_color.is_equal_approx(profile["sun_color_sunset"])).is_true()

	# Overcast is not a profile mood: the game's own lighting shows.
	atmosphere.apply_atmosphere("Overcast", true)
	await _runner.simulate_frames(2)
	assert_bool(_sun().light_color.is_equal_approx(profile["sun_color_day"])).is_false()
	assert_bool(_sun().light_color.is_equal_approx(profile["sun_color_sunset"])).is_false()

	# Day: the profile is the Day base.
	atmosphere.apply_atmosphere("Day", true)
	await _runner.simulate_frames(2)
	assert_bool(_sun().light_color.is_equal_approx(profile["sun_color_day"])).is_true()
	assert_float(_sun().light_energy).is_equal_approx(float(profile["sun_energy"]), 0.0001)
