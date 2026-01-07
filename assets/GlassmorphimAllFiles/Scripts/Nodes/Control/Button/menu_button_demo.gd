extends MenuButton


func _ready() -> void:
	# Get the popup menu
	var popup: PopupMenu = get_popup()
	
	# Set Radio Button 2 as a radio button (checkable type 2)
	popup.set_item_as_radio_checkable(1, true)
	
	# Connect the popup menu's item selection signal
	popup.id_pressed.connect(_on_popup_id_pressed)


func _on_popup_id_pressed(id: int) -> void:
	var popup: PopupMenu = get_popup()
	
	# Handle radio buttons (index 0 and 1)
	if id == 0 or id == 1:
		# Uncheck all radio buttons first
		popup.set_item_checked(0, false)
		popup.set_item_checked(1, false)
		# Check the selected radio button
		popup.set_item_checked(id, true)
	
	# Handle checkbox (index 2)
	elif id == 2:
		# Toggle the checkbox state
		var is_checked: bool = popup.is_item_checked(2)
		popup.set_item_checked(2, not is_checked)
	
	# Handle regular options (index 4 and 5)
	elif id == 4 or id == 5:
		print("Selected: " + popup.get_item_text(id))
