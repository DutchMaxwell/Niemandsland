extends GdUnitTestSuite
## Tests for the startup update checker (update_checker.gd).
## The version comparison is pure and static — most of the surface is covered without
## any network. Persisted preferences are exercised against a real ConfigFile and
## cleaned up afterwards.

const UpdateCheckerScript := preload("res://scripts/update_checker.gd")


func _make_checker() -> Node:
	var checker: Node = auto_free(UpdateCheckerScript.new())
	add_child(checker)
	return checker


# ===== Current version =====

func test_current_version_matches_project_setting() -> void:
	var checker := _make_checker()
	var expected := str(ProjectSettings.get_setting("application/config/version", "unknown"))
	assert_that(checker.get_current_version()).is_equal(expected)
	assert_that(checker.get_current_version()).is_not_equal("unknown")


# ===== Tag normalization & parsing =====

func test_normalize_tag_strips_v_prefix_and_whitespace() -> void:
	assert_that(UpdateCheckerScript.normalize_tag("  v0.4.0 ")).is_equal("0.4.0")
	assert_that(UpdateCheckerScript.normalize_tag("V1.2.3-alpha")).is_equal("1.2.3-alpha")
	assert_that(UpdateCheckerScript.normalize_tag("0.3.1-alpha")).is_equal("0.3.1-alpha")


func test_parse_version_core_and_prerelease() -> void:
	var parsed := UpdateCheckerScript.parse_version("0.3.1-alpha")
	assert_bool(parsed["valid"]).is_true()
	assert_array(Array(parsed["core"] as PackedInt64Array)).is_equal([0, 3, 1, 0])
	assert_array(Array(parsed["prerelease"] as PackedStringArray)).is_equal(["alpha"])


func test_parse_version_rejects_non_numeric_core() -> void:
	assert_bool(UpdateCheckerScript.parse_version("garbage")["valid"]).is_false()
	assert_bool(UpdateCheckerScript.parse_version("")["valid"]).is_false()
	assert_bool(UpdateCheckerScript.parse_version("1.x.0")["valid"]).is_false()


func test_parse_version_ignores_build_metadata() -> void:
	var parsed := UpdateCheckerScript.parse_version("0.3.1-alpha+abc1234")
	assert_array(Array(parsed["core"] as PackedInt64Array)).is_equal([0, 3, 1, 0])
	assert_array(Array(parsed["prerelease"] as PackedStringArray)).is_equal(["alpha"])


# ===== Newer-than comparison =====

func test_newer_patch_minor_major() -> void:
	assert_bool(UpdateCheckerScript.is_newer("0.3.2-alpha", "0.3.1-alpha")).is_true()
	assert_bool(UpdateCheckerScript.is_newer("0.4.0-alpha", "0.3.1-alpha")).is_true()
	assert_bool(UpdateCheckerScript.is_newer("1.0.0", "0.9.9")).is_true()
	assert_bool(UpdateCheckerScript.is_newer("0.3.1-alpha", "0.3.2-alpha")).is_false()


func test_equal_version_is_not_newer() -> void:
	assert_bool(UpdateCheckerScript.is_newer("0.3.1-alpha", "0.3.1-alpha")).is_false()


func test_release_outranks_matching_prerelease() -> void:
	assert_bool(UpdateCheckerScript.is_newer("0.3.1", "0.3.1-alpha")).is_true()
	assert_bool(UpdateCheckerScript.is_newer("0.3.1-alpha", "0.3.1")).is_false()


func test_prerelease_identifier_ordering() -> void:
	assert_bool(UpdateCheckerScript.is_newer("0.3.1-beta", "0.3.1-alpha")).is_true()
	assert_bool(UpdateCheckerScript.is_newer("0.3.1-alpha.2", "0.3.1-alpha")).is_true()
	assert_bool(UpdateCheckerScript.is_newer("0.3.1-alpha.2", "0.3.1-alpha.10")).is_false()


func test_v_prefixed_tag_compares() -> void:
	assert_bool(UpdateCheckerScript.is_newer("v0.4.0", "0.3.1-alpha")).is_true()


func test_malformed_input_is_never_newer() -> void:
	assert_bool(UpdateCheckerScript.is_newer("", "0.3.1-alpha")).is_false()
	assert_bool(UpdateCheckerScript.is_newer("garbage", "0.3.1-alpha")).is_false()


