extends GdUnitTestSuite
## TerrainOverlay._create_lava_pool: the glowing lava pool that is the DANGEROUS-terrain
## prop in the volcanic biome (replaces mines). Dark crust rim + emissive molten core, an
## optional capped OmniLight for the emanating glow. Seeded per object (MP/save safe).

const TerrainOverlayScript = preload("res://scripts/terrain_overlay.gd")


func _overlay():
	# .new() does not run _ready (no tree); _create_lava_pool only needs the method + consts.
	return auto_free(TerrainOverlayScript.new())


func _obj(cx: int, cy: int) -> Dictionary:
	return {"cell": Vector2i(cx, cy), "offset": Vector2(0.5, 0.5)}


func _emissive_core(node: Node3D) -> StandardMaterial3D:
	for c in node.get_children():
		if c is MeshInstance3D:
			var m := (c as MeshInstance3D).material_override as StandardMaterial3D
			if m and m.emission_enabled:
				return m
	return null


func _omni(node: Node3D) -> OmniLight3D:
	for c in node.get_children():
		if c is OmniLight3D:
			return c as OmniLight3D
	return null


func test_pool_without_light_has_no_omnilight() -> void:
	var node: Node3D = auto_free(_overlay()._create_lava_pool(_obj(2, 3), false))
	assert_object(node).is_not_null()
	assert_object(_omni(node)).is_null()
	# Still has the crust + molten-core meshes.
	assert_int(node.get_child_count()).is_equal(2)


func test_pool_with_light_adds_a_capped_omnilight() -> void:
	var node: Node3D = auto_free(_overlay()._create_lava_pool(_obj(2, 3), true))
	var light := _omni(node)
	assert_object(light).is_not_null()
	assert_bool(light.shadow_enabled).is_false()  # cheap: no shadow casting


func test_core_is_emissive_molten() -> void:
	var mat := _emissive_core(auto_free(_overlay()._create_lava_pool(_obj(1, 1), false)))
	assert_object(mat).is_not_null()
	assert_object(mat.emission).is_equal(TerrainOverlayScript.LAVA_EMISSION_COLOR)


func test_is_deterministic_per_object() -> void:
	var ov = _overlay()
	var a: Node3D = auto_free(ov._create_lava_pool(_obj(4, 7), false))
	var b: Node3D = auto_free(ov._create_lava_pool(_obj(4, 7), false))
	assert_float(a.rotation.y).is_equal_approx(b.rotation.y, 0.0001)
