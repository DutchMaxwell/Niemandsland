extends SceneTree
## Solo-AI SELF-PLAY harness — drives the REAL game path (scripts/main.gd) on a REAL board, headless,
## with BOTH armies played by the REAL SoloController, and runs ONE complete OPR match end to end.
##
## What is REAL here (no synthesized data):
##   · Board:    scenes/main.tscn booted the normal way; terrain via the game's own OPR-guideline autogen
##               (map_layout editor, frozen LAYOUT_SEED) with FRONT_LINE (12") deployment zones + objectives.
##   · Armies:   the two maintainer tutorial lists — Battle Brothers (__FfT0jOYHtc) vs Robot Legions
##               (gLi7he9YFjEt) — imported through the production TTS parser (import_from_tts_json) and
##               spawned via the real spawn path (OPRArmyManager.spawn_army).
##   · Brain:    the REAL SoloController — official OPR Solo & Co-Op v3.5.0 unit pick, decision tree,
##               MovementPlanner, terrain/LOS providers — deploys and activates BOTH sides (ai_slot is
##               flipped per activation so each army gets the identical real AI treatment).
##   · Combat:   the REAL main.gd resolution (_run_ai_shooting / _run_ai_melee / _run_ai_dangerous /
##               _solo_shooting_morale) on the REAL dice tray + the shared pure modules — Counter, Impact,
##               Fatigue, Fear, morale, consolidation, Deadly/AP/Cover/Regeneration all as in-game.
##   · Log:      the REAL in-game BattleLog collector (the Battle Log panel's data source) + the REAL
##               SoloController.decision_log (structured reasoning records).
##
## The ONE interactive seam that cannot run headless is the human SAVE / STRIKE-BACK dialog
## (_solo_prompt_saves / _solo_confirm_strike_back hard-await a ConfirmationDialog, and the visual dice
## tray awaits a physical settle). This harness STUBS only that seam — in the tool, never in the game —
## with an in-tree DialogAutoConfirm node that auto-answers those prompts (defender always rolls its
## saves / always strikes back); the dice + resolution stay the game's real modules. Everything else is
## the untouched production path.
##
## Run (headless — battle log + decisions + summary; screenshots skipped):
##   flatpak run --filesystem=home --share=network org.godotengine.Godot \
##     --path <worktree> --headless -s res://tools/solo_selfplay.gd
## Run ONE diverse game (seed varies terrain/deploy/AI-pick; out names the files):
##   flatpak run --filesystem=home --share=network org.godotengine.Godot \
##     --path <worktree> --headless -s res://tools/solo_selfplay.gd -- seed=7 out=game_007
##   (or export NML_SELFPLAY_SEED=7 instead of the -- seed= arg). No seed => legacy
##   fixed board + "game1_*" outputs (back-compat). A BATCH of N diverse games:
##   tools/selfplay_batch.sh N   (import pass, then seeds 1..N, then batch_summary.json).
## Run (gamescope — same, PLUS board screenshots at deploy / round 2 / end):
##   gamescope --backend headless -W 1600 -H 900 -- \
##     flatpak run --filesystem=home --socket=wayland --share=network org.godotengine.Godot \
##       --path <worktree> --rendering-driver vulkan -s res://tools/solo_selfplay.gd

const P1_FIXTURE := "res://assets/tutorial/tutorial_army_p1.json"  # Battle Brothers (player 1)
const P2_FIXTURE := "res://assets/tutorial/tutorial_army_p2.json"  # Robot Legions (player 2)
const GAME_ROUNDS := 4          # OPR standard match length (== main.gd SOLO_GAME_ROUNDS)
const LAYOUT_SEED := 20260710   # legacy (no-arg) terrain autogen seed (same seed the tutorial board uses)
const SELFPLAY_SEED := 424242   # legacy (no-arg) unit pick / deploy / global RNG seed for reproducibility
const MAX_BOOT_FRAMES := 1200
const SPAWN_SETTLE_FRAMES := 120
const ACTIVATION_GUARD := 400   # hard cap on activations per round (defensive)
const WALL_CLOCK_BUDGET_S := 1500.0   # abort + dump what we have if the match overruns
const FRONT_LINE := 1           # MapLayout.DeploymentType.FRONT_LINE
const IN2M := 0.0254

var _out_dir: String = ""
var _decisions: Array = []      # raw SoloController.decision_log records, in order
var _violations: Array = []     # {round, kind, unit, detail} — runtime rule-violation audit
var _act_order: Array = []       # sides activated this round, in order (back-to-back audit)
var _blocker: String = ""       # set if a headless blocker aborts the match early
var _t0: float = 0.0
var _watcher: Node = null

# --- Per-game seed + output naming (goal: BATCH of diverse games) ---
# A single game seed derives four independent sub-seeds so DIFFERENT seeds produce a
# genuinely different board (terrain), deployment, and AI section-pick/order — while
# the SAME seed is fully deterministic (real-physics dice aside). No seed arg => the
# legacy fixed constants + "game1_*" outputs (back-compat).
var _game_seed: int = -1        # -1 => legacy fixed board (no seed supplied)
var _out_name: String = "game1" # output filename stem (<stem>_battlelog.txt, …)
var _layout_seed: int = LAYOUT_SEED
var _play_seed: int = SELFPLAY_SEED
var _deploy_seed_p1: int = SELFPLAY_SEED + 1
var _deploy_seed_p2: int = SELFPLAY_SEED + 2

