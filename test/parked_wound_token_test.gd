extends GdUnitTestSuite
## J9: a model PARKED on the tray (both `deleted` + `dead_slot` metas) must never show a wound token,
## so NO caller re-draws the red "1" onto the tray — notably the MP receive path
## (_on_remote_wounds_updated → _update_wound_marker), which is where the defect showed. Guards the
## pure gate RadialMenuController._wound_token_active (the single decision every wound-marker draw runs
## through).


func test_wounded_alive_model_shows_the_token() -> void:
	var n: Node3D = auto_free(Node3D.new())   # not parked
	assert_bool(RadialMenuController._wound_token_active(1, n)).is_true()


func test_parked_model_never_shows_the_token() -> void:
	var n: Node3D = auto_free(Node3D.new())
	n.set_meta("deleted", true)
	n.set_meta("dead_slot", 3)
	assert_bool(RadialMenuController._wound_token_active(1, n)).is_false()   # the J9 receiver fix
	assert_bool(RadialMenuController._wound_token_active(5, n)).is_false()


func test_unwounded_model_shows_no_token() -> void:
	var n: Node3D = auto_free(Node3D.new())
	assert_bool(RadialMenuController._wound_token_active(0, n)).is_false()


func test_deleted_without_dead_slot_is_not_treated_as_parked() -> void:
	# A delete-hidden (not tray-parked) node lacks dead_slot, so it is NOT "parked" — a wounded such
	# model still shows its token (matches the J3 parked-model discriminator: deleted AND dead_slot).
	var n: Node3D = auto_free(Node3D.new())
	n.set_meta("deleted", true)
	assert_bool(RadialMenuController._wound_token_active(1, n)).is_true()
