extends GdUnitTestSuite
## One-core P3 steps 22 + 22b (the spike gate #2647, reworked): one AI activation of a plain unit - Hold + shoot, or
## Advance 4" + shoot on an open or a terrain board - resolved by the core through CoreActivation.drive on the table's
## own tray equals the table's own AI path (_run_ai_shooting) seed for seed: the attacks (the table's scaled count vs
## the core's hit dice), the surviving models, Shaken, the tray RNG after. In the core run the dead leave right after the
## saves (O4 b, read at the morale throw) and the removals the steps landed equal the binding's delta. Step 27: both
## runs add the same battle-log lines, (category, text) in the same order.
## Real: the main scene, NmlCore, the table's volley, move and sight code. Constructed: plain shooters vs 5 at 12" (the
## seed picks the shooters' shape, SHAPES: weapon copies vs models, the dead, a per-model loadout or none, step 42d),
## both seats AI (no save prompt waits). NML_ONE_CORE_SEEDS overrides the 200 seeds (1000 locally).

const INCH := 0.0254
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
	_main._solo_fast = true    # the Advance glide at fast pace
	_main._autosave_controller.set_lesson_paused(true)   # a long run's periodic autosave would add its own log line


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Review item B2: one terrain board - a painted forest cell, a painted ruin cell (see-through from rules 3.6), a
## map-layout container (its exact box and the painted cells it covers) and a free shelf forest piece - each in the
## sight lines of its own shooters after the Advance (eye lines clear of every edge by >= 0.3"). `_run` shifts the
## units into the board's lanes.
func _terrain_board() -> void:
	var o = _main.terrain_overlay
	o.grid_cells[o.world_to_cell(Vector3(7.5, 0, 4.5) * INCH)] = o.TerrainType.FOREST
	o.grid_cells[o.world_to_cell(Vector3(7.5, 0, 1.5) * INCH)] = o.TerrainType.RUINS
	o._blocker_obbs.append({"c": Vector2(8.0, 6.8) * INCH, "he": Vector2(3.0, 1.5) * INCH, "yaw": 0.0})
	for x in [7.5, 10.5]:
		o.grid_cells[o.world_to_cell(Vector3(x, 0, 7.5) * INCH)] = o.TerrainType.CONTAINER
	var shelf := {"type": int(o.TerrainType.FOREST), "c": Vector2(5.5, 3.5) * INCH, "he": Vector2(0.5, 1.5) * INCH,
		"yaw": 0.0}
	o.sandbox_shapes_provider = func() -> Array: return [shelf]
	o._los_volumes_dirty = true


## Step 42d: seed `s`'s shooters - [models, copies of their one Rifle (A1 each), models already dead]; every second
## pass of the list the models carry their own loadout (the last `copies` the Rifle, the rest a CCW), so the table counts
## the living bearers - [5, 3, 3] has none left; without a loadout it keeps the unit's ratio. Seed 0 is the original 10.
const SHAPES := [[10, 10, 0], [5, 1, 0], [5, 3, 0], [5, 5, 0], [5, 7, 0], [5, 3, 1], [5, 3, 3]]


func _shape(s: int) -> Dictionary:
	var sh: Array = SHAPES[s % SHAPES.size()]
	return {"models": sh[0], "copies": sh[1], "dead": sh[2], "loadout": s % (2 * SHAPES.size()) >= SHAPES.size()}


## Gives `att` the shape's loadout and its dead (the last models; their bases leave every sight line).
func _kit_out(att: GameUnit, sh: Dictionary) -> void:
	for i in att.models.size():
		var m: ModelInstance = att.models[i]
		if sh["loadout"]:
			m.properties["weapons"] = [{"name": "Rifle" if i >= att.models.size() - int(sh["copies"]) else "CCW",
				"attacks": 1}]
		if i >= att.models.size() - int(sh["dead"]):
			m.is_alive = false
			m.wounds_current = 0
			m.node.global_position.x -= 30.0 * INCH


