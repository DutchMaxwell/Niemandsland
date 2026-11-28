class_name LoadingOverlay
extends CanvasLayer
## Reusable full-screen loading overlay: a near-black cover, a centred eyebrow label and a
## thin accent bar whose fill EASES continuously toward its target (exponential smoothing,
## never stepping/jumping). Used for the menu build, the scene transitions (menu -> game,
## table chooser -> game) and in-game army model caching, so they all read the same and
## always communicate "something is happening".
##
## As a CanvasLayer it draws above everything and, when added directly to the SceneTree
## root, survives a change_scene_to_file — so a transition can keep the black + bar up
## across the scene swap with no grey flash.

# === Constants ===

const TRACK_W := 360.0
const BAR_H := 3.0
## How fast the visible fill eases toward the target (higher = snappier, lower = slower
## and more "flowing"). Tuned so the fill glides smoothly without ever stepping.
const SMOOTH_RATE := 2.6
## Indeterminate mode (no real progress known, e.g. a scene transition): the target
## creeps up to CREEP_TARGET so the bar keeps flowing, then complete() finishes it.
const CREEP_TARGET := 0.9
const CREEP_RATE := 0.18  # ratio per second
const FADE_S := 0.4
const FULL_TRACK_W := 760.0   # full mode (sheet 06): a wider, thicker bar under the title block
const FULL_BAR_H := 5.0
const FULL_BOTTOM := 280      # full mode: the bar stands at y = 800 of 1080, as on the sheet
const FULL_SUBTITLE_PX := 20
const FULL_RULE_W := 250      # the signature rule under the small wordmark
const LEGAL_ABOVE_BOTTOM := 50
const TIP_W := 760
const TIP_MIN_HEIGHT := 800.0   # the tip card stays away from windows lower than this
## The tips of the named loading picture (one at random); a text-only change adds more.
const TIPS: Array[String] = ["The ? Controls button in the top bar lists every key and mouse action."]
const TIP_BULB_SVG := "<svg xmlns='http://www.w3.org/2000/svg' width='48' height='48' viewBox='0 0 24 24' fill='none' stroke='#fff' stroke-width='1.75' stroke-linecap='round' stroke-linejoin='round'><path d='M9 18h6M10 21h4M12 3a6 6 0 0 0-3.5 10.9c.6.5 1 1.3 1 2.1h5c0-.8.4-1.6 1-2.1A6 6 0 0 0 12 3z'/></svg>"
const BACKDROP_LIGHT := 0.62   # full mode: the table's picture behind the text, at 62 % brightness (sheet 06)

# === Stage marks (full mode, sheet 06) ===

