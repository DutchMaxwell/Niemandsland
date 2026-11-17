extends GdUnitTestSuite
## One core P4.D-19: the AI body hands a plain Hold/Advance's whole activation to the core - its Dangerous test and the
## end-of-activation morale from the test's wounds included - and the table rolls neither (no double roll). The ONE core
## call sits in `_run_ai_shooting` (the volley and its two early returns) or, for a unit that cannot shoot, in the body.
## A call the core does not take (a refusal) pays the test on the table first, in the old order; a split volley is the core's (P4.D-14).
## Real: the main scene, NmlCore, the AI's decision and move, the body (`_solo_activate_one_ai`), the table's volley and
## tray. Constructed: plain units (ParityTable), a painted Dangerous block under the attacker (the golden harness's own),
## both seats AI (no save card waits for a click).
## What one test is: the sentence "takes one Dangerous terrain test for the whole unit", and one tray roll of its dice
## (a "(6+)" dice line of the attacker, quality 4 so no hit roll reads 6+).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}

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
	CoreActivation._env = 1
	CoreActivation.ai_runs = 0
	CoreActivation.ai_refusals = 0
	CoreActivation.dangerous_mismatches = 0


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A plain AI unit "Att" (seat 2, `models` Rifles of 24", or a Blade when `reach` is 0).
func _att(models: int, reach: int = 24) -> GameUnit:
	return ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": models, "x_in": -10.0}, true),
		{"name": "Rifle" if reach > 0 else "Blade", "range_in": reach, "attacks": 1, "count": models, "rules": []})


## A defender "Def" (seat 1) at `x_in`; a unit rule makes it not plain, so the core door refuses a volley at it.
func _def(x_in: float, rules: Array = []) -> GameUnit:
	return ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 5, "x_in": x_in, "rules": rules}, true),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []})


## What the attacker's activation wrote: the Dangerous sentences, the tray rolls of the test, its wound sentence, the
## attacker's morale verdicts, and the volley's own "fires at" / "fires <weapon> at" lines.
func _tally(lines: Array) -> Dictionary:
	var out := {"tests": 0, "dice": 0, "wounds": 0, "morale": 0, "fires": 0}
	for l in lines:
		var t := str(l)
		out["tests"] += 1 if t.contains("Dangerous terrain test") else 0
		out["dice"] += 1 if t.begins_with("COMBAT|AI (Att)") and t.ends_with("(6+)") else 0
		out["wounds"] += 1 if t.contains("from dangerous terrain") else 0
		out["morale"] += 1 if t.begins_with("COMBAT|Att ") and t.contains(" morale") else 0
		out["fires"] += 1 if t.contains(" fires at ") or t.contains(" fires Rifle at ") or t.contains(" fires Pistol at ") else 0
	return out


## The index of the first line that contains `needle`, -1 when none does.
func _first(lines: Array, needle: String) -> int:
	for i in lines.size():
		if str(lines[i]).contains(needle):
			return i
	return -1


func _free(units: Array, painted: Dictionary) -> void:
	Harness._unpaint_cover(_main, painted)
	Harness._free_units(_main, units)
	_main.solo_controller._peeked_unit = null


## One real AI activation of `att` (the only AI unit) against `foes`, on seed `seed`. Returns the tally, the report, how
## many activations the core took and how many models the attacker lost. `dead` models are lost beforehand.
func _body(att: GameUnit, foes: Array, seed: int, dead: int = 0) -> Dictionary:
	Harness._kill_models(att, dead)
	var painted: Dictionary = Harness._paint_cover(_main, att, _main.terrain_overlay.TerrainType.DANGEROUS)
	_main.seed_tray_rng(seed)
	var lines: Array = []
	var tap: Callable = Harness._line_tap(lines)
	_main.battle_log.entry_added.connect(tap)
	var ran := CoreActivation.ai_runs
	await _main._solo_activate_one_ai()
	_main.battle_log.entry_added.disconnect(tap)
	var report: Dictionary = (_main.solo_controller.last_report as Dictionary).duplicate()
	var out := {"tally": _tally(lines), "report": report, "core": CoreActivation.ai_runs - ran,
		"lost": att.models.size() - dead - att.get_alive_count(), "lines": lines}
	_free([att] + foes, painted)
	await _main.get_tree().process_frame
	return out


