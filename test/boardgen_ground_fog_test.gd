extends GdUnitTestSuite
## The ruin town's ground fog (shaders/ruintown_groundfog.gdshader): one plane that
## integrates a height fog along every view ray, with lamp pools glowing in it. A pool
## is a compact term (no long tails: ten lamps must not add up to a brown carpet),
## looked up where the ray ends (a pool looked up mid-ray stays cold).

const FOG := "res://shaders/ruintown_groundfog.gdshader"


## The source without its comments, so a remark cannot satisfy or break a check.
func _code(path: String) -> String:
	var lines := PackedStringArray()
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		lines.append(line.split("//")[0])
	return "\n".join(lines)


func test_the_fog_shader_has_compact_lamp_pools_where_the_ray_ends() -> void:
	(
		assert_bool(ResourceLoader.exists(FOG))
		. override_failure_message("no ground fog shader")
		. is_true()
	)
	assert_object(load(FOG)).is_not_null()
	var src := _code(FOG)
	assert_str(src).contains("uniform vec3 lamps[12];")
	assert_str(src).contains("float k = 1.0 - clamp(dl / lamp_r, 0.0, 1.0);")
	assert_str(src).contains("glow += k * k;")
	assert_str(src).contains("length(b.xz - lamps[i].xz)")
	var msg := "a lamp term with long tails paints the street brown"
	assert_bool(src.contains("exp(-length(")).override_failure_message(msg).is_false()
	assert_bool(src.contains("TIME")).is_false()
