extends Button

@export var accept_dialog: AcceptDialog

func _ready() -> void:
	pressed.connect(_on_button_pressed)

func _on_button_pressed() -> void:
	if accept_dialog:
		accept_dialog.popup_centered(Vector2(400, 200))
	else:
		push_error("AcceptDialog not assigned to accept_dialog_button")
