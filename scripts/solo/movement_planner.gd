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
# Laggard gather (real-game opts path only — the field-test "only half the unit moved" fix): a model that
# advanced along the goal by less than LAG_FRACTION of the unit's BEST forward progress is pulled up toward
# the moved formation so no model is left parked while the rest advance. Bounded, obstacle-checked, monotonic.
const LAG_FRACTION := 0.5
const GATHER_PASSES := 16                    # a fully-parked model may need to travel further than a coherency nudge
# Deflection fan for wall-sliding: straight first, then widening turns to either side (degrees).
const SLIDE_ANGLES: Array[float] = [0.0, 20.0, -20.0, 45.0, -45.0, 70.0, -70.0, 90.0, -90.0]

# === Unified formation pipeline (REAL-GAME PATH ONLY — gated on opts["radii"]) ================
# The pathfinding-research rewrite: configuration-space inflation + any-angle Theta* + funnel/string-pull +
# a UNIFIED constraint solver that satisfies base-separation, coherency, unit-spacing AND terrain-avoidance
# TOGETHER (iterative projection) instead of the competing separate passes that traded one constraint for
# another (self-play nightloop evidence). This branch runs ONLY when opts carries "radii" (the controller /
# self-play path); SoloSim passes empty opts and keeps the legacy steer+A* path byte-identical, so the
# mirror-fairness oracle is untouched. See docs: pathfinding_research.md §1.3/1.6/3.
const PLAN_CELL_IN := 1.0                    # any-angle search grid (~1"): matches the smallest base + OPR 1" granularity
const DIFFICULT_COST_MULT := 2.0            # Theta* soft cost: route AROUND Difficult when cheaper (research §1.3/3.3)
const DANGEROUS_COST_MULT := 3.0            # Dangerous costs more than Difficult, but is still traversable (not hard-blocked)
const THETA_DIAG := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]   # 8-connected (any-angle)
const SOLVE_PASSES := 24                     # iterative-projection sweeps (compact AI units converge well within this)
const TERRAIN_PUSH_MAX_IN := 6.0            # max radial search when projecting a model OUT of forbidden terrain
const TERRAIN_PUSH_STEP_IN := 0.5           # radial search granularity for the terrain-out projection
# Deterministic radial directions for terrain-out projection: 16 compass points, world-frame ordered so the
# nearest-valid tie-break stays canonical (research §4 — no rotation-sign/iteration-order chirality).
const RADIAL_DIRS := 16
# Least-violating-fallback weights: a config the solver can't make perfect is scored so the WORST classes
# (a model stuck in terrain, then a broken chain) are shed first — exactly the trade the nightloop rejected.
const W_TERRAIN := 100.0
const W_COHERENCY := 60.0
const W_OVERLAP := 40.0
const W_ZONE := 30.0


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


# === Base-aware obstacle checks (opt-in via `opts` — the sim passes none, so its behaviour is =========
# === byte-identical; the REAL game inflates obstacles by the moving model's base radius) ==============
#
# `opts` keys (all optional; {} = legacy point-model behaviour):
#   clearance   : float — the moving model's base radius + epsilon (inches). Walls become base-aware: a
#                 step may not bring the base's OUTER EDGE onto a wall (GF v3.5.1 p.7: models "may never
#                 move through" obstacles; the swept-corridor guarantee — no wall clipping, no shaving).
#   zones       : Array of {"c": Vector2, "r": float} no-go circles — enemy models inflated by their base
#                 radius + 1" + the mover's radius (GF v3.5.1 p.7: "Models may never be within 1” of
#                 models from OTHER UNITS — friendly AND enemy — unless charging"). A step may neither
#                 cross a zone nor end inside one; a model that starts inside (legacy state) may only
#                 move OUT.
#   avoid_cells : Dictionary(Vector2i -> true) — grid cells steering/A* must not enter (Difficult terrain
#                 when the route should go AROUND it — GF v3.5.1 solo overlay p.57: AI units "must always
#                 move around" difficult terrain — plus Impassable cells). A model already inside an
#                 avoided cell may step freely (escape allowed).

## Distance from point p to segment a→b.
static func point_seg_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < EPS * EPS:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Minimum distance between segments p1→p2 and q1→q2 (0 when they cross).
static func seg_seg_distance(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2) -> float:
	if segments_cross(p1, p2, q1, q2):
		return 0.0
	return minf(minf(point_seg_distance(p1, q1, q2), point_seg_distance(p2, q1, q2)),
		minf(point_seg_distance(q1, p1, p2), point_seg_distance(q2, p1, p2)))


## Base-aware wall check for one step p→c: a crossing always blocks; with clearance > 0 the step may not
## dip within `clearance` of the wall (the base edge would shave it) — unless the model STARTS inside the
## inflated band (pre-existing state), where only distance-improving escape steps are allowed.
static func _wall_blocks(p: Vector2, c: Vector2, wa: Vector2, wb: Vector2, clearance: float) -> bool:
	if segments_cross(p, c, wa, wb):
		return true
	if clearance <= 0.0:
		return false
	if seg_seg_distance(p, c, wa, wb) >= clearance:
		return false
	var d_p := point_seg_distance(p, wa, wb)
	if d_p >= clearance - EPS:
		return true   # started clear of the inflated wall → any dip inside is a clip
	return point_seg_distance(c, wa, wb) <= d_p + EPS   # inside already: only escaping steps allowed


