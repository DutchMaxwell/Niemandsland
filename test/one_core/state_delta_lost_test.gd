extends GdUnitTestSuite
## One core P4.0-4b: the (b) row of the state-delta inventory, fixed. A once buff is spent after a volley the core
## resolves.
##
## `buffs` was the one lost row: a plain activation spends the once record in the core (`sim.rs`,
## `spend_exchange_wounded`), but the live capture never sends the ledger (`plain.rs`, buffs start empty) and the table's
## own spend (`_solo_consume_once_mods`) was not called on the core path, so the record survived and the next table volley
## applied the once buff a second time. `CoreActivation.drive` now ends a `done` volley with the table's own spend
## (`spend_once_after_volley`); the table stays the owner of the ledger, the token, the log line and the wire message.
## The buffs here are recorded through the table's own recorder (`_solo_record_spell_mod`) and mirrored (`SOLO_SPELL_RECORDS_KEY`),
## the copy the capture reads, so the core's volley applies them as in play.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main.solo_ai_slots = {}
	CoreActivation._env = 1   # the flag ON for every case


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## The fixture of core_activation_test.gd: one plain 10-model shooter and one plain 5-model target.
func _volley_units() -> Array:
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main._solo_batch = true
	_main._solo_auto_saves = true
	var side := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
		"faction_folder": "robot_legions", "rules": []}
	var att := ParityTable._make_unit(_main, side.merged({"player": 2, "name": "Att", "models": 10, "x_in": 0.0}),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []})
	var foe := ParityTable._make_unit(_main, side.merged({"player": 1, "name": "Def", "models": 5, "x_in": 12.0}), {})
	return [att, foe]


## Records one spell effect on `gu` the way a cast does, then mirrors it into unit_properties (what the capture reads).
func _record(gu: GameUnit, effect: Dictionary) -> void:
	_main._solo_record_spell_mod(gu, "Fury", effect)
	_main._solo_mirror_spell_state()


## One core volley of `att` at `foe`; `shoot` false = an End without a shot (the intent names no target).
func _activate(att: GameUnit, foe: GameUnit, shoot := true) -> Dictionary:
	_main.seed_tray_rng(7)
	var t: Array = [{"t": "begin"}, {"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": foe.unit_id if shoot else ""}]
	var r: Dictionary = await CoreActivation.drive(_main, CoreActivation.capture(_main), att, t, true)
	assert_str(str(r["step"])).override_failure_message("the core's answer: %s" % r).is_equal("done")
	return r


func _records(gu: GameUnit) -> Array:
	return _main._solo_spell_mods.get(gu.get_instance_id(), [])


func test_a_once_buff_is_spent_by_the_core_activation() -> void:
	var units := _volley_units()
	var att: GameUnit = units[0]
	_record(att, {"modifier": {"hit_mod": 1}, "scope": "shooting", "duration": "once"})
	assert_dict(att.unit_properties[_main.SOLO_SPELL_RECORDS_KEY][0]).contains_keys(["hit_mod"])   # the capture sees it
	await _activate(att, units[1])
	assert_array(_records(att)).override_failure_message("the once buff was spent on the core path").is_empty()
	assert_bool(att.unit_properties.has(_main.SOLO_SPELL_RECORDS_KEY)).override_failure_message("the mirror follows").is_false()


func test_a_once_buff_on_the_target_is_spent_by_the_core_activation() -> void:
	var units := _volley_units()
	var foe: GameUnit = units[1]
	_record(foe, {"modifier": {"def_mod": 1}, "scope": "shooting", "duration": "once"})
	await _activate(units[0], foe)
	assert_array(_records(foe)).override_failure_message("the defender's once buff was spent by the volley it took").is_empty()


