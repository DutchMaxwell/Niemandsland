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


func test_every_entry_has_a_complete_ctex_block() -> void:
	var models := _models()
	var incomplete := 0
	for key in models:
		var c: Dictionary = models[key].get("ctex", {})
		var tex: Dictionary = c.get("textures", {})
		if c.is_empty() or not c.has("mesh") or not c.has("godot_version") \
				or not c.has("size_class") or not tex.has("albedo"):
			incomplete += 1
	assert_int(incomplete).is_equal(0)


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
