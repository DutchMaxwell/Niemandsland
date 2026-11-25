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


func _fog(layout: Dictionary) -> BoardgenGroundFog:
	var fog: BoardgenGroundFog = auto_free(BoardgenGroundFog.new())
	fog.build(layout)
	return fog


func test_the_fog_plane_covers_the_board_and_casts_nothing() -> void:
	var fog := _fog({"nx": 12, "nz": 8, "cell_in": 3.0})
	var plane := fog.mesh as PlaneMesh
	assert_object(plane).is_not_null()
	var board_m := Vector2(12, 8) * 3.0 * BoardgenGroundFog.INCHES_TO_METERS
	assert_vector(plane.size).is_equal_approx(board_m, Vector2(0.0001, 0.0001))
	assert_int(fog.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_int(fog.find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)
	assert_float(fog.position.y).is_greater(0.0)  # at the fog's top, above the street


func test_the_noise_is_an_image_texture_never_a_noise_texture() -> void:
	var noise := _fog({"nx": 4, "nz": 4, "cell_in": 3.0}).noise()
	var msg := "a NoiseTexture2D fills itself late: its first frames are the pink-table race"
	assert_bool(noise is ImageTexture).override_failure_message(msg).is_true()


func test_fourteen_lamps_are_capped_at_twelve() -> void:
	var fog := _fog({"nx": 4, "nz": 4, "cell_in": 3.0})
	var points := PackedVector3Array()
	for i in 14:
		points.append(Vector3(i, 0, 0))
	fog.set_lamps(points)
	assert_int(fog.lamp_count()).is_equal(BoardgenGroundFog.MAX_LAMPS)
	assert_int(BoardgenGroundFog.MAX_LAMPS).is_equal(12)
	fog.set_lamps(PackedVector3Array([Vector3.ZERO]))
	assert_int(fog.lamp_count()).is_equal(1)
