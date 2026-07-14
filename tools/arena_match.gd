extends SceneTree
## AI ARENA — run ONE native both-AI match to the scoring end, with a DIFFICULTY GRADE per side. The
## foundation launcher the rating-ladder tooling drives: it boots the real game, imports two armies, autogens
## a symmetric board, performs the OFFICIAL deployment roll-off (the winner deploys first and takes round 1's
## first turn), deploys both sides with the production AI deployment, arms native both-AI mode with the
## graded sides, and runs main._solo_run_both_ai_game() unattended (no dialogs — the AI defender auto-rolls on
## the real dice tray). Same seed + same grades ⇒ identical decisions (the difficulty knobs are seeded).
##
## Run (grades: rekrut | veteran | kriegsherr | albtraum):
##   NML_AI_P1=rekrut NML_AI_P2=kriegsherr NML_AI_SEED=7 \
##     flatpak run --filesystem=home org.godotengine.Godot --path <worktree> \
##       -s res://tools/arena_match.gd
## Headless works for the decision/rules layer; a Vulkan display (or gamescope --backend headless) is needed
## for the physics-probe deployment. Grades/seed may also be passed as -- p1=rekrut p2=kriegsherr seed=7.
##
## Rating-ladder extensions (env / `--` args):
##   dice_seed= / NML_AI_DICE_SEED — re-seeds ONLY the global RNG after deployment. Its sole in-match
##     consumer is the dice tray, so the same seed= board/deploy/AI-pick can be replayed under different
##     dice (the harness-proven stream split). Default: == seed (bare runs keep one seed for everything).
##   army1= army2= / NML_AI_ARMY1 NML_AI_ARMY2 — army-list JSON paths per side (res:// or absolute),
##     defaulting to the tutorial fixtures, so pairings can swap lists without file copies.
##   out= / NML_AI_OUT — directory for the machine-readable per-game result JSON
##     (default: $HOME/selfplay_out). File: arena_<p1>_vs_<p2>_s<seed>_d<dice_seed>.json.
##   capture= / NML_AI_CAPTURE — showcase-artifact directory. When set, the run ADDITIONALLY writes
##     board screenshots (deploy.png after both deployments, round<N>.png at each round end — needs a
##     display; use `gamescope --backend headless`, PNGs are skipped under the headless dummy renderer),
##     the FULL battle log (battlelog.txt — collected via entry_added, so the panel's 200-entry ring
##     buffer cap does not truncate it) and EVERY decision record verbatim (decisions.json, annotated
##     with side + round). Ladder runs without capture= are byte-identical to before.

const P1_FIXTURE := "res://assets/tutorial/tutorial_army_p1.json"
const P2_FIXTURE := "res://assets/tutorial/tutorial_army_p2.json"
const IN2M := 0.0254
const FRONT_LINE := 1            # MapLayout.DeploymentType.FRONT_LINE
const LAYOUT_SEED := 20260710
const MAX_BOOT_FRAMES := 1200
const SPAWN_SETTLE_FRAMES := 90
const RESULT_SCHEMA := 1

var _p1_grade := "kriegsherr"
var _p2_grade := "kriegsherr"
var _seed := 0
var _dice_seed := 0
var _dice_seed_explicit := false
var _army1 := P1_FIXTURE
var _army2 := P2_FIXTURE
var _out_dir := ""

# Decision capture (via SoloController.decision_sink): per-side per-kind counts for every record, plus the
# verbatim knob/roll-off records the ladder's monotonicity diagnosis reads ("which knob failed to bite").
var _decision_counts: Dictionary = {}   # side(int) → {kind(String): count}
var _knob_records: Array = []           # full records of kind roll_off / difficulty (+side/round annotation)

# Showcase capture (capture= / NML_AI_CAPTURE) — board PNGs + full battle log + verbatim decisions.
var _capture_dir := ""                  # empty => captures off (the ladder default)
var _all_decisions: Array = []          # EVERY decision record verbatim, annotated {side, round}
var _log_entries: Array = []            # every battle-log entry (the panel itself caps at 200)


