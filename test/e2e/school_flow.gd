extends RefCounted
## Game School e2e helpers: the explicit activation the way a player does it. Select a unit (its card shows), press
## Activate on the card, set the Movement row, drag, shoot / cast, press End activation or Cancel. Every press goes
## through the same buttons and handlers the UI uses; nothing here writes a model position or a flag.

const INCH := 0.0254


static func screen(main: Node, wx: float, wz: float) -> Vector2:
	return main.get_viewport().get_camera_3d().unproject_position(Vector3(wx, 0.0, wz))


## What a click on a model of `unit` does: the whole unit is selected and its card is presented.
static func select(main: Node, unit: GameUnit) -> void:
	var om: Node3D = main.object_manager
	om._deselect_all()
	for model in unit.models:
		var mi := model as ModelInstance
		if mi != null and mi.is_alive and is_instance_valid(mi.node):
			om._add_to_selection(mi.node)
	main.unit_dock.present_unit(unit)


## Presses the card button with this text. False when the card shows no such button.
static func press(main: Node, label: String) -> bool:
	for n: Node in main.unit_dock.find_children("*", "Button", true, false):
		var b := n as Button
		if b.text == label and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return true
	return false


## Presses a button of the Movement row (ObjectManager.MovementCap: 1 Advance, 2 Rush, 3 Charge).
static func set_mode(main: Node, mode: int) -> void:
	var b := main._movement_cap_buttons[mode] as Button
	b.pressed.emit()


## A real drag of the selected unit by (dx, dz) inches, landed (the drop tween done).
static func drag(main: Node, tree: SceneTree, unit: GameUnit, dx_in: float, dz_in: float) -> void:
	var om: Node3D = main.object_manager
	var a: Node3D = null
	for model in unit.models:
		var mi := model as ModelInstance
		if mi != null and mi.is_alive and is_instance_valid(mi.node):
			a = mi.node
			break
	var p := a.global_position
	om._start_dragging(screen(main, p.x, p.z))
	om._update_drag(screen(main, p.x + dx_in * INCH, p.z + dz_in * INCH))
	await tree.process_frame
	om._stop_dragging()
	for i in 3:
		await tree.process_frame
	await tree.create_timer(0.3).timeout   # a new drop id (a millisecond stamp) for the next drag