## One mark of the row under the subtitle: a ring (pending), a gold ring with a faint halo (now) or a filled accent
## disc with a tick (done).
class StageMark:
	extends Control
	var state := 0   # 0 pending, 1 now, 2 done

	func _init() -> void:
		custom_minimum_size = Vector2(22, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var middle := size * 0.5
		if state == 2:
			draw_circle(middle, 10.0, HouseStyle.ACCENT)
			draw_polyline(PackedVector2Array([middle + Vector2(-4, 0), middle + Vector2(-1, 3), middle + Vector2(4, -3)]),
					HouseStyle.ON_ACCENT, 2.0, true)
		elif state == 1:
			draw_circle(middle, 11.0, Color(HouseStyle.GOLD, 0.16))
			draw_arc(middle, 9.0, 0.0, TAU, 32, HouseStyle.GOLD, 2.0, true)
		else:
			draw_arc(middle, 9.0, 0.0, TAU, 32, HouseStyle.LINE, 2.0, true)

# === Private variables ===

var _tip_card: Control = null   # full mode: one tip under the bar, only on the named overlay
var _where: Label = null   # full mode: "BIOME REFERENCE · EXAMPLE ARRANGEMENT" bottom right, with the tip (sheet 06)
var _stage_names := PackedStringArray()
var _stage_marks: Array[StageMark] = []
var _stage_labels: Array[Label] = []

var _content: Control = null
var _label: Label = null
var _fill: Control = null   # a ColorRect in compact mode, a gradient in full mode
var _target := 0.0
var _current := 0.0
var _indeterminate := false
var _title: Label = null     # full mode: the optional big title (set_title)
var _stage: Label = null     # full mode: the mono stage line under the bar (set_stage)
var _percent: Label = null   # full mode: the per cent right of the stage line
var _subtitle: Label = null  # full mode: the line under the title (system and size)
var _fade_in: Tween = null

# === Exports ===

## Compact mode: a small centred glass panel instead of a full-screen black cover, so
## the rest of the screen stays visible (used for in-game loads like the army import).
## Set BEFORE adding the node to the tree.
@export var compact := false

# === Lifecycle ===

func _init() -> void:
	layer = 200  # above all in-scene UI


func _ready() -> void:
	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_STOP if not compact else Control.MOUSE_FILTER_IGNORE
	add_child(_content)

	if not compact:
		var bg := ColorRect.new()
		bg.color = HouseStyle.SHEET_FILL
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", HouseStyle.GAP_SECTION)

	# Compact: wrap the box in a glass panel so it reads as a small floating window.
	if compact:
		var panel := PanelContainer.new()
		HouseStyle.apply(panel)
		panel.add_child(box)
		center.add_child(panel)
	else:
		_place_full(box)

	_label = HouseStyle.label("", HouseStyle.EYEBROW)
	_label.theme = HouseStyle.theme()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if compact else HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(_label)
	if not compact:
		_label.add_theme_font_size_override("font_size", HouseStyle.FONT_EYEBROW_LARGE)
		_title = _text(box, "", HouseStyle.INK, HouseStyle.FONT_DISPLAY)
		_title.visible = false
		_subtitle = _text(box, "", HouseStyle.MUTED, FULL_SUBTITLE_PX)
		_subtitle.visible = false

	var track := Control.new()
	track.custom_minimum_size = Vector2(_track_w(), FULL_BAR_H if not compact else BAR_H)
	track.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if not compact else Control.SIZE_FILL
	track.clip_contents = true
	box.add_child(track)
	var track_bg := ColorRect.new()
	track_bg.color = HouseStyle.FILL_RAISED
	track_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	track_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(track_bg)
	_fill = _make_fill()
	_fill.size = Vector2(0.0, track.custom_minimum_size.y)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_fill)
	if compact:
		return
	var line := HBoxContainer.new()
	line.custom_minimum_size.x = FULL_TRACK_W
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(line)
	_stage = _text(line, "", HouseStyle.MUTED, HouseStyle.FONT_EYEBROW_LARGE)
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_percent = _text(line, "0 %", HouseStyle.GOLD, HouseStyle.FONT_EYEBROW_LARGE)
	for mono: Label in [_stage, _percent]:
		mono.add_theme_font_override("font", HouseStyle.mono())
	if not UiMotion.reduced():
		_content.modulate.a = 0.0
		_fade_in = create_tween()
		_fade_in.tween_property(_content, "modulate:a", 1.0, HouseStyle.DUR_SCREEN_IN)


## Full mode (sheet 06): the small wordmark top left, and `box` (eyebrow, title, bar, stage line) low on the left.
func _place_full(box: VBoxContainer) -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.theme = HouseStyle.theme()
	margin.add_theme_constant_override("margin_left", HouseStyle.PAD_SCREEN)
	margin.add_theme_constant_override("margin_top", HouseStyle.PAD_SCREEN / 2)
	margin.add_theme_constant_override("margin_bottom", FULL_BOTTOM)
	_content.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var brand := HBoxContainer.new()
	brand.name = "Wordmark"
	brand.add_theme_constant_override("separation", 0)
	column.add_child(brand)
	for part: String in ["NIEMANDS", "LAND"]:
		_text(brand, part, HouseStyle.ACCENT if part == "LAND" else HouseStyle.INK, HouseStyle.FONT_WORDMARK_SMALL) \
			.add_theme_font_override("font", load(HouseStyle.FONT_WORDMARK_PATH) as Font)
	column.add_child(HouseStyle.signature_rule(FULL_RULE_W))
	box.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	column.add_child(box)
	_content.add_child(_legal_line())
	_tip_card = _tip()
	_content.add_child(_tip_card)
	_where = _legal_line()
	_where.name = "PictureCaption"
	_where.text = "Biome reference · example arrangement"
	_where.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_where.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_where.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_where.offset_right = -64
	_where.offset_left = -64
	_where.offset_bottom = -40   # sheet 06 .where: 64 px from the right, 40 px from the bottom
	_where.offset_top = -40
	_where.visible = false
	_content.add_child(_where)