func _initialize() -> void:
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	_run.call_deferred()


func _run() -> void:
	_parse_config()
	var t0 := Time.get_ticks_msec()
	printerr("[ARENA] both-AI match — P1=%s vs P2=%s (seed %d, dice_seed %d%s)" % [
		_p1_grade, _p2_grade, _seed, _dice_seed, "" if _dice_seed_explicit else " derived"])
	change_scene_to_file("res://scenes/main.tscn")
	var main: Node = await _await_main()
	if main == null:
		printerr("[ARENA] FATAL: main.tscn never became ready — see main.gd parse errors above")
		quit(1)
		return
	printerr("[ARENA] main.tscn ready")   # main.gd parsed + _ready ran — the launch gate

	var army_manager: Node = main.get("opr_army_manager")
	var layout_editor: Control = main.get("map_layout_editor")
	var terrain_overlay: Node = main.get("terrain_overlay")
	var table: Node = main.get("table")
	var battle_log: Node = main.get("battle_log")
	if army_manager == null or layout_editor == null or terrain_overlay == null or table == null or battle_log == null:
		printerr("[ARENA] FATAL: a manager is missing")
		quit(1)
		return

	if not _capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_capture_dir)
		# Full-log collection: the Battle Log panel's data source is a 200-entry ring buffer, so a
		# whole match overflows it — mirror every entry as it is logged and dump the mirror at the end.
		battle_log.entry_added.connect(func(entry: Dictionary) -> void: _log_entries.append(entry))
		# Round-end boards: advance_round() emits AFTER the round's auto-seize, i.e. exactly at the
		# round boundary — new_round-1 is the round that just ended (rounds 1..3; the final round has
		# no advance and is captured after the game returns).
		army_manager.round_advanced.connect(func(new_round: int) -> void:
			await _capture_board(main, "round%d.png" % (new_round - 1)))

	main.set("_solo_fast", true)
	main.set("_solo_dev", OS.get_environment("NML_AI_DEV") == "1")

	if not await _import_and_spawn(army_manager, _army1, 1):
		return
	if not await _import_and_spawn(army_manager, _army2, 2):
		return
	for _i in range(SPAWN_SETTLE_FRAMES):
		await process_frame

	# Symmetric board: the game's own OPR terrain autogen + FRONT_LINE zones + three centre objectives.
	seed(LAYOUT_SEED)
	layout_editor._generate_terrain_layout()
	layout_editor.deployment_type = FRONT_LINE
	layout_editor._rebuild_derived()
	layout_editor._emit_layout_update()
	layout_editor.deployment_type_changed.emit(FRONT_LINE)
	await process_frame
	# Objectives: three centre-line markers written DIRECTLY to the overlay in WORLD METRES (the
	# harness-proven fix): routing table-centred inches through layout_editor.mission_objectives /
	# get_objectives_for_overlay() double-shifts them ≈(-24,-24)" into P1's back corner (that seam expects
	# the grid-origin inch frame), which turned every game into a 0-0 objective draw. Centred inches × IN2M
	# ARE world metres; objectives_provider / _solo_auto_seize read the overlay live, so AI + scoring agree.
	var objectives_in: Array[Vector2] = [Vector2(-16.0, 0.0), Vector2(0.0, 0.0), Vector2(16.0, 0.0)]
	var obj_world: Array = []
	for o in objectives_in:
		obj_world.append(Vector3((o as Vector2).x * IN2M, 0.0, (o as Vector2).y * IN2M))
	terrain_overlay.update_objectives(obj_world)
	await process_frame
	var placed: Array = terrain_overlay.get_objectives()
	var half_w_m: float = table.table_size.x * 0.3048 / 2.0
	var half_d_m: float = table.table_size.y * 0.3048 / 2.0
	if placed.size() != objectives_in.size():
		printerr("[ARENA] FATAL: overlay reports %d objectives, expected %d" % [placed.size(), objectives_in.size()])
		quit(1)
		return
	for oi in range(placed.size()):
		var op := placed[oi] as Vector3
		if absf(op.x) > half_w_m or absf(op.z) > half_d_m:
			printerr("[ARENA] FATAL: objective #%d OFF TABLE at (%.3f, %.3f) m" % [oi + 1, op.x, op.z])
			quit(1)
			return
	printerr("[ARENA] objectives on table: %d (centre-line spread, all within bounds)" % placed.size())

	# Arm native both-AI with the graded sides, then wire the controller for the whole board.
	main.set_both_ai(true, _p1_grade, _p2_grade, _seed)
	main._ensure_solo_controller()
	var solo: Node = main.get("solo_controller")
	if solo == null:
		printerr("[ARENA] FATAL: SoloController not created")
		quit(1)
		return
	solo._rng.seed = _seed
	solo.decision_sink = func(rec: Dictionary) -> void:
		var side: int = int(solo.ai_slot)
		var by_kind: Dictionary = _decision_counts.get(side, {})
		var kind := str(rec.get("kind", "?"))
		by_kind[kind] = int(by_kind.get(kind, 0)) + 1
		_decision_counts[side] = by_kind
		if kind == "roll_off" or kind == "difficulty":
			var annotated := rec.duplicate(true)
			annotated["side"] = side
			annotated["round"] = int(army_manager.current_round)
			_knob_records.append(annotated)
		if not _capture_dir.is_empty():
			var full := rec.duplicate(true)
			full["side"] = side
			full["round"] = int(army_manager.current_round)
			_all_decisions.append(full)

	# OFFICIAL deployment roll-off (highest die wins, ties re-roll — drawn from the seeded controller RNG,
	# so the winner is reproducible per seed): the winner deploys FIRST and takes round 1's first turn.
	var opener: int = solo.roll_off()
	printerr("[ARENA] roll-off: P%d wins — deploys first, opens round 1 (official rule)" % opener)

	# Production AI deployment for BOTH sides into their 12" front-line zones, in roll-off order. The
	# per-side deployment seed stays attached to the SLOT (seed+slot), so a side's deployment is identical
	# across the swapped games of a ladder pairing regardless of who won the roll-off.
	var objectives: Array = terrain_overlay.get_objectives()
	var objectives_v2: Array = []
	for o in objectives:
		objectives_v2.append(Vector2((o as Vector3).x, (o as Vector3).z))
	var deploy_order: Array = [1, 2] if opener == 1 else [2, 1]
	for slot in deploy_order:
		_deploy_side(main, solo, table, terrain_overlay, int(slot), objectives_v2, _seed + int(slot))
	await process_frame
	# Deployment board BEFORE the dice re-seed below, so the capture's frame ticks cannot leak into
	# the dice stream (seed(_dice_seed) resets the global RNG right after either way).
	await _capture_board(main, "deploy.png")

	# Dice-stream split (harness-proven): everything board-shaped is fixed above (terrain under the layout
	# seed, deployment under its per-slot seeds, AI pick/D3 under solo._rng = seed). The only remaining
	# global-RNG consumer during the rounds is the dice tray, so re-seeding here isolates "the dice" as an
	# independent stream: same seed + different dice_seed ⇒ identical board/deploy, different game course.
	seed(_dice_seed)

	# Run the whole match unattended to the SOLO_GAME_ROUNDS scoring end, opened by the roll-off winner.
	army_manager.current_round = 1
	battle_log.log_event(0, "=== AI ARENA: %s (P1) vs %s (P2) — seed %d dice %d, P%d opens ===" % [
		_p1_grade, _p2_grade, _seed, _dice_seed, opener], true)
	await main._solo_run_both_ai_game(opener)

	# Final-round board: the last round never advance_round()s, so it is captured here — after hiding
	# the game-over AcceptDialog the summary pops (it would sit centred over the table).
	if not _capture_dir.is_empty():
		for c in main.get_children():
			if c is Window and (c as Window).visible:
				(c as Window).hide()
		await _capture_board(main, "round%d.png" % int(army_manager.current_round))

	# Report the objective outcome (the rating signal) + the machine-readable result JSON.
	var owners: Array = terrain_overlay.get_objective_owners() if terrain_overlay.has_method("get_objective_owners") else []
	var p1 := 0
	var p2 := 0
	var neutral := 0
	for o in owners:
		if int(o) == 1:
			p1 += 1
		elif int(o) == 2:
			p2 += 1
		else:
			neutral += 1
	var winner := "draw"
	if p1 != p2:
		winner = "p1" if p1 > p2 else "p2"
	elif owners.is_empty():
		# No markers (not the ladder board): documented fallback — surviving models decide, ties draw.
		var a1: int = int(main._solo_side_alive(1))
		var a2: int = int(main._solo_side_alive(2))
		if a1 != a2:
			winner = "p1" if a1 > a2 else "p2"
	printerr("[ARENA] RESULT seed=%d dice=%d P1(%s) objectives=%d P2(%s) objectives=%d → %s" % [
		_seed, _dice_seed, _p1_grade, p1, _p2_grade, p2, winner])
	_write_result_json(main, army_manager, opener, winner,
		{"p1": p1, "p2": p2, "neutral": neutral}, float(Time.get_ticks_msec() - t0) / 1000.0)
	_write_capture_outputs()
	quit(0)


