extends Control
class_name RadialMenu
## A radial/pie menu for context-sensitive actions on units and models.
## Follows UX best practices: Fitts's Law, muscle memory, gesture support.

signal action_selected(action_id: String, context: Dictionary)
signal menu_closed()

# ===== Configuration =====

## Menu radius in pixels (the approved mockup B draws a 240 px ring)
@export var menu_radius: float = 120.0

## Inner dead zone radius (cancel area)
@export var center_radius: float = 34.0

## Animation duration in seconds
@export var animation_duration: float = 0.15

# House style (maintainer D53): _draw paints with draw_* calls, which no Theme reaches, so every colour,
# font size and box of the wheel is read from HouseStyle — never a literal; a tint is a token at one of
# HouseStyle's alphas (UI inventory finding 5).
const GOLD_VERBS := ["solo_shoot", "solo_fight", "solo_cast", "solo_spot"]   # mockup B: the attack verbs in gold
const SEGMENT_GAP := 0.07          # radians trimmed from each side of a segment
const HOVER_POP := 10.0            # px the hovered segment extends outward
const LABEL_PAD := 4.0             # px kept clear between a label and the edges of its wedge
const ELLIPSIS := "…"              # U+2026 (Inter has it)
const TOOLTIP_PAD := Vector2(HouseStyle.PAD_CARD_X, HouseStyle.PAD_CARD_Y)   # px inside the tooltip box
const TOOLTIP_BAR_W := 4.0                # px width of the tooltip's left accent bar
const TOOLTIP_TEXT_W := 340.0             # px a tooltip line wraps at (Reinforce's text is 1,945 px on one line)
const TOOLTIP_GAP := 16.0                 # px between the ring's popped edge and the tooltip box
const EDGE_PADDING := 8.0                 # px kept clear between the menu and the viewport border
# D53 = b: a menu of up to RING_MAX entries stays one flat ring; a crowded one keeps its core verbs on
# the ring and moves the rest (status, management, transport lines) into a second tier — a column of
# pills beside the ring that the ring's TIER_ID wedge opens. 8 wedges still leave "Shoot" its 39 px.
const RING_MAX := 8
const RING_VERBS := ["solo_shoot", "solo_fight", "solo_cast", "solo_spot", "solo_speed_feat", "solo_pass", "toggle_activate",
	"solo_auto_charge", "solo_auto_advance", "solo_auto_rush"]
const TIER_ID := "more"                   # the wedge that opens the second tier; never sent down the action pipe


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

## Each wedge's label as drawn, laid out once per open (see _label_layout)
var _labels: Array = []