## The bar's fill: the accent in the compact panel; in full mode a gradient from the accent to the gold.
func _make_fill() -> Control:
	if compact:
		var solid := ColorRect.new()
		solid.color = HouseStyle.ACCENT
		return solid
	var gradient := Gradient.new()
	gradient.set_color(0, HouseStyle.ACCENT)
	gradient.set_color(1, HouseStyle.GOLD)
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	var bar := TextureRect.new()
	bar.texture = texture
	bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar.stretch_mode = TextureRect.STRETCH_SCALE
	return bar


## Whether a window of this height has room for the tip card.
static func tip_fits(window_height: float) -> bool:
	return window_height >= TIP_MIN_HEIGHT


## Full mode: one tip in a card under the bar (a gold bulb, the eyebrow "AT THE TABLE", the line); hidden until a title is
## set and below 800 px of height.
func _tip() -> Control:
	var card := PanelContainer.new()
	card.name = "TipCard"
	card.theme = HouseStyle.menu_theme()   # the tip at the menu's type scale (sheet 06: 18 px)
	card.theme_type_variation = HouseStyle.PANEL_VARIANT
	card.custom_minimum_size.x = TIP_W
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	card.offset_left = HouseStyle.PAD_SCREEN
	card.offset_right = HouseStyle.PAD_SCREEN + TIP_W
	card.offset_bottom = -(LEGAL_ABOVE_BOTTOM + 40)
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", HouseStyle.GAP_SECTION)
	var bulb := TextureRect.new()
	bulb.texture = HouseStyle.svg_icon(TIP_BULB_SVG)
	bulb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bulb.custom_minimum_size = Vector2(24, 24)
	bulb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bulb.modulate = HouseStyle.GOLD
	row.add_child(bulb)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.add_child(HouseStyle.label("AT THE TABLE", HouseStyle.EYEBROW))
	var line := HBoxContainer.new()   # a "?" in the tip stands as a key cap (sheet 06)
	line.add_theme_constant_override("separation", 6)
	var tip := TIPS[randi() % TIPS.size()]
	for i in tip.split(" ? ").size():
		if i > 0:
			line.add_child(HouseStyle.key_cap("?"))
		line.add_child(HouseStyle.label(tip.split(" ? ")[i], HouseStyle.BODY))
	words.add_child(line)
	row.add_child(words)
	card.add_child(row)
	return card


## Full mode: the line at the foot of the sheet, the menu's own (fan project, version, rules).
func _legal_line() -> Label:
	var menu := load("res://scripts/startup_menu.gd") as GDScript
	var line := Label.new()
	line.name = "LegalLine"
	line.text = "Fan project for OnePageRules  ·  " + str(menu.call("version_string"))
	line.uppercase = true
	line.add_theme_font_override("font", HouseStyle.mono())
	line.add_theme_font_size_override("font_size", HouseStyle.FONT_EYEBROW_LARGE)
	line.add_theme_color_override("font_color", Color(HouseStyle.MUTED, 0.78))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	line.offset_left = HouseStyle.PAD_SCREEN
	line.offset_top = -LEGAL_ABOVE_BOTTOM - 22
	line.offset_bottom = -LEGAL_ABOVE_BOTTOM
	return line


func _text(parent: Control, text: String, colour: Color, font_size: int) -> Label:
	var l := HouseStyle.label(text, HouseStyle.BODY)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l


func _track_w() -> float:
	return TRACK_W if compact else FULL_TRACK_W


func _process(delta: float) -> void:
	if _indeterminate:
		_target = minf(CREEP_TARGET, _target + CREEP_RATE * delta)
	# Exponential smoothing: a continuous, frame-rate-independent glide to the target.
	_current += (_target - _current) * (1.0 - exp(-delta * SMOOTH_RATE))
	if _fill != null:
		_fill.size.x = _current * _track_w()
	if _percent != null:
		_percent.text = "%d %%" % roundi(_current * 100.0)

# === Public API ===

func set_label(text: String) -> void:
	if _label != null:
		_label.text = text


## Full mode: the big title above the bar (the table being prepared); an empty text hides it.
func set_title(text: String) -> void:
	if _title != null:
		_title.text = text
		_title.visible = not text.is_empty()
	if _tip_card != null:
		_tip_card.visible = not text.is_empty() and tip_fits(get_viewport().get_visible_rect().size.y)
		_where.visible = _tip_card.visible


## Full mode: the line under the title (the game system and the table size); an empty text hides it.
func set_subtitle(text: String) -> void:
	if _subtitle != null:
		_subtitle.text = text
		_subtitle.visible = not text.is_empty()


