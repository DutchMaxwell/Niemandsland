extends GdUnitTestSuite
## One core P4.D-37: the activation_level group (Strafing, Crossing Attack). A move-through bearer the core takes has its
## move-through attacks resolved by the core's ONE call (its pre-attack slots, from the trails it is handed); the table's
## own `_solo_apply_strafing` / `_solo_apply_crossing_attack` run only when that call is not made or refused. Seed for seed
## against the table: the survivors, Shaken, the tray RNG after and the battle-log lines (as a multiset).
## Real: the main scene, NmlCore, `_run_ai_shooting` / `_solo_ai_core_call` and the table's own move-through resolvers.
## Constructed: OPR units (ParityTable) at both seats AI; the slice is the shipped one, so the shipped `activation_level`
## group is the one exercised. NML_ONE_CORE_SEEDS overrides 20. Not compared: the declaration line (the core's announce
## against the table's sight line, one per volley) and the shot rows the recorder gets.

const SlicePin := preload("res://test/one_core/slice_pin.gd")
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const INCH := 0.0254
const TMP := "user://move_through_slice.json"
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []}
const STRAFE_GUN := {"name": "Strafe Gun", "range_in": 24, "attacks": 2, "count": 10, "rules": ["Crossing Strike"]}

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


func after_test() -> void:
	SlicePin.release()
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


## The bearer `Att` (seat 2) with `weapon` (plus a Rifle when `rifle`), a defender `Def` (seat 1) of 20 models at `foe_in`.
func _units(weapon: Dictionary, unit_rules: Array, rifle: bool, foe_in: float, foe_models := 20, foe_rules := []) -> Array:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 10, "x_in": 0.0, "rules": unit_rules}, true), weapon)
	if rifle:
		var w := OPRApiClient.OPRWeapon.new()
		w.name = "Rifle"
		w.range_value = 24
		w.attacks = 1
		w.count = 10
		(att.source_data as OPRApiClient.OPRUnit).weapons.append(w)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": foe_models, "x_in": foe_in, "rules": foe_rules}, true), RIFLE.merged({"count": foe_models}))
	# A uniform lattice makes the casualty order tie left end against right end, and the tie breaks on the last bit of a float
	# (the table's node positions against the core's): nudge every model by its own few thousandths of an inch.
	for i in foe.models.size():
		(foe.models[i] as ModelInstance).node.global_position.z += float((i * 7) % 5) * 0.0001
	return [att, foe]


## The executed move: every alive model of `att` from its start to x = `to_in`, the planner's own `last_move_paths` shape.
func _move(att: GameUnit, to_in: float) -> void:
	var legs: Array = []
	for m in att.get_alive_models():
		var from: Vector3 = (m as ModelInstance).node.global_position
		var to := Vector3(to_in * INCH, from.y, from.z)
		legs.append({"model": m, "path": [from, to]})
		(m as ModelInstance).node.global_position = to
	_main.solo_controller.last_move_paths = legs
	att.unit_properties["moved_round"] = 1   # what the planner's apply stamps with the move


func _line_key(l: String) -> String:
	# The Crossing Attack sentence is worded differently by the table and the core; both carry "<wounds> of <n> dice wound".
	if l.begins_with("COMBAT|Crossing Attack"):
		return "COMBAT|Crossing Attack: " + l.substr(l.rfind("—") + 2).replace(" (no save)", "")
	return l


