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
const GATHER_PASSES := 16
const UNTANGLE_PASSES := 4                   # endpoint 2-opt sweeps of the flow result (bug 12b X-fan untangle)                    # a fully-parked model may need to travel further than a coherency nudge
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
# Headless-sweep fast planner (set ONLY by the arena/batch driver — the shipped game leaves it false, so
# its any-angle search is byte-identical). When on, each per-model theta_star is bounded: the search stops
# after FAST_PLANNER_GUARD cell-expansions and returns the closest-to-goal node reached so far (a sensible
# "head that way" route), instead of exhaustively flooding the whole reachable free region (~1000 cells on a
# crowded 2000pt board). Symmetric + deterministic, so both AIs approximate equally in a rating sweep.
static var fast_planner: bool = false
const FAST_PLANNER_GUARD := 320
## The active per-search expansion cap when fast_planner is on. The arena sweep keeps the tight 320 (speed +
## byte-fair symmetry); the INTERACTIVE game raises it (main.gd) so the bounded search still explores routes
## AROUND obstacles/Dangerous terrain instead of reach_closest returning a straight-through route (field
## report: a unit walked into Dangerous terrain toward its goal instead of routing around it).
static var fast_planner_guard: int = FAST_PLANNER_GUARD
const DIFFICULT_COST_MULT := 2.0            # Theta* soft cost: route AROUND Difficult when cheaper (research §1.3/3.3)
const DANGEROUS_COST_MULT := 6.0            # Dangerous DEALS DAMAGE — avoid it hard (route around unless the detour is >6x)
const THETA_DIAG := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]   # 8-connected (any-angle)
const SOLVE_PASSES := 24                     # iterative-projection sweeps (compact AI units converge well within this)
## Shaved off an OWN-model body zone (radii sum) in the sequential flow so bases at EXACT contact can slide
## along each other (round 7, finding 2): the deploy grid packs to edge ≈ 0, and an un-shaved zone made every
## tangent step float-marginal — the lead model of a packed squad stalled at its start and anchored the unit.
## Well under the overlap the solver/final gate resolves back to contact, so it never leaves real overlap.
const CONTACT_SLIDE_EPS_IN := 0.05
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
	# Fine C-space set (base-radius-inflated, 1" cells): the base EDGE must clear avoided terrain,
	# not just the path centre (maintainer 2026-07-22). Same escape semantics as the coarse set.
	var fine: Dictionary = opts.get("avoid_fine", {})
	if not fine.is_empty():
		if fine.has(TerrainRules.cell_of(c, PLAN_CELL_IN)) and not fine.has(TerrainRules.cell_of(p, PLAN_CELL_IN)):
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
		var fine: Dictionary = opts.get("avoid_fine", {})
		if not fine.is_empty() and not fine.has(TerrainRules.cell_of(a, PLAN_CELL_IN)):
			var fsteps := maxi(1, int(ceil(delta.length() / (PLAN_CELL_IN * 0.5))))
			for s in range(1, fsteps):
				if fine.has(TerrainRules.cell_of(a.lerp(b, float(s) / float(fsteps)), PLAN_CELL_IN)):
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

## Plan one unit move on the REAL-GAME path. PRIMARY placement is the SEQUENTIAL PER-MODEL FLOW (field-test
## round 6, finding 7): the models file to their slots one at a time in nearest-to-destination order, each
## planning its own taut configuration-space Theta*/funnel route while treating the other models as body
## obstacles, so a choke the rigid formation slide would jam is threaded model-by-model. solve_formation then
## runs as the final SAFETY NET (base-separation, coherency, unit-spacing and terrain-avoidance projected
## together). Replaces the former rigid-slot slide on this path only; the sim's empty-opts path is untouched.
## Pure + deterministic. The flow ORDER is written back into opts["flow_order"] for the caller's step-by-step
## glide presentation.
static func _plan_unit_step_unified(model_pos: Array, delta: Vector2, walls: Array, grid: Dictionary,
		allow_contact: bool, board_in: float, trails: Array, opts: Dictionary) -> Array:
	var radii: Array = opts.get("radii", [])
	var order_out: Array = []
	# PRIMARY: sequential per-model flow — each model files to its slot in nearest-to-destination order,
	# treating the already-placed + not-yet-moved models as body obstacles, coherency kept progressively.
	var flowed := plan_sequential_flow(model_pos, delta, radii, walls, grid, opts, board_in, allow_contact,
		trails, order_out)
	opts["flow_order"] = order_out   # the caller replays the glide in this order (finding 7 presentation)
	# SAFETY NET: the unified constraint solver clears any residual overlap / broken chain / terrain rest / zone
	# dip the flow's least-violating pull could not (starting from the flow's already-mostly-legal placement, so
	# a fully-legal flow is returned unchanged — best_score == 0 short-circuits).
	var solved := solve_formation(flowed, radii, walls, opts, board_in, allow_contact)
	_append_trail_finals(trails, solved)
	return solved


