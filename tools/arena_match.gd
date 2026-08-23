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
## Off-board audit (#215): shared with tools/solo_selfplay.gd so BOTH harnesses emit the identical
## parseable line that tools/tactic_audit.py counts as d9.
const OffboardAudit := preload("res://tools/offboard_audit.gd")

var _p1_grade := "kriegsherr"
var _p2_grade := "kriegsherr"
var _seed := 0
var _dice_seed := 0
var _dice_seed_explicit := false
var _layout_seed := LAYOUT_SEED         # terrain autogen seed; layout_seed= varies the board per game (fairness probes)
var _symmetric := false                 # symmetric=1: point-symmetric terrain (tuning runs)
var _objective_count := 3               # objectives=5: five point-symmetric markers
var _mission_id := ""                   # NML_MISSION: play a catalog mission (M5); empty = legacy centre-line tuning board
var _objectives_placed := 0             # what actually reached the overlay — the stamp states played truth, not intent
var _batch := true                      # headless sweeps: instant (non-physics) dice + zero pacing holds; batch=0 forces the physics tray
var _army1 := P1_FIXTURE
var _army2 := P2_FIXTURE
var _out_dir := ""

# Decision capture (via SoloController.decision_sink): per-side per-kind counts for every record, plus the
# verbatim knob/roll-off records the ladder's monotonicity diagnosis reads ("which knob failed to bite").
var _decision_counts: Dictionary = {}   # side(int) → {kind(String): count}
var _knob_records: Array = []           # full records of kind roll_off / difficulty (+side/round annotation)
# P0 menu-coverage probe (NML-1009, NML_MENU_PROBE=1): per action class, how many
# of the TREE's activations the planner's candidate menu can express. The move
# histogram buckets the miss distance in 3" steps — "how far off the menu was".
var _menu_probe: Dictionary = {}        # class(String) → {n, covered, loose}
var _menu_miss_hist: Dictionary = {}    # 3"-bucket(String) → count (movement only)
var _teacher_rows: Array = []           # P1 imitation rows (NML_TEACHER_ROWS=1)
# Behaviour meters (terrain grill D9, NML_TERRAIN_METER=1): the maintainer's
# acceptance test, deliberately winrate-free — per side, how often an
# activation ends in cover, actually shoots, ends exposed to enemy lanes, and
# enters terrain at all. These are the BEFORE values the terrain wave moves.
var _meters: Dictionary = {}            # side(int) -> {n, cover, shot, terrain, exposed_sum, exposed_max}
# Movement plausibility capture (AI plausibility wave 1): every MOVE record's numbers, per side — the
# result JSON aggregates them into the acceptance metrics (median achieved/band on open-field moves,
# aimless sub-inch moves, large-base stall streaks, aircraft lane compliance).
var _move_records: Array = []           # {side, round, unit, why, data} for every kind == "move"
# Planner calibration capture (parity wave, NML-995): every planner record's expectation numbers, per
# side — calib_pairs() folds them into per-round-boundary (predicted, measured) pairs, the parity
# wave's progress meter (the mental model was ~0.2 too optimistic early; watch this gap shrink).
var _calib_records: Array = []          # {side, round, before, after} for planner records carrying win_before
var _unit_activations: Dictionary = {}  # slot -> {unit_name: activation count} (log-linter input)
var _position_rows: Array = []          # E1/E6: {side, round, seq, features} — EVERY planner pick

