class_name MoveRecorder
extends RefCounted
## NML-1073 M4-0a: env NML_MOVE_DUMP=<dir> appends every MovementPlanner.plan_unit_step call made from
## SoloController._plan_positions to <dir>/moves_calls.jsonl — the movement counterpart to act_recorder.gd
## (AiActRecorder), same style: one FileAccess stream opened once and kept open, JSON lines via
## JSON.stringify(x, "", true, true), env cap NML_MOVE_DUMP_MAX (default 2000). Unset (default) never
## touches disk: the caller calls begin()/finish() unconditionally, but begin() returns {} on the very
## first (cheap, cached) env check and finish() no-ops on an empty pending dict — byte-identical game
## either way (the Rust port's per-move-call contract, corpus for M4-0b's replay parity gate).
##
## Line 1 is {"kind":"header", "board_in":[w,h], "board_y_in", "inches_to_meters", "terrain", "walls",
## "fast_planner", "fast_planner_guard", "constants":{...}} — the STATIC per-game data every
## plan_unit_step call reads, written ONCE from the first call's own inputs; every call after it is a
## {"kind":"call", ...} line with the FULL plan_unit_step input (model_pos/delta/walls/grid/opts, AS
## PASSED) plus the "planned"/"trails"/"flow_order" it returned.
##
## NML_MOVE_TRACE=1 (only meaningful together with NML_MOVE_DUMP) additionally arms
## MovementPlanner.trace_on so each call line also carries a "trace" block: the sequential flow's per-
## model Theta*/string-pull/walk legs, the untangle 2-opt swaps, and solve_formation's per-pass
## positions+score — fed in by MovementPlanner's own trace_model/trace_swap/trace_solve_pass calls into
## this file's static buffers (zero cost on the hot path when trace_on is false: one bool check).


static var _stream: FileAccess = null
static var _checked := false
static var _header_written := false
static var _max := 2000
static var _count := 0
static var _trace_wanted := false
static var _header_walls: Array = []

static var _trace_flow: Array = []
static var _trace_swaps: Array = []
static var _trace_solve: Array = []


static func _dump_stream() -> FileAccess:
	if not _checked:
		_checked = true
		var dir := OS.get_environment("NML_MOVE_DUMP")
		if dir != "" and DirAccess.dir_exists_absolute(dir):
			_stream = FileAccess.open(dir.path_join("moves_calls.jsonl"), FileAccess.WRITE)
			var cap := OS.get_environment("NML_MOVE_DUMP_MAX")
			if cap != "":
				_max = maxi(int(cap), 0)
			_trace_wanted = OS.get_environment("NML_MOVE_TRACE") == "1"
	return _stream


## Pre-call capture (INPUT). `ctx` carries every plan_unit_step argument AS PASSED (model_pos, delta,
## walls, grid, allow_contact, board_in, opts) plus the caller's own bookkeeping (unit, act, round, rung)
## and the terrain Callable (header only). Returns {} when the env seam is off or the line cap is hit —
## the caller's finish() then no-ops too. Also arms/disarms MovementPlanner.trace_on for THIS call.
static func begin(ctx: Dictionary) -> Dictionary:
	var f := _dump_stream()
	MovementPlanner.trace_on = f != null and _trace_wanted and _count < _max
	if f == null or _count >= _max:
		return {}
	if not _header_written:
		_header_written = true
		f.store_line(JSON.stringify(_header_line(ctx), "", true, true))
		f.flush()   # a same-process reader (the completeness smoke) must see the header without a close()
	if MovementPlanner.trace_on:
		_trace_flow = []
		_trace_swaps = []
		_trace_solve = []
	var opts: Dictionary = ctx["opts"]
	var walls: Array = ctx["walls"]
	return {"kind": "call", "unit": ctx["unit"], "act": int(ctx["act"]), "round": int(ctx["round"]),
		"rung": ctx["rung"], "model_pos": _flatten(ctx["model_pos"]), "delta": _flatten(ctx["delta"]),
		"walls": "header" if walls == _header_walls else _flatten(walls), "grid": _grid_list(ctx["grid"]),
		"allow_contact": bool(ctx["allow_contact"]), "board_in": float(ctx["board_in"]),
		"opts": _flatten_opts(opts)}


## Post-call write (OUTPUT). `pending` is begin()'s return value — {} (env off / cap hit) is a silent
## no-op. `opts` is the SAME Dictionary object the call was made with: plan_unit_step writes
## opts["flow_order"] back into it, so reading it here (after the call) picks that up.
static func finish(pending: Dictionary, planned: Array, trails: Array, opts: Dictionary) -> void:
	if pending.is_empty() or _stream == null or _count >= _max:
		return
	pending["planned"] = _flatten(planned)
	pending["trails"] = _flatten(trails)
	pending["flow_order"] = opts.get("flow_order", [])
	if MovementPlanner.trace_on:
		pending["trace"] = {"flow": _trace_flow, "untangle_swaps": _trace_swaps, "solve_passes": _trace_solve}
	MovementPlanner.trace_on = false
	_stream.store_line(JSON.stringify(pending, "", true, true))
	_stream.flush()   # a same-process reader (the completeness smoke) must see the line without a close()
	_count += 1


