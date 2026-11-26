extends GdUnitTestSuite
## Look review R11 (the green yard read flat and dead): in the old board shader the earth branch's
## relief follows the ground cover and its tufts (raised clumps, deeper than bare earth) and the
## garden-plot branch has a relief of its own; both carry a dry / green drift. Source contract.

const SHADER := "res://shaders/ruintown_board.gdshader"


## The source of one `k == n` branch of the board shader: from its `if` to the next branch.
func _branch(src: String, head: String) -> String:
	var at := src.find(head)
	assert_int(at).override_failure_message("no branch %s" % head).is_greater(-1)
	var end := src.find("} else if (k ==", at + head.length())
	return src.substr(at, end - at)


func test_the_earth_relief_follows_the_cover_and_its_tufts() -> void:
	var earth := _branch(FileAccess.get_file_as_string(SHADER), "} else if (k == 0) {")
	var rel_line := ""
	for line in earth.split("\n"):
		if line.strip_edges().begins_with("rel = clamp("):
			rel_line = line
	assert_str(rel_line).contains("cover").contains("tuft")
	assert_str(earth).contains("depth_in = mix(0.05, 0.08, cover)").contains("green_drift(xz")


func test_a_garden_plot_has_relief_and_a_drift() -> void:
	var plot := _branch(FileAccess.get_file_as_string(SHADER), "} else if (k == 11) {")
	assert_str(plot).contains("depth_in = 0.08").contains("rel = clamp(").contains(
		"green_drift(xz"
	)


## LOOK4 G1: the soil and the plot read the ONE green of ruintown_green.gdshaderinc (later plants read it too), folded by the half turn.
func test_soil_and_plot_read_the_one_folded_green() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	assert_bool(src.contains('#include "res://shaders/ruintown_green.gdshaderinc"')).is_true()
	for head in ["} else if (k == 0) {", "} else if (k == 11) {"]:
		var branch := _branch(src, head)
		assert_str(branch).contains("green_drift(xz").contains("green_break(xz")
		assert_bool(branch.contains("vnoise(xz * 0.2 +") or branch.contains("fbm(xz * 5.5 +")).override_failure_message("%s keeps an inline copy of the green" % head).is_false()
	var inc := FileAccess.get_file_as_string("res://shaders/ruintown_green.gdshaderinc")
	assert_str(inc).contains("vec3 green_tone(vec2 xz_in, float seed)").contains("float green_break(vec2 xz_in, float seed)").contains("xz_in.y >= 0.0 ? -xz_in : xz_in")
