extends Control
class_name RadialMenu
## A radial/pie menu for context-sensitive actions on units and models.
## Follows UX best practices: Fitts's Law, muscle memory, gesture support.

signal action_selected(action_id: String, context: Dictionary)
signal menu_closed()

# ===== Configuration =====

## Menu radius in pixels
@export var menu_radius: float = 100.0

## Inner dead zone radius (cancel area)
@export var center_radius: float = 30.0

## Animation duration in seconds
@export var animation_duration: float = 0.15

## Colors
@export var background_color: Color = Color(0.1, 0.1, 0.15, 0.95)
@export var segment_color: Color = Color(0.2, 0.25, 0.3, 1.0)
@export var segment_hover_color: Color = Color(0.3, 0.5, 0.8, 1.0)
@export var text_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var disabled_color: Color = Color(0.5, 0.5, 0.5, 0.5)


# ===== Internal State =====

## Currently displayed menu items
var _items: Array[RadialMenuItem] = []

## Currently hovered item index (-1 = none/center)
var _hovered_index: int = -1

## Context data passed to actions
var _context: Dictionary = {}

## Is the menu currently visible
var _is_open: bool = false

## Animation tween
var _tween: Tween = null

## Center position of the menu
var _center_pos: Vector2 = Vector2.ZERO


# ===== Menu Item Class =====

class RadialMenuItem:
	var id: String = ""
	var label: String = ""
	var icon: String = ""
	var enabled: bool = true
	var tooltip: String = ""
	var shortcut_key: int = 0  # 1-8

	func _init(p_id: String, p_label: String, p_icon: String = "", p_enabled: bool = true):
		id = p_id
		label = p_label
		icon = p_icon
		enabled = p_enabled


# ===== Lifecycle =====

func _ready() -> void:
	# Start hidden
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Set up for drawing
	set_process_input(true)


func _draw() -> void:
	if not _is_open or _items.is_empty():
		return

	var item_count = _items.size()
	var angle_step = TAU / item_count
	var start_angle = -PI / 2 - angle_step / 2  # Start from top

	# Draw background circle
	draw_circle(_center_pos, menu_radius, background_color)

	# Draw center (cancel zone)
	draw_circle(_center_pos, center_radius, segment_color.darkened(0.3))

	# Draw segments
	for i in range(item_count):
		var item = _items[i]
		var angle_start = start_angle + i * angle_step
		var angle_end = angle_start + angle_step

		# Determine color
		var color = segment_color
		if not item.enabled:
			color = disabled_color
		elif i == _hovered_index:
			color = segment_hover_color

		# Draw segment arc
		_draw_segment(angle_start, angle_end, color)

		# Draw label
		var label_angle = angle_start + angle_step / 2
		var label_radius = (menu_radius + center_radius) / 2
		var label_pos = _center_pos + Vector2(cos(label_angle), sin(label_angle)) * label_radius

		# Draw icon and text
		var display_text = item.icon if not item.icon.is_empty() else item.label
		var font = ThemeDB.fallback_font
		var font_size = ThemeDB.fallback_font_size
		var text_size = font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos = label_pos - text_size / 2

		var text_col = text_color if item.enabled else disabled_color
		draw_string(font, text_pos, display_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_col)

	# Draw center cancel icon
	var cancel_text = "✕"
	var font = ThemeDB.fallback_font
	var font_size = ThemeDB.fallback_font_size
	var cancel_size = font.get_string_size(cancel_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, _center_pos - cancel_size / 2, cancel_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color.darkened(0.3))


func _draw_segment(angle_start: float, angle_end: float, color: Color) -> void:
	var points: PackedVector2Array = []
	var colors: PackedColorArray = []

	# Inner arc
	var segments = 16
	for i in range(segments + 1):
		var t = float(i) / segments
		var angle = lerp(angle_start, angle_end, t)
		points.append(_center_pos + Vector2(cos(angle), sin(angle)) * center_radius)
		colors.append(color)

	# Outer arc (reversed)
	for i in range(segments, -1, -1):
		var t = float(i) / segments
		var angle = lerp(angle_start, angle_end, t)
		points.append(_center_pos + Vector2(cos(angle), sin(angle)) * menu_radius)
		colors.append(color)

	if points.size() >= 3:
		draw_polygon(points, colors)


# ===== Input Handling =====

