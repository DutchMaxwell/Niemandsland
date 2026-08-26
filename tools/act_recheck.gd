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
## NML-1073 M2-0d: the charge gate is no longer replayed from the recorded ROOT
## pair matrix (which cannot answer a rollout-imagined gap) but from
## BattleSim.charge_illegal_plain, a PURE function of the capture. Two checks
## ride on that: CHARGE_GATE diffs the pure function against the recorded LIVE
## gap grid (act line "charge_illegal_grid"), and the stamped state Callable
## forwards to it so the search itself replays off the pure gate.
##
## Usage: godot --headless -s res://tools/act_recheck.gd --
##   file=<acts.jsonl> [n=25] [offset=0]
##   --corrupt=charge   RED proof: flip the PURE gate's answer inside the search
##   --corrupt=gate     RED proof for CHARGE_GATE: flip it inside the grid diff
##   --ignore-knobs     RED proof (only bites on a non-default-knobs corpus):
##                       never stamp the header's knobs

const NodeRecheck := preload("res://tools/node_recheck.gd")
const EPS := 1e-9

var _corrupt_charge := false
var _corrupt_gate := false
var _ignore_knobs := false
var _gate_pairs := 0
var _gate_points := 0
var _gate_bad := 0
var _matrix_pairs := 0
var _matrix_bad := 0


func _init() -> void:
	var file_path := ""
	var n := 25
	var offset := 0
	for a in OS.get_cmdline_user_args():
		if a == "--corrupt=charge":
			_corrupt_charge = true
			continue
		if a == "--corrupt=gate":
			_corrupt_gate = true
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
	# M2-0d: BattleSim.charge_illegal_plain asks the board through header["terrain_at"]
	# — the SAME port node_recheck already owns, built ONCE here (rebuilding the cell
	# dictionary per gate call would dominate the run).
	if terrain != null:
		header["terrain_at"] = NodeRecheck.terrain_at_from_plain(terrain as Dictionary)
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
		var mism := _check_act(act, header, profiles, terrain, knobs)
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
	print("CHARGE_GATE pairs=%d grid=%d mismatch=%d" % [_gate_pairs, _gate_points, _gate_bad])
	print("CHARGE_MATRIX pairs=%d mismatch=%d" % [_matrix_pairs, _matrix_bad])
	print("RECHECK acts=%d ok=%d mismatch=%d" % [checked, ok, mismatch])
	# NML-1073 M2-0b: the replay stamps its OWN charge_illegal/los_at lambdas
	# into every rebuilt state, and plan_with_rollout parks the last one's leaf
	# in a script static — drop it before quit(), or teardown frees a lambda
	# whose script instance is already gone (measured elsewhere: exit 134).
	AiPlanner.close()
	quit(0 if (mismatch == 0 and _gate_bad == 0) else 1)


## One activation: rebuild -> stamp -> plan_with_rollout -> diff. Returns the
## list of mismatches (empty = exact replay).
func _check_act(act: Dictionary, header: Dictionary, profiles: Dictionary,
		terrain: Variant, knobs: Dictionary) -> Array:
	var state: Dictionary = NodeRecheck._rebuild_state(act["state"], profiles)
	var key_of := {}   # GameUnit instance id -> the corpus's string unit key
	for k in state["units"]:
		key_of[(state["units"][k]["unit"] as GameUnit).get_instance_id()] = str(k)

	# M2-0d: the search's charge gate is the PURE function of the capture, called
	# with the SAME five arguments the live SoloController.charge_candidate_illegal
	# takes — so a rollout-imagined gap/geometry gets a real answer instead of the
	# root matrix's one recorded point (the M2-0c 22/25 rollout-leaf mismatch).
	# The plain (recorded) state carries every per-unit read the gate makes; those
	# are ROOT reads in the live game too (the search never mutates a GameUnit).
	var plain_state: Dictionary = act["state"]
	var corrupt := _corrupt_charge
	var ci_gap := [false]
	state["charge_illegal"] = func(atk: GameUnit, vic: GameUnit, gap: float,
			ca: Vector3, cv: Vector3) -> bool:
		var akey := str(key_of.get(atk.get_instance_id(), ""))
		var vkey := str(key_of.get(vic.get_instance_id(), ""))
		if akey == "" or vkey == "":
			push_error("[ACT_RECHECK] charge_illegal: unit outside the corpus state")
			ci_gap[0] = true
			return false
		var v := BattleSim.charge_illegal_plain(plain_state, header, akey, vkey, gap, ca, cv)
		return (not v) if corrupt else v
	_check_gate_grid(act, header, plain_state)

	if terrain != null:
		state["terrain_at"] = NodeRecheck.terrain_at_from_plain(terrain as Dictionary)
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