# ===== select_latest =====

func test_select_latest_picks_highest() -> void:
	var tags := ["0.3.0-alpha", "0.4.0-alpha", "0.3.1-alpha"]
	assert_that(UpdateCheckerScript.select_latest(tags, true)).is_equal("0.4.0-alpha")


func test_select_latest_excludes_prereleases_when_disabled() -> void:
	var tags := ["0.4.0-alpha", "0.3.0", "0.3.0-beta"]
	assert_that(UpdateCheckerScript.select_latest(tags, false)).is_equal("0.3.0")


func test_select_latest_returns_empty_when_none_valid() -> void:
	assert_that(UpdateCheckerScript.select_latest(["garbage", ""], true)).is_equal("")


# ===== Persisted preferences =====

func test_skip_version_roundtrip() -> void:
	var checker := _make_checker()
	checker.clear_skip_version()
	assert_bool(checker.is_version_skipped("0.4.0-alpha")).is_false()
	checker.set_skip_version("v0.4.0-alpha")  # stored normalized
	assert_bool(checker.is_version_skipped("0.4.0-alpha")).is_true()
	assert_bool(checker.is_version_skipped("0.5.0-alpha")).is_false()
	checker.clear_skip_version()
	assert_bool(checker.is_version_skipped("0.4.0-alpha")).is_false()


func test_enabled_toggle_roundtrip() -> void:
	var checker := _make_checker()
	checker.set_enabled(false)
	assert_bool(checker.is_enabled()).is_false()
	checker.set_enabled(true)
	assert_bool(checker.is_enabled()).is_true()


# ===== one-click platform download link =====

func test_platform_asset_url_picks_matching_zip() -> void:
	var checker := _make_checker()
	var release := {
		"html_url": "https://example.com/releases/tag/v1",
		"assets": [
			{"name": "Niemandsland-v1-windows.zip", "browser_download_url": "https://example.com/win.zip"},
			{"name": "Niemandsland-v1-linux.zip", "browser_download_url": "https://example.com/lin.zip"},
		],
	}
	# One-click to THIS platform's zip. Keyword depends on the test host's OS.
	var key: String = checker._os_asset_keyword()
	if key == "linux":
		assert_str(checker._platform_asset_url(release)).is_equal("https://example.com/lin.zip")
	elif key == "windows":
		assert_str(checker._platform_asset_url(release)).is_equal("https://example.com/win.zip")
	else:
		assert_str(checker._platform_asset_url(release)).is_equal("https://example.com/releases/tag/v1")


func test_platform_asset_url_falls_back_to_page_without_match() -> void:
	var checker := _make_checker()
	var release := {
		"html_url": "https://example.com/releases/tag/v1",
		"assets": [{"name": "README.txt", "browser_download_url": "https://example.com/readme"}],
	}
	assert_str(checker._platform_asset_url(release)).is_equal("https://example.com/releases/tag/v1")


func test_compares_the_fourth_build_field() -> void:
	# Regression: the 4-field scheme (MAJOR.MINOR.PATCH.BUILD) must compare ALL four fields.
	# Comparing only three made 0.3.6.0 and 0.3.6.1 look identical -> the in-game update prompt
	# never fired (the reason 0.3.6.0 clients saw no 0.3.6.1).
	assert_bool(UpdateCheckerScript.is_newer("0.3.6.1-alpha", "0.3.6.0-alpha")).is_true()
	assert_bool(UpdateCheckerScript.is_newer("0.3.7.1-alpha", "0.3.7.0-alpha")).is_true()
	assert_bool(UpdateCheckerScript.is_newer("0.3.6.0-alpha", "0.3.6.1-alpha")).is_false()
	# A 3-field version equals its 4-field-with-trailing-zero form, so both schemes interoperate.
	assert_int(UpdateCheckerScript.compare_versions("0.3.7-alpha", "0.3.7.0-alpha")).is_equal(0)
	# The 0.3.7 jump is detectable even by a plain 3-field comparison (first three fields rose).
	assert_bool(UpdateCheckerScript.is_newer("0.3.7-alpha", "0.3.6.0-alpha")).is_true()
