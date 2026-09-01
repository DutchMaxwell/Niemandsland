extends SceneTree
## CORE self-play runner (NML-995 core track, S1): full AI-vs-AI matches on
## the BattleSim substrate WITHOUT the game engine — no main.tscn, no models,
## no renderer. One process amortises its ~2s boot over thousands of games,
## replacing minutes-per-game Godot matches for TRAINING DATA generation.
##
## HONESTY GATE (documented, enforced by the roadmap): core results feed
## TRAINING only until the S3 parity ladder proves rule-equivalence against
## engine replays. The ladder A/B stays on the real engine until then.
##
## v0 scope: BattleSim rules (morale, fatigue, fractional wounds, spells EV)
## with STOCHASTIC ROUNDING of expected wounds (mean-preserving; real per-die
## sampling is S4); simple line deployment (no terrain); planner picks per
## activation for BOTH sides via AiPlanner.plan_with_rollout on the live
## core state; official alternation incl. the finished-first round opener.
##
## Run: godot --headless -s res://tools/core_selfplay.gd -- \
##        army1=<json> army2=<json> seed=1 games=100 out=<dir>

const IN2M := 0.0254
const TABLE_W_IN := 72.0
const TABLE_D_IN := 48.0
const ROUNDS := 4
## Board rows moved to BattleSim.board_rows (ONE canonical source for factory
## and in-game encoder — NML-995 v5). Kept here as thin delegates so the
## existing tests and call sites stay valid.
static func _board_rows(state: Dictionary) -> Array:
	return BattleSim.board_rows(state)


## NML-1046 M2a: magic-cast telemetry seed — per-side granted/caster/spell-book
## counts computed ONCE from the built rosters (before any activation), plus
## the empty per-game cast/token counters _play_round fills in as it plays.
static func _magic_init(units1: Array, units2: Array) -> Dictionary:
	var magic := {"granted": {"p1": 0, "p2": 0}, "casters": {"p1": 0, "p2": 0},
		"books_resolved": {"p1": 0, "p2": 0}, "casts": {"p1": 0, "p2": 0},
		"tokens_spent": {"p1": 0, "p2": 0},
		# NML-1064: eligibility counters — "never eligible" (no tokens, or no
		# enemy in spell range) vs "eligible but chose not to cast" needs its
		# own denominator; casts/tokens_spent alone can't tell them apart.
		"caster_activations": {"p1": 0, "p2": 0}, "in_range_activations": {"p1": 0, "p2": 0},
		# NML-1069: WHAT was cast, not just how much was paid — the cast sub-phase
		# stamps a kind per attempt (battle_sim.gd:_cast_phase), and a corpus that
		# only ever throws damage spells is a different bug from one that never casts.
		"spells_by_kind": {"p1": {"damage": 0, "buff": 0, "debuff": 0},
			"p2": {"damage": 0, "buff": 0, "debuff": 0}}}
	for pair in [["p1", units1], ["p2", units2]]:
		var key: String = pair[0]
		for u in (pair[1] as Array):
			var gu := u as GameUnit
			magic["granted"][key] = int(magic["granted"][key]) + gu.casts_current
			if gu.casts_current > 0:
				magic["casters"][key] = int(magic["casters"][key]) + 1
				if not SpellsRegistry.spells_for_unit(gu).is_empty():
					magic["books_resolved"][key] = int(magic["books_resolved"][key]) + 1
	return magic


## Played-actions-only tally: a positive token delta across the ONE resolve at
## the PLAYED action (core_selfplay.gd:167) IS the one-spell-per-activation
## cast event (battle_sim.gd:_cast_phase) — the pair/fork resolves in _play_round
## run on CLONES and never reach this call.
static func _magic_tally(magic: Dictionary, side_key: String, tokens_before: int,
		tokens_after: int) -> void:
	var delta := tokens_before - tokens_after
	if delta > 0:
		magic["casts"][side_key] = int(magic["casts"][side_key]) + 1
		magic["tokens_spent"][side_key] = int(magic["tokens_spent"][side_key]) + delta


## NML-1069 companion of _magic_tally: the KINDS the played apply cast. `events`
## is the round's cast log (state["cast_events"], accumulated across the round),
## `from` its size read PRE-apply — so only this activation's stamps are counted.
static func _spells_by_kind_tally(magic: Dictionary, side_key: String, events: Array,
		from: int) -> void:
	var by_kind: Dictionary = magic["spells_by_kind"][side_key]
	for i in range(maxi(from, 0), events.size()):
		var kind := str((events[i] as Dictionary).get("kind", ""))
		if by_kind.has(kind):
			by_kind[kind] = int(by_kind[kind]) + 1


