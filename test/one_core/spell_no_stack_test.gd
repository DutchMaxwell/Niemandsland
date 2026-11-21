extends GdUnitTestSuite
## EPOCH_95_PARITY_BATCH (95; lead ruling 20.11., GF 3.6 "Rules priority & stacking effects": the same spell does not stack): a second identical record of a
## spell on the same unit refreshes the first and adds none, with a line and no second token. Core twin `sim::tray_spell_effect`. Three casts of an Indirect mark leave one
## record from 95 (the table's own exchange spend then says "consumed" once and leaves nothing), three below it. Real: the main scene, the table's token / record placement,
## `_solo_consume_once_mods`. Constructed: two plain units.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf", "faction_folder": "robot_legions", "rules": []}
const MARK := {"kind": "debuff", "grants_rule": "Indirect", "beneficiary": "attackers", "duration": "once", "once": true}

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


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## `casts` casts of the mark on a foe, then one exchange of an attacker at it: the records on the foe after the casts, the lines said and the records left.
func _run(epoch: int, casts: int) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 3, "x_in": -6.0}, true), {})
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 3, "x_in": 6.0}, true), {})
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	for i in casts:
		_main._solo_place_spell_tokens("Triangulation Bots", [foe], MARK)
	var records := (_main._solo_spell_mods.get(foe.get_instance_id(), []) as Array).size()
	_main._solo_consume_once_mods(att, foe, false)
	_main.battle_log.entry_added.disconnect(tap)
	var out := {"records": records, "left": (_main._solo_spell_mods.get(foe.get_instance_id(), []) as Array).size(),
		"consumed": lines.filter(func(l: String) -> bool: return l.contains("consumed (applies once)")).size(),
		"refreshed": lines.filter(func(l: String) -> bool: return l.contains("does not stack")).size(),
		"placed": lines.filter(func(l: String) -> bool: return l.contains("token placed")).size(),
		"active": lines.filter(func(l: String) -> bool: return l.contains("is ACTIVE")).size()}
	for gu in [att, foe]:
		_main._solo_spell_mods.erase((gu as GameUnit).get_instance_id())
	_main._solo_spell_tokens_active.clear()
	Harness._free_units(_main, [att, foe])
	await get_tree().process_frame
	return out


## RED before the fix: three records after three casts at 95. Green: one, said placed / ACTIVE once and refreshed twice, one spend sentence, nothing left.
## Below the pending epoch the old stacking replays (three records, no refresh line); a single cast is the same at both.
func test_three_casts_of_one_spell_leave_one_record_from_the_pending_epoch() -> void:
	var gate: int = AiActRecorder.EPOCH_95_PARITY_BATCH
	var now := await _run(gate, 3)
	assert_dict(now).override_failure_message("at the gate: %s" % str(now)).is_equal({"records": 1, "left": 0, "consumed": 1, "refreshed": 2, "placed": 1, "active": 1})
	var old := await _run(gate - 1, 3)
	assert_int(int(old["records"])).override_failure_message("below the gate the stacking replays: %s" % str(old)).is_equal(3)
	assert_int(int(old["refreshed"])).is_equal(0)
	var one := await _run(gate, 1)
	assert_dict(one).is_equal({"records": 1, "left": 0, "consumed": 1, "refreshed": 0, "placed": 1, "active": 1})
