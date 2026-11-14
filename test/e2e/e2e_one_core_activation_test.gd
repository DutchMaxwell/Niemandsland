extends GdUnitTestSuite
## One-core P3 steps 22 + 22b (the spike gate #2647, reworked): one AI activation of a plain unit - Hold + shoot, or
## Advance 4" + shoot on an open or a terrain board - resolved by the core through CoreActivation.drive on the table's
## own tray equals the table's own AI path (_run_ai_shooting) seed for seed: the attacks (the table's scaled count vs
## the core's hit dice), the surviving models, Shaken, the tray RNG after. In the core run the dead leave right after the
## saves (O4 b, read at the morale throw) and the removals the steps landed equal the binding's delta. Step 27: both
## runs add the same battle-log lines, (category, text) in the same order.
## Step 22c adds the terrain board once more with its free forest as a real 3D sandbox piece (ObjectManager, rotated).
## Real: the main scene, NmlCore, the table's volley, move and sight code. Constructed: plain shooters vs 5 at 12" (the
## seed picks the shooters' shape, SHAPES: weapon copies vs models, the dead, a per-model loadout or none, step 42d),
## both seats AI (no save prompt waits). NML_ONE_CORE_SEEDS overrides the 200 seeds (1000 locally).

const INCH := 0.0254
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []}
const SANDBOX_AT := Vector2(8.5, -1.0)   # the free forest's centre on the sandbox board, inches
const SANDBOX_YAW := 45.0                # its rotation about the table's up axis, degrees

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
	_painted_board()
	var o = _main.terrain_overlay
	var shelf := {"type": int(o.TerrainType.FOREST), "c": Vector2(5.5, 3.5) * INCH, "he": Vector2(0.5, 1.5) * INCH,
		"yaw": 0.0}
	o.sandbox_shapes_provider = func() -> Array: return [shelf]
	o._los_volumes_dirty = true


## The painted part of the board: a forest cell, a ruin cell and the map-layout container with its two painted cells.
func _painted_board() -> void:
	var o = _main.terrain_overlay
	o.grid_cells[o.world_to_cell(Vector3(7.5, 0, 4.5) * INCH)] = o.TerrainType.FOREST
	o.grid_cells[o.world_to_cell(Vector3(7.5, 0, 1.5) * INCH)] = o.TerrainType.RUINS
	o._blocker_obbs.append({"c": Vector2(8.0, 6.8) * INCH, "he": Vector2(3.0, 1.5) * INCH, "yaw": 0.0})
	for x in [7.5, 10.5]:
		o.grid_cells[o.world_to_cell(Vector3(x, 0, 7.5) * INCH)] = o.TerrainType.CONTAINER
	o._los_volumes_dirty = true


## Step 22c (plan item B2): the painted board above, but the free piece is a REAL 3D sandbox forest, spawned and rotated
## the way a player's drag does it (`ObjectManager.spawn_sandbox_terrain`); the overlay reads it through main's own
## `_sandbox_terrain_shapes` (node footprint, kind, position, yaw) and the core through the game header's `sandbox` list.
## Centre and yaw are chosen so the piece overlaps no other piece and its rotation decides the sight: at +45 degrees it
## blinds shooter 1 (shooters 0 and 2 keep a line, shooter 0's through the see-through ruin cell, so every shape keeps a
## model in sight); a core that read -45 degrees would blind shooter 0 instead.
func _sandbox_board() -> Node3D:
	_painted_board()
	return await _spawn_piece()


## The real forest of the sandbox board (see `_sandbox_board`), spawned now.
func _spawn_piece() -> Node3D:
	var piece: Node3D = _main.object_manager.spawn_sandbox_terrain("forest_small", ObjectManager.SandboxPropKind.FOREST,
		Vector3(SANDBOX_AT.x, 0.0, SANDBOX_AT.y) * INCH, false, 7301)
	piece.rotation.y = deg_to_rad(SANDBOX_YAW)
	await _runner.simulate_frames(2)
	var shapes: Array = _main.terrain_overlay._sandbox_shapes()   # what both the table's volumes and the header read
	assert_int(shapes.size()).is_equal(1)
	assert_int(int(shapes[0]["type"])).is_equal(TerrainRules.TerrainType.FOREST)
	assert_vector(shapes[0]["he"]).is_equal_approx(Vector2(3.0, 2.0) * INCH, Vector2(1e-6, 1e-6))
	assert_float(float(shapes[0]["yaw"])).is_equal_approx(deg_to_rad(SANDBOX_YAW), 1e-5)
	return piece


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
		var to: Vector3 = m.node.global_position + Vector3(4.0 * INCH, 0, 0)
		to.y = _main.terrain_overlay.surface_y_at(Vector2(to.x, to.z)) if board else 0.0   # stands on a roof or a floor
		paths.append({"model": m, "path": [m.node.global_position, to]})
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
		for p in paths:   # the real table settles a moved model on the surface it ends on (a roof, a floor)
			((p["model"] as ModelInstance).node as Node3D).global_position.y = (p["path"][1] as Vector3).y
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