# --- Objective instrumentation ---
var _objectives_world: Array = []   # objective marker positions (world Vector3, metres) — fixed for the game
var _obj_events: Array = []          # {kind:"objective_distance"|"seize", round, …} — machine-readable
var _prev_owners: Array = []         # objective owners snapshot, to diff for SEIZE events
var _terrain_pieces: int = 0         # placed terrain prefab count (per-game diversity proof)
var _terrain_fingerprint: String = ""   # hash of sorted piece origins — proves POSITION diversity per seed
var _terrain_origins: Array = []     # sorted "prefab@x,y" list (piece count is often constant; positions vary)

const OVERLAP_EPS_IN := 0.10    # ignore sub-0.1" base overlaps (float / resting-jitter noise)


# === Lifecycle ===

func _initialize() -> void:
	# Boot main.tscn straight to the table (skip intro / startup menu), like the tutorial board builder.
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	_run.call_deferred()


func _run() -> void:
	_t0 = Time.get_ticks_msec() / 1000.0
	_parse_args()
	seed(_play_seed)
	_out_dir = OS.get_environment("HOME").path_join("selfplay_out")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	printerr("[SELFPLAY] out dir: %s" % _out_dir)
	printerr("[SELFPLAY] game seed=%s out=%s (layout=%d play=%d deploy=%d/%d)" % [
		("legacy" if _game_seed < 0 else str(_game_seed)), _out_name,
		_layout_seed, _play_seed, _deploy_seed_p1, _deploy_seed_p2])

	change_scene_to_file("res://scenes/main.tscn")
	var main: Node = await _await_main()
	if main == null:
		printerr("[SELFPLAY] FATAL: main.tscn never became ready (managers missing) — see main.gd parse errors")
		quit(1)
		return
	printerr("[SELFPLAY] main.tscn ready")

	var army_manager: Node = main.get("opr_army_manager")
	var layout_editor: Control = main.get("map_layout_editor")
	var terrain_overlay: Node = main.get("terrain_overlay")
	var battle_log: Node = main.get("battle_log")
	var table: Node = main.get("table")
	if army_manager == null or layout_editor == null or terrain_overlay == null or battle_log == null or table == null:
		printerr("[SELFPLAY] FATAL: a manager is missing (army=%s layout=%s overlay=%s log=%s table=%s)" % [
			army_manager, layout_editor, terrain_overlay, battle_log, table])
		quit(1)
		return

	# --- Armies through the production import + spawn path ---
	if not await _import_and_spawn(army_manager, P1_FIXTURE, 1):
		return
	if not await _import_and_spawn(army_manager, P2_FIXTURE, 2):
		return
	for _i in range(SPAWN_SETTLE_FRAMES):
		await process_frame

	# --- Terrain: the game's own OPR autogen (per-game seed) + 12" front-line zones ---
	seed(_layout_seed)
	layout_editor._generate_terrain_layout()
	layout_editor.deployment_type = FRONT_LINE
	layout_editor._rebuild_derived()        # -> layout_updated -> terrain_overlay is populated
	layout_editor._emit_layout_update()
	layout_editor.deployment_type_changed.emit(FRONT_LINE)
	await process_frame
	seed(_play_seed)                         # restore the match RNG after the terrain draw
	_terrain_pieces = layout_editor.placed_pieces.size()
	# Position fingerprint: the autogen targets a near-constant PIECE COUNT, so count alone is a weak
	# diversity signal — hash the sorted piece origins to prove two seeds yield different BOARDS.
	for p in layout_editor.placed_pieces:
		var o = (p as Dictionary).get("origin", Vector2i.ZERO)
		_terrain_origins.append("%s@%d,%d" % [str((p as Dictionary).get("prefab_key", "?")), int(o.x), int(o.y)])
	_terrain_origins.sort()
	_terrain_fingerprint = str(hash("|".join(_terrain_origins)))
	printerr("[SELFPLAY] terrain: %d prefab pieces (fingerprint %s), %d grid cells" % [
		_terrain_pieces, _terrain_fingerprint, layout_editor.grid_cells.size()])

	# --- Objectives: three markers across the centre line (OPR standard), through the real editor seam ---
	var objectives_in: Array[Vector2] = [Vector2(-24.0, 0.0), Vector2(0.0, 0.0), Vector2(24.0, 0.0)]  # inches
	layout_editor.mission_objectives = objectives_in
	layout_editor.objectives_changed.emit(objectives_in)   # -> main._on_objectives_changed -> overlay
	await process_frame
	var objectives: Array = terrain_overlay.get_objectives()
	if objectives.is_empty():
		# Fallback: write the overlay directly (world metres) if the editor seam didn't take.
		var direct: Array = []
		for o in objectives_in:
			direct.append(Vector3((o as Vector2).x * IN2M, 0.0, (o as Vector2).y * IN2M))
		terrain_overlay.update_objectives(direct)
		objectives = terrain_overlay.get_objectives()
	_objectives_world = objectives   # cache (positions fixed) for per-activation nearest-objective distance
	printerr("[SELFPLAY] objectives on table: %d" % objectives.size())

	# --- Wire the REAL SoloController for the whole board (main's own _ensure_solo_controller) ---
	main.set("solo_ai_slots", {1: true, 2: true})   # BOTH armies are AI (self-play)
	main.set("_solo_fast", true)                     # compress pacing holds
	main.set("_solo_dev", false)                     # we render + capture decisions ourselves
	main._ensure_solo_controller()
	var solo: Node = main.get("solo_controller")
	if solo == null:
		printerr("[SELFPLAY] FATAL: SoloController was not created")
		quit(1)
		return
	solo._rng.seed = _play_seed

	# Auto-answer the one interactive seam (human save / strike-back dialogs).
	_watcher = _DialogAutoConfirm.new()
	_watcher.set("main_node", main)
	main.add_child(_watcher)

	# --- Deployment: the REAL AI deployment for BOTH sides into their 12" zones (fixed seeds) ---
	var objectives_v2: Array = []
	for o in objectives:
		objectives_v2.append(Vector2((o as Vector3).x, (o as Vector3).z))
	_deploy_side(main, solo, table, terrain_overlay, 1, objectives_v2, _deploy_seed_p1)
	_deploy_side(main, solo, table, terrain_overlay, 2, objectives_v2, _deploy_seed_p2)
	await process_frame
	battle_log.log_event(0, "=== SELF-PLAY: Battle Brothers (P1) vs Robot Legions (P2) — %d rounds ===" % GAME_ROUNDS, true)
	_audit_all_units(main, 0, "deploy")   # deploy-time geometry audit (terrain / overlap / coherency)
	# Objective ownership baseline (all neutral) for the per-round SEIZE diff.
	_prev_owners = terrain_overlay.get_objective_owners()
	await _screenshot("%s_deploy.png" % _out_name)

	# --- Run the full match ---
	army_manager.current_round = 1
	for round_no in range(1, GAME_ROUNDS + 1):
		if _over_budget():
			_blocker = "wall-clock budget (%.0fs) exceeded at round %d" % [WALL_CLOCK_BUDGET_S, round_no]
			break
		battle_log.on_round_advanced(round_no)
		printerr("[SELFPLAY] ===== ROUND %d =====" % round_no)
		# Ambush arrivals at the start of any round after the first (both sides).
		if round_no > 1:
			for slot in [1, 2]:
				_set_sides(solo, slot)
				await main._solo_arrive_ambush()
		if round_no == 2:
			await _screenshot("%s_round2.png" % _out_name)
		await _play_round(main, solo, round_no)
		# Round end: the REAL objective seize, then advance (fatigue clears, activations reset).
		main._solo_auto_seize()
		_record_seizes(main, round_no)   # diff owners → machine-readable SEIZE events
		if round_no < GAME_ROUNDS:
			main._solo_reset_all_fatigue()
			army_manager.advance_round()

	await _screenshot("%s_end.png" % _out_name)
	_write_outputs(main, solo, terrain_overlay, army_manager)
	quit(0 if _blocker.is_empty() else 2)