## The second tier (D53 = b): its entries, their pills (Rect2 each), whether it is shown, the hovered pill
var _tier: Array[RadialMenuItem] = []
var _pills: Array = []
var _tier_open: bool = false
var _hovered_pill: int = -1


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
	# The scene said PASS while this line said STOP: the menu blocked the board without ever
	# being exclusive. Resolved in favour of "catch clicks while the menu is open" — the SCRIPT
	# owns the filter from here on and tracks the open state, so the scene value is irrelevant.
	# STOP while open: this Control covers the FULL viewport, so it must swallow the click that
	# picked a segment — otherwise the same click also falls through to the board's picking and
	# moves/deselects a model behind the menu. IGNORE while closed (and during close()'s fade-out,
	# where the node is still visible but no longer accepting input) so the board stays clickable.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Load the project font (Inter); fall back to the engine default if missing.
	var loaded := load(HouseStyle.FONT_PATH)
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

	# The disc: a house-style window — panel fill, window rim, no glow.
	draw_circle(_center_pos, menu_radius, HouseStyle.PANEL)
	draw_arc(_center_pos, menu_radius, 0.0, TAU, 64, HouseStyle.LINE_SOFT, HouseStyle.BORDER, true)

	# Segments.
	for i in range(item_count):
		var item := _items[i]
		var seg_start := start_angle + i * angle_step + SEGMENT_GAP
		var seg_end := start_angle + (i + 1) * angle_step - SEGMENT_GAP
		var hovered := i == _hovered_index and item.enabled
		var tone := HouseStyle.TONE_DANGER if item.id.begins_with("delete") else HouseStyle.TONE_ACCENT
		var outer := menu_radius - 4.0 + (HOVER_POP if hovered else 0.0)

		var color := HouseStyle.FILL
		if hovered:
			color = Color(HouseStyle.tone_color(tone), HouseStyle.SELECTED_ALPHA)
		elif tone == HouseStyle.TONE_DANGER:
			color = Color(HouseStyle.DANGER, HouseStyle.HOVER_ALPHA)
		_draw_segment(seg_start, seg_end, center_radius, outer, color)

		# The tone's rim on the hovered segment's outer edge.
		if hovered:
			draw_arc(_center_pos, outer, seg_start, seg_end, 24, HouseStyle.tone_color(tone), 3.0, true)

		draw_multiline_string(font, _labels[i][1], _labels[i][0], HORIZONTAL_ALIGNMENT_CENTER,
			_labels[i][2], HouseStyle.FONT_BODY, -1, _ink(item))

	# Center dead-zone (a sheet well) + cancel glyph.
	draw_circle(_center_pos, center_radius, HouseStyle.SHEET_FILL)
	draw_arc(_center_pos, center_radius, 0.0, TAU, 48, HouseStyle.LINE, HouseStyle.BORDER, true)
	var cancel_text := HouseStyle.GLYPH_CLOSE
	var cs := font.get_string_size(cancel_text, HORIZONTAL_ALIGNMENT_CENTER, -1, HouseStyle.FONT_BODY)
	var cancel_col: Color = HouseStyle.tone_ink(HouseStyle.TONE_DANGER) if _hovered_index == -1 else HouseStyle.MUTED
	draw_string(font, Vector2(_center_pos.x - cs.x / 2.0, _center_pos.y + cs.y * 0.32), cancel_text, HORIZONTAL_ALIGNMENT_LEFT, -1, HouseStyle.FONT_BODY, cancel_col)

	# The second tier, once its wedge was pointed at: one house-style pill per entry, on a dark sheet
	# (a bare pill is 3 % white — unreadable over a bright table).
	if _tier_open and not _pills.is_empty():
		HouseStyle.tooltip_box().draw(get_canvas_item(), (_pills[0] as Rect2).merge(_pills[-1]).grow(HouseStyle.GAP_CONTROL))
	for k in (_tier.size() if _tier_open else 0):
		var pill: Rect2 = _pills[k]
		var tone := HouseStyle.TONE_DANGER if _tier[k].id.begins_with("delete") else HouseStyle.TONE_ACCENT
		HouseStyle.pill_box(tone, false, k == _hovered_pill and _tier[k].enabled).draw(get_canvas_item(), pill)
		var baseline := pill.get_center().y + (font.get_ascent(HouseStyle.FONT_BODY) - font.get_descent(HouseStyle.FONT_BODY)) / 2.0
		draw_string(font, Vector2(pill.position.x + HouseStyle.PAD_PILL_X, baseline), _fit(font, _tier[k].label,
			pill.size.x - HouseStyle.PAD_PILL_X * 2.0), HORIZONTAL_ALIGNMENT_LEFT, -1, HouseStyle.FONT_BODY, _ink(_tier[k]))

	# Tooltip for the hovered item.
	var tip := ""
	if _hovered_pill >= 0:
		tip = _tooltip_text(_tier[_hovered_pill], "")
	elif _hovered_index >= 0 and _hovered_index < _items.size():
		tip = _tooltip_text(_items[_hovered_index], _labels[_hovered_index][0])
	if not tip.is_empty():
		_draw_tooltip(font, tip)


## A wedge label's ink: muted when off, the lifted danger red for what ends something, gold for the
## attack verbs (mockup B), the house ink otherwise.
static func _ink(item: RadialMenuItem) -> Color:
	if not item.enabled:
		return Color(HouseStyle.MUTED, HouseStyle.DISABLED_ALPHA)
	if item.id.begins_with("delete"):
		return HouseStyle.tone_ink(HouseStyle.TONE_DANGER)
	return HouseStyle.GOLD if item.id in GOLD_VERBS else HouseStyle.INK