# Showcase capture (capture= / NML_AI_CAPTURE) — board PNGs + full battle log + verbatim decisions.
var _capture_dir := ""                  # empty => captures off (the ladder default)
var _act_capture: Callable = Callable() # per-activation trail dump + queued PNG (NML_CAPTURE_ACTS=1; on ai_unit_activated)
var _act_capture_png: Callable = Callable() # the queued PNG grab (main.solo_activation_done — the SETTLED board)
var _act_png_pending := ""              # file name queued by _act_capture, drained by _act_capture_png
var _act_fan: Node = null               # NML_CAPTURE_FAN overlay, kept alive until the deferred grab
var _act_started := -1                  # activations BEGUN so far — the MOMENT stamp of every capture; -1 = not armed
var _move_trail_dump: Array = []        # per-activation per-model path polylines (the offline wall-audit's input)
var _move_trail_walls: Array = []       # wall segments (world XZ metres), stashed at the first activation capture
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
		# PER-ACTIVATION board captures (maintainer directive: watch the AI play move by move — the wall-
		# pathfinding complaints need eyes, not metrics). NML_CAPTURE_ACTS=1 + a real renderer (gamescope
		# --backend headless): one PNG per AI activation, grabbed once the activation has RESOLVED. Nothing
		# lags a picture behind its label any more — both grabs hang on awaited seams in the round loop.
		if OS.get_environment("NML_CAPTURE_ACTS") == "1":
			_act_started = 0
			var arena_self := self
			# connected below once `solo` exists (see after _ensure_solo_controller)
			_act_capture = func(u) -> void:
				_act_started += 1
				var unit_tag := str(u.get_name()).to_lower().replace(" ", "_") if u != null else "unit"
				# PER-MODEL PATH DUMP (maintainer: "nach jeder Modellbewegung — angemessenes Maß"): every
				# model's planned polyline + base radius, for the offline wall-crossing AUDIT + re-render.
				# Finer than per-model screenshots — every single model move gets machine-checked.
				if _move_trail_walls.is_empty():   # stash once — terrain exists by the first activation
					var ovl: Node = main.get("terrain_overlay")
					if ovl != null and ovl.has_method("get_wall_segments_world"):
						for wseg in ovl.get_wall_segments_world():
							_move_trail_walls.append([[snappedf((wseg[0] as Vector2).x, 0.0001), snappedf((wseg[0] as Vector2).y, 0.0001)],
								[snappedf((wseg[1] as Vector2).x, 0.0001), snappedf((wseg[1] as Vector2).y, 0.0001)]])
				var solo_node: Node = main.get("solo_controller")
				if solo_node != null:
					var rec: Array = []
					for mp in solo_node.last_move_paths:
						var d := mp as Dictionary
						var pts: Array = []
						for p in (d.get("path", []) as Array):
							pts.append([snappedf((p as Vector3).x, 0.0001), snappedf((p as Vector3).z, 0.0001)])
						rec.append({"r": snappedf(float(d.get("radius_m", 0.016)), 0.0001), "pts": pts})
					var _fly: bool = u != null and (u.has_special_rule("Flying") or SoloController.is_aircraft(u))
					# Coherency audit flag (live-test Bug 20): post-activation coherency of the ACTING unit —
					# ladders count violations; the fix target is zero.
					var _coh: bool = u == null or bool(solo_node.unit_coherent_now(u))
					# Bug-31 charge audit: action type + the TARGET unit's surviving bases, so the
					# offline analyzer can isolate charges and measure arc ratio / pass-through /
					# end-formation against the real enemy footprint.
					var _rep: Dictionary = solo_node.last_report
					var _tgt: GameUnit = _rep.get("target") as GameUnit
					var tgt_bases: Array = []
					if _tgt != null:
						for tm in _tgt.models:
							var tmi := tm as ModelInstance
							if tmi != null and tmi.is_alive and tmi.node != null and is_instance_valid(tmi.node):
								tgt_bases.append([snappedf(tmi.node.global_position.x, 0.0001),
									snappedf(tmi.node.global_position.z, 0.0001),
									snappedf(solo_node.model_base_radius_m(tmi), 0.0001)])
					_move_trail_dump.append({"act": _act_started, "unit": str(u.get_name()) if u != null else "?", "flying": _fly,
						"coherent": _coh, "action": int(_rep.get("action", -1)),
						"target": str(_tgt.get_name()) if _tgt != null else "",
						"tgt_bases": tgt_bases,
						"round": int((main.get("opr_army_manager") as Node).current_round), "models": rec})
				# NML_CAPTURE_FAN=1: draw the activating unit's sight+range fan into the capture — the
				# watch-loop verification of the fan overlay (I review it against ruins/containers frame by
				# frame before it ships to the player's selection UI).
				_act_fan = null
				if OS.get_environment("NML_CAPTURE_FAN") == "1" and u != null:
					_act_fan = main.get_node_or_null("ArenaFanDebug")
					if _act_fan == null:
						_act_fan = SightFanController.new()
						_act_fan.name = "ArenaFanDebug"
						main.add_child(_act_fan)
					var solo_ctl: Node = main.get("solo_controller")
					var fan_ranges: Array = []
					if solo_ctl != null:
						var bonus_in: int = SoloController.shooting_range_bonus(u)
						for wpn in solo_ctl._unit_weapons(u):
							var r_in: int = AiArchetype.max_range_inches([wpn]) + bonus_in
							if r_in > bonus_in and not fan_ranges.has(r_in):
								fan_ranges.append(r_in)
					var tbl: Node = main.get("table")
					var hw: float = (tbl.table_size.x * 0.3048 / 2.0) if tbl != null else 0.0
					var hd: float = (tbl.table_size.y * 0.3048 / 2.0) if tbl != null else 0.0
					_act_fan.show_fan_for(u, main.get("terrain_overlay"), fan_ranges,
						Rect2(Vector2(-hw, -hd), Vector2(hw * 2.0, hd * 2.0)))
				# QUEUE the PNG — grabbing here caught the board mid-choreography (measured, seed 7: 6 of
				# 27 consecutive act PNGs byte-identical, 4 of them with the later unit moving >1"). The
				# trail dump above stays on this signal: it must read last_move_paths / last_report before
				# any pile-in or casualty edits them.
				_act_png_pending = "act%03d_%s.png" % [_act_started, unit_tag]
			# Drains the queue once the activation has fully resolved (main.solo_activation_done).
			_act_capture_png = func(_u) -> void:
				if _act_png_pending.is_empty():
					return
				await arena_self._capture_board(main, _act_png_pending)
				_act_png_pending = ""
				if _act_fan != null:
					_act_fan.clear_fan()
					_act_fan = null
		# Full-log collection: the Battle Log panel's data source is a 200-entry ring buffer, so a
		# whole match overflows it — mirror every entry as it is logged and dump the mirror at the end.
		battle_log.entry_added.connect(func(entry: Dictionary) -> void: _log_entries.append(entry))
		# Round-end boards (rounds 1..3; the final round has no advance and is captured after the game
		# returns). Hung on round_advanced this landed a whole activation LATE — the handler's await is
		# fire-and-forget, so the loop played on while the grab waited for its frame (measured, seed 7:
		# round1/2/3.png were stamped after 8/16/23 activations, i.e. one unit of the NEXT round had
		# already acted; round2.png carried six round-3 dice rolls). main.solo_round_done is AWAITED by
		# the round loop, so nothing can act until the board is on disk.
		main.solo_round_done = func(ended_round: int) -> void:
			await _capture_board(main, "round%d.png" % ended_round)

	main.set("_solo_fast", true)
	main.set("_solo_batch", _batch)
	AiEv.versatile_enabled = OS.get_environment("NML_VERSATILE") != "0"   # A/B seam: =0 runs the rule-OFF leg
	main.set("_solo_dev", OS.get_environment("NML_AI_DEV") == "1")

	if not await _import_and_spawn(main, army_manager, _army1, 1):
		return
	if not await _import_and_spawn(main, army_manager, _army2, 2):
		return
	for _i in range(SPAWN_SETTLE_FRAMES):
		await process_frame

	# Symmetric board: the game's own OPR terrain autogen + FRONT_LINE zones + three centre objectives.
	seed(_layout_seed)
	if _symmetric:
		layout_editor.point_symmetry_enabled = true   # tuning runs: mirror terrain across the centre (fairness)
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
	if _objective_count == 5:
		# 5 point-symmetric markers >=9" apart (tuning-run mission): centre + two symmetric pairs.
		objectives_in = [Vector2(0.0, 0.0), Vector2(-16.0, 6.0), Vector2(16.0, -6.0), Vector2(-8.0, -8.0), Vector2(8.0, 8.0)]
	if not _mission_id.is_empty():
		# Missions wave M5: the ladder plays a CATALOG mission — markers resolve via
		# the M3 placement modes. Duel's 'alternate' resolves to [] by design (hand
		# placement has no headless equivalent), so NML_MISSION=duel keeps the
		# centre-line approximation above and stays comparable with legacy runs.
		var mission := MissionCatalog.get_mission(_mission_id)
		# NML-1010 W2: arm the live VP ledger with the mission's scoring —
		# "end" for Face-Off keeps every consumer as before; round_vp switches
		# main's round-end bookkeeping, the planner state and the winner call.
		var mmeta: Array = []
		if bool((mission.get("markers", {}) as Dictionary).get("owned", false)):
			# deploy_zone_front resolves [P1's, P2's] in zone order — the
			# owned_by convention rides that order (index + 1).
			var mc := int((mission.get("markers", {}) as Dictionary).get("count", 2))
			for mi in range(mc):
				mmeta.append({"owned_by": mi + 1,
					"destructible": bool((mission.get("markers", {}) as Dictionary).get("destructible", false)),
					"destroyed": false, "destroyed_seq": 0})
		SoloController.mission_reset(str(mission.get("scoring", "end")),
			(mission.get("vp", {}) as Dictionary), mmeta)
		var style := DeploymentCatalog.get_style(str(mission.get("deployment", "front_line")))
		var resolved := MissionCatalog.marker_positions(mission, style,
			table.table_size.x * 12.0, table.table_size.y * 12.0)
		if not resolved.is_empty():
			objectives_in = []
			for rp in resolved:
				objectives_in.append(rp as Vector2)
		printerr("[ARENA] mission '%s': placement=%s markers=%d (catalog-resolved)" % [_mission_id,
			str((mission.get("markers", {}) as Dictionary).get("placement", "?")), objectives_in.size()])
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
	_objectives_placed = placed.size()
	printerr("[ARENA] objectives on table: %d (all within bounds)" % placed.size())

	# Arm native both-AI with the graded sides, then wire the controller for the whole board.
	main.set_both_ai(true, _p1_grade, _p2_grade, _seed)
	main._ensure_solo_controller()
	# Measurement seam: override the fast-planner cap AFTER _ensure_solo_controller — that call re-derives
	# fast_planner_guard, so an earlier env read was silently clobbered back to the sweep default (xhigh
	# review find: the 320/1200/2400 guard comparison actually ran 320 three times — its "the cap costs no
	# time" conclusion was void; re-measure with this ordering when the cap matters).
	var _pg := OS.get_environment("NML_PLANNER_GUARD").strip_edges()
	if _pg.is_valid_int():
		MovementPlanner.fast_planner_guard = int(_pg)
	var solo: Node = main.get("solo_controller")
	if solo == null:
		printerr("[ARENA] FATAL: SoloController not created")
		quit(1)
		return
	solo._rng.seed = _seed
	if _act_capture.is_valid():
		solo.ai_unit_activated.connect(_act_capture)   # trail dump + PNG queue (NML_CAPTURE_ACTS=1)
		main.solo_activation_done = _act_capture_png   # the grab itself, on the settled board
	# Off-board audit (#215) — ALWAYS on, no env gate: the ladder IS the A/B measurement track, so every
	# graded game must carry the number. One parseable battle-log line per offending unit right after it
	# settled; tools/tactic_audit.py counts those lines as d9. Measurement only — no decision is touched.
	solo.ai_unit_activated.connect(func(u) -> void:
		OffboardAudit.audit_and_log(main.get("table"), battle_log, u, "after activation"))
	# Eval-method hardening (10.08.): per-unit activation counts into the result
	# JSON — the log linter's food. A unit alive at game end with ZERO
	# activations is the NML-1002 anomaly class (stolen/stuck units) and must
	# never again hide inside aggregate winrates.
	solo.ai_unit_activated.connect(func(u) -> void:
		if u == null:
			return
		var slot := int(u.unit_properties.get("player_id", 0))
		var by: Dictionary = _unit_activations.get(slot, {})
		by[str(u.get_name())] = int(by.get(str(u.get_name()), 0)) + 1
		_unit_activations[slot] = by)
	solo.decision_sink = func(rec: Dictionary) -> void:
		var kind := str(rec.get("kind", "?"))
		var side: int = honest_side(rec, int(solo.ai_slot))
		var by_kind: Dictionary = _decision_counts.get(side, {})
		by_kind[kind] = int(by_kind.get(kind, 0)) + 1
		_decision_counts[side] = by_kind
		if kind == "terrain_meter":
			var td: Dictionary = rec.get("data", {})
			var mt: Dictionary = _meters.get(side, {"n": 0, "cover": 0, "shot": 0,
				"terrain": 0, "exposed_sum": 0, "exposed_max": 0})
			mt["n"] = int(mt["n"]) + 1
			mt["cover"] = int(mt["cover"]) + (1 if bool(td.get("in_cover", false)) else 0)
			mt["shot"] = int(mt["shot"]) + (1 if bool(td.get("shot", false)) else 0)
			mt["terrain"] = int(mt["terrain"]) + (1 if bool(td.get("in_terrain", false)) else 0)
			mt["exposed_sum"] = int(mt["exposed_sum"]) + int(td.get("exposed_to", 0))
			mt["exposed_max"] = maxi(int(mt["exposed_max"]), int(td.get("exposed_to", 0)))
			_meters[side] = mt
		if kind == "teacher_row":
			# P1 imitation corpus (NML_TEACHER_ROWS=1): board + menu + the
			# teacher's index, one row per tree activation. seq = arrival order.
			var tr: Dictionary = (rec.get("data", {}) as Dictionary).duplicate(true)
			tr["seq"] = _teacher_rows.size()
			tr["unit"] = str(rec.get("unit", ""))
			_teacher_rows.append(tr)
		if kind == "menu_probe":
			var md: Dictionary = rec.get("data", {})
			var cls := str(md.get("class", "?"))
			var by: Dictionary = _menu_probe.get(cls, {"n": 0, "covered": 0, "loose": 0,
				"covered_wide": 0, "loose_wide": 0, "menu_sum": 0, "menu_wide_sum": 0})
			by["n"] = int(by["n"]) + 1
			for f in ["covered", "loose", "covered_wide", "loose_wide"]:
				by[f] = int(by.get(f, 0)) + (1 if bool(md.get(f, false)) else 0)
			by["menu_sum"] = int(by.get("menu_sum", 0)) + int(md.get("menu", 0))
			by["menu_wide_sum"] = int(by.get("menu_wide_sum", 0)) + int(md.get("menu_wide", 0))
			_menu_probe[cls] = by
			if cls == "move":
				var bucket := str(int(floor(maxf(float(md.get("best_in", 0.0)), 0.0) / 3.0)) * 3)
				_menu_miss_hist[bucket] = int(_menu_miss_hist.get(bucket, 0)) + 1
		if kind == "roll_off" or kind == "difficulty":
			var annotated := rec.duplicate(true)
			annotated["side"] = side
			annotated["round"] = int(army_manager.current_round)
			_knob_records.append(annotated)
		if kind == "planner" and (rec.get("data", {}) as Dictionary).has("win_before"):
			var d: Dictionary = rec["data"]
			_calib_records.append({"side": side, "round": int(army_manager.current_round),
				"before": float(d["win_before"]), "after": float(d["win_after"])})
		if kind == "planner" and (rec.get("data", {}) as Dictionary).has("features"):
			# E1/E6 (eval-tuning wave): EVERY planner pick logs its position
			# (E6 — per-activation granularity; round-level TD was too coarse
			# to isolate a move's consequence, the controllable features
			# zeroed out). seq = arrival order, the offline TD chains on it.
			_position_rows.append({"side": side, "round": int(army_manager.current_round),
				"seq": _position_rows.size(),
				"leaf": bool((rec["data"] as Dictionary).get("leaf", false)),
				"value": float((rec["data"] as Dictionary).get("value", -1.0)),
				"features": (rec["data"] as Dictionary)["features"]})
		if kind == "move":
			_move_records.append({"side": side, "round": int(army_manager.current_round),
				"unit": str(rec.get("unit", "?")), "why": str(rec.get("why", "")),
				"data": (rec.get("data", {}) as Dictionary).duplicate(true)})
		if not _capture_dir.is_empty():
			var full := rec.duplicate(true)
			full["side"] = side
			full["round"] = int(army_manager.current_round)
			_all_decisions.append(full)

	# OFFICIAL deployment roll-off (highest die wins, ties re-roll — drawn from the seeded controller RNG,
	# so the winner is reproducible per seed): the winner deploys FIRST and takes round 1's first turn.
	var opener: int = solo.roll_off()
	printerr("[ARENA] roll-off: P%d wins — deploys first, opens round 1 (official rule)" % opener)
	# RESEARCH KNOBS (NML-995 seat decomposition, env-gated, ladder-inert when
	# unset): decouple the roll-off's two prizes — NML_DEPLOY_FIRST forces who
	# deploys first (counter-deploy edge), NML_OPEN_FIRST forces who takes
	# round 1's first activation. Measures how much of the opener-seat penalty
	# is DEPLOYMENT vs TEMPO.
	var deploy_first := opener
	if OS.get_environment("NML_DEPLOY_FIRST") != "":
		deploy_first = clampi(int(OS.get_environment("NML_DEPLOY_FIRST")), 1, 2)
	if OS.get_environment("NML_OPEN_FIRST") != "":
		opener = clampi(int(OS.get_environment("NML_OPEN_FIRST")), 1, 2)
	if deploy_first != opener or OS.get_environment("NML_DEPLOY_FIRST") != "":
		printerr("[ARENA] RESEARCH decouple: P%d deploys first, P%d opens round 1" % [deploy_first, opener])

	# Production AI deployment for BOTH sides into their 12" front-line zones, in roll-off order. The
	# per-side deployment seed stays attached to the SLOT (seed+slot), so a side's deployment is identical
	# across the swapped games of a ladder pairing regardless of who won the roll-off.
	var objectives: Array = terrain_overlay.get_objectives()
	var objectives_v2: Array = []
	for o in objectives:
		objectives_v2.append(Vector2((o as Vector3).x, (o as Vector3).z))
	var deploy_order: Array = [1, 2] if deploy_first == 1 else [2, 1]
	for slot in deploy_order:
		_deploy_side(main, solo, table, terrain_overlay, int(slot), objectives_v2, _seed + int(slot),
			int(slot) == deploy_first)
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
	var vp1: int = int(SoloController.mission_vp[0])
	var vp2: int = int(SoloController.mission_vp[1])
	# NML-1048: the verdict is no longer computed here. BattleSim.mission_winner is the ONE referee —
	# the same call main._solo_show_game_summary makes — so the result JSON and the summary the table
	# reads can never name different sides again (measured: 55 of 233 round_vp games disagreed).
	var winner: String = BattleSim.mission_winner(SoloController.mission_scoring, owners,
		SoloController.mission_vp, SoloController.mission_markers,
		int(main._solo_side_alive(1)), int(main._solo_side_alive(2)))
	printerr("[ARENA] RESULT seed=%d dice=%d P1(%s) objectives=%d P2(%s) objectives=%d vp=%d:%d → %s" % [
		_seed, _dice_seed, _p1_grade, p1, _p2_grade, p2, vp1, vp2, winner])
	_write_result_json(main, army_manager, opener, winner,
		{"p1": p1, "p2": p2, "neutral": neutral, "vp1": vp1, "vp2": vp2,
			"markers_destroyed": SoloController.mission_markers.map(
				func(mk: Variant) -> bool: return bool((mk as Dictionary).get("destroyed", false)))},
		float(Time.get_ticks_msec() - t0) / 1000.0)
	_write_capture_outputs()
	quit(0)


