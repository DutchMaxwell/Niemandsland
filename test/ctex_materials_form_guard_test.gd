extends GdUnitTestSuite
## J0 hotfix: a ctex block this loader cannot use — notably the contract-v1 `materials` form, which
## has no `textures.albedo` — must degrade to the LEGACY raw-GLB path, NEVER to "no model". Guards the
## single shared usability check (ModelLibrary._ctex_block_usable) and that get_ctex_entry() returns {}
## for such a block, so both decision points (prefetch + spawn) fall back to the legacy url.


func _engine_mm() -> String:
	var v := Engine.get_version_info()
	return "%d.%d" % [int(v.get("major", 0)), int(v.get("minor", 0))]


func test_block_usable_only_for_the_supported_textures_albedo_form() -> void:
	var mesh := {"sha256": "meshsha", "url": "meshsha.glb"}
	var albedo := {"sha256": "albsha", "url": "albsha.ctex"}
	# Supported form: mesh + textures.albedo.
	assert_bool(ModelLibrary._ctex_block_usable({"mesh": mesh, "textures": {"albedo": albedo}})).is_true()
	# Contract-v1 `materials` form (no textures) → unsupported → legacy fallback.
	assert_bool(ModelLibrary._ctex_block_usable({"mesh": mesh, "materials": {"body": {}}})).is_false()
	# Missing mesh, or empty block → unusable.
	assert_bool(ModelLibrary._ctex_block_usable({"textures": {"albedo": albedo}})).is_false()
	assert_bool(ModelLibrary._ctex_block_usable({})).is_false()


func test_get_ctex_entry_degrades_materials_only_block_to_legacy() -> void:
	var lib: ModelLibrary = auto_free(ModelLibrary.new())   # not in tree → _ready() (network) never fires
	var ver := _engine_mm()
	var manifest := {
		"base_url": "",
		"models": {
			"pilot/matonly": {
				"url": "legacy1.glb", "sha256": "legacy1", "size": 100,
				"ctex": {
					"godot_version": ver,
					"mesh": {"sha256": "m1", "url": "m1.glb"},
					"materials": {"body": {"albedo": {"sha256": "x"}}}   # v1 shape, no textures.albedo
				}
			},
			"pilot/texform": {
				"url": "legacy2.glb", "sha256": "legacy2", "size": 100,
				"ctex": {
					"godot_version": ver,
					"mesh": {"sha256": "m2", "url": "m2.glb"},
					"textures": {"albedo": {"sha256": "a2", "url": "a2.ctex"}}
				}
			}
		}
	}
	lib.apply_manifest_text(JSON.stringify(manifest))
	# materials-only block is unusable → {} → the caller resolves the (present) legacy url instead.
	assert_bool(lib.get_ctex_entry("pilot", "matonly").is_empty()).is_true()
	# the supported textures.albedo form stays usable.
	assert_bool(lib.get_ctex_entry("pilot", "texform").is_empty()).is_false()
