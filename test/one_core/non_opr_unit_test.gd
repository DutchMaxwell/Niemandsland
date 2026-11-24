extends GdUnitTestSuite
## One core P4.D-13: can a NON-OPR unit (source_type "generic", or an OPR unit with no profile) be PLAYING in a game and
## reach a combat door? This suite PINS the answer, so P4.D-6 can keep or drop `CoreActivation.is_plain`'s non-OPR clause
## on evidence, not on a guess.
##
## The facts (each pinned below):
## (1) No UI path makes such a unit. `EquipmentDistributor.create_from_opr_unit` is the only code that stamps
##     source_type "opr" (with the profile) and the only one that puts the "game_unit" meta on a spawned model besides
##     the save loader; a model placed from the sandbox catalog has no GameUnit at all.
## (2) The loader can: `GameUnit.from_dict` keeps whatever the file says, so a save written by an old build (before the
##     profile was serialised) or edited by hand gives a PLAYING unit with source_data == null.
## (3) Such a unit has no weapons at any resolver (every site reads `weapons` only when source_type == "opr" AND
##     source_data is an OPRUnit): as ATTACKER it throws no die; as TARGET it is shot by the table, from unit_properties.
## (4) `is_plain` refuses it as an ATTACKER (nothing to read weapons from); P4.D-13b: as a TARGET `is_plain_target` takes it,
## because the core builds a target's whole profile from unit_properties - so the core door shoots it, like for like.
## OUTCOME B (it can, through a loaded save): the attacker clause stays, and it must NOT become an assert in P4.D-6 - it is
## also the only guard before `source_data.weapons` (with the clause removed, `is_plain` of a loaded unit dies on a null
## profile). P4.D-13c: a target with NO statline (a hand-written save: quality / defense 0) is not a valid target at a core
## table; one battle-log line says why and no die is thrown.
## Real: the main scene, NmlCore, both doors (`_run_ai_shooting`, `_run_human_attack`), the table's volley.
## Constructed: bare units (E2EBoot.make_unit, ParityTable._make_unit), the OPR profile of the armed ones.
## NML_ONE_CORE_SEEDS overrides the 20 seeds per defense (200 for the sweep run).
##
## The table arm left when the AI table resolver retired; door values are pinned as literals read on main af5c83610.

const SlicePin := preload("res://test/one_core/slice_pin.gd")
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const INCH := 0.0254
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []}
## Per-seed alive count of the 5-model target after the AI door volley, read on main af5c83610 (identical at defense 2, 4 and 6).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_ALIVE_D2 := [0, 2, 3, 5, 3, 3, 3, 2, 4, 4, 2, 5, 5, 4, 1, 3, 1, 4, 3, 2]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_ALIVE_D4 := [0, 2, 3, 5, 3, 3, 3, 2, 4, 4, 2, 5, 5, 4, 1, 3, 1, 4, 3, 2]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_ALIVE_D6 := [0, 2, 3, 5, 3, 3, 3, 2, 4, 4, 2, 5, 5, 4, 1, 3, 1, 4, 3, 2]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_HURT := 123

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [1, 2], 1)   # both seats AI: the saves of the shot unit roll without a prompt
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	CoreActivation._env = 1
	CoreActivation.ai_runs = 0
	CoreActivation.ai_refusals = 0


func after_test() -> void:
	SlicePin.release()
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## `models` bare models in a column x_in inches from the origin. `armed`: an OPR profile with `models` Rifles (24", A1);
## unarmed = the loader's non-OPR shape (source_type "generic", source_data null).
func _unit(pid: int, uname: String, x_in: float, models: int, armed: bool) -> GameUnit:
	var positions: Array = []
	for i in models:
		positions.append(Vector3(x_in * INCH, 0.0, 1.2 * INCH * i))
	var u := E2EBoot.make_unit(_main, pid, uname, positions)
	u.unit_properties["special_rules"] = []
	if armed:
		var w := OPRApiClient.OPRWeapon.new()
		w.name = "Rifle"
		w.range_value = 24
		w.attacks = 1
		w.count = models
		var src := OPRApiClient.OPRUnit.new()
		src.weapons.assign([w])
		u.source_type = "opr"
		u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _free(units: Array) -> void:
	for u in units:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			var nd: Node = (m as ModelInstance).node
			if nd != null and is_instance_valid(nd):
				nd.free()