## Whose ACCOUNT a decision record belongs on. Usually the slot the controller was acting as when the
## record fired (`acting_slot`), but two kinds describe a side that is NOT the acting one:
##   seize  — a round-end objective ownership event, not an acting side's decision: its honest side is
##            the marker's new owner (0 = contested/neutral), never whichever slot happened to take the
##            round's last activation (showcase finding: every seize carried the active slot).
##   deploy — deploy_finish's coherency repair walks EVERY graded slot, so one side's finish pass emits
##            repair records for the OTHER side's units (measured, rekrut vs rekrut seed 7: 8 of 17
##            deploy records were a P2 unit's repair booked to P1). Those records carry the repaired
##            unit's own seat in data.slot; every other deploy record has no hint and stays on the actor.
static func honest_side(rec: Dictionary, acting_slot: int) -> int:
	var data: Dictionary = rec.get("data", {})
	match str(rec.get("kind", "?")):
		"seize":
			return int(data.get("owner", 0))
		"deploy":
			if data.has("slot"):
				return int(data["slot"])
	return acting_slot


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
		# The MOMENT belongs in the record: how many activations had already BEGUN when this frame was
		# drawn. A picture whose stamp is one ahead of its file name is a picture of the wrong turn.
		printerr("[ARENA] capture -> %s%s" % [path,
			(" (after %d activations)" % _act_started) if _act_started >= 0 else ""])
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
	# Per-model move trails + wall segments (NML_CAPTURE_ACTS): the offline wall-crossing audit's input.
	if not _move_trail_dump.is_empty():
		var mv_f := FileAccess.open(_capture_dir.path_join("moves.json"), FileAccess.WRITE)
		if mv_f != null:
			mv_f.store_string(JSON.stringify({"walls": _move_trail_walls, "activations": _move_trail_dump}, " "))
			mv_f.close()
			printerr("[ARENA] move trails (%d activations, %d walls) -> %s" % [
				_move_trail_dump.size(), _move_trail_walls.size(), _capture_dir.path_join("moves.json")])


