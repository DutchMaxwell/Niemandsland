class_name DropdownPlacement
extends RefCounted
## A dropdown's list must never cover its own button: the mouse release that ends the opening click would
## land on an entry and pick it — the player never chose it (board N15: the Mission picker jumped from Duel
## to entry 3 on a plain click). Godot's OptionButton covers its button in two cases: (1) the button sits so
## low that the list does not fit below, and the engine slides the list up over it; (2) the window is smaller
## than the 1920 x 1080 design size, where the engine applies the stretch scale to the button's height twice
## and opens the list inside the button's lower part. `keep_button_clear` moves such a list below the button,
## or above it when there is no room, or beside it when there is room for neither.


## Call once per dropdown (OptionButton) that can sit low on the screen or in a small window.
static func keep_button_clear(opt: OptionButton) -> void:
	opt.pressed.connect(_clear_button.bind(opt))


## Runs right after the engine opened the list (the `pressed` signal follows OptionButton's own show_popup).
static func _clear_button(opt: OptionButton) -> void:
	var popup := opt.get_popup()
	if not popup.visible or not popup.is_embedded():
		return
	var button := opt.get_global_rect()
	var list := Rect2(popup.position, popup.size)
	if not list.intersects(button):
		return
	var room := opt.get_viewport().get_visible_rect().size
	var pos := popup.position
	if button.end.y + list.size.y <= room.y:
		pos.y = ceili(button.end.y)
	elif button.position.y - list.size.y >= 0.0:
		pos.y = floori(button.position.y - list.size.y)
	else:
		pos = Vector2i(ceili(button.end.x), clampi(int(button.position.y), 0, maxi(0, int(room.y - list.size.y))))
	popup.position = pos
