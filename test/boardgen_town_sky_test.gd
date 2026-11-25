extends GdUnitTestSuite
## The ruin town's night sky: stars, a moonlit cloud deck and a horizon haze on top
## of the blue-hour colours. A sky shader that reads the frame clock re-renders its
## radiance map every frame, so the source must never name it; the night layers stay
## out of the cube-map pass (the radiance lights nothing).

const TOWN_SKY := "res://shaders/ruintown_sky.gdshader"


## The source without its comments, so a remark cannot satisfy or break a check.
func _code(path: String) -> String:
	var lines := PackedStringArray()
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		lines.append(line.split("//")[0])
	return "\n".join(lines)


func test_the_town_sky_has_stars_clouds_and_haze_and_never_reads_the_clock() -> void:
	assert_object(load(TOWN_SKY)).is_not_null()
	var src := _code(TOWN_SKY)
	assert_str(src).contains("uniform float star_strength = 1.0;")
	assert_str(src).contains("uniform float cloud_strength = 0.85;")
	assert_str(src).contains("uniform float haze_strength = 0.35;")
	assert_str(src).contains("!AT_CUBEMAP_PASS")
	var msg := "the town sky reads TIME: its radiance re-renders every frame"
	assert_bool(src.contains("TIME")).override_failure_message(msg).is_false()


## Tiefwerk's vault (an undercity has no open sky): near black overhead, haze at the
## horizon, far work lights and dark structures. Inert until a board look names it.
func test_the_tiefwerk_vault_sky_loads_and_never_reads_the_clock() -> void:
	var path := "res://shaders/tiefwerk_sky.gdshader"
	assert_bool(ResourceLoader.exists(path)).override_failure_message("no vault sky").is_true()
	assert_object(load(path)).is_not_null()
	var src := _code(path)
	assert_str(src).contains("shader_type sky;")
	assert_str(src).contains("!AT_CUBEMAP_PASS")
	var msg := "the vault sky reads TIME: its radiance re-renders every frame"
	assert_bool(src.contains("TIME")).override_failure_message(msg).is_false()
	assert_bool(src.contains("LIGHT0_DIRECTION")).override_failure_message("a disc").is_false()