## The played-truth mission descriptor: catalog-backed when NML_MISSION picked a
## mission, the historical duel stamp otherwise. objective_count is the overlay's
## own count, never the requested one — values state what was ACTUALLY played.
func _mission_stamp() -> Dictionary:
	var mid := _mission_id if not _mission_id.is_empty() else "duel"
	var m := MissionCatalog.get_mission(mid)
	return {"family": str(m.get("family", "face_off")), "name": mid,
		"rounds": int(m.get("rounds", 4)), "scoring": str(m.get("scoring", "end")),
		"deployment": str(m.get("deployment", "front_line")), "symmetric": _symmetric,
		"objective_count": _objectives_placed, "packs": []}


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
		# Table-config descriptor (GF Advanced v3.5.1 foresight): keeps every
		# corpus filterable/mixable across missions, deployments and rule packs.
		"mission": _mission_stamp(),
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
		"search_knobs": search_knobs(),
		"decision_counts": _stringify_keys(_decision_counts),
		"clone": clone_stamp(),
		"meters": _stringify_keys(_meters),
		"menu_probe": _menu_probe,
		"teacher_rows": _teacher_rows,
		"menu_miss_hist": _menu_miss_hist,
		"knob_records": _knob_records,
		"move_usage": _move_usage_summary(),
		"planner_calib": calib_pairs(_calib_records),
		"planner_positions": _position_rows,
		"unit_activations": _stringify_keys(_unit_activations),
		"duration_sec": duration_sec,
	}
	for c in result["planner_calib"]:
		printerr("[ARENA] planner_calib P%d round %d->%d: predicted %.3f measured %.3f gap %+.3f" % [
			int(c["side"]), int(c["from_round"]), int(c["to_round"]),
			float(c["predicted"]), float(c["measured"]), float(c["gap"])])
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


