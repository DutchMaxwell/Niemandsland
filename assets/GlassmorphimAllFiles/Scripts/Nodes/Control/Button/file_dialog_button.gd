extends Button

@export var file_dialog: FileDialog

func _ready() -> void:
	pressed.connect(_on_button_pressed)

func _on_button_pressed() -> void:
	if file_dialog:
		file_dialog.popup_centered(Vector2(800, 600))
	else:
		push_error("FileDialog not assigned to file_dialog_button")