# === Sequential per-model flow (field-test round 6, finding 7 — the maintainer's design) =====

## Order the unit's models by distance to the DESTINATION (nearest first; ties by stable index) and move them
## ONE AT A TIME. Each model plans its OWN taut Theta*/funnel route (configuration space, base-radius
## clearance) to its formation slot, treating the already-PLACED models (at their final spots) and the
## not-yet-moved models (at their current spots) as BODY obstacles (base contact allowed, no 1" buffer — same
## unit), so the lead models vacate forward and the rest FLOW after them through a choke the rigid formation
## slide would jam. Coherency is kept PROGRESSIVELY: each model ends within a 1" link of the already-placed
## set (or as close as a clear pull allows — GF/AoF v3.5.1 p.7). A model whose OWN route stalls far short of
## its slot while others still wait is DEFERRED to the back of the queue once (round 7, finding 2): placing a
## stalled model FIRST anchored the whole unit — every later model was coherency-pulled back to it and a
## 10-model advance achieved half an inch; deferred last, the stall pulls TOWARD the advanced group instead.
## `trails` (sized n, per MODEL index) receives each model's route; the flow ORDER is appended to `order_out`
## Bug-31 (Säulen-Formation): per-model CONTACT SLOTS along the target's near face, so a
## charging unit fans into a battle line instead of queuing at the single centre goal.
## Pure: mpos/radii = the movers (planner inches), tgt_bases = [[centre: Vector2, r_in], ...].
## Per target base up to 5 candidate points on its contact circle (facing the chargers ± up
## to ~80°); movers pick nearest-first, each chosen slot repels later picks by base spacing.
## Returns one slot per mover (Vector2), falling back to the nearest base's facing point.
static func charge_contact_slots(mpos: Array, radii: Array, tgt_bases: Array) -> Array:
	var out: Array = []
	if tgt_bases.is_empty():
		return out
	var ucentre := Vector2.ZERO
	for p in mpos:
		ucentre += p as Vector2
	ucentre /= maxf(1.0, float(mpos.size()))
	var order := range(mpos.size())
	order.sort_custom(func(a, b) -> bool:
		return _nearest_base_dist(mpos[a], tgt_bases) < _nearest_base_dist(mpos[b], tgt_bases))
	var taken: Array = []
	for idx in order:
		var ri := float(radii[idx]) if idx < radii.size() else 0.5
		var best := Vector2.INF
		var best_d := INF
		for tb in tgt_bases:
			var c: Vector2 = tb[0]
			var tr := float(tb[1])
			var face := (ucentre - c).normalized() if (ucentre - c).length() > 0.001 else Vector2.RIGHT
			var base_ang := face.angle()
			# Single-base targets (vehicles/monsters) may be SURROUNDED: extend the fan past the
			# front face so a horde can ring the base instead of losing contacts to slot scarcity.
			var fan: Array = [0.0, 0.7, -0.7, 1.4, -1.4]
			if tgt_bases.size() * 5 < mpos.size() or tgt_bases.size() == 1:
				fan = [0.0, 0.7, -0.7, 1.4, -1.4, 2.1, -2.1, 2.8, -2.8, PI]
			for k in fan:
				var ang: float = base_ang + k
				var slot := c + Vector2(cos(ang), sin(ang)) * (tr + ri)
				var free := true
				for t in taken:
					var td := t as Dictionary
					if slot.distance_to(td["p"] as Vector2) < (ri + float(td["r"])) * 0.95:
						free = false
						break
				if not free:
					continue
				var d := (mpos[idx] as Vector2).distance_to(slot)
				if d < best_d:
					best_d = d
					best = slot
		if best == Vector2.INF:   # everything taken — fall back to the nearest base's facing point
			var c0: Vector2 = tgt_bases[0][0]
			var tr0 := float(tgt_bases[0][1])
			var face0 := ((mpos[idx] as Vector2) - c0).normalized()
			best = c0 + face0 * (tr0 + ri)
		taken.append({"p": best, "r": ri})
		out.append([idx, best])
	out.sort_custom(func(a, b) -> bool: return int(a[0]) < int(b[0]))
	var slots: Array = []
	for e in out:
		slots.append(e[1])
	return slots


