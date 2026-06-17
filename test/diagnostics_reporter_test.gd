extends GdUnitTestSuite
## Diagnostics scrub: the privacy boundary. Verifies secrets (username, player names, room
## code) are replaced, longest-first so a name containing another is fully scrubbed, and that
## very short secrets are skipped so they can't blank the whole report.

const Reporter := preload("res://scripts/diagnostics_reporter.gd")


func test_scrub_replaces_each_secret() -> void:
	var text := "path /home/maxwell/x | room ABC123 | player Alice"
	var out := Reporter.scrub_text(text, [["maxwell", "<user>"], ["ABC123", "<room>"], ["Alice", "<player>"]])
	assert_str(out).not_contains("maxwell")
	assert_str(out).not_contains("ABC123")
	assert_str(out).not_contains("Alice")
	assert_str(out).contains("<user>")
	assert_str(out).contains("<room>")
	assert_str(out).contains("<player>")


func test_scrub_longest_first_avoids_partial_replace() -> void:
	# "Bob" is a substring of "Bobby"; longest-first must replace "Bobby" wholly.
	var out := Reporter.scrub_text("Bobby and Bob", [["Bob", "<p>"], ["Bobby", "<p>"]])
	assert_str(out).is_equal("<p> and <p>")


func test_scrub_skips_too_short_secret() -> void:
	# A 1-char secret would blank the text; it is skipped (MIN_SECRET_LEN).
	var out := Reporter.scrub_text("a army of ants", [["a", "<x>"]])
	assert_str(out).is_equal("a army of ants")


func test_gather_replacements_includes_names_and_room() -> void:
	var pairs := Reporter.gather_replacements(["Alice", "Bob"], "XYZ12")
	var secrets: Array = []
	for p in pairs:
		secrets.append(p[0])
	assert_bool(secrets.has("Alice")).is_true()
	assert_bool(secrets.has("Bob")).is_true()
	assert_bool(secrets.has("XYZ12")).is_true()


func test_gather_replacements_ignores_blank_room_and_names() -> void:
	var pairs := Reporter.gather_replacements(["", "  "], "")
	var secrets: Array = []
	for p in pairs:
		secrets.append(p[0])
	assert_bool(secrets.has("")).is_false()
	# (a username from the env may still be present; we only assert the blanks are gone)


# ===== Room-code discovery (so prior-session codes in the multi-log report get scrubbed) =====

func test_room_codes_discovered_dashed_and_undashed() -> void:
	var log_text := "=== ROOM CREATED: V2K-T9S ===\n=== JOINING ONLINE room 9RVCJH ===\n[Relay] Connection lost (peer=2 room=JV5HUM): dropped"
	var codes := Reporter._room_codes_in(log_text)
	# the dashed code yields both forms; the undashed ones come through as-is
	assert_array(codes).contains(["V2K-T9S", "V2KT9S", "9RVCJH", "JV5HUM"])


func test_room_codes_ignore_lowercase_words() -> void:
	# "Room not found" must not be mistaken for a code (the code class is uppercase-only).
	assert_array(Reporter._room_codes_in("WARNING: Relay error: Room not found")).is_empty()


func test_discovered_room_code_scrubs_out() -> void:
	var log_text := "joined room 9RVCJH ok"
	var pairs: Array = []
	for c in Reporter._room_codes_in(log_text):
		pairs.append([c, "<room>"])
	assert_str(Reporter.scrub_text(log_text, pairs)).is_equal("joined room <room> ok")