## Search-knob provenance (12.08. morning quake): a result dir must PROVE which
## search configuration produced it — the phantom reference survived because
## runs differed only in env vars nobody recorded. Stamped are the EFFECTIVE
## values (the lazy accessors resolve env + default, exactly what the game
## consumed); net_loaded is the boot-time load probe's permanent record.
## What the CLONE actually did in THIS game — never what the environment asked
## for. A box running a repo older than the knob ignores it silently, and the
## run then reproduces the previous experiment while looking like a new one
## (cost me a 45-minute wave, 16.08.). Absent stamp = old build: the scorers
## refuse such a run instead of averaging it in.
static func clone_stamp() -> Dictionary:
	var want := OS.get_environment("NML_CLONE_PATH").strip_edges()
	var k := OS.get_environment("NML_CLONE_SEARCH").strip_edges()
	var p1 := OS.get_environment("NML_CLONE_P1").strip_edges()
	var p2 := OS.get_environment("NML_CLONE_P2").strip_edges()
	if p1 != "" or p2 != "":
		var k1 := OS.get_environment("NML_CLONE_SEARCH_P1").strip_edges()
		var k2 := OS.get_environment("NML_CLONE_SEARCH_P2").strip_edges()
		# Turn 4: the DEEP-TEACHER knob is corpus identity — a depth-2 book must
		# never be mistaken for a 1-ply one, so the stamp carries it (gate food).
		var dg := OS.get_environment("NML_CLONE_SEARCH_DEPTH").strip_edges()
		var dt := OS.get_environment("NML_CLONE_SEARCH_DEEP_TOP").strip_edges()
		return {"requested": want, "p1": p1, "p2": p2,
			"loaded": not AiClone.net_for(1).is_empty() or not AiClone.net_for(2).is_empty(),
			"loaded_p1": not AiClone.net_for(1).is_empty(),
			"loaded_p2": not AiClone.net_for(2).is_empty(),
			"search": int(k) if k.is_valid_int() else 0,
			"search_p1": int(k1) if k1.is_valid_int() else (int(k) if k.is_valid_int() else 0),
			"search_p2": int(k2) if k2.is_valid_int() else (int(k) if k.is_valid_int() else 0),
			"depth": int(dg) if dg.is_valid_int() else 0,
			"deep_top": int(dt) if dt.is_valid_int() else (8 if dg.is_valid_int() and int(dg) > 0 else 0),
			"seat": OS.get_environment("NML_CLONE_SIDE").strip_edges(), "stamp_version": 2}
	var dg2 := OS.get_environment("NML_CLONE_SEARCH_DEPTH").strip_edges()
	return {"requested": want, "loaded": not AiClone.net().is_empty(),
		"search": int(k) if k.is_valid_int() else 0,
		"depth": int(dg2) if dg2.is_valid_int() else 0,
		"seat": OS.get_environment("NML_CLONE_SIDE").strip_edges(),
		"stamp_version": 2}


