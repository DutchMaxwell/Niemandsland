extends GdUnitTestSuite
## Community #170: the dice tray names WHAT is being rolled. The scene must carry the
## RollPurposeLabel (hidden until a roll announces its purpose) and the roll context
## must have a purpose key so the label mirrors to MP peers inside the existing
## context Dictionary.

const MAIN_SCENE := "res://scenes/main.tscn"


func test_tray_panel_carries_the_roll_purpose_label() -> void:
	# Instantiate-only (ui_click_ownership_test pattern): asserts what the .tscn stores
	# without running main.gd's heavy _ready().
	var main: Node = auto_free(load(MAIN_SCENE).instantiate())
	var label := main.get_node("UI/HUD/DiceRollerPanel/VBox/RollPurposeLabel") as Label
	assert_object(label).is_not_null()
	assert_bool(label.visible).is_false()   # empty until a roll sets it
	assert_int(label.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)


func test_roll_context_has_a_purpose_key() -> void:
	assert_str(DiceRules.CTX_PURPOSE).is_equal("purpose")
