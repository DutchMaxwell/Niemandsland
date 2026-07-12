class_name AiDeployment
extends RefCounted
## Solo-AI M2 — OPR Solo & Co-Op v3.5.0 "AI Deployment" (goal 001 P2), the pure, seeded-RNG core:
## the AI's units are randomly split into 3 groups of equal size (as far as possible); the table is
## divided into 3 sections along the AI's deployment-zone edge; each group rolls a D3 for its section
## (re-rolling while ALL groups would share one); then one random unit at a time deploys in its section,
## as close as possible to the nearest objective and outside difficult/dangerous terrain (unless the
## unit has Strider or Flying). Scout units deploy after all others; Ambush units stay in reserve
## (arriving at the start of round 2). The caller supplies zone geometry, objectives and a terrain
## callback — no scene access here (headless-testable per the solo conventions).


## Randomly split `count` unit indices into 3 groups of equal size as far as possible.
## Deterministic under a fixed rng seed (Fisher-Yates with the provided rng).
static func split_into_groups(count: int, rng: RandomNumberGenerator) -> Array:
	var idx: Array = []
	for i in range(count):
		idx.append(i)
	_shuffle(idx, rng)
	var groups: Array = [[], [], []]
	for k in range(idx.size()):
		groups[k % 3].append(idx[k])
	return groups


## One D3 roll (section 1-3) per group; re-roll while ALL groups would deploy in the same section.
static func assign_sections(group_count: int, rng: RandomNumberGenerator) -> Array:
	if group_count <= 0:
		return []
	while true:
		var sections: Array = []
		for i in range(group_count):
			sections.append(rng.randi_range(1, 3))
		if group_count == 1:
			return sections
		var all_same := true
		for s in sections:
			if int(s) != int(sections[0]):
				all_same = false
				break
		if not all_same:
			return sections
	return []


## The rect of section 1-3: the AI zone split into 3 equal strips along its table-edge axis (x).
static func section_rect(zone: Rect2, section: int) -> Rect2:
	var w := zone.size.x / 3.0
	return Rect2(Vector2(zone.position.x + w * float(clampi(section, 1, 3) - 1), zone.position.y), Vector2(w, zone.size.y))


## Placement order: units deploy one at a time in RANDOM order, but Scout units always deploy LAST and
## Ambush units are excluded entirely (reserve, start of round 2). `units` = [{id, scout, ambush}].
static func placement_order(units: Array, rng: RandomNumberGenerator) -> Array:
	var normal: Array = []
	var scouts: Array = []
	for u in units:
		var d := u as Dictionary
		if bool(d.get("ambush", false)):
			continue
		if bool(d.get("scout", false)):
			scouts.append(d.get("id"))
		else:
			normal.append(d.get("id"))
	_shuffle(normal, rng)
	_shuffle(scouts, rng)
	return normal + scouts


## The free, terrain-legal spot inside `section` closest to the nearest objective (rule: "as close as
## possible to the nearest objective"). `occupied` = [{pos: Vector2, radius: float}] already-placed
## footprints; `blocked` = Callable(Vector2) -> bool for difficult/dangerous terrain (pass an invalid
## Callable for units with Strider/Flying, which ignore it). Returns Vector2.INF when nothing fits.
static func best_spot(section: Rect2, objectives: Array, occupied: Array, radius: float, blocked: Callable, step: float = 0.05, probe_radius: float = 0.0, footprint: Array = [], base_r: float = 0.0) -> Vector2:
	var best := Vector2.INF
	var best_score := INF
	var y := section.position.y + radius
	while y <= section.end.y - radius + 0.0001:
		var x := section.position.x + radius
		while x <= section.end.x - radius + 0.0001:
			var p := Vector2(x, y)
			if _spot_free(p, radius, occupied) and not _blocked_at(p, blocked, probe_radius, footprint, base_r):
				var score := _nearest_objective_distance(p, objectives, section)
				if score < best_score:
					best_score = score
					best = p
			x += step
		y += step
	return best