## A held, shooting unit standing in Dangerous terrain, an enemy in range: the core takes the activation (core == 1) and
## the test is written and rolled once. RED: the body keeps its own `_run_ai_dangerous` call -> two sentences and two dice
## sets. The "half" shape (4 of 10 models left) calls the end morale for every wound: tested once, not twice (RED: the
## body's end morale not skipped when the core took the activation -> two verdicts).
func test_a_shooter_takes_its_dangerous_test_once_through_the_core() -> void:
	for shape in [{"models": 5, "dead": 0}, {"models": 10, "dead": 6}]:
		for s in 6:
			var att := _att(int(shape["models"]))
			var foe := _def(8.0)
			var r := await _body(att, [foe], s, int(shape["dead"]))
			var tally: Dictionary = r["tally"]
			var why := "shape %s seed %d: %s, report action %s dice %s, core %s\n%s" % [shape, s, tally,
				r["report"].get("action"), r["report"].get("dangerous_dice"), r["core"], "\n".join(r["lines"])]
			assert_bool(int(r["report"].get("action", -1)) in [AiDecision.Action.HOLD, AiDecision.Action.ADVANCE] \
				and int(r["report"].get("dangerous_dice", 0)) > 0).override_failure_message("not a Hold/Advance over Dangerous: " + why).is_true()
			assert_int(int(r["core"])).override_failure_message("the core did not take it: " + why).is_equal(1)
			assert_int(int(tally["tests"])).override_failure_message("sentences: " + why).is_equal(1)
			assert_int(int(tally["dice"])).override_failure_message("dice sets: " + why).is_equal(1)
			assert_int(int(tally["wounds"])).override_failure_message("wound sentence: " + why).is_equal(1 if int(r["lost"]) > 0 else 0)
			# The staged volley opens at its own first hit roll, not at the Dangerous test's throw: its announce comes after.
			var announce := _first(r["lines"], "Att fires at Def")
			assert_bool(announce > _first(r["lines"], "from dangerous terrain") if int(r["lost"]) > 0 \
				else announce > _first(r["lines"], "(6+)")).override_failure_message("the volley's announce came early: " + why).is_true()
			if int(shape["dead"]) > 0:
				assert_int(int(tally["morale"])).override_failure_message("morale tests: " + why).is_equal(1 if int(r["lost"]) > 0 else 0)
	assert_int(CoreActivation.dangerous_mismatches).override_failure_message("core and table disagree on the test").is_equal(0)
	assert_int(CoreActivation.ai_refusals).is_equal(0)


## A unit that cannot shoot (the enemy is 49" out, its reach 24") holds and still takes its test, in the core.
## RED: the body makes no core call for a unit with no volley -> zero sentences, zero dice: the unit is never tested.
func test_a_unit_that_cannot_shoot_still_takes_its_test_through_the_core() -> void:
	for s in 6:
		var att := _att(5)
		var foe := _def(40.0)
		var r := await _body(att, [foe], s)
		var tally: Dictionary = r["tally"]
		var why := "seed %d: %s, report %s, core %s\n%s" % [s, tally, r["report"], r["core"], "\n".join(r["lines"])]
		assert_bool(bool(r["report"].get("can_shoot", true))).override_failure_message("it can shoot: " + why).is_false()
		assert_int(int(r["core"])).override_failure_message("the core did not take it: " + why).is_equal(1)
		assert_int(int(tally["tests"])).override_failure_message("sentences: " + why).is_equal(1)
		assert_int(int(tally["dice"])).override_failure_message("dice sets: " + why).is_equal(1)
		assert_int(int(tally["fires"])).is_equal(0)
	assert_int(CoreActivation.dangerous_mismatches).is_equal(0)


