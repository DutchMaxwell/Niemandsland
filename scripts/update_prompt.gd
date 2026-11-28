extends ConfirmationDialog
class_name UpdatePrompt
## Non-blocking "a newer version is available" dialog shown over the startup menu.
## Built entirely in code to match the menu's other popups (host/join). It only
## presents information and collects intent; the startup menu performs the actions
## (open the download page, persist a skip) so this stays free of side effects.

# ===== Constants =====

const DIALOG_TITLE: String = "Update available"
const DOWNLOAD_LABEL: String = "Update & Restart"
const LATER_LABEL: String = "Later"
const SKIP_LABEL: String = "Skip this version"
const CONTENT_SEPARATION: int = 10
## The window is 560 px wide (its sheet pads 22 px each side) and as high as its content; the changelog stands in
## a card of fixed height and SCROLLS inside it instead of growing the dialog past the screen (which pushed the
## Download/Later buttons out of reach).
const CONTENT_WIDTH: int = 516
const NOTES_HEIGHT: int = 132
const HEADLINE_PX: int = 22
const NOTES_PX: int = 15

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

	content.custom_minimum_size.x = CONTENT_WIDTH
	var headline := HouseStyle.label("A newer version of Niemandsland is available.", HouseStyle.BODY)
	headline.add_theme_font_override("font", HouseStyle.font(500))
	headline.add_theme_font_size_override("font_size", HEADLINE_PX)
	content.add_child(headline)

	# One mono line in a card: INSTALLED a  →  LATEST b, the offered version in gold.
	var versions := HBoxContainer.new()
	versions.add_theme_constant_override("separation", 0)
	for part: Array in [["INSTALLED %s  →  LATEST " % current_version.to_upper(), HouseStyle.INK],
			[offered_version.to_upper(), HouseStyle.GOLD]]:
		var piece := HouseStyle.label(part[0], HouseStyle.BODY)
		piece.add_theme_font_override("font", HouseStyle.mono())
		piece.add_theme_font_size_override("font_size", HouseStyle.MENU_FONT_EYEBROW)
		piece.add_theme_color_override("font_color", part[1])
		versions.add_child(piece)
	content.add_child(HouseStyle.card(versions))

	if not notes.strip_edges().is_empty():
		var notes_label := RichTextLabel.new()
		notes_label.bbcode_enabled = false
		notes_label.fit_content = false  # don't grow to the full changelog height — scroll instead,
		notes_label.scroll_active = true # so the dialog stays small and its buttons stay reachable
		notes_label.add_theme_font_size_override("normal_font_size", NOTES_PX)
		notes_label.add_theme_color_override("default_color", HouseStyle.MUTED)
		notes_label.custom_minimum_size.y = NOTES_HEIGHT
		notes_label.text = notes
		content.add_child(HouseStyle.card(notes_label))

	var howto := Label.new()
	howto.text = "Niemandsland downloads the update and restarts itself. If that isn't possible, the download page opens instead."
	howto.autowrap_mode = TextServer.AUTOWRAP_WORD
	howto.custom_minimum_size.x = CONTENT_WIDTH   # a wrapping label measures at width 0 without a floor
	content.add_child(howto)

	_skip_checkbox = CheckBox.new()
	_skip_checkbox.text = SKIP_LABEL
	content.add_child(_skip_checkbox)

	# Later left, Update & Restart right: two equal 44 px buttons in the content's own row, wired to the dialog's
	# own buttons (which stay, hidden), so every handler and test sees the same signals.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", HouseStyle.GAP_CONTROL)
	row.add_child(_row_button(LATER_LABEL, HouseStyle.BUTTON, get_cancel_button()))
	row.add_child(_row_button(DOWNLOAD_LABEL, HouseStyle.PRIMARY, get_ok_button()))
	content.add_child(row)
	MenuDialog.add_header(self, content)
	add_child(content)
	MenuDialog.style(self)
	get_ok_button().hide()
	get_cancel_button().hide()


func _row_button(text: String, variant: StringName, target: Button) -> Button:
	var b := HouseStyle.button(text, variant, HouseStyle.MENU_H_ACTION)
	b.pressed.connect(func() -> void: target.pressed.emit())
	return b


## Whether the player ticked "Skip this version".
func is_skip_checked() -> bool:
	return _skip_checkbox != null and _skip_checkbox.button_pressed