## One activation of the bearer: Rush (no shot) or Advance (a Rifle volley at `Def`), then what it left. `core_run` = the
## door (the board is captured before the move and the body marks the report), else the table's own resolvers.
func _run(weapon: Dictionary, unit_rules: Array, kind: int, s: int, core_run: bool, foe_models := 20, foe_rules := []) -> Dictionary:
	var rifle := kind == AiDecision.Action.ADVANCE
	var units := _units(weapon, unit_rules, rifle, 3.0 if rifle else 8.0, foe_models, foe_rules)   # an Advance (6") crosses the foe at 3", a Rush (12") the one at 8"
	var att: GameUnit = units[0]
	var foe: GameUnit = units[1]
	var lines: Array = []
	var tap := func(e: Dictionary) -> void:
		lines.append("%s|%s" % [BattleLog.Category.keys()[int(e["category"])], str(e["text"])])
	_main.battle_log.entry_added.connect(tap)
	_main.seed_tray_rng(s)
	var runs := CoreActivation.ai_runs
	var h := CoreActivation.capture(_main) if core_run else 0
	_main._solo_core_ai_h = h
	_move(att, 6.0 if rifle else 11.0)
	var report := {"unit": att, "moved": true, "action": kind, "can_shoot": rifle}
	if core_run:
		report["core_through"] = true
	else:
		await _main._solo_apply_strafing(att)
		await _main._solo_apply_crossing_attack(att)
	if rifle:
		await _main._run_ai_shooting(report)
	elif core_run:
		await _main._solo_ai_core_call(att, report, null, [])
	_main._solo_core_ai_h = 0
	if h != 0:
		(_main.solo_controller as SoloController)._core_node_ready().release(h)
	_main.battle_log.entry_added.disconnect(tap)
	var pos := func(u: GameUnit) -> Array:
		var a: Array = u.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
		a.sort()
		return a
	var rest := lines.filter(func(l: String) -> bool: return not l.begins_with("COMBAT|Att fires at ") \
		and not l.contains("no volley — no target")).map(_line_key)
	rest.sort()
	var out := {"foe": pos.call(foe), "att": pos.call(att), "shaken": [att.is_shaken, foe.is_shaken],
		"rng": _main._tray_rng.state, "lines": rest, "core": CoreActivation.ai_runs - runs, "left": report.has("core_through")}
	_free(units)
	return out


func _sweep(name: String, weapon: Dictionary, unit_rules: Array, kind: int, foe_models := 20) -> void:
	var seeds := int(OS.get_environment("NML_ONE_CORE_SEEDS")) if OS.has_environment("NML_ONE_CORE_SEEDS") else 20
	var bad: Array = []
	var hurt := 0
	for s in seeds:
		var table := await _run(weapon, unit_rules, kind, s, false, foe_models)
		var core := await _run(weapon, unit_rules, kind, s, true, foe_models)
		hurt += foe_models - (core["foe"] as Array).size()
		if int(core["core"]) != 1 or int(table["core"]) != 0 or core["left"]:
			bad.append("seed %d: the core took it %d times (table run %d), core_through left: %s" % [s, core["core"], table["core"], core["left"]])
		for k in ["foe", "att", "shaken", "rng", "lines"]:
			if table[k] != core[k]:
				bad.append("seed %d: %s: table %s, core %s" % [s, k, table[k], core[k]])
	print("MOVE_THROUGH %s seeds=%d hurt=%d mismatches=%d" % [name, seeds, hurt, bad.size()])
	assert_int(hurt).override_failure_message("no seed hurt the defender: the sweep compares nothing").is_greater(0)
	assert_array(bad).override_failure_message("core vs table:\n" + "\n".join(bad.slice(0, 10))).is_empty()


## A Rush through the defender: only the move-through volley fires (Crossing Strike). RED: `takes_action` refuses a
## Rush -> the core is never called (core 0) and the table pays it.
func test_a_rush_through_an_enemy_strafes_in_the_core() -> void:
	await _sweep("strafing_rush", STRAFE_GUN, [], AiDecision.Action.RUSH)


## An Advance through the defender with a Rifle: the strafe, then the Rifle volley, in ONE core call.
func test_an_advance_through_an_enemy_strafes_then_shoots_in_the_core() -> void:
	await _sweep("strafing_advance", STRAFE_GUN, [], AiDecision.Action.ADVANCE)