## `_run_ai_shooting` with a test owed (`core_dangerous`), the board captured, the attacker in a Dangerous block. `act`
## builds the units and returns [att, foes]. Returns the tally, the report afterwards, the core's activations and refusals.
func _shooting(act: Callable, seed: int) -> Dictionary:
	var made: Array = act.call()
	var att := made[0] as GameUnit
	var painted: Dictionary = Harness._paint_cover(_main, att, _main.terrain_overlay.TerrainType.DANGEROUS)
	var dice := OPRArmyManager.dangerous_dice_for(att)
	var report := {"unit": att, "moved": true, "action": AiDecision.Action.ADVANCE, "dangerous_dice": dice,
		"core_dangerous": dice}
	_main.seed_tray_rng(seed)
	_main._solo_core_ai_h = CoreActivation.capture(_main)
	var lines: Array = []
	var tap: Callable = Harness._line_tap(lines)
	_main.battle_log.entry_added.connect(tap)
	var ran := CoreActivation.ai_runs
	var refused := CoreActivation.ai_refusals
	await _main._run_ai_shooting(report)
	_main.battle_log.entry_added.disconnect(tap)
	_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
	_main._solo_core_ai_h = 0
	var out := {"tally": _tally(lines), "report": report, "core": CoreActivation.ai_runs - ran,
		"refused": CoreActivation.ai_refusals - refused, "gone": att.is_destroyed(), "lines": lines}
	_free([att] + (made[1] as Array), painted)
	await _main.get_tree().process_frame
	return out


## Every exit of `_run_ai_shooting` pays an owed test exactly once: the core's volley, no target, no ranged weapon (the
## core takes the shotless activation) and a split volley (the core's, its groups in one call); a refused call (the table rolls it in
## front of its own volley).
## RED: an exit with no call or payment -> zero sentences; a refusal path that pays twice -> two.
func test_every_exit_of_the_volley_code_pays_an_owed_test_once() -> void:
	var cases := {
		"volley": func() -> Array: return [_att(5), [_def(8.0)]],
		"no target": func() -> Array: return [_att(5), [_def(40.0)]],
		"no ranged weapon": func() -> Array: return [_att(5, 0), [_def(8.0)]],
		"split": func() -> Array:
			var sc: Dictionary = Harness.split_scenarios()[0]
			var att := ParityTable._make_unit(_main, sc["attacker"], Harness._kit_weapon((sc["kit"] as Array)[0]))
			Harness._kit_out(att, sc["kit"])
			var a := ParityTable._make_unit(_main, sc["def_a"], {})
			var b := ParityTable._make_unit(_main, sc["def_b"], {})
			b.is_activated = true
			return [att, [a, b]],
		"refused": func() -> Array: return [_att(5), [_def(8.0, ["Fast"])]],   # a target with a unit rule: not plain
	}
	var core_runs := {"volley": 1, "no target": 1, "no ranged weapon": 1, "split": 1, "refused": 0}
	for name in cases:
		var r := await _shooting(cases[name], 3)
		var tally: Dictionary = r["tally"]
		var why := "%s: %s, core %s, refused %s\n%s" % [name, tally, r["core"], r["refused"], "\n".join(r["lines"])]
		assert_int(int(tally["tests"])).override_failure_message("sentences: " + why).is_equal(1)
		assert_int(int(tally["dice"])).override_failure_message("dice sets: " + why).is_equal(1)
		assert_int(int(r["core"])).override_failure_message("core runs: " + why).is_equal(int(core_runs[name]))
		assert_int(int(r["refused"])).override_failure_message("a refusal after a throw: " + why).is_equal(0)
		assert_bool(r["report"].has("core_dangerous")).override_failure_message("test still owed: " + why).is_false()
		assert_bool(bool(r["report"].get("core_took_dangerous", false))).override_failure_message("took flag: " + why) \
			.is_equal(int(core_runs[name]) == 1)
	assert_int(CoreActivation.dangerous_mismatches).is_equal(0)


## A lone attacker whose own test (paid on the table after a refused call) kills it fires nothing: the old body stopped
## right after the test. RED: no stop -> the table's volley still fires from a dead unit. Seeds are scanned for a wipe.
func test_a_test_paid_on_the_table_that_wipes_the_unit_stops_the_volley() -> void:
	var wiped := 0
	for s in 30:
		var r := await _shooting(func() -> Array: return [_att(1), [_def(8.0, ["Fast"])]], s)
		if bool(r["gone"]):
			wiped += 1
			assert_int(int((r["tally"] as Dictionary)["fires"])).override_failure_message(
				"fired from a dead unit: %s" % [r["lines"]]).is_equal(0)
		assert_int(int((r["tally"] as Dictionary)["tests"])).is_equal(1)
	assert_bool(wiped >= 3).override_failure_message("only %d seeds wiped the unit" % wiped).is_true()
