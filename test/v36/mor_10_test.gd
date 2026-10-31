extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-10: from EPOCH_73_V36 a friendly unit within 6" of a not-Shaken Tough(9)+ Hero may
## test morale on that Hero's Quality. The Hero is its own unit (a Tough(9)+ Hero cannot be joined), so the
## reading walks the friendly units by distance, base edge to base edge (SoloController.nearest_melee_gap_in,
## the measure the Spell Conduit reading uses). The core's twin in core/nml-core/src/tests/sim/v36_morale.rs
## pins the same 5" / 7" cases. Below 73 the unit keeps its own Quality.

const MainScript := preload("res://scripts/main.gd")
const M := 0.0254
const BASE_MM := 50   # 1" radius like the core fixture, so a centre gap of (edge gap + 2") is the edge gap

var _uid := 0
var _saved_epoch := 0


func before_test() -> void:
	_saved_epoch = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func after_test() -> void:
	AiActRecorder.rules_epoch = _saved_epoch


func _unit(pid: int, unit_name: String, quality: int, rules: Array, x_in: float) -> GameUnit:
	var u := GameUnit.new()
	_uid += 1
	u.unit_id = "mor10_%d" % _uid
	u.unit_properties = {"player_id": pid, "name": unit_name, "quality": quality, "defense": 4,
		"special_rules": rules, "base_size_round": BASE_MM}
	var m := ModelInstance.new()
	m.is_alive = true
	m.unit = u
	var n := Node3D.new()
	add_child(n)
	n.global_position = Vector3(x_in * M, 0.0, 0.0)
	m.node = n
	u.models.append(m)
	return u


## A bare main with a Q5 squad (player 1, at x = 0) and a Q3 Tough(9) Hero `gap_in` base-edge inches away.
## `hero_rules` bends what kind of Hero it is; the tests bend side, state and Quality on the returned units.
func _table(gap_in: float, hero_rules: Array = ["Hero", "Tough(9)"]) -> Dictionary:
	var squad := _unit(1, "Squad", 5, [], 0.0)
	var hero := _unit(1, "Warlord", 3, hero_rules, gap_in + 2.0)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {squad.unit_id: squad, hero.unit_id: hero}
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	var main: Node3D = auto_free(MainScript.new())
	main.opr_army_manager = army
	main.solo_controller = solo
	var log_node: BattleLog = auto_free(BattleLog.new())
	main.battle_log = log_node
	return {"main": main, "squad": squad, "hero": hero, "solo": solo, "log": log_node}


func _quality(t: Dictionary) -> int:
	return int(t["main"]._solo_morale_quality(t["squad"]))


func _aura_lines(t: Dictionary) -> Array:
	var out: Array = []
	for e in (t["log"] as BattleLog)._entries:
		if str((e as Dictionary)["text"]).contains("lends its Quality"):
			out.append(str((e as Dictionary)["text"]))
	return out


## The fixture measures the gap it claims: the two engines agree on the 5" / 7" cases through this number.
func test_the_fixture_gap_is_the_base_edge_gap() -> void:
	var t := _table(5.0)
	assert_float(float(t["solo"].nearest_melee_gap_in(t["squad"], t["hero"]))).is_equal_approx(5.0, 0.05)


## RED on origin/main: the squad tests on its own Q5 whatever stands next to it.
func test_a_unit_five_inches_from_a_tough_nine_hero_tests_on_the_hero_quality() -> void:
	var t := _table(5.0)
	assert_int(_quality(t)).override_failure_message("5\" from a Tough(9) Hero: the Hero's Q3 is the test").is_equal(3)


## Control: below 73 the same table keeps the unit's own Quality.
func test_a_unit_five_inches_from_a_tough_nine_hero_keeps_its_quality_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_int(_quality(_table(5.0))).is_equal(5)


## Control: the aura ends past six inches.
func test_a_unit_seven_inches_from_the_hero_keeps_its_own_quality() -> void:
	assert_int(_quality(_table(7.0))).is_equal(5)