## NML-1064 round-start refill — GF v3.5.1 Caster(X): "Gets X spell tokens at
## the start of each round, but can't hold more than 6" (accumulate+cap-6
## lives on GameUnit.add_round_caster_points, game_unit.gd:426). The build-
## time grant (initialize_caster_points, _units_from_list) covers round 1
## only — the round loop (_play_one) calls this for round_no >= 2.
static func _refill_round_caster_points(su: Dictionary, magic: Dictionary, side_key: String) -> void:
	var gu := su.get("unit") as GameUnit
	if gu == null:
		return
	# The sim only ever DECREMENTS su["casts"] (the cast sub-phase spends the
	# attempt's tokens, battle_sim.gd:_cast_phase) and never writes back to the
	# GameUnit — sync the ledger to the sim's spend before granting, or the
	# refill starts from a stale (too-high) balance.
	gu.casts_current = int(su.get("casts", 0))
	var before := gu.casts_current
	gu.add_round_caster_points()
	su["casts"] = gu.casts_current
	magic["granted"][side_key] = int(magic["granted"][side_key]) + (gu.casts_current - before)


## NML-1064 eligibility tally — "never eligible" (no tokens, or no living
## enemy within spell range) vs "eligible but chose not to cast" needs its
## own denominator; _magic_tally alone (a positive token delta) can't tell
## them apart. Reads `state` PRE-apply — the same instant _magic_tally reads
## casts_before at the call site — so the resolve this activation is about
## to produce never counts here.
static func _magic_eligibility_tally(magic: Dictionary, side_key: String,
		state: Dictionary, actor_key: String) -> void:
	var su: Dictionary = (state["units"] as Dictionary).get(actor_key, {})
	if int(su.get("casts", 0)) <= 0:
		return
	magic["caster_activations"][side_key] = int(magic["caster_activations"][side_key]) + 1
	var gu := su.get("unit") as GameUnit
	if gu == null:
		return
	var max_range := 0.0
	for e in SpellsRegistry.spells_for_unit(gu):
		max_range = maxf(max_range, float((e as Dictionary).get("range_in", 0)))
	if max_range <= 0.0:
		return
	var actor_player := int(su.get("player", 0))
	var positions: Array = su.get("positions", [])
	for k in (state["units"] as Dictionary):
		var ou: Dictionary = state["units"][k]
		if int(ou.get("player", 0)) == actor_player or int(ou.get("alive", 0)) <= 0:
			continue
		if BattleSim.dist_in(positions, ou.get("positions", [])) <= max_range + 0.001:
			magic["in_range_activations"][side_key] = int(magic["in_range_activations"][side_key]) + 1
			return


var _army1 := ""
var _army2 := ""
var _seed := 1
var _games := 1
var _out := ""
var _magic: Dictionary = {}
var _doctrine_mode := "rulebook"   # NML-1140 step 8: the resolved placement rung — env override + strongest seat's preset (SoloDifficulty.resolve_placement)


func _initialize() -> void:
	_parse_args()
	# NML-1140 step 8: ONE resolver (env NML_OBJECTIVE_DOCTRINE override, else the
	# strongest seat's preset — no seat grades here, so the default preset decides).
	# Unknown words and an armed rung without NML_OBJECTIVES=rulebook FATAL loudly
	# inside it. Refused BEFORE the _run_all connect, so nothing plays on.
	_doctrine_mode = SoloDifficulty.resolve_placement("", "",
		OS.get_environment("NML_OBJECTIVES").strip_edges().to_lower())
	if _doctrine_mode == "?":
		quit(1)
		return
	# Script-mode quirk: during _initialize the root window is NOT yet inside
	# the tree, so add_child'ed nodes never enter it and every Node3D position
	# write fails SILENTLY (all units sat at the origin — the S3 gate's whole
	# "melee ball" cluster). Start on the first process frame instead.
	process_frame.connect(_run_all, CONNECT_ONE_SHOT)


func _run_all() -> void:
	var t0 := Time.get_ticks_msec()
	var played := 0
	for g in range(_games):
		_play_one(_seed + g)
		played += 1
	var dt := float(Time.get_ticks_msec() - t0) / 1000.0
	printerr("[CORE] %d games in %.1fs (%.2f games/s)" % [played, dt, played / maxf(dt, 0.001)])
	quit(0)


