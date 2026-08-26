extends SceneTree
## NML-1073 M2-0c — the ACTIVATION corpus's completeness proof (the M1-0
## node_recheck.gd sibling, one level up): rebuilds every input
## AiPlanner.plan_with_rollout reads using ONLY the recorded acts.jsonl (state,
## charge_illegal matrix, terrain cells/sandbox, statics, knobs), calls the
## REAL search, and diffs the pick + search trace against what was recorded.
## Any mismatch means some live read the search makes is missing from the
## corpus. Reuses tools/node_recheck.gd's state-rebuild statics (preloaded,
## called directly — both were already static, no edit needed there) instead
## of re-deriving state["units"]/stand-in GameUnits a second time.
##
## Usage: godot --headless -s res://tools/act_recheck.gd --
##   file=<acts.jsonl> [n=25] [offset=0]
##   --corrupt=charge   RED proof: flip every recorded charge_illegal answer
##   --ignore-knobs     RED proof (only bites on a non-default-knobs corpus):
##                       never stamp the header's knobs

const NodeRecheck := preload("res://tools/node_recheck.gd")
const EPS := 1e-9

var _corrupt_charge := false
var _ignore_knobs := false


func _init() -> void:
	var file_path := ""
	var n := 25
	var offset := 0
	for a in OS.get_cmdline_user_args():
		if a == "--corrupt=charge":
			_corrupt_charge = true
			continue
		if a == "--ignore-knobs":
			_ignore_knobs = true
			continue
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"file": file_path = kv[1]
			"n": n = int(kv[1])
			"offset": offset = int(kv[1])
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		printerr("[ACT_RECHECK] cannot open ", file_path)
		quit(1)
		return
	var header: Dictionary = JSON.parse_string(f.get_line())
	var profiles: Dictionary = header["profiles"]
	var terrain: Variant = header.get("terrain")
	var knobs: Dictionary = header.get("knobs", {})
	AiPlanner.trace_enabled = true   # M2-0c seam: fill trace without the NML_ACT_DUMP file

	var skipped := 0
	while skipped < offset and not f.eof_reached():
		if f.get_line().strip_edges() != "":
			skipped += 1

	var checked := 0
	var ok := 0
	var mismatch := 0
	while checked < n and not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var act: Dictionary = JSON.parse_string(line)
		checked += 1
		var t0 := Time.get_ticks_msec()
		var mism := _check_act(act, profiles, terrain, knobs)
		var dt := Time.get_ticks_msec() - t0
		var tag := "ACT %d round=%d player=%d" % [offset + checked, int(act["round"]), int(act["player"])]
		if mism.is_empty():
			ok += 1
			print("%s OK (%dms)" % [tag, dt])
		else:
			mismatch += 1
			print("%s MISMATCH (%dms)" % [tag, dt])
			for m in mism.slice(0, 3):
				print("  MISMATCH %s: recorded=%s got=%s" % [str(m["field"]), str(m["recorded"]), str(m["got"])])
	print("RECHECK acts=%d ok=%d mismatch=%d" % [checked, ok, mismatch])
	quit(0 if mismatch == 0 else 1)


