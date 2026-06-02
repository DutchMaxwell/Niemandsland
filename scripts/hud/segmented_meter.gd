class_name SegmentedMeter
extends Control
## XCOM-style segmented meter: `segments` cells, `filled` of them solid, the rest hollow.
## Countable + glanceable on the 3D table — replaces smooth progress bars for wounds /
## strength. Drawn from HudTokens; no art assets. Pair the colour with a label/icon so
## meaning is never carried by hue alone (CVD).

const T := preload("res://scripts/hud/hud_tokens.gd")

@export var segments: int = 3: set = set_segments
@export var filled: int = 0: set = set_filled
@export var fill_color: Color = T.AMBER
@export var empty_color: Color = Color(1.0, 1.0, 1.0, 0.14)
@export var gap: float = 4.0


func _ready() -> void:
	resized.connect(queue_redraw)
	if custom_minimum_size.y <= 0.0:
		custom_minimum_size.y = 8.0


func set_segments(v: int) -> void:
	segments = maxi(0, v)
	filled = clampi(filled, 0, segments)
	queue_redraw()


func set_filled(v: int) -> void:
	filled = clampi(v, 0, segments)
	queue_redraw()


## Pure: width of one cell given the total width, segment count and gap (testable).
static func cell_width(total_w: float, segs: int, gap_px: float) -> float:
	if segs <= 0:
		return 0.0
	return (total_w - gap_px * float(segs - 1)) / float(segs)


func _draw() -> void:
	if segments <= 0:
		return
	var cw := cell_width(size.x, segments, gap)
	if cw <= 0.0:
		return
	for i in range(segments):
		var rect := Rect2(float(i) * (cw + gap), 0.0, cw, size.y)
		if i < filled:
			draw_rect(rect, fill_color, true)
		else:
			draw_rect(rect.grow(-1.0), empty_color, false, 1.0)
