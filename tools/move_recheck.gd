extends SceneTree
## NML-1073 M4-0b — the M2-0c act_recheck.gd sibling for MOVEMENT: proves scripts/solo/move_recorder.gd's
## moves_calls.jsonl corpus is COMPLETE. Rebuilds every MovementPlanner.plan_unit_step argument from the
## recorded JSON ALONE — Vector2/Vector2i typed back, avoid/forbid cell dicts, zones, charge slot/base
## geometry — mirroring exactly how SoloController._plan_positions builds them (solo_controller.gd:5940-
## 6086), stamps the header's fast_planner/fast_planner_guard statics, calls the REAL planner with
## MovementPlanner.trace_on armed, and diffs planned/trails/flow_order/trace against what was recorded.
## Any mismatch means some live read the call line does not carry the inputs for.
##
## Both the recorded trace (move_recorder.gd's trace_model/trace_swap/trace_solve_pass) and THIS tool's
## replay trace are built through the SAME MoveRecorder._flatten-shaped buffers (MoveRecorder._trace_flow/
## _trace_swaps/_trace_solve — read directly, no re-derivation), so the comparison is a plain structural
## diff once "planned"/"trails" are flattened through MoveRecorder._flatten too (reused verbatim, the same
## pattern act_recheck.gd uses for AiActRecorder._flatten_vec3).
##
## trace v2 (header "trace_v": 2, NML-1073 M4-0b follow-up): the generic diff above already covers the new
## per-node Theta* search trace and the new per-flow-entry "walk_spent"/"pull" fields node-exact (it only
## ever checks keys the RECORDING carries, so a v1 file — no "trace_v", no v2 keys — is unaffected). ON TOP
## of that, _verify_v2 below checks what a v2 file lets us recompute from the corpus ALONE, independent of
## the full replay: walk_spent against the recorded trail's own arc length, and the post-pull endpoint via
## a standalone MovementPlanner._pull_into_placed call. Reports "v2 fields: checked N / skipped M" per file.
##
## Usage: godot --headless -s res://tools/move_recheck.gd --
##   file=<moves_calls.jsonl> [n=<N>] [offset=<K>]
##   --corrupt=zones   RED proof: drop every second recorded zone disc before replay
##   --corrupt=guard   RED proof: ignore the header's fast_planner_guard, force 200

const EPS := 1e-9

var _corrupt_zones := false
var _corrupt_guard := false


func _init() -> void:
	var file_path := ""
	var n := -1   # -1 = no limit (replay to EOF)
	var offset := 0
	for a in OS.get_cmdline_user_args():
		if a == "--corrupt=zones":
			_corrupt_zones = true
			continue
		if a == "--corrupt=guard":
			_corrupt_guard = true
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
		printerr("[MOVE_RECHECK] cannot open ", file_path)
		quit(1)
		return
	var header: Dictionary = JSON.parse_string(f.get_line())
	_check_constants(header)
	var header_walls := _wall_list(header.get("walls", []))
	MovementPlanner.fast_planner = bool(header.get("fast_planner", false))
	MovementPlanner.fast_planner_guard = 200 if _corrupt_guard \
		else int(header.get("fast_planner_guard", MovementPlanner.FAST_PLANNER_GUARD))

	var skipped := 0
	while skipped < offset and not f.eof_reached():
		if f.get_line().strip_edges() != "":
			skipped += 1

	var checked := 0
	var ok := 0
	var mismatch := 0
	var v2n := [0, 0]   # [checked, skipped] — v2-only field verification tally (trace_pull / trace_walk_spent)
	while (n < 0 or checked < n) and not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var call: Dictionary = JSON.parse_string(line)
		checked += 1
		var mism := _check_call(call, header_walls, v2n)
		var tag := "CALL %d unit=%s rung=%s" % [offset + checked, str(call.get("unit", "")), str(call.get("rung", ""))]
		if mism.is_empty():
			ok += 1
			print("%s OK" % tag)
		else:
			mismatch += 1
			print("%s MISMATCH" % tag)
			for m in mism.slice(0, 3):
				print("  MISMATCH %s: recorded=%s got=%s" % [str(m["field"]), str(m["recorded"]), str(m["got"])])
	print("MOVE_RECHECK calls=%d ok=%d mismatch=%d" % [checked, ok, mismatch])
	print("v2 fields: checked %d / skipped %d" % [v2n[0], v2n[1]])
	quit(0 if mismatch == 0 else 1)


