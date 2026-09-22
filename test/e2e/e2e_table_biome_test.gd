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
