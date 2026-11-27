extends GdUnitTestSuite
## Feature test FT-7: jumping down, Firefight (gff), hot-seat table, PINNED to the pending epoch 106 (jump and fall reach
## the core from PENDING_EPOCH_CORE_TIERS on; the table ships 103 - R-FT1, recorded in SkirmishTable.pins). FF36 p.15
## l.1276-1284 and the example l.1292-1293: a drop of up to 3 in is regular movement; up to 6 in is a jump - one die per
## inch, all 2+ or the model falls; the jump does not count toward the move.
## Scene: the drawn generated board 7 (3 in and 6 in ledges, no ladder) and board 2 (a 9 in ledge); a 1-model Tough(3)
## unit on the high cell drops to the low one. Tray seed 6 (R-FT3 scan): the six jump dice 5 3 3 6 3 5 - it lands.
## Real: the main scene, the drawn board, the card's Activate / End, the table's drop check (the core's move check) and
## the drop door.

const INCH := 0.0254
var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _jump(seed_board: int, drop_in: float, seed_tray: int, rules: Array = []) -> GameUnit:
	_t.need_epoch(106)
	SoloHarness.generated_board(_t.main, seed_board, "")
	var l := SkirmishTable.ledge(seed_board, drop_in)
	assert_array(l).override_failure_message("a %.0f in ledge on board %d" % [drop_in, seed_board]).is_not_empty()
	var u := _t.unit("gff", 1, "Leaper", 1, 3, 0.0, 0.0, {}, rules)
	var keep := _t.unit("gff", 1, "Reserve", 1, 1, 0.0, 0.0)
	var foe := _t.unit("gff", 2, "Mark", 1, 1, 0.0, 0.0)
	(keep.models[0] as ModelInstance).node.global_position = l[1] + Vector3(-20 * INCH, 0, 0)
	(foe.models[0] as ModelInstance).node.global_position = l[1] + Vector3(-20 * INCH, 0, 20 * INCH)
	var m := u.models[0] as ModelInstance
	m.node.global_position = l[0]
	assert_bool(await _t.start(u)).is_true()
	_t.main.seed_tray_rng(seed_tray)
	u.unit_properties["moved_round"] = 1
	await _t.drop(m, l[1], 3.0)
	return u


func test_a_3_in_drop_is_regular_movement(timeout := 120000) -> void:
	var u := await _jump(7, 3.0, 0)
	await _t.end(u)
	assert_int(_t.lines.filter(func(l: String) -> bool: return l.begins_with("Jump:")).size()).override_failure_message("no jump: %s" % [_t.lines]).is_equal(0)
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.find("Drop 3 in - a drop is regular movement") != -1)) \
		.override_failure_message("the drop line: %s" % [_t.lines]).is_true()
	assert_int((u.models[0] as ModelInstance).wounds_current).is_equal(3)


func test_a_6_in_jump_rolls_6_dice_and_lands(timeout := 120000) -> void:
	var u := await _jump(7, 6.0, 6)
	await _t.end(u)
	assert_int(_t.count("Jump: Leaper model 1 jumps down 6 in - [5, 3, 3, 6, 3, 5] at 2+ - it lands")) \
		.override_failure_message("one Jump line, 6 dice, all 2+: %s" % [_t.lines]).is_equal(1)
	assert_int(_t.lines.filter(func(l: String) -> bool: return l.begins_with("Falling:")).size()).is_equal(0)
	assert_int((u.models[0] as ModelInstance).wounds_current).is_equal(3)


func test_a_9_in_drop_is_refused(timeout := 120000) -> void:
	var u := await _jump(2, 9.0, 0)
	assert_float((u.models[0] as ModelInstance).node.global_position.y / INCH).override_failure_message("stays up: %s" % [_t.lines]).is_equal_approx(9.0, 0.05)
	assert_int(_t.count("Leaper: cliff: no ladder here")).override_failure_message("one line says why: %s" % [_t.lines]).is_equal(1)