# === Round / activation driving ===

## One round of OPR alternating activation: the opener alternates by round parity; each side activates one
## unit in turn until BOTH sides are exhausted (the trailing side drains its remaining units). Each
## activation runs the REAL controller decision + movement and the REAL main.gd combat resolution.
func _play_round(main: Node, solo: Node, round_no: int) -> void:
	_act_order = []
	var current: int = 1 if round_no % 2 == 1 else 2   # P1 opens odd rounds, P2 opens even (OPR alternation)
	var guard := 0
	while guard < ACTIVATION_GUARD:
		guard += 1
		if _over_budget():
			_blocker = "wall-clock budget (%.0fs) exceeded mid-round %d" % [WALL_CLOCK_BUDGET_S, round_no]
			return
		var cur_has: bool = _side_has_eligible(solo, current)
		var oth_has: bool = _side_has_eligible(solo, _other(current))
		if not cur_has and not oth_has:
			break
		if cur_has:
			# Back-to-back audit: the same side must not act twice running while the OTHER side still has
			# an eligible unit (that would break OPR alternation; a one-sided TAIL after exhaustion is legal).
			if not _act_order.is_empty() and int(_act_order.back()) == current and oth_has:
				_flag(round_no, "activation_back_to_back", "P%d" % current,
					"P%d activated twice in a row while P%d still had eligible units" % [current, _other(current)])
			_act_order.append(current)
			await _drive_activation(main, solo, current, round_no)
		current = _other(current)
	_audit_overlaps(main, round_no)   # inter-unit base overlap over the whole table, end of round


