class_name UiMotion
extends RefCounted
## Centralised UI micro-interaction motion (hover / press) from HudTokens Motion tokens.
## Honours GraphicsSettings.reduce_motion (collapses to instant — WCAG 2.3.3). Attach to a
## Control once via attach_button(); a global wirer can call this for every BaseButton so
## there is no per-call-site Tween code. Render-only `scale` (pivot-centred) so layout and
## neighbours never shift.

const T := preload("res://scripts/hud/hud_tokens.gd")
const META_TWEEN := "_ui_motion_tw"


## True when motion should be suppressed. Reads the GraphicsSettings autoload if present
## (guarded so tests / headless tools don't crash).
static func reduced() -> bool:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var gs: Node = (loop as SceneTree).root.get_node_or_null("GraphicsSettings")
		if gs and "reduce_motion" in gs:
			return gs.reduce_motion
	return false


## Give a control tactile hover (1.02) + press-in (0.97) + release-punch (1.06) feedback.
static func attach_button(c: Control) -> void:
	if not is_instance_valid(c):
		return
	c.pivot_offset = c.size * 0.5
	c.resized.connect(func() -> void:
		if is_instance_valid(c):
			c.pivot_offset = c.size * 0.5)
	c.mouse_entered.connect(func() -> void: _scale_to(c, T.SCALE_HOVER, T.DUR_HOVER))
	c.mouse_exited.connect(func() -> void: _scale_to(c, 1.0, T.DUR_HOVER))
	if c is BaseButton:
		var b := c as BaseButton
		b.button_down.connect(func() -> void: _scale_to(c, T.SCALE_PRESS, T.DUR_PRESS))
		b.button_up.connect(func() -> void: _punch(c))
		b.focus_entered.connect(func() -> void: _scale_to(c, T.SCALE_HOVER, T.DUR_HOVER))
		b.focus_exited.connect(func() -> void: _scale_to(c, 1.0, T.DUR_HOVER))


static func _scale_to(c: Control, s: float, dur: float) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	if c is BaseButton and (c as BaseButton).disabled:
		return
	c.pivot_offset = c.size * 0.5  # re-centre (size may have been 0 at attach time)
	_kill(c)
	if reduced():
		c.scale = Vector2(s, s)
		return
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(s, s), dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	c.set_meta(META_TWEEN, tw)


static func _punch(c: Control) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	_kill(c)
	if reduced():
		c.scale = Vector2.ONE
		return
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(T.SCALE_PUNCH, T.SCALE_PUNCH), T.DUR_PRESS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, T.DUR_HOVER) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	c.set_meta(META_TWEEN, tw)


static func _kill(c: Control) -> void:
	if c.has_meta(META_TWEEN):
		var tw: Variant = c.get_meta(META_TWEEN)
		if tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).kill()