func _gate(advance: bool, board: bool, label := "", fewer := 0) -> void:
	var seeds := int(OS.get_environment("NML_ONE_CORE_SEEDS")) if OS.has_environment("NML_ONE_CORE_SEEDS") else 200
	seeds = mini(seeds, fewer) if fewer > 0 else seeds
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
	var case_name := label if not label.is_empty() else "terrain" if board else "advance" if advance else "hold"
	print("ONE_CORE_ACTIVATION case=%s seeds=%d mismatches=%d line_diffs=%d mean_us=%.1f max_us=%d handles=%d" % [
		case_name, seeds, bad.size(), line_diffs.size(), float(core_us) / maxi(steps, 1), max_us,
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


func test_advance_on_a_board_with_a_3d_sandbox_piece_equals_the_table(timeout := 900000) -> void:
	await _sandbox_board()
	await _gate(true, true, "sandbox")


## Step 22c (1): the game header - the board the core reads - goes out with the first capture; the table reads its
## pieces live. Seed 0's core run is that first capture, then the player changes the table. 28 seeds = 4 of each shape.
func _header_sent() -> void:
	await _run(0, true, true, true)


## How many free pieces the core holds now (the header's, or the last refresh's).
func _held_pieces() -> int:
	return int(((_main.solo_controller as SoloController)._core_node_ready().header_digest())["sandbox_pieces"])


func test_a_piece_rotated_after_the_first_capture_equals_the_table(timeout := 900000) -> void:
	var piece := await _sandbox_board()
	await _header_sent()
	piece.rotation.y = deg_to_rad(-SANDBOX_YAW)   # the pose that blinds shooter 0 instead of shooter 1
	await _runner.simulate_frames(2)
	await _gate(true, true, "sandbox_rotated", 28)
	assert_int(_held_pieces()).is_equal(1)


func test_a_piece_deleted_after_the_first_capture_equals_the_table(timeout := 900000) -> void:
	var piece := await _sandbox_board()
	await _header_sent()
	piece.set_meta("deleted", true)   # what Delete does: hidden and undoable, no longer a rule
	piece.visible = false
	await _runner.simulate_frames(2)
	await _gate(true, true, "sandbox_deleted", 28)
	assert_int(_held_pieces()).is_equal(0)


func test_a_piece_added_after_the_first_capture_equals_the_table(timeout := 900000) -> void:
	_painted_board()
	await _header_sent()
	await _spawn_piece()
	await _gate(true, true, "sandbox_added", 28)
	assert_int(_held_pieces()).is_equal(1)


## The AI's own plan (`_core_plan`) hands the core the changed board too, not only a step capture. The unit pair is bare
## (nothing is planned from it): the call reaches the refresh before it plans.
func test_the_ai_plan_refreshes_the_board_too() -> void:
	var piece := await _sandbox_board()
	await _header_sent()
	piece.set_meta("deleted", true)
	piece.visible = false
	await _runner.simulate_frames(2)
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Att0", "models": 5, "x_in": 0.0}),
		RIFLE.merged({"count": 5}, true))
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Def", "models": 5, "x_in": 12.0}), {})
	var sc := _main.solo_controller as SoloController
	var state := BattleSim.capture(_main.opr_army_manager, sc.objectives_provider, sc.objective_owner_of, 1, 4,
		sc.majority_in_cover, sc._has_los, sc.terrain_type_at, int(sc.ai_slot))
	assert_int(_held_pieces()).is_equal(1)   # the header's board, before the plan
	sc._core_plan(state, 1)
	assert_int(_held_pieces()).is_equal(0)
	for u in [att, foe]:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			(m as ModelInstance).node.free()


## Step 22c (3): free pieces of other kinds, spawned as a player's drag leaves them. The core takes the placed positions
## as given (its y included), so these cases guard the path where the TABLE settles a moved model on the surface it ends
## on (`surface_y_at`: a roof) and the core reads the same height; `_run` settles the shooters so.
func _spawn(prop_id: String, kind: int, at_in: Vector2, yaw_deg: float) -> Node3D:
	var piece: Node3D = _main.object_manager.spawn_sandbox_terrain(prop_id, kind, Vector3(at_in.x, 0.0, at_in.y) * INCH,
		false, 7400 + kind)
	piece.rotation.y = deg_to_rad(yaw_deg)
	await _runner.simulate_frames(2)
	return piece


## The standing height the table gives the shooters' end spot (x 4", z 2.8"), in inches.
func _stand_in(z_in := 2.8) -> float:
	return float(_main.terrain_overlay.surface_y_at(Vector2(4.0, z_in) * INCH)) / INCH


## A free blocker on the ground: sight past it equals the table (the pose blinds shooter 0).
func test_advance_on_a_board_with_a_free_blocker_equals_the_table() -> void:
	_painted_board()
	await _spawn("blocker_6x3", ObjectManager.SandboxPropKind.BLOCKER, Vector2(8.0, -1.0), 15.0)
	assert_int(int(_main.terrain_overlay._sandbox_shapes()[0]["type"])).is_equal(TerrainRules.TerrainType.CONTAINER)
	await _gate(true, true, "free_blocker", 28)


## Shooters 1 and 2 end their Advance (x 4", z 1.6" and 2.8") on the roof of a free blocker (x 1..7", z 0.7..3.7").
func test_advance_onto_the_roof_of_a_free_blocker_equals_the_table() -> void:
	_painted_board()
	await _spawn("blocker_6x3", ObjectManager.SandboxPropKind.BLOCKER, Vector2(4.0, 2.2), 0.0)
	assert_float(_stand_in()).is_equal_approx(2.5, 0.01)   # the roof: the shooters really are lifted
	await _gate(true, true, "free_roof", 28)