## One full match: build fresh units, deploy on facing lines, alternate
## activations under the official rules, seize at round ends, score markers.
func _play_one(game_seed: int) -> void:
	if BattleSim.profile_enabled():
		BattleSim.profile_reset()
	var _prof_game_t0 := Time.get_ticks_usec() if BattleSim.profile_enabled() else 0
	var rng := RandomNumberGenerator.new()
	rng.seed = game_seed
	var units1 := _units_from_list(_army1, 1)
	var units2 := _units_from_list(_army2, 2)
	if units1.is_empty() or units2.is_empty():
		printerr("[CORE] FATAL: empty army (%s / %s)" % [_army1, _army2])
		quit(1)
		return
	_magic = _magic_init(units1, units2)
	var objectives := [Vector3(-16.0 * IN2M, 0, 0), Vector3.ZERO, Vector3(16.0 * IN2M, 0, 0)]
	# Realism wave (maintainer 14.08.): the REAL symmetric map layouter is the
	# one terrain source for table and school. NOTE the old _gen_terrain drew 9
	# values from the game rng — its removal starts a new world era anyway
	# (result stamp school_world=2 keeps corpora separate).
	_world = SchoolTerrain.generate(game_seed)
	# D8a: NML_OBJECTIVES=rulebook swaps the three constants for the seeded rulebook
	# layout. The board is this tool's own SchoolTerrain world — the very cells its act
	# header records — so the twin re-derives the layout from the header. The board seed
	# IS game_seed here, so that is the objective stream's seed too.
	if OS.get_environment("NML_OBJECTIVES").strip_edges().to_lower() == "rulebook":
		# NML-1140 step 7: the rung ("" = today's rulebook draw) + the armies'
		# profiles in seat order 1/2 — the doctrine is army-order-symmetric.
		var armies := [ObjectiveLayout.army_profiles(units1), ObjectiveLayout.army_profiles(units2)]
		var stamp_o := ObjectiveLayout.generate(game_seed, MissionCatalog.get_mission("duel"),
			DeploymentCatalog.get_style("front_line"), _world["cells"], int(_world["n"]),
			TABLE_W_IN, TABLE_D_IN, _doctrine_mode, armies)
		objectives = []
		for rp in (stamp_o["positions"] as Array):
			objectives.append(Vector3(float(rp[0]) * IN2M, 0.0, float(rp[1]) * IN2M))
		AiActRecorder.objectives_stamp = stamp_o
		printerr("[CORESP] objectives=rulebook: rolled %d, P%d first, seed %d, swept %d" % [
			int(stamp_o["count_roll"]), int(stamp_o["first_placer"]), game_seed,
			int(stamp_o["swept"])])
	_deploy_zone(units1, -TABLE_D_IN / 2.0, 12.0, rng)
	_deploy_zone(units2, TABLE_D_IN / 2.0 - 12.0, 12.0, rng)
	var state := _capture(units1 + units2, objectives, _world)
	# D8a: the owner slot count follows the LAYOUT, not the historical three — the
	# rulebook generator rolls D3+2 markers.
	var owners: Array = []
	for _oi in range(objectives.size()):
		owners.append(0)
	var vp := [0, 0]   # NML-1008: cumulative VPs, 1/marker at each round end
	var opener := 1 if rng.randi_range(1, 6) >= rng.randi_range(1, 6) else 2
	var positions_log: Array = []
	for round_no in range(1, ROUNDS + 1):
		state["round"] = round_no
		# NML-1069: the round's cast log starts empty, and every spell modifier from
		# the last round expires with it ("until the end of the round").
		state["cast_events"] = []
		BattleSim.reset_round_mods(state)
		for k in state["units"]:
			var su: Dictionary = state["units"][k]
			su["activated"] = false
			su["fatigued"] = false
			# NML-1064: round 1 keeps the build-time grant (initialize_caster_points,
			# _units_from_list) -- round 2+ must refill under the real per-round
			# Caster(X) rule, or every core game after round 1 plays with a dead
			# spell economy (add_round_caster_points is never called otherwise).
			if round_no >= 2:
				_refill_round_caster_points(su, _magic, "p%d" % int(su["player"]))
		opener = _play_round(state, opener, rng, positions_log, round_no, game_seed,
			owners, objectives)
		state = _last_state   # adopt the played round (resolve works on clones)
		_seize(state, objectives, owners)
		BattleSim.vp_round_add(owners, vp)
	BattleSim.vp_end_bonus(owners, vp)
	# NML-1072: env-gated wall-clock split of this game (unset NML_PROFILE =
	# no timing calls at all above, so this whole block is skipped byte-for-
	# byte). resolve/clone/spacing/cast run INSIDE plan's search (and the
	# played/fork resolves outside it) so they overlap with plan and each
	# other — reported as their own totals, not summed into "other"; other =
	# total - plan - snapshot (the only two non-overlapping outer buckets).
	var _prof_summary := {}
	if BattleSim.profile_enabled():
		var _prof_total := Time.get_ticks_usec() - _prof_game_t0
		var _prof_other := _prof_total - int(BattleSim.profile["plan"]) - int(BattleSim.profile["snapshot"])
		_prof_summary = {"total_usec": _prof_total, "other_usec": _prof_other}
		for k in BattleSim.profile.keys():
			_prof_summary[k] = BattleSim.profile[k]
		printerr(("[CORE] PROFILE total=%.3fs plan=%.3fs(%d) resolve=%.3fs(%d) " +
			"clone=%.3fs(%d) snapshot=%.3fs(%d) spacing=%.3fs(%d) cast=%.3fs(%d) other=%.3fs") % [
			_prof_total / 1.0e6, int(BattleSim.profile["plan"]) / 1.0e6, int(BattleSim.profile["plan_n"]),
			int(BattleSim.profile["resolve"]) / 1.0e6, int(BattleSim.profile["resolve_n"]),
			int(BattleSim.profile["clone"]) / 1.0e6, int(BattleSim.profile["clone_n"]),
			int(BattleSim.profile["snapshot"]) / 1.0e6, int(BattleSim.profile["snapshot_n"]),
			int(BattleSim.profile["spacing"]) / 1.0e6, int(BattleSim.profile["spacing_n"]),
			int(BattleSim.profile["cast"]) / 1.0e6, int(BattleSim.profile["cast_n"]),
			_prof_other / 1.0e6])
	_write_result(game_seed, owners, positions_log, vp, _prof_summary)
	# NML-1073 M2-0b: close the planner's statics at THIS game's end — the
	# node-dump stream and, above all, the leaf stash: it holds this game's
	# state, including the los_blocked lambda bound to the school world, and a
	# lambda freed at process teardown corrupts the heap (measured: exit 134).
	# The multi-game loop (_games > 1) reopens the dump fresh.
	AiPlanner.close()
	# NML-1073 M3-0: AiPlanner.close() does not touch the ACT stream (a separate
	# static) — without this a _games>1 run would keep one acts.jsonl header/cap
	# across every game in the process instead of one file per game.
	AiActRecorder.close()


