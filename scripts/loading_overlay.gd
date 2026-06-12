class_name LoadingOverlay
extends CanvasLayer
## Reusable full-screen loading overlay: a black background, a centred mono label and a
## thin cyan bar whose fill EASES continuously toward its target (exponential smoothing,
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
const MONO_FONT_PATH := "res://assets/ui_glassmorphism/fonts/SourceCodePro.ttf"

# === Private variables ===

var _content: Control = null
var _label: Label = null
var _fill: ColorRect = null
var _target := 0.0
var _current := 0.0
var _indeterminate := false

# === Lifecycle ===

func _init() -> void:
	layer = 200  # above all in-scene UI


func _ready() -> void:
	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow input while loading
	add_child(_content)

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var mono := FontVariation.new()
	mono.base_font = load(MONO_FONT_PATH)
	mono.spacing_glyph = 2
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", mono)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
	box.add_child(_label)

	var track := Control.new()
	track.custom_minimum_size = Vector2(TRACK_W, BAR_H)
	track.clip_contents = true
	box.add_child(track)
	var track_bg := ColorRect.new()
	track_bg.color = Color(1, 1, 1, 0.08)
	track_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	track_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(track_bg)
	_fill = ColorRect.new()
	_fill.color = HudTokens.CYAN
	_fill.size = Vector2(0.0, BAR_H)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_fill)


func _process(delta: float) -> void:
	if _indeterminate:
		_target = minf(CREEP_TARGET, _target + CREEP_RATE * delta)
	# Exponential smoothing: a continuous, frame-rate-independent glide to the target.
	_current += (_target - _current) * (1.0 - exp(-delta * SMOOTH_RATE))
	if _fill != null:
		_fill.size.x = _current * TRACK_W

# === Public API ===

func set_label(text: String) -> void:
	if _label != null:
		_label.text = text


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
	var fade := create_tween()
	fade.tween_property(_content, "modulate:a", 0.0, FADE_S)
	await fade.finished
	queue_free()


## Fade out and free without forcing the bar to 100% (caller already knows it's done).
func fade_and_free() -> void:
	if _content != null:
		var fade := create_tween()
		fade.tween_property(_content, "modulate:a", 0.0, FADE_S)
		await fade.finished
	queue_free()