func _log_texts() -> Array:
	var out: Array = []
	for e in _main.battle_log.entries():
		out.append(str((e as Dictionary)["text"]))
	return out


func _lines_containing(fragment: String) -> Array:
	return _log_texts().filter(func(t: String) -> bool: return t.contains(fragment))


## All `.gd` files under `dir` (recursive), as res:// paths.
func _gd_files(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir.path_join(d)))
	return out


## (1) Which scripts WRITE a unit's source_type, and which put the "game_unit" meta on a model: the importer's factory
## and the loader, nothing else. A new creator reddens this and must answer P4.D-13 again.
func test_only_the_importer_and_the_loader_can_put_a_unit_on_the_table() -> void:
	var setters: Array = []
	var metas: Array = []
	var re_set := RegEx.create_from_string("(?m)^\\s*[\\w.]*source_type\\s*=[^=]")
	for path in _gd_files("res://scripts"):
		var src := FileAccess.get_file_as_string(path)
		if re_set.search(src) != null:
			setters.append(path.get_file())
		if src.contains("set_meta(\"game_unit\""):
			metas.append(path.get_file())
	setters.sort()
	metas.sort()
	assert_array(setters).override_failure_message("scripts that write source_type: %s" % [setters]) \
		.is_equal(["equipment_distributor.gd", "game_unit.gd"])
	assert_array(metas).override_failure_message("scripts that stamp the game_unit meta: %s" % [metas]) \
		.is_equal(["equipment_distributor.gd", "save_manager.gd"])


## (2) The loader keeps what the file says: a "generic" unit, and an "opr" unit saved without its profile, both load with
## source_data null - and neither is plain.
func test_the_loader_can_bring_a_non_opr_unit_into_a_game() -> void:
	for source_type in ["generic", "opr"]:
		var u := GameUnit.from_dict({"unit_id": "loaded_%s" % source_type, "source_type": source_type,
			"unit_properties": {"player_id": 2, "name": "Loaded", "quality": 4, "defense": 4, "special_rules": []},
			"models": []})
		assert_str(u.source_type).is_equal(source_type)
		assert_bool(u.source_data == null).override_failure_message("%s: the loader invented a profile" % source_type).is_true()
		assert_bool(CoreActivation.is_plain(u)).override_failure_message("%s: a unit with no profile is plain" % source_type).is_false()
		assert_bool(CoreActivation.is_plain_target(u)).override_failure_message("%s: a loaded target is not plain" % source_type).is_true()


## (4) The control and the clause: an armed OPR unit with no rules is plain, the same unit without its profile is not.
## RED: delete the non-OPR clause from `is_plain` -> the second assertion fails.
func test_is_plain_needs_the_opr_profile() -> void:
	var armed := _unit(2, "Armed", 0.0, 2, true)
	var bare := _unit(2, "Bare", 6.0, 2, false)
	assert_bool(CoreActivation.is_plain(armed)).override_failure_message("the control is not plain").is_true()
	assert_bool(bare.source_type == "generic" and bare.source_data == null).is_true()
	assert_bool(CoreActivation.is_plain(bare)).override_failure_message("a unit with no OPR profile is plain").is_false()
	assert_bool(CoreActivation.is_plain_target(bare)).override_failure_message("the profile-less target is not plain").is_true()
	_free([armed, bare])


