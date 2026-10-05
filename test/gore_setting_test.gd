extends GdUnitTestSuite
## The Gore setting (maintainer look verdict 04.10.: "more blood", with a switch so players and streamers can turn it
## down): 0 Off (dust instead of blood), 1 Normal (the default), 2 Extra. It is persisted like every graphics setting
## and a broken value in the file clamps into range.

const CFG := "user://graphics_settings.cfg"
var _before: Variant


func before_test() -> void:
	_before = GraphicsSettings.get("gore_level")


func after_test() -> void:
	if _before != null:
		GraphicsSettings.set("gore_level", _before)
	GraphicsSettings.save_settings()


func test_gore_is_normal_by_default() -> void:
	var fresh: Object = auto_free(load("res://scripts/graphics_settings.gd").new())
	assert_int(int(fresh.get("gore_level") if fresh.get("gore_level") != null else -1)).is_equal(1)


func test_gore_round_trips_through_save_and_load() -> void:
	GraphicsSettings.set("gore_level", 2)
	GraphicsSettings.save_settings()
	GraphicsSettings.set("gore_level", 0)
	GraphicsSettings.load_settings()
	assert_int(int(GraphicsSettings.get("gore_level") if GraphicsSettings.get("gore_level") != null else -1)).is_equal(2)


func test_a_broken_gore_value_clamps_into_range() -> void:
	GraphicsSettings.save_settings()
	var config := ConfigFile.new()
	config.load(CFG)
	config.set_value("graphics", "gore_level", 7)
	config.save(CFG)
	GraphicsSettings.load_settings()
	assert_int(int(GraphicsSettings.get("gore_level") if GraphicsSettings.get("gore_level") != null else -1)).is_equal(2)