## No-go circle check for one step p→c: the step may not cross the circle nor end inside it; a model
## starting inside may only move outward (escape).
static func _zone_blocks(p: Vector2, c: Vector2, centre: Vector2, r: float) -> bool:
	if point_seg_distance(centre, p, c) >= r:
		return false
	var d_p := p.distance_to(centre)
	if d_p >= r - EPS:
		return true   # entered / clipped the zone from outside
	return c.distance_to(centre) <= d_p + EPS   # inside already: only escaping steps allowed


## Combined step check: walls (base-aware), no-go zones, and avoided grid cells. `opts` = {} is exactly
## the legacy path_crosses_wall behaviour.
static func step_blocked(p: Vector2, c: Vector2, walls: Array, opts: Dictionary) -> bool:
	var clearance: float = float(opts.get("clearance", 0.0))
	if clearance > 0.0:
		for w in walls:
			if _wall_blocks(p, c, _wall_a(w), _wall_b(w), clearance):
				return true
	elif path_crosses_wall(p, c, walls):
		return true
	for z in opts.get("zones", []):
		var zd := z as Dictionary
		if _zone_blocks(p, c, zd.get("c", Vector2.ZERO), float(zd.get("r", 0.0))):
			return true
	var avoid: Dictionary = opts.get("avoid_cells", {})
	if not avoid.is_empty():
		if avoid.has(TerrainRules.cell_of(c)) and not avoid.has(TerrainRules.cell_of(p)):
			return true
	return false


## Distance between two consecutive polyline points (Vector2 or Vector3 — typed branches, no dynamic call).
static func _point_dist(a: Variant, b: Variant) -> float:
	if a is Vector3:
		return (a as Vector3).distance_to(b as Vector3)
	return (a as Vector2).distance_to(b as Vector2)


static func _point_lerp(a: Variant, b: Variant, t: float) -> Variant:
	if a is Vector3:
		return (a as Vector3).lerp(b as Vector3, t)
	return (a as Vector2).lerp(b as Vector2, t)