## NML-1073 M2-0d: BattleSim.charge_illegal_plain against the recorded LIVE gap grid —
## every ordered opposite-side pair over 29 gaps (0", 0.5", … 14"). from/to are left to
## the plain state's own centres, which is exactly how the recorder called the live gate.
## The ROOT pair matrix is kept as an extra sanity print: the same pure function at the
## pair's own real gap must reproduce the matrix M2-0c replayed from.
func _check_gate_grid(act: Dictionary, header: Dictionary, plain_state: Dictionary) -> void:
	var grid: Dictionary = act.get("charge_illegal_grid", {})
	var first_bad := true
	for pk in grid:
		var parts := str(pk).split("|")
		if parts.size() != 2:
			continue
		_gate_pairs += 1
		var row: Array = grid[pk]
		for i in row.size():
			var gap := float(i) * AiActRecorder.GATE_GRID_STEP_IN
			var want := bool(row[i])
			var got := BattleSim.charge_illegal_plain(plain_state, header, parts[0], parts[1], gap)
			if _corrupt_gate:
				got = not got
			_gate_points += 1
			if got != want:
				_gate_bad += 1
				if first_bad:
					first_bad = false
					_print_gate_bisect(plain_state, header, parts[0], parts[1], gap, want, got)
	var matrix: Dictionary = act.get("charge_illegal", {})
	var units: Dictionary = plain_state["units"]
	for mk in matrix:
		var mp := str(mk).split("|")
		if mp.size() != 2 or not units.has(mp[0]) or not units.has(mp[1]):
			continue
		_matrix_pairs += 1
		var gap := maxf(BattleSim.dist_in(NodeRecheck._vec3s((units[mp[0]] as Dictionary)["positions"]),
			NodeRecheck._vec3s((units[mp[1]] as Dictionary)["positions"])) - BattleSim.CONTACT_IN, 0.0)
		if BattleSim.charge_illegal_plain(plain_state, header, mp[0], mp[1], gap) != bool(matrix[mk]):
			_matrix_bad += 1


## Every intermediate the LIVE gate computes on the way to its answer, for the FIRST
## disagreeing pair/gap — the bisect the fix starts from (which read is missing, or wrong).
func _print_gate_bisect(plain_state: Dictionary, header: Dictionary, ak: String, vk: String,
		gap: float, want: bool, got: bool) -> void:
	var units: Dictionary = plain_state["units"]
	var au: Dictionary = units[ak]
	var vu: Dictionary = units[vk]
	var band := float((au.get("bands", {}) as Dictionary).get("rush", 12))
	var reach := BattleSim._melee_shroud_charge_in_plain(band, vu)
	var probe_r := float(au.get("charge_probe_r", -1.0))
	var ca := BattleSim._plain_centre(au)
	var cv := BattleSim._plain_centre(vu)
	var terrain_at: Callable = header.get("terrain_at", Callable())
	print("  CHARGE_GATE MISMATCH %s|%s gap=%.2f live=%s pure=%s" % [ak, vk, gap, str(want), str(got)])
	print("    victim.aircraft=%s attacker.rush=%.3f shroud=%s reach=%.3f" \
		% [str(bool(vu.get("aircraft", false))), band, str(vu.get("shroud", [])), reach])
	print("    cap_in=%.1f no_difficult=%s probe_r=%.5f terrain=%s" \
		% [SoloController.DIFFICULT_MOVE_CAP_IN, str(bool(au.get("charge_no_difficult", false))),
			probe_r, str(terrain_at.is_valid())])
	print("    from=%s to=%s corridor_forced=%s" % [str(ca), str(cv),
		str(BattleSim._corridor_forced_through_plain(ca, cv, probe_r, terrain_at))])
