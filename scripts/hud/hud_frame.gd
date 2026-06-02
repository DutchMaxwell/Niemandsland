class_name HudFrame
extends Control
## Tactical "instrumentation" chrome: L-shaped corner brackets drawn in _draw() from
## HudTokens. Drop it as the LAST child of any Panel/PanelContainer (it fits the content
## rect and stacks on top) to make the panel read as a HUD module rather than a web card.
## mouse_filter is IGNORE so it never blocks input. No art assets — sharp at any zoom.

const T := preload("res://scripts/hud/hud_tokens.gd")

@export var bracket_color: Color = Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.75)
@export var bracket_length: float = 14.0
@export var line_width: float = 2.0
@export var inset: float = 1.0  # pull brackets a hair inside the rect so they read as drawn-on


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## Pure: clamp the bracket leg so two legs never exceed the shorter side (testable).
static func bracket_len(requested: float, rect_size: Vector2) -> float:
	return minf(requested, minf(rect_size.x, rect_size.y) * 0.45)


func _draw() -> void:
	var r := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var bl := bracket_len(bracket_length, r.size)
	_corner(r.position, Vector2(1, 1), bl)                          # top-left
	_corner(Vector2(r.end.x, r.position.y), Vector2(-1, 1), bl)     # top-right
	_corner(Vector2(r.position.x, r.end.y), Vector2(1, -1), bl)     # bottom-left
	_corner(r.end, Vector2(-1, -1), bl)                             # bottom-right


func _corner(p: Vector2, dir: Vector2, bl: float) -> void:
	draw_line(p, p + Vector2(dir.x * bl, 0.0), bracket_color, line_width, true)
	draw_line(p, p + Vector2(0.0, dir.y * bl), bracket_color, line_width, true)
