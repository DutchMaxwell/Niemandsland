class_name MovementPlanner
extends RefCounted
## Pure, headless movement planner for the Solo-AI — a sim-shareable module in the same family as
## AiDecision / TerrainRules (static, no scene / mesh / physics dependency, deterministic). It replaces the
## rigid formation slide with INDIVIDUAL-MODEL steering: each model steers toward its own goal while the
## unit is kept in COHERENCY, thin WALL segments are treated as impassable barriers models slide around,
## and a model boxed in by walls is rescued with a local A* on the 3" grid. It is the shared plan-WHERE
## brain; the sim (SoloSim) applies the resulting positions, and the real game may reuse it later.
##
## Rules cited (all distances in INCHES here; the module is unit-agnostic like TerrainRules):
##   • Coherency (CoherencyChecker.gd, GF Advanced Rules v3.5.1 p.7): models form an uninterrupted 1"
##     model-to-model chain and stay within 9" of every other model. CoherencyChecker measures edge-to-edge
##     with per-model base geometry; the sim's models are POINTS, so we fold a nominal base allowance
##     (BASE_CONTACT_IN, the sim's base-contact centre distance == SoloSim.CONTACT_IN) into centre-to-centre
##     thresholds: two models LINK within BASE_CONTACT_IN + 1", and the unit's spread may reach
##     BASE_CONTACT_IN + 9". Same rule, point-model form. Do not fork the 1"/9" numbers from CoherencyChecker.
##   • Movement / 1" enemy spacing (p.7) stays owned by SoloSim (its shipped magnitude clamp); the planner
##     only ever SHORTENS the per-model travel, never pushes a model past its allowance, so a spacing- and
##     Difficult-clamped delta handed in here is preserved. A Charge (allow_contact) is exempt from spacing.
##   • Walls = Impassable (terrain_overlay.gd wall segments): a thin segment blocks a model's path. The sim's
##     wall layer mirrors terrain_overlay._last_wall_segments as a list of [Vector2 a, Vector2 b] pairs.
##   • Terrain grid: the same typed 3" cells as TerrainRules (CONTAINER = Impassable) — used by the A* rescue.

const EPS := 0.0001

# --- Coherency (mirrors CoherencyChecker; folded into centre-to-centre point space) ---
const BASE_CONTACT_IN := 2.0                # centre-to-centre distance at base contact (== SoloSim.CONTACT_IN)
const COHERENCY_IN := 1.0                   # CoherencyChecker.COHERENCY_DISTANCE_INCHES (1" model-to-model)
const MAX_CHAIN_IN := 9.0                   # CoherencyChecker.MAX_CHAIN_DISTANCE_INCHES (9" max spread)
const LINK_IN := BASE_CONTACT_IN + COHERENCY_IN     # two points count as a coherency link within this
const SPREAD_IN := BASE_CONTACT_IN + MAX_CHAIN_IN   # the unit's furthest pair may reach this

# --- Steering ---
const STEP_IN := 0.75                       # per-substep travel: fine enough to hug a wall, coarse enough to be fast
const STUCK_FRACTION := 0.25                # steering that advances the anchor < this fraction of the intended move = stuck → A*
const COH_PULL_IN := 1.0                    # per-pass inward pull when restoring coherency
const COH_PASSES := 8                       # max coherency-restore passes (bounds the pull to COH_PASSES × COH_PULL_IN)
# Deflection fan for wall-sliding: straight first, then widening turns to either side (degrees).
const SLIDE_ANGLES: Array[float] = [0.0, 20.0, -20.0, 45.0, -45.0, 70.0, -70.0, 90.0, -90.0]


# === Public geometry: wall-segment intersection =============================================

## Signed area ×2 of triangle abc — >0 left turn, <0 right turn, ~0 collinear.
static func _orient(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)


## True if collinear point p lies within the bounding box of segment a→b.
static func _on_segment(a: Vector2, b: Vector2, p: Vector2) -> bool:
	return p.x >= minf(a.x, b.x) - EPS and p.x <= maxf(a.x, b.x) + EPS \
		and p.y >= minf(a.y, b.y) - EPS and p.y <= maxf(a.y, b.y) + EPS