static func _nearest_base_dist(p, tgt_bases: Array) -> float:
	var best := INF
	for tb in tgt_bases:
		best = minf(best, (p as Vector2).distance_to(tb[0] as Vector2))
	return best


## for the caller's sequential glide. A Charge (allow_contact) skips the progressive-coherency pull (it must
## reach base contact). Pure + deterministic; returns a NEW Array[Vector2]. The caller runs solve_formation
## on the result as the final safety net.
static func plan_sequential_flow(model_pos: Array, delta: Vector2, radii: Array, walls: Array,
		grid: Dictionary, opts: Dictionary, board_in: float, allow_contact: bool,
		trails: Array = [], order_out: Array = []) -> Array:
	var n := model_pos.size()
	var result := model_pos.duplicate()
	if trails != null:
		trails.clear()
		for i in range(n):
			trails.append([model_pos[i]])
	if n == 0:
		return result
	# A Charge routes its nearest models to base contact, and the ONLY path to the target may DETOUR around
	# obstacles / other units' zones / a large enemy base — a bend whose arc length exceeds the straight
	# gap. The straight-line delta length was the sole arc budget, so any detour starved the charge and it
	# fell short by the bend amount (field-test: 1–5" short whenever the lane wasn't dead straight). For a
	# charge the caller grants the FULL charge band via opts.charge_allowance so the route can bend around
	# and still close to contact; the target's body-only zone clamps the nearest models AT contact, and the
	# per-model slot (delta, aimed at contact) never lets a non-detouring model overrun. Non-charge moves
	# omit the key ⇒ the exact old delta-length allowance (byte-identical).
	var allowance := float(opts.get("charge_allowance", delta.length()))
	var goal_anchor := _centroid(model_pos) + delta
	# Deterministic flow order: nearest to the destination first, ties broken by stable model index (total
	# order → the same sequence regardless of sort stability; research §4 canonicity).
	var order: Array = []
	for i in range(n):
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var da: float = (model_pos[a] as Vector2).distance_squared_to(goal_anchor)
		var db: float = (model_pos[b] as Vector2).distance_squared_to(goal_anchor)
		if absf(da - db) > EPS:
			return da < db
		return a < b)
	var base_clearance: float = float(opts.get("clearance", 0.0))
	var base_zones: Array = opts.get("zones", [])
	# PERF (sweep-only, gated on fast_planner): cull spacing zones to those a reach-bounded route is likely to
	# touch. theta_star's step_blocked scans EVERY zone per grid edge, so at large games (~90 enemy zones) the
	# per-model search cost is ~O(cells × zones). A zone farther than this unit's move budget (+ its own radius
	# + the moving base's clearance) from every model start is almost never on a legal route. NOTE: this is a
	# near-approximation, NOT byte-identical — an empirical decisions.json diff showed it shifts a few
	# marginal routes (a bend that just grazes a culled zone). Acceptable in a rating sweep (symmetric +
	# deterministic, washes out over many games); the shipped game leaves fast_planner false and never culls.
	if fast_planner and base_zones.size() > 8:
		var cull_reach: float = maxf(delta.length(), float(opts.get("charge_allowance", 0.0))) + base_clearance + PLAN_CELL_IN
		var kept_zones: Array = []
		for z in base_zones:
			var zd := z as Dictionary
			var zc: Vector2 = zd.get("c", Vector2.ZERO)
			var keep_r2: float = pow(cull_reach + float(zd.get("r", 0.0)), 2.0)
			for m in model_pos:
				if (m as Vector2).distance_squared_to(zc) <= keep_r2:
					kept_zones.append(z)
					break
		base_zones = kept_zones
	var avoid_cells: Dictionary = opts.get("avoid_cells", {})
	var have_r: bool = radii.size() == n
	var placed: Array = []   # model indices already settled at their final spots
	var deferred := {}       # indices already sent to the back of the queue once (no re-defer → terminates)
	var queue: Array = order.duplicate()
	while not queue.is_empty():
		var idx: int = queue.pop_front()
		# Body zones for EVERY other own model (placed → final spot, else current spot): base contact allowed
		# (radii sum MINUS a hair — see CONTACT_SLIDE_EPS_IN), so this model files up to and slides ALONG its
		# neighbours but never moves THROUGH one (GF/AoF v3.5.1 p.7). The epsilon matters (finding 2): the
		# deploy grid packs bases to EXACT contact, and a zone of exactly radii-sum made the tangent forward
		# step float-marginal — every outgoing edge of a packed model read as blocked, the lead model stalled
		# at its start, and the progressive coherency then collapsed the whole unit onto it. Other units keep
		# their full 1" buffer zones (base_zones), where the epsilon is irrelevant.
		var zones: Array = base_zones.duplicate()
		if have_r:
			for j in range(n):
				if j == idx:
					continue
				var jc: Vector2 = result[j] if placed.has(j) else model_pos[j]
				zones.append({"c": jc, "r": maxf(0.0, float(radii[j]) + float(radii[idx]) - CONTACT_SLIDE_EPS_IN)})
		var oi := {"clearance": base_clearance, "avoid_cells": avoid_cells, "zones": zones}
		var slot: Vector2 = (model_pos[idx] as Vector2) + delta
		# CHARGE body-goal (charge-reach fix): aim the charging model at the ENEMY BODY (opts.charge_goal, the
		# target centre) rather than the fixed along-the-line slot. If the direct line is blocked (an obstacle
		# or another unit's zone straddling the approach), Theta*'s reach_closest bends the route around to the
		# target's nearest OPEN face instead of stalling; the appended body point then lets _walk_offset walk
		# right up to the target's body-only zone — base contact. The full charge band (allowance) funds the
		# detour arc. Straight, clear charges are unchanged (the body point is co-linear with the slot).
		if allow_contact and opts.has("charge_goal"):
			# Bug-31: per-model contact SLOT (fans the unit into a line) instead of the shared
			# centre; the target's own bases become hard no-through zones whose boundary IS the
			# legal kiss — reaching contact stays possible, cutting THROUGH the unit does not.
			var body: Vector2 = opts["charge_goal"]
			var cslots: Array = opts.get("charge_slots", [])
			var goal_pt: Vector2 = body
			if idx < cslots.size() and cslots[idx] is Vector2:
				goal_pt = cslots[idx]
			var czones: Array = (zones as Array).duplicate()
			for tb in (opts.get("charge_tgt_bases", []) as Array):
				czones.append({"c": tb[0], "r": maxf(0.0, float(tb[1]) + float(radii[idx]) - CONTACT_SLIDE_EPS_IN)})
			var coi := oi.duplicate()
			coi["reach_closest"] = true
			coi["zones"] = czones
			var woi := oi.duplicate()
			woi["zones"] = czones
			var croute := theta_star(model_pos[idx], goal_pt, walls, grid, board_in, coi)
			var ctaut := string_pull(croute, walls, grid, coi)
			if ctaut.is_empty() or (ctaut.back() as Vector2).distance_to(goal_pt) > EPS:
				ctaut.append(goal_pt)
			var cleg := _walk_offset(model_pos[idx], ctaut, Vector2.ZERO, allowance, walls, grid, woi, board_in)
			result[idx] = cleg.back()
			placed.append(idx)
			if trails != null and idx < trails.size():
				trails[idx] = cleg
			order_out.append(idx)
			continue
		var route := theta_star(model_pos[idx], slot, walls, grid, board_in, oi)
		var taut := string_pull(route, walls, grid, oi)
		var leg := _walk_offset(model_pos[idx], taut, Vector2.ZERO, allowance, walls, grid, oi, board_in)
		var final_pt: Vector2 = leg.back()
		# Lead-stall deferral (finding 2): this model got badly stuck on its own route while other models
		# still wait — try it again LAST, when the vacated ground and the advanced placed set give it both a
		# clearer route and a FORWARD coherency pull. Each model defers at most once (deterministic, bounded).
		var intended: float = minf(allowance, (model_pos[idx] as Vector2).distance_to(slot))
		if not queue.is_empty() and not deferred.has(idx) and intended > STEP_IN \
				and (model_pos[idx] as Vector2).distance_to(final_pt) < intended * STUCK_FRACTION:
			deferred[idx] = true
			queue.push_back(idx)
			continue
		# Progressive coherency: link this model into the already-placed set (or as close as a clear pull
		# allows). A charge is exempt (it must reach base contact with the enemy).
		if not allow_contact and have_r and not placed.is_empty():
			var linked := _pull_into_placed(final_pt, idx, radii, placed, result, walls,
				base_clearance, base_zones, avoid_cells, board_in)
			if linked.distance_to(final_pt) > EPS:
				leg.append(linked)
				final_pt = linked
		result[idx] = final_pt
		placed.append(idx)
		if trails != null and idx < trails.size():
			trails[idx] = leg
		order_out.append(idx)
	# UNTANGLE (watch-loop bug 12b): choke detours + coherency pulls can leave endpoint pairs CROSSED —
	# model A at what was naturally B's spot and vice versa (the maintainer's X-fan; audit: up to 15 chord
	# crossings per activation). Swapping the two ENDPOINTS keeps the exact same position SET (formation,
	# overlap and coherency untouched) while shortening both chords — optimal Euclidean assignments never
	# cross. Same-radius pairs only, both new chords within the move allowance; each accepted swap
	# re-routes the two trails so the drawn corridors (and the dangerous/difficult accounting read off
	# them) stay truthful. Charges are exempt (contact endpoints are owned by the charge snap).
	var untangle_oi := {"clearance": base_clearance, "avoid_cells": opts.get("avoid_cells", {}), "zones": base_zones}
	if not allow_contact and n >= 2 and untangle_endpoints(model_pos, result, radii, allowance, walls, untangle_oi):
		var re_oi := untangle_oi
		for i in range(n):
			if trails != null and i < trails.size():
				var t_end: Vector2 = (trails[i] as Array).back() if not (trails[i] as Array).is_empty() else model_pos[i]
				if t_end.distance_to(result[i] as Vector2) > EPS:
					var rroute := theta_star(model_pos[i], result[i], walls, grid, board_in, re_oi)
					trails[i] = string_pull(rroute, walls, grid, re_oi)
	return result