## Alternate single activations (official one-for-one; a dry side passes the
## tail to the other). Returns the NEXT round's opener (finished-first rule:
## the side that did NOT take the last activation opens).
func _play_round(state: Dictionary, opener: int, rng: RandomNumberGenerator,
		positions_log: Array, round_no: int, game_seed: int,
		owners: Array = [], objectives: Array = []) -> int:
	var turn := opener
	var last_side := 0
	var forked := false
	var rp_count := 0
	var guard: int = (state["units"] as Dictionary).size() * 2 + 4
	while guard > 0:
		guard -= 1
		var pick := _pick_for(state, turn)
		if pick.is_empty():
			var other := 2 if turn == 1 else 1
			pick = _pick_for(state, other)
			if pick.is_empty():
				break
			turn = other
		var _prof_sn_t0 := Time.get_ticks_usec() if BattleSim.profile_enabled() else 0
		var row := {"side": turn, "round": round_no,
			"seq": positions_log.size(),
			"value": float((pick.get("expectation", {}) as Dictionary).get("before", -1.0)),
			"features": AiMissionEval.features(state, turn, BattleSim.reply_threat(state, turn), true),
			"board": _board_rows(state),
			# Judge-bench sidecars (NML-1006): roster indices per row + the
			# planner's ORIGINAL intent sentence — next to the rows, never in
			# them (v5 number format untouched).
			"ids": BattleSim.board_row_indices(state),
			"intent": str(pick.get("intent", ""))}
		if BattleSim.profile_enabled():
			BattleSim.profile["snapshot"] += Time.get_ticks_usec() - _prof_sn_t0
			BattleSim.profile["snapshot_n"] += 1
		# E0b (controller-proxy pairs for E2): resolve the CHOSEN and the
		# REJECTED candidate on clones and log both end boards. A log-only
		# rng keeps the game's dice stream untouched (determinism per seed).
		var ru: Dictionary = pick.get("runner_up", {})
		if not ru.is_empty() and ru.has("action"):
			var lrng := RandomNumberGenerator.new()
			lrng.seed = game_seed * 100000 + positions_log.size()
			var st_ch := BattleSim.resolve_stochastic(state, pick["action"], lrng)
			lrng.seed = game_seed * 100000 + positions_log.size() + 50000
			var st_ru := BattleSim.resolve_stochastic(state, ru["action"], lrng)
			row["pair"] = {"chosen": _board_rows(st_ch),
				"runner": _board_rows(st_ru),
				"chosen_ids": BattleSim.board_row_indices(st_ch),
				"runner_ids": BattleSim.board_row_indices(st_ru)}
			# E2-v2 fork counterfactuals (maintainer decisions 14.08.: ONE fork
			# per round, played to GAME END): the round's round_no-th runner-
			# bearing pick forks — both branches play out on clones under a
			# fork-local rng; the game's dice stream stays untouched. The
			# outcome DELTA is the first true decision label in the corpus.
			rp_count += 1
			if not forked and rp_count >= round_no and not owners.is_empty():
				forked = true
				var frng := RandomNumberGenerator.new()
				# NML_FORK_SALT shifts ONLY the fork dice (label-noise probes:
				# same game, re-diced playouts). Unset = 0 = byte-identical.
				var fsalt := int(OS.get_environment("NML_FORK_SALT"))
				# Label-noise fix (probe 14.08.: single playouts flip sign in
				# 3 of 4 forks under re-dicing): THREE playouts per branch,
				# training label = the mean delta; per-run points stay logged.
				var c_runs: Array = []
				var r_runs: Array = []
				for rep in range(3):
					frng.seed = game_seed * 1000003 + positions_log.size() 						+ rep * 70001 + fsalt
					c_runs.append(_fork_playout(state, pick["action"], turn,
						round_no, owners, objectives, frng))
					frng.seed = game_seed * 1000003 + positions_log.size() 						+ 500011 + rep * 70001 + fsalt
					r_runs.append(_fork_playout(state, ru["action"], turn,
						round_no, owners, objectives, frng))
				row["fork"] = {"chosen_runs": c_runs, "runner_runs": r_runs}
		positions_log.append(row)
		# NML-1046 M2a: the ONE played apply per activation — the pair/fork
		# resolves above run on clones and must never feed the magic tally.
		var ak := str((pick["action"] as Dictionary).get("unit", ""))
		var casts_before := int((state["units"].get(ak, {}) as Dictionary).get("casts", 0))
		var events_before := (state.get("cast_events", []) as Array).size()
		# NML-1064: eligibility tally reads `state` PRE-apply, the same instant
		# casts_before above is read.
		_magic_eligibility_tally(_magic, "p%d" % turn, state, ak)
		state = BattleSim.resolve_stochastic(state, pick["action"], rng)
		if (state["units"] as Dictionary).has(ak):
			var casts_after := int((state["units"][ak] as Dictionary).get("casts", 0))
			_magic_tally(_magic, "p%d" % turn, casts_before, casts_after)
		_spells_by_kind_tally(_magic, "p%d" % turn,
			state.get("cast_events", []), events_before)
		last_side = turn
		turn = 2 if turn == 1 else 1
	# writeback: resolve clones — copy the final round state over the caller's
	_last_state = state
	return (2 if last_side == 1 else 1) if last_side != 0 else opener