## Each wedge's label as drawn: [text, first baseline]. A label sits centred in the room its wedge has on
## a row; one too wide for any row drops its note ("Speed Feat (once per game)" -> "Speed Feat"), then
## breaks onto two lines, and only then is cut with an ellipsis (NML-979: long labels burst the ring) —
## the hover tooltip names it in full (_tooltip_text).
func _label_layout(font: Font) -> Array:
	var out: Array = []
	var line_h := font.get_height(HouseStyle.FONT_BODY)
	for i in _items.size():
		var a := -PI / 2.0 + i * TAU / _items.size()
		var label := _items[i].label
		var head := label.get_slice(" (", 0).get_slice(" — ", 0)
		var sp := head.find(" ", head.length() / 2 - 1)
		var two := head.substr(0, sp) + "\n" + head.substr(sp + 1) if sp > 0 else head
		var text := ""
		var spot: Array = []
		for t: String in [label, head, two]:
			var lines := t.split("\n")
			var w := 0.0
			for ln in lines:
				w = maxf(w, _text_w(font, ln))
			spot = _row_room(a, line_h * lines.size() / 2.0, w + LABEL_PAD * 2.0)
			if spot[0] >= w + LABEL_PAD * 2.0:
				text = t
				break
		if text.is_empty():
			spot = _row_room(a, line_h / 2.0, INF)
			text = _fit(font, label, spot[0] - LABEL_PAD * 2.0)
		var size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, HouseStyle.FONT_BODY)
		out.append([text, _center_pos + spot[2] + Vector2(spot[1] - size.x / 2.0, font.get_ascent(HouseStyle.FONT_BODY) - size.y / 2.0),
			maxf(size.x, 1.0)])
	return out


## The widest room a text box `fh` px half-high finds on a row of the wedge at angle `a`: [room, the
## room's middle x, the row]. The middle row first; rows further out or in only while it needs more.
func _row_room(a: float, fh: float, need: float) -> Array:
	var half := PI / _items.size()
	var mid := (menu_radius - 4.0 + center_radius) / 2.0
	var best: Array = [-1.0, 0.0, Vector2.ZERO]
	for r: float in [mid, mid + 12.0, mid - 12.0, mid + 22.0]:
		var row := Vector2(cos(a), sin(a)) * r
		var lo := 0.0
		while lo > -menu_radius and _in_wedge(row + Vector2(lo - 2.0, 0.0), a, half, fh):
			lo -= 2.0
		var hi := 0.0
		while hi < menu_radius and _in_wedge(row + Vector2(hi + 2.0, 0.0), a, half, fh):
			hi += 2.0
		if hi - lo > best[0]:
			best = [hi - lo, (lo + hi) / 2.0, row]
		if best[0] >= need:
			break
	return best


## The second tier's pills: one row per entry, a column beside the ring — left of it, right when the
## left has no room — centred on the ring and kept on screen. Wider labels are cut to TOOLTIP_TEXT_W.
func _pill_layout(font: Font) -> Array:
	var w := 0.0
	for it in _tier:
		w = maxf(w, _text_w(font, it.label))
	w = minf(w, TOOLTIP_TEXT_W) + HouseStyle.PAD_PILL_X * 2.0
	var row := HouseStyle.H_CHIP + HouseStyle.GAP_CONTROL
	var x := _center_pos.x - menu_radius - HouseStyle.GAP_SECTION - w
	if x < EDGE_PADDING:
		x = _center_pos.x + menu_radius + HouseStyle.GAP_SECTION
	var h := _tier.size() * row
	var y := clampf(_center_pos.y - h / 2.0, EDGE_PADDING, maxf(EDGE_PADDING, get_viewport_rect().size.y - h - EDGE_PADDING))
	var out: Array = []
	for k in _tier.size():
		out.append(Rect2(x, y + k * row, w, HouseStyle.H_CHIP))
	return out


