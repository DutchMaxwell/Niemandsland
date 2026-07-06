extends GdUnitTestSuite
## AssetCDN: expansion of the "{cdn}" token in manifest base_urls to the live
## host. The host lives in exactly one place (AssetCDN.HOST); manifests stay
## domain-agnostic. See docs/ASSET_DELIVERY.md.

# ===== expand =====


func test_expand_token_root_yields_host_with_slash() -> void:
	assert_str(AssetCDN.expand("{cdn}/")).is_equal(AssetCDN.HOST + "/")


func test_expand_token_with_path_prepends_host() -> void:
	assert_str(AssetCDN.expand("{cdn}/terrain-source/ambience")) \
		.is_equal(AssetCDN.HOST + "/terrain-source/ambience")


func test_expand_empty_passes_through() -> void:
	assert_str(AssetCDN.expand("")).is_empty()


func test_expand_absolute_url_passes_through_unchanged() -> void:
	# Test fixtures and any fully-qualified manifest must not be rewritten.
	assert_str(AssetCDN.expand("https://cdn/")).is_equal("https://cdn/")


func test_host_carries_no_trailing_slash() -> void:
	# Guards the "{cdn}/" convention: the slash comes from the manifest, not HOST.
	assert_bool(AssetCDN.HOST.ends_with("/")).is_false()


# ===== request headers (bus 037: honest product UA so Cloudflare doesn't bot-challenge us) =====


func test_user_agent_is_honest_product_string() -> void:
	var ua := AssetCDN.user_agent()
	# Product UA — NOT a fake Mozilla string; carries the real version + OS + engine.
	assert_str(ua).starts_with("Niemandsland/")
	assert_bool(ua.contains(OS.get_name())).is_true()
	assert_bool(ua.contains("Godot 4.6")).is_true()
	assert_bool(ua.to_lower().contains("mozilla")).is_false()


func test_headers_carry_ua_and_accept() -> void:
	var h := AssetCDN.headers("application/json")
	assert_int(h.size()).is_equal(2)
	assert_str(h[0]).starts_with("User-Agent: Niemandsland/")
	assert_str(h[1]).is_equal("Accept: application/json")


func test_headers_default_accept_is_wildcard() -> void:
	assert_str(AssetCDN.headers()[1]).is_equal("Accept: */*")


# ===== end-to-end through a library =====


func test_library_resolves_tokenized_manifest_to_live_host() -> void:
	var lib := AmbienceLibrary.new()
	add_child(lib)
	auto_free(lib)
	var manifest := JSON.stringify({
		"version": 1,
		"base_url": "{cdn}/terrain-source/ambience",
		"sounds": {"rain_loop": {"url": "rain.ogg", "sha256": "x", "size": 1, "loop": true}},
	})
	lib.apply_manifest_text(manifest)
	var entry := {"url": "rain.ogg", "sha256": "x", "size": 1, "loop": true}
	assert_str(lib._resolve_url(entry)) \
		.is_equal(AssetCDN.HOST + "/terrain-source/ambience/rain.ogg")
