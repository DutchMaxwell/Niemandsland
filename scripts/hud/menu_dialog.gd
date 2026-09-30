class_name MenuDialog
extends RefCounted
## House-style chrome for the menu scene's AcceptDialogs: the shared theme, a gold OK, ghost lines for the
## content buttons. A control that already carries a variation keeps it (RESET = danger, goal lines = caption).


static func style(d: AcceptDialog) -> void:
	d.theme = HouseStyle.theme()
	d.get_ok_button().theme_type_variation = HouseStyle.PRIMARY
	d.get_ok_button().custom_minimum_size.y = HouseStyle.H_ACTION
	if d is ConfirmationDialog:
		(d as ConfirmationDialog).get_cancel_button().theme_type_variation = HouseStyle.BUTTON
		(d as ConfirmationDialog).get_cancel_button().custom_minimum_size.y = HouseStyle.H_ACTION
	for n: Node in d.find_children("*", "Button", true, false):
		var b := n as Button
		if b == d.get_ok_button() or b.theme_type_variation != &"" or b is CheckBox or b is CheckButton:
			continue
		if d is ConfirmationDialog and b == (d as ConfirmationDialog).get_cancel_button():
			continue
		b.theme_type_variation = HouseStyle.BUTTON
		b.custom_minimum_size.y = HouseStyle.H_SEGMENT
	for n: Node in d.find_children("*", "Label", true, false):
		if (n as Label).theme_type_variation == &"":
			(n as Label).theme_type_variation = HouseStyle.BODY
