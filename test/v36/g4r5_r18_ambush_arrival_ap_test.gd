extends GdUnitTestSuite
## G4 round 5, row R18 F-AMBUSH-ARRIVAL-AP (rules 3.6, EPOCH_73_V36 only; below 73 byte-identical): the army-book rule
## "Ambushing Piercing Shot" gives the unit's SHOOTING AP(+1) in the round it arrives from Ambush through that rule.
## The core already folds it per shooting member (`ambush_arrival_ap`, stamp == round, shooting only); the table never
## did, neither in the AI's volley nor in the human's (gf_023/13: core save 6+, table save 5+). From 73 both table
## volleys add the +1 per shot member and the battle log names the book rule.
## The recorded act closes only with the next re-recording; these tests drive the live volley seams.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := 5
const RULE := "Ambushing Piercing Shot"
const ARRIVAL_LINE := "Ambushing Piercing Shot: Trackers shoots with AP(+1) in its arrival round"
const ROUND := 2

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = ROUND
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The parity act's weapon: a rifle with AP(1), plain (no Takedown pick to answer).
func _rifle() -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Test Sniper Rifle"
	w.range_value = 24
	w.attacks = 8
	w.count = 1
	w.special_rules.assign(["AP(1)"])
	return w


func _unit(pid: int, unit_name: String, positions: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	for i in u.models.size():
		(u.models[i] as ModelInstance).model_index = i
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A shooter the way the game delivers it: the book rule on its rule line and the arrival stamp the Ambush arrival
## writes (`ambush_arrived_round`); a Defense 4+ squad stands 12" away in the open.
func _fixture(rule: bool, arrived_round: int) -> Dictionary:
	var shooter := _unit(1, "Trackers", [Vector3.ZERO])
	shooter.unit_properties["quality"] = 2
	shooter.unit_properties["game_system"] = "gf"
	if rule:
		shooter.unit_properties["special_rules"] = [RULE]
	shooter.unit_properties["ambush_arrived_round"] = arrived_round
	var src := OPRApiClient.OPRUnit.new()
	src.weapons.assign([_rifle()])
	shooter.source_type = "opr"
	shooter.source_data = src
	var positions: Array = []
	for i in 4:
		positions.append(Vector3(12.0 * INCH, 0, 0.02 * i))
	var squad := _unit(2, "Infected Soldiers", positions)
	return {"shooter": shooter, "squad": squad}


func _ai_volley(epoch: int, rule: bool, arrived_round: int) -> String:
	AiActRecorder.rules_epoch = epoch
	var f := _fixture(rule, arrived_round)
	var shots: Array = []
	for p in AiShooting.profiles_in_range([_rifle()], 0.0):
		shots.append({"member": f["shooter"], "quality": 2, "alive": 1, "max": 1, "reach": 24, "profile": p})
	_main.seed_tray_rng(SEED)
	await _main._solo_resolve_ai_volley(f["shooter"], f["squad"], shots)
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	return text


func _human_volley(epoch: int, rule: bool, arrived_round: int) -> String:
	AiActRecorder.rules_epoch = epoch
	var f := _fixture(rule, arrived_round)
	_main.seed_tray_rng(SEED)
	await _main._run_human_shooting(f["shooter"], f["squad"])
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	return text


## EPOCH_72 leg (declared first: gdUnit drops tests declared after a failing one): below 73 the arrival round adds
## nothing, byte for byte.
func test_arrival_round_adds_no_ap_at_epoch_72(timeout := 120000) -> void:
	var text: String = await _ai_volley(AiActRecorder.EPOCH_72_PLAYTEST_RULES, true, ROUND)
	assert_str(text).override_failure_message("fixture: the weapon's own AP(1) must reach the save line (log: %s)" % text) \
		.contains("saves on 5+ (Def 4+, AP 1)")
	assert_str(text).override_failure_message("EPOCH_72 keeps the old merge (log: %s)" % text).not_contains(ARRIVAL_LINE)


## The parity act's shape, AI side: the rule plus an arrival stamp equal to the current round -> the save line reads
## AP 2 (Def 4+ -> 6+) and the log names the book rule.
func test_ai_volley_adds_ap_one_in_the_arrival_round_at_epoch_73(timeout := 120000) -> void:
	var text: String = await _ai_volley(AiActRecorder.EPOCH_73_V36, true, ROUND)
	assert_str(text) \
		.override_failure_message("F-AMBUSH-ARRIVAL-AP — the AI volley must shoot AP 2 in the arrival round (log: %s)" % text) \
		.contains("saves on 6+ (Def 4+, AP 2)")
	assert_str(text).override_failure_message("rules-must-log — name the book rule (log: %s)" % text) \
		.contains(ARRIVAL_LINE)


## CONTROL: arrived one round earlier -> AP 1 and no line.
func test_ai_volley_adds_nothing_one_round_after_arrival_at_epoch_73(timeout := 120000) -> void:
	var text: String = await _ai_volley(AiActRecorder.EPOCH_73_V36, true, ROUND - 1)
	assert_str(text).override_failure_message("a stale arrival stamp adds nothing (log: %s)" % text) \
		.contains("saves on 5+ (Def 4+, AP 1)")
	assert_str(text).not_contains(ARRIVAL_LINE)


## CONTROL: the stamp alone is not the rule — a unit that arrived this round WITHOUT the book rule shoots AP 1.
func test_ai_volley_needs_the_rule_not_just_the_stamp_at_epoch_73(timeout := 120000) -> void:
	var text: String = await _ai_volley(AiActRecorder.EPOCH_73_V36, false, ROUND)
	assert_str(text).override_failure_message("no rule, no AP (log: %s)" % text).contains("saves on 5+ (Def 4+, AP 1)")
	assert_str(text).not_contains(ARRIVAL_LINE)


## The human volley reads the same rule (the report names both seams).
func test_human_volley_adds_ap_one_in_the_arrival_round_at_epoch_73(timeout := 120000) -> void:
	var text: String = await _human_volley(AiActRecorder.EPOCH_73_V36, true, ROUND)
	assert_str(text) \
		.override_failure_message("F-AMBUSH-ARRIVAL-AP — the human volley must shoot AP 2 in the arrival round (log: %s)" % text) \
		.contains("saves on 6+ (Def 4+, AP 2)")
	assert_str(text).override_failure_message("rules-must-log — name the book rule (log: %s)" % text) \
		.contains(ARRIVAL_LINE)


## CONTROL, human side: arrived one round earlier -> AP 1 and no line.
func test_human_volley_adds_nothing_one_round_after_arrival_at_epoch_73(timeout := 120000) -> void:
	var text: String = await _human_volley(AiActRecorder.EPOCH_73_V36, true, ROUND - 1)
	assert_str(text).override_failure_message("a stale arrival stamp adds nothing (log: %s)" % text) \
		.contains("saves on 5+ (Def 4+, AP 1)")
	assert_str(text).not_contains(ARRIVAL_LINE)