## Graceful last-resort spot for a terrain-choked table where NO fully terrain-legal footprint exists
## anywhere in `zone` (field-test finding 1: the unit must still deploy, but was dumped blindly at the
## section CENTRE — which sat inside a ruin/blocking terrain). Instead scan the zone and return the spot
## whose footprint has the FEWEST model-base sample points in blocking/dangerous terrain, tie-broken toward
## the nearest objective. So a unit lands on the CLEAREST available ground (usually zero blocked points —
## i.e. still fully legal — and only ever a wall/hazard cell when literally nothing better exists), never
## on top of a wall when clear ground is one cell over. Always returns a finite spot.
static func least_blocked_spot(zone: Rect2, objectives: Array, radius: float, blocked: Callable,
		step: float, base_r: float, footprint: Array = []) -> Vector2:
	var best := zone.get_center()
	var best_blocked := INF
	var best_score := INF
	var y := zone.position.y + radius
	while y <= zone.end.y - radius + 0.0001:
		var x := zone.position.x + radius
		while x <= zone.end.x - radius + 0.0001:
			var p := Vector2(x, y)
			var bc := _blocked_count(p, blocked, base_r, footprint)
			var score := _nearest_objective_distance(p, objectives, zone)
			if bc < best_blocked or (bc == best_blocked and score < best_score):
				best_blocked = bc
				best_score = score
				best = p
			x += step
		y += step
	return best


## How many of the footprint's model-base sample points (each model's centre + its 8 base-edge points at
## `base_r`, or the footprint-circle edges when no explicit grid) land in blocking/dangerous terrain. 0 = a
## fully terrain-legal spot. Shares the exact sample set with `_blocked_at` so "0 blocked" here == "not
## blocked" there.
static func _blocked_count(p: Vector2, blocked: Callable, base_r: float, footprint: Array) -> int:
	if not blocked.is_valid():
		return 0
	var n := 0
	var edges := _base_edge_offsets(base_r)
	if not footprint.is_empty():
		for off in footprint:
			for e in edges:
				if bool(blocked.call(p + (off as Vector2) + e)):
					n += 1
		return n
	for e in edges:
		if bool(blocked.call(p + e)):
			n += 1
	return n


## Terrain check over the unit's FOOTPRINT, not just its centre. When `footprint` (the model-local XZ
## offsets each model WILL occupy at this spot) is supplied, EVERY model's base — its centre plus its
## base-edge cardinal/diagonal points at `base_r` — is checked against blocking terrain, so no model in a
## spread formation can land in terrain between coarse samples (field-test finding 1). Otherwise it falls
## back to the footprint-circle sampling (8 edge points at `probe_radius`) for units without an explicit
## model grid (e.g. regiment trays).
static func _blocked_at(p: Vector2, blocked: Callable, probe_radius: float, footprint: Array = [], base_r: float = 0.0) -> bool:
	if not blocked.is_valid():
		return false
	if bool(blocked.call(p)):
		return true
	if not footprint.is_empty():
		var edges := _base_edge_offsets(base_r)
		for off in footprint:
			for e in edges:
				if bool(blocked.call(p + (off as Vector2) + e)):
					return true
		return false
	if probe_radius <= 0.0:
		return false
	# Sample the footprint's cardinal AND diagonal edge points (8): a centre-plus-cardinals check let a
	# unit's grid CORNER overlap blocking terrain between the cardinal samples (field-test finding 3).
	for off in _base_edge_offsets(probe_radius):
		if off == Vector2.ZERO:
			continue
		if bool(blocked.call(p + off)):
			return true
	return false


## The centre plus the eight base-edge sample points (cardinals + diagonals) at radius `r`. A zero radius
## collapses to the centre alone. Shared by the per-model footprint check and the circle fallback.
static func _base_edge_offsets(r: float) -> Array:
	if r <= 0.0:
		return [Vector2.ZERO]
	var diag := r * 0.70710678   # cos 45° — the corner offset at radius r
	return [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r),
		Vector2(diag, diag), Vector2(diag, -diag), Vector2(-diag, diag), Vector2(-diag, -diag)]


# === Private ===

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func _spot_free(p: Vector2, radius: float, occupied: Array) -> bool:
	for o in occupied:
		var od := o as Dictionary
		if p.distance_to(od.get("pos", Vector2.INF)) < radius + float(od.get("radius", 0.0)):
			return false
	return true


## Distance to the nearest objective; with no objectives on the table, aim for the section centre so
## the group still forms up coherently instead of degenerating to the rect origin.
static func _nearest_objective_distance(p: Vector2, objectives: Array, section: Rect2) -> float:
	if objectives.is_empty():
		return p.distance_to(section.get_center())
	var best := INF
	for obj in objectives:
		best = minf(best, p.distance_to(obj))
	return best
