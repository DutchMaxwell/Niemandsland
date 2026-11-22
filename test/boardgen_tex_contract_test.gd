extends GdUnitTestSuite
## The scale contract of the town's authored sets (texture plan step 16, D-TEX2): every set has 110-180 texels per board inch, so no two
## neighbouring surfaces differ by x2 or more; every patterned set's feature reads from the start camera (>= 0.30 in); the sets stay <= 16 MB.
## With NML_RUINTOWN_DEV_LIB=<staged library folder> the staged files are held to it too: their real pixel size (the .ctex header) over the
## manifest's tile_in. Unset (CI): only the contract itself is checked.

const DEV_LIB_ENV := "NML_RUINTOWN_DEV_LIB"


func test_every_town_set_has_a_contract_and_the_contract_keeps_one_scale() -> void:
	var names := BoardgenTheme.TOWN_SETS.map(func(s: Array) -> String: return s[0])
	assert_array(names).contains_exactly_in_any_order(BoardgenTheme.TOWN_SET_CONTRACT.keys())
	for name: String in BoardgenTheme.TOWN_SET_CONTRACT:
		var c: Dictionary = BoardgenTheme.TOWN_SET_CONTRACT[name]
		var tpi := float(c["px"]) / float(c["tile_in"])
		assert_bool(tpi >= BoardgenTheme.TOWN_TEXELS_PER_IN.x and tpi <= BoardgenTheme.TOWN_TEXELS_PER_IN.y).override_failure_message("%s: %.0f texels/in" % [name, tpi]).is_true()
		if name not in ["earth", "plaster"]:   # no pattern of their own: only the macro layer reads there
			assert_float(c["feature_in"]).override_failure_message("%s: feature %.2f in" % [name, c["feature_in"]]).is_greater_equal(BoardgenTheme.TOWN_FEATURE_MIN_IN)


func test_the_staged_library_keeps_the_contract() -> void:
	var dir := OS.get_environment(DEV_LIB_ENV)
	if dir == "" or not FileAccess.file_exists(dir.path_join("manifest.json")):
		return   # no staged library on this machine
	var sets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("manifest.json")))["sets"]
	var total := 0
	for name: String in sets:
		var s: Dictionary = sets[name]
		for map in ["albedo", "normal", "orm"]:
			total += int(s[map]["size"])
		var f := FileAccess.open(dir.path_join(s["albedo"]["url"]), FileAccess.READ)
		assert_object(f).is_not_null()
		if f == null:
			continue
		assert_str(f.get_buffer(4).get_string_from_ascii()).is_equal("GST2")   # Godot's CompressedTexture2D: magic, version, width, height
		f.get_32()
		var tpi := float(f.get_32()) / float(s["tile_in"])
		assert_bool(tpi >= BoardgenTheme.TOWN_TEXELS_PER_IN.x and tpi <= BoardgenTheme.TOWN_TEXELS_PER_IN.y).override_failure_message("staged %s: %.0f texels/in" % [name, tpi]).is_true()
	assert_int(total).is_less_equal(BoardgenTheme.TOWN_SETS_MAX_BYTES)