## Do segments p1→p2 and p3→p4 intersect (including touching / collinear overlap)? Standard orientation
## test; touching counts as crossing so a path that grazes a wall end is still treated as blocked (safe side).
static func segments_cross(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	var d1 := _orient(p3, p4, p1)
	var d2 := _orient(p3, p4, p2)
	var d3 := _orient(p1, p2, p3)
	var d4 := _orient(p1, p2, p4)
	if ((d1 > 0.0 and d2 < 0.0) or (d1 < 0.0 and d2 > 0.0)) \
			and ((d3 > 0.0 and d4 < 0.0) or (d3 < 0.0 and d4 > 0.0)):
		return true
	if absf(d1) <= EPS and _on_segment(p3, p4, p1):
		return true
	if absf(d2) <= EPS and _on_segment(p3, p4, p2):
		return true
	if absf(d3) <= EPS and _on_segment(p1, p2, p3):
		return true
	if absf(d4) <= EPS and _on_segment(p1, p2, p4):
		return true
	return false


## Endpoints of a wall segment (accepts [a, b] pairs or {"a":, "b":} dictionaries).
static func _wall_a(w: Variant) -> Vector2:
	if w is Array:
		return (w as Array)[0]
	return (w as Dictionary).get("a", Vector2.ZERO)


static func _wall_b(w: Variant) -> Vector2:
	if w is Array:
		return (w as Array)[1]
	return (w as Dictionary).get("b", Vector2.ZERO)


## True if the straight path a→b crosses ANY wall segment (walls are impassable).
static func path_crosses_wall(a: Vector2, b: Vector2, walls: Array) -> bool:
	for w in walls:
		if segments_cross(a, b, _wall_a(w), _wall_b(w)):
			return true
	return false


# === Public coherency predicate (mirrors CoherencyChecker, point-model form) ================

static func _are_linked(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) <= LINK_IN


## Connected components of the 1"-link graph, as arrays of indices into `model_pos` (BFS; mirrors
## CoherencyChecker._connected_components).
static func _components(model_pos: Array) -> Array:
	var n := model_pos.size()
	var visited: Array[bool] = []
	visited.resize(n)
	visited.fill(false)
	var comps: Array = []
	for start in range(n):
		if visited[start]:
			continue
		var comp: Array = [start]
		var queue: Array = [start]
		visited[start] = true
		while not queue.is_empty():
			var cur: int = queue.pop_back()
			for other in range(n):
				if visited[other] or other == cur:
					continue
				if _are_linked(model_pos[cur], model_pos[other]):
					visited[other] = true
					queue.append(other)
					comp.append(other)
		comps.append(comp)
	return comps


static func _largest(comps: Array) -> Array:
	var best: Array = comps[0]
	for c in comps:
		if (c as Array).size() > best.size():
			best = c
	return best


## Furthest-apart pair distance (the unit's spread), mirroring CoherencyChecker._get_max_spread_pair.
static func _spread(model_pos: Array) -> float:
	var worst := 0.0
	for i in range(model_pos.size()):
		for j in range(i + 1, model_pos.size()):
			worst = maxf(worst, (model_pos[i] as Vector2).distance_to(model_pos[j]))
	return worst


## OPR coherency (p.7): a single connected 1"-chain AND spread within 9" (folded into point space). A unit
## of 0/1 model is trivially coherent.
static func is_coherent(model_pos: Array) -> bool:
	if model_pos.size() <= 1:
		return true
	if _components(model_pos).size() > 1:
		return false
	return _spread(model_pos) <= SPREAD_IN + EPS


# === Public entry: plan one move step =======================================================

static func _centroid(model_pos: Array) -> Vector2:
	if model_pos.is_empty():
		return Vector2.ZERO
	var s := Vector2.ZERO
	for m in model_pos:
		s += m as Vector2
	return s / float(model_pos.size())


## True if the plain rigid translation by `delta` would drive any model's straight path through a wall.
## When false the caller can safely apply the exact rigid move (SoloSim keeps its fast path this way, so
## open-field play — and the mirror-fairness oracle — is byte-identical to the pre-planner behaviour).
static func rigid_blocked(model_pos: Array, delta: Vector2, walls: Array) -> bool:
	if walls.is_empty() or delta == Vector2.ZERO:
		return false
	for m in model_pos:
		if path_crosses_wall(m, (m as Vector2) + delta, walls):
			return true
	return false


## Plan the next per-model positions for a unit moving by the (already spacing/Difficult-clamped) rigid
## `delta`. Each model steers toward its own rigid target (model + delta), never crossing a wall, capped at
## |delta| of travel; the unit is pulled back into coherency; and if the formation is boxed in (walls stop
## it advancing) a local A* on the 3" grid finds a corridor and the models steer toward its farthest visible
## waypoint. Returns a NEW Array[Vector2] (same length/order as model_pos). Pure + deterministic.
##   model_pos     : current per-model positions (inches)
##   delta         : intended rigid translation (its length is the per-model move allowance)
##   walls         : Array of [Vector2 a, Vector2 b] impassable segments (empty = open field)
##   grid          : TerrainRules typed 3" cells (for the A* rescue; CONTAINER = impassable)
##   allow_contact : Charge — exempt from spacing (handled by SoloSim; here it only skips coherency easing)
##   board_in      : board extent in inches (A* bounds + off-board rejection)
##   trails        : OPTIONAL out-array — when provided it is filled with one Array[Vector2] of substep
##                   waypoints per model (start … final), so the game can ANIMATE each model along its
##                   real steering route (goal 003 presentation layer). Pure observation: passing it
##                   changes NOTHING about the planned positions (the sim never passes it, so the
##                   mirror-fairness proof is untouched).
static func plan_unit_step(model_pos: Array, delta: Vector2, walls: Array, grid: Dictionary = {},
		allow_contact: bool = false, board_in: float = 48.0, trails: Array = []) -> Array:
	var allowance := delta.length()
	if allowance < EPS or model_pos.is_empty():
		return model_pos.duplicate()
	# Fast path: no wall in the way → the exact rigid slide (keeps open-field play identical).
	if not rigid_blocked(model_pos, delta, walls):
		var out: Array = []
		for m in model_pos:
			out.append((m as Vector2) + delta)
		_record_trail_pair(trails, model_pos, out)
		return out
	# Steer each model to its rigid target, sliding around walls.
	var targets: Array = []
	for m in model_pos:
		targets.append((m as Vector2) + delta)
	var result := _steer(model_pos, targets, allowance, walls, board_in, trails)
	# Boxed in? The anchor barely progressed and the direct route is walled → A* corridor rescue.
	var anchor := _centroid(model_pos)
	var goal := anchor + delta
	if _unit_stuck(model_pos, result, delta) and path_crosses_wall(anchor, goal, walls):
		var corridor := astar_corridor(anchor, goal, walls, grid, board_in)
		if not corridor.is_empty():
			# Aim at the farthest corridor waypoint reachable in a straight (wall-free) line — string-pulling.
			var aim: Vector2 = corridor[0]
			for w in corridor:
				if path_crosses_wall(anchor, w as Vector2, walls):
					break
				aim = w
			var wdelta := aim - anchor
			if wdelta.length() > allowance:
				wdelta = wdelta.normalized() * allowance
			var wtargets: Array = []
			for m in model_pos:
				wtargets.append((m as Vector2) + wdelta)
			trails.clear()   # the rescue replaces the stuck first attempt — its trail too
			result = _steer(model_pos, wtargets, allowance, walls, board_in, trails)
	var eased := _enforce_coherency(result, walls, board_in)
	_append_trail_finals(trails, eased)
	return eased


## Trail helper: the fast rigid slide is a single straight leg per model.
static func _record_trail_pair(trails: Array, from_pos: Array, to_pos: Array) -> void:
	if trails == null:
		return
	trails.clear()
	for i in range(from_pos.size()):
		trails.append([from_pos[i], to_pos[i]])


## Trail helper: append the post-coherency final position when it differs from the last waypoint.
static func _append_trail_finals(trails: Array, finals: Array) -> void:
	if trails == null or trails.is_empty():
		return
	for i in range(mini(trails.size(), finals.size())):
		var t := trails[i] as Array
		if t.is_empty() or (t.back() as Vector2).distance_to(finals[i]) > EPS:
			t.append(finals[i])


# === Steering internals =====================================================================

## One reachable substep from `p` toward `target`: try straight, then a widening deflection fan, and take
## the candidate that lands closest to the target without crossing a wall or leaving the board. Returns `p`
## unchanged when every direction is blocked (a stuck model — feeds the A* trigger).
static func _advance_model(p: Vector2, target: Vector2, step_cap: float, walls: Array, board_in: float) -> Vector2:
	var to_t := target - p
	var d := to_t.length()
	if d < EPS or step_cap < EPS:
		return p
	var step_len := minf(step_cap, d)
	var dir := to_t / d
	var best := p
	var best_d := INF
	for ang in SLIDE_ANGLES:
		var s := dir.rotated(deg_to_rad(ang)) * step_len
		var c := p + s
		if c.x < -EPS or c.x > board_in + EPS or c.y < -EPS or c.y > board_in + EPS:
			continue
		if path_crosses_wall(p, c, walls):
			continue
		var dd := c.distance_to(target)
		if dd < best_d - EPS:
			best_d = dd
			best = c
		elif best_d < INF and absf(dd - best_d) <= EPS:
			# A tie (a symmetric obstacle deflects equally to either side): break it on the WORLD frame (smaller
			# x, then y), not on the rotation sign. A sign-based tie-break is chiral — it steers a north-bound
			# unit to the opposite side of a wall from its mirror-image south-bound unit, which quietly biases a
			# mirror match. The world-canonical choice is invariant under the board's reflection symmetry.
			if c.x < best.x - EPS or (absf(c.x - best.x) <= EPS and c.y < best.y - EPS):
				best = c
	return best


## Advance every model toward its target in fixed substeps until each spends its allowance. Deterministic.
## `trails` (optional out): one waypoint list per model, recording each substep position — observation
## only, never feeds back into the steering.
static func _steer(model_pos: Array, targets: Array, allowance: float, walls: Array, board_in: float,
		trails: Array = []) -> Array:
	var n := model_pos.size()
	var result := model_pos.duplicate()
	var budget: Array = []
	budget.resize(n)
	budget.fill(allowance)
	if trails != null:
		trails.clear()
		for i in range(n):
			trails.append([model_pos[i]])
	var substeps := maxi(1, int(ceil(allowance / STEP_IN)))
	for _it in range(substeps):
		var moved_any := false
		for i in range(n):
			if budget[i] <= EPS:
				continue
			var np := _advance_model(result[i], targets[i], minf(STEP_IN, budget[i]), walls, board_in)
			var moved: float = (result[i] as Vector2).distance_to(np)
			if moved > EPS:
				result[i] = np
				budget[i] = float(budget[i]) - moved
				moved_any = true
				if trails != null and i < trails.size():
					(trails[i] as Array).append(np)
		if not moved_any:
			break
	return result


## The unit is "stuck" when its anchor advanced less than STUCK_FRACTION of the intended move along the goal
## direction — i.e. walls stopped the steering from making real progress, so an A* corridor is worth finding.
static func _unit_stuck(before: Array, after: Array, delta: Vector2) -> bool:
	var intended := delta.length()
	if intended < EPS:
		return false
	var progress := (_centroid(after) - _centroid(before)).dot(delta / intended)
	return progress < STUCK_FRACTION * intended


## Restore coherency after sliding: pull models that fell out of the main 1"-chain (or beyond the 9" spread)
## toward the centroid in small wall-checked steps. Monotonic (only ever moves models closer together) so it
## can never cross a wall or worsen coherency. Best-effort — bounded by COH_PASSES × COH_PULL_IN.
static func _enforce_coherency(result: Array, walls: Array, board_in: float) -> Array:
	var out := result.duplicate()
	if out.size() <= 1:
		return out
	for _pass in range(COH_PASSES):
		var bad := _incoherent_indices(out)
		if bad.is_empty():
			break
		var c := _centroid(out)
		for i in bad:
			var to_c := c - (out[i] as Vector2)
			var d := to_c.length()
			if d < EPS:
				continue
			var cand: Vector2 = (out[i] as Vector2) + to_c / d * minf(COH_PULL_IN, d)
			if cand.x < -EPS or cand.x > board_in + EPS or cand.y < -EPS or cand.y > board_in + EPS:
				continue
			if not path_crosses_wall(out[i], cand, walls):
				out[i] = cand
	return out


## Indices that break coherency: every model outside the largest 1"-component, plus (if the spread is too
## wide) the single model furthest from the centroid — pulling those in shrinks the spread.
static func _incoherent_indices(model_pos: Array) -> Array:
	var bad: Array = []
	var comps := _components(model_pos)
	if comps.size() > 1:
		var main := _largest(comps)
		var in_main := {}
		for idx in main:
			in_main[idx] = true
		for i in range(model_pos.size()):
			if not in_main.has(i):
				bad.append(i)
	if _spread(model_pos) > SPREAD_IN + EPS:
		var c := _centroid(model_pos)
		var far := -1
		var far_d := -1.0
		for i in range(model_pos.size()):
			var d: float = (model_pos[i] as Vector2).distance_to(c)
			if d > far_d:
				far_d = d
				far = i
		if far >= 0 and not bad.has(far):
			bad.append(far)
	return bad


# === Local A* on the 3" grid (the wall-rescue path) =========================================

static func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2((float(cell.x) + 0.5) * TerrainRules.CELL_IN, (float(cell.y) + 0.5) * TerrainRules.CELL_IN)


## A* from `start` to `goal` on the 3" grid, 4-connected. An edge between adjacent cells is blocked when the
## centre-to-centre segment crosses a wall; a cell is blocked when it is off-board or Impassable (CONTAINER).
## Returns the corridor as cell-CENTRE points AFTER the start cell (empty if none / already there). The wall
## barrier the steering hit is thereby routed around. Bounded by the board so it always terminates.
static func astar_corridor(start: Vector2, goal: Vector2, walls: Array, grid: Dictionary = {},
		board_in: float = 48.0) -> Array:
	var start_cell := TerrainRules.cell_of(start)
	var goal_cell := TerrainRules.cell_of(goal)
	if start_cell == goal_cell:
		return []
	var n := int(board_in / TerrainRules.CELL_IN)
	var came_from := {}
	var g_score := {start_cell: 0.0}
	var open: Array = [start_cell]
	var closed := {}
	var neighbours := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not open.is_empty():
		# Pick the open cell with the lowest g + Manhattan heuristic (small grid → linear scan is fine).
		var best_i := 0
		var best_f := INF
		for k in range(open.size()):
			var cell: Vector2i = open[k]
			var f: float = float(g_score[cell]) + float(absi(cell.x - goal_cell.x) + absi(cell.y - goal_cell.y)) * TerrainRules.CELL_IN
			if f < best_f:
				best_f = f
				best_i = k
		var current: Vector2i = open[best_i]
		if current == goal_cell:
			return _reconstruct(came_from, current)
		open.remove_at(best_i)
		closed[current] = true
		var cc := _cell_center(current)
		for d in neighbours:
			var nb: Vector2i = current + d
			if nb.x < 0 or nb.x >= n or nb.y < 0 or nb.y >= n or closed.has(nb):
				continue
			if TerrainRules.is_impassable(int(grid.get(nb, TerrainRules.TerrainType.NONE))):
				continue
			if path_crosses_wall(cc, _cell_center(nb), walls):
				continue   # a wall sits on this cell edge → not traversable
			var tentative: float = float(g_score[current]) + TerrainRules.CELL_IN
			if not g_score.has(nb) or tentative < float(g_score[nb]):
				came_from[nb] = current
				g_score[nb] = tentative
				if not open.has(nb):
					open.append(nb)
	return []


## Walk `came_from` back to the start and return the cell CENTRES from the first step to `current`.
static func _reconstruct(came_from: Dictionary, current: Vector2i) -> Array:
	var cells: Array = [current]
	while came_from.has(current):
		current = came_from[current]
		cells.append(current)
	cells.reverse()
	var out: Array = []
	for i in range(1, cells.size()):   # drop the start cell — corridor waypoints only
		out.append(_cell_center(cells[i]))
	return out