## Arc length of a waypoint polyline (Vector2 or Vector3 points).
static func polyline_length(points: Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += _point_dist(points[i - 1], points[i])
	return total


## Trim a polyline so its arc length never exceeds `max_len` (GF v3.5.1 p.7: "no part of their bases move
## further than the total movement distance") — the distance-truth clamp. Walks the legs and cuts the
## final leg at the exact remaining budget. Works on Vector2 or Vector3 points; returns a NEW array.
static func trim_polyline(points: Array, max_len: float) -> Array:
	if points.size() <= 1:
		return points.duplicate()
	if max_len <= 0.0:
		return [points[0]]
	var out: Array = [points[0]]
	var spent := 0.0
	for i in range(1, points.size()):
		var leg: float = _point_dist(points[i - 1], points[i])
		if leg <= EPS:
			continue
		if spent + leg <= max_len + EPS:
			out.append(points[i])
			spent += leg
			continue
		var frac := (max_len - spent) / leg
		if frac > EPS:
			out.append(_point_lerp(points[i - 1], points[i], frac))
		break
	return out


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


# === Final formation guarantees (real-game path only — see solo_controller._plan_positions) ==========

const COHERENCY_BISECT_STEPS := 14   # 2^-14 ≈ 0.006% of the move — a tight yet cheap "shorten just enough"

## Push a unit's OWN models apart until no two bases overlap (GF/AoF Advanced Rules v3.5.1 p.7: models "may
## never move through other models or units, friendly or enemy"). `model_pos` are base CENTRES and
## `radii_in[i]` the matching base radius (same unit + index order); a pair whose centre gap is below
## radius[i]+radius[j] is separated along its centre line, split evenly, each half wall/zone-checked via
## `opts` (a push that would clip a wall or enter another unit's no-go zone is skipped for that model). A
## few relaxation passes converge for the compact formations the AI moves. Pure + deterministic; returns a
## NEW Array[Vector2]. The sim keeps dimensionless point models (no base overlap notion), so it never calls
## this — its planned positions stay byte-identical.
static func separate_overlaps(model_pos: Array, radii_in: Array, walls: Array, opts: Dictionary = {}, passes: int = 8) -> Array:
	var out := model_pos.duplicate()
	var n := out.size()
	if n <= 1 or radii_in.size() != n:
		return out
	for _pass in range(passes):
		var moved := false
		for i in range(n):
			for j in range(i + 1, n):
				var pi := out[i] as Vector2
				var pj := out[j] as Vector2
				var min_gap: float = float(radii_in[i]) + float(radii_in[j])
				var d := pi.distance_to(pj)
				if d >= min_gap - EPS:
					continue
				var dir := pj - pi
				# Coincident centres: separate along a deterministic axis biased by index so both move apart.
				dir = dir.normalized() if dir.length() > EPS else Vector2(1.0, 0.0)
				var push := (min_gap - d) * 0.5 + EPS
				var ci := pi - dir * push
				var cj := pj + dir * push
				if not step_blocked(pi, ci, walls, opts):
					out[i] = ci
					moved = true
				if not step_blocked(pj, cj, walls, opts):
					out[j] = cj
					moved = true
		if not moved:
			break
	return out


## Shorten a planned move back toward its (coherent) START just enough to end in coherency (GF/AoF Advanced
## Rules v3.5.1 p.7 unit coherency; field-test finding 4: an AI move ended out of coherency). The unit began
## coherent, so blend factor 0 (no move) is always coherent — the bisection therefore ALWAYS returns a
## coherent result, moving as far as coherency allows and no further ("or as close as possible"). No-op when
## the full move is already coherent. Pure; returns a NEW Array[Vector2]. NOT applied to Charges (they must
## reach base contact — the caller gates on allow_contact).
static func shorten_to_coherent(start_pos: Array, planned_pos: Array) -> Array:
	if planned_pos.size() <= 1 or start_pos.size() != planned_pos.size():
		return planned_pos.duplicate()
	if is_coherent(planned_pos):
		return planned_pos.duplicate()
	var lo := 0.0   # known coherent (the start formation)
	var hi := 1.0   # the full planned move (currently incoherent)
	for _b in range(COHERENCY_BISECT_STEPS):
		var mid := (lo + hi) * 0.5
		if is_coherent(_blend(start_pos, planned_pos, mid)):
			lo = mid
		else:
			hi = mid
	return _blend(start_pos, planned_pos, lo)


## Per-model linear blend of two same-length position arrays at t (0 = a, 1 = b).
static func _blend(a: Array, b: Array, t: float) -> Array:
	var out: Array = []
	for i in range(a.size()):
		out.append((a[i] as Vector2).lerp(b[i] as Vector2, t))
	return out


# === Public entry: plan one move step =======================================================

static func _centroid(model_pos: Array) -> Vector2:
	if model_pos.is_empty():
		return Vector2.ZERO
	var s := Vector2.ZERO
	for m in model_pos:
		s += m as Vector2
	return s / float(model_pos.size())


## True if the plain rigid translation by `delta` would drive any model's straight path through a wall —
## or, with `opts`, shave an inflated wall / cross a no-go zone / enter an avoided cell. When false the
## caller can safely apply the exact rigid move (SoloSim passes no opts and keeps its fast path, so
## open-field play — and the mirror-fairness oracle — is byte-identical to the pre-planner behaviour).
static func rigid_blocked(model_pos: Array, delta: Vector2, walls: Array, opts: Dictionary = {}) -> bool:
	if delta == Vector2.ZERO:
		return false
	if walls.is_empty() and opts.is_empty():
		return false
	for m in model_pos:
		var a := m as Vector2
		var b := a + delta
		if step_blocked(a, b, walls, opts):
			return true
		# A long rigid leg can pass THROUGH an avoided cell with both endpoints outside it — sample the
		# leg at sub-cell intervals so the fast path never silently tunnels difficult/impassable cells.
		var avoid: Dictionary = opts.get("avoid_cells", {})
		if not avoid.is_empty() and not avoid.has(TerrainRules.cell_of(a)):
			var steps := maxi(1, int(ceil(delta.length() / (TerrainRules.CELL_IN * 0.5))))
			for s in range(1, steps):
				if avoid.has(TerrainRules.cell_of(a.lerp(b, float(s) / float(steps)))):
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
		allow_contact: bool = false, board_in: float = 48.0, trails: Array = [], opts: Dictionary = {}) -> Array:
	var allowance := delta.length()
	if allowance < EPS or model_pos.is_empty():
		return model_pos.duplicate()
	# Real-game formation path: when opts carries per-model "radii" the caller (SoloController / self-play)
	# wants the UNIFIED pipeline — configuration-space Theta*/funnel routing + a single constraint solver that
	# resolves base-separation, coherency, unit-spacing and terrain-avoidance TOGETHER. SoloSim never passes
	# radii, so its steer+A* path below (and the mirror-fairness oracle) is byte-identical.
	if opts.has("radii"):
		return _plan_unit_step_unified(model_pos, delta, walls, grid, allow_contact, board_in, trails, opts)
	# Fast path: nothing in the way → the exact rigid slide (keeps open-field play identical).
	if not rigid_blocked(model_pos, delta, walls, opts):
		var out: Array = []
		for m in model_pos:
			out.append((m as Vector2) + delta)
		_record_trail_pair(trails, model_pos, out)
		return out
	# Steer each model to its rigid target, sliding around obstacles.
	var targets: Array = []
	for m in model_pos:
		targets.append((m as Vector2) + delta)
	var result := _steer(model_pos, targets, allowance, walls, board_in, trails, opts)
	# Boxed in? The anchor barely progressed and the direct route is blocked → A* corridor rescue.
	var anchor := _centroid(model_pos)
	var goal := anchor + delta
	if _unit_stuck(model_pos, result, delta) and step_blocked(anchor, goal, walls, opts):
		var corridor := astar_corridor(anchor, goal, walls, grid, board_in, opts)
		if not corridor.is_empty():
			# Aim at the farthest corridor waypoint reachable in a straight (unblocked) line — string-pulling.
			var aim: Vector2 = corridor[0]
			for w in corridor:
				if step_blocked(anchor, w as Vector2, walls, opts):
					break
				aim = w
			var wdelta := aim - anchor
			if wdelta.length() > allowance:
				wdelta = wdelta.normalized() * allowance
			var wtargets: Array = []
			for m in model_pos:
				wtargets.append((m as Vector2) + wdelta)
			trails.clear()   # the rescue replaces the stuck first attempt — its trail too
			result = _steer(model_pos, wtargets, allowance, walls, board_in, trails, opts)
	# Real-game path (opts present): before the coherency ease, pull up any model the obstacle-steering
	# left behind so EVERY model advances with the unit (field-test finding 2: only half the unit moved).
	# The SIM passes no opts and keeps the pure coherency ease, so its planned positions are byte-identical.
	var gathered := _gather_laggards(model_pos, result, delta, walls, board_in, opts) if not opts.is_empty() else result
	var eased := _enforce_coherency(gathered, walls, board_in, opts)
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
static func _advance_model(p: Vector2, target: Vector2, step_cap: float, walls: Array, board_in: float,
		opts: Dictionary = {}) -> Vector2:
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
		if step_blocked(p, c, walls, opts):
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
		trails: Array = [], opts: Dictionary = {}) -> Array:
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
			var np := _advance_model(result[i], targets[i], minf(STEP_IN, budget[i]), walls, board_in, opts)
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
static func _enforce_coherency(result: Array, walls: Array, board_in: float, opts: Dictionary = {}) -> Array:
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
			# The pull must respect the same obstacles as the steering (a coherency correction may not
			# clip a wall or drag a model into an enemy 1" zone).
			if not step_blocked(out[i], cand, walls, opts):
				out[i] = cand
	return out


