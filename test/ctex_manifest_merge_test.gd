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
	var bad := 0
	for key in _models():
		var e: Dictionary = _models()[key]
		if str(e.get("url", "")).is_empty() or str(e.get("sha256", "")).is_empty() or int(e.get("size", 0)) <= 0:
			bad += 1
	assert_int(bad).is_equal(0)


func test_every_entry_has_a_complete_ctex_block() -> void:
	var incomplete := 0
	for key in _models():
		var c: Dictionary = _models()[key].get("ctex", {})
		var tex: Dictionary = c.get("textures", {})
		if c.is_empty() or not c.has("mesh") or not c.has("godot_version") \
				or not c.has("size_class") or not tex.has("albedo"):
			incomplete += 1
	assert_int(incomplete).is_equal(0)


func test_legacy_url_is_never_the_stripped_ctex_mesh() -> void:
	# The critical old-client safety invariant: a legacy sha must differ from its ctex.mesh sha.
	var unsafe := 0
	for key in _models():
		var e: Dictionary = _models()[key]
		var mesh_sha := str(e.get("ctex", {}).get("mesh", {}).get("sha256", ""))
		if mesh_sha != "" and mesh_sha == str(e.get("sha256", "")):
			unsafe += 1
	assert_int(unsafe).is_equal(0)