## The text row through `v` (relative to the centre), `fh` px above and below, lies on the ring and
## within `half` radians of the wedge angle `a` — its top and bottom edge alike.
func _in_wedge(v: Vector2, a: float, half: float, fh: float) -> bool:
	for p: Vector2 in [v + Vector2(0.0, fh), v - Vector2(0.0, fh)]:
		if p.length() < center_radius or p.length() > menu_radius - 4.0 or absf(angle_difference(a, p.angle())) > half:
			return false
	return true


## `text` fitted to `room` px: a note in brackets or after a dash goes first ("Speed Feat (once per
## game)" -> "Speed Feat"), then letters, with an ellipsis; "" when not even one letter fits.
static func _fit(font: Font, text: String, room: float) -> String:
	var head := text if _text_w(font, text) <= room else text.get_slice(" (", 0).get_slice(" — ", 0)
	var cut := head
	while not cut.is_empty() and _text_w(font, cut if cut == head else cut + ELLIPSIS) > room:
		cut = cut.left(-1).strip_edges()
	return cut if cut == head or cut.is_empty() else cut + ELLIPSIS


static func _text_w(font: Font, text: String) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, HouseStyle.FONT_BODY).x


## The hover text: the tooltip, headed by the full label when the wedge shows it cut (`shown`).
static func _tooltip_text(item: RadialMenuItem, shown: String) -> String:
	return item.tooltip if shown == item.label or item.tooltip == item.label else "%s\n%s" % [item.label, item.tooltip]


## Size of the tooltip box for `tip`. Shared by the drawing below and by the viewport clamp
## in _clamp_to_viewport, so the two can never disagree about how much room a tooltip needs.
func _tooltip_box_size(font: Font, tip: String) -> Vector2:
	var ts := font.get_multiline_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, TOOLTIP_TEXT_W, HouseStyle.FONT_BODY)
	return Vector2(ts.x + TOOLTIP_PAD.x * 2.0 + TOOLTIP_BAR_W + 4.0, ts.y + TOOLTIP_PAD.y * 2.0)


func _draw_tooltip(font: Font, tip: String) -> void:
	var box_size := _tooltip_box_size(font, tip)
	var box_pos := _center_pos + Vector2(-box_size.x / 2.0, menu_radius + HOVER_POP + TOOLTIP_GAP)
	# The box is centred under the ring but can be far WIDER than the ring (measured: 374-618 px
	# against a 230 px ring). Reserving that width in _clamp_to_viewport would shove the whole
	# menu up to ~310 px away from the click for every model in the outer third of the screen —
	# on the game's most frequent interaction. So only the ring drives the menu's position and
	# the tooltip slides along the bottom edge on its own: the ring stays under the cursor and
	# the text stays readable. maxf keeps clampf legal if the box is wider than the viewport.
	var view_w := get_viewport_rect().size.x
	box_pos.x = clampf(box_pos.x, EDGE_PADDING, maxf(EDGE_PADDING, view_w - box_size.x - EDGE_PADDING))

	HouseStyle.tooltip_box().draw(get_canvas_item(), Rect2(box_pos, box_size))

	# Accent bar.
	draw_rect(Rect2(box_pos + Vector2(TOOLTIP_PAD.x * 0.4, TOOLTIP_PAD.y), Vector2(TOOLTIP_BAR_W, box_size.y - TOOLTIP_PAD.y * 2.0)), HouseStyle.ACCENT)

	# Text, wrapped at TOOLTIP_TEXT_W.
	var text_pos := box_pos + Vector2(TOOLTIP_PAD.x + TOOLTIP_BAR_W + 4.0, TOOLTIP_PAD.y + font.get_ascent(HouseStyle.FONT_BODY))
	draw_multiline_string(font, text_pos, tip, HORIZONTAL_ALIGNMENT_LEFT, TOOLTIP_TEXT_W, HouseStyle.FONT_BODY, -1, HouseStyle.INK)


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
	# The second tier's pills first: they stand inside the ring's generous outer hit zone.
	_hovered_pill = -1
	for k in (_pills.size() if _tier_open else 0):
		if (_pills[k] as Rect2).has_point(mouse_pos):
			_hovered_pill = k
			_hovered_index = -1
			return

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
	# Pointing at the tier's wedge opens the tier; it then stays while the menu is open.
	_tier_open = _tier_open or _items[_hovered_index].id == TIER_ID


