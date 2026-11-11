extends GdUnitTestSuite

const Boot := preload("res://test/e2e/e2e_boot.gd")
## One roll line of the battle log: "<unit> rolls N <rule> dice (T+) — M wounds ignored".
const ROLL_LINE := "rolls (\\d+) (.+?) di(?:e|ce) \\((\\d)\\+\\) — (\\d+) wound"
var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests - restore
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


func _unit(rules: Array, system: String, faction: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "rule_%d" % rules.size()
	u.unit_properties = {"player_id": 2, "name": "Fixture", "quality": 4, "defense": 2,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var model := ModelInstance.new()
	model.is_alive = true
	u.models.append(model)
	return u


## Lands `regenable` + `bypassed` wounds on a unit with `rules` and returns what landed plus the log text.
func _land(rules: Array, faction: String, regenable: int, bypassed: int, epoch: int = AiActRecorder.EPOCH_73_V36) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	var unit := _unit(rules, "gf", faction)
	_main.seed_tray_rng(1300)
	var start: int = _main.battle_log.entries().size()
	var landed: int = await _main._solo_ignore_wounds(unit, regenable, bypassed)
	var text := ""
	for entry in _main.battle_log.entries().slice(start):
		text += str(entry["text"]) + "\n"
	return {"landed": landed, "text": text, "rolls": _roll_lines(text)}


func _roll_lines(text: String) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string(ROLL_LINE)
	for m in re.search_all(text):
		out.append({"count": int(m.get_string(1)), "rule": m.get_string(2),
			"target": int(m.get_string(3)), "ignored": int(m.get_string(4))})
	return out


## B: a bypass skips only the roll of the rule named Regeneration - Self-Repair still rolls, and says so.
func test_a_bypass_still_meets_a_rule_not_named_regeneration() -> void:
	var r: Dictionary = await _land(["Self-Repair"], "robot_legions", 0, 60)
	var text: String = r["text"]
	assert_str(text).contains("self-repair di")
	assert_str(text).contains("ignore only Regeneration — Self-Repair still rolls")
	assert_str(text).not_contains("no self-repair roll")
	assert_int((r["rolls"] as Array).size()).is_equal(1)
	assert_int(int(r["landed"])).is_equal(60 - int(r["rolls"][0]["ignored"]))


## CONTROL (the check can fail): against the rule really named Regeneration the bypass still skips the roll.
func test_a_bypass_skips_only_the_regeneration_roll() -> void:
	var r: Dictionary = await _land(["Regeneration"], "robot_legions", 0, 60)
	var text: String = r["text"]
	assert_str(text).not_contains("regeneration di")
	assert_str(text).contains("ignore Regeneration — no regeneration roll")
	assert_int(int(r["landed"])).is_equal(60)


## B with a second rule: the Regeneration roll is skipped for the bypassed wounds, Plaguebound still rolls them.
func test_a_bypass_against_regeneration_and_plaguebound_rolls_plaguebound_only() -> void:
	var r: Dictionary = await _land(["Regeneration", "Plaguebound"], "plague_disciples", 0, 60)
	assert_str(str(r["text"])).contains("no regeneration roll")
	var rolls: Array = r["rolls"]
	assert_int(rolls.size()).is_equal(1)
	assert_str(str(rolls[0]["rule"])).is_equal("Plaguebound")
	assert_int(int(rolls[0]["count"])).is_equal(60)
	assert_int(int(rolls[0]["target"])).is_equal(6)


## A: two differently named rules each roll, one after the other, on the wounds still standing.
func test_two_named_rules_roll_one_after_the_other() -> void:
	var r: Dictionary = await _land(["Regeneration", "Plaguebound"], "plague_disciples", 60, 0)
	var rolls: Array = r["rolls"]
	assert_int(rolls.size()).is_equal(2)
	assert_str(str(rolls[0]["rule"])).is_equal("regeneration")
	assert_int(int(rolls[0]["target"])).is_equal(5)
	assert_int(int(rolls[0]["count"])).is_equal(60)
	assert_str(str(rolls[1]["rule"])).is_equal("Plaguebound")
	assert_int(int(rolls[1]["target"])).is_equal(6)
	assert_int(int(rolls[1]["count"])).is_equal(60 - int(rolls[0]["ignored"]))
	assert_int(int(r["landed"])).is_equal(int(rolls[1]["count"]) - int(rolls[1]["ignored"]))


## A: forms of ONE rule stay one roll, at the best target.
func test_forms_of_one_rule_roll_once() -> void:
	var r: Dictionary = await _land(["Plaguebound", "Enhanced Plaguebound"], "plague_disciples", 60, 0)
	var rolls: Array = r["rolls"]
	assert_int(rolls.size()).is_equal(1)
	assert_int(int(rolls[0]["target"])).is_equal(5)


## Below the rules 3.6 epoch the fold stays: a bypass skips Self-Repair too, as it always did.
func test_epoch_72_keeps_the_fold() -> void:
	var r: Dictionary = await _land(["Self-Repair"], "robot_legions", 0, 60, AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var text: String = r["text"]
	assert_str(text).not_contains("self-repair di")
	assert_str(text).contains("no self-repair roll")
	assert_int(int(r["landed"])).is_equal(60)