## One activation: rebuild -> stamp -> plan_with_rollout -> diff. Returns the
## list of mismatches (empty = exact replay).
func _check_act(act: Dictionary, profiles: Dictionary, terrain: Variant, knobs: Dictionary) -> Array:
	var state: Dictionary = NodeRecheck._rebuild_state(act["state"], profiles)
	var key_of := {}   # GameUnit instance id -> the corpus's string unit key
	for k in state["units"]:
		key_of[(state["units"][k]["unit"] as GameUnit).get_instance_id()] = str(k)

	var matrix: Dictionary = (act.get("charge_illegal", {}) as Dictionary).duplicate()
	if _corrupt_charge:
		for mk in matrix.keys():
			matrix[mk] = not bool(matrix[mk])
	var ci_gap := [false]
	state["charge_illegal"] = func(atk: GameUnit, vic: GameUnit, _gap: float,
			_ca: Vector3, _cb: Vector3) -> bool:
		var mkey := "%s|%s" % [str(key_of.get(atk.get_instance_id(), "?")),
			str(key_of.get(vic.get_instance_id(), "?"))]
		if not matrix.has(mkey):
			push_error("[ACT_RECHECK] charge_illegal: no recorded answer for " + mkey)
			ci_gap[0] = true
			return false
		return bool(matrix[mkey])

	if terrain != null:
		state["terrain_at"] = _terrain_at_callable(terrain as Dictionary)
	# READ FIRST finding: solo_controller.gd never stamps state["los_blocked"] (grep
	# confirms it), so it is left UNSET here too — _los_clear (battle_sim.gd:684-688)
	# reads it every reply_threat call and short-circuits to "clear" on an invalid
	# Callable. Binding a stub here (tried first) changed nothing about the VALUE
	# (the stub also had to return the same "clear" answer) but made is_valid() true,
	# so it actually got called on every _los_clear probe — real signal, wrong fix.

	var statics: Dictionary = act.get("statics", {})
	var playout_net: Dictionary = statics.get("playout_net", {})
	var los_hit := [false]
	if playout_net.is_empty():
		# _policy_step_net (the only los_at caller) never runs with an empty net —
		# a call here proves the corpus does NOT cover what actually ran.
		state["los_at"] = func(_a, _b) -> bool:
			push_error("[ACT_RECHECK] los_at called with no net path active")
			los_hit[0] = true
			return false
	else:
		state["los_at"] = _los_at_from_recorded(state)

	AiPlanner.opener_seat = bool(statics.get("opener_seat", false))
	AiPlanner.playout_search = bool(statics.get("playout_search", false))
	AiMissionEval.fit_mode = bool(statics.get("fit_mode", false))
	AiPlanner.playout_net = playout_net
	if not _ignore_knobs:
		_stamp_knobs(knobs)

	var pick := AiPlanner.plan_with_rollout(state, int(act["player"]))
	var trace := AiPlanner.trace

	var mism: Array = []
	_compare_pick(act.get("pick", {}), pick, mism)
	_compare_trace(act.get("trace", {}), trace, mism)
	if ci_gap[0]:
		mism.append({"field": "charge_illegal.unknown_pair", "recorded": "every queried pair", "got": "gap"})
	if los_hit[0]:
		mism.append({"field": "los_at.called", "recorded": "net path inactive", "got": "called"})
	return mism


## Port of terrain_overlay.gd get_terrain_at_world_position + world_to_cell
## (scripts/terrain_overlay.gd:1090-1116) over the recorded cells/sandbox/
## cell_params — no live TerrainOverlay node.
func _terrain_at_callable(terrain: Dictionary) -> Callable:
	var cells := {}
	for c in (terrain["cells"] as Array):
		cells[Vector2i(int(c[0]), int(c[1]))] = int(c[2])
	var sandbox: Array = terrain["sandbox"]
	var cp: Dictionary = terrain["cell_params"]
	var tsize: Array = cp["table_size_feet"]
	var width_in := float(tsize[0]) * 12.0
	var height_in := float(tsize[1]) * 12.0
	var grid_in := float(cp["grid_size_inches"])
	var cell_m := grid_in * float(cp["inches_to_meters"])
	var rot_rad := deg_to_rad(float(cp["grid_rotation_degrees"]))
	var grid_size := int(ceil(sqrt(width_in * width_in + height_in * height_in) / grid_in))
	if grid_size % 2 != 0:
		grid_size += 1
	return func(world_pos: Vector3) -> int:
		var rx := world_pos.x * cos(-rot_rad) - world_pos.z * sin(-rot_rad)
		var rz := world_pos.x * sin(-rot_rad) + world_pos.z * cos(-rot_rad)
		var cell := Vector2i(int(floor(rx / cell_m + grid_size / 2.0)), int(floor(rz / cell_m + grid_size / 2.0)))
		var t := int(cells.get(cell, 0))
		if t != 0:
			return t
		var p := Vector2(world_pos.x, world_pos.z)
		for s in sandbox:
			var sd: Dictionary = s
			var c: Array = sd["c"]
			var he: Array = sd["he"]
			if TerrainRules.point_in_obb(p, Vector2(c[0], c[1]), Vector2(he[0], he[1]), float(sd["yaw"])):
				return int(sd["type"])
		return 0