func _select_current() -> void:
	if _hovered_pill >= 0:
		if _tier[_hovered_pill].enabled:
			action_selected.emit(_tier[_hovered_pill].id, _context)
			close()
		return

	if _hovered_index < 0:
		# Center = cancel
		close()
		return

	if _items[_hovered_index].id == TIER_ID:
		_tier_open = true   # the tier's wedge opens the tier, it is no action
		queue_redraw()
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


## Nudges the menu centre so everything the player has to HIT — the ring, its popped segment and
## the height of the tooltip below the ring — stays inside the viewport. Opened next to a screen
## border the menu was previously drawn half off-image, and this is the most frequent interaction
## of the game (click a unit -> radial menu), so the edge case is not an edge case at all.
## The tooltip's WIDTH is deliberately not reserved here — it clamps itself in _draw_tooltip, so
## the ring keeps landing where the player clicked instead of jumping a tooltip-width inward.
##
## Why this cannot corrupt the hit zones: _update_hover() measures the cursor RELATIVE to
## _center_pos, exactly as _draw() places the segments. Shifting the centre therefore moves
## the drawn segments AND their hit zones by the same vector — the segment under the cursor
## stays the segment drawn there. Any future hit test must keep measuring from _center_pos
## (never from the raw position handed to open()) or that guarantee breaks.
func _clamp_to_viewport(pos: Vector2) -> Vector2:
	var view_size := get_viewport_rect().size
	var font: Font = _font if _font else ThemeDB.fallback_font

	# The tooltip sits UNDER the ring and which one is shown depends on the hovered item, which
	# is still unknown while opening — so reserve the height of the tallest one this menu can
	# show. Only the height: the width is the tooltip's own problem (see _draw_tooltip).
	var tip_h := 0.0
	for item in _items + _tier:
		if item.tooltip.is_empty():
			continue
		tip_h = maxf(tip_h, _tooltip_box_size(font, _tooltip_text(item, "")).y)

	var ring := menu_radius + HOVER_POP
	var pad_x := ring + EDGE_PADDING
	var pad_top := ring + EDGE_PADDING
	var pad_bottom := ring + EDGE_PADDING
	if tip_h > 0.0:
		pad_bottom = menu_radius + HOVER_POP + TOOLTIP_GAP + tip_h + EDGE_PADDING

	# On a viewport too small for the reserved box the lower and upper bound would cross;
	# maxf keeps clampf legal and parks the menu at the top/left edge instead of erroring.
	var out := pos
	out.x = clampf(out.x, pad_x, maxf(pad_x, view_size.x - pad_x))
	out.y = clampf(out.y, pad_top, maxf(pad_top, view_size.y - pad_bottom))
	return out


# ===== Public API =====

