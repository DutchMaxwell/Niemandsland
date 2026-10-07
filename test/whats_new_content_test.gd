extends GdUnitTestSuite

const SCRIPT := "res://scripts/whats_new_content.gd"
const STATE := "user://whats_new_test.cfg"
var _version: String

func before_test() -> void:
	_version = str(ProjectSettings.get_setting("application/config/version"))
	DirAccess.remove_absolute(STATE)

func after_test() -> void:
	ProjectSettings.set_setting("application/config/version", _version)
	DirAccess.remove_absolute(STATE)

func test_seen_version_survives_restart_and_new_version_is_unseen() -> void:
	assert_bool(FileAccess.file_exists(SCRIPT)).is_true()
	if not FileAccess.file_exists(SCRIPT):
		return
	var content = load(SCRIPT).new()
	assert_bool(content.should_show(STATE)).is_true()
	assert_int(content.mark_seen(STATE)).is_equal(OK)
	var restarted = load(SCRIPT).new()
	assert_bool(restarted.should_show(STATE)).is_false()
	ProjectSettings.set_setting("application/config/version", _version + ".next")
	assert_bool(restarted.should_show(STATE)).is_true()
	assert_int(restarted.mark_seen(STATE)).is_equal(OK)
	assert_bool(content.should_show(STATE)).is_false()

func test_bilingual_cards_have_two_sentences_and_capture_slots() -> void:
	assert_bool(FileAccess.file_exists(SCRIPT)).is_true()
	if not FileAccess.file_exists(SCRIPT):
		return
	var content = load(SCRIPT).new()
	assert_int(content.cards().size()).is_equal(5)
	for card: Dictionary in content.cards():
		assert_str(card.image).starts_with("res://assets/whats_new/")
		assert_bool(ResourceLoader.exists(card.image)).is_true()
		assert_str(card.capture).is_not_empty()
		for locale: String in ["en", "de"]:
			assert_str(card[locale].title).is_not_empty()
			assert_int(card[locale].body.split(". ").size()).is_equal(2)
	assert_str(content.text_for("de_DE", "menu")).is_equal("Was ist neu?")
	assert_str(content.text_for("fr", "menu")).is_equal(content.text_for("en", "menu"))
