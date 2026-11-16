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
## (4) `is_plain` refuses it, so `run_ai` / `human_shoot` hand a volley at such a target to the table.
## OUTCOME B (it can, through a loaded save): the clause stays, and it must NOT become an assert in P4.D-6 - it is also
## the only guard before `source_data.weapons` (with the clause removed, `is_plain` of a loaded unit dies on a null
## profile, core_activation.gd:29). The table's resolvers are the only thing that shoots a non-OPR TARGET today, so a
## follow-up step must route that case before the first resolver is deleted (P4.D-41).
## Real: the main scene, the AI door `_run_ai_shooting`, the table's volley, the AI-door predicate `run_ai`.
## Constructed: bare units (E2EBoot.make_unit), the OPR profile of the armed ones, a dummy core handle for `run_ai`
## (its predicate answers before any core call, so no NmlCore is needed).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}   # both seats AI: the saves of the shot unit roll without a prompt
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	CoreActivation._env = 1


func after_test() -> void:
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


## (4) The control and the clause: an armed OPR unit with no rules is plain, the same unit without its profile is not.
## RED: delete the non-OPR clause from `is_plain` -> the second assertion fails.
func test_is_plain_needs_the_opr_profile() -> void:
	var armed := _unit(2, "Armed", 0.0, 2, true)
	var bare := _unit(2, "Bare", 6.0, 2, false)
	assert_bool(CoreActivation.is_plain(armed)).override_failure_message("the control is not plain").is_true()
	assert_bool(bare.source_type == "generic" and bare.source_data == null).is_true()
	assert_bool(CoreActivation.is_plain(bare)).override_failure_message("a unit with no OPR profile is plain").is_false()
	_free([armed, bare])


## (4) The AI door's predicate answers before any core call: a non-OPR attacker or a non-OPR target is false (the table
## shoots), and no core run or refusal is counted. h = 1 is a dummy handle.
func test_the_ai_door_hands_a_non_opr_unit_to_the_table() -> void:
	var armed := _unit(2, "Armed", 0.0, 2, true)
	var armed_too := _unit(1, "ArmedToo", 6.0, 2, true)
	var bare := _unit(1, "Bare", 12.0, 2, false)
	var report := {"action": AiDecision.Action.HOLD, "moved": false}
	var runs := CoreActivation.ai_runs
	var refusals := CoreActivation.ai_refusals
	assert_bool(await CoreActivation.run_ai(_main, armed, report, bare, 1)).override_failure_message("a non-OPR target went to the core").is_false()
	assert_bool(await CoreActivation.run_ai(_main, bare, report, armed_too, 1)).override_failure_message("a non-OPR attacker went to the core").is_false()
	assert_int(CoreActivation.ai_runs).is_equal(runs)
	assert_int(CoreActivation.ai_refusals).is_equal(refusals)
	_free([armed, armed_too, bare])


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


## (3)+(4) As TARGET a non-OPR unit is shot: with a (dummy) core handle open, the AI door still resolves the volley on
## the table - the predicate refuses the target, the table's volley fires and the unit loses models.
func test_a_non_opr_target_is_shot_by_the_table() -> void:
	var att := _unit(2, "Att", 0.0, 10, true)
	var bare := _unit(1, "Bare", 8.0, 10, false)
	_main.seed_tray_rng(0)
	_main._solo_core_ai_h = 1   # the body's capture of a plain attacker; run_ai refuses the target before any core call
	var runs := CoreActivation.ai_runs
	await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
	_main._solo_core_ai_h = 0
	assert_int(CoreActivation.ai_runs).override_failure_message("the core took a non-OPR target").is_equal(runs)
	assert_array(_lines_containing("Att fires at Bare")).override_failure_message("log: %s" % [_log_texts()]).has_size(1)
	assert_int(bare.get_alive_count()).override_failure_message("the table's volley hurt nobody (seed 0 wounds)").is_less(10)
	_free([att, bare])


## (3) The human door agrees: a non-OPR attacker's volley throws no die, the table says so in ONE line.
func test_a_non_opr_attacker_fires_nothing_on_the_human_door() -> void:
	var bare := _unit(1, "Bare", 0.0, 5, false)
	var foe := _unit(2, "Foe", 8.0, 5, true)
	await _main._run_human_attack(bare, foe, false)
	assert_array(_lines_containing("Bare has no weapon in range of Foe — no shots")).override_failure_message(
		"log: %s" % [_log_texts()]).has_size(1)
	assert_array(_lines_containing("Bare fires")).override_failure_message("a die was thrown: %s" % [_log_texts()]).is_empty()
	_free([bare, foe])


## (3)+(4) ... and a non-OPR TARGET is shot by the table from the human door too.
func test_a_non_opr_target_is_shot_by_the_table_on_the_human_door() -> void:
	var att := _unit(1, "Att", 0.0, 10, true)
	var bare := _unit(2, "Bare", 8.0, 10, false)
	_main.seed_tray_rng(0)
	await _main._run_human_attack(att, bare, false)
	assert_array(_lines_containing("Att fires Rifle at Bare")).override_failure_message("log: %s" % [_log_texts()]).has_size(1)
	assert_int(bare.get_alive_count()).override_failure_message("the table's volley hurt nobody").is_less(10)
	_free([att, bare])
