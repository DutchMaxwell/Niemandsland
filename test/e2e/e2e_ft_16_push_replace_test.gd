extends GdUnitTestSuite
## Feature test FT-16: after a push, the DEFENDER places the pushed unit's other models, on a Firefight (gff) table at the
## shipped epoch. FF36 p.15 l.1268-1269 (our words): the opponent places any other models of the pushed unit within 1 in of
## the pushed one (D-29-Q3-FINAL: "I place" on the defender's own table, or "Place for me" = the core's placer).
## Scene: Gunners (one model, Quality 2, 4 shots) 12 in from Target (6 models, Quality 6, Defense 6, Tough 1). Tray seed 9
## (R-FT3, scanned 0..63 in the game's order): hits 1 6 2 6, saves 1 3 4 -> 3 lost (3/6: a morale test), morale 1
## (Shaken), push die 4; the attacker drags Target's first survivor 1.9 in east, its two others stay. Then:
##   H (hot-seat): P2's "Place the rest" - I place (drags within 1 in, Enter) / Place for me / a drag left 1.5 in away;
##   S (vs the AI): Target is AI-owned - the core's placer at once, no prompt.
## Real: the main scene, the card's Activate, the radial targeting and click, the core's volley / morale / push / re-place,
## the "Push?" and "Place the rest" prompts, the table's own drags (the drop door) and Enter.

const INCH := 0.0254
const SEED := 9

var _t: SkirmishTable
var _a: GameUnit
var _target: GameUnit


func after_test() -> void:
	CoreActivation.finish_replace_pick(false)
	CoreActivation.skip_push_pick()
	if _t != null:
		_t.teardown()
	_t = null


func _scene(seat: String) -> void:
	_t = await SkirmishTable.boot(self, seat)
	_a = _t.unit("gff", 1, "Gunners", 1, 1, -12.0, 0.0, {"name": "Rifle", "range_in": 24, "attacks": 4, "count": 1, "rules": []})
	_a.unit_properties["quality"] = 2
	_target = _t.unit("gff", 2, "Target", 6, 1, 0.0, 0.0)
	_target.unit_properties["quality"] = 6
	_target.unit_properties["defense"] = 6


## The shot, the push (1.9 in east) and the defender's answer: `place` = [] for "Place for me", else one gap (inches, south
## of the pushed model, base to base) per ask for the second survivor - the third goes north at 0.5 in on the first ask.
## Returns whether "Place the rest" was asked.
func _push(seat: String, place: Array) -> bool:
	await _scene(seat)
	assert_bool(await _t.start(_a)).override_failure_message("Gunners start").is_true()
	_t.main.seed_tray_rng(SEED)
	# Every die rolls instant and seeded (R-FT3); the owners' questions are asked off the headless batch, as at a real table:
	# off after the failed morale test, on again for the push die, off after its line (P1 / You) for the spot and re-place.
	var pushed_asked := [false]
	var batch := func(e: Dictionary) -> void:
		var text := str(e["text"])
		if text.contains("fails morale") or (pushed_asked[0] and (text.begins_with("P1: ") or text.begins_with("You: "))):
			SoloHarness.instant(_t.main, false)
	_t.main.battle_log.entry_added.connect(batch)
	var done := [false]
	(func() -> void:
		await _t.aim(_a, _target)
		done[0] = true).call()
	var asked := false
	var spot_given := false
	var gaps := place.duplicate()
	var until := Time.get_ticks_msec() + 30000   # a time budget: the prompts wait on real-time pacing, not on frames
	while Time.get_ticks_msec() < until and not (done[0] and CoreActivation.replace_pick.is_empty() and _t.count("Push: Gunners") > 0):
		for c in _t.main.find_children("*", "PromptCard", false, false):
			var title := str((c as PromptCard).title)
			if title == "Push?" and not pushed_asked[0]:
				pushed_asked[0] = true
				SoloHarness.instant(_t.main, true)   # the push die rolls seeded
				(c as PromptCard).resolve(true)
			elif title == "Place the rest":
				asked = true
				(c as PromptCard).resolve(not gaps.is_empty())
		if not CoreActivation.push_pick.is_empty() and not spot_given:
			spot_given = true
			var m: ModelInstance = _target.get_alive_models()[0]
			await _t.drop(m, m.node.global_position + Vector3(1.9 * INCH, 0, 0), 1.9)
		if not CoreActivation.replace_pick.is_empty() and not gaps.is_empty():
			var alive := _target.get_alive_models()
			var at: Vector3 = (alive[0] as ModelInstance).node.global_position
			var r := SoloController.model_base_radius_m(alive[0] as ModelInstance)
			await _t.drop(alive[1] as ModelInstance, at + Vector3(0, 0, 2 * r + float(gaps.pop_front()) * INCH), 2.0)
			if _distance_in(2) > 1.0:
				await _t.drop(alive[2] as ModelInstance, at - Vector3(0, 0, 2 * r + 0.5 * INCH), 2.0)
			CoreActivation.finish_replace_pick(true)
		await _t.runner.simulate_frames(1)
	_t.main.battle_log.entry_added.disconnect(batch)
	SoloHarness.instant(_t.main, true)
	assert_int(_t.count("Push: Gunners rolls 4 and pushes Target model")).override_failure_message("the push: %s" % [_t.lines]).is_equal(1)
	return asked