## Drive one AI activation for `side` — a faithful replay of main._solo_activate_one_ai, but with the
## decision records captured/rendered by the harness (so both the JSON and the battle log get them) and
## the cosmetic move animation skipped (the controller already applied the final model positions).
func _drive_activation(main: Node, solo: Node, side: int, round_no: int) -> void:
	_set_sides(solo, side)
	var unit = solo.activate_next_ai_unit()
	if unit == null:
		return
	_capture_decisions(main, solo)
	if main.get("radial_menu_controller") != null:
		main.radial_menu_controller._update_activated_markers(unit)
	var report: Dictionary = solo.last_report
	if bool(report.get("idle_shaken", false)):
		if unit.is_shaken and main.get("radial_menu_controller") != null:
			main.radial_menu_controller.card_toggle_shaken(unit)
		main.battle_log.log_event(0, "%s spends its activation idle — recovers from Shaken" % unit.get_name(), true)
		return
	var target = report.get("target")
	if target != null:
		main.battle_log.log_event(2, "%s %s (→ %s)" % [
			unit.get_name(), AiDecision.action_name(int(report.get("action", 0))), target.get_name()], true)
	main._solo_log_unmodeled_rules(unit)
	if target != null:
		main._solo_log_unmodeled_rules(target)
	# Objective instrumentation: after the move settled, record the unit's closest-model distance to the
	# NEAREST objective marker (so "is the AI closing on objectives" is measurable per activation).
	_record_objective_distance(main, unit, round_no)
	# Post-move audit (real positions): coherency, base overlap within the unit, terrain the models rest in.
	_audit_unit_geometry(main, unit, round_no, "after move")
	# Shooting/LOS audit: the controller gates shooting on LOS; verify unit-centre LOS to the intended target.
	if bool(report.get("can_shoot", false)) and target != null:
		_audit_shooting_los(main, unit, target, round_no)
	var dangerous: int = int(report.get("dangerous_models", 0))
	var alive_before: int = unit.get_alive_count()
	if dangerous > 0:
		await main._run_ai_dangerous(unit, dangerous)
	if unit.is_destroyed():
		_capture_decisions(main, solo)
		return
	if bool(report.get("can_shoot", false)):
		await main._run_ai_shooting(report)
	elif int(report.get("action", 0)) == AiDecision.Action.CHARGE:
		var log_before: int = main.battle_log.size()
		await main._run_ai_melee(report)
		# Charge-without-attacks audit: a declared CHARGE that reached melee must roll the charger's strikes.
		_audit_charge_attacks(main, unit, target, round_no, log_before)
	if dangerous > 0 and not unit.is_destroyed() and int(report.get("action", 0)) != AiDecision.Action.CHARGE:
		await main._solo_shooting_morale(unit, alive_before, main._solo_owner_label(unit))
	_capture_decisions(main, solo)


## Drain the controller's fresh decision records: store them raw (for the JSON) and render each into the
## REAL battle log via the game's own SoloController.render_decision (what dev-mode would show).
func _capture_decisions(main: Node, solo: Node) -> void:
	var records: Array = solo.drain_decisions()
	for rec in records:
		var d := rec as Dictionary
		_decisions.append(d)
		main.battle_log.log_event(0, SoloController.render_decision(d))
		# Move-band audit: the planned corridor arc must never exceed the granted movement band (GF p.7).
		if str(d.get("kind", "")) == "move":
			var data := d.get("data", {}) as Dictionary
			var arc: float = float(data.get("arc_in", 0.0))
			var band: float = float(data.get("band_in", 0.0))
			if arc > band + 0.05:
				_flag(int(main.opr_army_manager.current_round), "move_arc_exceeds_band", str(d.get("unit", "?")),
					"corridor arc %.2f\" > band %.2f\"" % [arc, band])


# === Runtime rule-violation audit (real positions / terrain / coherency) ===

func _flag(round_no: int, kind: String, unit: String, detail: String) -> void:
	_violations.append({"round": round_no, "kind": kind, "unit": unit, "detail": detail})


## Audit every alive unit's geometry (used at deploy time). Per-unit checks are in _audit_unit_geometry.
func _audit_all_units(main: Node, round_no: int, phase: String) -> void:
	for u in main.opr_army_manager.get_all_game_units():
		if u != null and u.get_alive_count() > 0:
			_audit_unit_geometry(main, u, round_no, phase)
	_audit_overlaps(main, round_no)


## One unit after it settled: coherency broken, models resting in dangerous/impassable terrain, and any
## intra-unit base overlap (two of its own models sharing footprint).
func _audit_unit_geometry(main: Node, unit, round_no: int, phase: String) -> void:
	if unit == null or unit.get_alive_count() <= 0:
		return
	var overlay: Node = main.terrain_overlay
	var models: Array = unit.get_alive_models()
	# Terrain: DANGEROUS is a rules concern; CONTAINER/RUINS are impassable — no model may rest inside.
	for m in models:
		var node = (m as ModelInstance).node
		if node == null or not is_instance_valid(node):
			continue
		var t: int = overlay.get_terrain_at_world_position((node as Node3D).global_position)
		if t == overlay.TerrainType.CONTAINER or t == overlay.TerrainType.RUINS:
			_flag(round_no, "model_in_impassable_terrain", unit.get_name(), "%s: a model rests in impassable terrain (type %d)" % [phase, t])
			break
		if t == overlay.TerrainType.DANGEROUS:
			_flag(round_no, "model_in_dangerous_terrain", unit.get_name(), "%s: a model rests in dangerous terrain" % phase)
			break
	# Coherency (GF v3.5.1 p.6): every model within COHERENCY_DISTANCE of another in the unit.
	var result = CoherencyChecker.check_unit_coherency(unit, CoherencyChecker.is_skirmish_system(unit))
	if result != null and not result.valid:
		_flag(round_no, "coherency_broken", unit.get_name(), "%s: unit coherency invalid (%d issue(s))" % [phase, (result.issues as Array).size()])
	# Intra-unit base overlap.
	for i in range(models.size()):
		for j in range(i + 1, models.size()):
			var a := SeparationChecker.shape_for_model(models[i] as ModelInstance)
			var b := SeparationChecker.shape_for_model(models[j] as ModelInstance)
			if SeparationChecker.edge_distance(a, b) < -OVERLAP_EPS_IN:
				_flag(round_no, "base_overlap_intra_unit", unit.get_name(), "two of the unit's own bases overlap")
				return