## P4.D-13b: the target half asks for a statline (quality and defense in 2..6), not for a profile.
## RED: drop the 2..6 check from `has_statline` -> the 0, 1 and 7 rows fail.
func test_is_plain_target_needs_a_statline_not_a_profile() -> void:
	SlicePin.narrow()   # C-19: the case is about a unit the narrow slice refuses
	var bare := _unit(2, "Bare", 0.0, 2, false)
	for row in [[4, 4, true], [2, 6, true], [0, 4, false], [4, 0, false], [1, 4, false], [4, 7, false]]:
		bare.unit_properties["quality"] = row[0]
		bare.unit_properties["defense"] = row[1]
		assert_bool(CoreActivation.is_plain_target(bare)).override_failure_message("quality %d defense %d" % [row[0], row[1]]) \
			.is_equal(row[2])
	bare.unit_properties["quality"] = 4
	bare.unit_properties["defense"] = 4
	bare.unit_properties["special_rules"] = ["Fast"]
	assert_bool(CoreActivation.is_plain_target(bare)).override_failure_message("a unit rule makes a target not plain").is_false()
	_free([bare])


## (4) The AI door's predicate answers before any core call: a non-OPR ATTACKER is false (the table shoots), and no core
## run or refusal is counted. h = 1 is a dummy handle. (The non-OPR TARGET goes to the core since P4.D-13b: see below.)
func test_the_ai_door_hands_a_non_opr_attacker_to_the_table() -> void:
	var armed_too := _unit(1, "ArmedToo", 6.0, 2, true)
	var bare := _unit(2, "Bare", 12.0, 2, false)
	var report := {"action": AiDecision.Action.HOLD, "moved": false}
	var runs := CoreActivation.ai_runs
	var refusals := CoreActivation.ai_refusals
	assert_bool(await CoreActivation.run_ai(_main, bare, report, armed_too, 1)).override_failure_message("a non-OPR attacker went to the core").is_false()
	assert_int(CoreActivation.ai_runs).is_equal(runs)
	assert_int(CoreActivation.ai_refusals).is_equal(refusals)
	_free([armed_too, bare])


## (3) As ATTACKER a non-OPR unit throws no die: the AI door writes ONE line saying so and shoots nobody.
func test_a_non_opr_attacker_fires_nothing_on_the_ai_door() -> void:
	var bare := _unit(2, "Bare", 0.0, 5, false)
	var foe := _unit(1, "Foe", 8.0, 5, true)
	await _main._run_ai_shooting({"unit": bare, "moved": false, "action": AiDecision.Action.HOLD})
	assert_array(_lines_containing("Bare: no volley — no ready ranged weapon")).override_failure_message(
		"log: %s" % [_log_texts()]).has_size(1)
	assert_array(_lines_containing(" fires ")).override_failure_message("a die was thrown: %s" % [_log_texts()]).is_empty()
	assert_int(foe.get_alive_count()).is_equal(5)
	_free([bare, foe])


## One AI volley (seat 2: 10 Rifles) at 5 models of a profile-less target of `defense` (even seeds a loaded "opr" unit, odd
## ones a "generic" one), tray seed `s`. `core_run`: the body's capture is handed to the door, as `_solo_activate_one_ai`
## does for a plain unit; else the table shoots. Returns what the comparison reads, and how many volleys the core took.
func _ai_volley(s: int, defense: int, core_run: bool) -> Dictionary:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 10, "x_in": 0.0}), RIFLE)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Bare%d" % defense, "models": 5, "x_in": 12.0,
		"defense": defense}), {})
	foe.source_type = "opr" if s % 2 == 0 else "generic"
	_main.seed_tray_rng(s)
	var runs := CoreActivation.ai_runs
	var h := CoreActivation.capture(_main) if core_run else 0
	_main._solo_core_ai_h = h
	await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
	_main._solo_core_ai_h = 0
	if h != 0:
		(_main.solo_controller as SoloController)._core_node_ready().release(h)
	var survivors: Array = foe.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	survivors.sort()
	var out := {"alive": foe.get_alive_count(), "survivors": survivors, "shaken": foe.is_shaken,
		"rng": _main._tray_rng.state, "core": CoreActivation.ai_runs - runs}
	_free([att, foe])
	return out


