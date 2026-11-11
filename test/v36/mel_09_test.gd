extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-09: from rules epoch 73 (the core's EPOCH_73_V36) a fatigued striker still
## hits on its unmodified 6s, but those sixes no longer fire any special rule (Rending's extra AP, Surge's
## bonus hits, ...). A Shaken unit's strike-back counts as fatigued, so the same holds there. Epoch 72
## keeps today's reading: the sixes fire their rules. The core twin is
## core/nml-core/src/tests/dice/v36_melee.rs, `mod mel_09`.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := 909

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
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A Quality 4 model with one 12-attack melee weapon carrying `rule`.
func _striker(rule: String) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Guards", [Vector3.ZERO])
	(u.models[0] as ModelInstance).model_index = 0
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Claw"
	w.range_value = 0
	w.attacks = 12
	w.count = 1
	w.special_rules = [rule]
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## An AI unit of 10 in reach: its saves roll in the tray.
func _foe() -> GameUnit:
	var spots: Array = []
	for i in 10:
		spots.append(Vector3(0.5 * INCH, 0, (float(i) - 4.5) * 0.3 * INCH))
	var foe := E2EBoot.make_unit(_main, 2, "Grunts", spots)
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	return foe


## One strike-back (no charge) at `epoch` on tray seed 909 by a striker that is fatigued (or Shaken when
## `shaken`): {"sixes": unmodified 6s in the hit roll, "log": the battle log as one text}.
func _strike(epoch: int, rule: String, shaken: bool) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	var striker := _striker(rule)
	if shaken:
		striker.is_shaken = true
	else:
		striker.is_fatigued = true
	var foe := _foe()
	_main._solo_dice_trace_enabled = true
	_main.solo_controller.decision_log.clear()
	_main.seed_tray_rng(SEED)
	await _main._solo_melee_strike_phase(striker, foe, false, 0)   # 0 = SoloStrike.ALL
	var sixes := -1
	for rec in _main.solo_controller.decision_log:
		if str((rec as Dictionary).get("kind", "")) == "dice" and str(rec["roll_kind"]) == "attack":
			sixes = Array(rec["faces"]).count(6)
			break
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	await E2EBoot.settle(get_tree())
	return {"sixes": sixes, "log": text}


func _hits_line(sixes: int) -> String:
	return "Guards strikes with Claw at Grunts — %d hit%s" % [sixes, ("" if sixes == 1 else "s")]


func test_fatigued_rending_sixes_still_rend_at_epoch_72() -> void:
	var r: Dictionary = await _strike(AiActRecorder.EPOCH_72_PLAYTEST_RULES, "Rending", false)
	assert_int(int(r["sixes"])).override_failure_message("seed 909 must roll a six to hit").is_greater(0)
	assert_str(str(r["log"])) \
		.override_failure_message("epoch 72: a fatigued striker's sixes still rend (log: %s)" % r["log"]) \
		.contains("Rending: ")
	assert_str(str(r["log"])).not_contains("trigger no special rules")


func test_fatigued_rending_sixes_hit_but_do_not_rend_at_epoch_73() -> void:
	var r: Dictionary = await _strike(AiActRecorder.EPOCH_73_V36, "Rending", false)
	var sixes := int(r["sixes"])
	assert_int(sixes).override_failure_message("seed 909 must roll a six to hit").is_greater(0)
	assert_str(str(r["log"])) \
		.override_failure_message("epoch 73: every six still hits (log: %s)" % r["log"]) \
		.contains(_hits_line(sixes))
	assert_str(str(r["log"])) \
		.override_failure_message("epoch 73: a fatigued striker's sixes fire no Rending (log: %s)" % r["log"]) \
		.not_contains("Rending: ")
	assert_str(str(r["log"])) \
		.override_failure_message("rules-must-log: the muted sixes name the rule (log: %s)" % r["log"]) \
		.contains("Fatigued: Guards — %d unmodified 6" % sixes)


func test_shaken_strike_back_sixes_still_surge_at_epoch_72() -> void:
	var r: Dictionary = await _strike(AiActRecorder.EPOCH_72_PLAYTEST_RULES, "Surge", true)
	var sixes := int(r["sixes"])
	assert_int(sixes).override_failure_message("seed 909 must roll a six to hit").is_greater(0)
	assert_str(str(r["log"])) \
		.override_failure_message("epoch 72: a Shaken strike-back's sixes still surge (log: %s)" % r["log"]) \
		.contains("Surge: +%d hit" % sixes)
	assert_str(str(r["log"])).contains(_hits_line(2 * sixes))


func test_shaken_strike_back_sixes_hit_but_do_not_surge_at_epoch_73() -> void:
	var r: Dictionary = await _strike(AiActRecorder.EPOCH_73_V36, "Surge", true)
	var sixes := int(r["sixes"])
	assert_int(sixes).override_failure_message("seed 909 must roll a six to hit").is_greater(0)
	assert_str(str(r["log"])) \
		.override_failure_message("epoch 73: a Shaken strike-back's sixes fire no Surge (log: %s)" % r["log"]) \
		.not_contains("Surge: ")
	assert_str(str(r["log"])) \
		.override_failure_message("epoch 73: the sixes still hit, one hit each (log: %s)" % r["log"]) \
		.contains(_hits_line(sixes))
	assert_str(str(r["log"])).contains("Fatigued: Guards — %d unmodified 6" % sixes)