# === Showcase capture (capture= / NML_AI_CAPTURE) ===

## Board screenshot into the capture dir: re-frame the camera high-angle over the table centre (units +
## objective markers recognizable), freeze the tree for the draw, grab the root viewport. No-op without
## capture=; skipped (with a note) under the headless dummy renderer — run under gamescope for PNGs.
func _capture_board(main: Node, file_name: String) -> void:
	if _capture_dir.is_empty():
		return
	if DisplayServer.get_name() == "headless":
		printerr("[ARENA] capture SKIPPED (headless dummy renderer): %s" % file_name)
		return
	var pivot: Node3D = main.get("camera_pivot")
	if pivot != null:
		# Whole-table framing via the camera controller's own state (its _process applies it, but we
		# apply directly because the tree is paused during the grab): top-down-ish pitch, table centre.
		pivot.set("_target_position", Vector3.ZERO)
		pivot.set("_yaw", 0.0)
		pivot.set("_pitch", -75.0)
		pivot.set("_current_zoom", 2.0)
		if pivot.has_method("_apply_camera_transform"):
			pivot.call("_apply_camera_transform")
	paused = true   # freeze game motion so the round-end board is exactly what gets drawn
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image() if root.get_texture() != null else null
	paused = false
	if img == null or img.is_empty():
		printerr("[ARENA] capture FAILED (empty frame): %s" % file_name)
		return
	var path := _capture_dir.path_join(file_name)
	if img.save_png(path) == OK:
		printerr("[ARENA] capture -> %s" % path)
	else:
		printerr("[ARENA] capture WRITE FAILED: %s" % path)