var _last_state: Dictionary = {}
var _world: Dictionary = {}


## Judge-bench sidecar: unit display names in the units-dict key order —
## clone_state preserves that order, and dead units keep their slot, so the
## per-board "ids" indices map into this list for the whole game.
func _roster_names() -> Array:
	var out: Array = []
	for k in _last_state.get("units", {}):
		var gu: Variant = (_last_state["units"][k] as Dictionary).get("unit")
		out.append(str(gu.get_name()) if gu != null else str(k))
	return out




## E2-v2: play ONE branch (the given action from the given pre-pick state) to
## GAME END on clones and return the final marker points per side. Bare twin
## of the _play_round/_play_one loops WITHOUT logging, forks or _last_state —
## uses _seize_on (never the main loop's _last_state override).
func _fork_playout(pre_state: Dictionary, action: Dictionary, turn: int,
		round_no: int, owners0: Array, objectives: Array,
		frng: RandomNumberGenerator) -> Dictionary:
	var owners := owners0.duplicate()
	var vp := [0, 0]
	var state := BattleSim.resolve_stochastic(pre_state, action, frng)
	var next_turn := 2 if turn == 1 else 1
	var res := _fork_run_activations(state, next_turn, frng)
	state = res["state"]
	var opener: int = (2 if int(res["last"]) == 1 else 1) if int(res["last"]) != 0 else next_turn
	_seize_on(state, objectives, owners)
	BattleSim.vp_round_add(owners, vp)
	for r in range(round_no + 1, ROUNDS + 1):
		state["round"] = r
		for k in state["units"]:
			var su: Dictionary = state["units"][k]
			su["activated"] = false
			su["fatigued"] = false
		res = _fork_run_activations(state, opener, frng)
		state = res["state"]
		if int(res["last"]) != 0:
			opener = 2 if int(res["last"]) == 1 else 1
		_seize_on(state, objectives, owners)
		BattleSim.vp_round_add(owners, vp)
	# CORRECTED: fork labels score like the mission — END for Face-Off.
	var fp1 := 0
	var fp2 := 0
	for o in owners:
		if int(o) == 1:
			fp1 += 1
		elif int(o) == 2:
			fp2 += 1
	return {"p1": fp1, "p2": fp2}