## The strafe wipes out the Rifle volley's target (two defenders): the core's volley finds no model to shoot, so the survivors,
## Shaken and the tray RNG still equal the table's (whose body picks its target AFTER the strafe and writes "no volley — no
## target in range or sight" instead: the one line the comparison leaves out).
func test_a_target_the_core_strafe_wiped_out_is_not_shot_at() -> void:
	await _sweep("strafing_wipe", STRAFE_GUN, [], AiDecision.Action.ADVANCE, 2)


## Crossing Attack (unit rule, X dice per crossing model, wound on 6, no save).
func test_a_crossing_attack_rolls_in_the_core() -> void:
	await _sweep("crossing_attack", RIFLE, ["Crossing Attack(2)"], AiDecision.Action.RUSH)


## The shipped slice plus a test group (Aircraft: the one rule a real AI move-through needs; its lane is the straight run).
func _slice_with(extra: Dictionary) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CoreSlice.PATH))
	for name in extra:
		data["groups"][name] = {"primitives": extra[name], "step": "P4.D-0", "golden": "x", "parity": "x"}
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	CoreSlice.path_override = TMP
	CoreSlice.reset_cache()


## One REAL AI activation (`_solo_activate_one_ai`, the planner's own straight run) of an Aircraft strafer over a defender line:
## `core_run` = the door on, else the kill switch (the table strafes in the body).
func _body(s: int, core_run: bool) -> Dictionary:
	CoreActivation._env = 1 if core_run else 0
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 5, "x_in": -10.0, "rules": ["Aircraft"]}, true),
		STRAFE_GUN.merged({"count": 5}))
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 20, "x_in": 0.0}), RIFLE.merged({"count": 20}))
	for i in foe.models.size():
		(foe.models[i] as ModelInstance).node.global_position.z += float((i * 7) % 5) * 0.0001
	var lines: Array = []
	var tap := func(e: Dictionary) -> void:
		lines.append("%s|%s" % [BattleLog.Category.keys()[int(e["category"])], str(e["text"])])
	_main.battle_log.entry_added.connect(tap)
	_main.seed_tray_rng(s)
	var runs := CoreActivation.ai_runs
	await _main._solo_activate_one_ai()
	_main.battle_log.entry_added.disconnect(tap)
	var rest := lines.filter(func(l: String) -> bool: return not l.begins_with("COMBAT|Att fires at ") and not l.begins_with("MOVEMENT")).map(_line_key)
	rest.sort()
	var out := {"foe": foe.get_alive_count(), "rng": _main._tray_rng.state, "lines": rest, "core": CoreActivation.ai_runs - runs,
		"strafes": lines.filter(func(l: String) -> bool: return l.contains("passes over Def")).size(),
		"report": (_main.solo_controller.last_report as Dictionary).duplicate()}
	_free([att, foe])
	await _main.get_tree().process_frame
	return out


## The real body, the refusal path: the core's move check does not know an Aircraft's mandatory 30" run (P4.D-29), so the call
## is refused before any die and the table pays the strafe in `_solo_pay_dangerous`: ONCE (the body skipped its own calls
## because the core was to take it), with the table's own survivors, RNG and lines. RED: the body keeps its two table calls
## -> two "passes over" lines; the fallback dropped -> none. When D-29 teaches the core Aircraft this run is the success path:
## flip `core` to 1.
func test_a_refused_core_call_leaves_the_strafe_to_the_table_once() -> void:
	_slice_with({"aircraft_test": ["Aircraft"]})
	var bad: Array = []
	var hurt := 0
	for s in 10:
		var table := await _body(s, false)
		var core := await _body(s, true)
		hurt += 1 if int(core["foe"]) < 20 else 0
		if int(core["core"]) != 0 or int(core["strafes"]) != 1 or int(table["strafes"]) != 1:
			bad.append("seed %d: core runs %d, strafe lines core %d table %d (report %s)" % [s, core["core"], core["strafes"], table["strafes"], core["report"].get("action")])
		for k in ["foe", "rng", "lines"]:
			if table[k] != core[k]:
				bad.append("seed %d: %s: table %s, core %s" % [s, k, table[k], core[k]])
	print("MOVE_THROUGH body hurt=%d mismatches=%d" % [hurt, bad.size()])
	assert_int(hurt).override_failure_message("no seed hurt the defender: the test compares nothing").is_greater(0)
	assert_array(bad).override_failure_message("fallback vs table:\n" + "\n".join(bad.slice(0, 6))).is_empty()


