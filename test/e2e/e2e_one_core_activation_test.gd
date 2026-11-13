extends GdUnitTestSuite
## One-core P3 step 22 (the spike gate #2647, reworked): one AI activation of a plain unit - Hold + shoot - resolved by
## the core through CoreActivation.drive on the table's own tray equals the table's own AI path (_run_ai_shooting) seed
## for seed: the surviving models, Shaken, the tray RNG after. In the core run the dead leave right after the saves (O4 b,
## read at the morale throw) and the removals the steps landed equal the binding's delta. The battle-log lines of both
## runs are compared and PRINTED as a diff summary, not asserted (step 27).
## Real: the main scene, NmlCore, the table's volley code. Constructed: a plain 10 vs 5 at 12", both seats AI (no save
## prompt waits). NML_ONE_CORE_SEEDS overrides the 200 seeds (1000 locally).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
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
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true   # tray faces from the seeded tray RNG, no physics settle


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One seed, one run, on fresh units. Returns what the comparison reads, plus the core's answer in a core run.
func _run(s: int, core_run: bool) -> Dictionary:
	var att: GameUnit = ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Att", "models": 10, "x_in": 0.0}),
		RIFLE)
	var foe: GameUnit = ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Def", "models": 5, "x_in": 12.0}),
		{})
	var lines: Array = []
	var on_entry := func(e: Dictionary) -> void: lines.append("%d|%s" % [int(e["category"]), str(e["text"])])
	_main.battle_log.entry_added.connect(on_entry)
	_main.seed_tray_rng(s)
	var out := {"bad": []}
	if core_run:
		var h := CoreActivation.capture(_main)
		var t: Array = [{"t": "begin"}, {"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": foe.unit_id}]
		var before := foe.get_alive_models()
		var throws: Array = []
		var on_throw := func(k: String, _i: int) -> void: throws.append([k, foe.get_alive_count()])
		out = await CoreActivation.drive(_main, h, att, t, true, on_throw)
		out["bad"] = [] if str(out["step"]) == "done" else ["core answered %s" % out]
		var core: Object = (_main.solo_controller as SoloController)._core_node_ready()
		core.release(h)   # the test frees its own handles (the capture and the done state)
		core.release(int(out.get("handle", 0)))
		var saved := false
		for th in throws:   # O4 b: every throw after the saves (the morale test) sees the final survivors
			if saved and int(th[1]) != foe.get_alive_count():
				out["bad"].append("%d alive at the morale throw, %d after" % [th[1], foe.get_alive_count()])
			saved = saved or str(th[0]) == "defense"
		var landed: Array = range(before.size()).filter(func(i: int) -> bool: return not before[i].is_alive)
		var removed: Array = []
		for d in out.get("delta", []):
			removed = Array(d["removed"]) if str(d["unit"]) == foe.unit_id else removed
		removed.sort()
		if landed != removed:
			out["bad"].append("landed removals %s, delta removed %s" % [landed, removed])
	else:
		await _main._run_ai_shooting({"unit": att, "moved": false})
	_main.battle_log.entry_added.disconnect(on_entry)
	var survivors: Array = foe.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	survivors.sort()
	out.merge({"survivors": survivors, "shaken": foe.is_shaken, "rng": _main._tray_rng.state, "lines": lines}, true)
	for u in [att, foe]:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			(m as ModelInstance).node.free()
	return out


func test_hold_and_shoot_equals_the_table(timeout := 900000) -> void:
	var seeds := int(OS.get_environment("NML_ONE_CORE_SEEDS")) if OS.has_environment("NML_ONE_CORE_SEEDS") else 200
	var bad: Array = []
	var line_diffs: Array = []
	var steps := 0
	var core_us := 0
	var max_us := 0
	for s in seeds:
		var table := await _run(s, false)
		var core := await _run(s, true)
		steps += int(core.get("steps", 0))
		core_us += int(core.get("core_us", 0))
		max_us = maxi(max_us, int(core.get("max_us", 0)))
		for k in ["survivors", "shaken", "rng"]:
			if table[k] != core[k]:
				core["bad"].append("%s: table %s, core %s" % [k, table[k], core[k]])
		for b in core["bad"]:
			bad.append("seed %d: %s" % [s, b])
		if table["lines"] != core["lines"]:
			line_diffs.append("seed %d\n table %s\n core  %s" % [s, "\n       ".join(table["lines"]),
				"\n       ".join(core["lines"])])
	print("ONE_CORE_ACTIVATION case=hold seeds=%d mismatches=%d line_diffs=%d mean_us=%.1f max_us=%d handles=%d" % [
		seeds, bad.size(), line_diffs.size(), float(core_us) / maxi(steps, 1), max_us,
		int((_main.solo_controller as SoloController)._core_node_ready().live_handles())])
	if not line_diffs.is_empty():
		print("ONE_CORE_ACTIVATION first line diff (not asserted until step 27): ", line_diffs[0])
	assert_array(bad).override_failure_message("core vs table:\n" + "\n".join(bad.slice(0, 10))).is_empty()
