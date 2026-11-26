class_name UpdateProgressDialog
extends AcceptDialog
## The window the self-update shows while it downloads and stages the new files: the stage text, the per cent in mono
## gold at its right, a 4 px bar (accent to gold, as the loading bar) and the line that says the game restarts by
## itself. It has no buttons: the update either restarts the game or fails into a notice.

const DIALOG_TITLE := "Updating Niemandsland"
const CONTENT_WIDTH := 516
const BAR_H := 4.0
const NOTE := "The game restarts by itself when the files are in place."

var _stage: Label
var _percent: Label
var _track: Control
var _fill: TextureRect


func _ready() -> void:
	title = DIALOG_TITLE
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = CONTENT_WIDTH
	content.add_theme_constant_override("separation", HouseStyle.GAP_SECTION)
	var header := MenuDialog.add_header(self, content)
	header.get_parent().get_node("CloseButton").visible = false   # nothing to cancel
	var line := HBoxContainer.new()
	_stage = HouseStyle.label("Starting…", HouseStyle.BODY)
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_percent = HouseStyle.label("", HouseStyle.BODY)
	_percent.add_theme_font_override("font", HouseStyle.mono())
	_percent.add_theme_color_override("font_color", HouseStyle.GOLD)
	line.add_child(_stage)
	line.add_child(_percent)
	content.add_child(line)
	_track = Control.new()
	_track.custom_minimum_size = Vector2(0, BAR_H)
	_track.clip_contents = true
	var well := ColorRect.new()
	well.color = HouseStyle.FILL_RAISED
	well.set_anchors_preset(Control.PRESET_FULL_RECT)
	_track.add_child(well)
	var gradient := Gradient.new()
	gradient.set_color(0, HouseStyle.ACCENT)
	gradient.set_color(1, HouseStyle.GOLD)
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	_fill = TextureRect.new()
	_fill.texture = texture
	_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fill.stretch_mode = TextureRect.STRETCH_SCALE
	_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fill.anchor_right = 0.0   # the fill is a share of the track's width, whatever its layout state
	_track.add_child(_fill)
	content.add_child(_track)
	var note := HouseStyle.label(NOTE, HouseStyle.CAPTION)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = CONTENT_WIDTH
	content.add_child(note)
	add_child(content)
	MenuDialog.style(self)
	get_ok_button().hide()


## Feeds the window: `ratio` 0..1 fills the bar and shows the per cent; a negative ratio is a stage without a measure.
func show_progress(stage: String, ratio: float) -> void:
	_stage.text = "%s…" % stage
	_percent.text = "%d %%" % roundi(ratio * 100.0) if ratio >= 0.0 else ""
	_fill.anchor_right = clampf(ratio, 0.0, 1.0)