## P4.D-13b, AI door: the volley at a loaded profile-less target goes through the core (the door counts it) and is not
## refused. RED: put the OPR-profile clause back into `is_plain_target` -> `core` stays 0.
func test_a_non_opr_target_is_shot_by_the_core_on_the_ai_door() -> void:
	var core := await _ai_volley(1, 4, true)
	assert_int(core["core"]).override_failure_message("the table shot a non-OPR target").is_equal(1)
	assert_int(CoreActivation.ai_refusals).override_failure_message("the core refused it").is_equal(0)
	assert_array(_lines_containing("Att fires at Bare4")).override_failure_message("log: %s" % [_log_texts()]).has_size(1)
	assert_int(core["alive"]).override_failure_message("the volley hurt nobody (seed 1 wounds)").is_less(5)


## The AI door shoots a loaded profile-less target and ends on the same alive count the table left on main, at defense 2, 4 and 6
## (the ends of the statline range), seed for seed. A planted fault in the core's target profile reddens it.
func test_the_core_shoots_a_non_opr_target_like_the_table_on_the_ai_door(timeout := 900000) -> void:
	var seeds := int(OS.get_environment("NML_ONE_CORE_SEEDS")) if OS.has_environment("NML_ONE_CORE_SEEDS") else 20
	var want := {2: WANT_ALIVE_D2, 4: WANT_ALIVE_D4, 6: WANT_ALIVE_D6}
	var bad: Array = []
	var hurt := 0
	for defense in [2, 4, 6]:
		var pins: Array = want[defense]
		assert_array(pins.slice(0, seeds)).override_failure_message(
			"defense %d: the literal holds %d seeds, the sweep wants %d" % [defense, pins.size(), seeds]).has_size(seeds)
		for s in seeds:
			var core := await _ai_volley(s, defense, true)
			hurt += 5 - int(core["alive"])
			if int(core["core"]) != 1:
				bad.append("defense %d seed %d: the door took %d (core run)" % [defense, s, core["core"]])
			if s < pins.size() and int(core["alive"]) != int(pins[s]):
				bad.append("defense %d seed %d: alive %d, pinned %d" % [defense, s, core["alive"], pins[s]])
	print("NON_OPR_TARGET door=ai seeds=%d defenses=3 hurt=%d mismatches=%d" % [seeds, hurt, bad.size()])
	assert_int(hurt).override_failure_message("the volley's damage moved off the pinned sum").is_equal(WANT_HURT)
	assert_array(bad).override_failure_message("door vs pinned literal:\n" + "\n".join(bad.slice(0, 10))).is_empty()


## (3) The human door agrees: a non-OPR attacker's volley throws no die, the table says so in ONE line.
func test_a_non_opr_attacker_fires_nothing_on_the_human_door() -> void:
	var bare := _unit(1, "Bare", 0.0, 5, false)
	var foe := _unit(2, "Foe", 8.0, 5, true)
	await _main._run_human_attack(bare, foe, false)
	assert_array(_lines_containing("Bare has no weapon in range of Foe — no shots")).override_failure_message(
		"log: %s" % [_log_texts()]).has_size(1)
	assert_array(_lines_containing("Bare fires")).override_failure_message("a die was thrown: %s" % [_log_texts()]).is_empty()
	_free([bare, foe])


