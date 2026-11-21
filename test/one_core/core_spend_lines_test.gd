extends GdUnitTestSuite
## gaps3 item 3: the core's exchange spends EVERY once-record of a spell stacked on a unit (a cast that was not used up in an earlier
## round stays; soak game 16 at the pending epoch held three "Triangulation Bots" on one foe), and its delta names each one in `buffs_spent`.
## The landing spent them with one table spend per entry and said "\"X\" on U is consumed (applies once)" three times; the table's own
## exchange spend says it once (the effect applies once). `_land_buffs` now spends the whole delta in one call and the spend says each
## sentence once. Real: the main scene, the table's records and log, `CoreActivation._land_buffs`. Constructed: a unit and its records.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf", "faction_folder": "robot_legions", "rules": []}
const MARK := {"grants_rule": "Indirect", "beneficiary": "attackers", "duration": "once", "quiet": true}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Records `spells` (names, in order, one record each) on a fresh unit, lands a delta naming `spent` ([name, scope] entries) and returns the
## "consumed" sentences said and the records left.
func _land(spells: Array, spent: Array) -> Dictionary:
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 3, "x_in": 6.0}, true), {})
	for s in spells:
		_main._solo_record_spell_mod(foe, str(s), MARK)
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	CoreActivation._land_buffs(_main, foe, {"buffs_spent": spent})
	_main.battle_log.entry_added.disconnect(tap)
	var left := (_main._solo_spell_mods.get(foe.get_instance_id(), []) as Array).size()
	_main._solo_spell_mods.erase(foe.get_instance_id())
	Harness._free_units(_main, [foe])
	return {"said": lines.filter(func(l: String) -> bool: return l.contains("consumed (applies once)")), "left": left}


## RED before the fix: three equal records and three spent entries say the sentence three times. Green: once, and the records are all gone
## (the core spent them all). Controls: one record, one sentence; two different spells, one sentence each.
func test_stacked_equal_records_spent_together_say_their_sentence_once() -> void:
	# Identical records stack only below the epoch 95 batch (SPELL_NO_STACK: from 95 a second identical record refreshes the first), so this pins the
	# stacked reading a replay under an older stamp still plays.
	var epoch_before := AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_95_PARITY_BATCH - 1
	var three := _land(["Triangulation Bots", "Triangulation Bots", "Triangulation Bots"], [["Triangulation Bots", ""], ["Triangulation Bots", ""], ["Triangulation Bots", ""]])
	assert_array(three["said"]).override_failure_message("three stacked records: %s" % str(three)).has_size(1)
	assert_int(int(three["left"])).override_failure_message("the core spent all three").is_equal(0)
	var one := _land(["Triangulation Bots"], [["Triangulation Bots", ""]])
	assert_array(one["said"]).has_size(1)
	assert_int(int(one["left"])).is_equal(0)
	var two := _land(["Triangulation Bots", "Surge Mark"], [["Triangulation Bots", ""], ["Surge Mark", ""]])
	assert_array(two["said"]).override_failure_message("two spells: %s" % str(two)).has_size(2)
	var part := _land(["Triangulation Bots", "Triangulation Bots"], [["Triangulation Bots", ""]])
	assert_array(part["said"]).has_size(1)
	assert_int(int(part["left"])).override_failure_message("a delta naming one spend leaves the other record").is_equal(1)
	AiActRecorder.rules_epoch = epoch_before