## The human door (P4.D-37b): a Strafing bearer is a core unit (its strike comes with the activation's Fire / End), a Crossing
## Attack bearer stays on the table (the table never rolled that rule for a human unit; the core would). The slice takes both
## (`is_plain`). RED: drop the Crossing Attack clause from `is_core_unit` -> the human Crossing Attack bearer is a core unit.
## PLAN_FIRST_DELETION step 21: the human Hit & Run bearer IS a core unit now (its intent says `no_step`, the player drags the step).
func test_the_human_door_takes_a_strafe_bearer_but_not_a_crossing_attack_bearer() -> void:
	_main.solo_ai_slots = {2: true}
	var strafer := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Strafer", "models": 2, "x_in": 0.0}), STRAFE_GUN)
	var crosser := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Crosser", "models": 2, "x_in": 10.0, "rules": ["Crossing Attack(2)"]}, true), RIFLE)
	var plain := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Plain", "models": 2, "x_in": 20.0}), RIFLE)
	assert_bool(CoreActivation.is_plain(crosser)).override_failure_message("the slice no longer takes the Crossing Attack bearer").is_true()
	assert_bool(CoreActivation.is_core_unit(_main, plain)).override_failure_message("a plain human unit is not a core unit").is_true()
	assert_bool(CoreActivation.is_core_unit(_main, strafer)).override_failure_message("the human Strafing bearer is no core unit").is_true()
	assert_bool(CoreActivation.is_core_unit(_main, crosser)).override_failure_message("the human Crossing Attack bearer is a core unit").is_false()
	# H-30 kept a Hit & Run bearer on the table (the core stepped for it and spent the round's use; a human drags the step). Step 21: the
	# door sends `no_step` (step 20), so the bearer is a core unit. Pinned on the deny file WITHOUT the `hit_and_run_landing` group (gone
	# from the live file since 3e), so `is_core_unit`'s own clause stays the one under test.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CoreSlice.live_path()))
	(data["groups"] as Dictionary).erase("hit_and_run_landing")
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	CoreSlice.path_override = TMP
	CoreSlice.reset_cache()
	var runner := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Runner", "models": 2, "x_in": 30.0, "faction_folder": "custodian_brothers", "rules": ["Hit & Run Shooter"]}, true), RIFLE)
	assert_bool(CoreActivation.is_plain(runner)).override_failure_message("the slice no longer takes the Hit & Run bearer").is_true()
	assert_bool(CoreActivation.is_core_unit(_main, runner)).override_failure_message("the human Hit & Run bearer is a core unit (step 21)").is_true()
	_free([strafer, crosser, plain, runner])