static func search_knobs() -> Dictionary:
	var fw := OS.get_environment("NML_FIT_WEIGHTS").strip_edges()
	var net_loaded := fw == "net" and not AiMissionEval._net().is_empty()
	return {
		"top_k": AiPlanner.top_k_default(),
		"horizon": AiPlanner.horizon(),
		"seat_depth": AiPlanner.seat_depth_enabled(),
		"fit_weights": "net" if net_loaded else ("v2" if fw == "v2" else "v4"),
		"fit_blend": AiMissionEval.fit_blend(),
		"net_path": OS.get_environment("NML_NET_PATH"),
		"net_loaded": net_loaded,
		"playout_rich": AiPlanner.playout_rich(),
		"playout_margin": AiPlanner.close_margin(),
		"playout_fired": AiPlanner.playout_arbitrations,
	}


## Planner calibration pairs (parity wave, NML-995): fold the per-activation expectation records into
## per-round-boundary comparisons. For each side, the LAST record of round N carries the planner's
## end-of-round forecast ("after"); the FIRST record of round N+1 carries the freshly measured position
## ("before"). Their gap (measured - predicted) is the mental model's calibration error — the number the
## sim-parity work must shrink before deeper search can pay. Records must be in arrival order (they are:
## the sink appends). Pure and static so the pairing is unit-testable without a game.
static func calib_pairs(records: Array) -> Array:
	var prev := {}   # side(int) → last record seen for that side
	var pairs: Array = []
	for r in records:
		var side: int = int(r["side"])
		if prev.has(side) and int(r["round"]) > int((prev[side] as Dictionary)["round"]):
			var p: Dictionary = prev[side]
			pairs.append({"side": side, "from_round": int(p["round"]), "to_round": int(r["round"]),
				"predicted": float(p["after"]), "measured": float(r["before"]),
				"gap": float(r["before"]) - float(p["after"])})
		prev[side] = r
	return pairs


