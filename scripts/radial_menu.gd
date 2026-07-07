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
@export var center_radius: float = 34.0

## Animation duration in seconds
@export var animation_duration: float = 0.15

## Colors — Tactical HUD tokens
@export var background_color: Color = Color(HudTokens.SURFACE.r, HudTokens.SURFACE.g, HudTokens.SURFACE.b, 0.9)
@export var segment_color: Color = Color(1.0, 1.0, 1.0, 0.06)
@export var segment_hover_color: Color = Color(HudTokens.CYAN.r, HudTokens.CYAN.g, HudTokens.CYAN.b, 0.28)
@export var text_color: Color = HudTokens.TEXT
@export var disabled_color: Color = Color(1.0, 1.0, 1.0, 0.25)

const ACCENT_COLOR := HudTokens.CYAN
const DESTRUCTIVE_COLOR := HudTokens.DANGER
const INTER_FONT_PATH := "res://assets/ui_glassmorphism/fonts/Inter.ttf"
const SEGMENT_GAP := 0.07          # radians trimmed from each side of a segment
const HOVER_POP := 10.0            # px the hovered segment extends outward
const LABEL_FONT_SIZE := 14
const TOOLTIP_FONT_SIZE := 14


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

## Label font (project Inter; falls back to the engine default if missing)
var _font: Font = null


# ===== Menu Item Class =====

class RadialMenuItem:
	var id: String = ""
	var label: String = ""
	var icon: String = ""
	var enabled: bool = true
	var tooltip: String = ""

	func _init(p_id: String, p_label: String, p_icon: String = "", p_enabled: bool = true, p_tooltip: String = ""):
		id = p_id
		label = p_label
		icon = p_icon
		enabled = p_enabled
		tooltip = p_tooltip if not p_tooltip.is_empty() else p_label


# ===== Lifecycle =====

func _ready() -> void:
	# Start hidden
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Load the project font (Inter); fall back to the engine default if missing.
	var loaded := load(INTER_FONT_PATH)
	_font = loaded if loaded is Font else ThemeDB.fallback_font

	# Set up for drawing
	set_process_input(true)


func _draw() -> void:
	if not _is_open or _items.is_empty():
		return

	var item_count := _items.size()
	var angle_step := TAU / item_count
	var start_angle := -PI / 2 - angle_step / 2  # Start from top
	var font: Font = _font if _font else ThemeDB.fallback_font

	# Soft cyan glow halo (concentric fading rings — _draw has no blur).
	for g in range(3):
		var halo_r := menu_radius + 3.0 + g * 5.0
		var halo_a := 0.12 - g * 0.035
		draw_arc(_center_pos, halo_r, 0.0, TAU, 64, Color(ACCENT_COLOR.r, ACCENT_COLOR.g, ACCENT_COLOR.b, halo_a), 4.0, true)

	# Dark glass disk + cyan rim.
	draw_circle(_center_pos, menu_radius, background_color)
	draw_arc(_center_pos, menu_radius, 0.0, TAU, 64, Color(ACCENT_COLOR.r, ACCENT_COLOR.g, ACCENT_COLOR.b, 0.55), 2.0, true)

	# Segments.
	for i in range(item_count):
		var item := _items[i]
		var seg_start := start_angle + i * angle_step + SEGMENT_GAP
		var seg_end := start_angle + (i + 1) * angle_step - SEGMENT_GAP
		var hovered := i == _hovered_index
		var destructive := item.id.begins_with("delete")
		var outer := menu_radius - 4.0 + (HOVER_POP if hovered else 0.0)

		var color := segment_color
		if not item.enabled:
			color = disabled_color
		elif hovered:
			color = segment_hover_color
		elif destructive:
			color = Color(DESTRUCTIVE_COLOR.r, DESTRUCTIVE_COLOR.g, DESTRUCTIVE_COLOR.b, 0.12)
		_draw_segment(seg_start, seg_end, center_radius, outer, color)

		# Bright accent arc on the hovered segment's outer edge.
		if hovered:
			var arc_color := DESTRUCTIVE_COLOR if destructive else ACCENT_COLOR
			draw_arc(_center_pos, outer, seg_start, seg_end, 24, arc_color, 3.0, true)

		# Label (full word, Inter).
		var label_angle := (seg_start + seg_end) / 2.0
		var label_radius := (outer + center_radius) / 2.0
		var label_pos := _center_pos + Vector2(cos(label_angle), sin(label_angle)) * label_radius
		var label_col := text_color
		if not item.enabled:
			label_col = disabled_color
		elif destructive:
			label_col = DESTRUCTIVE_COLOR
		elif hovered:
			label_col = HudTokens.TEXT
		var ls := font.get_string_size(item.label, HORIZONTAL_ALIGNMENT_CENTER, -1, LABEL_FONT_SIZE)
		var label_draw := Vector2(label_pos.x - ls.x / 2.0, label_pos.y + ls.y * 0.32)
		draw_string(font, label_draw, item.label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, label_col)

	# Center dead-zone (glass) + cancel glyph.
	draw_circle(_center_pos, center_radius, Color(HudTokens.SURFACE.r, HudTokens.SURFACE.g, HudTokens.SURFACE.b, 0.95))
	draw_arc(_center_pos, center_radius, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.16), 1.0, true)
	var cancel_text := "✕"
	var cs := font.get_string_size(cancel_text, HORIZONTAL_ALIGNMENT_CENTER, -1, LABEL_FONT_SIZE)
	var cancel_col: Color = DESTRUCTIVE_COLOR if _hovered_index == -1 else HudTokens.TEXT_MUTED
	draw_string(font, Vector2(_center_pos.x - cs.x / 2.0, _center_pos.y + cs.y * 0.32), cancel_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, cancel_col)

	# Tooltip for the hovered item.
	if _hovered_index >= 0 and _hovered_index < _items.size():
		var hovered_item := _items[_hovered_index]
		if not hovered_item.tooltip.is_empty():
			_draw_tooltip(font, hovered_item.tooltip)


