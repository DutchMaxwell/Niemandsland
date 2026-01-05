class_name BattleSimulatorUI
extends Control
## UI for the AI vs AI Battle Simulator.
## Provides controls for loading armies, advancing steps, and viewing battle progress.

# ===== Signals =====

signal army_load_requested(player: int)
signal close_requested


# ===== References =====

var simulator: BattleSimulator = null
var army_manager: OPRArmyManager = null


# ===== UI Elements =====

var main_container: VBoxContainer
var header_panel: PanelContainer
var content_split: HSplitContainer

# Left side - Controls
var control_panel: VBoxContainer
var army1_section: VBoxContainer
var army2_section: VBoxContainer
var army1_label: Label
var army2_label: Label
var army1_button: Button
var army2_button: Button
var start_button: Button
var stop_button: Button

# Center - Step display
var step_panel: PanelContainer
var step_container: VBoxContainer
var step_title: Label
var step_description: Label
var step_details: RichTextLabel
var step_result: Label
var advance_button: Button
var auto_advance_check: CheckBox
var skip_buttons: HBoxContainer

# Right side - Log
var log_panel: PanelContainer
var log_container: VBoxContainer
var log_scroll: ScrollContainer
var log_content: RichTextLabel
var clear_log_button: Button

# Bottom - Status
var status_bar: HBoxContainer
var phase_label: Label
var round_label: Label
var score_label: Label
var step_count_label: Label


# ===== Colors =====

const COLOR_PLAYER1 = Color(0.2, 0.4, 0.8)
const COLOR_PLAYER2 = Color(0.8, 0.2, 0.2)
const COLOR_HEADER = Color(0.15, 0.15, 0.18)
const COLOR_PANEL = Color(0.12, 0.12, 0.14)
const COLOR_HIGHLIGHT = Color(0.3, 0.5, 0.3)


func _ready() -> void:
	_build_ui()
	_connect_signals()


## Initializes the UI with references.
func initialize(p_simulator: BattleSimulator, p_army_manager: OPRArmyManager) -> void:
	simulator = p_simulator
	army_manager = p_army_manager

	# Connect simulator signals
	simulator.step_ready.connect(_on_step_ready)
	simulator.step_executed.connect(_on_step_executed)
	simulator.state_changed.connect(_on_state_changed)
	simulator.battle_log.connect(_on_battle_log)
	simulator.battle_started.connect(_on_battle_started)
	simulator.battle_ended.connect(_on_battle_ended)

	_update_army_display()


# ===== UI Building =====

func _build_ui() -> void:
	# Make full screen
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Main background
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main container
	main_container = VBoxContainer.new()
	main_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_container.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	add_child(main_container)

	_build_header()
	_build_content()
	_build_status_bar()


func _build_header() -> void:
	header_panel = PanelContainer.new()
	var header_style = StyleBoxFlat.new()
	header_style.bg_color = COLOR_HEADER
	header_style.corner_radius_top_left = 8
	header_style.corner_radius_top_right = 8
	header_panel.add_theme_stylebox_override("panel", header_style)
	main_container.add_child(header_panel)

	var header_content = HBoxContainer.new()
	header_content.add_theme_constant_override("separation", 20)
	header_panel.add_child(header_content)

	# Title
	var title = Label.new()
	title.text = "Battle Simulator"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color.WHITE)
	header_content.add_child(title)

	# Spacer
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_content.add_child(spacer)

	# Close button
	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(40, 40)
	close_btn.pressed.connect(func(): close_requested.emit())
	header_content.add_child(close_btn)


func _build_content() -> void:
	content_split = HSplitContainer.new()
	content_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_split.split_offset = 250
	main_container.add_child(content_split)

	_build_control_panel()
	_build_center_panel()


func _build_control_panel() -> void:
	var left_container = VBoxContainer.new()
	left_container.custom_minimum_size.x = 250
	content_split.add_child(left_container)

	# Army 1 Section
	army1_section = _create_army_section(1, "Player 1 Army", COLOR_PLAYER1)
	left_container.add_child(army1_section)

	# Army 2 Section
	army2_section = _create_army_section(2, "Player 2 Army", COLOR_PLAYER2)
	left_container.add_child(army2_section)

	# Spacer
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_container.add_child(spacer)

	# Battle controls
	var battle_section = _create_section("Battle Controls")
	left_container.add_child(battle_section)

	var battle_buttons = VBoxContainer.new()
	battle_buttons.add_theme_constant_override("separation", 8)
	battle_section.add_child(battle_buttons)

	start_button = Button.new()
	start_button.text = "Start Battle"
	start_button.custom_minimum_size.y = 40
	start_button.pressed.connect(_on_start_pressed)
	battle_buttons.add_child(start_button)

	stop_button = Button.new()
	stop_button.text = "Stop Battle"
	stop_button.custom_minimum_size.y = 40
	stop_button.disabled = true
	stop_button.pressed.connect(_on_stop_pressed)
	battle_buttons.add_child(stop_button)


