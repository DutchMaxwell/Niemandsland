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