func test_a_round_buff_outlives_the_core_activation() -> void:
	var units := _volley_units()
	var att: GameUnit = units[0]
	_record(att, {"modifier": {"hit_mod": 1}, "scope": "shooting", "duration": "round"})
	_record(att, {"modifier": {"hit_mod": 1}, "scope": "melee", "duration": "once"})
	await _activate(att, units[1])
	assert_array(_records(att).map(func(rd: Dictionary) -> String: return "%s/%s" % [rd["duration"], rd["scope"]])) \
		.override_failure_message("a round buff and a melee-scoped once buff are not spent by a volley") \
		.is_equal(["round/shooting", "once/melee"])


func test_an_end_without_a_shot_spends_nothing() -> void:
	var units := _volley_units()
	var att: GameUnit = units[0]
	_record(att, {"modifier": {"hit_mod": 1}, "scope": "shooting", "duration": "once"})
	await _activate(att, units[1], false)
	assert_array(_records(att)).override_failure_message("no exchange happened, so nothing is spent").has_size(1)


## Seeds the morale cases try: with the fixture's 10 shooters and 5 targets, a volley leaves the target at half strength
## or less (a morale die) on about one seed in three, and never reaches one on the rest.
const MORALE_SEEDS := 24


## One core volley of a fresh fixture at `seed_n`, the target carrying a once morale buff (and Shaken when `shaken`).
## Returns whether the core asked for a morale die, and whether the target's once buff is still recorded afterwards.
func _morale_run(seed_n: int, shaken := false) -> Dictionary:
	var units := _volley_units()
	var foe: GameUnit = units[1]
	_record(foe, {"modifier": {"morale_mod": 1}, "scope": "", "duration": "once"})
	foe.is_shaken = shaken
	var asked := [false]
	_main.seed_tray_rng(seed_n)
	var t: Array = [{"t": "begin"}, {"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": foe.unit_id}]
	var r: Dictionary = await CoreActivation.drive(_main, CoreActivation.capture(_main), units[0], t, true,
		func(kind: String, _i: int) -> void: asked[0] = asked[0] or kind == "morale")
	assert_str(str(r["step"])).override_failure_message("seed %d, the core's answer: %s" % [seed_n, r]).is_equal("done")
	var kept := not _records(foe).is_empty()
	for u in units:   # the next seed starts on a bare table
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			(m as ModelInstance).node.free()
	_main._solo_spell_mods.clear()
	_main._solo_mirror_spell_state()
	return {"asked": asked[0], "kept": kept}


## The table spends a once morale buff right after the morale die (`_solo_morale_test`); the core path must too, and only
## when a die was thrown. Both halves are counted, so a seed set that never reaches a morale test fails instead of passing.
func test_a_once_morale_buff_is_spent_by_the_morale_test_the_core_runs() -> void:
	var tested := 0
	var untested := 0
	var wrong: Array = []
	for seed_n in range(1, MORALE_SEEDS + 1):
		var run: Dictionary = await _morale_run(seed_n)
		tested += int(run["asked"])
		untested += int(not run["asked"])
		if run["asked"] == run["kept"]:   # a die thrown spends it, no die leaves it
			wrong.append("seed %d: morale die %s, once buff %s" % [seed_n, run["asked"], "kept" if run["kept"] else "spent"])
	assert_array(wrong).override_failure_message("the once morale buff follows the morale die:\n" + "\n".join(wrong)).is_empty()
	assert_bool(tested > 0 and untested > 0).override_failure_message(
		"the seeds must reach a morale test AND miss one (%d, %d)" % [tested, untested]).is_true()


## A Shaken unit fails a further morale test without a die: nothing is thrown, so the once buff stays.
func test_a_shaken_target_keeps_its_once_morale_buff() -> void:
	for seed_n in [1, 7, 10]:
		var run: Dictionary = await _morale_run(seed_n, true)
		assert_bool(run["asked"]).override_failure_message("seed %d: a Shaken unit rolls no morale die" % seed_n).is_false()
		assert_bool(run["kept"]).override_failure_message("seed %d: no die, no spend" % seed_n).is_true()