## Bare alternation loop for fork playouts (mirrors _play_round's turn logic).
## Continuations use the CHEAP greedy policy, not the full planner: both
## branches get the SAME continuation brain, so the outcome DELTA stays a
## fair comparison — and the fork overhead drops from ~6x to near-free.
func _fork_run_activations(state: Dictionary, turn: int,
		frng: RandomNumberGenerator) -> Dictionary:
	var last := 0
	var guard: int = (state["units"] as Dictionary).size() * 2 + 4
	while guard > 0:
		guard -= 1
		var pick := _fork_pick(state, turn)
		if pick.is_empty():
			var other := 2 if turn == 1 else 1
			pick = _fork_pick(state, other)
			if pick.is_empty():
				break
			turn = other
		state = BattleSim.resolve_stochastic(state, pick["action"], frng)
		last = turn
		turn = 2 if turn == 1 else 1
	return {"state": state, "last": last}


## Fork-continuation pick: cheap policy step only (see _fork_run_activations).
func _fork_pick(state: Dictionary, player: int) -> Dictionary:
	for k in state["units"]:
		var su: Dictionary = state["units"][k]
		if int(su["player"]) == player and not bool(su["activated"]) and int(su["alive"]) > 0:
			var a := AiPlanner._policy_step(state, player, true)
			return {} if a.is_empty() else {"action": a}
	return {}


func _pick_for(state: Dictionary, player: int) -> Dictionary:
	var pool: Array = []
	for k in state["units"]:
		var su: Dictionary = state["units"][k]
		if int(su["player"]) == player and not bool(su["activated"]) and int(su["alive"]) > 0:
			pool.append(su["unit"])
	if pool.is_empty():
		return {}
	# S2: NML_CORE_ACTOR=policy plays the cheap greedy policy instead of the
	# full planner — volume data generation (states + outcomes) at a fraction
	# of the cost; planner remains the default for quality data. NOT recorded
	# (NML-1073 M3-0): the oracle wrap below only covers the full-planner pick.
	if OS.get_environment("NML_CORE_ACTOR") == "policy":
		var a := AiPlanner._policy_step(state, player, true)
		return {} if a.is_empty() else {"used": true, "action": a}
	# NML-1073 M3-0: the oracle — same begin()/finish() contract
	# SoloController._planner_pick_unit uses (solo_controller.gd:3008-3015), so
	# acts.jsonl replays a core_selfplay pick identically to the arena's.
	# terrain_cb stays invalid here (no TerrainOverlay); _world (SchoolTerrain)
	# is the header's terrain fallback (act_recorder.gd:_school_terrain_line).
	var act_rec := AiActRecorder.begin(state, player, pool, Callable(), _world)
	var _prof_t0 := Time.get_ticks_usec() if BattleSim.profile_enabled() else 0
	var pick := AiPlanner.plan_with_rollout(state, player)
	if BattleSim.profile_enabled():
		BattleSim.profile["plan"] += Time.get_ticks_usec() - _prof_t0
		BattleSim.profile["plan_n"] += 1
	AiActRecorder.finish(act_rec, pick)
	return pick if bool(pick.get("used", false)) else {}


## Round-end marker seize — THE ONE referee (BattleSim.playout_seize), which
## is also the rule the real game runs (SoloController.seize_objectives).
func _seize(state: Dictionary, objectives: Array, owners: Array) -> void:
	_seize_on(_last_state if not _last_state.is_empty() else state, objectives, owners)