## One call: rebuild -> plan_unit_step (trace armed) -> diff. Returns the list of mismatches (empty = exact
## replay). `v2n` ([checked, skipped]) is mutated with the standalone v2-field tally (see _verify_v2).
func _check_call(call: Dictionary, header_walls: Array, v2n: Array) -> Array:
	var mism: Array = []
	var mpos := _vec2_list(call["model_pos"])
	var delta_arr: Array = call["delta"]
	var delta := Vector2(float(delta_arr[0]), float(delta_arr[1]))
	var walls: Array = header_walls if call["walls"] == "header" else _wall_list(call["walls"])
	var grid := _grid_dict(call["grid"])
	var allow_contact := bool(call["allow_contact"])
	var board_in := float(call["board_in"])
	var opts := _rebuild_opts(call["opts"])

	var trails: Array = []
	MoveRecorder._trace_flow = []
	MoveRecorder._trace_swaps = []
	MoveRecorder._trace_solve = []
	MoveRecorder._trace_theta = []
	MovementPlanner.trace_on = true
	var planned: Array = MovementPlanner.plan_unit_step(mpos, delta, walls, grid, allow_contact, board_in, trails, opts)
	MovementPlanner.trace_on = false
	var flow_order: Array = opts.get("flow_order", [])
	var trace := {"flow": MoveRecorder._trace_flow.duplicate(true),
		"untangle_swaps": MoveRecorder._trace_swaps.duplicate(true),
		"solve_passes": MoveRecorder._trace_solve.duplicate(true),
		"theta_searches": MoveRecorder._trace_theta.duplicate(true)}

	_diff("planned", call.get("planned", []), MoveRecorder._flatten(planned), mism)
	_diff("trails", call.get("trails", []), MoveRecorder._flatten(trails), mism)
	_diff("flow_order", call.get("flow_order", []), flow_order, mism)
	if call.has("trace"):
		_diff("trace", call["trace"], trace, mism)
		_verify_v2(call, mpos.size(), walls, board_in, opts, mism, v2n)
	return mism


## NML-1073 M4-0b trace v2: verifies whatever is recomputable from the CORPUS ALONE (independent of the
## full replay above) — a v1 file (no "walk_spent"/"pull" per flow entry) contributes only to `skipped`.
##   1. walk_spent self-consistency: the recorded scalar equals the recorded "walked" trail's own arc length.
##   2. post-pull endpoint: re-running MovementPlanner._pull_into_placed on the RECORDED pre-pull endpoint
##      (the flow entry's own "walked".back()) reproduces the recorded "pull" — only where the live flow
##      would actually have called it (non-charge, not deferred, at least one model already placed).
func _verify_v2(call: Dictionary, n_models: int, walls: Array, board_in: float, opts: Dictionary,
		mism: Array, v2n: Array) -> void:
	var trace: Dictionary = call.get("trace", {})
	var flow: Array = trace.get("flow", [])
	var is_charge: bool = bool(call.get("allow_contact", false)) and opts.has("charge_goal")
	var radii: Array = opts.get("radii", [])
	var clearance: float = float(opts.get("clearance", 0.0))
	var base_zones: Array = [] if bool(opts.get("zones_rest_only", false)) else opts.get("zones", [])
	var avoid_cells: Dictionary = opts.get("avoid_cells", {})
	var board := MovementPlanner.board_extents(board_in, opts)
	var result: Array = []
	result.resize(n_models)
	var placed: Array = []
	for e in flow:
		var ed: Dictionary = e
		var idx := int(ed.get("model", -1))
		var deferred := bool(ed.get("deferred", false))
		var walked: Array = ed.get("walked", [])
		var pre_pull := Vector2.ZERO
		if not walked.is_empty():
			var last: Array = walked.back()
			pre_pull = Vector2(float(last[0]), float(last[1]))
		if ed.has("walk_spent"):
			var s := 0.0
			for i in range(1, walked.size()):
				var a: Array = walked[i - 1]
				var b: Array = walked[i]
				s += Vector2(float(a[0]), float(a[1])).distance_to(Vector2(float(b[0]), float(b[1])))
			v2n[0] += 1
			if absf(s - float(ed["walk_spent"])) > EPS:
				mism.append({"field": "v2.walk_spent[model=%d]" % idx, "recorded": ed["walk_spent"], "got": s})
		else:
			v2n[1] += 1
		var eligible: bool = not is_charge and not deferred and not placed.is_empty() and idx < radii.size()
		if eligible and ed.has("pull"):
			var got := MovementPlanner._pull_into_placed(pre_pull, idx, radii, placed, result, walls,
				clearance, base_zones, avoid_cells, board)
			v2n[0] += 1
			var rp: Array = ed["pull"]
			var recorded_pull := Vector2(float(rp[0]), float(rp[1]))
			if got.distance_to(recorded_pull) > EPS:
				mism.append({"field": "v2.pull[model=%d]" % idx, "recorded": rp, "got": [got.x, got.y]})
		else:
			v2n[1] += 1
		if not deferred and idx >= 0 and idx < result.size():
			var final_pt := pre_pull
			if ed.has("pull"):
				var fp: Array = ed["pull"]
				final_pt = Vector2(float(fp[0]), float(fp[1]))
			result[idx] = final_pt
			placed.append(idx)


