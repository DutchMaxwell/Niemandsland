extends GdUnitTestSuite
## Feature test FT-15: pushing, the attacker's side, on a hot-seat Firefight (gff) table. FF36 p.15 l.1266-1268 (our words):
## when an attack leaves a unit Shaken, the attacker may try to push it - one die, on 4+ the attacker moves one of its
## models up to 2 in; on 1-3 nothing moves. No push is offered against a unit the attack did not shake.
## Scene: Gunners (one model, Quality 2, 4 shots) 12 in from Target (3 models, Quality 6, Defense 6, Tough 1). Dice by tray
## seed (R-FT3, scanned 0..63 in the game's order: hits, saves, morale, push):
##   seed 7  - hits 6 2 5 6, saves 4 6 1 6: 2 lost, morale 2 (Shaken), push die 4;
##   seed 19 - hits 1 4 2 3, saves 6 5 4: 2 lost, morale 5 (Shaken), push die 3;
##   seed 0  - hits 6 4 3 1, saves 4 1 6: 2 lost, morale 6 (passes): no push.
## Real: the main scene, the card's Activate, the radial targeting and click, the core's volley / morale / push, the
## "Push?" prompt, the 2 in ring and the table's own drag of the target model (its drop is the core's push_to answer).
## A lone pushed survivor asks nobody to "Place the rest" (#3943 fixed: it was asked with nothing to place).

const INCH := 0.0254
const PUSH_SEED := 7
const FAIL_SEED := 19
const STEADY_SEED := 0

var _t: SkirmishTable
var _a: GameUnit
var _target: GameUnit


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")


func after_test() -> void:
	CoreActivation.skip_push_pick()
	if _t != null:
		_t.teardown()
	_t = null


func _scene() -> void:
	_a = _t.unit("gff", 1, "Gunners", 1, 1, -12.0, 0.0, {"name": "Rifle", "range_in": 24, "attacks": 4, "count": 1, "rules": []})
	_a.unit_properties["quality"] = 2
	_target = _t.unit("gff", 2, "Target", 3, 1, 0.0, 0.0)
	_target.unit_properties["quality"] = 6
	_target.unit_properties["defense"] = 6


## Gunners shoot Target on `seed_value`. `answer` = "push" / "no" for the "Push?" prompt; each entry of `drags` (inches east
## of the survivor's spot) is one drag of the target's surviving model while the spot is asked. Returns whether "Push?" was
## asked and the survivor's x in inches before the shot's push.
func _shot(seed_value: int, answer: String, drags: Array) -> Dictionary:
	_scene()
	assert_bool(await _t.start(_a)).override_failure_message("Gunners start").is_true()
	_t.main.seed_tray_rng(seed_value)
	# Every die rolls instant and seeded (R-FT3); the owner's questions are asked off the headless batch, as at a real
	# table (a batch table never asks): off after the morale die, on again for the push die, off after it for the spot.
	var asked := [false]
	var placed_asked := [false]
	var batch := func(e: Dictionary) -> void:
		var text := str(e["text"])
		if text.begins_with("P2: ") or (asked[0] and text.begins_with("P1: ")):
			SoloHarness.instant(_t.main, false)
	_t.main.battle_log.entry_added.connect(batch)
	var done := [false]
	(func() -> void:
		await _t.aim(_a, _target)
		done[0] = true).call()
	var left := drags.duplicate()
	var until := Time.get_ticks_msec() + 30000   # a time budget: the prompts wait on real-time pacing, not on frames
	while not done[0] and Time.get_ticks_msec() < until:
		for c in _t.main.find_children("*", "PromptCard", false, false):
			if str((c as PromptCard).title) == "Push?" and not asked[0]:
				asked[0] = true
				SoloHarness.instant(_t.main, true)   # the push die rolls seeded
				(c as PromptCard).resolve(answer == "push")
			elif str((c as PromptCard).title) == "Place the rest":
				placed_asked[0] = true
				(c as PromptCard).resolve(false)   # the defender's "Place for me"
		if not CoreActivation.push_pick.is_empty() and not left.is_empty():
			var m: ModelInstance = _target.get_alive_models()[0]
			var to: Vector3 = m.node.global_position + Vector3(float(left.pop_front()) * INCH, 0, 0)
			await _t.drop(m, to, to.distance_to(m.node.global_position) / INCH)
		await _t.runner.simulate_frames(1)
	var settle := Time.get_ticks_msec() + 10000   # a pushed shot ends with the core's push line
	while asked[0] and answer == "push" and _t.count("Push: Gunners") == 0 and Time.get_ticks_msec() < settle:
		await _t.runner.simulate_frames(1)
	_t.main.battle_log.entry_added.disconnect(batch)
	SoloHarness.instant(_t.main, true)
	assert_bool(done[0]).override_failure_message("the shot did not end: %s" % [_t.lines]).is_true()
	return {"asked": asked[0], "placed_asked": placed_asked[0]}