## One human volley (seat 1: 10 Rifles, Hold) at 5 models of a profile-less target of `defense` (seat 2, AI), through the
## window door `_run_human_attack`; the pattern of e2e_one_core_human_test. `core_run`: the flag is on and the unit is
## started. Returns what the comparison reads, and whether the core's declaration line ("<Att> fires at <Target>") is in.
func _human_volley(s: int, defense: int, core_run: bool, auto := false) -> Dictionary:
	_main.solo_ai_slots = {2: true}   # seat 1 is the human: the shooter is a lifecycle unit
	SoloHarness.auto_saves(_main)
	SoloHarness.fast(_main)
	_main._autosave_controller.set_lesson_paused(true)   # a periodic autosave would add its own log line
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Att", "models": 10, "x_in": 0.0}), RIFLE)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Bare%d" % defense, "models": 5, "x_in": 12.0,
		"defense": defense}), {})
	foe.source_type = "opr" if s % 2 == 0 else "generic"
	foe.is_activated = true   # the AI has nothing left to do: no reply, in either run
	var spare := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Spare", "models": 1, "x_in": 40.0}), {})
	CoreActivation._env = 1 if core_run else 0
	if core_run:
		assert_bool(_main.core_activation_start(att)).override_failure_message("seed %d: no Start" % s).is_true()
	var lines: Array = []
	var on_entry := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(on_entry)
	_main.seed_tray_rng(s)
	await _main._run_human_attack(att, foe, false, auto)
	_main.battle_log.entry_added.disconnect(on_entry)
	var survivors: Array = foe.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	survivors.sort()
	var out := {"alive": foe.get_alive_count(), "survivors": survivors, "shaken": foe.is_shaken,
		"rng": _main._tray_rng.state, "core": lines.has("Att fires at Bare%d" % defense)}
	CoreActivation.close_session(_main, att.unit_id)
	_free([att, foe, spare])
	return out


## P4.D-13b, human door: the volley at a loaded profile-less target goes through the core. The core's declaration line
## is only there when it took the shot. RED: put the OPR-profile clause back into `is_plain_target` -> no such line.
func test_a_non_opr_target_is_shot_by_the_core_on_the_human_door() -> void:
	var core := await _human_volley(1, 4, true)
	assert_bool(core["core"]).override_failure_message("the table shot a non-OPR target: %s" % [_log_texts()]).is_true()
	assert_int(core["alive"]).override_failure_message("the volley hurt nobody (seed 1 wounds)").is_less(5)


## The Auto verbs move the unit through the engine, outside the session's drop, so the core would shoot from the START spot
## (the two-instance harness's Advance & Shoot saw `done` with no roll once its target became takeable). Their shot stays
## on the table. RED: drop the `auto` clause from `human_shoot` -> the core's declaration line is there and nothing hurt it.
func test_an_auto_verbs_shot_stays_on_the_table() -> void:
	var out := await _human_volley(1, 4, true, true)
	assert_bool(out["core"]).override_failure_message("the core took an auto verb's shot: %s" % [_log_texts()]).is_false()
	assert_int(out["alive"]).override_failure_message("the table's volley hurt nobody (seed 1 wounds)").is_less(5)


func test_the_core_shoots_a_non_opr_target_like_the_table_on_the_human_door(timeout := 900000) -> void:
	var seeds := int(OS.get_environment("NML_ONE_CORE_SEEDS")) if OS.has_environment("NML_ONE_CORE_SEEDS") else 20
	var bad: Array = []
	var hurt := 0
	for defense in [2, 4, 6]:
		for s in seeds:
			var table := await _human_volley(s, defense, false)
			var core := await _human_volley(s, defense, true)
			hurt += 5 - int(core["alive"])
			if not core["core"] or table["core"]:
				bad.append("defense %d seed %d: the core door took it: %s (core run), %s (table run)" % [defense, s, core["core"], table["core"]])
			for k in ["survivors", "shaken", "rng"]:
				if table[k] != core[k]:
					bad.append("defense %d seed %d: %s: table %s, core %s" % [defense, s, k, table[k], core[k]])
	print("NON_OPR_TARGET door=human seeds=%d defenses=3 hurt=%d mismatches=%d" % [seeds, hurt, bad.size()])
	assert_int(hurt).override_failure_message("no seed hurt the target: the sweep compares nothing").is_greater(0)
	assert_array(bad).override_failure_message("core vs table:\n" + "\n".join(bad.slice(0, 10))).is_empty()