## Pull up the models the obstacle-steering left behind (field-test finding 2: "only half the unit moved").
## A model whose forward progress along the goal is below LAG_FRACTION of the unit's BEST progress is a
## laggard — it steered into an obstacle and stalled while its neighbours advanced. Each pass moves every
## current laggard one COH_PULL_IN step toward the moved formation's centroid (which sits AHEAD of the
## laggards once the rest advanced), obstacle-checked and monotonic, so it can never clip a wall, enter an
## enemy zone or overshoot. Real-game path only (the caller gates on non-empty opts). The distance-truth
## trim in the caller still caps every model's arc at its allowance, so a gathered model never moves too far.
static func _gather_laggards(before: Array, result: Array, delta: Vector2, walls: Array,
		board_in: float, opts: Dictionary) -> Array:
	var out := result.duplicate()
	if out.size() <= 1 or delta.length() < EPS:
		return out
	var dir := delta / delta.length()
	var best_prog := 0.0
	for i in range(out.size()):
		best_prog = maxf(best_prog, ((out[i] as Vector2) - (before[i] as Vector2)).dot(dir))
	if best_prog < EPS:
		return out   # the WHOLE unit stalled (genuinely boxed in) — nothing to catch up to
	var lag_target := LAG_FRACTION * best_prog
	for _pass in range(GATHER_PASSES):
		var c := _centroid(out)
		var moved := false
		for i in range(out.size()):
			if ((out[i] as Vector2) - (before[i] as Vector2)).dot(dir) >= lag_target:
				continue   # this model kept up with the unit's advance
			var to_c := c - (out[i] as Vector2)
			var d := to_c.length()
			if d < EPS:
				continue
			var cand: Vector2 = (out[i] as Vector2) + to_c / d * minf(COH_PULL_IN, d)
			if cand.x < -EPS or cand.x > board_in + EPS or cand.y < -EPS or cand.y > board_in + EPS:
				continue
			if not step_blocked(out[i], cand, walls, opts):
				out[i] = cand
				moved = true
		if not moved:
			break
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


## A* from `start` to `goal` on the 3" grid, 4-connected. An edge between adjacent cells is blocked when
## the centre-to-centre segment is blocked (wall crossing; with `opts` also base-clearance shaves and
## no-go zones); a cell is blocked when it is off-board, Impassable (CONTAINER) or in opts.avoid_cells.
## Returns the corridor as cell-CENTRE points AFTER the start cell (empty if none / already there). The
## barrier the steering hit is thereby routed around. Bounded by the board so it always terminates.
static func astar_corridor(start: Vector2, goal: Vector2, walls: Array, grid: Dictionary = {},
		board_in: float = 48.0, opts: Dictionary = {}) -> Array:
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
			if (opts.get("avoid_cells", {}) as Dictionary).has(nb):
				continue   # a cell the route must go AROUND (difficult terrain — solo overlay p.57)
			if step_blocked(cc, _cell_center(nb), walls, opts):
				continue   # a wall / zone sits on this cell edge → not traversable
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


# === Unified pipeline entry (opts["radii"] path) ============================================

## Plan one unit move on the REAL-GAME path: a configuration-space Theta*/funnel route (walls inflated by
## the base radius via opts.clearance, terrain soft-costed), each model walking the taut route as true arc
## length, then ONE constraint solver that resolves base-separation, coherency, unit-spacing and terrain
## avoidance simultaneously (solve_formation). Replaces the legacy steer-fan + separate coherency/overlap
## passes on this path only; the sim's empty-opts path is untouched. Pure + deterministic.
static func _plan_unit_step_unified(model_pos: Array, delta: Vector2, walls: Array, grid: Dictionary,
		allow_contact: bool, board_in: float, trails: Array, opts: Dictionary) -> Array:
	var allowance := delta.length()
	var radii: Array = opts.get("radii", [])
	var targets: Array = []
	if not rigid_blocked(model_pos, delta, walls, opts):
		# The straight slide clears walls / zones / avoided cells → rigid targets. The solver below still
		# projects any model that would REST in forbidden terrain (RUINS/DANGEROUS are not routing-avoided)
		# back out — so a "clear" slide can never park a model inside impassable/dangerous terrain.
		for m in model_pos:
			targets.append((m as Vector2) + delta)
		_record_trail_pair(trails, model_pos, targets)
	else:
		# Plan a taut any-angle route for the unit anchor, then every model rides it at its slot offset.
		var anchor := _centroid(model_pos)
		var goal := anchor + delta
		var route := theta_star(anchor, goal, walls, grid, board_in, opts)
		var taut := string_pull(route, walls, grid, opts)
		if trails != null:
			trails.clear()
		for i in range(model_pos.size()):
			var offset := (model_pos[i] as Vector2) - anchor
			var leg := _walk_offset(model_pos[i], taut, offset, allowance, walls, grid, opts, board_in)
			targets.append((leg.back()) as Vector2)
			if trails != null:
				trails.append(leg)
	var solved := solve_formation(targets, radii, walls, opts, board_in, allow_contact)
	_append_trail_finals(trails, solved)
	return solved


# === Configuration-space visibility (research §1.6: obstacle ⊕ base-radius disc, planned as a POINT) =====

