extends GdUnitTestSuite
## Handover I: the contract-v1 MULTI-material ctex form (`materials: [{surface, albedo, normal?}]`) is
## usable and its per-surface blobs enumerate correctly, while the single `textures` form and unknown
## shapes are unchanged (I1). Plus the loadout→variant slug derivation and that `#` survives key
## normalization (I2 / contract v1).


func test_array_materials_form_is_usable() -> void:
	var mesh := {"sha256": "m", "url": "m.glb"}
	var block := {"mesh": mesh, "materials": [
		{"surface": 0, "albedo": {"sha256": "a0", "url": "a0.ctex"}},
		{"surface": 1, "albedo": {"sha256": "a1", "url": "a1.ctex"}, "normal": {"sha256": "n1", "url": "n1.ctex"}},
	]}
	assert_bool(ModelLibrary._ctex_block_usable(block)).is_true()


func test_single_textures_form_still_usable() -> void:
	var block := {"mesh": {"sha256": "m"}, "textures": {"albedo": {"sha256": "a"}}}
	assert_bool(ModelLibrary._ctex_block_usable(block)).is_true()


func test_materials_missing_albedo_or_mesh_is_not_usable() -> void:
	assert_bool(ModelLibrary._ctex_block_usable({"mesh": {"sha256": "m"}, "materials": [{"surface": 0}]})).is_false()
	assert_bool(ModelLibrary._ctex_block_usable({"materials": [{"surface": 0, "albedo": {"sha256": "a"}}]})).is_false()


func test_dict_materials_shape_still_degrades_to_legacy() -> void:
	# An unknown/dict `materials` shape must NOT be treated as usable (J0 forward-compat preserved).
	assert_bool(ModelLibrary._ctex_block_usable({"mesh": {"sha256": "m"}, "materials": {"body": {}}})).is_false()


func test_texture_blobs_enumerate_both_forms() -> void:
	var single := {"textures": {"albedo": {"sha256": "a"}, "normal": {"sha256": "n"}}}
	assert_int(ModelLibrary._ctex_texture_blobs(single).size()).is_equal(2)
	var multi := {"materials": [
		{"surface": 0, "albedo": {"sha256": "a0"}},
		{"surface": 1, "albedo": {"sha256": "a1"}, "normal": {"sha256": "n1"}},
	]}
	assert_int(ModelLibrary._ctex_texture_blobs(multi).size()).is_equal(3)   # 2 albedo + 1 normal


func test_variant_slug_sorts_dedups_and_maps_labels() -> void:
	var lib: ModelLibrary = auto_free(ModelLibrary.new())   # not added to tree → _ready() never fires
	lib._label_slug = {"shield": "shield", "spear": "spear", "banner": "banner", "musician": "horn"}
	assert_str(lib.variant_slug(["Spear", "Shield"])).is_equal("shield+spear")    # sorted, case-folded
	assert_str(lib.variant_slug(["Banner", "Musician"])).is_equal("banner+horn")  # label→slug mapping
	assert_str(lib.variant_slug(["Shield", "Shield"])).is_equal("shield")          # de-duplicated
	assert_str(lib.variant_slug(["Unmapped"])).is_equal("")                        # no match → base model


func test_hash_survives_key_normalization() -> void:
	# Variant keys `<base>#<slug>` must survive make_key / _normalize_unit intact (contract v1).
	assert_str(ModelLibrary.make_key("mummified_undead", "Skeleton Warriors#banner+shield")) \
		.is_equal("mummified_undead/skeleton warriors#banner+shield")
