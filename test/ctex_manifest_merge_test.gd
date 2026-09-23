extends GdUnitTestSuite
## Guards the ctex-augmented bundled manifest (tools/merge_ctex_manifest.py output): every unit keeps
## complete LEGACY fields (url/sha256/size — the only thing a client without CtexLoader reads), carries
## a COMPLETE ctex block, and its legacy url is NEVER the stripped ctex mesh (an old client resolving
## the legacy url must get a full-texture GLB, not the texture-less ctex mesh). See Handover B / T2.

const MANIFEST := "res://assets/model_manifest.json"


func _models() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	assert_bool(f != null).is_true()
	var parsed = JSON.parse_string(f.get_as_text())
	assert_bool(parsed is Dictionary).is_true()
	return (parsed as Dictionary).get("models", {})


func test_catalogue_is_populated() -> void:
	# The catalogue is ~1014 units; a large regression (empty/half-written merge) must fail loudly.
	assert_int(_models().size()).is_greater(1000)


func test_every_entry_keeps_complete_legacy_fields() -> void:
	var models := _models()
	var bad := 0
	for key in models:
		var e: Dictionary = models[key]
		if str(e.get("url", "")).is_empty() or str(e.get("sha256", "")).is_empty() or int(e.get("size", 0)) <= 0:
			bad += 1
	assert_int(bad).is_equal(0)


## Complete = baked for an engine (godot_version) AND usable by the loader: ModelLibrary's own shared
## check accepts the single `textures.albedo` form and the multi-material `materials[]` form. No
## `size_class` requirement: nothing in scripts/ or tools/ reads it, and the Ratmen entries omit it.
static func _ctex_block_complete(c: Dictionary) -> bool:
	return c.has("godot_version") and ModelLibrary._ctex_block_usable(c)


func test_every_entry_has_a_complete_ctex_block() -> void:
	var models := _models()
	var incomplete := 0
	for key in models:
		if not _ctex_block_complete(models[key].get("ctex", {})):
			incomplete += 1
	assert_int(incomplete).is_equal(0)


## The live/staged manifest's multi-material form (model_manifest.staged_ctex.json, 392 of 1,406
## entries; the 221 Ratmen entries carry no size_class): mesh + godot_version + a non-empty
## `materials` ARRAY with an albedo per surface — the form ModelLibrary._ctex_block_usable loads.
## Shape copied from a staged entry (hashes shortened).
func test_the_multi_material_form_is_a_complete_ctex_block() -> void:
	var staged := {"godot_version": "4.6", "mesh": {"url": "f3e0.glb", "sha256": "f3e0", "size": 7660932},
		"materials": [{"surface": 0, "name": "Material_0", "albedo": {"url": "bfd1.ctex", "sha256": "bfd1", "size": 5592484}},
			{"surface": 1, "name": "Material_0.003", "albedo": {"url": "1b9e.ctex", "sha256": "1b9e", "size": 5592484}}]}
	assert_bool(_ctex_block_complete(staged)) \
		.override_failure_message("the staged multi-material ctex block (materials[], no size_class) must count as complete") \
		.is_true()
	var single := {"godot_version": "4.6", "size_class": "m", "mesh": {"sha256": "m", "url": "m.glb"},
		"textures": {"albedo": {"sha256": "a", "url": "a.ctex"}}}
	assert_bool(_ctex_block_complete(single)).is_true()
	# Incomplete shapes stay incomplete: the contract-v1 materials DICT, a surface without albedo,
	# no mesh, no godot_version, an empty block.
	assert_bool(_ctex_block_complete({"godot_version": "4.6", "mesh": {"sha256": "m"}, "materials": {"body": {}}})).is_false()
	assert_bool(_ctex_block_complete({"godot_version": "4.6", "mesh": {"sha256": "m"}, "materials": [{"surface": 0}]})).is_false()
	assert_bool(_ctex_block_complete({"godot_version": "4.6", "textures": {"albedo": {"sha256": "a"}}})).is_false()
	assert_bool(_ctex_block_complete({"mesh": {"sha256": "m"}, "textures": {"albedo": {"sha256": "a"}}})).is_false()
	assert_bool(_ctex_block_complete({})).is_false()


## Mirrors the per-entry unsafe guard of tools/merge_ctex_manifest.py: the legacy sha must NEVER
## equal the stripped ctex mesh sha — an old client resolving the legacy url would get a
## texture-less GLB. Static so BOTH branches have a case here: the live merged manifest can only
## ever be on the safe branch (the tool ABORTs before writing), so the unsafe branch needs a
## crafted entry (F17 — the guard never fired over 1,014 entries and had no test).
static func _legacy_sha_conflicts(entry: Dictionary) -> bool:
	var mesh_sha := str(entry.get("ctex", {}).get("mesh", {}).get("sha256", ""))
	return mesh_sha != "" and mesh_sha == str(entry.get("sha256", ""))


func test_unsafe_guard_flags_legacy_sha_equal_to_ctex_mesh() -> void:
	# The ABORT branch: this shape must be flagged (merge_ctex_manifest.py exits 1 on it).
	assert_bool(_legacy_sha_conflicts({"sha256": "meshsha", "ctex": {"mesh": {"sha256": "meshsha"}}})).is_true()


func test_unsafe_guard_passes_distinct_legacy_sha() -> void:
	# The safe branch: legacy sha different from (or absent) ctex mesh sha → merge proceeds.
	assert_bool(_legacy_sha_conflicts({"sha256": "legacy", "ctex": {"mesh": {"sha256": "meshsha"}}})).is_false()
	assert_bool(_legacy_sha_conflicts({"sha256": "legacy", "ctex": {}})).is_false()


func test_legacy_url_is_never_the_stripped_ctex_mesh() -> void:
	# The critical old-client safety invariant over the LIVE manifest (safe branch, all entries).
	var models := _models()
	var unsafe := 0
	for key in models:
		if _legacy_sha_conflicts(models[key]):
			unsafe += 1
	assert_int(unsafe).is_equal(0)
