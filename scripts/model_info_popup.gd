extends Control
class_name ModelInfoPopup
## Popup for displaying model information.
## Shows wounds, weapons, equipment, and markers in a formatted read-only view.

signal dialog_closed()

## UI references
var title_label: Label = null
var info_label: RichTextLabel = null
var close_button: Button = null

## Flag to prevent double signal connection
var _signals_connected: bool = false


func _ready() -> void:
	visible = false


## Opens the popup with model information.
func open(model: ModelInstance) -> void:
	if not model:
		return

	_update_display(model)
	visible = true


## Opens the popup with custom formatted content.
func open_with_content(title: String, content: String) -> void:
	if title_label:
		title_label.text = title
	if info_label:
		info_label.text = content
	visible = true


## Closes the popup.
func close() -> void:
	visible = false
	dialog_closed.emit()


## Updates the display with model data.
func _update_display(model: ModelInstance) -> void:
	if not model:
		return

	# Set title
	if title_label:
		var unit_name = ""
		if model.unit and model.unit is GameUnit:
			unit_name = model.unit.get_name() + " - "
		title_label.text = unit_name + model.get_display_name()

	# Build info content
	var lines: Array[String] = []
	lines.append("[b]Wounds:[/b] %d / %d" % [model.wounds_current, model.wounds_max])

	var weapons = model.get_weapons()
	if not weapons.is_empty():
		lines.append("")
		lines.append("[b]Weapons:[/b]")
		for weapon in weapons:
			if weapon is Dictionary:
				var w_name = weapon.get("name", "Unknown")
				var w_attacks = weapon.get("attacks", 1)
				var w_range = weapon.get("range", 0)
				var range_str = "Melee" if w_range == 0 else "%d\"" % w_range
				lines.append("  - %s (%s, A%d)" % [w_name, range_str, w_attacks])

	var equipment = model.get_equipment()
	if not equipment.is_empty():
		lines.append("")
		lines.append("[b]Equipment:[/b]")
		lines.append("  " + ", ".join(equipment))

	if not model.markers.is_empty():
		lines.append("")
		lines.append("[b]Markers:[/b]")
		lines.append("  " + ", ".join(model.markers))

	if info_label:
		info_label.text = "\n".join(lines)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()


## Creates a simple info popup programmatically (without scene).
static func create_simple() -> ModelInfoPopup:
	var popup = ModelInfoPopup.new()
	popup.name = "ModelInfoPopup"
	popup.theme = ThemeManager.get_current_theme()  # so PrimaryButton variations resolve
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.mouse_filter = Control.MOUSE_FILTER_STOP

	# Semi-transparent background
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.4)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	popup.add_child(bg)

	# Create centered panel container (tactical dark-glass panel + hairline + shadow)
	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(300, 200)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", HudTokens.panel_style())
	popup.add_child(panel)

	# Content margin inside the panel
	var margin = MarginContainer.new()
	UiPolish.set_dialog_margins(margin)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(margin)

	# VBox container
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", UiPolish.SECTION_SEP)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(vbox)

	# Tactical header (Orbitron title + amber index + accent line)
	vbox.add_child(HudTokens.header("MODEL INFO", "/// INFO"))

	# Title (dynamic — set per-model via open_with_content / _update_display)
	var title = Label.new()
	title.name = "TitleLabel"
	title.text = "Model Info"
	title.add_theme_font_override("font", HudTokens.mono_font())
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", UiPolish.TEXT_MUTED)
	vbox.add_child(title)
	popup.title_label = title

	# Info content (RichTextLabel for BBCode support)
	var info = RichTextLabel.new()
	info.name = "InfoLabel"
	info.bbcode_enabled = true
	info.fit_content = true
	info.custom_minimum_size = Vector2(280, 120)
	info.scroll_active = true
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(info)
	popup.info_label = info

	# Close button
	var close_btn = Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "CLOSE"
	UiPolish.primary_button(close_btn)
	vbox.add_child(close_btn)
	popup.close_button = close_btn

	# Corner-bracket chrome on top (instrumentation look; mouse-ignore)
	panel.add_child(HudFrame.new())

	# Connect signals
	close_btn.pressed.connect(popup.close)
	popup._signals_connected = true

	return popup