## Endpoint 2-opt of the flow result (pure, unit-tested): swap endpoint pairs while a swap shortens the
## summed start→end chords, both models share a base radius, and both new chords stay within `allowance`
## (the per-model move budget — a swap must never grant an illegal move length). Deterministic pair order,
## bounded passes. Mutates `result`; returns whether anything swapped.
static func untangle_endpoints(model_pos: Array, result: Array, radii: Array, allowance: float,
		walls: Array = [], step_opts: Dictionary = {}) -> bool:
	var n := model_pos.size()
	var any := false
	for _pass in range(UNTANGLE_PASSES):
		var improved := false
		for i in range(n):
			for j in range(i + 1, n):
				if i < radii.size() and j < radii.size() and absf(float(radii[i]) - float(radii[j])) > 0.0005:
					continue
				var si: Vector2 = model_pos[i]
				var sj: Vector2 = model_pos[j]
				var ei: Vector2 = result[i]
				var ej: Vector2 = result[j]
				if si.distance_to(ej) > allowance + EPS or sj.distance_to(ei) > allowance + EPS:
					continue
				if si.distance_to(ej) + sj.distance_to(ei) + EPS < si.distance_to(ei) + sj.distance_to(ej):
					# WALL GATE (mirror-ladder audit: ONIs/Warriors corner cuts): a swap trades the two
					# route-true endpoints across a straight chord — near a ruin corner that chord can
					# tunnel where both original routes legally bent around. The caller's re-route can
					# fail there too (goal pocketed behind the corner ⇒ straight fallback), so wall
					# legality of BOTH new chords is the swap's acceptance condition, not an afterthought.
					if not walls.is_empty() and (step_blocked(si, ej, walls, step_opts)
							or step_blocked(sj, ei, walls, step_opts)):
						continue
					result[i] = ej
					result[j] = ei
					improved = true
					any = true
		if not improved:
			break
	return any