## Fine-grid cell centre (Vector2i -> inch point) at PLAN_CELL_IN resolution.
static func _cell_center_fine(cell: Vector2i) -> Vector2:
	return Vector2((float(cell.x) + 0.5) * PLAN_CELL_IN, (float(cell.y) + 0.5) * PLAN_CELL_IN)


## Terrain cost multiplier for routing at point `p` (research §1.3 soft cost): INF = hard block (Impassable
## or a caller-avoided cell — the go-around set), else a >1 multiplier for Dangerous/Difficult so the search
## routes AROUND them when cheaper yet may still enter. Uses the 3" typed grid + opts.avoid_cells.
static func _terrain_cost_at(p: Vector2, grid: Dictionary, opts: Dictionary) -> float:
	if grid.is_empty():
		return 1.0
	var cell := TerrainRules.cell_of(p, TerrainRules.CELL_IN)
	var t: int = int(grid.get(cell, TerrainRules.TerrainType.NONE))
	if TerrainRules.is_impassable(t):
		return INF
	if (opts.get("avoid_cells", {}) as Dictionary).has(cell):
		return INF
	if TerrainRules.is_dangerous(t):
		return DANGEROUS_COST_MULT
	if TerrainRules.is_difficult(t):
		return DIFFICULT_COST_MULT
	return 1.0


## True if the straight segment a→b is NOT traversable in configuration space: it shaves an inflated wall,
## crosses a no-go zone (step_blocked owns those, base-aware), or its interior touches a hard-blocked
## terrain cell. Endpoints are excluded from the terrain sampling (the search validates nodes on expansion),
## mirroring TerrainRules.has_line_of_sight — so a route may START in a hard cell and escape it.
static func _cspace_blocked(a: Vector2, b: Vector2, walls: Array, grid: Dictionary, opts: Dictionary) -> bool:
	if step_blocked(a, b, walls, opts):
		return true
	if grid.is_empty():
		return false
	var span := a.distance_to(b)
	var steps := maxi(1, int(ceil(span / (PLAN_CELL_IN * 0.5))))
	if steps < 2:
		return false
	for i in range(1, steps):
		if is_inf(_terrain_cost_at(a.lerp(b, float(i) / float(steps)), grid, opts)):
			return true
	return false


## World-frame canonical cell order (smaller x, then y) — the deterministic, reflection-covariant tie-break
## for the search frontier (research §4: never break ties on iteration order or rotation sign).
static func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


## World-frame canonical point order (smaller x, then y).
static func _world_before(a: Vector2, b: Vector2) -> bool:
	return a.x < b.x - EPS or (absf(a.x - b.x) <= EPS and a.y < b.y - EPS)


# === Theta* — any-angle path over the inflated obstacle set (research §1.3) ==================

## Any-angle shortest path from `start` to `goal` on the PLAN_CELL_IN grid, reusing the configuration-space
## LOS (_cspace_blocked) so a node may take its parent's parent as its own parent whenever the straight line
## is visible — yielding taut, natural legs without a polygon navmesh. Edge cost carries the terrain soft
## multiplier (route around Difficult/Dangerous). Deterministic (world-frame tie-break). Returns the polyline
## [start … goal] (straight [start, goal] when already visible or no route is found — the solver still fixes
## the end state). Bounded by the board so it always terminates.
static func theta_star(start: Vector2, goal: Vector2, walls: Array, grid: Dictionary,
		board_in: float, opts: Dictionary) -> Array:
	if not _cspace_blocked(start, goal, walls, grid, opts):
		return [start, goal]
	var start_c := TerrainRules.cell_of(start, PLAN_CELL_IN)
	var goal_c := TerrainRules.cell_of(goal, PLAN_CELL_IN)
	if start_c == goal_c:
		return [start, goal]
	var n := maxi(1, int(ceil(board_in / PLAN_CELL_IN)))
	var g := {start_c: 0.0}
	var parent := {start_c: start_c}
	var pos := {start_c: start}
	var open: Array = [start_c]
	var open_set := {start_c: true}
	var closed := {}
	var guard := n * n * 4
	while not open.is_empty() and guard > 0:
		guard -= 1
		var best_i := 0
		var best_f := INF
		for k in range(open.size()):
			var c: Vector2i = open[k]
			var f: float = float(g[c]) + (pos[c] as Vector2).distance_to(goal)
			if f < best_f - EPS or (absf(f - best_f) <= EPS and _cell_before(c, open[best_i])):
				best_f = f
				best_i = k
		var cur: Vector2i = open[best_i]
		if cur == goal_c:
			return _theta_reconstruct(parent, pos, cur)
		open.remove_at(best_i)
		open_set.erase(cur)
		closed[cur] = true
		var cur_pt: Vector2 = pos[cur]
		for d in THETA_DIAG:
			var nb: Vector2i = cur + d
			if nb.x < 0 or nb.x >= n or nb.y < 0 or nb.y >= n or closed.has(nb):
				continue
			var nb_pt := goal if nb == goal_c else _cell_center_fine(nb)
			if nb != goal_c and is_inf(_terrain_cost_at(nb_pt, grid, opts)):
				continue
			if step_blocked(cur_pt, nb_pt, walls, opts):
				continue
			# Any-angle: connect nb straight to cur's PARENT when that line is visible (taut), else to cur.
			var par: Vector2i = parent[cur]
			var use_par: bool = not _cspace_blocked(pos[par] as Vector2, nb_pt, walls, grid, opts)
			var from_node: Vector2i = par if use_par else cur
			var from_pt: Vector2 = pos[from_node]
			var mult := _terrain_cost_at(nb_pt, grid, opts)
			if is_inf(mult):
				mult = 1.0   # the goal cell itself may be terrain — cost its entry as plain ground
			var tentative: float = float(g[from_node]) + from_pt.distance_to(nb_pt) * mult
			if not g.has(nb) or tentative < float(g[nb]) - EPS:
				g[nb] = tentative
				parent[nb] = from_node
				pos[nb] = nb_pt
				if not open_set.has(nb):
					open.append(nb)
					open_set[nb] = true
	return [start, goal]


