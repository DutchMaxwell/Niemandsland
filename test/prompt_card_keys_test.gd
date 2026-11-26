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


func _collect_answer(card: PromptCard, into: Array) -> void:
	into[0] = await card.answer()


func _scrim_alpha(card: PromptCard) -> float:
	var scrim: Variant = card.get("_scrim")
	return scrim.color.a if scrim != null else 0.0


## The menu's cards fade in and out (scrim and card); a plain card, and any card with Reduce Motion, is
## instant. RED on main: the card was there at once.
func test_an_animated_card_fades_and_a_plain_card_does_not() -> void:
	var before_motion: bool = GraphicsSettings.reduce_motion
	GraphicsSettings.reduce_motion = false
	var plain := _card()
	await get_tree().process_frame
	assert_float((plain.find_child("Card", true, false) as Control).modulate.a).is_equal(1.0)
	assert_float(_scrim_alpha(plain)).is_equal(0.0)
	var card: PromptCard = auto_free(PromptCard.new("Title", "Body", "Yes", "No"))
	card.set("animate", true)
	add_child(card)
	var panel := card.find_child("Card", true, false) as Control
	assert_float(panel.modulate.a).override_failure_message("the card was there at once").is_equal(0.0)
	await get_tree().create_timer(0.5).timeout
	assert_float(panel.modulate.a).is_equal(1.0)
	assert_float((panel.get_parent() as Control).scale.x).is_equal(1.0)
	assert_float(_scrim_alpha(card)).is_equal_approx(HouseStyle.SCRIM.a, 0.01)
	card.resolve(true)
	var answered := [null]
	_collect_answer(card, answered)
	await get_tree().create_timer(0.08).timeout
	assert_bool(is_instance_valid(card) and not card.is_queued_for_deletion()).override_failure_message(
		"the card went at once").is_true()
	await get_tree().create_timer(0.4).timeout
	assert_bool(answered[0] == true).is_true()
	GraphicsSettings.reduce_motion = before_motion


func test_an_animated_card_is_instant_with_reduce_motion() -> void:
	var before_motion: bool = GraphicsSettings.reduce_motion
	GraphicsSettings.reduce_motion = true
	var card: PromptCard = auto_free(PromptCard.new("Title", "Body", "Yes", "No"))
	card.set("animate", true)
	add_child(card)
	await get_tree().process_frame
	assert_float((card.find_child("Card", true, false) as Control).modulate.a).is_equal(1.0)
	GraphicsSettings.reduce_motion = before_motion

