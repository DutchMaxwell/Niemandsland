extends GdUnitTestSuite
## Click ownership between the HUD and the 3D table.
##
## World picking runs in _unhandled_input, so UI occlusion is the ENGINE's decision, not ours: Godot
## dispatches _input → GUI (Control._gui_input) → _unhandled_input and aborts as soon as the event is
## handled, which happens when a mouse button reaches a MOUSE_FILTER_STOP ancestor (or a control calls
## accept_event()). That makes ONE tree property load-bearing, so it is pinned here:
##
##   transparent holder  → IGNORE   (else the holder eats every click and the whole 3D scene becomes
##                                   unselectable — the URGENT-024 regression)
##   interactive surface → STOP at its own root (else every gap, padding pixel and IGNORE Label band
##                                   inside it leaks a click through to the table — the maintainer bug:
##                                   "durchklickt auf das Spielfeld … anstatt der Aktivierung des Buttons")
##   PASS                → legal only INSIDE a surface whose own root is STOP
##
## Measured on Godot 4.6.2 against a replica of this exact tree:
##   HUD=STOP,   scroll=PASS  → click on open table  reaches the world: NO   (nothing selectable)
##   HUD=IGNORE, scroll=PASS  → click on a label band / a 4px button gap reaches the world: YES (the bug)
##   HUD=IGNORE, scroll=STOP  → gaps/labels consumed, open table still reaches the world: correct
##
## The scene is only instantiated, never added to the tree: this asserts what scenes/main.tscn stores,
## which is what a future .tscn edit would break, without running main.gd's very heavy _ready().

const MAIN_SCENE := "res://scenes/main.tscn"


func _hud() -> Control:
	var main: Node = auto_free(load(MAIN_SCENE).instantiate())
	return main.get_node("UI/HUD") as Control


func test_hud_root_is_ignore_so_the_table_stays_clickable() -> void:
	# URGENT-024: UI/HUD is a full-rect Control that merely holds the overlay. A Control defaults to
	# STOP, and a full-rect STOP holder consumes EVERY click in the viewport before _unhandled_input.
	assert_int(_hud().mouse_filter) \
		.override_failure_message("UI/HUD must be MOUSE_FILTER_IGNORE — as a STOP holder it swallows every click and nothing in the 3D scene can be selected (URGENT-024)") \
		.is_equal(Control.MOUSE_FILTER_IGNORE)


func test_no_hud_surface_leaks_clicks() -> void:
	# A direct child of the transparent holder has no STOP ancestor of its own, so a bare PASS there
	# means every gap, padding pixel and IGNORE Label band inside it leaks a click to the 3D table.
	# ScrollContainer and every Container subclass default to PASS — this is the trap.
	#
	# PASS is allowed in exactly one shape: the child is a FRAME that paints nothing itself and whose
	# interactive content carries its own STOP surface.
	# THE RULE THAT DECIDES IT: a control must own exactly the pixels it PAINTS. An attempt to make
	# LeftPanelScroll PASS failed this — the ScrollContainer draws the menu's opaque background across
	# its whole rect, so its "empty" tail below the last button is menu, not table, and turning it
	# click-through opened a measured 200x246 px hole in the middle of the visible menu at 1080p.
	var children: Array = _hud().get_children()
	assert_int(children.size()).is_greater(0)
	for child in children:
		if child is Control and (child as Control).mouse_filter == Control.MOUSE_FILTER_PASS:
			assert_bool(_has_stop_descendant(child)) \
				.override_failure_message("UI/HUD/%s is MOUSE_FILTER_PASS with no STOP surface inside it — a direct child of the IGNORE holder must own its clicks (STOP), be decoration (IGNORE), or be a frame whose content is STOP" % child.name) \
				.is_true()


func _has_stop_descendant(node: Node) -> bool:
	for child in node.get_children():
		if child is Control and (child as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			return true
		if _has_stop_descendant(child):
			return true
	return false


func test_the_hamburger_column_owns_its_clicks() -> void:
	# The single biggest instance of the bug: ~20 buttons at 4px separation plus five IGNORE Label
	# bands inside a PASS ScrollContainer → PASS VBox chain. Clicking a label or a seam fired no
	# button and opened a selection/box-select on the table behind it.
	# BOTH are STOP, and that is deliberate. The VBox owns the seams and label bands between the
	# buttons; the ScrollContainer owns the rest of the rect it paints — its background is opaque, so
	# the tail below the last button is still menu. Making that tail PASS was tried and measured to
	# open a 200x246 px click-through hole in the middle of the visible menu at 1080p.
	var scroll: Control = _hud().get_node("LeftPanelScroll") as Control
	assert_object(scroll).is_not_null()
	assert_int(scroll.mouse_filter) \
		.override_failure_message("LeftPanelScroll must be STOP — it paints the menu background across its whole rect, so it must own those clicks") \
		.is_equal(Control.MOUSE_FILTER_STOP)
	var vbox: Control = scroll.get_node("LeftPanelVBox") as Control
	assert_object(vbox).is_not_null()
	assert_int(vbox.mouse_filter) \
		.override_failure_message("the hamburger column's VBox must be STOP — it is the surface that owns the button gaps and the label bands") \
		.is_equal(Control.MOUSE_FILTER_STOP)


func test_world_clicks_are_never_handled_in_the_input_stage() -> void:
	# _input runs BEFORE the GUI, so a handler there can never be shielded by a Button: it is
	# structurally impossible to ask "did a control own this click?" from that stage. BUTTONS must
	# therefore wait for _unhandled_input.
	# MOTION is the one exception, and it is not a matter of taste: Godot routes motion to
	# gui_find_control() whenever gui.mouse_focus is null — the state during a drag that STARTED on the
	# table — so a STOP panel swallows it and the gesture freezes at the panel edge. Both files keep a
	# narrow _input that claims motion ONLY while a gesture is already live. This test pins that split:
	# _input may exist, but it may not touch mouse BUTTONS.
	for path in ["res://scripts/object_manager.gd", "res://scripts/camera_controller.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		assert_str(src).contains("func _unhandled_input(")
		var at: int = src.find("func _input(")
		if at < 0:
			continue
		var rest: String = src.substr(at + 12)
		var next_func: int = rest.find("\nfunc ")
		var body: String = rest if next_func < 0 else rest.substr(0, next_func)
		assert_bool(body.contains("InputEventMouseButton")) \
			.override_failure_message("%s handles a mouse BUTTON in _input(); that stage runs before the GUI, so a click on a Button would reach the world too" % path) \
			.is_false()
