extends SceneTree
## NML-1073 M1-4 — the GDScript half of gate KERN-P.
##
## Times ONE ROLLOUT NODE exactly as AiPlanner._policy_step (ai_planner.gd:462-467)
## pays for it, on the SAME recorded nodes the Rust bench replays:
##
##     next := BattleSim.resolve(state, action)              # clone_state is INSIDE resolve
##     s    := AiMissionEval.score(next, player, BattleSim.reply_threat(next, player))  # rich leaf
##     s    := AiMissionEval.score(next, player)                                        # cheap leaf
##
## States are rebuilt from the plain JSON the way tools/node_recheck.gd does it
## (stand-in GameUnits from the header's profile table, no live unit is touched),
## with ONE addition the benchmark needs: each unit gets its recorded `los` row,
## so `sees()` gives the same answer the Rust port reads off `los_pairs`. Without
## it a rebuilt state has NO sight gate at all and reply_threat prices ~8x more
## volleys than the recorded game did — the two sides would not be doing the same
## work and the factor would be fiction.
##
## Like the Rust bench, this side has no `terrain_at`/`los_blocked` Callable: the
## recorded answers stand in for both. Neither side pays the terrain probe the
## real trainer pays.
##
## Usage: godot --headless -s res://tools/node_bench.gd -- \
##            dir=<NML_NODE_DUMP dir> [n=2000] [passes=3] [out=<file>] [excl=<file>]
## NML_SIM_SPACING / NML_SIM_CAST must match the corpus header's seams.

const EPS := 1e-6