## A refused core call pays the move-through attacks on the table BEFORE the volley, which was aimed earlier: a target the strafe
## wiped out is not shot at. RED: drop the `get_alive_count() == 0` skip in `_run_ai_shooting` -> a second announce and "Rifle silent".
func test_a_target_the_table_strafe_wiped_out_is_not_shot_at() -> void:
	var units := _units(STRAFE_GUN, [], true, 3.0)
	var att: GameUnit = units[0]
	var foe: GameUnit = units[1]
	for i in range(2, foe.models.size()):   # two defenders left: ten strafe shots wipe them out
		(foe.models[i] as ModelInstance).is_alive = false
	_main.seed_tray_rng(1)
	_move(att, 6.0)
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	_main._solo_core_ai_h = 0   # no board: the core call is not made, the table pays
	await _main._run_ai_shooting({"unit": att, "moved": true, "action": AiDecision.Action.ADVANCE, "can_shoot": true, "core_through": true})
	_main.battle_log.entry_added.disconnect(tap)
	assert_int(foe.get_alive_count()).override_failure_message("the strafe did not wipe the target out: " + str(lines)).is_equal(0)
	assert_int(lines.filter(func(l: String) -> bool: return l.contains("passes over Def")).size()).is_equal(1)
	assert_int(lines.filter(func(l: String) -> bool: return l.contains("fires at Def") or l.contains("Rifle silent")).size()).override_failure_message(
		"a volley at a wiped-out target (the strafe's own announce is the one \"fires at\"): " + str(lines)).is_equal(1)
	_free(units)


## The body's own decision for a Rush through the defender line (`takes_ai_activation`, the core call, the table's strike when the
## core is not to take it), with a second crossed unit `far_rules` (null = none) behind the line at 10". Returns what the
## comparison reads: whether the core took it, how many core runs and strike sentences there were, the survivors, RNG and lines.
func _decided(s: int, foe_rules: Array, far_rules: Variant) -> Dictionary:
	var units := _units(STRAFE_GUN, [], false, 8.0, 20, foe_rules)
	var att: GameUnit = units[0]
	var far: GameUnit = null
	if far_rules != null:
		far = ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Far", "models": 5, "x_in": 10.0, "rules": far_rules}, true),
			RIFLE.merged({"count": 5}))
		units.append(far)
	var lines: Array = []
	var tap := func(e: Dictionary) -> void:
		lines.append("%s|%s" % [BattleLog.Category.keys()[int(e["category"])], str(e["text"])])
	_main.battle_log.entry_added.connect(tap)
	_main.seed_tray_rng(s)
	var runs := CoreActivation.ai_runs
	var h := CoreActivation.capture(_main)
	_main._solo_core_ai_h = h
	_move(att, 11.0)
	var report := {"unit": att, "moved": true, "action": AiDecision.Action.RUSH, "can_shoot": false}
	var takes: bool = CoreActivation.takes_ai_activation(_main, att, report)   # the body's decision, made once
	if takes:
		report["core_through"] = true
		await _main._solo_ai_core_call(att, report, null, [])
	else:
		await _main._solo_apply_strafing(att)
	_main._solo_core_ai_h = 0
	(_main.solo_controller as SoloController)._core_node_ready().release(h)
	_main.battle_log.entry_added.disconnect(tap)
	var rest := lines.filter(func(l: String) -> bool: return not l.begins_with("COMBAT|Att fires at ")).map(_line_key)
	rest.sort()
	var foe: GameUnit = units[1]
	var out := {"takes": takes, "core": CoreActivation.ai_runs - runs, "refused": bool(report.get("through_refused", false)),
		"strikes": lines.filter(func(l: String) -> bool: return l.contains("passes over")).size(),
		"foe": foe.get_alive_count(), "far": far.get_alive_count() if far != null else -1, "rng": _main._tray_rng.state, "lines": rest}
	_free(units)
	return out


