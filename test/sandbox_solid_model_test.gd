extends GdUnitTestSuite
## A shelf solid swaps its bundled look for the detailed GLB only once that model is cached and parses (3.5, delivery
## D5: bundled first, R2 after the maintainer's upload word). A model missing from the manifest or a corrupt cached file
## keeps the bundled look, and the rule box (the one collider) is the same either way.

const BAD_SHA := "0000fantasytable0test0corrupt0glb"


func _solid(om: ObjectManager) -> SandboxSolidProp:
	return om.spawn_sandbox_terrain("blocker_6x3", ObjectManager.SandboxPropKind.BLOCKER, Vector3.ZERO, false, 7301)


func _look_visible(solid: SandboxSolidProp) -> bool:
	return solid.find_children("*", "MeshInstance3D", false, false).all(func(m: Node) -> bool: return m.visible)


func _collider_size(solid: SandboxSolidProp) -> Vector3:
	var cols := solid.find_children("*", "CollisionShape3D", false, false)
	return (cols[0].shape as BoxShape3D).size if cols.size() == 1 else Vector3.ZERO


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HazardsLibrary.CACHE_DIR.path_join(BAD_SHA + ".glb")))


func test_a_model_replaces_the_look_but_not_the_rule_box() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	var solid := _solid(om)
	var box := _collider_size(solid)
	var model := Node3D.new()
	solid.use_model(model)
	assert_bool(model.get_parent() == solid).is_true()
	assert_bool(solid.find_children("*", "MeshInstance3D", false, false).any(func(m: Node) -> bool: return m.visible)).is_false()
	assert_vector(_collider_size(solid)).is_equal(box)


func test_a_model_missing_from_the_manifest_keeps_the_look() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	var solid := _solid(om)
	var before := solid.get_child_count()   # the piece's own children (collider, look, shadow, dressing) as built
	await om.apply_solid_model(solid, "no_such_solid_model")
	assert_bool(_look_visible(solid)).is_true()
	assert_int(solid.get_child_count()).is_equal(before)   # no model was added


func test_a_corrupt_cached_model_keeps_the_look() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	var lib := om.solid_models_library()
	lib.apply_manifest_text(JSON.stringify({"models": {"bad_solid": {"url": "bad.glb", "sha256": BAD_SHA}}}))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(HazardsLibrary.CACHE_DIR))
	var f := FileAccess.open(HazardsLibrary.CACHE_DIR.path_join(BAD_SHA + ".glb"), FileAccess.WRITE)
	f.store_string("not a glb")
	f.close()
	var solid := _solid(om)
	await om.apply_solid_model(solid, "bad_solid")
	assert_bool(_look_visible(solid)).is_true()
	assert_vector(_collider_size(solid)).is_equal(Vector3(6, 2.5, 3) * 0.0254)