## Only reached when statics.playout_net is non-empty (none of the sample
## corpus's 25 acts are) — AiClone.menu_tuples calls los_at.call(dest, foe_pos)
## with arbitrary ROLLOUT-imagined Vector3 points, but the corpus only records
## per-UNIT los at the ROOT state's own positions (su["los"]). Best-effort:
## nearest-centre match, exact only at the two units' own root centres — a
## genuine, documented corpus gap for the net-guided path, not a silent patch.
func _los_at_from_recorded(state: Dictionary) -> Callable:
	var centres := {}
	for k in state["units"]:
		centres[str(k)] = AiPlanner._centre(state["units"][k])
	return func(pa: Vector3, pb: Vector3) -> bool:
		var best_a := ""
		var best_b := ""
		var da := INF
		var db := INF
		for k in centres:
			var c: Vector3 = centres[k]
			if c.distance_squared_to(pa) < da:
				da = c.distance_squared_to(pa)
				best_a = k
			if c.distance_squared_to(pb) < db:
				db = c.distance_squared_to(pb)
				best_b = k
		var los: Dictionary = (state["units"][best_a] as Dictionary).get("los", {})
		return bool(los.get(best_b, true))


## Force every cached AiPlanner/BattleSim env-knob static to the header's
## recorded value: OS.set_environment (what a fresh process would read) THEN
## the static reset (each getter lazy-caches on first read — see the comments
## at each var's declaration in ai_planner.gd/battle_sim.gd).
func _stamp_knobs(k: Dictionary) -> void:
	OS.set_environment("NML_TOP_K", str(int(k.get("top_k", 6))))
	AiPlanner._tk = 0
	OS.set_environment("NML_HORIZON", str(int(k.get("horizon", 2))))
	AiPlanner._hz = 0
	OS.set_environment("NML_PLAYOUT_TAIL_CAP_P1", str(int(k.get("tail_cap_p1", 0))))
	OS.set_environment("NML_PLAYOUT_TAIL_CAP_P2", str(int(k.get("tail_cap_p2", 0))))
	AiPlanner._tail_cap_env = {}
	OS.set_environment("NML_IMAGINED_ROUND_END", "on" if bool(k.get("imagined_round_end", true)) else "off")
	AiPlanner._ire_env = -1
	OS.set_environment("NML_DEPTH_DISCOUNT", str(float(k.get("depth_discount", 0.5))))
	AiPlanner._dd_env = -1.0
	var seat := int(k.get("seat_mode", 0))
	OS.set_environment("NML_SEAT_DEPTH", "on" if seat == 1 else ("inv" if seat == 2 else "off"))
	AiPlanner._seat_env = -1
	OS.set_environment("NML_PLAYOUT_MARGIN", str(float(k.get("playout_margin", 0.02))))
	AiPlanner._po_margin_env = -1.0
	OS.set_environment("NML_PLAYOUT_RICH", "1" if bool(k.get("playout_rich", true)) else "0")
	AiPlanner._po_rich = -1
	OS.set_environment("NML_SIM_CAST", "1" if bool(k.get("seam_cast", false)) else "0")
	BattleSim._cast_env = -1
	OS.set_environment("NML_SIM_SPACING", "1" if bool(k.get("seam_spacing", false)) else "0")
	BattleSim._spacing_env = -1


func _compare_pick(rec: Dictionary, got: Dictionary, mism: Array) -> void:
	_eq(mism, "pick.used", rec.get("used", false), got.get("used", false), "b")
	if not bool(rec.get("used", false)):
		return
	_eq(mism, "pick.unit_key", rec.get("unit_key", ""), got.get("unit_key", ""), "s")
	_compare_action(rec.get("action", {}), got.get("action", {}), mism, "pick.action")
	var re: Dictionary = rec.get("expectation", {})
	var ge: Dictionary = got.get("expectation", {})
	_eq(mism, "pick.expectation.before", re.get("before", 0.0), ge.get("before", 0.0), "f")
	_eq(mism, "pick.expectation.after", re.get("after", 0.0), ge.get("after", 0.0), "f")
	_eq(mism, "pick.waits", rec.get("waits", 0), got.get("waits", 0), "i")
	var rs := {}
	for u in (rec.get("rolled_units", []) as Array):
		rs[str(u)] = true
	var gs := {}
	for u in (got.get("rolled_units", []) as Array):
		gs[str(u)] = true
	var eq := rs.size() == gs.size()
	if eq:
		for kk in rs:
			if not gs.has(kk):
				eq = false
				break
	if not eq:
		mism.append({"field": "pick.rolled_units", "recorded": rec.get("rolled_units"), "got": got.get("rolled_units")})


