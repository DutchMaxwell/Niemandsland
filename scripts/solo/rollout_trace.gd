class_name AiRolloutTrace
extends RefCounted
## NML-1114 (latent planner nondeterminism): env NML_ROLLOUT_TRACE=<path> appends
## ONE JSON line per planner unit pick — the inputs and per-unit intermediates the
## logged feature vector is built from, so a future divergence like the 28.08. Gate C
## one (record 16: presence_theirs 25.75 vs 17.6875, tail_theirs 5 vs 1, everything
## else identical) can be EXPLAINED from the artefact instead of resampled.
## The two features that differed are the only ones that fold per-unit geometry
## (control_gap_in per marker) with the unit's rush band, so the line carries exactly
## that fold per unit plus the statics/caches consulted.
##
## Unset (default) = the first (cached) env check returns null and write() no-ops:
## no allocation, no disk, byte-identical decisions.json either way. Same style as
## AiActRecorder/MoveRecorder (stream opened once, kept open, JSON lines with
## sort_keys, cap via NML_ROLLOUT_TRACE_MAX). Closed by AiPlanner.close().


static var _stream: FileAccess = null
static var _checked := false
static var _max := 20000
static var _count := 0


static func _out() -> FileAccess:
	if not _checked:
		_checked = true
		var path := OS.get_environment("NML_ROLLOUT_TRACE")
		if path != "":
			_stream = FileAccess.open(path, FileAccess.WRITE)
			var cap := OS.get_environment("NML_ROLLOUT_TRACE_MAX")
			if cap != "":
				_max = maxi(int(cap), 0)
	return _stream


## True once NML_ROLLOUT_TRACE names an openable file (same cached check write() uses).
static func active() -> bool:
	return _out() != null


## ONE line for ONE planner pick. `state` is the LIVE captured board the pick was
## made on (reserves already stamped), `features` the vector the decision record
## carries — written verbatim so a reader never has to trust a second computation.
static func write(state: Dictionary, player: int, pick_key: String, pick_name: String,
		features: Dictionary) -> void:
	var f := _out()
	if f == null or _count >= _max:
		return
	var line := {"kind": "pick", "seq": _count, "round": int(state["round"]),
		"rounds_total": int(state["rounds_total"]), "player": player,
		"pick_key": pick_key, "pick_unit": pick_name,
		"objectives": _objectives(state), "units": _units(state, player),
		"statics": _statics(state), "env": _env(),
		"playout_sig": AiPlanner._playout_sig(state, player) if AiPlanner.playout_search else 0,
		"features": features}
	f.store_line(JSON.stringify(line, "", true, true))
	f.flush()   # a same-process reader (the unit test) must see the line without a close()
	_count += 1


## Marker ring the presence/tail fold measures against.
static func _objectives(state: Dictionary) -> Array:
	var out: Array = []
	for o in state["objectives"]:
		var od := o as Dictionary
		var p: Vector3 = od["pos"] as Vector3
		out.append({"x": snappedf(p.x, 0.00001), "z": snappedf(p.z, 0.00001),
			"owner": int(od.get("owner", 0))})
	return out


## Per ALIVE unit: every input AiMissionEval.features folds into presence_*/tail_*
## — the rush band (a cache/props read), the eligibility verdict, the per-marker
## base-edge gap, and the rounded model positions those gaps come from.
static func _units(state: Dictionary, player: int) -> Array:
	var out: Array = []
	var round_no := int(state["round"])
	for key in state["units"]:
		var su: Dictionary = state["units"][key]
		if int(su["alive"]) <= 0:
			continue
		var gaps: Array = []
		for o in state["objectives"]:
			gaps.append(snappedf(BattleSim.control_gap_in(su, (o as Dictionary)["pos"] as Vector3), 0.0001))
		var wounds := 0.0
		for w in su["wounds"]:
			wounds += float(w)
		var pos: Array = []
		for p in su["positions"]:
			pos.append([snappedf((p as Vector3).x, 0.00001), snappedf((p as Vector3).z, 0.00001)])
		var radii: Array = []
		for r in su.get("radii", []):
			radii.append(snappedf(float(r), 0.00001))
		out.append({"key": str(key), "name": (su["unit"] as GameUnit).get_name(),
			"mine": int(su["player"]) == player, "player": int(su["player"]),
			"alive": int(su["alive"]), "wounds": wounds,
			"activated": bool(su.get("activated", false)), "shaken": bool(su.get("shaken", false)),
			"fatigued": bool(su.get("fatigued", false)), "in_cover": bool(su.get("in_cover", false)),
			"aircraft": bool(su.get("aircraft", false)),
			"ambush_round": int(su.get("ambush_arrived_round", -1)),
			"eligible": BattleSim.can_hold_marker(su, round_no),
			"rush_in": float(SoloController.sim_move_bands(su["unit"]).get("rush", 12)),
			"gaps_in": gaps, "pos_xz": pos, "radii_m": radii})
	return out


## The class statics and cached seams this pick read — the NML-1093 fast_planner
## pair, the per-seat search knobs, and whether the capture carried its live gates.
static func _statics(state: Dictionary) -> Dictionary:
	return {"fast_planner": MovementPlanner.fast_planner,
		"fast_planner_guard": MovementPlanner.fast_planner_guard,
		"opener_seat": AiPlanner.opener_seat, "playout_search": AiPlanner.playout_search,
		"playout_net": (AiPlanner.playout_net as Dictionary).size(),
		"fit_mode": AiMissionEval.fit_mode, "hero_fold": BattleSim.hero_fold_enabled(),
		"spacing": BattleSim.spacing_enabled(), "core": BattleSim.core_enabled(),
		"top_k": AiPlanner.top_k_default(), "horizon": AiPlanner.horizon(),
		"terrain_at": (state.get("terrain_at", Callable()) as Callable).is_valid(),
		"charge_gate": (state.get("charge_illegal", Callable()) as Callable).is_valid(),
		"los_at": (state.get("los_at", Callable()) as Callable).is_valid(),
		"scoring": str(state.get("scoring", ""))}


## Warm/cold indicator (#418 flavour) — how far the engine had stepped when this
## pick was taken. NOT reproducible across runs by design: a differ ignores "env".
static func _env() -> Dictionary:
	return {"physics_frames": Engine.get_physics_frames(),
		"process_frames": Engine.get_process_frames(), "ms": Time.get_ticks_msec()}


## Closes the stream where the writer stands (game/tool/test end, via AiPlanner.close())
## and resets every cached static so a later write() reopens a fresh file.
static func close() -> void:
	if _stream != null:
		_stream.flush()
		_stream.close()
	_stream = null
	_checked = false
	_count = 0
	_max = 20000