func _create_army_section(player_id: int, title: String, color: Color) -> VBoxContainer:
	var section = _create_section(title, color)

	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	section.add_child(content)

	var army_label = Label.new()
	army_label.text = "No army loaded"
	army_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	content.add_child(army_label)

	var load_btn = Button.new()
	load_btn.text = "Load Army..."
	load_btn.pressed.connect(func(): army_load_requested.emit(player_id))
	content.add_child(load_btn)

	if player_id == 1:
		army1_label = army_label
		army1_button = load_btn
	else:
		army2_label = army_label
		army2_button = load_btn

	return section


func _create_section(title: String, accent_color: Color = Color.WHITE) -> VBoxContainer:
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)

	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.border_color = accent_color
	style.border_width_left = 3
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)
	section.add_child(panel)

	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	panel.add_child(container)

	var title_label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", accent_color)
	container.add_child(title_label)

	return container


func _build_center_panel() -> void:
	var center_split = HSplitContainer.new()
	center_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_split.split_offset = -300
	content_split.add_child(center_split)

	# Step display
	_build_step_panel(center_split)

	# Log panel
	_build_log_panel(center_split)


func _build_step_panel(parent: Control) -> void:
	step_panel = PanelContainer.new()
	step_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	step_panel.add_theme_stylebox_override("panel", style)
	parent.add_child(step_panel)

	step_container = VBoxContainer.new()
	step_container.add_theme_constant_override("separation", 16)
	step_panel.add_child(step_container)

	# Step title
	step_title = Label.new()
	step_title.text = "Waiting to Start"
	step_title.add_theme_font_size_override("font_size", 28)
	step_title.add_theme_color_override("font_color", Color.WHITE)
	step_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_container.add_child(step_title)

	# Step description
	step_description = Label.new()
	step_description.text = "Load armies and click Start Battle to begin"
	step_description.add_theme_font_size_override("font_size", 18)
	step_description.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	step_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_container.add_child(step_description)

	# Step details
	step_details = RichTextLabel.new()
	step_details.bbcode_enabled = true
	step_details.fit_content = true
	step_details.custom_minimum_size.y = 100
	step_details.add_theme_color_override("default_color", Color(0.7, 0.7, 0.7))
	step_container.add_child(step_details)

	# Step result
	step_result = Label.new()
	step_result.text = ""
	step_result.add_theme_font_size_override("font_size", 16)
	step_result.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	step_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_container.add_child(step_result)

	# Spacer
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	step_container.add_child(spacer)

	# Advance button
	advance_button = Button.new()
	advance_button.text = "CLICK TO ADVANCE"
	advance_button.custom_minimum_size = Vector2(300, 60)
	advance_button.add_theme_font_size_override("font_size", 20)
	advance_button.disabled = true
	advance_button.pressed.connect(_on_advance_pressed)
	var btn_container = CenterContainer.new()
	btn_container.add_child(advance_button)
	step_container.add_child(btn_container)

	# Auto-advance checkbox
	var options_row = HBoxContainer.new()
	options_row.alignment = BoxContainer.ALIGNMENT_CENTER
	options_row.add_theme_constant_override("separation", 20)
	step_container.add_child(options_row)

	auto_advance_check = CheckBox.new()
	auto_advance_check.text = "Auto-advance"
	auto_advance_check.toggled.connect(_on_auto_advance_toggled)
	options_row.add_child(auto_advance_check)

	# Skip buttons
	skip_buttons = HBoxContainer.new()
	skip_buttons.add_theme_constant_override("separation", 8)
	options_row.add_child(skip_buttons)

	var skip_deploy = Button.new()
	skip_deploy.text = "Skip Deployment"
	skip_deploy.pressed.connect(func(): _skip_to_phase(BattleSimulator.Phase.ROUND_START))
	skip_buttons.add_child(skip_deploy)

	var skip_round = Button.new()
	skip_round.text = "Skip to Round End"
	skip_round.pressed.connect(func(): _skip_to_phase(BattleSimulator.Phase.ROUND_END))
	skip_buttons.add_child(skip_round)