## One seed, one run, on fresh units. Returns what the comparison reads, plus the core's answer in a core run.
func _run(s: int, advance: bool, board: bool, core_run: bool) -> Dictionary:
	var sh := _shape(s)
	# One name (roster key) per shape: the binding keeps the statics it built for a set of unit keys, so a shape that
	# reused seed 0's key would be resolved with seed 0's profile.
	var att: GameUnit = ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Att%d" % (s % SHAPES.size()),
		"models": sh["models"], "x_in": 0.0}), RIFLE.merged({"count": sh["copies"]}, true))
	_kit_out(att, sh)
	var foe: GameUnit = ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Def", "models": 5, "x_in": 12.0}),
		{})
	for m in att.models + foe.models if board else []:   # the board's lanes: shooters 0.4", targets 1.6" up the table
		m.node.global_position.z += (0.4 if m.unit == att else 1.6) * INCH
	var paths: Array = []
	for m in att.get_alive_models() if advance else []:   # every shooter 4" toward the foe, same in both runs
		paths.append({"model": m, "path": [m.node.global_position, m.node.global_position + Vector3(4.0 * INCH, 0, 0)]})
	var lines: Array = []
	var on_entry := func(e: Dictionary) -> void: lines.append("%d|%s" % [int(e["category"]), str(e["text"])])
	_main.battle_log.entry_added.connect(on_entry)
	_main.seed_tray_rng(s)
	var out := {"bad": []}
	if core_run:
		var h := CoreActivation.capture(_main)
		var t: Array = [{"t": "begin"}]
		if advance:
			t.append({"t": "placed", "positions": paths.map(func(p: Dictionary) -> Vector3: return p["path"][1])})
			for p in paths:
				(p["model"] as ModelInstance).node.global_position = p["path"][1]
		var kind := AiDecision.Action.ADVANCE if advance else AiDecision.Action.HOLD
		t.append({"t": "intent", "kind": kind, "shoot": foe.unit_id})
		# The table's own count of models with range and sight (main._solo_shot_eligibility), from the same spots, and
		# the attacks it scales from them (42d: copies and living bearers, SoloController.scaled_attacks_report).
		var sighted: int = _main._solo_sighted_count(att, foe, RIFLE["range_in"], false, null, false, null, true)
		var prof: Dictionary = AiShooting.profiles_in_range((att.source_data as OPRApiClient.OPRUnit).weapons,
			float(RIFLE["range_in"]))[0]
		var want := int(SoloController.scaled_attacks_report(att, prof, sighted, att.models.size())["attacks"])
		var before := foe.get_alive_models()
		var throws: Array = []
		var on_throw := func(k: String, _i: int) -> void: throws.append([k, foe.get_alive_count()])
		out = await CoreActivation.drive(_main, h, att, t, true, on_throw)
		out["bad"] = [] if str(out["step"]) == "done" else ["core answered %s" % out]
		var dice := 0   # the core's hit dice
		for e in t.filter(func(e: Dictionary) -> bool: return str(e["t"]) == "faces").slice(0, 1):
			dice = (e["faces"] as Array).size()
		if dice != want:
			out["bad"].append("attacks: the table fires %d (%d models in sight), the core throws %d dice" % [want, sighted,
				dice])
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
		await _main._solo_animate_move(paths)
		await _main._run_ai_shooting({"unit": att, "moved": advance})
	_main.battle_log.entry_added.disconnect(on_entry)
	var survivors: Array = foe.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	survivors.sort()
	out.merge({"survivors": survivors, "shaken": foe.is_shaken, "rng": _main._tray_rng.state, "lines": lines}, true)
	for u in [att, foe]:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			(m as ModelInstance).node.free()
	return out


func _gate(advance: bool, board: bool) -> void:
	var seeds := int(OS.get_environment("NML_ONE_CORE_SEEDS")) if OS.has_environment("NML_ONE_CORE_SEEDS") else 200
	var bad: Array = []
	var line_diffs: Array = []
	var steps := 0
	var core_us := 0
	var max_us := 0
	for s in seeds:
		var table := await _run(s, advance, board, false)
		var core := await _run(s, advance, board, true)
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
	print("ONE_CORE_ACTIVATION case=%s seeds=%d mismatches=%d line_diffs=%d mean_us=%.1f max_us=%d handles=%d" % [
		"terrain" if board else "advance" if advance else "hold", seeds, bad.size(), line_diffs.size(),
		float(core_us) / maxi(steps, 1), max_us,
		int((_main.solo_controller as SoloController)._core_node_ready().live_handles())])
	if not line_diffs.is_empty():
		print("ONE_CORE_ACTIVATION first line diff: ", line_diffs[0])
	assert_array(bad).override_failure_message("core vs table:\n" + "\n".join(bad.slice(0, 10))).is_empty()
	assert_array(line_diffs).override_failure_message("battle-log lines differ in %d seeds, first:\n%s" % [
		line_diffs.size(), "" if line_diffs.is_empty() else line_diffs[0]]).is_empty()


func test_hold_and_shoot_equals_the_table(timeout := 900000) -> void:
	await _gate(false, false)


func test_advance_and_shoot_equals_the_table(timeout := 900000) -> void:
	await _gate(true, false)


func test_advance_on_a_terrain_board_equals_the_table(timeout := 900000) -> void:
	_terrain_board()
	await _gate(true, true)
