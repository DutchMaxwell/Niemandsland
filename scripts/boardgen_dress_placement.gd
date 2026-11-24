class_name DressPlacement
extends RefCounted
## One placed module of the ruin-town dressing: which manifest module, where it stands (a transform
## in metres in board space, origin at the board centre), the class that placed it, the lot it
## belongs to (-1 when it belongs to none) and the planner's look pick (whole, holed, rafters, ...).

var module: String = ""
var transform := Transform3D()
var cls: String = ""
var lot: int = -1
var look: String = ""


func _init(
	p_module := "", p_transform := Transform3D(), p_cls := "", p_lot := -1, p_look := ""
) -> void:
	module = p_module
	transform = p_transform
	cls = p_cls
	lot = p_lot
	look = p_look