## End-of-run showcase artifacts: the FULL battle log (mirror of every entry_added — no ring-buffer
## truncation) and EVERY decision record verbatim (side/round-annotated), both into the capture dir.
func _write_capture_outputs() -> void:
	if _capture_dir.is_empty():
		return
	var title := "AI ARENA %s (P1) vs %s (P2) — seed %d dice %d" % [_p1_grade, _p2_grade, _seed, _dice_seed]
	var log_f := FileAccess.open(_capture_dir.path_join("battlelog.txt"), FileAccess.WRITE)
	if log_f != null:
		log_f.store_string(BattleLog.export_text(_log_entries, [], title))
		log_f.close()
		printerr("[ARENA] battle log (%d entries) -> %s" % [_log_entries.size(), _capture_dir.path_join("battlelog.txt")])
	var dec_f := FileAccess.open(_capture_dir.path_join("decisions.json"), FileAccess.WRITE)
	if dec_f != null:
		dec_f.store_string(JSON.stringify(_all_decisions, "  "))
		dec_f.close()
		printerr("[ARENA] decisions (%d records) -> %s" % [_all_decisions.size(), _capture_dir.path_join("decisions.json")])


## The per-game result artifact the ladder tooling aggregates: identity (grades/seeds/armies/sides),
## the roll-off + opener, the objective score + winner, survivors, the knob presets, per-side decision
## counts, and the verbatim difficulty/roll-off records (the monotonicity-diagnosis evidence).
func _write_result_json(main: Node, army_manager: Node, opener: int, winner: String,
		objectives: Dictionary, duration_sec: float) -> void:
	var result := {
		"schema": RESULT_SCHEMA,
		"tool": "arena_match",
		"seed": _seed,
		"dice_seed": _dice_seed,
		"grades": {"p1": _p1_grade, "p2": _p2_grade},
		"armies": {"p1": _army1, "p2": _army2},
		"opener": opener,
		"rounds_played": int(army_manager.current_round),
		"objectives": objectives,
		"winner": winner,
		"survivors": {
			"p1": _survivors(main, army_manager, 1),
			"p2": _survivors(main, army_manager, 2),
		},
		"knobs": {
			"p1": SoloDifficulty.for_grade(_p1_grade, _seed).to_dict(),
			"p2": SoloDifficulty.for_grade(_p2_grade, _seed).to_dict(),
		},
		"decision_counts": _stringify_keys(_decision_counts),
		"knob_records": _knob_records,
		"duration_sec": duration_sec,
	}
	if _out_dir.is_empty():
		_out_dir = OS.get_environment("HOME").path_join("selfplay_out")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var fname := "arena_%s_vs_%s_s%d_d%d.json" % [_p1_grade, _p2_grade, _seed, _dice_seed]
	var path := _out_dir.path_join(fname)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[ARENA] WARN: cannot write result JSON: %s" % path)
		return
	f.store_string(JSON.stringify(result, "  "))
	f.close()
	printerr("[ARENA] result JSON: %s" % path)


