extends CheckBox


@export var line_edit: LineEdit


func _on_toggled(toggled_on: bool) -> void:
	if not line_edit:
		return
	
	if toggled_on:
		line_edit.secret = false
	else:
		line_edit.secret = true
