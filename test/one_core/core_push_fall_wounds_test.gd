extends GdUnitTestSuite
## #3961 (found by FT-17): a model pushed off a ledge falls in the core - and its fall wounds must land on the table too, and
## online on the other table. Scene as FT-17: the drawn generated board 7 and its 6 in ledge; Target (4 models, Quality 6,
## Defense 6, Tough 1) on the high cell next to the edge, Gunners (Quality 2, 4 shots) on the ground east of it. Tray seed 7:
## 2 lost, Shaken, push die 4; the model nearest the edge is dragged 2 in east over the edge; the fall dice 5 2 2 1 6 6 give
## 3 wounds, so the Tough 1 model dies.
## Real: the main scene, the drawn board, the card's Activate, the radial targeting and click, the core's volley / morale /
## push / fall, the "Push?" prompt, the table's own drag, the step landings, and (O) the wire the other table reads.

const INCH := 0.0254
const SEED := 7

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
	SoloHarness.generated_board(_t.main, 7, "")
	var ledge := SkirmishTable.ledge(7, 6.0)
	assert_array(ledge).override_failure_message("board 7 has a 6 in ledge").is_not_empty()
	_a = _t.unit("gff", 1, "Gunners", 1, 1, 0.0, 0.0, {"name": "Rifle", "range_in": 24, "attacks": 4, "count": 1, "rules": []})
	_a.unit_properties["quality"] = 2
	(_a.models[0] as ModelInstance).node.global_position = ledge[1] + Vector3(10.0 * INCH, 0, 0)
	_target = _t.unit("gff", 2, "Target", 4, 1, 0.0, 0.0)
	_target.unit_properties["quality"] = 6
	_target.unit_properties["defense"] = 6
	# 1 in bases, the edge 1.5 in east of the cell centre: every model is within a 2 in push of crossing it.
	var spots := [Vector3(0.9, 0, -0.55), Vector3(0.9, 0, 0.55), Vector3(-0.2, 0, -0.55), Vector3(-0.2, 0, 0.55)]
	for k in 4:
		(_target.models[k] as ModelInstance).node.global_position = ledge[0] + spots[k] * INCH


## The shot and the push 2 in east over the edge; returns the pushed model.
func _push_off(seat: String) -> ModelInstance:
	await _scene(seat)
	assert_bool(await _t.start(_a)).override_failure_message("Gunners start").is_true()
	_t.main.seed_tray_rng(SEED)
	# Every die rolls instant and seeded; the owner's questions are asked off the headless batch, as at a real table.
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
	var until := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < until and not (done[0] and _t.count("Push: Gunners") > 0):
		for c in _t.main.find_children("*", "PromptCard", false, false):
			var title := str((c as PromptCard).title)
			if title == "Push?" and not pushed_asked[0]:
				pushed_asked[0] = true
				SoloHarness.instant(_t.main, true)   # the push die and the fall dice roll seeded
				(c as PromptCard).resolve(true)
			elif title == "Place the rest":
				(c as PromptCard).resolve(false)
		if not CoreActivation.push_pick.is_empty() and moved == null:
			for m in _target.get_alive_models():
				if moved == null or (m as ModelInstance).node.global_position.x > moved.node.global_position.x:
					moved = m
			SoloHarness.instant(_t.main, true)
			await _t.drop(moved, moved.node.global_position + Vector3(2.0 * INCH, 0, 0), 2.0)
		await _t.runner.simulate_frames(1)
	_t.main.battle_log.entry_added.disconnect(batch)
	SoloHarness.instant(_t.main, true)
	assert_int(_t.count("Push: Gunners rolls 4 and pushes Target model 1 2.0 in off a 6 in drop - it falls, [5, 2, 2, 1, 6, 6], 3 wounds on 1-3")) \
		.override_failure_message("the fall line: %s" % [_t.lines]).is_equal(1)
	return moved


func test_hot_seat_the_fall_kills_the_pushed_model_on_the_table(timeout := 180000) -> void:
	var moved := await _push_off("H")
	assert_bool(moved.is_alive).override_failure_message("3 wounds kill the Tough 1 model on the table: %s" % [_t.lines]).is_false()
	assert_int(_target.get_alive_count()).override_failure_message("one model of Target is left: %s" % [_t.lines]).is_equal(1)


func test_online_the_other_table_gets_the_death(timeout := 180000) -> void:
	var moved := await _push_off("O")
	assert_bool(moved.is_alive).override_failure_message("dead on the host's table: %s" % [_t.lines]).is_false()
	var sent := _t.net.wire.filter(func(f: Dictionary) -> bool:
		return str(f["t"]) == "rpc" and str(f["p"]["m"]) == "sync_model_wounds" and str(f["p"]["a"][0]) == _target.unit_id \
			and int(f["p"]["a"][1]) == moved.model_index and not bool(f["p"]["a"][3]))
	assert_int(sent.size()).override_failure_message("the guest's table hears the pushed model died: %s" % [_t.net.wire]).is_greater_equal(1)
