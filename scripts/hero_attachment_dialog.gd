extends Control
class_name HeroAttachmentDialog
## Dialog shown after import for heroes to attach them to units.
## Shows all heroes in the army and available units to attach to.

signal attachment_confirmed(hero: GameUnit, target: GameUnit)
signal attachment_skipped(hero: GameUnit)
signal all_attachments_done()

## List of heroes to process
var _heroes_to_process: Array[GameUnit] = []

## Current hero being processed
var _current_hero: GameUnit = null

## Available target units
var _available_units: Array[GameUnit] = []

## UI references
@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var hero_info_label: RichTextLabel = $Panel/VBox/HeroInfo
@onready var unit_list: ItemList = $Panel/VBox/UnitList
@onready var skip_button: Button = $Panel/VBox/Buttons/SkipButton
@onready var skip_all_button: Button = $Panel/VBox/Buttons/SkipAllButton
@onready var confirm_button: Button = $Panel/VBox/Buttons/ConfirmButton


func _ready() -> void:
	visible = false
	_setup_ui()


func _setup_ui() -> void:
	if skip_button:
		skip_button.pressed.connect(_on_skip_pressed)
	if skip_all_button:
		skip_all_button.pressed.connect(_on_skip_all_pressed)
	if confirm_button:
		confirm_button.pressed.connect(_on_confirm_pressed)
	if unit_list:
		unit_list.item_selected.connect(_on_unit_selected)


## Starts the hero attachment process for a list of game units.
## Filters out heroes automatically.
func start_attachment(all_units: Array[GameUnit]) -> void:
	_heroes_to_process.clear()
	_available_units.clear()

	# Separate heroes from regular units
	for unit in all_units:
		if EquipmentDistributor.is_hero(unit):
			_heroes_to_process.append(unit)
		else:
			_available_units.append(unit)

	# If no heroes, we're done
	if _heroes_to_process.is_empty():
		all_attachments_done.emit()
		return

	# Start with first hero
	_show_next_hero()


## Shows the dialog for the next hero.
func _show_next_hero() -> void:
	if _heroes_to_process.is_empty():
		visible = false
		all_attachments_done.emit()
		return

	_current_hero = _heroes_to_process.pop_front()
	visible = true
	_update_display()
	_center_dialog()


func _center_dialog() -> void:
	var viewport_size = get_viewport_rect().size
	position = (viewport_size - size) / 2


func _update_display() -> void:
	if not _current_hero:
		return

	# Update title
	if title_label:
		var remaining = _heroes_to_process.size()
		if remaining > 0:
			title_label.text = "Hero Attachment (%d remaining)" % remaining
		else:
			title_label.text = "Hero Attachment (last one)"

	# Update hero info
	if hero_info_label:
		var lines: Array[String] = []
		lines.append("[b]%s[/b]" % _current_hero.get_name())
		lines.append("Q%d+ | D%d+ | %dpts" % [
			_current_hero.get_quality(),
			_current_hero.get_defense(),
			_current_hero.get_cost()
		])

		var rules = _current_hero.get_special_rules()
		if not rules.is_empty():
			var rule_strings: Array[String] = []
			for rule in rules:
				if rule is String:
					rule_strings.append(rule)
				elif rule is Dictionary:
					var name = rule.get("name", "")
					var rating = rule.get("rating", 0)
					if rating > 0:
						rule_strings.append("%s(%d)" % [name, rating])
					else:
						rule_strings.append(name)
			lines.append("")
			lines.append("[i]%s[/i]" % ", ".join(rule_strings))

		hero_info_label.text = "\n".join(lines)

	# Update unit list
	if unit_list:
		unit_list.clear()

		# Add "Independent" option first
		unit_list.add_item("(Independent - no attachment)")

		# Add available units
		for unit in _available_units:
			var text = "%s [%d] - %dpts" % [
				unit.get_name(),
				unit.models.size(),
				unit.get_cost()
			]
			unit_list.add_item(text)

		# Select "Independent" by default
		unit_list.select(0)

	# Update button states
	if confirm_button:
		confirm_button.disabled = false


func _on_unit_selected(index: int) -> void:
	# Enable confirm button
	if confirm_button:
		confirm_button.disabled = false


func _on_skip_pressed() -> void:
	if not _current_hero:
		return

	attachment_skipped.emit(_current_hero)
	_show_next_hero()


func _on_skip_all_pressed() -> void:
	# Skip all remaining heroes
	if _current_hero:
		attachment_skipped.emit(_current_hero)

	for hero in _heroes_to_process:
		attachment_skipped.emit(hero)

	_heroes_to_process.clear()
	visible = false
	all_attachments_done.emit()


func _on_confirm_pressed() -> void:
	if not _current_hero or not unit_list:
		return

	var selected_idx = unit_list.get_selected_items()
	if selected_idx.is_empty():
		return

	var idx = selected_idx[0]

	if idx == 0:
		# Independent - no attachment
		attachment_skipped.emit(_current_hero)
	else:
		# Attach to selected unit (idx - 1 because of Independent option)
		var target_idx = idx - 1
		if target_idx >= 0 and target_idx < _available_units.size():
			var target = _available_units[target_idx]
			EquipmentDistributor.attach_hero_to_unit(_current_hero, target)
			attachment_confirmed.emit(_current_hero, target)

	_show_next_hero()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_skip_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER:
			_on_confirm_pressed()
			get_viewport().set_input_as_handled()


## Creates the hero attachment dialog programmatically (without scene).
static func create_simple() -> HeroAttachmentDialog:
	var dialog = HeroAttachmentDialog.new()
	dialog.name = "HeroAttachmentDialog"

	# Create panel
	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(400, 350)
	dialog.add_child(panel)

	# Main VBox
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.name = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "Hero Attachment"
	vbox.add_child(title)
	dialog.title_label = title

	# Separator
	vbox.add_child(HSeparator.new())

	# Hero info
	var hero_info = RichTextLabel.new()
	hero_info.name = "HeroInfo"
	hero_info.bbcode_enabled = true
	hero_info.custom_minimum_size = Vector2(0, 80)
	hero_info.fit_content = true
	vbox.add_child(hero_info)
	dialog.hero_info_label = hero_info

	# Separator
	vbox.add_child(HSeparator.new())

	# Instruction label
	var instruction = Label.new()
	instruction.text = "Attach to unit:"
	vbox.add_child(instruction)

	# Unit list
	var unit_list = ItemList.new()
	unit_list.name = "UnitList"
	unit_list.custom_minimum_size = Vector2(0, 150)
	unit_list.select_mode = ItemList.SELECT_SINGLE
	vbox.add_child(unit_list)
	dialog.unit_list = unit_list

	# Buttons
	var buttons = HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons)

	var skip_all_btn = Button.new()
	skip_all_btn.name = "SkipAllButton"
	skip_all_btn.text = "Skip All"
	buttons.add_child(skip_all_btn)
	dialog.skip_all_button = skip_all_btn

	var skip_btn = Button.new()
	skip_btn.name = "SkipButton"
	skip_btn.text = "Skip"
	buttons.add_child(skip_btn)
	dialog.skip_button = skip_btn

	var confirm_btn = Button.new()
	confirm_btn.name = "ConfirmButton"
	confirm_btn.text = "Confirm"
	buttons.add_child(confirm_btn)
	dialog.confirm_button = confirm_btn

	dialog._setup_ui()

	return dialog