## Base to base, in inches, from survivor `k` (alive order) to the pushed model (alive 0).
func _distance_in(k: int) -> float:
	var alive := _target.get_alive_models()
	var a: Vector3 = (alive[0] as ModelInstance).node.global_position
	var b: Vector3 = (alive[k] as ModelInstance).node.global_position
	return (Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) - 2.0 * SoloController.model_base_radius_m(alive[0] as ModelInstance)) / INCH


func test_hot_seat_the_defender_places_the_rest_itself(timeout := 180000) -> void:
	var asked := await _push("H", [0.5])
	assert_bool(asked).override_failure_message("P2 is asked: %s" % [_t.lines]).is_true()
	for k in [1, 2]:
		assert_float(_distance_in(k)).override_failure_message("survivor %d within 1 in: %s" % [k, _t.lines]).is_less_equal(1.0 + 1e-3)
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.contains("the owner placed model"))) \
		.override_failure_message("the line names the owner's placing: %s" % [_t.lines]).is_true()


func test_hot_seat_place_for_me_is_the_core_placer(timeout := 180000) -> void:
	var asked := await _push("H", [])
	assert_bool(asked).is_true()
	for k in [1, 2]:
		assert_float(_distance_in(k)).override_failure_message("survivor %d within 1 in: %s" % [k, _t.lines]).is_less_equal(1.0 + 1e-3)
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.contains("placed within 1 in of it"))) \
		.override_failure_message("the placer's line: %s" % [_t.lines]).is_true()


func test_hot_seat_a_spot_past_1_in_is_refused_and_asked_again(timeout := 180000) -> void:
	var asked := await _push("H", [1.5, 0.3])
	assert_bool(asked).is_true()
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.begins_with("Push: model") and l.ends_with("stands more than 1 in from the pushed model"))) \
		.override_failure_message("the 1.5 in spot refused: %s" % [_t.lines]).is_true()
	assert_float(_distance_in(1)).override_failure_message("the second spot stands: %s" % [_t.lines]).is_equal_approx(0.3, 0.05)


func test_vs_the_ai_the_ai_defender_takes_the_core_placer_at_once(timeout := 180000) -> void:
	var asked := await _push("S", [0.5])
	assert_bool(asked).override_failure_message("no prompt for the AI's unit: %s" % [_t.lines]).is_false()
	for k in [1, 2]:
		assert_float(_distance_in(k)).override_failure_message("survivor %d within 1 in: %s" % [k, _t.lines]).is_less_equal(1.0 + 1e-3)
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.contains("placed within 1 in of it"))) \
		.override_failure_message("the placer's line: %s" % [_t.lines]).is_true()