## Opens the menu at the specified position with the given items.
func open(screen_pos: Vector2, items: Array[RadialMenuItem], context: Dictionary = {}) -> void:
	# D53 = b: a crowded menu keeps its verbs on the ring, the rest goes to the second tier. RING_VERBS
	# grew past what the worst-case crowded menu (every verb-granting rule at once) leaves room for —
	# its OWN declared order is the priority: the ring fills up to RING_MAX-1 verb slots (plus "More"),
	# so an established verb is never bumped off the ring by a newer one further down the list.
	_tier.clear()
	if items.size() > RING_MAX:
		var by_id := {}
		for it in items:
			by_id[it.id] = it
		var ring: Array[RadialMenuItem] = []
		var kept := {}
		for verb_id in RING_VERBS:
			if ring.size() >= RING_MAX - 1:
				break
			if by_id.has(verb_id):
				ring.append(by_id[verb_id])
				kept[verb_id] = true
		for it in items:
			if not kept.has(it.id):
				_tier.append(it)
		var names := PackedStringArray()
		for it in _tier:
			names.append(it.label)
		ring.append(RadialMenuItem.new(TIER_ID, "More", "", true, ", ".join(names)))
		items = ring
	_items = items
	_context = context
	# Clamp before ANYTHING reads the centre — _draw(), _update_hover() and pivot_offset below
	# all measure from _center_pos, which is exactly why the shift is safe (see _clamp_to_viewport).
	# _items must already be assigned: the clamp measures this menu's widest tooltip.
	_center_pos = _clamp_to_viewport(screen_pos)
	_labels = _label_layout(_font if _font else ThemeDB.fallback_font)
	_pills = _pill_layout(_font if _font else ThemeDB.fallback_font)
	_tier_open = false
	_hovered_pill = -1
	_hovered_index = -1
	_is_open = true
	# Swallow board clicks for as long as the menu stands (see the filter note in _ready).
	mouse_filter = Control.MOUSE_FILTER_STOP

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
	# Hand the board back immediately: the node stays VISIBLE for the fade-out below, and a
	# full-rect STOP control would eat the player's next click for the length of the animation.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

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
static func solo_combat_items(game_unit: GameUnit = null, auto_ok: bool = false) -> Array[RadialMenuItem]:
	var out: Array[RadialMenuItem] = []
	out.append(RadialMenuItem.new("solo_shoot", "Shoot", "»", true, "Shoot at an AI unit — pick a target with line of sight"))
	out.append(RadialMenuItem.new("solo_fight", "Fight", "⚔", true, "Strike an AI unit in melee contact"))
	# Automodus (A1, NML-202): the engine moves the unit along a legal corridor and rolls the
	# attack itself — rulebook verbs, no "Auto-" jargon in the wheel (the "Auto:" log prefix marks
	# an engine-executed activation instead).
	if auto_ok:
		out.append(RadialMenuItem.new("solo_auto_charge", "Charge", "⚡", true,
			"Charge: the engine moves the unit along a legal path into base contact and fights — pick the enemy"))
		# The " (& Shoot)" note follows the label's own drop-the-parenthetical convention (see
		# "Speed Feat (once per game)"): a crowded wedge shows "Advance", the tooltip always says
		# "Advance & Shoot" in full.
		out.append(RadialMenuItem.new("solo_auto_advance", "Advance (& Shoot)", "»→", true,
			"Advance & Shoot: the engine advances toward the enemy (or steps back into range if already close) and fires — pick the enemy"))
		out.append(RadialMenuItem.new("solo_auto_rush", "Rush", "→→", true,
			"Rush: the engine moves the unit its full Rush distance toward the enemy — pick the enemy"))
	# Spell wave F2: a unit that fields a caster (itself or a joined hero) with tokens can cast —
	# spell picker -> target -> boost -> automatic resolution.
	if game_unit != null and _caster_member_of(game_unit) != null:
		out.append(RadialMenuItem.new("solo_cast", "Cast", "✦", true, "Cast a spell — pick it, pick a target, boost, auto-resolved"))
	# Spotter UX (maintainer 31.07.): Precision Spotter is a radial action — the player picks
	# the target (book 3.5.3: "pick one enemy unit within 30\" and in line of sight"), 4+ marks it.
	if game_unit != null and _spotter_member_of(game_unit) != null:
		out.append(RadialMenuItem.new("solo_spot", "Spot", "◎", true,
			"Precision Spotter: pick an enemy within 30\" line of sight — on 4+ a marker lands; attackers may remove markers for +1 to hit each"))
	# D22 (NML-984): the once-per-game Speed Feat is the player's to spend — one click, this activation.
	if game_unit != null and not SoloController.unspent_speed_feats(game_unit).is_empty():
		out.append(RadialMenuItem.new("solo_speed_feat", "Speed Feat (once per game)", "SF", true,
			"Speed Feat: spend the once-per-game move bonus for this activation — Advance and Rush/Charge grow at once. Cannot be undone."))
	# Delayed Action (wave 5) — the "Pass Turn" primitive. Offered on every carrier, NEVER hidden when
	# the condition happens to fail: an entry that vanishes reads like a missing rule, so an illegal
	# pass is refused in the battle log with the measured counts instead (#224 transparency doctrine).
	if game_unit != null and SoloController.delayed_action_member_of(game_unit) != null:
		out.append(RadialMenuItem.new("solo_pass", "Pass", "⏸", true,
			"Delayed Action: pass this turn instead of activating — legal once per round while your opponent has more units left to activate than you; the unit may still be activated later"))
	return out


