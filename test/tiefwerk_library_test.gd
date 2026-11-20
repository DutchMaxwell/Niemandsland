extends GdUnitTestSuite
## TiefwerkLibrary: manifest parsing, cache resolution and the decal-atlas slicing (no network involved).

const SHA_PREFIX := "tflib_test_"


func _lib() -> TiefwerkLibrary:
	var lib := TiefwerkLibrary.new()
	add_child(lib)
	return auto_free(lib)


func _entry(tag: String, ext: String) -> Dictionary:
	return {"url": "%s%s.%s" % [SHA_PREFIX, tag, ext], "sha256": SHA_PREFIX + tag, "size": 1}


func _manifest(cell: Dictionary, baked_for := "") -> String:
	var v: Dictionary = Engine.get_version_info()
	return JSON.stringify({
		"version": 1, "godot_version": baked_for if not baked_for.is_empty() else "%d.%d" % [int(v["major"]), int(v["minor"])], "base_url": "https://cdn/t",
		"sets": {"steel": {"tile_in": 3.0, "albedo": _entry("sa", "ctex"), "normal": _entry("sn", "ctex"), "orm": _entry("so", "ctex")}},
		"decals": {"atlas_px": 64, "texels_per_inch": 32, "albedo": _entry("da", "webp"), "normal": _entry("dn", "webp"),
			"orm": _entry("do", "webp"), "cells": {"red": cell}}})


func _put_atlas(tag: String, img: Image) -> String:
	DirAccess.make_dir_recursive_absolute(TiefwerkLibrary.CACHE_DIR)
	var path := "%s/%s%s.webp" % [TiefwerkLibrary.CACHE_DIR, SHA_PREFIX, tag]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(img.save_webp_to_buffer(false))
	f.close()
	return path


func test_manifest_parse_names_and_sizes() -> void:
	var lib := _lib()
	lib.apply_manifest_text(_manifest({"x": 8, "y": 8, "w": 16, "h": 32}))
	assert_bool(lib.has_set("steel")).is_true()
	assert_bool(lib.has_set("nope")).is_false()
	assert_float(lib.tile_in("steel")).is_equal(3.0)
	assert_array(lib.decal_cell_names()).contains(["red"])
	assert_vector(lib.cell_size_in("red")).is_equal(Vector2(0.5, 1.0))   # 16 x 32 texels at 32 per inch


func test_an_engine_version_mismatch_hides_the_sets() -> void:
	var lib := _lib()
	lib.apply_manifest_text(_manifest({}, "0.1"))
	assert_bool(lib.has_set("steel")).is_false()


func test_nothing_is_cached_before_a_download() -> void:
	var lib := _lib()
	lib.apply_manifest_text(_manifest({"x": 0, "y": 0, "w": 8, "h": 8}))
	assert_bool(lib.sets_cached()).is_false()
	assert_bool(lib.decals_cached()).is_false()
	assert_object(lib.set_texture("steel", "albedo")).is_null()
	assert_dict(lib.decal_textures("red")).is_empty()


func test_decal_textures_are_the_cell_rectangle_of_the_atlas() -> void:
	var lib := _lib()
	lib.apply_manifest_text(_manifest({"x": 8, "y": 16, "w": 16, "h": 32}))
	var atlas := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 1, 1))
	atlas.fill_rect(Rect2i(8, 16, 16, 32), Color(1, 0, 0, 1))   # the cell is red, everything round it blue
	var paths: Array[String] = []
	for tag in ["da", "dn", "do"]:
		paths.append(_put_atlas(tag, atlas))
	var tex: Dictionary = lib.decal_textures("red")
	for p in paths:
		DirAccess.remove_absolute(p)
	assert_array(tex.keys()).contains_exactly(["albedo", "normal", "orm"])
	var img: Image = (tex["albedo"] as Texture2D).get_image()
	assert_vector(Vector2(img.get_size())).is_equal(Vector2(16, 32))
	assert_vector(Vector2(img.get_pixel(0, 0).r, img.get_pixel(15, 31).r)).is_equal(Vector2(1, 1))   # inside the cell: red, no blue edge
	assert_float(img.get_pixel(0, 0).b).is_equal(0.0)
	assert_dict(lib.decal_textures("unknown")).is_empty()