## Walk the Theta* parent chain back to the start; return the world points [start … goal].
static func _theta_reconstruct(parent: Dictionary, pos: Dictionary, goal_cell: Vector2i) -> Array:
	var nodes: Array = [goal_cell]
	var cur := goal_cell
	while parent.has(cur) and parent[cur] != cur:
		cur = parent[cur]
		nodes.append(cur)
	nodes.reverse()
	var out: Array = []
	for node in nodes:
		out.append(pos[node])
	return out


# === Funnel / string-pull (research §1.2: pull the corridor taut) ===========================

## Greedy string-pull: from each anchor, advance to the FARTHEST later point still visible in a straight
## configuration-space line, dropping the vertices between — the point-path equivalent of the funnel, so the
## already-any-angle Theta* legs collapse to their minimal taut form. Pure; returns a NEW array.
static func string_pull(path: Array, walls: Array, grid: Dictionary, opts: Dictionary) -> Array:
	if path.size() <= 2:
		return path.duplicate()
	var out: Array = [path[0]]
	var anchor := 0
	while anchor < path.size() - 1:
		var farthest := anchor + 1
		for j in range(anchor + 2, path.size()):
			if _cspace_blocked(path[anchor] as Vector2, path[j] as Vector2, walls, grid, opts):
				break
			farthest = j
		out.append(path[farthest])
		anchor = farthest
	return out


## Walk one model along the anchor's taut route translated by its slot `offset`, spending `allowance` as TRUE
## arc length (research §3.3), stopping cleanly at the first leg a wall/zone/hard-cell blocks (the offset can
## shift a leg into an obstacle the anchor cleared) so a boxed model never stalls the unit. Returns the model
## polyline [start … end]; the last point is its planned target.
static func _walk_offset(start_pt: Vector2, taut: Array, offset: Vector2, allowance: float,
		walls: Array, grid: Dictionary, opts: Dictionary, board_in: float) -> Array:
	if taut.size() <= 1:
		return [start_pt]
	var out: Array = [start_pt]
	var spent := 0.0
	for i in range(1, taut.size()):
		var a: Vector2 = out.back()
		var b: Vector2 = (taut[i] as Vector2) + offset
		b = Vector2(clampf(b.x, 0.0, board_in), clampf(b.y, 0.0, board_in))
		var leg := a.distance_to(b)
		if leg < EPS:
			continue
		if _cspace_blocked(a, b, walls, grid, opts):
			# The offset shifted this leg into an obstacle the anchor cleared — advance to the FURTHEST clear
			# point on the leg and stop cleanly (never stall the whole unit). For a charge this walks the model
			# right up to the target's body-zone edge, i.e. base contact (GF/AoF v3.5.1 p.8).
			var stop := _furthest_clear(a, b, walls, grid, opts)
			var slen := a.distance_to(stop)
			if slen > EPS:
				if spent + slen <= allowance + EPS:
					out.append(stop)
				else:
					var f := (allowance - spent) / slen
					if f > EPS:
						out.append(a.lerp(stop, f))
			break
		if spent + leg <= allowance + EPS:
			out.append(b)
			spent += leg
		else:
			var frac := (allowance - spent) / leg
			if frac > EPS:
				out.append(a.lerp(b, frac))
			break
	return out


## Furthest point on a→b reachable without crossing an obstacle (a assumed clear) — bisection on the
## configuration-space LOS, so the returned point sits just outside the blocking wall/zone/terrain boundary.
static func _furthest_clear(a: Vector2, b: Vector2, walls: Array, grid: Dictionary, opts: Dictionary) -> Vector2:
	if not _cspace_blocked(a, b, walls, grid, opts):
		return b
	var lo := 0.0
	var hi := 1.0
	for _i in range(COHERENCY_BISECT_STEPS):
		var mid := (lo + hi) * 0.5
		if _cspace_blocked(a, a.lerp(b, mid), walls, grid, opts):
			hi = mid
		else:
			lo = mid
	return a.lerp(b, lo)


# === Unified constraint solver (research §3.3 / §1.7: project ALL constraints together) =====

## Board clamp helper (shared by every projection).
static func _board_clamp(p: Vector2, board_in: float) -> Vector2:
	return Vector2(clampf(p.x, 0.0, board_in), clampf(p.y, 0.0, board_in))


## Wall + no-go-zone check for a projection step p→c (hard resting constraints). Unlike step_blocked this
## does NOT consult avoid_cells: a model may legally REST in Difficult (soft-routed, not a violation), so the
## solver must be free to place it there when escaping a harder constraint — only walls (base-inflated) and
## unit-spacing zones are inviolable at rest. Terrain the model may not rest in is handled separately by the
## forbid-cell projection.
static func _wall_zone_blocked(p: Vector2, c: Vector2, walls: Array, opts: Dictionary) -> bool:
	var clearance: float = float(opts.get("clearance", 0.0))
	if clearance > 0.0:
		for w in walls:
			if _wall_blocks(p, c, _wall_a(w), _wall_b(w), clearance):
				return true
	elif path_crosses_wall(p, c, walls):
		return true
	for z in opts.get("zones", []):
		var zd := z as Dictionary
		if _zone_blocks(p, c, zd.get("c", Vector2.ZERO), float(zd.get("r", 0.0))):
			return true
	return false


