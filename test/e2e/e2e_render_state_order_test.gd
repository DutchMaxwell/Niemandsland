extends GdUnitTestSuite
## E2E — the game table's render state depends on the final choices (quality preset, biome, mood), never on the order
## they were made in. Several scripts wrote the same Environment and viewport properties (graphics council 03.10.:
## preset, biome reference, mood, intro), so the call order decided the look. Boots the REAL scenes/main.tscn per test.
## (The render-scale half of the same defect class lives in e2e_table_biome_test: the table tier owns no viewport.)

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const TreePass := preload("res://scripts/visual/table_tree_pass.gd")
const Materials := preload("res://scripts/visual/reference_materials.gd")
const KEYS: Array[String] = ["ssao_enabled", "ssao_radius", "ssao_intensity", "ssil_enabled", "sdfgi_enabled",
	"ssr_enabled", "ssr_fade_in", "glow_enabled", "glow_intensity", "glow_bloom", "volumetric_fog_enabled"]
const SUN_KEYS: Array[String] = ["shadow_bias", "shadow_normal_bias", "directional_shadow_max_distance",
	"directional_shadow_pancake_size", "light_volumetric_fog_energy"]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _preset_before: int


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_preset_before = _graphics().current_preset


func after_test() -> void:
	_graphics().apply_preset(_preset_before)   # apply_preset persists: hand the player's choice back
	TreePass.clear_sources()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	Materials.set_tier(false)
	_main = null
	_runner = null


func _graphics() -> Node:
	return get_tree().root.get_node("GraphicsSettings")


## Boot on `preset` the way play does: the preset is applied at the startup menu, before Main exists.
func _boot(preset: int) -> void:
	_graphics().apply_preset(preset)
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(10)
	_main._table_biome_presenter.allow_headless = true
	await _main._table_biome_presenter.rebuild()
	await _runner.simulate_frames(2)


func _preset(preset: int) -> void:
	_graphics().apply_preset(preset)
	await get_tree().create_timer(TableBiomePresenter.REBUILD_DELAY_S + 0.3).timeout
	await _runner.simulate_frames(3)


func _mood(mood: String) -> void:
	_main.atmosphere_controller.apply_atmosphere(mood, true)
	await _runner.simulate_frames(2)


func _state() -> Dictionary:
	var env: Environment = _main.get_node("WorldEnvironment").environment
	var state := {"dressed": _main._table_biome_presenter.is_dressed()}
	for key in KEYS:
		state[key] = snappedf(env.get(key), 0.001) if env.get(key) is float else env.get(key)
	var sun: DirectionalLight3D = _main.get_node("DirectionalLight3D")
	for key in SUN_KEYS:
		state["sun_" + key] = snappedf(sun.get(key), 0.001)
	return state


func test_low_at_start_is_low_after_a_round_trip(timeout := 120000) -> void:
	await _boot(1)
	var at_start := _state()
	await _preset(2)
	await _preset(1)
	assert_dict(_state()).is_equal(at_start)
	assert_bool(at_start["ssao_enabled"] or at_start["glow_enabled"]) \
		.override_failure_message("Low started with SSAO or glow on: %s" % at_start).is_false()


func test_overcast_and_ultra_in_either_order_give_one_state(timeout := 120000) -> void:
	await _boot(2)
	await _mood("Overcast")
	await _preset(4)
	var mood_first := _state()
	await _preset(2)
	await _mood("Sunset")
	await _preset(4)
	await _mood("Overcast")
	assert_dict(_state()).is_equal(mood_first)


## A table dressed while Overcast shows (probe 03.10.: High/Ultra) must look like one dressed in Sunset before the
## switch to Overcast — the way every game gets there, since each game starts in Sunset.
func test_dressing_in_overcast_gives_the_state_of_dressing_before_overcast(timeout := 120000) -> void:
	await _boot(3)
	await _mood("Overcast")
	var dressed_before := _state()
	var presenter: TableBiomePresenter = _main._table_biome_presenter
	presenter.enabled = false
	await presenter.rebuild()
	presenter.enabled = true
	await presenter.rebuild()
	await _runner.simulate_frames(2)
	assert_dict(_state()).is_equal(dressed_before)