func _init() -> void:
	var dir := ""
	var n := 2000
	var passes := 3
	var out_path := ""
	var excl_path := ""
	var skip_path := ""
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"dir": dir = kv[1]
			"n": n = int(kv[1])
			"passes": passes = int(kv[1])
			"out": out_path = kv[1]
			"excl": excl_path = kv[1]
			"skip": skip_path = kv[1]
	# Nodes dropped on BOTH sides before anything is timed (1-based corpus line
	# numbers, one per line) — the C6 set, so the two medians stay over the SAME
	# node set when the cast-LOS asymmetry is measured out.
	var skip := {}
	if skip_path != "":
		var sf := FileAccess.open(skip_path, FileAccess.READ)
		if sf == null:
			printerr("[BENCH] cannot open skip file ", skip_path)
			quit(1)
			return
		while not sf.eof_reached():
			var t := sf.get_line().strip_edges()
			if t != "":
				skip[int(t)] = true
		sf.close()
	var f := FileAccess.open(dir.path_join("nodes.jsonl"), FileAccess.READ)
	if f == null:
		printerr("[BENCH] cannot open ", dir.path_join("nodes.jsonl"))
		quit(1)
		return
	var header: Dictionary = JSON.parse_string(f.get_line())
	var profiles: Dictionary = header["profiles"]
	var seams: Dictionary = header.get("seams", {})
	var units_cache := {}
	for uid in profiles:
		units_cache[uid] = _stand_in_unit(profiles[uid])

	# ---- load + rebuild every node ONCE (outside the timed region) ----
	var states: Array = []
	var actions: Array = []
	var players: PackedInt32Array = PackedInt32Array()
	var riches: Array = []
	var recorded: PackedFloat64Array = PackedFloat64Array()
	var node_ids: PackedInt32Array = PackedInt32Array()
	var excluded: PackedInt32Array = PackedInt32Array()
	var line_no := 0
	while line_no < n and not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var rec: Variant = JSON.parse_string(line)
		if not (rec is Dictionary):
			continue
		line_no += 1
		var action: Dictionary = _rebuild_action((rec as Dictionary)["action"])
		var sb: Dictionary = (rec as Dictionary)["state_before"]
		var kind := int(action.get("kind", -1))
		if kind < 0 or kind > 3 or not (sb["units"] as Dictionary).has(str(action["unit"])) \
				or skip.has(line_no):
			excluded.append(line_no)   # no resolve branch for it, or the skip file names it
			continue
		states.append(_rebuild_state(sb, units_cache))
		actions.append(action)
		players.append(int((rec as Dictionary)["player"]))
		riches.append(bool((rec as Dictionary).get("rich", false)))
		recorded.append(float((rec as Dictionary)["score"]))
		node_ids.append(line_no)
	f.close()
	var m := states.size()
	if m == 0:
		printerr("[BENCH] no nodes")
		quit(1)
		return

	# ---- warm-up (JIT-free engine, but caches/registries are cold on node 1) ----
	for i in range(m):
		var w := BattleSim.resolve(states[i], actions[i])
		if riches[i]:
			AiMissionEval.score(w, players[i], BattleSim.reply_threat(w, players[i]))
		else:
			AiMissionEval.score(w, players[i])

	# ---- diagnostics: does the rebuilt node still price like the recording? ----
	var agree := 0
	var max_diff := 0.0
	var threat_pairs := 0
	var cast_nodes := 0
	var cast_ids: PackedInt32Array = PackedInt32Array()
	for i in range(m):
		var nx := BattleSim.resolve(states[i], actions[i])
		# Firing signal = the TOKEN SPEND (battle_sim.gd:893), because the Rust
		# port keeps no cast_events and both sides must count the same thing.
		var _uk := str(actions[i]["unit"])
		if int((nx["units"][_uk] as Dictionary).get("casts", 0)) \
				!= int((states[i]["units"][_uk] as Dictionary).get("casts", 0)):
			cast_nodes += 1
			cast_ids.append(node_ids[i])
		var s := 0.0
		if riches[i]:
			var inc := BattleSim.reply_threat(nx, players[i])
			s = AiMissionEval.score(nx, players[i], inc)
			threat_pairs += _count_threat_pairs(nx, players[i])
		else:
			s = AiMissionEval.score(nx, players[i])
		var d := absf(s - recorded[i])
		max_diff = maxf(max_diff, d)
		if d <= EPS:
			agree += 1

	# ---- the whole-node passes ----
	var best_mean := INF
	var best: PackedFloat64Array = PackedFloat64Array()
	var pass_means: Array = []
	var sink := 0.0
	for p in range(passes):
		var per: PackedFloat64Array = PackedFloat64Array()
		per.resize(m)
		var t_pass := Time.get_ticks_usec()
		for i in range(m):
			var t0 := Time.get_ticks_usec()
			var nx := BattleSim.resolve(states[i], actions[i])
			var s := AiMissionEval.score(nx, players[i], BattleSim.reply_threat(nx, players[i])) \
				if riches[i] else AiMissionEval.score(nx, players[i])
			var dt := Time.get_ticks_usec() - t0
			sink += s
			per[i] = float(dt)
		var wall := float(Time.get_ticks_usec() - t_pass)
		pass_means.append(wall / float(m))
		var inst := 0.0
		for v in per:
			inst += v
		inst /= float(m)
		if inst < best_mean:
			best_mean = inst
			best = per
	var sorted: Array = Array(best)
	sorted.sort()

	# ---- breakdown: clone / resolve / reply_threat / score ----
	var t_clone := INF
	var t_resolve := INF
	var t_threat := INF
	var t_score := INF
	var nexts: Array = []
	var incs: Array = []
	for i in range(m):
		var nx := BattleSim.resolve(states[i], actions[i])
		nexts.append(nx)
		incs.append(BattleSim.reply_threat(nx, players[i]) if riches[i] else {})
	for p in range(passes):
		var t0 := Time.get_ticks_usec()
		for i in range(m):
			sink += float(BattleSim.clone_state(states[i]).size())
		t_clone = minf(t_clone, float(Time.get_ticks_usec() - t0) / float(m))
		t0 = Time.get_ticks_usec()
		for i in range(m):
			sink += float(BattleSim.resolve(states[i], actions[i]).size())
		t_resolve = minf(t_resolve, float(Time.get_ticks_usec() - t0) / float(m))
		t0 = Time.get_ticks_usec()
		for i in range(m):
			if riches[i]:
				sink += float(BattleSim.reply_threat(nexts[i], players[i]).size())
		t_threat = minf(t_threat, float(Time.get_ticks_usec() - t0) / float(m))
		t0 = Time.get_ticks_usec()
		for i in range(m):
			sink += AiMissionEval.score(nexts[i], players[i], incs[i])
		t_score = minf(t_score, float(Time.get_ticks_usec() - t0) / float(m))

	# ---- diagnostic: what does re-deriving STATIC profile data cost? ----
	# `AiMissionEval._presence` (:610) asks `SoloController.sim_move_bands(unit)`
	# once per unit PER OBJECTIVE, and `resolve` (:574) once more; the Rust port
	# reads the same numbers out of the capture-time profile table. This is the
	# single largest structural difference between the two sides, so it is
	# measured rather than argued about.
	var t_bands := INF
	var bands_calls := 0
	for i in range(m):
		var st: Dictionary = nexts[i]
		var nobj: int = (st["objectives"] as Array).size()
		for k in st["units"]:
			var su: Dictionary = st["units"][k]
			if int(su["alive"]) <= 0 or bool(su.get("aircraft", false)):
				continue
			bands_calls += nobj
		bands_calls += 1   # the one resolve() makes
	for p in range(passes):
		var t0 := Time.get_ticks_usec()
		for i in range(m):
			var st: Dictionary = nexts[i]
			var nobj: int = (st["objectives"] as Array).size()
			for k in st["units"]:
				var su: Dictionary = st["units"][k]
				if int(su["alive"]) <= 0 or bool(su.get("aircraft", false)):
					continue
				for _o in range(nobj):
					sink += float(SoloController.sim_move_bands(su["unit"]).size())
			sink += float(SoloController.sim_move_bands((states[i]["units"] as Dictionary).values()[0]["unit"]).size())
		t_bands = minf(t_bands, float(Time.get_ticks_usec() - t0) / float(m))

	var n_rich := 0
	for r in riches:
		if r:
			n_rich += 1
	print("[BENCH] corpus=%s seams=%s" % [dir, str(seams)])
	print("[BENCH] env NML_SIM_SPACING=%s NML_SIM_CAST=%s -> spacing_enabled=%s cast_phase_enabled=%s" \
		% [OS.get_environment("NML_SIM_SPACING"), OS.get_environment("NML_SIM_CAST"),
			str(BattleSim.spacing_enabled()), str(BattleSim.cast_phase_enabled())])
	print("[BENCH] skip_file=%s (%d ids)" % [skip_path, skip.size()])
	print("[BENCH] nodes_read=%d measured=%d excluded=%d rich=%d" % [line_no, m, excluded.size(), n_rich])
	print("[BENCH] score agreement with the recording: %d/%d within 1e-6, max diff %.9f" \
		% [agree, m, max_diff])
	print("[BENCH] cast sub-phase fired on %d/%d nodes" % [cast_nodes, m])
	print("[BENCH] LOS-gate check   reply_threat volley pairs that pass sees()+los_clear: %d" % threat_pairs)
	for i in range(pass_means.size()):
		print("[BENCH]   pass %d mean %.0f us/node (wall/n)" % [i + 1, pass_means[i]])
	print("[BENCH] BEST PASS mean   %.1f us/node" % best_mean)
	print("[BENCH] BEST PASS MEDIAN %.1f us/node" % _median(sorted))
	print("[BENCH] BEST PASS p90    %.1f us/node" % _pct(sorted, 0.90))
	print("[BENCH] BEST PASS p99    %.1f us/node" % _pct(sorted, 0.99))
	print("[BENCH] BEST PASS max    %.1f us/node" % float(sorted[sorted.size() - 1]))
	print("[BENCH] BEST PASS min    %.1f us/node" % float(sorted[0]))
	print("[BENCH] breakdown us/node (best of %d passes): clone=%.1f resolve_incl_clone=%.1f reply_threat=%.1f score=%.1f sum=%.1f" \
		% [passes, t_clone, t_resolve, t_threat, t_score, t_resolve + t_threat + t_score])
	print("[BENCH] of which SoloController.sim_move_bands (static data the Rust port reads from a table): %.1f us/node over %.1f calls/node" \
		% [t_bands, float(bands_calls) / float(m)])
	if excl_path != "":
		var ef := FileAccess.open(excl_path, FileAccess.WRITE)
		if ef != null:
			for i in excluded:
				ef.store_line(str(i))
			ef.close()
	if out_path != "":
		var of := FileAccess.open(out_path, FileAccess.WRITE)
		if of != null:
			of.store_line("nodes_measured %d" % m)
			of.store_line("excluded %d" % excluded.size())
			of.store_line("rich %d" % n_rich)
			of.store_line("mean_us %.4f" % best_mean)
			of.store_line("median_us %.4f" % _median(sorted))
			of.store_line("p90_us %.4f" % _pct(sorted, 0.90))
			of.store_line("p99_us %.4f" % _pct(sorted, 0.99))
			of.store_line("max_us %.4f" % float(sorted[sorted.size() - 1]))
			of.store_line("clone_us %.4f" % t_clone)
			of.store_line("resolve_us %.4f" % t_resolve)
			of.store_line("threat_us %.4f" % t_threat)
			of.store_line("score_us %.4f" % t_score)
			of.store_line("score_agree %d" % agree)
			of.store_line("threat_pairs %d" % threat_pairs)
			of.store_line("cast_nodes %d" % cast_nodes)
			of.store_line("sim_move_bands_us %.4f" % t_bands)
			of.store_line("sim_move_bands_calls_per_node %.2f" % (float(bands_calls) / float(m)))
			of.close()
		var cf := FileAccess.open(out_path + ".castids", FileAccess.WRITE)
		if cf != null:
			for i in cast_ids:
				cf.store_line(str(i))
			cf.close()
	if sink == INF:
		quit(3)
		return
	quit(0)