## opts, rebuilt to the exact types _plan_positions passes (solo_controller.gd:5978-6037): Vector2/Vector2i
## typed back, avoid/forbid cell lists -> Vector2i-keyed Dictionaries, zones -> {"c": Vector2, "r": float}.
## --corrupt=zones drops every second zone disc (RED proof: spacing constraints the replay would then miss).
func _rebuild_opts(o: Dictionary) -> Dictionary:
	var out := {}
	for k in o:
		var key := str(k)
		match key:
			"avoid_cells", "avoid_fine", "forbid_cells":
				out[key] = _cell_dict(o[k])
			"zones":
				out[key] = _zones_rebuild(o[k])
			"charge_goal":
				var v: Array = o[k]
				out[key] = Vector2(float(v[0]), float(v[1]))
			"charge_tgt_bases":
				out[key] = _tgt_bases_rebuild(o[k])
			"charge_slots":
				out[key] = _vec2_list(o[k])
			"radii":
				var fr: Array = []
				for x in (o[k] as Array):
					fr.append(float(x))
				out[key] = fr
			_:
				out[key] = o[k]   # board_y_in/clearance/difficult_cap_in/charge_allowance/zones_rest_only: scalars, pass through
	return out


func _zones_rebuild(rows: Array) -> Array:
	var out: Array = []
	for i in rows.size():
		if _corrupt_zones and i % 2 == 1:
			continue
		var z: Dictionary = rows[i]
		var c: Array = z["c"]
		out.append({"c": Vector2(float(c[0]), float(c[1])), "r": float(z["r"])})
	return out