## Inter-unit base overlap across the whole table: any two models from DIFFERENT units whose bases overlap
## (base contact of enemies mid-charge is legal and excluded via is_separation_violation's melee exemption).
func _audit_overlaps(main: Node, round_no: int) -> void:
	var entries: Array = []   # {unit, shape, pid}
	for u in main.opr_army_manager.get_all_game_units():
		if u == null or u.get_alive_count() <= 0:
			continue
		for m in u.get_alive_models():
			var node = (m as ModelInstance).node
			if node != null and is_instance_valid(node):
				entries.append({"unit": u, "shape": SeparationChecker.shape_for_model(m as ModelInstance),
					"pid": int(u.unit_properties.get("player_id", 0))})
	var seen := {}
	for i in range(entries.size()):
		for j in range(i + 1, entries.size()):
			var ea := entries[i] as Dictionary
			var eb := entries[j] as Dictionary
			if ea["unit"] == eb["unit"]:
				continue
			# An attached hero and its host unit are ONE effective unit — their bases legitimately share
			# footprint, so exclude those pairs (only genuinely separate units count as inter-unit overlap).
			if not SeparationChecker.are_different_units(ea["unit"], eb["unit"]):
				continue
			if SeparationChecker.edge_distance(ea["shape"], eb["shape"]) < -OVERLAP_EPS_IN:
				var enemies: bool = int(ea["pid"]) != int(eb["pid"])
				# Enemy overlap can be a legal mid-charge base contact; only flag deep overlap.
				if enemies and SeparationChecker.edge_distance(ea["shape"], eb["shape"]) > -0.3:
					continue
				var key := "%s|%s" % [ea["unit"].get_name(), eb["unit"].get_name()]
				if seen.has(key):
					continue
				seen[key] = true
				_flag(round_no, "base_overlap_inter_unit", "%s / %s" % [ea["unit"].get_name(), eb["unit"].get_name()],
					"bases of two different units overlap (enemies=%s)" % str(enemies))


## LOS audit: the AI declared a shot; verify the shooter's unit centre actually has line of sight to the
## target's unit centre through the real overlay (the coarse fallback LOS main wires; per-model LOS gates
## the real decision, so a centre-LOS miss here is only a soft signal, tagged as such).
func _audit_shooting_los(main: Node, shooter, target, round_no: int) -> void:
	var overlay: Node = main.terrain_overlay
	if overlay == null or not overlay.has_method("has_line_of_sight"):
		return
	var solo: Node = main.solo_controller
	var from: Vector3 = solo.unit_centre(shooter)
	var to: Vector3 = solo.unit_centre(target)
	if not overlay.has_line_of_sight(from, to, 1, 1):
		_flag(round_no, "shoot_without_centre_los", shooter.get_name(),
			"declared a shot at %s but unit-centre LOS is blocked (per-model LOS may still clear it)" % target.get_name())


## Charge-without-attacks audit: after a declared CHARGE resolved, the battle log must contain a strike/
## attack line for the charger (its own attacks were rolled), unless the charge fell short.
func _audit_charge_attacks(main: Node, charger, target, round_no: int, log_before: int) -> void:
	if charger == null:
		return
	var cname: String = charger.get_name()
	var found_strike := false
	var fell_short := false
	var all: Array = main.battle_log.entries()
	for k in range(log_before, all.size()):
		var txt: String = str((all[k] as Dictionary).get("text", ""))
		if txt.contains("falls short"):
			fell_short = true
		if txt.begins_with(cname) and (txt.contains("strike") or txt.contains("hit") or txt.contains("Impact") or txt.contains("melee") or txt.contains("deals")):
			found_strike = true
	if not fell_short and not found_strike:
		_flag(round_no, "charge_without_attacks", cname, "declared a CHARGE that reached melee but no strike/attack line was logged")


func _side_has_eligible(solo: Node, slot: int) -> bool:
	var prev: int = solo.ai_slot
	solo.ai_slot = slot
	var has: bool = not solo.eligible_ai_units().is_empty()
	solo.ai_slot = prev
	return has


## Point the controller at `slot` as the acting AI and the other slot as its enemy — main's combat helpers
## read solo_controller.human_slot for target selection, so both must flip together per activation.
func _set_sides(solo: Node, slot: int) -> void:
	solo.ai_slot = slot
	solo.human_slot = _other(slot)


func _other(slot: int) -> int:
	return 2 if slot == 1 else 1


# === Seed + output naming (per-game diversity) ===