## Pull model `idx` (at `pos`) toward the NEAREST already-placed own model until their bases LINK (edge ≤ 1",
## CoherencyChecker) or a clear pull can bring it no closer — the progressive-coherency step of the sequential
## flow. Stepped in COH_PULL_IN increments, each checked against walls, OTHER units' zones and avoided cells
## (the neighbour's OWN body is deliberately NOT a zone here, so base contact is reachable). Returns the
## adjusted position (pos unchanged when already linked / no clear pull helps). Pure + deterministic.
static func _pull_into_placed(pos: Vector2, idx: int, radii: Array, placed: Array, result: Array,
		walls: Array, clearance: float, other_zones: Array, avoid_cells: Dictionary, board_in: float) -> Vector2:
	var nearest := -1
	var nd := INF
	for j in placed:
		var edge: float = pos.distance_to(result[j]) - float(radii[idx]) - float(radii[j])
		if edge < nd:
			nd = edge
			nearest = j
	if nearest < 0 or _linked_r(pos, result[nearest], float(radii[idx]), float(radii[nearest])):
		return pos
	var step_opts := {"clearance": clearance, "zones": other_zones, "avoid_cells": avoid_cells}
	var cur := pos
	for _p in range(GATHER_PASSES):
		if _linked_r(cur, result[nearest], float(radii[idx]), float(radii[nearest])):
			break
		var to_n := (result[nearest] as Vector2) - cur
		var d := to_n.length()
		if d < EPS:
			break
		var cand := _board_clamp(cur + to_n / d * minf(COH_PULL_IN, d), board_in)
		if step_blocked(cur, cand, walls, step_opts):
			break
		cur = cand
	return cur


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
	# Container wave: impassable boxes are EXACT wall segments now — pricing their quantised
	# cells INF made routes orbit a fattened phantom. Walls hard-block; cells price as ground.
	if (opts.get("avoid_cells", {}) as Dictionary).has(cell):
		return INF
	if (opts.get("avoid_fine", {}) as Dictionary).has(TerrainRules.cell_of(p, PLAN_CELL_IN)):
		return INF   # base-radius-inflated: within clearance of avoided terrain (edge-aware routing)
	if TerrainRules.is_dangerous(t):
		return DANGEROUS_COST_MULT
	if TerrainRules.is_difficult(t):
		return DIFFICULT_COST_MULT
	return 1.0