static func _median(sorted: Array) -> float:
	var n := sorted.size()
	if n == 0:
		return 0.0
	if n % 2 == 1:
		return float(sorted[n / 2])
	return 0.5 * (float(sorted[n / 2 - 1]) + float(sorted[n / 2]))


static func _pct(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return float(sorted[int(round((sorted.size() - 1) * p))])


## The pair count the Rust bench prints as well — if the two differ, the two
## sides are not resolving the same volleys and no factor between them is real.
static func _count_threat_pairs(state: Dictionary, player: int) -> int:
	var c := 0
	for ek in state["units"]:
		var eu: Dictionary = state["units"][ek]
		if int(eu["player"]) == player or int(eu["alive"]) <= 0:
			continue
		for mk in state["units"]:
			var mu: Dictionary = state["units"][mk]
			if int(mu["player"]) != player or int(mu["alive"]) <= 0:
				continue
			if BattleSim.sees(eu, str(mk)) and BattleSim._los_clear(state, eu, mu):
				c += 1
	return c


## Same rebuild as tools/node_recheck.gd:_rebuild_state, plus the recorded `los`
## row per unit and a SHARED stand-in GameUnit per profile (the live trainer
## shares one GameUnit across every rollout node too — building 13 fresh ones
## per node would be harness cost, not node cost).
static func _rebuild_state(plain: Dictionary, units_cache: Dictionary) -> Dictionary:
	var state := {"round": int(plain["round"]), "rounds_total": int(plain["rounds_total"]),
		"scoring": str(plain["scoring"])}
	for k in ["vp", "vp_flavour", "vp_memo", "markers_meta", "destroy_seq"]:
		if plain.has(k):
			state[k] = plain[k]
	var objectives: Array = []
	for o in (plain.get("objectives", []) as Array):
		objectives.append({"pos": _vec3((o as Dictionary)["pos"]), "owner": (o as Dictionary)["owner"]})
	state["objectives"] = objectives
	var units := {}
	var plain_units: Dictionary = plain["units"]
	var keys: Array = plain_units.keys()
	var los_pairs: Array = plain.get("los_pairs", [])
	for i in range(keys.size()):
		var uid: String = str(keys[i])
		var su: Dictionary = (plain_units[uid] as Dictionary).duplicate(true)
		su["unit"] = units_cache[uid]
		su["positions"] = _vec3s(su.get("positions", []))
		# The recorded `_los_clear` answers, moved onto the `sees()` gate: the
		# rebuilt state carries no `los_blocked` Callable, so without this the
		# sight gate would be wide open and every volley would be priced.
		if i < los_pairs.size():
			var row := str(los_pairs[i])
			var m := {}
			for j in range(keys.size()):
				if j != i and j < row.length():
					m[str(keys[j])] = row[j] == "1"
			su["los"] = m
		units[uid] = su
	state["units"] = units
	return state


static func _rebuild_action(a: Dictionary) -> Dictionary:
	var out := a.duplicate()
	if out.has("dest"):
		out["dest"] = _vec3(out["dest"])
	return out


static func _stand_in_unit(p: Dictionary) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = str(p.get("unit_id", ""))
	u.unit_properties = {"name": p.get("name", ""), "quality": int(p.get("quality", 0)),
		"defense": int(p.get("defense", 0)), "special_rules": p.get("special_rules", []),
		"game_system": str(p.get("game_system", "")), "faction_folder": str(p.get("faction_folder", "")),
		"size": int(p.get("model_count", 0))}
	for wm in (p.get("wounds_max", []) as Array):
		var mi := ModelInstance.new()
		mi.wounds_max = int(wm)
		u.models.append(mi)
	var weapons: Array = p.get("weapons", [])
	if not weapons.is_empty():
		u.source_type = "opr"
		var ou := OPRApiClient.OPRUnit.new()
		for w in weapons:
			var ow := OPRApiClient.OPRWeapon.new()
			ow.name = str((w as Dictionary).get("name", ""))
			ow.range_value = int((w as Dictionary).get("range", 0))
			ow.attacks = int((w as Dictionary).get("attacks", 0))
			ow.count = int((w as Dictionary).get("count", 1))
			for r in ((w as Dictionary).get("rules", []) as Array):
				ow.special_rules.append(str(r))
			ou.weapons.append(ow)
		u.source_data = ou
	return u


static func _vec3(v: Array) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


static func _vec3s(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(_vec3(v))
	return out