func _draw_tooltip(font: Font, tip: String) -> void:
	var ts := font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, TOOLTIP_FONT_SIZE)
	var pad := Vector2(12.0, 7.0)
	var bar_w := 4.0
	var box_size := Vector2(ts.x + pad.x * 2.0 + bar_w + 4.0, ts.y + pad.y * 2.0)
	var box_pos := _center_pos + Vector2(-box_size.x / 2.0, menu_radius + HOVER_POP + 16.0)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(HudTokens.SURFACE.r, HudTokens.SURFACE.g, HudTokens.SURFACE.b, 0.96)
	sb.set_corner_radius_all(HudTokens.RADIUS)
	sb.border_color = HudTokens.HAIRLINE
	sb.set_border_width_all(1)
	sb.draw(get_canvas_item(), Rect2(box_pos, box_size))

	# Accent bar.
	draw_rect(Rect2(box_pos + Vector2(pad.x * 0.4, pad.y), Vector2(bar_w, box_size.y - pad.y * 2.0)), ACCENT_COLOR)

	# Text.
	var text_pos := box_pos + Vector2(pad.x + bar_w + 4.0, box_size.y / 2.0 + ts.y * 0.32)
	draw_string(font, text_pos, tip, HORIZONTAL_ALIGNMENT_LEFT, -1, TOOLTIP_FONT_SIZE, text_color)


