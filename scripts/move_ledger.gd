class_name MoveLedger
extends RefCounted
## "Path painting" P1 — the movement ledger: every executed human move is recorded as a
## polyline + measured arc length (the proof-of-movement data layer; see docs/ROADMAP.md).
## The model IS the brush: during a drag the anchor's traversed path is sampled, and on
## drop each moved model's own polyline (the anchor path translated to its base, with the
## drop-resolved final position appended) is recorded here and painted by MoveTrails.
##
## This class is PURE data + rules (no nodes, no rendering) so the two behaviours the
## design makes binding are unit-testable:
##   1. MEASUREMENT — the arc length of the polyline that was actually dragged. The path
##      is never re-routed; simplify() only drops near-collinear sample noise.
##   2. ACTIVATION-END CLEARING — a unit's visible trails persist until the END OF THE
##      UNIT'S ACTIVATION (maintainer precision). An activation ends when (a) the same
##      owner commits a move for a DIFFERENT unit (the next activation began), (b) the
##      unit is marked Activated (bookkeeping done), or (c) the round advances. Multiple
##      drops of the SAME unit (moving a unit model by model) accumulate; a single drop
##      spanning several units (sandbox housekeeping) is ONE set — its units do not fade
##      each other (drop_id groups them, including across the per-unit MP messages).
##
## Ledger entries themselves OUTLIVE the visible trail (the design keeps the data for the
## round receipt / replay stages) — note_* only steers what is VISIBLE.

# ===== Constants =====

## Inches -> metres (CODING_STANDARDS §2.2; shared with SeparationChecker et al.).
const INCHES_TO_METERS := 0.0254

## Douglas-Peucker deviation bound (metres) for simplify(): ~2 mm keeps every deliberate
## bend (the taut path is binding geometry) and only drops sampling noise.
const SIMPLIFY_MAX_DEV_M := 0.002

## Consecutive samples closer than this (metres) collapse into one point.
const SIMPLIFY_MIN_DIST_M := 0.003

## Backtrack ("Rückwärtsmalen radiert") tolerance (metres): while the cursor retraces
## toward the start within this perpendicular band of the last recorded leg, the head is
## erased and the budget REFUNDED — so wiggling or repositioning can't inflate the
## measured travel. 0.25" ≈ absorbs hand jitter but well under a base width, so a genuine
## parallel detour (offset further than this) is NOT mistaken for a backtrack.
const RETRACE_TOLERANCE_M := 0.00635

## Min forward advance (metres) before a new committed vertex is laid down (~0.2"): keeps
## legs long enough for stable retrace geometry; the live head tracks the cursor between.
const PATH_SAMPLE_MIN_M := 0.005

# ===== State =====

## Every recorded move this session: {owner, unit, unit_name, model, points, inches,
## round, ts_ms}. Kept in memory (small: a few floats per move); round-tagged so later
## stages (receipt/replay) can slice per round.
var entries: Array[Dictionary] = []

## Per-owner visible-trail activation tracking: owner (int) -> {"drop": int (drop_id),
## "units": PackedStringArray (unit keys committed in the CURRENT activation)}.
var _active: Dictionary = {}


# ===== Pure geometry (static) =====

## Arc length of a world-XZ polyline (metres in) in INCHES — the measured truth stamped
## onto every trail. 0.0 for fewer than 2 points.
static func length_inches(points: PackedVector2Array) -> float:
	return length_meters(points) / INCHES_TO_METERS


## Arc length of a world-XZ polyline in METRES — the movement-budget currency for the cap.
static func length_meters(points: PackedVector2Array) -> float:
	var metres := 0.0
	for i in range(1, points.size()):
		metres += points[i - 1].distance_to(points[i])
	return metres


## RETRACE-only pass — the erase half of a drag update: pop every trailing leg the cursor
## `c` has walked back along (within `retrace_tol` of the leg's line, projecting before the
## leg's end). This is the design's "Rückwärtsmalen radiert, Budget kommt zurück" — it
## SHORTENS the net path (refunding the budget) and never appends. Cascades back leg by
## leg, so a full there-and-back collapses to ~0 net; a genuine parallel detour (offset
## beyond the tolerance) is preserved. Returns the shortened path (>=1 point when non-empty).
static func retrace(points: PackedVector2Array, c: Vector2,
		retrace_tol: float = RETRACE_TOLERANCE_M) -> PackedVector2Array:
	var pts := points.duplicate()
	if pts.is_empty():
		return pts
	while pts.size() >= 2:
		var head: Vector2 = pts[pts.size() - 1]
		var prev: Vector2 = pts[pts.size() - 2]
		var seg := head - prev
		var seg_len := seg.length()
		if seg_len < 0.000001:
			pts.remove_at(pts.size() - 1)   # degenerate leg — drop it
			continue
		var dir := seg / seg_len
		var proj := (c - prev).dot(dir)                       # distance along prev -> head
		var perp := (c - (prev + dir * proj)).length()        # offset from the leg's line
		# Retracing = the cursor sits before the head along this leg (proj < seg_len) and
		# close to its line. Pop the head; the next iteration re-checks the shorter path.
		if perp <= retrace_tol and proj < seg_len - 0.000001:
			pts.remove_at(pts.size() - 1)
			continue
		break
	return pts


