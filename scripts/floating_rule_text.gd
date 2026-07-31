class_name FloatingRuleText
extends Node3D
## Transparency wave stage 2 (grilled 2026-07-30): every applied rule announces itself AT
## THE TABLE — a small billboard text rises from the affected unit and fades ("Blast ×3",
## "Artillery +1", "Surge: +1 hit", the negative lines too). The battle log stays the
## archive; this is the in-the-moment voice, because players watch models, not logs.
##
## Maintainer decision: show EVERYTHING — so readability comes from the CASCADE: texts on
## the same spot stack vertically and start staggered, never overlapping. System-owner
## overlay pattern (like MoveTrails): pure visuals under /root/Main, never in the pick path.

const RISE_M := 0.06            # world rise over the float's life
const LIFE_S := 2.2
const STAGGER_S := 0.28         # cascade delay between texts on the same anchor
const STACK_M := 0.022          # vertical slot per queued text on the same anchor
const BASE_Y_M := 0.09
const FONT_SIZE := 40
const MAX_QUEUE := 12           # runaway guard per anchor burst

## Player toggle (GraphicsSettings.show_rule_floats, default on).
var enabled: bool = true
var force_for_tests: bool = false   # e2e opts in — plain headless never spawns

## anchor key (rounded world pos) -> pending count, for the stagger/stack cascade.
var _pending := {}


func _ready() -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs != null and gs.get("show_rule_floats") != null:
		enabled = bool(gs.show_rule_floats)


## Announce one rule application at a world position. Cheap and fire-and-forget: every
## call spawns one Label3D whose slot in the local cascade is derived from how many are
## already pending on the same anchor.
func announce(world_pos: Vector3, text: String, color: Color = Color(1.0, 0.92, 0.5)) -> void:
	if not enabled or text.is_empty():
		return
	# Headless spawns are invisible and only leak: the staggered cascade (12 queued + 1
	# live) was the CI's recurring "13 orphans" in long volley e2e runs. Tests that assert
	# the labels opt in explicitly — same pattern as the combat stage.
	if DisplayServer.get_name() == "headless" and not force_for_tests:
		return
	var key := "%d:%d" % [int(round(world_pos.x * 10.0)), int(round(world_pos.z * 10.0))]
	var slot := int(_pending.get(key, 0))
	if slot >= MAX_QUEUE:
		return
	_pending[key] = slot + 1
	var label := Label3D.new()
	label.text = text
	label.font_size = FONT_SIZE
	label.pixel_size = 0.0004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = color
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.position = world_pos + Vector3(0, BASE_Y_M + slot * STACK_M, 0)
	label.modulate.a = 0.0
	add_child(label)
	var tw := create_tween()
	tw.tween_interval(slot * STAGGER_S)   # the cascade: later texts start later
	tw.tween_property(label, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(label, "position:y", label.position.y + RISE_M, LIFE_S)
	tw.tween_interval(maxf(LIFE_S - 0.5, 0.1))
	tw.tween_property(label, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func() -> void:
		_pending[key] = maxi(int(_pending.get(key, 1)) - 1, 0)
		label.queue_free())


## Test/teardown hygiene: drop the pending cascade and free every live label NOW —
## queue_free'd-but-unprocessed labels read as orphans in the test harness.
func clear() -> void:
	_pending.clear()
	for c in get_children():
		if c is Label3D:
			c.free()
