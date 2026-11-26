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
const FULL_TRACK_W := 560.0   # full mode (sheet 06): a wider, thicker bar under the title block
const FULL_BAR_H := 5.0
const BACKDROP_LIGHT := 0.62   # full mode: the table's picture behind the text, at 62 % brightness (sheet 06)

# === Private variables ===

var _content: Control = null
var _label: Label = null
var _fill: ColorRect = null
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
		_subtitle = _text(box, "", HouseStyle.MUTED, HouseStyle.FONT_VALUE)
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
	_fill = ColorRect.new()
	_fill.color = HouseStyle.ACCENT
	_fill.size = Vector2(0.0, track.custom_minimum_size.y)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_fill)
	if compact:
		return
	var line := HBoxContainer.new()
	line.custom_minimum_size.x = FULL_TRACK_W
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(line)
	_stage = _text(line, "", HouseStyle.MUTED, HouseStyle.FONT_CAPTION)
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_percent = _text(line, "0 %", HouseStyle.GOLD, HouseStyle.FONT_CAPTION)
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
	margin.add_theme_constant_override("margin_bottom", HouseStyle.PAD_SCREEN * 2)
	_content.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var brand := HBoxContainer.new()
	brand.name = "Wordmark"
	brand.add_theme_constant_override("separation", 0)
	column.add_child(brand)
	for part: String in ["NIEMANDS", "LAND"]:
		_text(brand, part, HouseStyle.ACCENT if part == "LAND" else HouseStyle.INK, HouseStyle.FONT_WORDMARK_SMALL) \
			.add_theme_font_override("font", load(HouseStyle.FONT_WORDMARK_PATH) as Font)
	box.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	column.add_child(box)


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


## Full mode: the stage line under the bar, in mono capitals.
func set_stage(text: String) -> void:
	if _stage != null:
		_stage.text = text.to_upper()


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
