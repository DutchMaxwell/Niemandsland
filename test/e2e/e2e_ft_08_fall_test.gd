extends GdUnitTestSuite
## Feature test FT-8: falling, Firefight (gff), hot-seat table, PINNED to the pending epoch 106 (R-FT1). FF36 p.15
## l.1304-1308 and the example l.1314-1315: a model that falls rolls one die per inch fallen, each 1-3 a wound, is placed
## within 2 in of the bottom, the unit's other models within 1 in of it, and the activation ends at once.
## Scene: the drawn generated board 7, its 6 in ledge (no ladder); a 3-model Tough(3) unit on the high cell, model 1 drops
## to the foot. Tray seed 0 (R-FT3 scan): jump dice 6 4 3 1 4 1 (a 1: it falls), fall dice 6 6 6 6 2 4 (one 1-3: 1 wound).
## Green: the fall line, its dice and wound, the End lock, "Place for me" lifts it. FINDING #3872 (R-FT2): the player's
## OWN placement of models 2 and 3 within 1 in is checked as a move (a jump line, then "moved 9.4\" - the Advance
## allowance is 6.0\"") - kept as a skipped case.
## Real: the main scene, the drawn board, the card's Activate / End and its lock, the table's drop check and drop door.

const INCH := 0.0254
const LOCK := "Place the other models within 1 in of Leaper's model that fell"

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _fall() -> Array:
	_t.need_epoch(106)
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
	var m1 := u.models[0] as ModelInstance
	await _t.drop(m1, l[1], 3.0)
	await _t.press(u, "End activation")   # the jump rolls on the move's close; the fall locks the End
	assert_int(_t.count("Falling: Leaper model 1 falls 6 in")).override_failure_message("the fall line: %s" % [_t.lines]).is_equal(1)
	assert_bool(_t.lines.any(func(l2: String) -> bool: return l2.begins_with("Falling:") and l2.ends_with("[6, 6, 6, 6, 2, 4], 1 wound on 1-3"))) \
		.override_failure_message("6 dice, 1 wound: %s" % [_t.lines]).is_true()
	assert_int(m1.wounds_max - m1.wounds_current).override_failure_message("one 1-3 face, one wound").is_equal(1)
	var at: Vector3 = m1.node.global_position
	assert_float(Vector2(at.x - l[1].x, at.z - l[1].z).length() / INCH).override_failure_message("within 2 in of the foot").is_less_equal(2.0 + 0.6)
	assert_int(_t.count(LOCK)).override_failure_message("End is locked: %s" % [_t.lines]).is_equal(1)
	assert_bool(u.is_activated).is_false()
	return [u, m1, at]


func test_a_fall_wounds_on_1_to_3_and_locks_the_end(timeout := 180000) -> void:
	var f := await _fall()
	var u: GameUnit = f[0]
	await _t.press(u, "Place for me")   # the core's placer (D14) lifts the lock; the hand path is the skipped case below
	await _t.press(u, "End activation")
	assert_bool(u.is_activated).override_failure_message("End spends it after the placing: %s" % [_t.lines]).is_true()
	assert_int(_t.count(LOCK)).override_failure_message("no second lock").is_equal(1)


@warning_ignore("unused_parameter")
func test_the_owner_places_the_others_by_hand(timeout := 180000, do_skip := true,
		skip_reason := "FINDING #3872: a hand placement after a fall is checked as a move (jump, 6 in cap)") -> void:
	var f := await _fall()
	var u: GameUnit = f[0]
	var m1: ModelInstance = f[1]
	var at: Vector3 = f[2]
	var r := SoloController.model_base_radius_m(m1)
	for k in [1, 2]:   # the player's own drags down beside model 1, 0.5 in base to base
		var side := -1.0 if k == 1 else 1.0
		var to := Vector3(at.x, at.y, at.z + side * (2.0 * r + 0.5 * INCH))
		assert_bool(await _t.drop(u.models[k] as ModelInstance, to, 3.0)).override_failure_message("model %d's drag: %s" % [k + 1, _t.lines]).is_true()
	for k in [1, 2]:
		var q: Vector3 = (u.models[k] as ModelInstance).node.global_position
		assert_float((Vector2(q.x, q.z).distance_to(Vector2(at.x, at.z)) - 2.0 * r) / INCH).is_less_equal(1.0 + 1e-3)
	await _t.press(u, "End activation")
	assert_bool(u.is_activated).override_failure_message("End spends it now: %s" % [_t.lines]).is_true()
	assert_int(_t.count(LOCK)).override_failure_message("no second lock").is_equal(1)
