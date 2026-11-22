extends GdUnitTestSuite
## One core P4.D-38a: the door lands the once-per-game feat latch the core spent. A Protection Feat defender rolls its 5+
## ignore die in the first volley that wounds it and never again; the core spends the latch in its own copy, so the table's
## flag (`ignore_feat_used_<snake>`, what the table's own roll and the next capture read) is closed from the activation's delta,
## and the next volley's capture sends the closed latch back. Seed for seed against the table's two volleys: the Feat dice rolled
## (kind, count, target), survivors, Shaken, the tray RNG after, the flag, and the battle-log lines (as a multiset).
## Real: the main scene, NmlCore, `_run_ai_shooting` (the AI body's door), the table's volley and spend.
## Constructed: OPR units (ParityTable) at both seats AI; the slice is the shipped one plus a test group for Regeneration (the
## Protection Feat's primitive). NML_ONE_CORE_SEEDS overrides 20.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const TMP := "user://feat_latch_slice.json"
const FLAG := "ignore_feat_used_protection_feat"
const SHOT_FLAG := "shot_feat_used_precision_feat"
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const SHOT_SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "aof",
	"faction_folder": "ghostly_undead", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	_main._solo_auto_saves = true
	_main._solo_fast = true
	_main._autosave_controller.set_lesson_paused(true)
	CoreActivation._env = 1
	CoreActivation.ai_runs = 0
	CoreActivation.ai_refusals = 0
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CoreSlice.PATH))
	data["groups"]["regen_test"] = {"primitives": ["Regeneration"], "step": "P4.D-0", "golden": "x", "parity": "x"}
	data["groups"]["shot_test"] = {"primitives": ["Shot Modifier"], "step": "P4.D-0", "golden": "x", "parity": "x"}
	data["groups"]["takedown_test"] = {"primitives": ["Takedown"], "step": "P4.D-0", "golden": "x", "parity": "x"}
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	CoreSlice.path_override = TMP
	CoreSlice.reset_cache()


func after_test() -> void:
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _free(units: Array) -> void:
	for u in units:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()
	_main.solo_controller._peeked_unit = null


## Two volleys (10 Rifles at 10 models 8" away, the defender carries Protection Feat) on tray seed `s`; `core_run` = the door
## (a board is captured before each volley), else the table's own volley. Returns what the comparison reads.
func _two_volleys(s: int, core_run: bool, rules := ["Protection Feat"]) -> Dictionary:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 10, "x_in": 0.0}), RIFLE)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 10, "x_in": 8.0, "rules": rules}, true), RIFLE)
	for i in foe.models.size():   # a uniform lattice ties the casualty order on a float's last bit: nudge each model
		(foe.models[i] as ModelInstance).node.global_position.z += float((i * 7) % 5) * 0.0001
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	_main.seed_tray_rng(s)
	var runs := CoreActivation.ai_runs
	for _v in 2:
		var h := CoreActivation.capture(_main) if core_run else 0
		_main._solo_core_ai_h = h
		await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
		_main._solo_core_ai_h = 0
		if h != 0:
			(_main.solo_controller as SoloController)._core_node_ready().release(h)
	_main.battle_log.entry_added.disconnect(tap)
	var survivors: Array = foe.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	survivors.sort()
	# Not compared: the declaration line pair (the core's announce against the table's sight line), the AI's opening line, and the
	# Regeneration family's own two sentences ("rolls N <rule> dice", "already used it"): the core door does not say them yet
	# (the defense_regen group, P4.D-33). The dice they describe ARE compared: the tray RNG after equals only when both sides rolled
	# the same Feat dice, so a re-rolled Feat shows there.
	var rest := lines.filter(func(l: String) -> bool: return not (l.begins_with("Att fires at ") or l.contains("with line of sight + range")
		or l == "Att begins its activation." or l.begins_with("NACHTMAHR") or l.contains("Protection Feat di")
		or l.contains("already used it this game")))
	rest.sort()
	var out := {"alive": foe.get_alive_count(), "survivors": survivors, "shaken": foe.is_shaken, "rng": _main._tray_rng.state,
		"lines": rest, "flag": bool(foe.unit_properties.get(FLAG, false)), "core": CoreActivation.ai_runs - runs,
		"spends": lines.filter(func(l: String) -> bool: return l.contains("spends its once-per-game ignore roll")).size()}
	_free([att, foe])
	return out


