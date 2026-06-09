extends ConfirmationDialog
class_name UpdatePrompt
## Non-blocking "a newer version is available" dialog shown over the startup menu.
## Built entirely in code to match the menu's other popups (host/join). It only
## presents information and collects intent; the startup menu performs the actions
## (open the download page, persist a skip) so this stays free of side effects.

# ===== Constants =====

const DIALOG_TITLE: String = "Update available"
const DOWNLOAD_LABEL: String = "Download"
const LATER_LABEL: String = "Later"
const SKIP_LABEL: String = "Skip this version"
const CONTENT_SEPARATION: int = 10
const NOTES_MIN_SIZE: Vector2 = Vector2(420, 140)

# ===== Public state =====

## Normalized version string of the offered release (e.g. "0.4.0-alpha").
var latest_version: String = ""
## Page to open when the player chooses to download.
var release_url: String = ""

# ===== Private state =====

var _skip_checkbox: CheckBox

# ===== Public API =====

## Fills the dialog. Call once before adding it to the tree and popping it up.
func setup(current_version: String, offered_version: String, url: String, notes: String) -> void:
	title = DIALOG_TITLE
	latest_version = offered_version
	release_url = url
	ok_button_text = DOWNLOAD_LABEL
	get_cancel_button().text = LATER_LABEL

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", CONTENT_SEPARATION)

	var headline := Label.new()
	headline.text = "A newer version of Niemandsland is available."
	content.add_child(headline)

	var versions := Label.new()
	versions.text = "Installed: %s    →    Latest: %s" % [current_version, offered_version]
	content.add_child(versions)

	if not notes.strip_edges().is_empty():
		var notes_label := RichTextLabel.new()
		notes_label.bbcode_enabled = false
		notes_label.fit_content = true
		notes_label.scroll_active = true
		notes_label.custom_minimum_size = NOTES_MIN_SIZE
		notes_label.text = notes
		content.add_child(notes_label)

	_skip_checkbox = CheckBox.new()
	_skip_checkbox.text = SKIP_LABEL
	content.add_child(_skip_checkbox)

	add_child(content)


## Whether the player ticked "Skip this version".
func is_skip_checked() -> bool:
	return _skip_checkbox != null and _skip_checkbox.button_pressed