static func _tgt_bases_rebuild(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		var c: Array = r[0]
		out.append([Vector2(float(c[0]), float(c[1])), float(r[1])])
	return out


static func _vec2_list(rows: Array) -> Array:
	var out: Array = []
	for p in rows:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


## Wall segments (header or a non-"header" call value): [[x1,y1],[x2,y2]] rows -> [Vector2, Vector2] pairs
## (movement_planner.gd:128-137's _wall_a/_wall_b index element 0/1 directly).
static func _wall_list(rows: Array) -> Array:
	var out: Array = []
	for w in rows:
		var wa: Array = w[0]
		var wb: Array = w[1]
		out.append([Vector2(float(wa[0]), float(wa[1])), Vector2(float(wb[0]), float(wb[1]))])
	return out


static func _grid_dict(rows: Array) -> Dictionary:
	var out := {}
	for r in rows:
		out[Vector2i(int(r[0]), int(r[1]))] = int(r[2])
	return out


static func _cell_dict(rows: Array) -> Dictionary:
	var out := {}
	for r in rows:
		out[Vector2i(int(r[0]), int(r[1]))] = true
	return out


## Every MovementPlanner/SoloController const move_recorder.gd's _constants() (:120-142) records, diffed
## against the LIVE value — a warning only (these are compile-time consts; a mismatch means the corpus was
## recorded off a different build, not something this replay can fix).
func _check_constants(header: Dictionary) -> void:
	var rec: Dictionary = header.get("constants", {})
	var diag: Array = []
	for d in MovementPlanner.THETA_DIAG:
		diag.append([(d as Vector2i).x, (d as Vector2i).y])
	var live := {"EPS": MovementPlanner.EPS, "BASE_CONTACT_IN": MovementPlanner.BASE_CONTACT_IN,
		"COHERENCY_IN": MovementPlanner.COHERENCY_IN, "MAX_CHAIN_IN": MovementPlanner.MAX_CHAIN_IN,
		"LINK_IN": MovementPlanner.LINK_IN, "SPREAD_IN": MovementPlanner.SPREAD_IN,
		"STEP_IN": MovementPlanner.STEP_IN, "STUCK_FRACTION": MovementPlanner.STUCK_FRACTION,
		"COH_PULL_IN": MovementPlanner.COH_PULL_IN, "COH_PASSES": MovementPlanner.COH_PASSES,
		"LAG_FRACTION": MovementPlanner.LAG_FRACTION, "GATHER_PASSES": MovementPlanner.GATHER_PASSES,
		"UNTANGLE_PASSES": MovementPlanner.UNTANGLE_PASSES, "SLIDE_ANGLES": MovementPlanner.SLIDE_ANGLES,
		"PLAN_CELL_IN": MovementPlanner.PLAN_CELL_IN, "FAST_PLANNER_GUARD": MovementPlanner.FAST_PLANNER_GUARD,
		"DIFFICULT_COST_MULT": MovementPlanner.DIFFICULT_COST_MULT,
		"DANGEROUS_COST_MULT": MovementPlanner.DANGEROUS_COST_MULT, "THETA_DIAG": diag,
		"SOLVE_PASSES": MovementPlanner.SOLVE_PASSES, "CONTACT_SLIDE_EPS_IN": MovementPlanner.CONTACT_SLIDE_EPS_IN,
		"TERRAIN_PUSH_MAX_IN": MovementPlanner.TERRAIN_PUSH_MAX_IN,
		"TERRAIN_PUSH_STEP_IN": MovementPlanner.TERRAIN_PUSH_STEP_IN, "RADIAL_DIRS": MovementPlanner.RADIAL_DIRS,
		"W_TERRAIN": MovementPlanner.W_TERRAIN, "W_COHERENCY": MovementPlanner.W_COHERENCY,
		"W_OVERLAP": MovementPlanner.W_OVERLAP, "W_ZONE": MovementPlanner.W_ZONE,
		"COHERENCY_BISECT_STEPS": MovementPlanner.COHERENCY_BISECT_STEPS,
		"CLEARANCE_EPS_IN": SoloController.CLEARANCE_EPS_IN}
	var drift: Array = []
	_diff("constants", rec, live, drift)
	for m in drift:
		printerr("[MOVE_RECHECK] WARNING constant drift %s: recorded=%s live=%s" % [str(m["field"]), str(m["recorded"]), str(m["got"])])


## Generic recursive structural diff (both sides already plain JSON-shaped: float/int/bool/String/Array/
## Dictionary/null — planned/trails/trace are flattened through MoveRecorder._flatten before this is called,
## exactly matching how move_recorder.gd wrote them). Numeric leaves compare within EPS; everything else exact.
static func _diff(path: String, rec: Variant, got: Variant, mism: Array) -> void:
	var rt := typeof(rec)
	var gt := typeof(got)
	if rt == TYPE_BOOL or gt == TYPE_BOOL:
		if bool(rec) != bool(got):
			mism.append({"field": path, "recorded": rec, "got": got})
		return
	if rt == TYPE_ARRAY:
		if gt != TYPE_ARRAY:
			mism.append({"field": path, "recorded": rec, "got": got})
			return
		var ra: Array = rec
		var ga: Array = got
		if ra.size() != ga.size():
			mism.append({"field": path + ".size", "recorded": ra.size(), "got": ga.size()})
			return
		for i in ra.size():
			_diff("%s[%d]" % [path, i], ra[i], ga[i], mism)
		return
	if rt == TYPE_DICTIONARY:
		if gt != TYPE_DICTIONARY:
			mism.append({"field": path, "recorded": rec, "got": got})
			return
		var rd: Dictionary = rec
		var gd: Dictionary = got
		# One-directional on purpose (NML-1073 M4-0b trace v2): only keys the RECORDING carries are
		# checked, so a v1 corpus (no "walk_spent"/"pull"/"theta_searches" per entry) simply never
		# exercises those v2-only keys, even though a live v2 replay always produces them.
		for k in rd:
			if not gd.has(k):
				mism.append({"field": path + "." + str(k), "recorded": rd[k], "got": null})
				continue
			_diff(path + "." + str(k), rd[k], gd[k], mism)
		return
	if rt == TYPE_STRING or gt == TYPE_STRING:
		if str(rec) != str(got):
			mism.append({"field": path, "recorded": rec, "got": got})
		return
	if rt == TYPE_NIL and gt == TYPE_NIL:
		return
	if absf(float(rec) - float(got)) > EPS:
		mism.append({"field": path, "recorded": rec, "got": got})