## Extend the recorded drag polyline toward the current cursor `c`: RETRACE (erase what the
## cursor walked back over — budget refunded) then EXTEND (append `c` as the new head once it
## has advanced at least `sample_min`, so legs stay long enough for stable geometry). The one
## drag-sampler behind the free-drag path (the movement-cap path composes retrace() itself so
## it can clamp the head before appending). Pure + deterministic.
static func extend_path(points: PackedVector2Array, c: Vector2,
		retrace_tol: float = RETRACE_TOLERANCE_M,
		sample_min: float = PATH_SAMPLE_MIN_M) -> PackedVector2Array:
	if points.is_empty():
		return PackedVector2Array([c])
	var pts := retrace(points, c, retrace_tol)
	if pts.is_empty() or pts[pts.size() - 1].distance_to(c) >= sample_min:
		pts.append(c)
	return pts


## Truncate a world-XZ polyline to a maximum arc length (metres), interpolating the final
## leg so the result is EXACTLY `max_len_m` long — the "dry brush" boundary: the path can't
## represent more travel than the budget. Returns the head-only path for a non-positive
## budget, and the input unchanged when it is already within budget.
static func truncate_to_length(points: PackedVector2Array, max_len_m: float) -> PackedVector2Array:
	if points.is_empty():
		return points.duplicate()
	if max_len_m <= 0.0:
		return PackedVector2Array([points[0]])
	var out := PackedVector2Array([points[0]])
	var acc := 0.0
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var seg := a.distance_to(b)
		if acc + seg <= max_len_m + 0.000000001:
			out.append(b)
			acc += seg
		else:
			var remaining := max_len_m - acc
			if remaining > 0.0 and seg > 0.000001:
				out.append(a + (b - a).normalized() * remaining)
			return out
	return out


## Simplify a sampled drag polyline WITHOUT re-routing it: collapse near-duplicate
## samples, then Douglas-Peucker with a millimetre-scale deviation bound so collinear
## sample noise goes away while every deliberate bend stays. Endpoints are always kept
## exactly (the final position is the binding drop-resolved spot).
static func simplify(points: PackedVector2Array,
		max_dev_m: float = SIMPLIFY_MAX_DEV_M,
		min_dist_m: float = SIMPLIFY_MIN_DIST_M) -> PackedVector2Array:
	if points.size() < 2:
		return points.duplicate()
	# Pass 1: drop consecutive near-duplicates, but always keep the exact last point.
	var pts := PackedVector2Array()
	pts.append(points[0])
	for i in range(1, points.size()):
		if pts[pts.size() - 1].distance_to(points[i]) >= min_dist_m:
			pts.append(points[i])
	var last := points[points.size() - 1]
	if pts[pts.size() - 1] != last:
		if pts.size() >= 2 and pts[pts.size() - 1].distance_to(last) < min_dist_m:
			pts[pts.size() - 1] = last   # snap the kept tail onto the true endpoint
		else:
			pts.append(last)
	if pts.size() < 3:
		return pts
	# Pass 2: Douglas-Peucker keep-marking (deviation above the bound = a real bend).
	var keep := PackedByteArray()
	keep.resize(pts.size())
	keep[0] = 1
	keep[pts.size() - 1] = 1
	_dp_mark(pts, 0, pts.size() - 1, max_dev_m, keep)
	var out := PackedVector2Array()
	for i in range(pts.size()):
		if keep[i] == 1:
			out.append(pts[i])
	return out


