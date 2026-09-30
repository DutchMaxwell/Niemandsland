class_name GameOverPanel
extends RefCounted
## The Game over summary as an in-viewport house-style panel (D98 a): the words the AcceptDialog carried,
## an OK that closes it. Closing by OK, the × or Esc calls `on_closed` once.

const LAYER := 110
const WIDTH := 460


static func open(parent: Node, text: String, on_closed: Callable) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "GameOverLayer"
	layer.layer = LAYER
	var parts := HouseStyle.overlay_sheet("Game over", WIDTH)
	var body: VBoxContainer = parts["body"]
	var summary := HouseStyle.label(text, HouseStyle.BODY)
	summary.name = "Summary"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	summary.custom_minimum_size.x = WIDTH - 2 * HouseStyle.PAD_SHEET
	body.add_child(summary)
	var ok := HouseStyle.button("OK", HouseStyle.PRIMARY)
	ok.name = "OkButton"
	ok.focus_mode = Control.FOCUS_ALL
	body.add_child(ok)
	var done := [false]
	var close := func() -> void:
		if done[0]:
			return
		done[0] = true
		layer.queue_free()
		on_closed.call()
	ok.pressed.connect(close)
	(parts["close"] as Button).pressed.connect(close)
	ok.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_cancel"):
			close.call())
	layer.add_child(parts["root"] as Control)
	parent.add_child(layer)
	ok.grab_focus()
	return layer