## P4.D-37c: every enemy the legs cross must be a plain target. A crossed unit with a defense rule the slice does not list
## (Regeneration) leaves the whole activation to the table: the core is not called, the table strikes once, and the result is
## the table's own run. RED (the guard dropped from `takes_ai_activation`): the core takes it and strikes the Regeneration unit.
func test_a_crossed_enemy_with_an_unsupported_rule_leaves_the_strike_to_the_table() -> void:
	SlicePin.narrow()   # C-19: the case is about a unit the narrow slice refuses
	var bad: Array = []
	for s in 6:
		var table := await _run(STRAFE_GUN, [], AiDecision.Action.RUSH, s, false, 20, ["Regeneration"])
		var door := await _decided(s, ["Regeneration"], null)
		if door["takes"] or door["core"] != 0 or not door["refused"] or int(door["strikes"]) != 1:
			bad.append("seed %d: takes %s, core runs %s, refused %s, strikes %s" % [s, door["takes"], door["core"], door["refused"], door["strikes"]])
		if door["foe"] != (table["foe"] as Array).size() or door["rng"] != table["rng"] or door["lines"] != table["lines"]:
			bad.append("seed %d: not the table's own run: foe %s/%s" % [s, door["foe"], (table["foe"] as Array).size()])
	assert_array(bad).override_failure_message("\n".join(bad.slice(0, 6))).is_empty()


## The conservative reading: a second crossed unit the strike would not even pick (it stands behind the nearest) still decides.
func test_any_crossed_enemy_decides_not_only_the_one_struck() -> void:
	SlicePin.narrow()   # C-19: the case is about a unit the narrow slice refuses
	var door := await _decided(1, [], ["Regeneration"])
	assert_bool(door["takes"]).override_failure_message("a crossed Regeneration unit behind the line was ignored").is_false()
	assert_int(int(door["core"])).is_equal(0)
	assert_int(int(door["strikes"])).is_equal(1)


## No regression: crossed enemies that are all plain targets (the line and a second unit behind it) still go through the core, once.
func test_crossed_plain_enemies_still_go_through_the_core() -> void:
	for s in 6:
		var door := await _decided(s, [], [])
		assert_bool(door["takes"]).override_failure_message("seed %d: a plain crossed enemy refused the core" % s).is_true()
		assert_int(int(door["core"])).is_equal(1)
		assert_int(int(door["strikes"])).is_equal(1)


## The decision is made once. The body left the strike to the table (a crossed Regeneration unit); the table's strike wipes that
## unit out, and the Rifle volley after it (aimed at a plain unit, not crossed) must not be taken by the core: its board, captured
## before the move, still holds the wiped-out unit and would strike it again. RED (`through_refused` ignored by `run_ai`): the
## core takes the volley's call and a second strike sentence stands.
func test_a_refused_activation_is_not_resumed_by_the_core_after_the_table_struck() -> void:
	SlicePin.narrow()   # C-19: the case is about a unit the narrow slice refuses
	var units := _units(STRAFE_GUN, [], true, 3.0, 2, ["Regeneration"])   # the crossed unit: 2 models, wiped out by ten strafe shots
	var att: GameUnit = units[0]
	var tgt := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Tgt", "models": 5, "x_in": 15.0}), RIFLE.merged({"count": 5}))
	units.append(tgt)
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	_main.seed_tray_rng(2)
	var runs := CoreActivation.ai_runs
	var h := CoreActivation.capture(_main)
	_main._solo_core_ai_h = h
	_move(att, 6.0)
	var report := {"unit": att, "moved": true, "action": AiDecision.Action.ADVANCE, "can_shoot": true}
	assert_bool(CoreActivation.takes_ai_activation(_main, att, report)).override_failure_message("the core took a crossed Regeneration unit").is_false()
	await _main._solo_apply_strafing(att)   # the body's table strike
	await _main._run_ai_shooting(report)
	_main._solo_core_ai_h = 0
	(_main.solo_controller as SoloController)._core_node_ready().release(h)
	_main.battle_log.entry_added.disconnect(tap)
	assert_int((units[1] as GameUnit).get_alive_count()).override_failure_message("the strike did not wipe the unit out: " + str(lines)).is_equal(0)
	assert_int(CoreActivation.ai_runs - runs).override_failure_message("the core took the volley after the table struck").is_equal(0)
	assert_int(lines.filter(func(l: String) -> bool: return l.contains("passes over")).size()).override_failure_message(
		"the strike was made twice: " + str(lines)).is_equal(1)
	_free(units)