## The member (unit itself or a joined hero) bearing Precision Spotter, or null.
static func _spotter_member_of(game_unit: GameUnit) -> GameUnit:
	var members: Array = [game_unit]
	if game_unit.has_method("get_attached_heroes"):
		members = members + game_unit.get_attached_heroes()
	for m in members:
		var mu := m as GameUnit
		if mu == null or mu.get_alive_count() <= 0:
			continue
		if mu.has_special_rule("Precision Spotter") \
				or not RulesRegistry.unit_rules_of_primitive(mu, "Precision Spotter").is_empty():
			return mu
	return null


## The unit member (unit itself or a joined hero) that can pay for a cast right now, or null.
static func _caster_member_of(game_unit: GameUnit) -> GameUnit:
	var members: Array = [game_unit]
	if game_unit.has_method("get_attached_heroes"):
		members = members + game_unit.get_attached_heroes()
	for m in members:
		var mu := m as GameUnit
		# No casts_current gate (maintainer 2026-07-22): with 0 tokens the entry must still be
		# DISCOVERABLE — the spell picker then shows every spell disabled with the token count.
		if mu != null and mu.is_caster() and mu.get_alive_count() > 0:
			return mu
	return null


## The owner's Reinforcement entry (army-book v3.5.3). Offered on every carrier and NEVER hidden when
## the rule cannot fire right now — an entry that vanishes reads exactly like a missing rule, so an
## impossible sacrifice is refused with its reason in the battle log instead (#224). Not gated on solo:
## the rule belongs to the army book, not to NACHTMAHR.
static func reinforcement_items(game_unit: GameUnit) -> Array[RadialMenuItem]:
	var out: Array[RadialMenuItem] = []
	if game_unit != null and SoloController.reinforcement_offered(game_unit):
		out.append(RadialMenuItem.new("reinforce", "Reinforce", "⟲", true,
			"Reinforcement: while this unit IS Shaken — or once it is fully destroyed — remove it from the table as destroyed; a fresh copy of it returns within 12\" of any table edge at the start of the next round, after the Ambushers. The copy cannot seize objectives that round and does not have the rule."))
	return out


static func create_unit_menu(game_unit: GameUnit, solo_combat: bool = false, auto_ok: bool = false) -> Array[RadialMenuItem]:
	var items: Array[RadialMenuItem] = []

	if solo_combat:
		items.append_array(solo_combat_items(game_unit, auto_ok))
	items.append_array(reinforcement_items(game_unit))

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
	# Transport(X) items (Embark/Unload) are APPENDED by the controller for unit AND model menus
	# alike (_append_transport_items) — a transport is usually a single-model unit and would never
	# see additions made only here.
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


## The only menu an EMBARKED model offers (NML-105, the dead-model mirror): disembark its unit.
static func create_embarked_model_menu(transport_name: String) -> Array[RadialMenuItem]:
	var items: Array[RadialMenuItem] = []
	items.append(RadialMenuItem.new("disembark", "Disembark", "▢", true,
		"Leave %s (GF v3.5.1 Transport: the unit is placed fully within 6\")" % transport_name))
	# #338: staying inside is a legal choice — it spends the activation so the round can close.
	items.append(RadialMenuItem.new("stay_embarked", "Stay aboard", "▣", true,
		"Spend the activation inside %s — the unit stays embarked this round" % transport_name))
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

	# Cycle frontage (mirrors B) — convenient from the menu.
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
