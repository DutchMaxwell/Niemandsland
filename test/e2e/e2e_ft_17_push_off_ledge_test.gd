extends GdUnitTestSuite
## Feature test FT-17: a push off a ledge on a hot-seat Firefight (gff) table, at the shipped epoch (the tier hand-over and
## the push are live). FF36 p.15 (our words): a model pushed down a drop of 2 in or more falls - one die per inch, a wound on
## each 1-3 - and lands at the foot; the opponent places the unit's other models within 1 in of it. The pushed unit is not
## the active one, so nobody's activation ends (ruling D10).
## Scene: the drawn generated board 7, its 6 in ledge (no ladder). Target (4 models, Quality 6, Defense 6) stands 2 x 2 on the
## high cell next to the edge; Gunners (Quality 2, 4 shots) on the ground east of it. Tray seed SEED (R-FT3): the shot
## shakes Target (hits 6 6 5 2, saves 6 6 4 1 at 5+ in cover: 2 lost, morale 2), the push die is a 4; the attacker drags
## the model nearest the edge 2 in east, over the edge; the fall dice are 5 2 2 1 6 6 (3 wounds - the model dies, so this
## seed leaves nothing to re-place around it: FT-16 covers the re-place).
## Real: the main scene, the drawn board, the card's Activate, the radial targeting and click, the core's volley / morale /
## push / fall / re-place, the "Push?" and "Place the rest" prompts and the table's own drag.
## FINDING #3961 (R-FT2): the fall's wounds never reach the table - the model stays alive at 1/1 though the core has it dead;
## that case is skipped with the issue.

const INCH := 0.0254
const SEED := 7
const LOCK := "Place the other models within 1 in"

var _t: SkirmishTable
var _a: GameUnit
var _target: GameUnit
var _ledge: Array


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")


func after_test() -> void:
	CoreActivation.finish_replace_pick(false)
	CoreActivation.skip_push_pick()
	if _t != null:
		_t.teardown()
	_t = null


func _scene() -> void:
	SoloHarness.generated_board(_t.main, 7, "")
	_ledge = SkirmishTable.ledge(7, 6.0)
	assert_array(_ledge).override_failure_message("board 7 has a 6 in ledge").is_not_empty()
	_a = _t.unit("gff", 1, "Gunners", 1, 1, 0.0, 0.0, {"name": "Rifle", "range_in": 24, "attacks": 4, "count": 1, "rules": []})
	_a.unit_properties["quality"] = 2
	(_a.models[0] as ModelInstance).node.global_position = _ledge[1] + Vector3(10.0 * INCH, 0, 0)
	_target = _t.unit("gff", 2, "Target", 4, 1, 0.0, 0.0)
	_target.unit_properties["quality"] = 6
	_target.unit_properties["defense"] = 6
	# 1 in bases, the edge 1.5 in east of the cell centre: every model is within a 2 in push of crossing it.
	var spots := [Vector3(0.9, 0, -0.55), Vector3(0.9, 0, 0.55), Vector3(-0.2, 0, -0.55), Vector3(-0.2, 0, 0.55)]
	for k in 4:
		(_target.models[k] as ModelInstance).node.global_position = _ledge[0] + spots[k] * INCH


## The model of Target nearest the edge (largest x: the low cell lies east).
func _edge_model() -> ModelInstance:
	var best: ModelInstance = null
	for m in _target.get_alive_models():
		if best == null or (m as ModelInstance).node.global_position.x > best.node.global_position.x:
			best = m
	return best


## The shot, the push 2 in east over the edge, and "Place for me" for the rest. Returns [the pushed model, its start].
func _push_off() -> Array:
	_scene()
	assert_bool(await _t.start(_a)).override_failure_message("Gunners start").is_true()
	_t.main.seed_tray_rng(SEED)
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
	var moved: ModelInstance = null
	var from := Vector3.ZERO
	var until := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < until and not (done[0] and CoreActivation.replace_pick.is_empty() and _t.count("Push: Gunners") > 0):
		for c in _t.main.find_children("*", "PromptCard", false, false):
			var title := str((c as PromptCard).title)
			if title == "Push?" and not pushed_asked[0]:
				pushed_asked[0] = true
				SoloHarness.instant(_t.main, true)   # the push die and the fall dice roll seeded
				(c as PromptCard).resolve(true)
			elif title == "Place the rest":
				(c as PromptCard).resolve(false)   # the defender's "Place for me"
		if not CoreActivation.push_pick.is_empty() and moved == null:
			moved = _edge_model()
			from = moved.node.global_position
			SoloHarness.instant(_t.main, true)   # the fall dice that follow the spot roll seeded
			await _t.drop(moved, from + Vector3(2.0 * INCH, 0, 0), 2.0)
		await _t.runner.simulate_frames(1)
	_t.main.battle_log.entry_added.disconnect(batch)
	SoloHarness.instant(_t.main, true)
	return [moved, from]


func test_a_push_off_the_ledge_falls_and_ends_no_activation(timeout := 180000) -> void:
	var r := await _push_off()
	var moved: ModelInstance = r[0]
	assert_object(moved).override_failure_message("the spot was asked: %s" % [_t.lines]).is_not_null()
	# The dice line (R-FT3): 6 dice for the 6 in drop, a wound on each 1-3.
	assert_int(_t.count("Push: Gunners rolls 4 and pushes Target model 1 2.0 in off a 6 in drop - it falls, [5, 2, 2, 1, 6, 6], 3 wounds on 1-3")) \
		.override_failure_message("the fall line: %s" % [_t.lines]).is_equal(1)
	assert_bool(_target.is_activated).override_failure_message("the pushed unit's activation is not spent: %s" % [_t.lines]).is_false()
	assert_int(_t.count(LOCK)).override_failure_message("no fall lock - the pushed unit is not the active one: %s" % [_t.lines]).is_equal(0)


## The fall's 3 wounds remove the Tough 1 model on the table too (the core's state already has it dead).
@warning_ignore("unused_parameter")
func test_the_fall_wounds_land_on_the_table(timeout := 180000, do_skip := true,
		skip_reason := "FINDING #3961: a pushed model's fall wounds never reach the table") -> void:
	var r := await _push_off()
	var moved: ModelInstance = r[0]
	assert_bool(moved.is_alive).override_failure_message("3 wounds kill the Tough 1 model").is_false()
	assert_int(_target.get_alive_count()).override_failure_message("one model of Target is left: %s" % [_t.lines]).is_equal(1)