## Seize on EXACTLY the given state — the fork playouts (E2-v2) score their
## own cloned worlds; the _last_state override above is main-loop-only.
## NML gap 11: this used to be a SECOND seize with a rule of its own — it
## counted BODIES and gave a contested marker to the MAJORITY, the very rule
## BattleSim dropped on 16.08. Every label this corpus wrote, and every fork
## branch it scored, was judged against a game that does not exist. It is now
## a pass-through; the markers come from the state, so `_objectives` is only
## kept for the call sites (and MUST keep its underscore, project.godot:37).
static func _seize_on(state: Dictionary, _objectives: Array, owners: Array) -> void:
	BattleSim.playout_seize(state, owners)


## GameUnits built through the TABLE's OWN import path — the same two calls
## `tools/arena_match.gd` makes, minus everything that needs a renderer:
##   OPRApiClient.build_army_offline()  (opr_api_client.gd, the network-free half
##     of _parse_tts_api_response) -> Army-Forge base recommendation + Tough base
##     fallback, item grants, typed upgrade gains, selectionId/joinToUnit, the
##     Combined fold;
##   EquipmentDistributor.create_from_opr_unit() (the very call
##     OPRArmyManager._spawn_unit makes) -> unit_properties, per-model Tough,
##     loadout distribution, caster tokens;
##   OPRArmyManager.attach_joined_heroes_of() + .expand_auras_of() -> the two
##     post-spawn passes, hoisted to statics for exactly this.
## NML-1105: this used to be a hand-rolled reduced copy, and the oracle it feeds
## paid for it — 32 mm bases for EVERY unit (no `bases`, no Tough fallback), no
## item grants, no aura expansion, no hero attachment, and rule names guessed out
## of upgrade LABEL text (real lists carry `gains`, never a parsable label, so
## that hack only ever invented rules). Model nodes are bare Node3Ds: no meshes,
## no renderer — only `SeparationChecker.shape_for_model` reads them, and it
## takes the base off `unit_properties`.
func _units_from_list(path: String, player: int) -> Array:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return []
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		return []
	# v1c (v5.1): the registry resolves spell books via faction_folder +
	# game_system — factory lists carry the faction in their FILENAME
	# ({faction}_{points}.json); the table reads it off the army book, which
	# costs a network round trip this harness must not take.
	var faction := path.get_file().get_basename()
	var us := faction.rfind("_")
	if us > 0:
		faction = faction.substr(0, us)
	var client := OPRApiClient.new()
	var army: OPRApiClient.OPRArmy = client.build_army_offline(data as Dictionary)
	client.free()
	if army == null:
		return []
	var out: Array = []
	var by_unit: Dictionary = {}
	var uidx := 0
	for ou: OPRApiClient.OPRUnit in army.units:
		var nodes: Array[Node3D] = []
		for _m in range(maxi(ou.size, 1)):
			var n := Node3D.new()
			root.add_child(n)
			nodes.append(n)
		var gu := EquipmentDistributor.create_from_opr_unit(ou, nodes, player)
		# GameUnit.generate_unit_id() is time+randi: the sidecar roster, every
		# board row and every act line key off this id, so the harness keeps its
		# own DETERMINISTIC one (unchanged shape: "p<player>_<index>_<list id>").
		gu.unit_id = "p%d_%d_%s" % [player, uidx, str(ou.id)]
		uidx += 1
		gu.unit_properties["faction_folder"] = faction
		by_unit[ou] = gu
		out.append(gu)
	# The two passes OPRArmyManager.spawn_army runs after the last unit is built,
	# in that order: a hero must be attached before the aura pass can read him.
	OPRArmyManager.attach_joined_heroes_of(army.units, by_unit)
	OPRArmyManager.expand_auras_of(army.units, by_unit)
	return out


## S3: 12"-deep ZONE deployment — units spread across width AND depth (the
## naive single line doubled charge-exposure density vs engine positions).
func _deploy_zone(units: Array, z0_in: float, depth_in: float, rng: RandomNumberGenerator) -> void:
	var n := units.size()
	for i in range(n):
		var gu: GameUnit = units[i]
		var x0 := (-TABLE_W_IN / 2.0 + 8.0) + (TABLE_W_IN - 16.0) * (float(i) + 0.5) / float(n)
		# Plain random spot in the zone slot: measured per-round engine profile
		# (round-1 cover 0.31 of ~4.4 units) matches the islands' natural overlap
		# with the zone — active cover-seeking overshot it 5x.
		var best_x := x0 + rng.randf_range(-3.0, 3.0)
		var best_z := z0_in + rng.randf_range(1.0, depth_in - 3.0)
		for m in range(gu.models.size()):
			(gu.models[m] as ModelInstance).node.global_position = Vector3(
				(best_x + float(m % 5)) * IN2M, 0.0, (best_z + float(m / 5)) * IN2M)


