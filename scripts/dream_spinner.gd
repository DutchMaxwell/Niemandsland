class_name DreamSpinner
extends Control
## A small self-drawn "comet-tail" idle spinner for the NACHTMAHR-dreams overlay (maintainer request:
## a centred, animated symbol that the AI is computing). No external assets — a rotating arc drawn as
## alpha-ramped segments, advanced every frame it is allowed to render. During a synchronous planner
## burst it momentarily freezes (single-threaded), then resumes; over an AI turn it reads as "thinking".

@export var arc_color: Color = Color(1.0, 0.78, 0.30)   # NACHTMAHR amber
@export var revolutions_per_sec: float = 0.85
@export var thickness: float = 4.0

var _angle: float = 0.0
const SEGMENTS := 24


func _process(delta: float) -> void:
	_angle = fposmod(_angle + revolutions_per_sec * TAU * delta, TAU)
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - thickness
	if radius <= 1.0:
		return
	# A 270° comet with alpha ramping from faint (tail) to full (head), rotated by _angle.
	var span := TAU * 0.75
	for i in range(SEGMENTS):
		var t := float(i) / float(SEGMENTS - 1)
		var a0 := _angle + span * (float(i) / float(SEGMENTS))
		var a1 := _angle + span * (float(i + 1) / float(SEGMENTS))
		var col := arc_color
		col.a = arc_color.a * lerpf(0.08, 1.0, t)
		draw_arc(centre, radius, a0, a1, 3, col, thickness, true)
	# The bright head dot.
	var head := centre + Vector2(cos(_angle + span), sin(_angle + span)) * radius
	draw_circle(head, thickness * 0.9, arc_color)
