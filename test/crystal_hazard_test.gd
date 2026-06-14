extends GdUnitTestSuite
## TerrainOverlay._create_crystal_hazard: the glowing ember-crystal cluster that replaces
## the mine disc as the DANGEROUS-terrain prop in the dwarven volcanic biome. Procedural,
## seeded from the object's identity (deterministic -> multiplayer + save safe). Decorative.

const TerrainOverlayScript = preload("res://scripts/terrain_overlay.gd")


func _overlay():
	# .new() does not run _ready (no tree), so no library/autoload setup is triggered;
	# _create_crystal_hazard only needs the instance method + constants.
	return auto_free(TerrainOverlayScript.new())


func _obj(cx: int, cy: int) -> Dictionary:
	return {"cell": Vector2i(cx, cy), "offset": Vector2(0.5, 0.5)}


func test_builds_a_shard_cluster() -> void:
	var node: Node3D = auto_free(_overlay()._create_crystal_hazard(_obj(2, 3)))
	assert_object(node).is_not_null()
	assert_int(node.get_child_count()).is_between(
		TerrainOverlayScript.CRYSTAL_SHARDS_MIN, TerrainOverlayScript.CRYSTAL_SHARDS_MAX)


func test_is_deterministic_per_object() -> void:
	var ov = _overlay()
	var a: Node3D = auto_free(ov._create_crystal_hazard(_obj(2, 3)))
	var b: Node3D = auto_free(ov._create_crystal_hazard(_obj(2, 3)))
	assert_int(a.get_child_count()).is_equal(b.get_child_count())
	# Same seed -> identical first shard transform.
	assert_vector((a.get_child(0) as Node3D).position).is_equal((b.get_child(0) as Node3D).position)


func test_shards_are_emissive_ember() -> void:
	var node: Node3D = auto_free(_overlay()._create_crystal_hazard(_obj(1, 1)))
	var mat := (node.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
	assert_bool(mat.emission_enabled).is_true()
	assert_object(mat.emission).is_equal(TerrainOverlayScript.CRYSTAL_EMISSION_COLOR)


func test_shards_sit_on_the_table() -> void:
	# Each shard's centre is at height/2, so its base rests at ~y=0 (not floating/buried).
	var node: Node3D = auto_free(_overlay()._create_crystal_hazard(_obj(5, 5)))
	for c in node.get_children():
		var mi := c as MeshInstance3D
		var mesh := mi.mesh as CylinderMesh
		assert_float(mi.position.y).is_equal_approx(mesh.height / 2.0, 0.0001)
