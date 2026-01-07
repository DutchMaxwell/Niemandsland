extends Button

@export var confirmation_dialog: ConfirmationDialog

func _ready() -> void:
	pressed.connect(_on_button_pressed)
	
	if confirmation_dialog:
		confirmation_dialog.confirmed.connect(_on_confirmed)
		confirmation_dialog.canceled.connect(_on_canceled)

func _on_button_pressed() -> void:
	if confirmation_dialog:
		confirmation_dialog.popup_centered(Vector2(400, 200))
	else:
		push_error("ConfirmationDialog not assigned to confirmation_dialog_button")

func _on_confirmed() -> void:
	print("User clicked OK")

func _on_canceled() -> void:
	print("User clicked Cancel")
