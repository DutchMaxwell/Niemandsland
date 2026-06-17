extends GdUnitTestSuite
## Army-sync idempotency + restore-lock (0.3.4.4). The host army reaches a guest via BOTH the
## join state-sync AND the per-army broadcast. The receiver must therefore (a) spawn each model
## exactly once — find_by_network_id rebinds a duplicate instead of doubling it — and (b) never
## let the two restores interleave, or one path's _loaded_game_units.clear() wipes the other
## mid-restore (the "Could not restore OPR unit" / missing-models bug). begin/end_restore is the
## async mutex that serializes them.


func test_find_by_network_id_returns_matching_child() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	var a := Node3D.new()
	a.set_meta("network_id", 42)
	om.add_child(a)
	var b := Node3D.new()
	b.set_meta("network_id", 7)
	om.add_child(b)
	assert_object(om.find_by_network_id(42)).is_same(a)
	assert_object(om.find_by_network_id(7)).is_same(b)


func test_find_by_network_id_missing_and_negative_return_null() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	var a := Node3D.new()
	a.set_meta("network_id", 42)
	om.add_child(a)
	assert_object(om.find_by_network_id(999)).is_null()
	assert_object(om.find_by_network_id(-1)).is_null()


func test_restore_lock_acquire_and_release() -> void:
	var sm: SaveManager = auto_free(SaveManager.new())
	assert_bool(sm._restore_in_flight).is_false()
	await sm.begin_restore()
	assert_bool(sm._restore_in_flight).is_true()
	sm.end_restore()
	assert_bool(sm._restore_in_flight).is_false()


func test_reset_restore_lock_force_releases() -> void:
	var sm: SaveManager = auto_free(SaveManager.new())
	await sm.begin_restore()
	assert_bool(sm._restore_in_flight).is_true()
	sm.reset_restore_lock()
	assert_bool(sm._restore_in_flight).is_false()


## The core guarantee: while path A holds the lock, a second acquirer must NOT proceed until
## A releases — this is what stops the two army-delivery paths from clobbering each other.
func test_restore_lock_serializes_second_acquirer() -> void:
	var sm: SaveManager = auto_free(SaveManager.new())
	await sm.begin_restore()  # path A holds the lock
	var second_done := [false]
	var acquire_second := func() -> void:
		await sm.begin_restore()
		second_done[0] = true
	acquire_second.call()  # starts; blocks inside begin_restore awaiting the unlock signal
	await get_tree().process_frame
	assert_bool(second_done[0]).is_false()  # still blocked while A holds the lock
	sm.end_restore()  # release -> the second acquirer proceeds
	await get_tree().process_frame
	assert_bool(second_done[0]).is_true()
	sm.end_restore()