## The Feat is rolled once and spent once on both sides, flag and all. RED: drop `_land_feats` from `land_delta` -> the table's flag
## never closes: no flag, no spend sentence, and the second capture sends an open latch, so the core rolls the Feat again (RNG
## differs). RED: drop `_stamp_spent_ignore_feats` from `capture` -> the flag closes but the second volley re-rolls the Feat.
func test_the_door_closes_the_feat_latch_the_table_closes() -> void:
	var seeds := int(OS.get_environment("NML_ONE_CORE_SEEDS")) if OS.has_environment("NML_ONE_CORE_SEEDS") else 20
	var bad: Array = []
	var spent := 0
	for s in seeds:
		var table := await _two_volleys(s, false)
		var core := await _two_volleys(s, true)
		spent += 1 if bool(core["flag"]) else 0
		if int(core["core"]) != 2 or int(table["core"]) != 0:
			bad.append("seed %d: the core took %d volleys (table run %d)" % [s, core["core"], table["core"]])
		for k in ["alive", "survivors", "shaken", "rng", "flag", "spends", "lines"]:
			if table[k] != core[k]:
				bad.append("seed %d: %s: table %s, core %s" % [s, k, table[k], core[k]])
	print("FEAT_LATCH seeds=%d spent=%d mismatches=%d" % [seeds, spent, bad.size()])
	assert_int(spent).override_failure_message("no seed spent the Feat: the sweep compares nothing").is_greater(0)
	assert_array(bad).override_failure_message("core vs table:\n" + "\n".join(bad.slice(0, 10))).is_empty()


## A defender WITHOUT the feat spends nothing: no flag, no sentence, and no "no table flag" report for a name the core never
## produced. (The delta of a plain volley names no feat.)
func test_a_defender_without_the_feat_spends_none() -> void:
	var core := await _two_volleys(3, true, [])
	assert_bool(core["flag"]).is_false()
	assert_int(core["spends"]).is_equal(0)


## Two volleys through the door (else the table's own) with the SHOOTER carrying Precision Feat: the aof once-per-game
## Shot Modifier (+1 to hit on every attack, `uses_per_game`). The table spends it through `_solo_spend_shot_feats`
## (`shot_feat_used_<snake>`); the defender is plain. Returns what the comparison reads.
func _two_shot_volleys(s: int, core_run: bool) -> Dictionary:
	var att := ParityTable._make_unit(_main, SHOT_SIDE.merged({"player": 2, "name": "Att", "models": 10, "x_in": 0.0,
		"rules": ["Precision Feat"]}, true), RIFLE)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 10, "x_in": 8.0}), RIFLE)
	for i in foe.models.size():
		(foe.models[i] as ModelInstance).node.global_position.z += float((i * 7) % 5) * 0.0001
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	_main.seed_tray_rng(s)
	var runs := CoreActivation.ai_runs
	for _v in 2:
		var h := CoreActivation.capture(_main) if core_run else 0
		_main._solo_core_ai_h = h
		await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
		_main._solo_core_ai_h = 0
		if h != 0:
			(_main.solo_controller as SoloController)._core_node_ready().release(h)
	_main.battle_log.entry_added.disconnect(tap)
	var survivors: Array = foe.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	survivors.sort()
	var out := {"alive": foe.get_alive_count(), "survivors": survivors, "shaken": foe.is_shaken, "rng": _main._tray_rng.state,
		"flag": bool(att.unit_properties.get(SHOT_FLAG, false)), "core": CoreActivation.ai_runs - runs,
		"spends": lines.filter(func(l: String) -> bool: return l.contains("spends its once-per-game feat on this attack")).size()}
	_free([att, foe])
	return out