## Full mode: `texture` fills the screen behind the text at BACKDROP_LIGHT, under a shade that keeps the left
## side (the text) dark. Call after the overlay is in the tree.
func set_backdrop(texture: Texture2D) -> void:
	if compact or _content == null or texture == null:
		return
	var picture := TextureRect.new()
	picture.name = "Backdrop"
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.self_modulate = Color(BACKDROP_LIGHT, BACKDROP_LIGHT, BACKDROP_LIGHT)
	var gradient := Gradient.new()
	gradient.set_color(0, HouseStyle.SHEET_FILL)
	gradient.set_color(1, Color(HouseStyle.SHEET_FILL, 0.0))
	var fill := GradientTexture2D.new()
	fill.gradient = gradient
	fill.fill_to = Vector2(1, 0)   # left to right
	var shade := TextureRect.new()
	shade.texture = fill
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	for layer: TextureRect in [picture, shade]:
		layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(layer)
		_content.move_child(layer, 1 if layer == picture else 2)   # above the cover, under the text


## Full mode: the stage line under the bar, in mono capitals; the marks follow it (see set_stages).
func set_stage(text: String) -> void:
	if _stage != null:
		_stage.text = text.to_upper()
	_mark_stages(text)


## Full mode: a row of marks under the subtitle, one per stage name; the first is the one in hand. The plain overlay
## (no names) shows none.
func set_stages(names: PackedStringArray) -> void:
	if compact or _subtitle == null or names.is_empty():
		return
	_stage_names = names
	var row := HBoxContainer.new()
	row.name = "StageMarks"
	row.add_theme_constant_override("separation", 26)
	_stage_marks.clear()
	_stage_labels.clear()
	for stage_name: String in names:
		var part := HBoxContainer.new()
		part.add_theme_constant_override("separation", 8)
		var mark := StageMark.new()
		part.add_child(mark)
		var label := _text(part, stage_name, HouseStyle.MUTED, 16)
		_stage_marks.append(mark)
		_stage_labels.append(label)
		row.add_child(part)
	var air := MarginContainer.new()   # room above and below, as the sheet leaves it
	air.add_theme_constant_override("margin_top", 12)
	air.add_theme_constant_override("margin_bottom", 20)
	air.add_child(row)
	_subtitle.get_parent().add_child(air)
	_subtitle.get_parent().move_child(air, _subtitle.get_index() + 1)
	_mark_stages(names[0])


## Every name before `text` is done, `text` is in hand, the rest pending; an empty text means all done; a text that is not
## a stage name ("Waiting for the host") leaves the marks as they are.
func _mark_stages(text: String) -> void:
	if _stage_marks.is_empty():
		return
	var at := _stage_names.size() if text.is_empty() else _stage_names.find(text)
	if at < 0:
		return
	for i in _stage_marks.size():
		var state := 2 if i < at else 1 if i == at else 0
		_stage_marks[i].state = state
		_stage_marks[i].queue_redraw()
		_stage_labels[i].add_theme_color_override("font_color",
				HouseStyle.INK if state == 2 else HouseStyle.GOLD if state == 1 else HouseStyle.MUTED)


## Set the real progress 0..1 (turns off indeterminate creep). The visible fill eases
## toward it; callers may update it as often as they like with no stepping.
func set_progress(ratio: float) -> void:
	_indeterminate = false
	_target = clampf(ratio, 0.0, 1.0)


## No known progress (e.g. a scene transition): keep the bar flowing by creeping up.
func set_indeterminate(on: bool = true) -> void:
	_indeterminate = on


## Fill to 100%, let it settle, fade out and free. Awaitable.
func complete_and_free() -> void:
	_indeterminate = false
	_target = 1.0
	await get_tree().create_timer(0.3).timeout
	if not is_instance_valid(self):
		return
	if _fade_in != null:
		_fade_in.kill()
	var fade := create_tween()
	fade.tween_property(_content, "modulate:a", 0.0, FADE_S)
	await fade.finished
	queue_free()


## Fade out and free without forcing the bar to 100% (caller already knows it's done).
func fade_and_free() -> void:
	if _fade_in != null:
		_fade_in.kill()
	if _content != null:
		var fade := create_tween()
		fade.tween_property(_content, "modulate:a", 0.0, FADE_S)
		await fade.finished
	queue_free()