## Control: a Shaken Hero lends nothing.
func test_a_shaken_hero_lends_nothing() -> void:
	var t := _table(5.0)
	(t["hero"] as GameUnit).is_shaken = true
	assert_int(_quality(t)).is_equal(5)


## Control: the aura starts at Tough(9).
func test_a_tough_six_hero_lends_nothing() -> void:
	assert_int(_quality(_table(5.0, ["Hero", "Tough(6)"]))).is_equal(5)


## Control: only a Hero lends it.
func test_a_tough_nine_unit_that_is_no_hero_lends_nothing() -> void:
	assert_int(_quality(_table(5.0, ["Tough(9)"]))).is_equal(5)


## W1.3: a named hero is a Hero, so it lends the aura as well.
func test_a_unique_hero_lends_the_aura() -> void:
	assert_int(_quality(_table(5.0, ["Unique Hero", "Tough(9)"]))).is_equal(3)


## Control: an enemy Hero and a dead Hero lend nothing.
func test_an_enemy_hero_and_a_dead_hero_lend_nothing() -> void:
	var enemy := _table(5.0)
	(enemy["hero"] as GameUnit).unit_properties["player_id"] = 2
	assert_int(_quality(enemy)).override_failure_message("an enemy Hero").is_equal(5)
	var dead := _table(5.0)
	((dead["hero"] as GameUnit).models[0] as ModelInstance).is_alive = false
	assert_int(_quality(dead)).override_failure_message("a dead Hero").is_equal(5)


## Control: the unit keeps a better Quality of its own.
func test_a_unit_with_a_better_quality_than_the_hero_keeps_it() -> void:
	var t := _table(5.0)
	(t["squad"] as GameUnit).unit_properties["quality"] = 2
	assert_int(_quality(t)).is_equal(2)


## The human's once-per-unit choice covers the aura: "Use unit" switches it off for that unit.
func test_use_unit_switches_the_aura_off_for_a_human_unit() -> void:
	var t := _table(5.0)
	(t["squad"] as GameUnit).unit_properties["hero_tests_morale"] = false
	assert_int(_quality(t)).is_equal(5)


## The AI takes the better Quality automatically.
func test_the_ai_unit_takes_the_hero_quality_without_a_choice() -> void:
	var t := _table(5.0)
	t["main"].solo_ai_slots = {1: true}
	assert_int(_quality(t)).is_equal(3)


## RED on origin/main: a batch run records the once-per-unit answer for a unit an aura Hero helps,
## the same way it does for a joined Hero.
func test_batch_answers_the_hero_choice_for_a_unit_near_an_aura_hero() -> void:
	var t := _table(5.0)
	t["main"]._solo_batch = true
	await t["main"]._solo_ask_hero_morale_once(t["squad"])
	assert_bool((t["squad"] as GameUnit).unit_properties.has("hero_tests_morale")).is_true()


## Control: no Hero near, no choice to make.
func test_no_hero_choice_is_recorded_for_a_unit_far_from_the_aura_hero() -> void:
	var t := _table(7.0)
	t["main"]._solo_batch = true
	await t["main"]._solo_ask_hero_morale_once(t["squad"])
	assert_bool((t["squad"] as GameUnit).unit_properties.has("hero_tests_morale")).is_false()


## rules-must-log (RED on origin/main): the applied aura names the Hero and the unit.
func test_the_aura_writes_a_battle_log_line() -> void:
	var t := _table(5.0)
	_quality(t)
	var lines := _aura_lines(t)
	assert_int(lines.size()).override_failure_message("one aura line expected, got %s" % [lines]).is_equal(1)
	var line := str(lines[0]) if not lines.is_empty() else ""
	assert_str(line).contains("Warlord").contains("Tough 9+").contains("Squad").contains("Q3+")


## The aura line is silent when the Hero does not help.
func test_no_aura_line_is_written_when_the_hero_does_not_help() -> void:
	var t := _table(7.0)
	_quality(t)
	assert_array(_aura_lines(t)).is_empty()