## The once-per-game SHOT feat the core spends closes the table's own latch, so the second volley's capture sends it CLOSED:
## volley 2 keeps no +1, and the door's outcome (survivors, Shaken, tray RNG, flag) is the table's own two volleys seed for seed.
## RED: filter the shot-feat names out of `_land_feats` -> the flag stays open, the second capture sends it open, and the core
## grants the +1 a second time (survivors/RNG drift from the table run).
func test_the_door_closes_the_shot_feat_latch_the_core_spends() -> void:
	var seeds := int(OS.get_environment("NML_ONE_CORE_SEEDS")) if OS.has_environment("NML_ONE_CORE_SEEDS") else 20
	var bad: Array = []
	var spent := 0
	for s in seeds:
		var table := await _two_shot_volleys(s, false)
		var core := await _two_shot_volleys(s, true)
		spent += 1 if bool(core["flag"]) else 0
		if int(table["spends"]) != 1:
			bad.append("seed %d: the table run says %d spend sentence(s), want 1" % [s, table["spends"]])
		for k in ["alive", "survivors", "shaken", "rng", "flag", "spends"]:
			if table[k] != core[k]:
				bad.append("seed %d: %s: table %s, core %s" % [s, k, table[k], core[k]])
	print("SHOT_FEAT_LATCH seeds=%d spent=%d mismatches=%d" % [seeds, spent, bad.size()])
	assert_int(spent).override_failure_message("no seed spent the shot feat: the sweep compares nothing").is_greater(0)
	assert_array(bad).override_failure_message("core vs table:\n" + "\n".join(bad.slice(0, 10))).is_empty()


## Two volleys through the door (else the table's own) with a one-model SHOOTER carrying Takedown Shot (gf, the once-per-game
## extra attack at Quality 2+, AP(2), Deadly(3), Takedown; `uses_per_game`). The table closes `takedown_bonus_used_<name>`.
func _two_takedown_volleys(s: int, core_run: bool) -> Dictionary:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 1, "x_in": 0.0,
		"faction_folder": "human_inquisition", "rules": ["Takedown Shot"]}, true), RIFLE)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 10, "x_in": 8.0}), RIFLE)
	for i in foe.models.size():
		(foe.models[i] as ModelInstance).node.global_position.z += float((i * 7) % 5) * 0.0001
	_main.seed_tray_rng(s)
	var runs := CoreActivation.ai_runs
	for _v in 2:
		var h := CoreActivation.capture(_main) if core_run else 0
		_main._solo_core_ai_h = h
		await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
		_main._solo_core_ai_h = 0
		if h != 0:
			(_main.solo_controller as SoloController)._core_node_ready().release(h)
	var survivors: Array = foe.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	survivors.sort()
	var out := {"alive": foe.get_alive_count(), "survivors": survivors, "shaken": foe.is_shaken, "rng": _main._tray_rng.state,
		"flag": bool(att.unit_properties.get("takedown_bonus_used_Takedown Shot", false)), "core": CoreActivation.ai_runs - runs}
	_free([att, foe])
	return out


## Coverage ledger m2 (gf_811, state class): the Takedown Shot the core spends closes the table's own latch through the door, so
## the second volley's capture sends it CLOSED and the core makes no second extra attack. RED: drop the Takedown branch from
## `_land_feats` -> the flag stays open (and the door reports a feat no table flag closes).
func test_the_door_closes_the_takedown_shot_latch_the_core_spends() -> void:
	var seeds := int(OS.get_environment("NML_ONE_CORE_SEEDS")) if OS.has_environment("NML_ONE_CORE_SEEDS") else 20
	var bad: Array = []
	var spent := 0
	for s in seeds:
		var table := await _two_takedown_volleys(s, false)
		var core := await _two_takedown_volleys(s, true)
		spent += 1 if bool(core["flag"]) else 0
		if int(core["core"]) != 2:
			bad.append("seed %d: the core took %d volleys" % [s, core["core"]])
		for k in ["alive", "survivors", "shaken", "rng", "flag"]:
			if table[k] != core[k]:
				bad.append("seed %d: %s: table %s, core %s" % [s, k, table[k], core[k]])
	print("TAKEDOWN_LATCH seeds=%d spent=%d mismatches=%d" % [seeds, spent, bad.size()])
	assert_int(spent).override_failure_message("no seed spent Takedown Shot: the sweep compares nothing").is_greater(0)
	assert_array(bad).override_failure_message("core vs table:\n" + "\n".join(bad.slice(0, 10))).is_empty()
