extends GdUnitTestSuite
## Terrain-projected base top: the base reconstructs the SAME plane UV the table's PlaneMesh carries,
## from world XZ, so the base reads as a seamless window onto the ground. These tests lock the two
## halves that must agree: the PlaneMesh UV convention and Table's world->UV parameter derivation.

const FEET_TO_METERS := 0.3048
const TableScript := preload("res://scripts/table.gd")


# ===== PlaneMesh UV convention (must match Table.BASE_UV_AXIS_SIGN) =====

func test_planemesh_uv_increases_with_plus_x_and_plus_z() -> void:
	# The base shader assumes u = x/size + 0.5 and v = z/size + 0.5 (both axes positive). If Godot
	# ever changes PlaneMesh winding, this test fails and BASE_UV_AXIS_SIGN must be updated.
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	var arrays := pm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for i in range(verts.size()):
		var expected_u := verts[i].x / 2.0 + 0.5
		var expected_v := verts[i].z / 2.0 + 0.5
		assert_float(uvs[i].x).is_equal_approx(expected_u, 0.0001)
		assert_float(uvs[i].y).is_equal_approx(expected_v, 0.0001)


func test_base_uv_axis_sign_matches_the_convention() -> void:
	# Positive on both axes — the sign the reconstruction uses.
	assert_vector(TableScript.BASE_UV_AXIS_SIGN).is_equal(Vector2(1.0, 1.0))


# ===== Table world->UV derivation (shader parameters) =====

func test_reference_table_shows_the_whole_battlemap() -> void:
	# 6x4 ft = the authored reference: uv_scale is 1 (no crop); inv_size = 1 / metres.
	var p := TableScript.plane_uv_params(Vector2(6, 4))
	assert_vector(p["uv_scale"]).is_equal_approx(Vector2(1.0, 1.0), Vector2(0.001, 0.001))
	assert_vector(p["inv_size_m"]).is_equal_approx(
		Vector2(1.0 / (6.0 * FEET_TO_METERS), 1.0 / (4.0 * FEET_TO_METERS)), Vector2(0.001, 0.001))


func test_smaller_table_centre_crops_the_battlemap() -> void:
	# A 4x4 ft table shows a centred crop: uv_scale < 1 on the shorter (x) axis.
	var p := TableScript.plane_uv_params(Vector2(4, 4))
	assert_vector(p["uv_scale"]).is_equal_approx(Vector2(4.0 / 6.0, 4.0 / 4.0), Vector2(0.001, 0.001))


# ===== The shared base-top material carries the derived parameters =====

func test_base_top_material_uses_the_projection_shader_with_derived_uv_scale() -> void:
	var table: TableScript = auto_free(TableScript.new())
	# Not added to the tree, so _ready()'s async biome load never runs — pure parameter check.
	table.table_size = Vector2(6, 4)
	var mat := table.get_base_top_material()
	assert_object(mat).is_not_null()
	assert_object(mat.shader).is_same(TableScript.BASE_TOP_SHADER)
	assert_vector(mat.get_shader_parameter("uv_scale")).is_equal_approx(Vector2(1.0, 1.0), Vector2(0.001, 0.001))
	# No biome/fallback texture bound yet -> the shader falls back to a neutral colour.
	assert_bool(mat.get_shader_parameter("has_texture")).is_false()


func test_base_top_material_is_a_single_shared_instance() -> void:
	var table: TableScript = auto_free(TableScript.new())
	assert_object(table.get_base_top_material()).is_same(table.get_base_top_material())


# ===== Brightness match (maintainer field feedback) =====

func test_base_top_vignette_defaults_off_and_is_pushed_from_table() -> void:
	# Shipped default is 0.0 — the black beveled rim alone grounds the base, and the terrain top must
	# read identical to the board (verified numerically to well under 1 % — tools/base_luminance_qa.gd).
	# The uniform is retained for later taste-tuning; a non-zero value reintroduces a thin rim band.
	assert_float(TableScript.BASE_TOP_VIGNETTE_STRENGTH).is_equal_approx(0.0, 0.0001)
	assert_float(TableScript.BASE_TOP_VIGNETTE_START).is_equal_approx(0.80, 0.0001)
	var table: TableScript = auto_free(TableScript.new())
	var mat := table.get_base_top_material()
	assert_float(mat.get_shader_parameter("vignette_strength")).is_equal_approx(0.0, 0.0001)
	assert_float(mat.get_shader_parameter("vignette_start")).is_equal_approx(TableScript.BASE_TOP_VIGNETTE_START, 0.0001)


func test_base_top_matches_the_ground_detail_relief() -> void:
	# Identical texture => identical brightness: the base carries the SAME detail-normal depth as
	# table_ground.gdshader, so it answers the sun the same way as the board it sits on (the actual
	# darkening the flat-lit base used to have was the missing normal map, not just the vignette).
	assert_float(TableScript.DETAIL_NORMAL_STRENGTH).is_equal_approx(0.35, 0.0001)
	var table: TableScript = auto_free(TableScript.new())
	var mat := table.get_base_top_material()
	assert_float(mat.get_shader_parameter("detail_normal_strength")).is_equal_approx(TableScript.DETAIL_NORMAL_STRENGTH, 0.0001)