## THE UNIFIED SOLVER. Place the unit's models to satisfy ALL formation constraints TOGETHER — no two bases
## overlap (GF/AoF v3.5.1 p.7), unit coherency (1"/9" chain, p.7), ≥1" from every other unit (p.7 no-go
## zones, charge target exempted body-only by the caller), and no model resting in forbidden terrain
## (Impassable/Dangerous — self-play audit) — via iterative projection instead of the competing sequential
## passes that traded one constraint for another (nightloop evidence). Each sweep projects every constraint
## once; the least-violating config seen is kept, so the result is never worse than the desired formation and
## converges to a jointly-legal placement (or the closest legal one). Charges skip terrain + coherency (they
## must reach base contact with the target — p.7). Pure + deterministic; returns a NEW Array[Vector2].
static func solve_formation(desired: Array, radii: Array, walls: Array,
		opts: Dictionary, board_in: float, allow_contact: bool) -> Array:
	var out := desired.duplicate()
	if out.is_empty():
		return out
	var forbid: Dictionary = {} if allow_contact else opts.get("forbid_cells", {})
	var zones: Array = opts.get("zones", [])
	var best := out.duplicate()
	var best_score := _formation_score(out, radii, forbid, zones)
	if best_score <= EPS:
		return out
	for _pass in range(SOLVE_PASSES):
		_project_out_of_zones(out, zones, walls, opts, board_in)
		_project_separate(out, radii, walls, opts, board_in)
		_project_out_of_terrain(out, forbid, walls, opts, board_in)
		if not allow_contact:
			_project_coherency(out, radii, walls, opts, board_in)
		var s := _formation_score(out, radii, forbid, zones)
		if s < best_score - EPS:
			best_score = s
			best = out.duplicate()
		if best_score <= EPS:
			break
	return best


## Weighted violation score for the least-violating fallback: a model stuck in terrain outweighs a broken
## chain, which outweighs an overlap, which outweighs a spacing dip — so a config the solver cannot make
## perfect sheds the WORST class first (exactly the trade the nightloop gate rejected). Zero = fully legal.
static func _formation_score(out: Array, radii: Array, forbid: Dictionary, zones: Array) -> float:
	var score := 0.0
	if not forbid.is_empty():
		for p in out:
			if forbid.has(TerrainRules.cell_of(p as Vector2, PLAN_CELL_IN)):
				score += W_TERRAIN
	score += _coherency_penalty(out, radii) * W_COHERENCY
	if radii.size() == out.size():
		for i in range(out.size()):
			for j in range(i + 1, out.size()):
				var overlap: float = float(radii[i]) + float(radii[j]) - (out[i] as Vector2).distance_to(out[j])
				if overlap > EPS:
					score += overlap * W_OVERLAP
	for z in zones:
		var zd := z as Dictionary
		var c: Vector2 = zd.get("c", Vector2.ZERO)
		var r: float = float(zd.get("r", 0.0))
		for p in out:
			var pen: float = r - (p as Vector2).distance_to(c)
			if pen > EPS:
				score += pen * W_ZONE
	return score


# --- Radii-aware coherency (solver only) -----------------------------------------------------
# The shared is_coherent / _components / _spread above fold a NOMINAL base contact (BASE_CONTACT_IN = 2")
# into point space for the sim (which has no per-model radii). The solver DOES have the real radii, so it
# uses CoherencyChecker's EXACT edge-to-edge measure instead: two models link when centre_gap - r_i - r_j
# <= 1" (COHERENCY_IN), and the unit over-spreads when the widest such edge gap > 9" (MAX_CHAIN_IN). This
# matches the self-play audit's coherency check for real 25-60 mm bases (the point-space 3"/11" thresholds
# were ~1" too loose for small bases, leaving chains the audit still flags broken).

## Edge-to-edge coherency link between two bases (CoherencyChecker._are_linked, point form).
static func _linked_r(a: Vector2, b: Vector2, ra: float, rb: float) -> bool:
	return a.distance_to(b) <= ra + rb + COHERENCY_IN + EPS


## Connected components of the radii-aware 1"-link graph (indices into `out`).
static func _components_r(out: Array, radii: Array) -> Array:
	var n := out.size()
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
				if _linked_r(out[cur], out[other], float(radii[cur]), float(radii[other])):
					visited[other] = true
					queue.append(other)
					comp.append(other)
		comps.append(comp)
	return comps


## Widest edge-to-edge gap between any two models (the unit's spread, CoherencyChecker._get_max_spread_pair).
static func _max_edge_spread_r(out: Array, radii: Array) -> float:
	var worst := 0.0
	for i in range(out.size()):
		for j in range(i + 1, out.size()):
			var edge: float = (out[i] as Vector2).distance_to(out[j]) - float(radii[i]) - float(radii[j])
			worst = maxf(worst, edge)
	return worst


## Graded coherency penalty (models outside the largest link-component + any 9" edge over-spread) — a
## gradient for the least-violating fallback. Radii-aware when radii align; else the point-space fallback.
static func _coherency_penalty(out: Array, radii: Array = []) -> float:
	if out.size() <= 1:
		return 0.0
	var use_r: bool = radii.size() == out.size()
	var pen := 0.0
	var comps := _components_r(out, radii) if use_r else _components(out)
	if comps.size() > 1:
		pen += float(out.size() - _largest(comps).size())
	var over: float = (_max_edge_spread_r(out, radii) - MAX_CHAIN_IN) if use_r else (_spread(out) - SPREAD_IN)
	if over > 0.0:
		pen += over
	return pen


