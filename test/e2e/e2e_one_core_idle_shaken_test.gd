extends GdUnitTestSuite
## One core P4.D-36: an idle Shaken unit that stands in Dangerous terrain owes the test - the AI body hands it to the core
## (a Hold that tests, then recovers: the core takes the activation, `CoreActivation.ai_runs`) and the table rolls nothing
## itself (no double roll). The probe that opened this step: `step_activation` accepts the idle Shaken Hold, asks the Dangerous
## dice (one per model, 6+ is a 6, a 1 wounds) when the unit stands in the terrain and clears Shaken - as the table's idle
## path does. A Shaken unit outside the terrain owes no test and recovers on the table, as before.
## Real: the main scene, NmlCore, the AI body (`_solo_activate_one_ai`), the tray. Constructed: plain units (ParityTable) and the
## golden harness's own painted Dangerous block under the idle unit; both seats AI.

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
	SoloHarness.start(_main, [1, 2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	CoreActivation.ai_runs = 0
	CoreActivation.ai_refusals = 0


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One seed: a Shaken AI unit "Att" of `models` (seat 2), standing in a painted Dangerous block when `dangerous`, and a spent
## foe; the AI body activates it. `core` = the core door on (flag 1) or the table alone (flag 0).
func _run(seed: int, core: bool, models: int, dangerous: bool) -> Dictionary:
	CoreActivation._env = 1 if core else 0
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": models, "x_in": -10.0}, true),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": models, "rules": []})
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 3, "x_in": 8.0}, true),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 3, "rules": []})
	foe.is_activated = true
	att.is_shaken = true
	var painted := Harness._paint_cover(_main, att, _main.terrain_overlay.TerrainType.DANGEROUS) if dangerous else {}
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	_main.seed_tray_rng(seed)
	var runs := CoreActivation.ai_runs
	await _main._solo_activate_one_ai()
	_main.battle_log.entry_added.disconnect(tap)
	var rec := {"final": Harness._final([att]), "rng": str(_main._tray_rng.state), "lines": lines,
		"core_runs": CoreActivation.ai_runs - runs}
	if dangerous:
		Harness._unpaint_cover(_main, painted)
	Harness._free_units(_main, [att, foe])
	CoreActivation.reset_all(_main)
	_main._solo_core_ai_h = 0
	await get_tree().process_frame
	return rec


## The rows with the Shaken flag of a destroyed unit cleared.
func _alive_shaken_free(rows: Array) -> Array:
	var out: Array = (rows as Array).duplicate(true)
	for r in out:
		if int(r["alive"]) == 0:
			r["shaken"] = false
	return out


func _count(lines: Array, needle: String) -> int:
	return lines.filter(func(l: String) -> bool: return l.contains(needle)).size()


## RED: the table's own call kept next to the core's -> two tests ("Dangerous terrain test" twice, two "(each 1)" dice lines).
@warning_ignore('unused_parameter')
func test_an_idle_shaken_unit_in_dangerous_terrain_takes_exactly_one_test_through_the_core(timeout := 300000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	var r := await _run(7, true, 5, true)
	var lines: Array = r["lines"]
	assert_int(int(r["core_runs"])).override_failure_message("the core did not take the idle activation: %s" % str(lines)).is_equal(1)
	assert_int(_count(lines, "Dangerous terrain test")).override_failure_message("not exactly one test: %s" % str(lines)).is_equal(1)
	assert_int(lines.filter(func(l: String) -> bool: return l.begins_with("AI (Att)") and l.ends_with("(each 1)")).size()) \
		.override_failure_message("not one die set: %s" % str(lines)).is_equal(1)
	assert_int(_count(lines, "recovers from Shaken")).is_equal(1)
	assert_bool(r["final"][0]["shaken"]).override_failure_message("still Shaken").is_false()
	assert_int(CoreActivation.ai_refusals).is_equal(0)


## No terrain, no test: nothing for the core to do, the table recovers the unit as ever.
@warning_ignore('unused_parameter')
func test_an_idle_shaken_unit_outside_dangerous_terrain_recovers_without_a_core_call(timeout := 300000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	var r := await _run(7, true, 5, false)
	assert_int(int(r["core_runs"])).is_equal(0)
	assert_int(_count(r["lines"], "Dangerous terrain test")).is_equal(0)
	assert_int(_count(r["lines"], "recovers from Shaken")).is_equal(1)
	assert_bool(r["final"][0]["shaken"]).is_false()


## The same activation on the table alone and through the core, seed for seed: the unit ends the same (every model's alive /
## wounds, Shaken) and the tray is at the same state. The battle log differs only by (a) the table's pooled "takes N wound(s)
## (a/b)" line, which the core does not write (the known door difference) and (b) the order of the two wound sentences. The
## Dangerous wipe-down owes the end-of-activation morale test (GF 3.6 p.10), which a Shaken unit always fails: both sides now
## say the "is already Shaken - automatically fails morale" sentence and the outcome line, draw no die, and the unit recovers
## as the activation's last step (the core after the test, `sim.rs`; the table after `_solo_shooting_morale`). A destroyed
## unit's Shaken flag (the table never recovers a dead unit) is not compared. 3 models reach the
## end-morale threshold now and then, 1 model dies in the test.
@warning_ignore('unused_parameter')
func test_the_core_and_the_table_end_every_idle_shaken_activation_alike(timeout := 900000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	var seeds := int(OS.get_environment("NML_ONE_CORE_SEEDS")) if OS.has_environment("NML_ONE_CORE_SEEDS") else 60
	var bad: Array = []
	var hurt := 0
	var pooled := RegEx.create_from_string("^Att takes \\d+ wounds? \\(\\d+/\\d+\\)$")
	for models in [3, 1]:
		for s in seeds:
			var t := await _run(s, false, models, true)
			var c := await _run(s, true, models, true)
			hurt += 1 if _count(t["lines"], "from dangerous terrain") > 0 else 0
			if int(c["core_runs"]) != 1:
				bad.append("%d models seed %d: the core did not take the activation" % [models, s])
			if _alive_shaken_free(t["final"]) != _alive_shaken_free(c["final"]) or t["rng"] != c["rng"]:
				bad.append("%d models seed %d: table %s rng %s, core %s rng %s" % [models, s, t["final"], t["rng"], c["final"], c["rng"]])
			var tl: Array = (t["lines"] as Array).filter(func(l: String) -> bool: return pooled.search(l) == null)
			var cl: Array = (c["lines"] as Array).duplicate()
			tl.sort()
			cl.sort()
			if tl != cl:
				bad.append("%d models seed %d: lines table %s core %s" % [models, s, str(tl), str(cl)])
	print("ONE_CORE_IDLE_SHAKEN seeds=%d x 2 shapes hurt=%d mismatches=%d" % [seeds, hurt, bad.size()])
	for b in bad:
		print("ONE_CORE_IDLE_SHAKEN_BAD ", b)
	assert_int(hurt).override_failure_message("no seed was hurt by the test: nothing was compared").is_greater(0)
	assert_array(bad).override_failure_message("\n".join(bad.slice(0, 6))).is_empty()