## Soft-cost PATH INTEGRAL of the straight segment a→b: sample midpoints every half plan-cell and sum
## sub-length × that cell's multiplier. The any-angle taut shortcut previously priced a whole parent→node
## segment at its ENDPOINT cell's multiplier only, so a line crossing Dangerous/Difficult terrain that ENDED
## on open ground cost plain distance — the route-around soft costs never bit on taut segments (field
## report: units cut straight through Dangerous ground; the DANGEROUS_COST_MULT bump alone was ineffective).
## INF samples price as plain ground here — hard blocking stays owned by _cspace_blocked / the entry check,
## and a goal cell inside terrain must remain enterable (mirrors the old endpoint-INF fallback).
static func _segment_cost(a: Vector2, b: Vector2, grid: Dictionary, opts: Dictionary) -> float:
	var span := a.distance_to(b)
	if grid.is_empty() or span <= EPS:
		return span
	var steps := maxi(1, int(ceil(span / (PLAN_CELL_IN * 0.5))))
	var sub := span / float(steps)
	var total := 0.0
	for i in range(steps):
		var m := _terrain_cost_at(a.lerp(b, (float(i) + 0.5) / float(steps)), grid, opts)
		total += sub * (1.0 if is_inf(m) else m)
	return total


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
	# Early-out only when the straight shot is hard-clear AND carries no soft-cost surcharge: a line that
	# merely crosses Dangerous/Difficult ground is not hard-blocked, so the search never ran and the soft
	# costs never bit — the true root cause of "the unit walked straight into Dangerous terrain" (the cost
	# bump alone was dead code on the direct path). The search may still pick the straight line if the
	# detour is dearer; this only makes the comparison actually happen.
	if not _cspace_blocked(start, goal, walls, grid, opts) \
			and _segment_cost(start, goal, grid, opts) <= start.distance_to(goal) + EPS:
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
	if fast_planner:
		guard = mini(guard, fast_planner_guard)
	# reach_closest (charge-reach fix): when the GOAL itself is unreachable (a charge aims at the enemy's
	# body, which sits inside its own no-go zone), return the path to the closest REACHABLE node instead of
	# the straight line — so the mover bends around obstacles to the target's nearest open face rather than
	# stalling at the first thing in the way. Off by default ⇒ every existing caller is byte-identical.
	var reach_closest: bool = bool(opts.get("reach_closest", false)) or fast_planner
	var best_reach: Vector2i = start_c
	var best_reach_d: float = start.distance_to(goal)
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
			# Any-angle with SOFT costs: price BOTH candidates — the taut parent shortcut and the grid step
			# via cur — with the path-integral _segment_cost, and take the cheaper (parent preferred on
			# ties, keeping open-ground paths taut). The old rule connected via the parent whenever the
			# line was merely hard-clear, so with soft-cost-only obstructions EVERY node collapsed to a
			# straight line from the start and a Dangerous-avoiding detour could never even form.
			var par: Vector2i = parent[cur]
			var from_node: Vector2i = cur
			var tentative: float = float(g[cur]) + _segment_cost(cur_pt, nb_pt, grid, opts)
			if not _cspace_blocked(pos[par] as Vector2, nb_pt, walls, grid, opts):
				var via_par: float = float(g[par]) + _segment_cost(pos[par] as Vector2, nb_pt, grid, opts)
				if via_par <= tentative + EPS:
					from_node = par
					tentative = via_par
			if not g.has(nb) or tentative < float(g[nb]) - EPS:
				g[nb] = tentative
				parent[nb] = from_node
				pos[nb] = nb_pt
				if reach_closest:
					var rd: float = (nb_pt as Vector2).distance_to(goal)
					if rd < best_reach_d - EPS:
						best_reach_d = rd
						best_reach = nb
				if not open_set.has(nb):
					open.append(nb)
					open_set[nb] = true
	if reach_closest and best_reach != start_c:
		# Guard-exhausted searches can return a NEAR-ZERO stub (Windows playtest bug 4: achieved 0.0" of a
		# 4" band — the visible twitching). When the straight line is hard-legal (soft-cost-only
		# obstruction), take whichever option promises the cheaper total — the stub prefix plus a straight
		# remainder, or the straight line paying the toll. Paralysis is worse than the toll; hard-blocked
		# goals (walls / charges into no-go zones) keep the stub as before.
		if not _cspace_blocked(start, goal, walls, grid, opts):
			var via_stub: float = float(g[best_reach]) + _segment_cost(pos[best_reach] as Vector2, goal, grid, opts)
			if _segment_cost(start, goal, grid, opts) <= via_stub + EPS:
				return [start, goal]
		return _theta_reconstruct(parent, pos, best_reach)
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
			# Soft costs: only shortcut when the straight line is no dearer than the legs it replaces —
			# otherwise the pull would drag a Dangerous-avoiding detour straight back through the field.
			if _segment_cost(path[anchor] as Vector2, path[j] as Vector2, grid, opts) \
					> _legs_cost(path, anchor, j, grid, opts) + EPS:
				continue
			farthest = j
		out.append(path[farthest])
		anchor = farthest
	return out


## Summed soft-cost of the existing polyline legs path[i0..i1] (see _segment_cost).
static func _legs_cost(path: Array, i0: int, i1: int, grid: Dictionary, opts: Dictionary) -> float:
	var total := 0.0
	for k in range(i0, i1):
		total += _segment_cost(path[k] as Vector2, path[k + 1] as Vector2, grid, opts)
	return total


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