func _survivors(main: Node, army_manager: Node, pid: int) -> Dictionary:
	var units_alive := 0
	for u in army_manager.get_game_units_for_player(pid):
		if u != null and int(u.get_alive_count()) > 0:
			units_alive += 1
	return {"units": units_alive, "models": int(main._solo_side_alive(pid))}


## JSON.stringify keeps int keys as-is (non-standard JSON) — normalise the side keys to strings.
func _stringify_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = d[k]
	return out


func _import_and_spawn(army_manager: Node, fixture: String, player_id: int) -> bool:
	var text := FileAccess.get_file_as_string(fixture)
	if text.is_empty():
		printerr("[ARENA] FATAL: fixture missing/empty: %s" % fixture)
		quit(1)
		return false
	var army = await army_manager.api_client._parse_tts_api_response(text)
	if army == null or army.units.is_empty():
		printerr("[ARENA] FATAL: player %d import produced no units (network needed for the army-book fetch?)" % player_id)
		quit(1)
		return false
	army.player_id = player_id
	army_manager.get("armies")[player_id] = army
	await army_manager.spawn_army(army)
	printerr("[ARENA] player %d = '%s' — %d units spawned" % [player_id, army.name,
		army_manager.get_game_units_for_player(player_id).size()])
	return true


func _deploy_side(main: Node, solo: Node, table: Node, terrain_overlay: Node, slot: int, objectives_v2: Array, seed_value: int) -> void:
	solo.ai_slot = slot
	solo.human_slot = 2 if slot == 1 else 1
	var w: float = table.table_size.x * 0.3048
	var d: float = table.table_size.y * 0.3048
	var depth: float = 12.0 * IN2M
	var zmin: float = (-d / 2.0) if slot == 1 else (d / 2.0 - depth)
	var zone := Rect2(Vector2(-w / 2.0, zmin), Vector2(w, depth))
	var space = terrain_overlay.get_world_3d().direct_space_state if terrain_overlay != null else null
	var probe := PhysicsShapeQueryParameters3D.new()
	var probe_shape := SphereShape3D.new()
	probe_shape.radius = 0.02
	probe.shape = probe_shape
	probe.collide_with_areas = false
	var hits_prop := func(p: Vector2) -> bool:
		if space == null:
			return false
		probe.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, 0.07, p.y))
		for hit in space.intersect_shape(probe, 6):
			var col: Object = hit.get("collider")
			if col is Node3D and not (col as Node3D).is_in_group("miniature"):
				return true
		return false
	var blocked_normal := func(p: Vector2) -> bool:
		if hits_prop.call(p):
			return true
		var t: int = terrain_overlay.get_terrain_at_world_position(Vector3(p.x, 0.0, p.y))
		return t == terrain_overlay.TerrainType.FOREST or t == terrain_overlay.TerrainType.DANGEROUS \
			or t == terrain_overlay.TerrainType.CONTAINER or t == terrain_overlay.TerrainType.RUINS
	var blocked_flying := func(p: Vector2) -> bool:
		if hits_prop.call(p):
			return true
		var t: int = terrain_overlay.get_terrain_at_world_position(Vector3(p.x, 0.0, p.y))
		return t == terrain_overlay.TerrainType.CONTAINER or t == terrain_overlay.TerrainType.RUINS
	var res: Dictionary = solo.deploy_army(zone, objectives_v2, blocked_normal, blocked_flying, seed_value)
	for u in solo.ambush_reserve:
		main._solo_set_unit_visible(u, false)
	printerr("[ARENA] P%d deployed %d units (%d reserve)" % [slot, int(res.get("deployed", 0)), int(res.get("reserved", 0))])


