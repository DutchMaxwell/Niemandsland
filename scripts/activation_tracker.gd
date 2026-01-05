extends Control
class_name ActivationTracker
## Panel that tracks unit activations during a game round.
## Shows all units by player with activation status.

signal round_changed(new_round: int)
signal unit_clicked(game_unit: GameUnit)

## Current game round
var current_round: int = 1

## Current player turn (1 or 2)
var current_player: int = 1

## Reference to the army manager
var army_manager: OPRArmyManager = null

## UI references
@onready var round_label: Label = $Panel/VBox/Header/RoundLabel
@onready var player_label: Label = $Panel/VBox/Header/PlayerLabel
@onready var player1_container: VBoxContainer = $Panel/VBox/Player1Section/UnitList
@onready var player2_container: VBoxContainer = $Panel/VBox/Player2Section/UnitList
@onready var new_round_button: Button = $Panel/VBox/Buttons/NewRoundButton
@onready var end_turn_button: Button = $Panel/VBox/Buttons/EndTurnButton


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	if new_round_button:
		new_round_button.pressed.connect(_on_new_round_pressed)
	if end_turn_button:
		end_turn_button.pressed.connect(_on_end_turn_pressed)


## Initializes with army manager reference.
func initialize(p_army_manager: OPRArmyManager) -> void:
	army_manager = p_army_manager
	refresh()


## Refreshes the display with current unit data.
func refresh() -> void:
	_update_header()
	_update_player_units(1, player1_container)
	_update_player_units(2, player2_container)


func _update_header() -> void:
	if round_label:
		round_label.text = "Round %d" % current_round

	if player_label:
		player_label.text = "Player %d's Turn" % current_player


func _update_player_units(player_id: int, container: VBoxContainer) -> void:
	if not container:
		return

	# Clear existing
	for child in container.get_children():
		child.queue_free()

	if not army_manager:
		return

	# Get units for this player
	var units = army_manager.get_game_units_for_player(player_id)

	for game_unit in units:
		var item = _create_unit_item(game_unit)
		container.add_child(item)


func _create_unit_item(game_unit: GameUnit) -> Control:
	var hbox = HBoxContainer.new()

	# Activation checkbox/indicator
	var checkbox = CheckBox.new()
	checkbox.button_pressed = game_unit.is_activated
	checkbox.toggled.connect(_on_unit_activation_toggled.bind(game_unit))
	checkbox.tooltip_text = "Activated" if game_unit.is_activated else "Not activated"
	hbox.add_child(checkbox)

	# Unit name button
	var name_btn = Button.new()
	name_btn.flat = true
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var display_name = game_unit.get_name()
	var suffix = game_unit.unit_properties.get("display_suffix", "")
	var alive_count = game_unit.get_alive_count()
	var total_count = game_unit.models.size()

	name_btn.text = "%s%s [%d/%d]" % [display_name, suffix, alive_count, total_count]
	name_btn.pressed.connect(_on_unit_clicked.bind(game_unit))

	# Gray out if all dead
	if alive_count == 0:
		name_btn.modulate = Color(0.5, 0.5, 0.5)

	hbox.add_child(name_btn)

	# Points cost
	var cost_label = Label.new()
	cost_label.text = "%dpts" % game_unit.get_cost()
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_label.custom_minimum_size = Vector2(60, 0)
	hbox.add_child(cost_label)

	# Show attachment info
	if game_unit.is_hero():
		var attached_to = game_unit.get_attached_to()
		if attached_to and attached_to is GameUnit:
			var attach_label = Label.new()
			attach_label.text = "→ %s" % attached_to.get_name()
			attach_label.modulate = Color(0.7, 0.7, 0.7)
			hbox.add_child(attach_label)

	return hbox


func _on_unit_activation_toggled(toggled: bool, game_unit: GameUnit) -> void:
	if toggled:
		game_unit.activate(current_round)
	else:
		game_unit.reset_activation()

	refresh()


func _on_unit_clicked(game_unit: GameUnit) -> void:
	unit_clicked.emit(game_unit)


func _on_new_round_pressed() -> void:
	# Reset all activations
	if army_manager:
		for game_unit in army_manager.get_all_game_units():
			game_unit.reset_activation()

	current_round += 1
	current_player = 1
	round_changed.emit(current_round)
	refresh()


func _on_end_turn_pressed() -> void:
	# Switch to other player
	current_player = 2 if current_player == 1 else 1
	refresh()


## Gets the current round number.
func get_current_round() -> int:
	return current_round


## Sets the current round number.
func set_current_round(round_num: int) -> void:
	current_round = round_num
	refresh()


## Creates the activation tracker programmatically (without scene).
static func create_simple() -> ActivationTracker:
	var tracker = ActivationTracker.new()
	tracker.name = "ActivationTracker"
	tracker.custom_minimum_size = Vector2(300, 400)

	# Create panel
	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tracker.add_child(panel)

	# Main VBox
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Header
	var header = HBoxContainer.new()
	header.name = "Header"
	vbox.add_child(header)

	var round_lbl = Label.new()
	round_lbl.name = "RoundLabel"
	round_lbl.text = "Round 1"
	round_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(round_lbl)
	tracker.round_label = round_lbl

	var player_lbl = Label.new()
	player_lbl.name = "PlayerLabel"
	player_lbl.text = "Player 1's Turn"
	player_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(player_lbl)
	tracker.player_label = player_lbl

	# Separator
	vbox.add_child(HSeparator.new())

	# Player 1 section
	var p1_section = VBoxContainer.new()
	p1_section.name = "Player1Section"
	vbox.add_child(p1_section)

	var p1_label = Label.new()
	p1_label.text = "Player 1 (Blue)"
	p1_label.add_theme_color_override("font_color", Color(0.3, 0.5, 0.9))
	p1_section.add_child(p1_label)

	var p1_scroll = ScrollContainer.new()
	p1_scroll.custom_minimum_size = Vector2(0, 120)
	p1_section.add_child(p1_scroll)

	var p1_list = VBoxContainer.new()
	p1_list.name = "UnitList"
	p1_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p1_scroll.add_child(p1_list)
	tracker.player1_container = p1_list

	# Separator
	vbox.add_child(HSeparator.new())

	# Player 2 section
	var p2_section = VBoxContainer.new()
	p2_section.name = "Player2Section"
	vbox.add_child(p2_section)

	var p2_label = Label.new()
	p2_label.text = "Player 2 (Red)"
	p2_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	p2_section.add_child(p2_label)

	var p2_scroll = ScrollContainer.new()
	p2_scroll.custom_minimum_size = Vector2(0, 120)
	p2_section.add_child(p2_scroll)

	var p2_list = VBoxContainer.new()
	p2_list.name = "UnitList"
	p2_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p2_scroll.add_child(p2_list)
	tracker.player2_container = p2_list

	# Separator
	vbox.add_child(HSeparator.new())

	# Buttons
	var buttons = HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons)

	var end_turn_btn = Button.new()
	end_turn_btn.name = "EndTurnButton"
	end_turn_btn.text = "End Turn"
	buttons.add_child(end_turn_btn)
	tracker.end_turn_button = end_turn_btn

	var new_round_btn = Button.new()
	new_round_btn.name = "NewRoundButton"
	new_round_btn.text = "New Round"
	buttons.add_child(new_round_btn)
	tracker.new_round_button = new_round_btn

	tracker._setup_ui()

	return tracker
