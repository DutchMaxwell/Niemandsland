extends PanelContainer
class_name OPRStatsTooltip
## Tooltip panel that displays OPR unit statistics on mouse hover
## Shows unit name, quality/defense, weapons, and special rules

@onready var unit_name_label: RichTextLabel = $MarginContainer/VBox/UnitNameLabel
@onready var stats_label: RichTextLabel = $MarginContainer/VBox/StatsLabel
@onready var weapons_label: RichTextLabel = $MarginContainer/VBox/WeaponsLabel
@onready var rules_label: RichTextLabel = $MarginContainer/VBox/RulesLabel

## Reference to the army manager for unit lookups
var army_manager: OPRArmyManager

## Currently displayed unit
var _current_unit: OPRApiClient.OPRUnit = null

## Pending unit (waiting for delay)
var _pending_unit: OPRApiClient.OPRUnit = null

## Delay timer for showing tooltip
var _show_timer: Timer

## Offset from cursor
const TOOLTIP_OFFSET = Vector2(15, 15)

## Delay before showing tooltip (seconds)
const SHOW_DELAY: float = 0.4


func _ready() -> void:
	# Start hidden
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Create delay timer
	_show_timer = Timer.new()
	_show_timer.one_shot = true
	_show_timer.timeout.connect(_on_show_timer_timeout)
	add_child(_show_timer)

	# Make sure all children ignore mouse
	_set_mouse_ignore_recursive(self)


func _set_mouse_ignore_recursive(node: Control) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control:
			_set_mouse_ignore_recursive(child)


func _process(_delta: float) -> void:
	if visible:
		_update_position()


## Update tooltip position to follow cursor
func _update_position() -> void:
	var viewport = get_viewport()
	if not viewport:
		return

	var mouse_pos = viewport.get_mouse_position()
	var viewport_size = viewport.get_visible_rect().size
	var tooltip_size = size

	# Calculate position with offset
	var new_pos = mouse_pos + TOOLTIP_OFFSET

	# Keep tooltip within viewport bounds
	if new_pos.x + tooltip_size.x > viewport_size.x:
		new_pos.x = mouse_pos.x - tooltip_size.x - TOOLTIP_OFFSET.x
	if new_pos.y + tooltip_size.y > viewport_size.y:
		new_pos.y = mouse_pos.y - tooltip_size.y - TOOLTIP_OFFSET.y

	# Ensure not negative
	new_pos.x = max(0, new_pos.x)
	new_pos.y = max(0, new_pos.y)

	global_position = new_pos


## Show tooltip for a specific unit (with delay)
func show_unit(unit: OPRApiClient.OPRUnit) -> void:
	if not unit:
		hide_tooltip()
		return

	if _current_unit == unit and visible:
		return  # Already showing this unit

	# If we're already waiting for this unit, don't restart timer
	if _pending_unit == unit:
		return

	# Store pending unit and start delay timer
	_pending_unit = unit
	_show_timer.start(SHOW_DELAY)


## Called when the show delay timer expires
func _on_show_timer_timeout() -> void:
	if _pending_unit:
		_current_unit = _pending_unit
		_pending_unit = null
		_update_content()
		# Force resize to fit content
		reset_size()
		visible = true
		_update_position()


## Hide the tooltip
func hide_tooltip() -> void:
	_show_timer.stop()
	_pending_unit = null
	visible = false
	_current_unit = null


## Update tooltip content with current unit data
func _update_content() -> void:
	if not _current_unit:
		return

	# Unit name with size
	var name_text = "[b]%s[/b]" % _current_unit.get_display_name()
	unit_name_label.text = name_text

	# Core stats
	var stats_text = "Quality: [color=#88ff88]%d+[/color] | Defense: [color=#8888ff]%d+[/color]" % [
		_current_unit.quality,
		_current_unit.defense
	]
	if _current_unit.cost > 0:
		stats_text += " | [color=#ffcc44]%d pts[/color]" % _current_unit.cost
	stats_label.text = stats_text

	# Weapons
	if _current_unit.weapons.size() > 0:
		var weapons_text = "[b]Weapons:[/b]\n"
		for weapon in _current_unit.weapons:
			weapons_text += "  %s\n" % _format_weapon(weapon)
		weapons_label.text = weapons_text.strip_edges()
		weapons_label.visible = true
	else:
		weapons_label.visible = false

	# Equipment and special rules
	var all_rules: Array[String] = []
	all_rules.append_array(_current_unit.equipment)
	all_rules.append_array(_current_unit.special_rules)

	if all_rules.size() > 0:
		var rules_text = "[b]Rules:[/b] [color=#aaaaaa]%s[/color]" % ", ".join(all_rules)
		rules_label.text = rules_text
		rules_label.visible = true
	else:
		rules_label.visible = false


## Format weapon for display
func _format_weapon(weapon: OPRApiClient.OPRWeapon) -> String:
	var parts: Array[String] = []

	# Name with count
	if weapon.count > 1:
		parts.append("%dx %s" % [weapon.count, weapon.name])
	else:
		parts.append(weapon.name)

	# Range
	if weapon.range_value > 0:
		parts.append("[color=#88ccff]%d\"[/color]" % weapon.range_value)
	else:
		parts.append("[color=#ff8888]Melee[/color]")

	# Attacks
	parts.append("A%d" % weapon.attacks)

	# Special rules
	if weapon.special_rules.size() > 0:
		parts.append("[color=#aaaaaa](%s)[/color]" % ", ".join(weapon.special_rules))

	return " ".join(parts)