func _await_main() -> Node:
	for _i in range(MAX_BOOT_FRAMES):
		await process_frame
		var scene := current_scene
		if scene != null and scene.get("opr_army_manager") != null and scene.get("map_layout_editor") != null \
				and scene.get("terrain_overlay") != null and scene.get("battle_log") != null:
			return scene
	return null


## Grades/seeds/armies/out dir from env (NML_AI_P1/P2/SEED/DICE_SEED/ARMY1/ARMY2/OUT) or `--` cmdline args
## (p1= p2= seed= dice_seed= army1= army2= out=). Args win over env; dice_seed defaults to seed.
func _parse_config() -> void:
	_p1_grade = _env_or("NML_AI_P1", _p1_grade)
	_p2_grade = _env_or("NML_AI_P2", _p2_grade)
	_army1 = _env_or("NML_AI_ARMY1", _army1)
	_army2 = _env_or("NML_AI_ARMY2", _army2)
	_out_dir = _env_or("NML_AI_OUT", _out_dir)
	_capture_dir = _env_or("NML_AI_CAPTURE", _capture_dir)
	var s := OS.get_environment("NML_AI_SEED").strip_edges()
	if s.is_valid_int():
		_seed = int(s)
	var ds := OS.get_environment("NML_AI_DICE_SEED").strip_edges()
	if ds.is_valid_int():
		_dice_seed = int(ds)
		_dice_seed_explicit = true
	for arg in OS.get_cmdline_user_args():
		var a := str(arg)
		if a.begins_with("p1="):
			_p1_grade = a.substr(3)
		elif a.begins_with("p2="):
			_p2_grade = a.substr(3)
		elif a.begins_with("seed=") and a.substr(5).is_valid_int():
			_seed = int(a.substr(5))
		elif a.begins_with("dice_seed=") and a.substr(10).is_valid_int():
			_dice_seed = int(a.substr(10))
			_dice_seed_explicit = true
		elif a.begins_with("army1="):
			_army1 = a.substr(6)
		elif a.begins_with("army2="):
			_army2 = a.substr(6)
		elif a.begins_with("out="):
			_out_dir = a.substr(4)
		elif a.begins_with("capture="):
			_capture_dir = a.substr(8)
	if not _dice_seed_explicit:
		_dice_seed = _seed


func _env_or(key: String, fallback: String) -> String:
	var v := OS.get_environment(key).strip_edges()
	return v if v != "" else fallback
