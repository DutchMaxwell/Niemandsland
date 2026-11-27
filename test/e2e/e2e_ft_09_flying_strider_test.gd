extends GdUnitTestSuite
## Feature test FT-9: Flying and Strider at a jump, Firefight (gff), hot-seat table, PINNED to the pending epoch 106 (R-FT1).
## FF36 p.14 l.1218-1220 (Flying ignores terrain and jumps), p.15 l.1311-1312 (Strider halves the jump dice, rounding up).
## Scene: the drawn generated board 7, its 6 in ledge (no ladder); a 1-model Tough(3) unit with Flying, a twin with
## Strider, each dropping to the foot. Tray seed 6: Strider's three dice 5 3 3 (all 2+).
## The flyer's drop writes no line at all (the rule is applied silently): kept as a skipped case under #3858.
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


func test_flying_passes_a_6_in_drop_without_dice(timeout := 120000) -> void:
	var u := await _jump(7, 6.0, 6, ["Flying"])
	await _t.end(u)
	assert_float((u.models[0] as ModelInstance).node.global_position.y / INCH).override_failure_message("at the foot").is_equal_approx(0.0, 0.05)
	assert_int(_t.lines.filter(func(l: String) -> bool: return l.begins_with("Jump:") or l.begins_with("Falling:")).size()) \
		.override_failure_message("no dice for a flyer: %s" % [_t.lines]).is_equal(0)
	assert_int((u.models[0] as ModelInstance).wounds_current).is_equal(3)


@warning_ignore("unused_parameter")
func test_a_line_names_flying_at_the_drop(timeout := 120000, do_skip := true,
		skip_reason := "FINDING #3858 (comment): a rule applied on a player's move writes no line - Flying at a jump") -> void:
	await _jump(7, 6.0, 6, ["Flying"])
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.find("Flying") != -1)).override_failure_message("%s" % [_t.lines]).is_true()


func test_strider_rolls_half_the_jump_dice(timeout := 120000) -> void:
	var u := await _jump(7, 6.0, 6, ["Strider"])
	await _t.end(u)
	assert_int(_t.count("Jump: Leaper model 1 jumps down 6 in - [5, 3, 3] at 2+ - it lands")) \
		.override_failure_message("6 / 2 = 3 dice: %s" % [_t.lines]).is_equal(1)