func _build_log_panel(parent: Control) -> void:
	log_panel = PanelContainer.new()
	log_panel.custom_minimum_size.x = 300
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	log_panel.add_theme_stylebox_override("panel", style)
	parent.add_child(log_panel)

	log_container = VBoxContainer.new()
	log_container.add_theme_constant_override("separation", 8)
	log_panel.add_child(log_container)

	# Log header
	var log_header = HBoxContainer.new()
	log_container.add_child(log_header)

	var log_title = Label.new()
	log_title.text = "Battle Log"
	log_title.add_theme_font_size_override("font_size", 16)
	log_header.add_child(log_title)

	var log_spacer = Control.new()
	log_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_header.add_child(log_spacer)

	clear_log_button = Button.new()
	clear_log_button.text = "Clear"
	clear_log_button.pressed.connect(_on_clear_log_pressed)
	log_header.add_child(clear_log_button)

	# Log scroll
	log_scroll = ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_container.add_child(log_scroll)

	log_content = RichTextLabel.new()
	log_content.bbcode_enabled = true
	log_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_content.fit_content = true
	log_content.add_theme_font_size_override("normal_font_size", 12)
	log_scroll.add_child(log_content)


func _build_status_bar() -> void:
	var status_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_HEADER
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	status_panel.add_theme_stylebox_override("panel", style)
	main_container.add_child(status_panel)

	status_bar = HBoxContainer.new()
	status_bar.add_theme_constant_override("separation", 40)
	status_panel.add_child(status_bar)

	phase_label = Label.new()
	phase_label.text = "Phase: Setup"
	status_bar.add_child(phase_label)

	round_label = Label.new()
	round_label.text = "Round: 0/4"
	status_bar.add_child(round_label)

	score_label = Label.new()
	score_label.text = "Score: P1: 0 | P2: 0"
	status_bar.add_child(score_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_bar.add_child(spacer)

	step_count_label = Label.new()
	step_count_label.text = "Steps: 0"
	status_bar.add_child(step_count_label)


func _connect_signals() -> void:
	pass  # Signals connected in initialize()


# ===== Event Handlers =====

func _on_start_pressed() -> void:
	if not simulator:
		return

	simulator.setup_loaded_armies()

	# Setup mission with default table bounds
	var table_bounds = Rect2(-0.6096, -0.6096, 1.2192, 1.2192)  # 4x4 feet
	simulator.setup_mission(table_bounds)

	simulator.start_battle()

	start_button.disabled = true
	stop_button.disabled = false
	advance_button.disabled = false
	army1_button.disabled = true
	army2_button.disabled = true


func _on_stop_pressed() -> void:
	if not simulator:
		return

	simulator.stop_battle()

	start_button.disabled = false
	stop_button.disabled = true
	advance_button.disabled = true
	army1_button.disabled = false
	army2_button.disabled = false


func _on_advance_pressed() -> void:
	if simulator:
		simulator.advance_step()


func _on_auto_advance_toggled(pressed: bool) -> void:
	if simulator:
		simulator.auto_advance = pressed
		if pressed and simulator.is_waiting():
			simulator.advance_step()


func _on_clear_log_pressed() -> void:
	log_content.clear()


func _skip_to_phase(phase: BattleSimulator.Phase) -> void:
	if simulator:
		simulator.skip_to_phase(phase)


# ===== Simulator Signal Handlers =====

func _on_step_ready(step: BattleSimulator.BattleStep) -> void:
	step_title.text = step.description
	step_description.text = step.details

	# Build details text
	var details_text = ""

	if step.unit:
		var player_id = step.unit.unit_properties.get("player_id", 1)
		var color = COLOR_PLAYER1 if player_id == 1 else COLOR_PLAYER2
		details_text += "[color=#%s]%s[/color]\n" % [color.to_html(false), step.unit.get_name()]

		# Unit stats
		details_text += "Q%d+ | D%d+ | %d models\n" % [
			step.unit.get_quality(),
			step.unit.get_defense(),
			step.unit.get_alive_count()
		]

	if step.target_unit:
		var player_id = step.target_unit.unit_properties.get("player_id", 1)
		var color = COLOR_PLAYER1 if player_id == 1 else COLOR_PLAYER2
		details_text += "\n[b]Target:[/b] [color=#%s]%s[/color]\n" % [
			color.to_html(false),
			step.target_unit.get_name()
		]

	if step.show_path:
		var distance = step.path_start.distance_to(step.path_end)
		details_text += "\nMovement: %.1f\"" % (distance / 0.0254)

	step_details.text = details_text
	step_result.text = ""

	advance_button.text = "CLICK TO EXECUTE"
	advance_button.disabled = false

	step_count_label.text = "Steps: %d pending" % simulator.get_pending_steps()


func _on_step_executed(step: BattleSimulator.BattleStep) -> void:
	step_result.text = step.result_text

	# Color result based on step type
	match step.type:
		"shoot", "melee":
			if step.casualties > 0:
				step_result.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
			else:
				step_result.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
		"morale":
			if "FAILED" in step.result_text:
				step_result.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
			else:
				step_result.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
		_:
			step_result.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))