## The same polyline translated by a constant XZ offset — a formation drag applies ONE
## shared delta to every model, so each model's true path is the anchor path shifted to
## its own base.
static func translated(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in range(points.size()):
		out[i] = points[i] + offset
	return out


## The polyline with the drop-RESOLVED final position appended (anti-stacking push-back /
## charge magnet-snap may nudge a base after the last drag sample): a real nudge becomes
## a final leg; a sub-millimetre difference just snaps the endpoint exactly onto it.
static func with_final(points: PackedVector2Array, final: Vector2,
		min_dist_m: float = 0.001) -> PackedVector2Array:
	var out := points.duplicate()
	if out.is_empty():
		out.append(final)
		return out
	if out[out.size() - 1].distance_to(final) >= min_dist_m:
		out.append(final)
	else:
		out[out.size() - 1] = final
	return out


## Min distance (metres) from a point to a polyline — the click-proof hit test (a click
## within the trail's half-width + margin selects it).
static func distance_to_polyline_m(p: Vector2, points: PackedVector2Array) -> float:
	if points.is_empty():
		return INF
	if points.size() == 1:
		return p.distance_to(points[0])
	var best := INF
	for i in range(1, points.size()):
		var a := points[i - 1]
		var ab := points[i] - a
		var len2 := ab.length_squared()
		var d: float
		if len2 < 0.000000001:
			d = p.distance_to(a)
		else:
			var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
			d = p.distance_to(a + ab * t)
		best = minf(best, d)
	return best


# ===== Recording (P1) =====

## Record one executed move: unit, model, polyline, measured arc length, round and
## timestamp. Returns the appended entry (the caller stamps entry["inches"] onto the
## visible trail). `points` is duplicated — the entry owns its data.
func record(owner: int, unit_key: String, unit_name: String, model_id: int,
		points: PackedVector2Array, round_num: int) -> Dictionary:
	var entry := {
		"owner": owner,
		"unit": unit_key,
		"unit_name": unit_name,
		"model": model_id,
		"points": points.duplicate(),
		"inches": length_inches(points),
		"round": round_num,
		"ts_ms": Time.get_ticks_msec(),
	}
	entries.append(entry)
	return entry


## All recorded entries for one unit (proof lookup / later receipt stages).
func entries_for_unit(unit_key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in entries:
		if str(entry.get("unit", "")) == unit_key:
			out.append(entry)
	return out


# ===== Activation-end clearing (the visible-trail rules) =====

## A move for `unit_key` (owned by `owner`) was committed as part of drop `drop_id`.
## Returns the unit keys whose ACTIVATION JUST ENDED — the caller fades their trails.
## Same drop_id = the same physical drop (possibly spanning units, and re-used verbatim
## by the MP messages so both sides fade identically); a NEW drop by the same owner ends
## the previous activation of every unit not part of it.
func note_commit(owner: int, unit_key: String, drop_id: int) -> PackedStringArray:
	var fade := PackedStringArray()
	var cur: Dictionary = _active.get(owner, {})
	if not cur.is_empty() and int(cur.get("drop", -1)) == drop_id:
		var units: PackedStringArray = cur.get("units", PackedStringArray())
		if not units.has(unit_key):
			units.append(unit_key)
			cur["units"] = units
		return fade
	for k in cur.get("units", PackedStringArray()):
		if k != unit_key:
			fade.append(k)
	_active[owner] = {"drop": drop_id, "units": PackedStringArray([unit_key])}
	return fade


## The unit was marked Activated (locally or via MP sync) — its activation is DONE, the
## trail's caller-side fade follows. Removes the unit from every owner's active set so a
## later commit doesn't try to fade it again.
func note_activation_done(unit_key: String) -> void:
	for owner in _active:
		var cur: Dictionary = _active[owner]
		var units: PackedStringArray = cur.get("units", PackedStringArray())
		var idx := units.find(unit_key)
		if idx >= 0:
			units.remove_at(idx)
			cur["units"] = units


## Round advance clears every activation (OPR bookkeeping) — all visible trails end.
## Ledger ENTRIES persist (round-tagged) for the later receipt/replay stages.
func note_round_advance() -> void:
	clear_active()


## Reset the visible-trail activation tracking (round advance / manual clear-all).
func clear_active() -> void:
	_active.clear()


# ===== Internals =====

## Douglas-Peucker keep-marking between kept indices i0..i1: the sample furthest from
## the chord is a real bend when beyond eps — keep it and recurse both halves.
static func _dp_mark(pts: PackedVector2Array, i0: int, i1: int, eps: float,
		keep: PackedByteArray) -> void:
	if i1 <= i0 + 1:
		return
	var a := pts[i0]
	var ab := pts[i1] - a
	var len2 := ab.length_squared()
	var worst := -1.0
	var worst_i := -1
	for i in range(i0 + 1, i1):
		var d: float
		if len2 < 0.000000001:
			d = pts[i].distance_to(a)
		else:
			var t := clampf((pts[i] - a).dot(ab) / len2, 0.0, 1.0)
			d = pts[i].distance_to(a + ab * t)
		if d > worst:
			worst = d
			worst_i = i
	if worst > eps and worst_i > 0:
		keep[worst_i] = 1
		_dp_mark(pts, i0, worst_i, eps, keep)
		_dp_mark(pts, worst_i, i1, eps, keep)
