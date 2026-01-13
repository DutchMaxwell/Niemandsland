extends TabContainer

## The popup menu that will be displayed when clicking the menu button
@export var popup_menu: PopupMenu


func _ready() -> void:
	if popup_menu:
		set_popup(popup_menu)
	
	# Disable the 10th tab (index 9)
	if get_tab_count() >= 12:
		set_tab_disabled(10, true)