func _survivor_x_in() -> float:
	return (_target.get_alive_models()[0] as ModelInstance).node.global_position.x / INCH


func test_a_4_lets_the_attacker_move_one_model_up_to_2_in(timeout := 180000) -> void:
	var r := await _shot(PUSH_SEED, "push", [1.9])
	assert_bool(r["asked"]).override_failure_message("Push? asked after the shot: %s" % [_t.lines]).is_true()
	assert_int(_t.count("Target fails morale — Shaken")).override_failure_message("Shaken: %s" % [_t.lines]).is_equal(1)
	assert_int(_t.count("Push: Gunners rolls 4 and pushes Target model")).override_failure_message("the 4: %s" % [_t.lines]).is_equal(1)
	assert_float(_survivor_x_in()).override_failure_message("moved 1.9 in east: %s" % [_t.lines]).is_equal_approx(1.9, 0.02)


func test_a_spot_past_2_in_is_said_and_asked_again(timeout := 180000) -> void:
	var r := await _shot(PUSH_SEED, "push", [2.5, 1.0])
	assert_bool(r["asked"]).is_true()
	assert_int(_t.count("Push: 2.5 in is over the 2 in")).override_failure_message("the refusal, once: %s" % [_t.lines]).is_equal(1)
	assert_float(_survivor_x_in()).override_failure_message("the second spot stands: %s" % [_t.lines]).is_equal_approx(1.0, 0.02)


func test_a_3_moves_nothing(timeout := 180000) -> void:
	var r := await _shot(FAIL_SEED, "push", [1.5])
	assert_bool(r["asked"]).is_true()
	assert_int(_t.count("Push: Gunners rolls 3 to push Target - no push on 1-3")).override_failure_message("the 3: %s" % [_t.lines]).is_equal(1)
	assert_float(_survivor_x_in()).override_failure_message("nothing moved: %s" % [_t.lines]).is_equal_approx(0.0, 0.02)


func test_a_steady_target_gets_no_push(timeout := 180000) -> void:
	var r := await _shot(STEADY_SEED, "push", [1.5])
	assert_int(_t.count("Target passes morale")).override_failure_message("steady: %s" % [_t.lines]).is_equal(1)
	assert_bool(r["asked"]).override_failure_message("no Push? against a steady unit: %s" % [_t.lines]).is_false()
	assert_float(_survivor_x_in()).is_equal_approx(0.0, 0.02)


## The book places "any other models" of the pushed unit (FF36 p.15 l.1268-1269): a lone survivor leaves nothing to
## place, so its owner is asked nothing.
func test_a_lone_pushed_model_asks_nobody_to_place_the_rest(timeout := 180000) -> void:
	var r := await _shot(PUSH_SEED, "push", [1.9])
	assert_int(_t.count("Push: Gunners rolls 4 and pushes Target model")).is_equal(1)
	assert_bool(r["placed_asked"]).override_failure_message("Place the rest asked with nothing to place: %s" % [_t.lines]).is_false()