## NML-1073 M4-0a: closes the stream at a GAME's end (arena_match/core_selfplay, via AiPlanner.close())
## so the file is complete where the writer stands. Resets every cached static so a later begin()
## reopens a fresh file+header cleanly.
static func close() -> void:
	if _stream != null:
		_stream.flush()
		_stream.close()
	_stream = null
	_checked = false
	_header_written = false
	_count = 0
	_trace_wanted = false
	_header_walls = []
	MovementPlanner.trace_on = false


static func _header_line(ctx: Dictionary) -> Dictionary:
	_header_walls = ctx["walls"]
	var opts: Dictionary = ctx["opts"]
	var board_y_in := float(opts.get("board_y_in", 0.0))
	return {"kind": "header", "board_in": [float(ctx["board_in"]), board_y_in], "board_y_in": board_y_in,
		"inches_to_meters": SoloController.INCHES_TO_METERS,
		"terrain": AiActRecorder._terrain_line(ctx["terrain_cb"]), "walls": _flatten(ctx["walls"]),
		"fast_planner": MovementPlanner.fast_planner, "fast_planner_guard": MovementPlanner.fast_planner_guard,
		"constants": _constants()}


## Every MovementPlanner const the plan_unit_step pipeline (:496-1650) reads, plus SoloController's
## CLEARANCE_EPS_IN (the caller-side wall-clearance epsilon folded into opts["clearance"]).
static func _constants() -> Dictionary:
	var diag: Array = []
	for d in MovementPlanner.THETA_DIAG:
		diag.append([(d as Vector2i).x, (d as Vector2i).y])
	return {"EPS": MovementPlanner.EPS, "BASE_CONTACT_IN": MovementPlanner.BASE_CONTACT_IN,
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


## opts, verbatim, EXCEPT: avoid_cells/avoid_fine/forbid_cells (Vector2i-keyed sets) become cell lists
## [[cx,cy],...] instead of dicts (a Vector2i can't be a JSON key), and flow_order is dropped — it is an
## OUTPUT plan_unit_step writes into the SAME opts object, recorded separately by finish() once it exists.
static func _flatten_opts(opts: Dictionary) -> Dictionary:
	var out := {}
	for k in opts:
		if k == "flow_order":
			continue
		if k == "avoid_cells" or k == "avoid_fine" or k == "forbid_cells":
			out[str(k)] = _cell_list(opts[k] as Dictionary)
		else:
			out[str(k)] = _flatten(opts[k])
	return out


static func _cell_list(d: Dictionary) -> Array:
	var out: Array = []
	for k in d:
		var c := k as Vector2i
		out.append([c.x, c.y])
	return out


## The typed 3" cells the call received, as [cx, cy, type] rows (a Vector2i can't be a JSON key).
static func _grid_list(grid: Dictionary) -> Array:
	var out: Array = []
	for k in grid:
		var c := k as Vector2i
		out.append([c.x, c.y, int(grid[k])])
	return out


## Recursive Vector2/Vector2i -> [x,y] flattener (JSON.stringify would otherwise write a Vector-typed
## value as its native "(x, y)" STRING, not a parsable number pair) — applied through any Array/
## Dictionary nesting depth, since the planner's inputs/outputs nest Vector2 at every level (a bare
## point, a [a,b] wall segment, a trail = an array of points, a zone dict's "c" field, ...).
static func _flatten(v: Variant) -> Variant:
	if v is Vector2:
		return [(v as Vector2).x, (v as Vector2).y]
	if v is Vector2i:
		return [(v as Vector2i).x, (v as Vector2i).y]
	if v is Dictionary:
		var out := {}
		for k in (v as Dictionary):
			out[str(k)] = _flatten((v as Dictionary)[k])
		return out
	if v is Array:
		var out: Array = []
		for e in (v as Array):
			out.append(_flatten(e))
		return out
	return v


# === Trace hooks (NML_MOVE_TRACE=1) — called from movement_planner.gd, guarded there by trace_on ====

## Sequential flow (:1011-1166): one entry per model per attempt (a deferred model's stalled first
## attempt AND its later retry both record) — the Theta* path, the string-pulled taut polyline, and the
## walked (offset + allowance-spent) leg, plus whether this attempt deferred to the back of the queue.
static func trace_model(idx: int, route: Array, taut: Array, leg: Array, deferred: bool) -> void:
	_trace_flow.append({"model": idx, "theta": _flatten(route), "taut": _flatten(taut),
		"walked": _flatten(leg), "deferred": deferred})


## untangle_endpoints (:1173-1204): one [i, j] entry per accepted endpoint swap.
static func trace_swap(i: int, j: int) -> void:
	_trace_swaps.append([i, j])


## solve_formation (:1573-1597): one entry per sweep — the positions AFTER that pass's projections and
## its violation score (0 = fully legal; see _formation_score).
static func trace_solve_pass(pass_idx: int, positions: Array, score: float) -> void:
	_trace_solve.append({"pass": pass_idx, "positions": _flatten(positions), "score": score})
