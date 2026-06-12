extends GdUnitTestSuite
## PlayerIdentity: name sanitization and the peer-id display fallback.
## Persistence (load/save) touches user:// and is covered by the live test, not here.

# ===== sanitize =====


func test_sanitize_trims_and_passes_clean_name() -> void:
	assert_str(PlayerIdentity.sanitize("Alice")).is_equal("Alice")
	assert_str(PlayerIdentity.sanitize("  Bob  ")).is_equal("Bob")


func test_sanitize_collapses_internal_whitespace() -> void:
	assert_str(PlayerIdentity.sanitize("Big    Boss")).is_equal("Big Boss")


func test_sanitize_strips_control_characters() -> void:
	assert_str(PlayerIdentity.sanitize("Eve\nMallory")).is_equal("EveMallory")
	assert_str(PlayerIdentity.sanitize("Tab\there")).is_equal("Tabhere")


func test_sanitize_clamps_to_max_length() -> void:
	var long_name := "X".repeat(PlayerIdentity.MAX_NAME_LEN + 10)
	assert_int(PlayerIdentity.sanitize(long_name).length()).is_equal(PlayerIdentity.MAX_NAME_LEN)


func test_sanitize_empty_and_whitespace_only_return_empty() -> void:
	assert_str(PlayerIdentity.sanitize("")).is_empty()
	assert_str(PlayerIdentity.sanitize("   ")).is_empty()
	assert_str(PlayerIdentity.sanitize("\n\t")).is_empty()

# ===== display_name =====


func test_display_name_uses_sanitized_name() -> void:
	assert_str(PlayerIdentity.display_name("  Carol ", 3)).is_equal("Carol")


func test_display_name_falls_back_to_peer_id() -> void:
	assert_str(PlayerIdentity.display_name("", 2)).is_equal("Player 2")
	assert_str(PlayerIdentity.display_name("   ", 4)).is_equal("Player 4")
