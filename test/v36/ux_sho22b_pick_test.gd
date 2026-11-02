extends GdUnitTestSuite
## Rules 3.6 wave, row UX-SHO22b-PICK: a HUMAN bearer picks the Precision Tag target and the
## stack-vs-spread itself. The table used to run the AI policy for both sides, so the game chose
## for the player. From EPOCH_73_V36 the dialog seam `_solo_ask_precision_tag_pick` is asked; the
## AI keeps its policy untouched, and below 73 the single auto target stays.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A bearer with the shipped gf/jackals entry: Precision Tag is a "Utility Buff" there.
func _tagger(pid: int, x: int) -> GameUnit:
	var u := _reg(E2EBoot.make_unit(_main, pid, "Marksman" if pid == 1 else "Nightmare", [Vector3.ZERO]))
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "jackals"
	u.unit_properties["special_rules"] = ["Precision Tag(%d)" % x]
	return u


func _foe(pid: int, pos: Vector3, models: int) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(pos + Vector3(0.02 * INCH * i, 0, 0))
	return _reg(E2EBoot.make_unit(_main, pid, "Alpha" if models > 1 else "Bravo", positions))


func _tokens(u: GameUnit) -> int:
	return int(u.unit_properties.get("tag_markers", 0))


## Stub the dialog seam: records every ask and returns `answer` unchanged.
func _stub_pick(answer: Dictionary) -> Array:
	var asked: Array = []
	_main.set("_solo_ask_precision_tag_pick", func(member: GameUnit, legal: Array, markers: int) -> Dictionary:
		asked.append({"member": member, "legal": legal, "markers": markers})
		var a := answer.duplicate()
		if int(a.get("target_index", -1)) >= 0:
			a["target"] = legal[int(a["target_index"])]
		return a)
	return asked


func test_human_bearer_is_asked_and_its_stack_target_wins_at_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var tagger := _tagger(1, 2)
	var alpha := _foe(2, Vector3(10.0 * INCH, 0, 0), 2)
	var bravo := _foe(2, Vector3(10.0 * INCH, 0, 6.0 * INCH), 1)
	var asked := _stub_pick({"target_index": 1, "spread": false})
	_main._solo_apply_precision_tag(tagger)
	assert_int(asked.size()).override_failure_message("the human bearer must be asked exactly once").is_equal(1)
	var legal: Array = asked[0]["legal"]
	assert_int(legal.size()).override_failure_message("both legal enemies reach the dialog").is_equal(2)
	assert_int(asked[0]["markers"]).override_failure_message("the marker count reaches the dialog").is_equal(2)
	assert_int(_tokens(alpha)).override_failure_message("the AI pick is not used").is_equal(0)
	assert_int(_tokens(bravo)).override_failure_message("both tokens follow the player's target").is_equal(2)


func test_human_bearer_spread_choice_is_honoured_at_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var tagger := _tagger(1, 2)
	var alpha := _foe(2, Vector3(10.0 * INCH, 0, 0), 2)
	var bravo := _foe(2, Vector3(10.0 * INCH, 0, 6.0 * INCH), 1)
	_stub_pick({"target_index": 1, "spread": true})
	_main._solo_apply_precision_tag(tagger)
	assert_int(_tokens(alpha)).override_failure_message("one token on each unit").is_equal(1)
	assert_int(_tokens(bravo)).override_failure_message("one token on each unit").is_equal(1)


func test_ai_bearer_is_never_asked_at_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var tagger := _tagger(2, 2)
	var alpha := _foe(1, Vector3(10.0 * INCH, 0, 0), 2)
	var bravo := _foe(1, Vector3(10.0 * INCH, 0, 6.0 * INCH), 1)
	var asked := _stub_pick({"target_index": 1, "spread": false})
	_main._solo_apply_precision_tag(tagger)
	assert_int(asked.size()).override_failure_message("the AI keeps its own policy, no dialog").is_equal(0)
	assert_int(_tokens(alpha)).override_failure_message("today's AI spread is unchanged").is_equal(1)
	assert_int(_tokens(bravo)).is_equal(1)


func test_human_bearer_is_never_asked_below_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var tagger := _tagger(1, 2)
	var alpha := _foe(2, Vector3(10.0 * INCH, 0, 0), 2)
	var bravo := _foe(2, Vector3(10.0 * INCH, 0, 6.0 * INCH), 1)
	var asked := _stub_pick({"target_index": 1, "spread": false})
	_main._solo_apply_precision_tag(tagger)
	assert_int(asked.size()).override_failure_message("rules 3.5 has no spread prompt").is_equal(0)
	assert_int(_tokens(alpha)).override_failure_message("3.5: every marker on the toughest unit").is_equal(2)
	assert_int(_tokens(bravo)).is_equal(0)