func _on_state_changed(state: BattleSimulator.BattleState) -> void:
	# Update phase label
	var phase_names = {
		BattleSimulator.Phase.SETUP: "Setup",
		BattleSimulator.Phase.DEPLOYMENT: "Deployment",
		BattleSimulator.Phase.ROUND_START: "Round Start",
		BattleSimulator.Phase.PLAYER_TURN: "Player Turn",
		BattleSimulator.Phase.ACTIVATION: "Activation",
		BattleSimulator.Phase.MOVEMENT: "Movement",
		BattleSimulator.Phase.SHOOTING: "Shooting",
		BattleSimulator.Phase.MELEE: "Melee",
		BattleSimulator.Phase.MORALE: "Morale",
		BattleSimulator.Phase.ROUND_END: "Round End",
		BattleSimulator.Phase.GAME_OVER: "Game Over"
	}
	phase_label.text = "Phase: %s" % phase_names.get(state.phase, "Unknown")

	round_label.text = "Round: %d/%d" % [state.current_round, state.max_rounds]
	score_label.text = "Score: P1: %d | P2: %d" % [state.player1_objectives, state.player2_objectives]


func _on_battle_log(message: String, type: String) -> void:
	var color = Color.WHITE

	match type:
		"header":
			color = Color(1.0, 0.8, 0.2)
		"phase":
			color = Color(0.5, 0.8, 1.0)
		"action":
			color = Color(0.8, 0.8, 0.8)
		"combat":
			color = Color(1.0, 0.5, 0.5)
		"morale":
			color = Color(0.8, 0.6, 1.0)
		"info":
			color = Color(0.6, 0.6, 0.6)
		"error":
			color = Color(1.0, 0.3, 0.3)
		"ai":
			color = Color(0.6, 0.8, 0.6)

	log_content.push_color(color)
	log_content.add_text(message + "\n")
	log_content.pop()

	# Auto-scroll to bottom
	await get_tree().process_frame
	log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)


func _on_battle_started(army1_name: String, army2_name: String) -> void:
	step_title.text = "Battle Started!"
	step_description.text = "%s vs %s" % [army1_name, army2_name]


func _on_battle_ended(winner: int, final_state: BattleSimulator.BattleState) -> void:
	advance_button.disabled = true
	start_button.disabled = false
	stop_button.disabled = true
	army1_button.disabled = false
	army2_button.disabled = false

	var winner_text = "TIE!"
	var winner_color = Color.YELLOW

	if winner == 1:
		winner_text = "%s WINS!" % simulator.player1_army_name
		winner_color = COLOR_PLAYER1
	elif winner == 2:
		winner_text = "%s WINS!" % simulator.player2_army_name
		winner_color = COLOR_PLAYER2

	step_title.text = winner_text
	step_title.add_theme_color_override("font_color", winner_color)
	step_description.text = "Final Score: P1: %d objectives | P2: %d objectives" % [
		final_state.player1_objectives,
		final_state.player2_objectives
	]


# ===== Public Methods =====

## Updates the army display labels.
func _update_army_display() -> void:
	if not army_manager:
		return

	var army1 = army_manager.get_army(1)
	var army2 = army_manager.get_army(2)

	if army1:
		army1_label.text = "%s\n%d units" % [army1.name, army1.units.size()]
		army1_label.add_theme_color_override("font_color", Color.WHITE)
	else:
		army1_label.text = "No army loaded"
		army1_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

	if army2:
		army2_label.text = "%s\n%d units" % [army2.name, army2.units.size()]
		army2_label.add_theme_color_override("font_color", Color.WHITE)
	else:
		army2_label.text = "No army loaded"
		army2_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

	# Enable start button only if both armies are loaded
	start_button.disabled = not (army1 and army2)


## Called when armies are loaded.
func on_armies_loaded() -> void:
	_update_army_display()


## Shows the UI.
func show_ui() -> void:
	_update_army_display()  # Refresh army display when opening
	show()


## Hides the UI.
func hide_ui() -> void:
	hide()
