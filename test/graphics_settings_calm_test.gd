extends GdUnitTestSuite
## Calm mode (GitHub #1634): one accessibility switch that turns down combat
## effects, idle motion, tilt-shift and motion in one click. DEFAULT OFF. It is a
## preset over the existing individual switches: turning it ON snapshots them and
## forces the calm values, turning it OFF restores exactly what the player had
## chosen. The mode and the snapshot persist, so a reload while ON keeps both the
## calm look and the player's real preferences.

const FIELDS := ["show_combat_effects", "idle_motion", "reduce_motion", "tilt_shift"]
var _before := {}


func before_test() -> void:
	for f: String in FIELDS:
		_before[f] = GraphicsSettings.get(f)
	_before["calm_mode"] = GraphicsSettings.get("calm_mode")


func after_test() -> void:
	GraphicsSettings.set_calm_mode(false)
	for f: String in FIELDS:
		if _before[f] != null:
			GraphicsSettings.set(f, _before[f])
	GraphicsSettings.save_settings()


func _snapshot() -> Dictionary:
	var d := {}
	for f: String in FIELDS:
		d[f] = GraphicsSettings.get(f)
	return d


func _seed_choices() -> void:
	GraphicsSettings.set("show_combat_effects", true)
	GraphicsSettings.set("idle_motion", true)
	GraphicsSettings.set("reduce_motion", false)
	GraphicsSettings.set("tilt_shift", true)


func test_calm_is_off_by_default() -> void:
	var fresh: Object = auto_free(load("res://scripts/graphics_settings.gd").new())
	assert_bool(bool(fresh.get("calm_mode") if fresh.get("calm_mode") != null else false)) \
		.override_failure_message("calm mode must ship OFF").is_false()


func test_calm_on_forces_the_quiet_values_and_off_restores_the_players_choices() -> void:
	_seed_choices()
	GraphicsSettings.set_calm_mode(true)
	var calm := _snapshot()
	assert_bool(calm["show_combat_effects"]).is_false()
	assert_bool(calm["idle_motion"]).is_false()
	assert_bool(calm["reduce_motion"]).is_true()
	assert_bool(calm["tilt_shift"]).is_false()

	GraphicsSettings.set_calm_mode(false)
	var restored := _snapshot()
	assert_bool(restored["show_combat_effects"]).is_true()
	assert_bool(restored["idle_motion"]).is_true()
	assert_bool(restored["reduce_motion"]).is_false()
	assert_bool(restored["tilt_shift"]).is_true()


func test_calm_survives_a_reload_and_still_restores_the_choices() -> void:
	_seed_choices()
	GraphicsSettings.set_calm_mode(true)
	GraphicsSettings.save_settings()

	GraphicsSettings.set("show_combat_effects", true)
	GraphicsSettings.set("idle_motion", true)
	GraphicsSettings.set("reduce_motion", false)
	GraphicsSettings.set("tilt_shift", true)
	GraphicsSettings.load_settings()
	assert_bool(GraphicsSettings.get("calm_mode")).override_failure_message("mode not persisted").is_true()
	var calm := _snapshot()
	assert_bool(calm["show_combat_effects"]).is_false()
	assert_bool(calm["reduce_motion"]).is_true()

	GraphicsSettings.set_calm_mode(false)
	var restored := _snapshot()
	assert_bool(restored["show_combat_effects"]).override_failure_message("choices lost across reload").is_true()
	assert_bool(restored["idle_motion"]).is_true()
	assert_bool(restored["reduce_motion"]).is_false()
	assert_bool(restored["tilt_shift"]).is_true()


func test_turning_calm_on_twice_is_a_no_op() -> void:
	_seed_choices()
	GraphicsSettings.set_calm_mode(true)
	GraphicsSettings.set("show_combat_effects", false)
	GraphicsSettings.set_calm_mode(true)  # second call must not re-snapshot the calm values
	GraphicsSettings.set_calm_mode(false)
	assert_bool(_snapshot()["show_combat_effects"]).is_true()