## Project each model radially out of any no-go zone it sits inside (to the zone edge), wall/zone-checked. On
## a charge the target's body-only zone pushes the model back to base contact — the legal charge end.
static func _project_out_of_zones(out: Array, zones: Array, walls: Array, opts: Dictionary, board_in: float) -> void:
	if zones.is_empty():
		return
	for i in range(out.size()):
		var p: Vector2 = out[i]
		for z in zones:
			var zd := z as Dictionary
			var c: Vector2 = zd.get("c", Vector2.ZERO)
			var r: float = float(zd.get("r", 0.0))
			var d := p.distance_to(c)
			if d >= r - EPS:
				continue
			var dir := p - c
			dir = dir.normalized() if dir.length() > EPS else Vector2(1.0, 0.0)
			var cand := _board_clamp(c + dir * (r + EPS), board_in)
			if not _wall_zone_blocked(p, cand, walls, opts):
				p = cand
		out[i] = p


## Push overlapping own-base pairs apart along their centre line (split evenly), wall/zone-checked — one
## Gauss-Seidel sweep of the p.7 "may never move through other models … friendly or enemy" separation.
static func _project_separate(out: Array, radii: Array, walls: Array, opts: Dictionary, board_in: float) -> void:
	var n := out.size()
	if n <= 1 or radii.size() != n:
		return
	for i in range(n):
		for j in range(i + 1, n):
			var pi: Vector2 = out[i]
			var pj: Vector2 = out[j]
			var min_gap: float = float(radii[i]) + float(radii[j])
			var d := pi.distance_to(pj)
			if d >= min_gap - EPS:
				continue
			var dir := pj - pi
			dir = dir.normalized() if dir.length() > EPS else Vector2(1.0, 0.0)
			var push := (min_gap - d) * 0.5 + EPS
			var ci := _board_clamp(pi - dir * push, board_in)
			var cj := _board_clamp(pj + dir * push, board_in)
			if not _wall_zone_blocked(pi, ci, walls, opts):
				out[i] = ci
			if not _wall_zone_blocked(pj, cj, walls, opts):
				out[j] = cj


## Restore coherency (one sweep, radii-aware, wall/zone-checked): pull every model outside the largest
## link-component toward its NEAREST in-component neighbour (the exact pair CoherencyChecker measures), and
## pull the model furthest from the centroid inward when the unit over-spreads. Interleaved with the other
## projections each pass so an overlap push can no longer permanently undo it (the nightloop trade).
static func _project_coherency(out: Array, radii: Array, walls: Array, opts: Dictionary, board_in: float) -> void:
	var n := out.size()
	if n <= 1 or radii.size() != n:
		return
	var comps := _components_r(out, radii)
	if comps.size() > 1:
		var main := _largest(comps)
		var in_main := {}
		for idx in main:
			in_main[idx] = true
		for i in range(n):
			if in_main.has(i):
				continue
			var nearest := -1
			var nd := INF
			for m in main:
				var d: float = (out[i] as Vector2).distance_to(out[m])
				if d < nd:
					nd = d
					nearest = m
			if nearest < 0:
				continue
			var to_n := (out[nearest] as Vector2) - (out[i] as Vector2)
			var dn := to_n.length()
			if dn < EPS:
				continue
			var cand := _board_clamp((out[i] as Vector2) + to_n / dn * minf(COH_PULL_IN, dn), board_in)
			if not _wall_zone_blocked(out[i], cand, walls, opts):
				out[i] = cand
	if _max_edge_spread_r(out, radii) > MAX_CHAIN_IN + EPS:
		var c := _centroid(out)
		var far := -1
		var fd := -1.0
		for i in range(n):
			var d: float = (out[i] as Vector2).distance_to(c)
			if d > fd:
				fd = d
				far = i
		if far >= 0:
			var to_c := c - (out[far] as Vector2)
			var d := to_c.length()
			if d >= EPS:
				var cand := _board_clamp((out[far] as Vector2) + to_c / d * minf(COH_PULL_IN, d), board_in)
				if not _wall_zone_blocked(out[far], cand, walls, opts):
					out[far] = cand


## Project each model resting in a forbidden-terrain cell out to the nearest clear point (16 compass
## directions × 0.5" rings), wall/zone-checked and never into another forbidden cell. A boxed model is left
## in place (the least-violating fallback keeps the config). Deterministic: nearest ring first, world-frame
## tie-break within a ring.
static func _project_out_of_terrain(out: Array, forbid: Dictionary, walls: Array, opts: Dictionary, board_in: float) -> void:
	if forbid.is_empty():
		return
	for i in range(out.size()):
		var p: Vector2 = out[i]
		if not forbid.has(TerrainRules.cell_of(p, PLAN_CELL_IN)):
			continue
		out[i] = _nearest_clear_of_terrain(p, forbid, walls, opts, board_in)


static func _nearest_clear_of_terrain(p: Vector2, forbid: Dictionary, walls: Array, opts: Dictionary, board_in: float) -> Vector2:
	var dist := TERRAIN_PUSH_STEP_IN
	while dist <= TERRAIN_PUSH_MAX_IN + EPS:
		var found := false
		var best_c := p
		for k in range(RADIAL_DIRS):
			var ang := TAU * float(k) / float(RADIAL_DIRS)
			var c := _board_clamp(p + Vector2(cos(ang), sin(ang)) * dist, board_in)
			if forbid.has(TerrainRules.cell_of(c, PLAN_CELL_IN)):
				continue
			if _wall_zone_blocked(p, c, walls, opts):
				continue
			if not found or _world_before(c, best_c):
				best_c = c
				found = true
		if found:
			return best_c
		dist += TERRAIN_PUSH_STEP_IN
	return p
