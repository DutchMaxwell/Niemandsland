extends GdUnitTestSuite
## The ruin-town dressing's manifest has to be IN the export (docs/adr/0004-dressing-materials-and-kit-manifest.md): a non-resource file only ships when an include_filter of every export preset matches it, and the kit loader reads
## res://assets/ruintown_dress.json at runtime. No exclude_filter may match it either.

const MANIFEST := "res://assets/ruintown_dress.json"


func test_every_export_preset_includes_the_dressing_manifest_and_none_excludes_it() -> void:
	assert_bool(FileAccess.file_exists(MANIFEST)).is_true()
	var presets := ConfigFile.new()
	assert_int(presets.load("res://export_presets.cfg")).is_equal(OK)
	var checked := 0
	for section in presets.get_sections():
		if not presets.has_section_key(section, "include_filter"):
			continue
		checked += 1
		var included := false
		for pattern in str(presets.get_value(section, "include_filter")).split(","):
			included = included or MANIFEST.trim_prefix("res://").match(pattern.strip_edges())
		assert_bool(included).override_failure_message("%s: assets/ruintown_dress.json is not in include_filter" % section).is_true()
		for pattern in str(presets.get_value(section, "exclude_filter")).split(","):
			assert_bool(MANIFEST.trim_prefix("res://").match(pattern.strip_edges())).override_failure_message("%s: excluded by `%s`" % [section, pattern]).is_false()
	assert_int(checked).is_greater_equal(3)   # Linux, Windows Desktop, macOS