func _draw_segment(angle_start: float, angle_end: float, r_inner: float, r_outer: float, color: Color) -> void:
	var points: PackedVector2Array = []

	var segments := 20
	for i in range(segments + 1):
		var t := float(i) / segments
		var angle := lerpf(angle_start, angle_end, t)
		points.append(_center_pos + Vector2(cos(angle), sin(angle)) * r_inner)

	for i in range(segments, -1, -1):
		var t := float(i) / segments
		var angle := lerpf(angle_start, angle_end, t)
		points.append(_center_pos + Vector2(cos(angle), sin(angle)) * r_outer)

	if points.size() >= 3:
		draw_colored_polygon(points, color)


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
		# Note: Right-click no longer closes the menu (it's used to open it)
		# Click on center zone or press ESC to close

	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			# Close menu and let the arrangement system handle these keys
			# Don't consume the event so it propagates to arrangement handlers
			close()


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
func open(screen_pos: Vector2, items: Array[RadialMenuItem], context: Dictionary = {}) -> void:
	_items = items
	_context = context
	_center_pos = screen_pos
	_hovered_index = -1
	_is_open = true

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

	# Show wounds option for Tough models
	if model.wounds_max > 1:
		var wounds_label = "W %d/%d" % [model.wounds_current, model.wounds_max]
		items.append(RadialMenuItem.new("wounds", wounds_label, "", true, "Adjust wounds for this model (Tough)"))

	# Show casts option for Caster units
	if model.unit and model.unit is GameUnit:
		var game_unit = model.unit as GameUnit
		if game_unit.is_caster():
			var casts_label = "C %d/%d" % [game_unit.casts_current, GameUnit.CASTER_POINTS_CAP]
			items.append(RadialMenuItem.new("casts", casts_label, "", true, "Adjust caster points for this unit"))

	# Status tokens (unit-wide)
	if model.unit and model.unit is GameUnit:
		var game_unit = model.unit as GameUnit

		# Activation toggle
		var activate_icon = "A+" if game_unit.is_activated else "A"
		var activate_tooltip = "Mark unit as not activated" if game_unit.is_activated else "Mark unit as activated this round"
		items.append(RadialMenuItem.new("toggle_activate", "Activate", activate_icon, true, activate_tooltip))

		var fatigue_icon = "F+" if game_unit.is_fatigued else "F"
		var shaken_icon = "S+" if game_unit.is_shaken else "S"
		var fatigue_tooltip = "Remove Fatigued status from unit" if game_unit.is_fatigued else "Mark unit as Fatigued"
		var shaken_tooltip = "Remove Shaken status from unit" if game_unit.is_shaken else "Mark unit as Shaken"
		items.append(RadialMenuItem.new("toggle_fatigued", "Fatigued", fatigue_icon, true, fatigue_tooltip))
		items.append(RadialMenuItem.new("toggle_shaken", "Shaken", shaken_icon, true, shaken_tooltip))

	items.append(RadialMenuItem.new("add_marker", "Token", "T", true, "Add/adjust status & counter tokens for special rules"))
	items.append(RadialMenuItem.new("select_unit", "Select All", "A", true, "Select all models in this unit"))
	# NOTE: no "Revive" here by design — a dead loose model is revived by RIGHT-CLICKING it on the
	# army tray (see create_dead_model_menu), not from a living model's menu.
	items.append(RadialMenuItem.new("delete_model", "Remove", "X", true, "Remove this model from the table"))

	return items


## Creates menu items for a full unit selection.
## Solo (goal 001 P8): declare an attack on the AI — enters targeting mode (line of sight shown), then
## the whole exchange resolves with real tray dice, mirroring the AI's own combat flow.
static func solo_combat_items() -> Array[RadialMenuItem]:
	var out: Array[RadialMenuItem] = []
	out.append(RadialMenuItem.new("solo_shoot", "Shoot", "»", true, "Shoot at an AI unit — pick a target with line of sight"))
	out.append(RadialMenuItem.new("solo_fight", "Fight", "⚔", true, "Strike an AI unit in melee contact"))
	return out


static func create_unit_menu(game_unit: GameUnit, solo_combat: bool = false) -> Array[RadialMenuItem]:
	var items: Array[RadialMenuItem] = []

	if solo_combat:
		items.append_array(solo_combat_items())

	var activate_icon = "-" if game_unit.is_activated else "+"
	var activate_tooltip = "Mark unit as not activated" if game_unit.is_activated else "Mark unit as activated this round"
	items.append(RadialMenuItem.new("toggle_activate", "Activate", activate_icon, true, activate_tooltip))

	# Show casts option for Caster units
	if game_unit.is_caster():
		var casts_label = "C %d/%d" % [game_unit.casts_current, GameUnit.CASTER_POINTS_CAP]
		items.append(RadialMenuItem.new("casts", casts_label, "", true, "Adjust caster points for this unit"))

	# Status tokens (unit-wide)
	var fatigue_icon = "F+" if game_unit.is_fatigued else "F"
	var shaken_icon = "S+" if game_unit.is_shaken else "S"
	var fatigue_tooltip = "Remove Fatigued status from unit" if game_unit.is_fatigued else "Mark unit as Fatigued"
	var shaken_tooltip = "Remove Shaken status from unit" if game_unit.is_shaken else "Mark unit as Shaken"
	items.append(RadialMenuItem.new("toggle_fatigued", "Fatigued", fatigue_icon, true, fatigue_tooltip))
	items.append(RadialMenuItem.new("toggle_shaken", "Shaken", shaken_icon, true, shaken_tooltip))

	items.append(RadialMenuItem.new("add_marker", "Token", "T", true, "Add/adjust status & counter tokens for special rules"))
	# NOTE: no "Revive" here by design — dead loose models are revived by RIGHT-CLICKING them on
	# the army tray (see create_dead_model_menu).
	items.append(RadialMenuItem.new("delete_unit", "Delete", "X", true, "Remove entire unit from the table"))

	return items