func _input(event: InputEvent) -> void:
	if not _is_open:
		return

	if event is InputEventMouseMotion:
		_update_hover(event.position)
		queue_redraw()

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_select_current()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			close()
			get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_8:
			var index = event.keycode - KEY_1
			if index < _items.size():
				_select_index(index)
				get_viewport().set_input_as_handled()


func _update_hover(mouse_pos: Vector2) -> void:
	var offset = mouse_pos - _center_pos
	var distance = offset.length()

	# In center = cancel zone
	if distance < center_radius:
		_hovered_index = -1
		return

	# Outside menu = no hover
	if distance > menu_radius * 1.2:
		_hovered_index = -1
		return

	# Calculate which segment
	var angle = offset.angle()
	var item_count = _items.size()
	var angle_step = TAU / item_count
	var start_angle = -PI / 2 - angle_step / 2

	# Normalize angle to match our coordinate system
	var normalized_angle = fmod(angle - start_angle + TAU, TAU)
	_hovered_index = int(normalized_angle / angle_step) % item_count


func _select_current() -> void:
	if _hovered_index < 0:
		# Center = cancel
		close()
		return

	_select_index(_hovered_index)


func _select_index(index: int) -> void:
	if index < 0 or index >= _items.size():
		return

	var item = _items[index]
	if not item.enabled:
		return

	action_selected.emit(item.id, _context)
	close()


# ===== Public API =====

## Opens the menu at the specified position with the given items.
func open(position: Vector2, items: Array[RadialMenuItem], context: Dictionary = {}) -> void:
	_items = items
	_context = context
	_center_pos = position
	_hovered_index = -1
	_is_open = true

	# Assign shortcut keys
	for i in range(min(items.size(), 8)):
		items[i].shortcut_key = i + 1

	# Animate in
	visible = true
	modulate.a = 0.0
	scale = Vector2(0.8, 0.8)
	pivot_offset = _center_pos

	if _tween:
		_tween.kill()

	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_BACK)
	_tween.tween_property(self, "modulate:a", 1.0, animation_duration)
	_tween.parallel().tween_property(self, "scale", Vector2.ONE, animation_duration)

	queue_redraw()


## Closes the menu.
func close() -> void:
	if not _is_open:
		return

	_is_open = false

	if _tween:
		_tween.kill()

	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, "modulate:a", 0.0, animation_duration * 0.5)
	_tween.parallel().tween_property(self, "scale", Vector2(0.9, 0.9), animation_duration * 0.5)
	_tween.tween_callback(func():
		visible = false
		_items.clear()
		menu_closed.emit()
	)


## Checks if the menu is currently open.
func is_open() -> bool:
	return _is_open


# ===== Context-Specific Menu Builders =====

## Creates menu items for a single model selection.
static func create_model_menu(model: ModelInstance) -> Array[RadialMenuItem]:
	var items: Array[RadialMenuItem] = []

	items.append(RadialMenuItem.new("unit_stats", "Stats", "📊"))

	# Show wounds option for Tough models
	if model.wounds_max > 1:
		var wounds_label = "Wounds %d/%d" % [model.wounds_current, model.wounds_max]
		items.append(RadialMenuItem.new("wounds", wounds_label, "❤️"))

	items.append(RadialMenuItem.new("select_unit", "Select All", "⬚"))
	items.append(RadialMenuItem.new("delete_model", "Remove", "🗑️"))

	return items


## Creates menu items for a full unit selection.
static func create_unit_menu(game_unit: GameUnit) -> Array[RadialMenuItem]:
	var items: Array[RadialMenuItem] = []

	items.append(RadialMenuItem.new("unit_stats", "Stats", "📊"))

	var activate_label = "Deactivate" if game_unit.is_activated else "Activate"
	var activate_icon = "✗" if game_unit.is_activated else "✓"
	items.append(RadialMenuItem.new("toggle_activate", activate_label, activate_icon))

	items.append(RadialMenuItem.new("check_coherency", "Coherency", "📏"))
	items.append(RadialMenuItem.new("delete_unit", "Delete", "🗑️"))

	return items


## Creates menu items for terrain.
static func create_terrain_menu() -> Array[RadialMenuItem]:
	var items: Array[RadialMenuItem] = []

	items.append(RadialMenuItem.new("delete_terrain", "Delete", "🗑️"))

	return items