func _capture(all_units: Array, objectives: Array, world: Dictionary) -> Dictionary:
	var army := OPRArmyManager.new()
	root.add_child(army)
	var gu := {}
	for u in all_units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	army.current_round = 1
	var objs := objectives.duplicate()
	var terrain_at := func(pos: Vector3) -> int: return SchoolTerrain.type_at(world, pos)
	var cover_of := func(u: GameUnit) -> bool:
		var c := Vector3.ZERO
		var alive := 0
		for m in u.models:
			var mi := m as ModelInstance
			if mi != null and mi.is_alive and mi.node != null:
				c += mi.node.global_position
				alive += 1
		if alive == 0:
			return false
		return TerrainRules.gives_cover(SchoolTerrain.type_at(world, c / alive))
	# Dynamic LOS from the real layout: ruins/containers/woods block sight
	# THROUGH them; endpoint cells are exempt (inside sees out, is seen).
	var los_blocked := func(a: Vector3, b: Vector3) -> bool:
		return SchoolTerrain.los_blocked(world, a, b)
	var st := BattleSim.capture(army, func() -> Array: return objs,
		func(_i: int) -> int: return 0, 1, ROUNDS, cover_of, Callable(), terrain_at)
	st["los_blocked"] = los_blocked
	return st


func _write_result(game_seed: int, owners: Array, positions_log: Array,
		vp: Array = [], profile_summary: Dictionary = {}) -> void:
	var p1 := 0
	var p2 := 0
	for o in owners:
		if int(o) == 1:
			p1 += 1
		elif int(o) == 2:
			p2 += 1
	# NML-1008: the WINNER is decided by cumulative VPs (book rule); the
	# final marker counts stay logged for reference.
	var vp1: int = int(vp[0]) if vp.size() == 2 else p1
	var vp2: int = int(vp[1]) if vp.size() == 2 else p2
	# CORRECTED (record check 15.08.): Face-Off (our duel) is END-scored
	# (book + grill D4 12.08.); vp stays logged for the progressive wave.
	var winner := "draw"
	if p1 != p2:
		winner = "p1" if p1 > p2 else "p2"
	# NML-1046 M1: v1c -> v1d — caster-era rows (units now carry granted spell
	# tokens) must stay distinguishable from pre-fix corpus rows.
	var result := {"schema": 1, "board_schema": 5, "rule_vocab": "v1d",
		"school_world": 2, "terrain": _world.get("pieces", []),
		"unknown_rules": BattleSim.unknown_rules.keys(),
		"tool": "core_selfplay", "seed": game_seed,
		"dice_seed": game_seed, "grades": {"p1": "planner_core", "p2": "planner_core"},
		"mission": {"family": "face_off", "name": "duel", "rounds": ROUNDS,
			"deployment": "zone12", "symmetric": true,
			"objective_count": owners.size(), "packs": []},
		"armies": {"p1": _army1, "p2": _army2}, "opener": 0,
		"objectives": {"p1": p1, "p2": p2, "neutral": owners.size() - p1 - p2},
		"vp": {"p1": vp1, "p2": vp2}, "scoring": "end",
		"winner": winner, "planner_positions": positions_log, "planner_calib": [],
		"roster": _roster_names(),
		# NML-1046 M2a: per-game cast counter — without it a probe has no way to
		# measure whether spells are actually firing (NML-1069 adds the per-kind
		# split, so "only ever damage" is a different reading from "never casts").
		"magic": _magic}
	if not profile_summary.is_empty():   # NML-1072: env-gated (NML_PROFILE=1) only
		result["profile"] = profile_summary
	# NML-1140 step 8: the rung rides the result only when it actually shaped the
	# RULEBOOK layout (a preset-derived search on a constants game placed nothing).
	if OS.get_environment("NML_OBJECTIVES").strip_edges().to_lower() == "rulebook" \
			and (_doctrine_mode == "style" or _doctrine_mode == "search"):
		result["objectives_doctrine"] = _doctrine_mode
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
		var f := FileAccess.open(_out.path_join("core_s%d.json" % game_seed), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(result))
			f.close()
	printerr("[CORE] RESULT seed=%d P1=%d P2=%d -> %s" % [game_seed, p1, p2, winner])


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"army1": _army1 = kv[1]
			"army2": _army2 = kv[1]
			"seed": _seed = int(kv[1])
			"games": _games = int(kv[1])
			"out": _out = kv[1]
