class_name DieFaceIcon
extends Control
## A small d6 face drawn with pips (no font glyphs or image assets required).
##
## Set [member face] to 1-6; the control draws a rounded die body with the
## matching pip pattern, scaled to the control's current size. Used by the dice
## roller's success readout (current roll column and the horizontal log).

# === Constants ===

## Pip radius as a fraction of the smaller side.
const PIP_RADIUS_FACTOR: float = 0.11
## Corner radius as a fraction of the smaller side.
const CORNER_FACTOR: float = 0.18

## Normalised pip centres (0..1) for each face, using a 3x3 grid.
const PIP_LAYOUT: Dictionary = {
	1: [Vector2(0.5, 0.5)],
	2: [Vector2(0.28, 0.28), Vector2(0.72, 0.72)],
	3: [Vector2(0.28, 0.28), Vector2(0.5, 0.5), Vector2(0.72, 0.72)],
	4: [Vector2(0.28, 0.28), Vector2(0.72, 0.28), Vector2(0.28, 0.72), Vector2(0.72, 0.72)],
	5: [Vector2(0.28, 0.28), Vector2(0.72, 0.28), Vector2(0.5, 0.5), Vector2(0.28, 0.72), Vector2(0.72, 0.72)],
	6: [Vector2(0.28, 0.28), Vector2(0.72, 0.28), Vector2(0.28, 0.5), Vector2(0.72, 0.5), Vector2(0.28, 0.72), Vector2(0.72, 0.72)],
}

# === Exports ===

## The face value to show (1-6).
@export var face: int = 6:
	set(value):
		face = clampi(value, 1, 6)
		queue_redraw()

@export var body_color: Color = Color(0.93, 0.93, 0.90)
@export var pip_color: Color = Color(0.12, 0.12, 0.14)
@export var border_color: Color = Color(0.30, 0.30, 0.32)

# === Lifecycle ===

func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var s: Vector2 = size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var short_side: float = minf(s.x, s.y)

	# Die body (rounded square with a thin border).
	var body := StyleBoxFlat.new()
	body.bg_color = body_color
	body.border_color = border_color
	body.set_border_width_all(1)
	body.set_corner_radius_all(int(short_side * CORNER_FACTOR))
	draw_style_box(body, Rect2(Vector2.ZERO, s))

	# Pips.
	var radius: float = short_side * PIP_RADIUS_FACTOR
	for cell: Vector2 in PIP_LAYOUT[face]:
		draw_circle(Vector2(cell.x * s.x, cell.y * s.y), radius, pip_color)