## P4.D-13c: a target with NO statline (quality and defense 0: a hand-written foreign save) is not a valid target at a core
## table. The AI door writes ONE line saying why, no "no volley" line, and throws no die. RED: drop the
## `refuses_statlineless` call from `_run_ai_shooting` -> the table shoots it.
func test_a_target_with_no_statline_is_not_shot_and_says_why_on_the_ai_door() -> void:
	var att := _unit(2, "Att", 0.0, 10, true)
	var ghost := _unit(1, "Ghost", 8.0, 10, false)
	ghost.unit_properties.erase("quality")
	ghost.unit_properties.erase("defense")
	_main.seed_tray_rng(0)
	var rng_before: int = _main._tray_rng.state
	_main._solo_core_ai_h = CoreActivation.capture(_main)
	await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
	_main._solo_core_ai_h = 0
	assert_array(_lines_containing("Att cannot shoot Ghost: it has no Quality or Defense")).override_failure_message(
		"log: %s" % [_log_texts()]).has_size(1)
	assert_array(_lines_containing("no volley")).override_failure_message("a second line: %s" % [_log_texts()]).is_empty()
	assert_array(_lines_containing(" fires ")).override_failure_message("a die was thrown: %s" % [_log_texts()]).is_empty()
	assert_int(ghost.get_alive_count()).is_equal(10)
	assert_int(_main._tray_rng.state).override_failure_message("a die was rolled").is_equal(rng_before)
	assert_int(CoreActivation.ai_runs + CoreActivation.ai_refusals).override_failure_message("the core was asked").is_equal(0)
	_free([att, ghost])


## ... with the kill switch on the volley is held (the GDScript table no longer resolves volleys): one held line, no statline line, no die.
func test_the_kill_switch_leaves_a_target_with_no_statline_to_the_table() -> void:
	CoreActivation._env = 0
	var att := _unit(2, "Att", 0.0, 10, true)
	var ghost := _unit(1, "Ghost", 8.0, 10, false)
	ghost.unit_properties.erase("quality")
	ghost.unit_properties.erase("defense")
	var rng_before: int = _main._tray_rng.state
	await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
	assert_array(_lines_containing("it has no Quality or Defense")).is_empty()
	assert_array(_lines_containing("Att: no volley — the rules core cannot resolve this volley")).override_failure_message("log: %s" % [_log_texts()]).has_size(1)
	assert_array(_lines_containing(" fires ")).override_failure_message("a die was thrown: %s" % [_log_texts()]).is_empty()
	assert_int(_main._tray_rng.state).override_failure_message("a die was rolled").is_equal(rng_before)
	_free([att, ghost])


## P4.D-13c, human door: the same one line, nothing shot, the activation stays open (the door returns before the volley).
func test_a_target_with_no_statline_is_not_shot_and_says_why_on_the_human_door() -> void:
	_main.solo_ai_slots = {2: true}
	var att := _unit(1, "Att", 0.0, 10, true)
	var ghost := _unit(2, "Ghost", 8.0, 10, false)
	ghost.unit_properties.erase("quality")
	ghost.unit_properties.erase("defense")
	ghost.is_activated = true
	assert_bool(_main.core_activation_start(att)).override_failure_message("no Start").is_true()
	_main.seed_tray_rng(0)
	var rng_before: int = _main._tray_rng.state
	await _main._run_human_attack(att, ghost, false)
	assert_array(_lines_containing("Att cannot shoot Ghost: it has no Quality or Defense")).override_failure_message(
		"log: %s" % [_log_texts()]).has_size(1)
	assert_array(_lines_containing(" fires ")).override_failure_message("a die was thrown: %s" % [_log_texts()]).is_empty()
	assert_int(ghost.get_alive_count()).is_equal(10)
	assert_int(_main._tray_rng.state).override_failure_message("a die was rolled").is_equal(rng_before)
	assert_object(CoreActivation.last_target).override_failure_message("a shot was noted").is_null()
	assert_bool(CoreActivation._sessions.has(att.unit_id)).override_failure_message("the activation was closed").is_true()
	CoreActivation.close_session(_main, att.unit_id)
	_free([att, ghost])