## Parse `-- seed=<n> out=<name>` (cmdline user args, after the `--`) or the NML_SELFPLAY_SEED env var.
## A seed derives four independent sub-seeds so different seeds => different terrain / deploy / AI pick,
## same seed => identical game (real dice aside). No seed => legacy fixed board + "game1_*" outputs.
func _parse_args() -> void:
	var seed_str := ""
	var out_name := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="):
			seed_str = a.substr("seed=".length())
		elif a.begins_with("out="):
			out_name = a.substr("out=".length())
	if seed_str.is_empty():
		var env := OS.get_environment("NML_SELFPLAY_SEED")
		if not env.is_empty():
			seed_str = env
	if not seed_str.is_empty() and seed_str.is_valid_int():
		_game_seed = int(seed_str)
		_out_name = out_name if not out_name.is_empty() else "game_%d" % _game_seed
		_layout_seed = _derive_seed(_game_seed, 101)
		_play_seed = _derive_seed(_game_seed, 202)
		_deploy_seed_p1 = _derive_seed(_game_seed, 303)
		_deploy_seed_p2 = _derive_seed(_game_seed, 404)
	else:
		_game_seed = -1
		_out_name = "game1"
		_layout_seed = LAYOUT_SEED
		_play_seed = SELFPLAY_SEED
		_deploy_seed_p1 = SELFPLAY_SEED + 1
		_deploy_seed_p2 = SELFPLAY_SEED + 2


## Deterministic 31-bit sub-seed mix (splitmix-style) — same (base, salt) always yields the same value,
## and neighbouring base values scatter widely so seeds 1/2/3 give unrelated boards.
func _derive_seed(base: int, salt: int) -> int:
	var x: int = (base * 2654435761 + salt * 40503 + 2654435769) & 0x7FFFFFFF
	x ^= (x >> 13)
	x = (x * 1274126177) & 0x7FFFFFFF
	x ^= (x >> 16)
	return x & 0x7FFFFFFF


# === Objective instrumentation ===

## Record (battle log + machine-readable event) the acting unit's closest-model distance to the NEAREST
## objective marker after its move. In2M-scaled world positions -> inches via MoveIntent.distance_inches.
func _record_objective_distance(main: Node, unit, round_no: int) -> void:
	if unit == null or _objectives_world.is_empty():
		return
	var solo: Node = main.get("solo_controller")
	if solo == null:
		return
	var positions: Array = solo.alive_positions(unit)
	if positions.is_empty():
		return
	var best_d := INF
	var best_idx := -1
	for p in positions:
		for oi in range(_objectives_world.size()):
			var d: float = MoveIntent.distance_inches(p as Vector3, _objectives_world[oi] as Vector3)
			if d < best_d:
				best_d = d
				best_idx = oi
	if best_idx < 0:
		return
	# CONTEST/HOLD threshold is 3" in OPR (a model within 3" of a marker contests it).
	var holding: bool = best_d <= 3.0
	main.battle_log.log_event(2, "%s nearest objective #%d: %.1f\"%s" % [
		unit.get_name(), best_idx + 1, best_d, ("  [within 3\" — contesting]" if holding else "")], true)
	_obj_events.append({"kind": "objective_distance", "round": round_no, "unit": unit.get_name(),
		"nearest_index": best_idx, "dist_in": snappedf(best_d, 0.01), "within_3in": holding})


## Diff the objective owners against the previous snapshot after the round-end auto-seize; emit an explicit
## SEIZE event (battle log + machine-readable) for every marker that changed to a non-neutral owner.
func _record_seizes(main: Node, round_no: int) -> void:
	var overlay: Node = main.get("terrain_overlay")
	if overlay == null:
		return
	var owners: Array = overlay.get_objective_owners()
	for i in range(owners.size()):
		var new_owner: int = int(owners[i])
		var old_owner: int = int(_prev_owners[i]) if i < _prev_owners.size() else 0
		if new_owner != old_owner and new_owner != 0:
			main.battle_log.log_event(0, "SEIZE: P%d takes objective #%d (round %d)" % [new_owner, i + 1, round_no], true)
			_obj_events.append({"kind": "seize", "round": round_no, "index": i, "owner": new_owner,
				"from": old_owner})
	_prev_owners = owners.duplicate()


# === Board build helpers ===

## Import one fixture through the production TTS parser + spawn path. Falls back to a direct list parse
## (offline-safe) only if the networked import yields nothing, so the harness always reaches a real board.
func _import_and_spawn(army_manager: Node, fixture: String, player_id: int) -> bool:
	var text := FileAccess.get_file_as_string(fixture)
	if text.is_empty():
		printerr("[SELFPLAY] FATAL: fixture missing/empty: %s" % fixture)
		quit(1)
		return false
	printerr("[SELFPLAY] importing player %d (%s)…" % [player_id, fixture.get_file()])
	# The fixtures are the exact /api/tts bodies; _parse_tts_api_response is the production parser
	# (import_from_share_link's parser, incl. the army-book faction/rules fetch).
	var army = await army_manager.api_client._parse_tts_api_response(text)
	if army == null or army.units.is_empty():
		printerr("[SELFPLAY] FATAL: player %d import produced no units" % player_id)
		quit(1)
		return false
	army.player_id = player_id
	army_manager.get("armies")[player_id] = army
	await army_manager.spawn_army(army)
	var spawned: int = army_manager.get_game_units_for_player(player_id).size()
	printerr("[SELFPLAY] player %d = '%s' (%s) — %d units, %d pts, %d game units spawned" % [
		player_id, army.name, army.faction_folder, army.units.size(), army.points, spawned])
	return spawned > 0


