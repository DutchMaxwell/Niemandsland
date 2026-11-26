extends GdUnitTestSuite
## PromptCard keys: Enter takes the OK button, unless a button of the card holds focus - then it takes that
## button (the menu's quit card focuses its safe answer, Back, so a stray Enter never quits).


func _enter() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	return event


func _card() -> PromptCard:
	var card: PromptCard = auto_free(PromptCard.new("Title", "Body", "Yes", "No"))
	add_child(card)
	return card


func test_enter_takes_ok_while_no_button_holds_focus() -> void:
	var card := _card()
	card._input(_enter())
	assert_bool(await card.answer()).is_true()


## RED on main: Enter always took OK, a focused Back included.
func test_enter_takes_the_button_that_holds_focus() -> void:
	var card := _card()
	card.cancel_button.focus_mode = Control.FOCUS_ALL
	card.cancel_button.grab_focus()
	card._input(_enter())
	assert_bool(await card.answer()).is_false()