## Movement plausibility metrics (AI plausibility wave 1), aggregated per side from every MOVE record:
##   open_field_moves      — "direct"-route moves granted their full budget whose goal lay beyond the
##                           band (the unit had room to use its whole allowance);
##   median_achieved_ratio — median achieved/budget over those (acceptance at kriegsherr: >= 0.85);
##   aimless_subinch       — sub-1" moves with a >2" goal, a >=2" band and no enemy within 2" — the
##                           "half an inch toward nothing" class (acceptance: none);
##   large_stall_streak    — longest consecutive sub-1" run of one LARGE-base unit while not surrounded
##                           (acceptance: <= 2);
##   aircraft_moves/full   — aircraft activations and how many flew their full straight lane.
func _move_usage_summary() -> Dictionary:
	var out := {}
	for side in [1, 2]:
		var ratios: Array = []
		var aimless: Array = []
		var streaks := {}      # unit -> running sub-1" streak
		var max_streak := {}   # unit -> longest streak seen
		var air_total := 0
		var air_full := 0
		for r in _move_records:
			var rec := r as Dictionary
			if int(rec.get("side", 0)) != side:
				continue
			var d := rec.get("data", {}) as Dictionary
			var band := float(d.get("band_in", 0.0))
			var budget := float(d.get("budget_in", 0.0))
			var achieved := float(d.get("achieved_in", 0.0))
			var gap := float(d.get("goal_gap_in", INF))
			var why := str(rec.get("why", ""))
			if bool(d.get("aircraft", false)):
				air_total += 1
				if achieved >= band - 0.1:
					air_full += 1
				continue
			if why == "direct" and budget >= band - 0.001 and gap > band:
				ratios.append(achieved / maxf(budget, 0.001))
			var surrounded: bool = float(d.get("enemy_gap_in", INF)) <= 2.0
			if achieved < 1.0 and band >= 2.0 and gap > 2.0 and not surrounded:
				aimless.append("%s R%d %s (%.2f\" of %.1f\")" % [
					str(rec.get("unit", "?")), int(rec.get("round", 0)), why, achieved, band])
			if bool(d.get("large", false)):
				var u := str(rec.get("unit", "?"))
				if achieved < 1.0 and not surrounded:
					streaks[u] = int(streaks.get(u, 0)) + 1
					max_streak[u] = maxi(int(max_streak.get(u, 0)), int(streaks[u]))
				else:
					streaks[u] = 0
		ratios.sort()
		var median := 0.0
		if not ratios.is_empty():
			median = float(ratios[ratios.size() / 2]) if ratios.size() % 2 == 1 \
				else (float(ratios[ratios.size() / 2 - 1]) + float(ratios[ratios.size() / 2])) / 2.0
		var worst_large := 0
		for u in max_streak:
			worst_large = maxi(worst_large, int(max_streak[u]))
		out[str(side)] = {"open_field_moves": ratios.size(), "median_achieved_ratio": median,
			"aimless_subinch": aimless, "large_stall_streak": worst_large,
			"large_stalls_by_unit": max_streak, "aircraft_moves": air_total, "aircraft_full_lanes": air_full}
	return out


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