func _compare_action(rec: Dictionary, got: Dictionary, mism: Array, prefix: String) -> void:
	_eq(mism, prefix + ".kind", rec.get("kind", -1), got.get("kind", -1), "i")
	_eq(mism, prefix + ".unit", rec.get("unit", ""), got.get("unit", ""), "s")
	if rec.has("dest") or got.has("dest"):
		var rd: Array = rec.get("dest", [])
		var gd: Vector3 = got.get("dest", Vector3.ZERO)
		if rd.size() != 3 or absf(float(rd[0]) - gd.x) > EPS \
				or absf(float(rd[1]) - gd.y) > EPS or absf(float(rd[2]) - gd.z) > EPS:
			mism.append({"field": prefix + ".dest", "recorded": rd, "got": [gd.x, gd.y, gd.z]})
	for k in ["shoot", "charge", "wave"]:
		_eq(mism, prefix + "." + k, rec.get(k, ""), got.get(k, ""), "s")
	_eq(mism, prefix + ".patient", rec.get("patient", false), got.get("patient", false), "b")


func _compare_trace(rec: Dictionary, got: Dictionary, mism: Array) -> void:
	if rec.is_empty() and got.is_empty():
		return
	var rsc: Array = rec.get("scored", [])
	var gsc: Array = got.get("scored", [])
	if rsc.size() != gsc.size():
		mism.append({"field": "trace.scored.size", "recorded": rsc.size(), "got": gsc.size()})
	else:
		for i in rsc.size():
			var r: Dictionary = rsc[i]
			var g: Dictionary = gsc[i]
			_eq(mism, "trace.scored[%d].idx" % i, r.get("idx", -1), g.get("idx", -1), "i")
			_eq(mism, "trace.scored[%d].unit" % i, r.get("unit", ""), g.get("unit", ""), "s")
			_eq(mism, "trace.scored[%d].kind" % i, r.get("kind", -1), g.get("kind", -1), "i")
			_eq(mism, "trace.scored[%d].score" % i, r.get("score", 0.0), g.get("score", 0.0), "f")
	var rpi: Array = rec.get("pool_idx", [])
	var gpi: Array = got.get("pool_idx", [])
	var pool_eq := rpi.size() == gpi.size()   # JSON round-trips ints as floats; == is strict-typed
	for i in range(min(rpi.size(), gpi.size())):
		if int(rpi[i]) != int(gpi[i]):
			pool_eq = false
	if not pool_eq:
		mism.append({"field": "trace.pool_idx", "recorded": rpi, "got": gpi})
	var rrs: Array = rec.get("rs", [])
	var grs: Array = got.get("rs", [])
	if rrs.size() != grs.size():
		mism.append({"field": "trace.rs.size", "recorded": rrs.size(), "got": grs.size()})
	else:
		for i in rrs.size():
			var r: Dictionary = rrs[i]
			var g: Dictionary = grs[i]
			_eq(mism, "trace.rs[%d].idx" % i, r.get("idx", -1), g.get("idx", -1), "i")
			_eq(mism, "trace.rs[%d].value" % i, r.get("rs", 0.0), g.get("rs", 0.0), "f")
	_eq(mism, "trace.best_idx", rec.get("best_idx", -1), got.get("best_idx", -1), "i")
	_eq(mism, "trace.runner_idx", rec.get("runner_idx", -1), got.get("runner_idx", -1), "i")
	var ra: Variant = rec.get("arbitration")
	var ga: Variant = got.get("arbitration")
	if (ra == null) != (ga == null):
		mism.append({"field": "trace.arbitration.null", "recorded": ra, "got": ga})
	elif ra != null:
		var rad: Dictionary = ra
		var gad: Dictionary = ga
		_eq(mism, "trace.arbitration.sig", rad.get("sig", 0), gad.get("sig", 0), "i")
		_eq(mism, "trace.arbitration.n", rad.get("n", 0), gad.get("n", 0), "i")
		_eq(mism, "trace.arbitration.sum_b", rad.get("sum_b", 0.0), gad.get("sum_b", 0.0), "f")
		_eq(mism, "trace.arbitration.sum_r", rad.get("sum_r", 0.0), gad.get("sum_r", 0.0), "f")
		_eq(mism, "trace.arbitration.swapped", rad.get("swapped", false), gad.get("swapped", false), "b")


## kind: "i" int, "s" string, "b" bool, "f" float (EPS tolerance) — JSON round-
## trips ints as floats, so every recorded value is coerced before comparing.
func _eq(mism: Array, field: String, rec: Variant, got: Variant, kind: String) -> void:
	var bad := true
	match kind:
		"i": bad = int(rec) != int(got)
		"s": bad = str(rec) != str(got)
		"b": bad = bool(rec) != bool(got)
		_: bad = absf(float(rec) - float(got)) > EPS
	if bad:
		mism.append({"field": field, "recorded": rec, "got": got})