## Deploy one side through the REAL SoloController.deploy_army (official OPR AI deployment: objective-near
## spots in each unit's table section, blocking/dangerous terrain avoided, physics-probed against props),
## seeded for reproducibility. Mirrors main._on_solo_deploy_pressed, incl. hiding Ambush reserves.
func _deploy_side(main: Node, solo: Node, table: Node, terrain_overlay: Node, slot: int, objectives_v2: Array, seed_value: int) -> void:
	_set_sides(solo, slot)
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
	main.battle_log.log_event(0, "P%d deploys %d units (%d in ambush reserve) [seed %d]" % [
		slot, int(res.get("deployed", 0)), int(res.get("reserved", 0)), seed_value], true)
	printerr("[SELFPLAY] P%d deployed %d units (%d reserve)" % [slot, int(res.get("deployed", 0)), int(res.get("reserved", 0))])
	_capture_decisions(main, solo)


func _await_main() -> Node:
	for _i in range(MAX_BOOT_FRAMES):
		await process_frame
		var scene := current_scene
		if scene != null and scene.get("opr_army_manager") != null and scene.get("map_layout_editor") != null \
				and scene.get("terrain_overlay") != null and scene.get("battle_log") != null:
			return scene
	return null


# === Output ===

func _screenshot(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	await process_frame
	var tex := root.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	var path := _out_dir.path_join(file_name)
	if img.save_png(path) == OK:
		printerr("[SELFPLAY] screenshot -> %s" % path)


func _write_outputs(main: Node, solo: Node, terrain_overlay: Node, army_manager: Node) -> void:
	var battle_log: Node = main.get("battle_log")
	# 1) Human-readable battle log, in order.
	var log_lines: Array = []
	var cats := ["GEN", "COMBAT", "MOVE"]
	for e in battle_log.entries():
		var entry := e as Dictionary
		var cat: int = int(entry.get("category", 0))
		var tag: String = cats[cat] if cat < cats.size() else "GEN"
		if bool(entry.get("ai", false)):
			tag += "/AI"
		log_lines.append("R%d [%s] %s" % [int(entry.get("round", 0)), tag, str(entry.get("text", ""))])
	_write_file("%s_battlelog.txt" % _out_name, "\n".join(log_lines) + "\n")

	# 2) Structured decision records + machine-readable objective events (distances + seizes).
	_write_file("%s_decisions.json" % _out_name, JSON.stringify(_decisions, "\t"))
	_write_file("%s_objectives.json" % _out_name, JSON.stringify(_obj_events, "\t"))

	# 3) Summary: scores, rounds, unit fates.
	var objectives: Array = terrain_overlay.get_objectives()
	var owners: Array = terrain_overlay.get_objective_owners()
	var held := {0: 0, 1: 0, 2: 0}
	for o in owners:
		held[int(o)] = int(held.get(int(o), 0)) + 1
	var p1_held: int = int(held.get(1, 0))
	var p2_held: int = int(held.get(2, 0))
	var neutral: int = int(held.get(0, 0))
	var verdict: String
	if p1_held > p2_held:
		verdict = "Battle Brothers (P1) win"
	elif p2_held > p1_held:
		verdict = "Robot Legions (P2) win"
	else:
		verdict = "Draw (objectives) — tie-break by surviving models"
	var seize_count := 0
	for ev in _obj_events:
		if str((ev as Dictionary).get("kind", "")) == "seize":
			seize_count += 1
	# Deploy-position fingerprint: hash the sorted deploy spots so "different unit start positions" per seed
	# is machine-provable (the deploy RNG is seeded per game).
	var deploy_pts: Array = []
	for d in _decisions:
		var dd := d as Dictionary
		if str(dd.get("kind", "")) == "deploy":
			var data := dd.get("data", {}) as Dictionary
			deploy_pts.append("%.3f,%.3f" % [float(data.get("x_m", 0.0)), float(data.get("z_m", 0.0))])
	deploy_pts.sort()
	var deploy_fingerprint: String = str(hash("|".join(deploy_pts)))
	var rounds_played: int = mini(army_manager.current_round, GAME_ROUNDS)
	var lines: Array = []
	lines.append("SELF-PLAY %s — Battle Brothers (P1) vs Robot Legions (P2)  [seed %s]" % [
		_out_name, ("legacy" if _game_seed < 0 else str(_game_seed))])
	lines.append("Rounds played: %d / %d%s" % [rounds_played, GAME_ROUNDS,
		("  [ABORTED: %s]" % _blocker) if not _blocker.is_empty() else ""])
	lines.append("Objectives: %d markers — P1 %d · P2 %d · neutral %d" % [objectives.size(), p1_held, p2_held, neutral])
	# Machine-readable objective + seize result line (grep-friendly for the batch aggregator).
	lines.append("OBJECTIVES_RESULT total=%d p1=%d p2=%d neutral=%d seizes=%d" % [
		objectives.size(), p1_held, p2_held, neutral, seize_count])
	lines.append("Verdict: %s" % verdict)
	lines.append("")
	lines.append("Unit fates:")
	for pid in [1, 2]:
		var alive_models := 0
		var alive_units := 0
		for u in army_manager.get_game_units_for_player(pid):
			if u == null:
				continue
			var a: int = u.get_alive_count()
			var m: int = u.models.size()
			alive_models += a
			if a > 0:
				alive_units += 1
			var state := "destroyed" if u.is_destroyed() else ("SHAKEN" if u.is_shaken else "ok")
			lines.append("  P%d  %-28s %d/%d models  %s" % [pid, u.get_name(), a, m, state])
		lines.append("  -> P%d: %d units left, %d models alive" % [pid, alive_units, alive_models])
	lines.append("")
	lines.append("Decisions captured: %d   Battle-log entries: %d" % [_decisions.size(), battle_log.size()])
	# Rule-violation audit summary folded into the game summary, full detail in <out>_violations.txt.
	var counts := {}
	for v in _violations:
		var k: String = str((v as Dictionary).get("kind", "?"))
		counts[k] = int(counts.get(k, 0)) + 1
	lines.append("")
	lines.append("Rule-violation audit: %d total" % _violations.size())
	if _violations.is_empty():
		lines.append("  (none across all audited classes)")
	else:
		for k in counts:
			lines.append("  %-32s %d" % [k, int(counts[k])])
	_write_file("%s_summary.txt" % _out_name, "\n".join(lines) + "\n")

	# 3b) Machine-readable per-game result (the batch aggregator reads these directly).
	var result := {
		"seed": _game_seed,
		"out": _out_name,
		"legacy": _game_seed < 0,
		"layout_seed": _layout_seed,
		"play_seed": _play_seed,
		"terrain_pieces": _terrain_pieces,
		"terrain_fingerprint": _terrain_fingerprint,
		"terrain_origins": _terrain_origins,
		"deploy_fingerprint": deploy_fingerprint,
		"deploy_positions": deploy_pts.size(),
		"rounds_played": rounds_played,
		"rounds_total": GAME_ROUNDS,
		"aborted": _blocker,
		"objectives": {"total": objectives.size(), "p1": p1_held, "p2": p2_held, "neutral": neutral},
		"seize_events": seize_count,
		"verdict": verdict,
		"decisions": _decisions.size(),
		"battle_log_entries": battle_log.size(),
		"violations": {"total": _violations.size(), "by_kind": counts},
	}
	_write_file("%s_result.json" % _out_name, JSON.stringify(result, "\t"))

	# 4) Full rule-violation audit.
	var vlines: Array = []
	vlines.append("RULE-VIOLATION AUDIT — self-play %s" % _out_name)
	vlines.append("Classes checked: model in blocking/dangerous terrain (deploy + after move); shooting")
	vlines.append("without LOS; move corridor arc > band; coherency broken after move; two AI activations")
	vlines.append("back-to-back across alternation; declared charge with no attacks rolled; base overlap")
	vlines.append("(intra-unit + inter-unit).")
	vlines.append("")
	if _violations.is_empty():
		vlines.append("RESULT: 0 violations detected across all classes.")
	else:
		vlines.append("RESULT: %d violation(s)." % _violations.size())
		for k in counts:
			vlines.append("  %-32s %d" % [k, int(counts[k])])
		vlines.append("")
		for v in _violations:
			var vd := v as Dictionary
			vlines.append("R%d  [%s]  %s — %s" % [int(vd.get("round", 0)), str(vd.get("kind", "?")),
				str(vd.get("unit", "?")), str(vd.get("detail", ""))])
	_write_file("%s_violations.txt" % _out_name, "\n".join(vlines) + "\n")

	printerr("\n[SELFPLAY] ================= COMPLETE =================")
	printerr("[SELFPLAY] %s" % verdict)
	printerr("[SELFPLAY] battle log : %s" % _out_dir.path_join("%s_battlelog.txt" % _out_name))
	printerr("[SELFPLAY] decisions  : %s" % _out_dir.path_join("%s_decisions.json" % _out_name))
	printerr("[SELFPLAY] objectives : %s  (%d events, %d seizes)" % [
		_out_dir.path_join("%s_objectives.json" % _out_name), _obj_events.size(), seize_count])
	printerr("[SELFPLAY] summary    : %s" % _out_dir.path_join("%s_summary.txt" % _out_name))
	printerr("[SELFPLAY] result     : %s" % _out_dir.path_join("%s_result.json" % _out_name))
	printerr("[SELFPLAY] violations : %s  (%d found)" % [_out_dir.path_join("%s_violations.txt" % _out_name), _violations.size()])
	if not _blocker.is_empty():
		printerr("[SELFPLAY] NOTE: match aborted early — %s" % _blocker)


func _write_file(file_name: String, content: String) -> void:
	var path := _out_dir.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[SELFPLAY] ERROR: cannot write %s" % path)
		return
	f.store_string(content)
	f.close()


func _over_budget() -> bool:
	return (Time.get_ticks_msec() / 1000.0) - _t0 > WALL_CLOCK_BUDGET_S


# === Interactive-seam stub (in the tool only): auto-answer the human save / strike-back dialogs ===

## Every frame, confirm any visible AcceptDialog/ConfirmationDialog under main — the ONLY human gates on
## the solo combat path (_solo_prompt_saves awaits `confirmed`; _solo_confirm_strike_back awaits
## `visibility_changed` and reads `confirmed`). Emitting `confirmed` + hiding satisfies both: the defender
## always rolls its saves and always strikes back. No other dialogs are triggered during a driven match.
class _DialogAutoConfirm extends Node:
	var main_node: Node
	var confirmed_count: int = 0

	func _process(_delta: float) -> void:
		if main_node != null:
			_scan(main_node)

	func _scan(node: Node) -> void:
		for child in node.get_children():
			if child is AcceptDialog and (child as AcceptDialog).visible:
				var dlg := child as AcceptDialog
				dlg.confirmed.emit()
				dlg.hide()
				confirmed_count += 1
			_scan(child)