func _import_and_spawn(main: Node, army_manager: Node, fixture: String, player_id: int) -> bool:
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
	# The interactive import path derives buff/debuff tokens from rules + spells; the harness
	# bypasses it, so trigger the derivation here — AI token placement depends on the library.
	if main.has_method("_auto_create_buff_tokens"):
		main._auto_create_buff_tokens(army)
	printerr("[ARENA] player %d = '%s' — %d units spawned" % [player_id, army.name,
		army_manager.get_game_units_for_player(player_id).size()])
	return true


func _deploy_side(main: Node, solo: Node, table: Node, terrain_overlay: Node, slot: int, objectives_v2: Array, seed_value: int, first := false) -> void:
	solo.ai_slot = slot
	solo.human_slot = 2 if slot == 1 else 1
	var w: float = table.table_size.x * 0.3048
	var d: float = table.table_size.y * 0.3048
	var depth: float = 12.0 * IN2M
	var zmin: float = (-d / 2.0) if slot == 1 else (d / 2.0 - depth)
	var zone := Rect2(Vector2(-w / 2.0, zmin), Vector2(w, depth))
	# RESEARCH KNOB (NML-995 deploy decomposition): restrict the FIRST
	# deployer's zone — the counter-deploy probe's arms. Env-gated, inert
	# when unset. back = the strip's rear half (table-edge side); left/right
	# = one width half (flank refuse).
	var zd := OS.get_environment("NML_FIRST_DEPLOY_ZONE")
	if first and zd != "":
		match zd:
			"back":
				zone = Rect2(Vector2(zone.position.x, zmin if slot == 1 else zmin + depth / 2.0),
					Vector2(w, depth / 2.0))
			"left":
				zone = Rect2(Vector2(-w / 2.0, zmin), Vector2(w / 2.0, depth))
			"right":
				zone = Rect2(Vector2(0.0, zmin), Vector2(w / 2.0, depth))
		printerr("[ARENA] RESEARCH first-deploy zone '%s' for P%d" % [zd, slot])
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
	var bt := OS.get_environment("NML_AI_BATCH").strip_edges()
	if bt != "":
		_batch = bt != "0"
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
		elif a.begins_with("batch="):
			_batch = a.substr(6) != "0"
		elif a.begins_with("layout_seed=") and a.substr(12).is_valid_int():
			_layout_seed = int(a.substr(12))
		elif a == "symmetric=1":
			_symmetric = true
		elif a.begins_with("objectives=") and a.substr(11).is_valid_int():
			_objective_count = int(a.substr(11))
	if not _dice_seed_explicit:
		_dice_seed = _seed

	# Same loud-fallback doctrine as grades/nets: a typo'd NML_MISSION quietly
	# playing duel would mislabel a whole tournament (the label-bug class).
	_mission_id = OS.get_environment("NML_MISSION").strip_edges().to_lower()
	if not _mission_id.is_empty() and not MissionCatalog.mission_ids().has(_mission_id):
		printerr("[ARENA] FATAL: unknown NML_MISSION '%s' (catalog: %s) — refusing a mislabeled run" % [
			_mission_id, str(MissionCatalog.mission_ids())])
		quit(1)
		return

	# Label-bug class EXTERMINATED (three silent-fallback incidents): an
	# unknown grade no longer plays nachtmahr quietly — it dies loudly.
	for g in [_p1_grade, _p2_grade]:
		if not SoloDifficulty.PRESETS.has(str(g).strip_edges().to_lower()) \
				and not SoloDifficulty.LEGACY_GRADE_ALIASES.has(str(g).strip_edges().to_lower()):
			printerr("[ARENA] FATAL: unknown grade '%s' — refusing the silent nachtmahr fallback" % g)
			quit(1)
			return

	# Same silent-fallback class, eval side: a typo'd NML_FIT_WEIGHTS used to
	# select v4 quietly, and a net request whose weights file is missing or
	# unparseable used to fall back to the linear eval quietly (the "verify
	# the net actually loaded" box probe, now enforced at boot instead).
	var fw := OS.get_environment("NML_FIT_WEIGHTS").strip_edges()
	if not (fw in ["", "v2", "v4", "net"]):
		printerr("[ARENA] FATAL: unknown NML_FIT_WEIGHTS '%s' (allowed: v2, v4, net)" % fw)
		quit(1)
		return
	if fw == "net" and AiMissionEval._net().is_empty():
		printerr("[ARENA] FATAL: NML_FIT_WEIGHTS=net but no loadable model at NML_NET_PATH '%s'"
				% OS.get_environment("NML_NET_PATH"))
		quit(1)
		return

func _env_or(key: String, fallback: String) -> String:
	var v := OS.get_environment(key).strip_edges()
	return v if v != "" else fallback
