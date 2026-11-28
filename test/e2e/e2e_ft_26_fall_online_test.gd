extends GdUnitTestSuite
## Feature test FT-26: a fall online, Firefight (gff), PINNED to the pending epoch 106 (R-FT1). An agreed Automatic room,
## this table the host on slot 1 and the faller's owner, the REAL NetworkManager with only its transport swapped. FF36
## p.15 l.1304-1308: the fallen model is placed at the foot, the others within 1 in of it, and the activation ends.
## Scene: FT-8's - board 7's 6 in ledge, a 3-model Tough(3) unit, tray seed 0 (the jump fails, one wound in the fall).
## Asserted (D-27c Q3): while the fall lock stands the turn token does not pass - the locked End sends the fall's lines
## and its landing but no `sync_turn_state` and no activation fact; "Place for me" then End sends ONE move batch whose
## three positions equal the table's to 1 mm, the placer's line, then the token [2].
## Not built: the mirror into a second scene booted as slot 2 (one scene per process here).
## Real: the main scene, the drawn board, the card's Activate / End / Place for me, the table's drop check and drop door.

const INCH := 0.0254

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "O")
	_t.need_epoch(106)


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _rpcs(from: int, method: String) -> Array:
	return _t.net.wire.slice(from).filter(func(f: Dictionary) -> bool: return str(f["t"]) == "rpc" and str(f["p"]["m"]) == method)


func test_the_token_waits_for_the_fall_and_the_placement_travels(timeout := 120000) -> void:
	SoloHarness.generated_board(_t.main, 7, "")
	var l := SkirmishTable.ledge(7, 6.0)
	var u := _t.unit("gff", 1, "Leaper", 3, 3, 0.0, 0.0)
	var keep := _t.unit("gff", 1, "Reserve", 1, 1, 0.0, 0.0)
	var foe := _t.unit("gff", 2, "Mark", 1, 1, 0.0, 0.0)
	(keep.models[0] as ModelInstance).node.global_position = l[1] + Vector3(-20 * INCH, 0, 0)
	(foe.models[0] as ModelInstance).node.global_position = l[1] + Vector3(-20 * INCH, 0, 20 * INCH)
	var spots := [Vector3.ZERO, Vector3(-1.1 * INCH, 0, -0.6 * INCH), Vector3(-1.1 * INCH, 0, 0.6 * INCH)]
	for k in 3:
		(u.models[k] as ModelInstance).node.global_position = l[0] + spots[k]
	assert_bool(await _t.start(u)).is_true()
	_t.main.seed_tray_rng(0)
	u.unit_properties["moved_round"] = 1
	await _t.drop(u.models[0], l[1], 3.0)
	var n0 := _t.net.wire.size()
	await _t.press(u, "End activation")
	assert_bool(u.is_activated).override_failure_message("locked: %s" % [_t.lines]).is_false()
	assert_bool(_rpcs(n0, "sync_log_event").any(func(f: Dictionary) -> bool: return str(f["p"]["a"][1]).begins_with("Falling: Leaper model 1 falls 6 in"))) \
		.override_failure_message("the fall line travels").is_true()
	assert_int(_rpcs(n0, "sync_turn_state").size() + _rpcs(n0, "sync_unit_activation").size()) \
		.override_failure_message("no token, no activation fact while locked: %s" % [_t.net.wire.slice(n0)]).is_equal(0)
	var n1 := _t.net.wire.size()
	await _t.press(u, "Place for me")
	await _t.press(u, "End activation")
	assert_bool(u.is_activated).override_failure_message("End spends it: %s" % [_t.lines]).is_true()
	var moves := _rpcs(n1, "move_objects_batch_networked")
	assert_int(moves.size()).override_failure_message("one move batch: %s" % [_t.net.wire.slice(n1)]).is_equal(1)
	if moves.size() == 1:
		var a: Array = moves[0]["p"]["a"][0]
		for k in 3:
			var at: Vector3 = (u.models[k] as ModelInstance).node.global_position
			var i := a.find(int((u.models[k] as ModelInstance).node.get_meta("network_id")))
			assert_int(i).override_failure_message("model %d in the batch" % (k + 1)).is_greater_equal(0)
			if i >= 0:
				assert_float(Vector3(a[i + 1], a[i + 2], a[i + 3]).distance_to(at)).override_failure_message("model %d to 1 mm" % (k + 1)).is_less(0.001)
	var tokens := _rpcs(n1, "sync_turn_state")
	assert_int(tokens.size()).override_failure_message("the token passes after the placing").is_equal(1)
	assert_array(tokens[0]["p"]["a"] if not tokens.is_empty() else []).is_equal([2])
