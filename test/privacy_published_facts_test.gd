extends GdUnitTestSuite

## RED gate for publishing the maintainer's privacy facts (2026-09-14): the EN
## "controller" line in the privacy screen must no longer carry the
## "to be published by the maintainer" placeholder.


func test_en_controller_string_no_longer_carries_the_placeholder() -> void:
	var menu_script = load("res://scripts/privacy/privacy_menu.gd")
	assert_str(menu_script.text_for("en", "controller")).not_contains("to be published")