## The only menu a DEAD loose model offers: revive. Whole-unit-destroyed revives the whole unit,
## otherwise just this model (decided by the controller from context). No other action is allowed.
static func create_dead_model_menu(unit_dead_count: int = 1, selection_dead_count: int = 0) -> Array[RadialMenuItem]:
	var items: Array[RadialMenuItem] = []
	items.append(RadialMenuItem.new("revive_dead", "Revive", "R", true, "Bring this model back onto the table"))
	# Multi-revive (G3): revive the whole unit's dead, or every dead model in the current selection.
	if unit_dead_count > 1:
		items.append(RadialMenuItem.new("revive_unit_dead", "Revive unit dead (%d)" % unit_dead_count, "U", true, "Revive all of this unit's dead models"))
	if selection_dead_count > 1:
		items.append(RadialMenuItem.new("revive_selected", "Revive selected (%d)" % selection_dead_count, "S", true, "Revive all selected dead models"))
	return items


## Creates menu items for an Age of Fantasy: Regiments movement-tray block. Replaces
## the per-model wounds/delete items with a pooled-wound counter (AoF:R v3.5.1 p.9
## "Remove Casualties" — models are removed from the back rank). `remaining`/`pool_max`
## drive the counter label; clicking "W" opens the same wounds dialog as for a single
## Tough(X) model, adjusting the pool. Individual model wounding/deletion is disabled
## by design. Only for Tough(1) regiments; Tough(X>1) uses the classic model menu.
static func create_regiment_menu(game_unit: GameUnit, remaining: int, pool_max: int) -> Array[RadialMenuItem]:
	var items: Array[RadialMenuItem] = []

	# Pooled-wound counter: opens the standard wounds dialog (same as for a Tough(X)
	# model) with a proxy model whose wounds_max = pool_max. +/- in the dialog adjusts
	# the pool, removing/reviving models from the back rank.
	var wounds_label = "W %d/%d" % [remaining, pool_max]
	var can_adjust: bool = pool_max > 0
	items.append(RadialMenuItem.new("regiment_wounds", wounds_label, "W", can_adjust, "Open the wounds dialog (AoF:R p.9 pooled-tough counter)"))

	# Cycle frontage (mirrors Shift+F) — convenient from the menu.
	items.append(RadialMenuItem.new("regiment_frontage", "Frontage", "⊧", true, "Cycle models-per-rank (5 → 4 → 3 → 2 → 1)"))

	var activate_icon = "-" if game_unit.is_activated else "+"
	var activate_tooltip = "Mark unit as not activated" if game_unit.is_activated else "Mark unit as activated this round"
	items.append(RadialMenuItem.new("toggle_activate", "Activate", activate_icon, true, activate_tooltip))

	if game_unit.is_caster():
		var casts_label = "C %d/%d" % [game_unit.casts_current, GameUnit.CASTER_POINTS_CAP]
		items.append(RadialMenuItem.new("casts", casts_label, "", true, "Adjust caster points for this unit"))

	var fatigue_icon = "F+" if game_unit.is_fatigued else "F"
	var shaken_icon = "S+" if game_unit.is_shaken else "S"
	items.append(RadialMenuItem.new("toggle_fatigued", "Fatigued", fatigue_icon, true, "Mark/Remove Fatigued"))
	items.append(RadialMenuItem.new("toggle_shaken", "Shaken", shaken_icon, true, "Mark/Remove Shaken"))
	items.append(RadialMenuItem.new("add_marker", "Token", "T", true, "Add/adjust status & counter tokens"))
	# Revive back-rank casualties (reset the pooled-wound counter to full).
	if remaining < pool_max:
		items.append(RadialMenuItem.new("revive_fallen", "Revive", "R", true, "Return this regiment's back-rank casualties"))
	items.append(RadialMenuItem.new("delete_unit", "Delete", "X", true, "Remove entire unit from the table"))

	return items


## Menu for right-clicking an army tray: return this player's fully-destroyed units (each has no
## clickable model of its own). `units` = [{"id": String, "name": String}]; empty → a disabled note.
static func create_army_tray_menu(units: Array) -> Array[RadialMenuItem]:
	var items: Array[RadialMenuItem] = []
	if units.is_empty():
		items.append(RadialMenuItem.new("noop", "No destroyed units", "", false, "No wiped units to return"))
		return items
	for u in units:
		var uname := str(u.get("name", "Unit"))
		items.append(RadialMenuItem.new("return_unit_%s" % str(u.get("id", "")), uname, "R", true, "Return %s to the table" % uname))
	return items


## Creates menu items for terrain.
static func create_terrain_menu() -> Array[RadialMenuItem]:
	var items: Array[RadialMenuItem] = []

	items.append(RadialMenuItem.new("delete_terrain", "Delete", "X", true, "Remove terrain piece from the table"))

	return items
