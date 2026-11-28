extends GdUnitTestSuite
## GEN-1: on a generated board at the LIVE rules epoch a raised block stops sight. Tiefwerk seed 42 through the release
## door on a 4 x 4 ft hot-seat table; a gff shooter and its target stand on ground cells of one row with a block of 6 in
## or more between them: the core rolls no shot. The same distance down an open lane: the shot is fired.
## Red while the live epoch is below the tier epoch (106): the core saw no block and fired.

const INCH := 0.0254
const SEED := 42

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")
	_t.main.seed_tray_rng(0)
	await _t.table_feet(Vector2(4, 4))
	_t.reset()   # a resize puts the table back into deployment: play again


func after_test() -> void:
	if _t != null:
		_t.main.restore_generated_board({})
		await get_tree().process_frame
		_t.teardown()
	_t = null


## A pair of ground cells of one row, 3 to 7 cells apart: [row, from, to] with a block of >= 6 in between (`blocked`)
## or only ground between (an open lane), or [] when the board has none.
static func _lane(h: Array, blocked: bool) -> Array:
	for row in range(2, 14):
		for a in range(0, 13):
			for gap in range(3, 8):
				var b := a + gap
				if b > 15 or float(h[row * 16 + a]) != 0.0 or float(h[row * 16 + b]) != 0.0:
					continue
				var between: Array = range(a + 1, b).map(func(c: int) -> float: return float(h[row * 16 + c]))
				if blocked and between.any(func(v: float) -> bool: return v >= 6.0):
					return [row, a, b]
				if not blocked and between.all(func(v: float) -> bool: return v == 0.0):
					return [row, a, b]
	return []


func _fired() -> bool:
	return _t.lines.any(func(l: String) -> bool: return l.begins_with("Gunners fires Rifle at"))


func _shot_along(lane: Array) -> void:
	var x := func(c: int) -> float: return c * 3.0 + 1.5 - 24.0
	var z: float = lane[0] * 3.0 + 1.5 - 24.0
	var a := _t.unit("gff", 1, "Gunners", 1, 1, x.call(lane[1]), z, {"name": "Rifle", "range_in": 24, "attacks": 6, "count": 1, "rules": []})
	var target := _t.unit("gff", 2, "Mark", 1, 3, x.call(lane[2]), z)
	assert_bool(await _t.start(a)).override_failure_message("Start").is_true()
	await SoloHarness.shoot_from_above(_t.main, a, target)


@warning_ignore('unused_parameter')
func test_a_raised_block_stops_sight_and_an_open_lane_does_not(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded", timeout := 180000) -> void:
	assert_bool(_t.main.apply_generated_board(GeneratedBoard.resolve("tiefwerk", SEED))).override_failure_message("no board").is_true()
	var h: Array = AiActRecorder.tiers_of_board(_t.main.generated_board())["tiers"]["level_in"]
	var blocked := _lane(h, true)
	var open := _lane(h, false)
	assert_bool(blocked.is_empty() or open.is_empty()).override_failure_message("seed 42 has no blocked / open lane").is_false()
	if blocked.is_empty() or open.is_empty():
		return
	await _shot_along(blocked)
	assert_bool(_fired()).override_failure_message("live epoch %d: shot across a raised block %s: %s" % [
		AiActRecorder.rules_epoch, blocked, _t.lines]).is_false()
	_t.reset()
	await _shot_along(open)
	assert_bool(_fired()).override_failure_message("open lane %s not shot: %s" % [open, _t.lines]).is_true()
