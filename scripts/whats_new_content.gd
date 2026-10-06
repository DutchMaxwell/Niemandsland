class_name WhatsNewContent
extends RefCounted
## Release copy and acknowledgement; the installed version has one source in project.godot.

const STATE_PATH := "user://whats_new.cfg"
const DATA_PATH := "res://data/whats_new.json"
var _data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))

## The same version displayed by the startup menu and update checker.
static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))

## Missing preferences (including an existing installation's first update) count as unseen.
static func should_show(path: String = STATE_PATH) -> bool:
	var config := ConfigFile.new()
	config.load(path)
	return not version().is_empty() and str(config.get_value("news", "last_seen_version", "")) != version()

## Save only after the screen has actually been opened; callers can retry a failed write.
static func mark_seen(path: String = STATE_PATH) -> Error:
	var config := ConfigFile.new()
	config.load(path)
	config.set_value("news", "last_seen_version", version())
	return config.save(path)

## Match the existing UI's German locale prefix and English fallback.
static func language(locale: String) -> String:
	return "de" if locale.to_lower().begins_with("de") else "en"

## Localized chrome lives beside the card copy, never in the view code.
func text_for(locale: String, key: String) -> String:
	return str(_data[language(locale)][key])

## Ordered release highlights, with optional screenshots and render-lane capture instructions.
func cards() -> Array:
	return _data.cards
