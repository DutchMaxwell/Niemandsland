extends Button

# Placeholder for the LinkTree URL
@export var linktree_url: String = "https://linktr.ee/AudaciousGabe"

func _ready() -> void:
	pressed.connect(_on_button_pressed)

func _on_button_pressed() -> void:
	OS.shell_open(linktree_url)
